// Package main provides a proxy that converts a stdio-based MCP server to streamable HTTP transport.
package main

import (
	"context"
	"encoding/json"
	"flag"
	"fmt"
	"log/slog"
	"net/http"
	"os"
	"os/exec"
	"sync"
	"time"

	"github.com/modelcontextprotocol/go-sdk/mcp"
)

type newMCPSessionFunc func(ctx context.Context) (*mcp.ClientSession, error)

type session struct {
	*mcp.ClientSession
	expireAt time.Time
}

func newSession(s *mcp.ClientSession) *session {
	return (&session{ClientSession: s}).Touch()
}

func (s *session) Touch() *session {
	s.expireAt = time.Now().Add(time.Hour)
	return s
}

func newHandler(newMCPSession newMCPSessionFunc) http.Handler {
	var sessions sync.Map
	cleanup := func() {
		now := time.Now()
		sessions.Range(func(key, value any) bool {
			if s := value.(*session); now.After(s.expireAt) {
				s.Close()
				sessions.Delete(key)
			}
			return true
		})
	}

	s := mcp.NewServer(&mcp.Implementation{
		Name:    "mcp-proxy",
		Version: "0.0.1",
	}, &mcp.ServerOptions{
		InitializedHandler: func(ctx context.Context, req *mcp.InitializedRequest) {
			id := req.Session.ID()
			slog.Info("new client session", "sessionID", id)

			s, err := newMCPSession(context.WithoutCancel(ctx))
			if err != nil {
				slog.Error("failed to create new session", "error", err, "sessionID", id)
				return
			}

			sessions.Store(id, newSession(s))
			slog.Info("connected to stdio server", "sessionID", id)

			go cleanup()
		},
	})

	s.AddReceivingMiddleware(func(next mcp.MethodHandler) mcp.MethodHandler {
		return func(ctx context.Context, method string, req mcp.Request) (result mcp.Result, err error) {
			if method == "initialize" || method == "notifications/initialized" {
				return next(ctx, method, req)
			}

			id := req.GetSession().ID()
			v, ok := sessions.Load(id)
			if !ok {
				return nil, fmt.Errorf("unknown session id: %s", id)
			}
			s := v.(*session).Touch()
			switch method {
			case "tools/call":
				raw := req.GetParams().(*mcp.CallToolParamsRaw)
				parsed := mcp.CallToolParams{
					Meta: raw.Meta,
					Name: raw.Name,
				}
				if err := json.Unmarshal(raw.Arguments, &parsed.Arguments); err != nil {
					return nil, err
				}
				return s.CallTool(ctx, &parsed)
			case "tools/list":
				return s.ListTools(ctx, req.GetParams().(*mcp.ListToolsParams))
			default:
				return next(ctx, method, req)
			}
		}
	})

	return mcp.NewStreamableHTTPHandler(func(r *http.Request) *mcp.Server { return s }, &mcp.StreamableHTTPOptions{
		Stateless: false,
	})
}

func main() {
	addr := flag.String("addr", ":8000", "address to listen on")
	help := flag.Bool("help", false, "show help")
	flag.Parse()
	if *help || len(flag.Args()) < 1 {
		flag.Usage()
		return
	}

	logger := slog.New(slog.NewTextHandler(os.Stderr, &slog.HandlerOptions{Level: slog.LevelInfo}))
	slog.SetDefault(logger)

	h := newHandler(func(ctx context.Context) (*mcp.ClientSession, error) {
		clt := mcp.NewClient(&mcp.Implementation{
			Name:    "mcp-proxy-client",
			Version: "1.0.0",
		}, nil)

		cmd := exec.Command(flag.Args()[0], flag.Args()[1:]...)
		transport := &mcp.CommandTransport{Command: cmd}

		return clt.Connect(ctx, transport, nil)
	})

	if err := http.ListenAndServe(*addr, h); err != nil {
		slog.Error("server error", "error", err)
	}
}
