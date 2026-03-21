package main

import (
	"context"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
	"testing/synctest"
	"time"

	"github.com/modelcontextprotocol/go-sdk/mcp"
)

func TestSessionTouch(t *testing.T) {
	synctest.Test(t, func(t *testing.T) {
		s := &session{ClientSession: nil, expireAt: time.Now()}
		before := s.expireAt

		time.Sleep(10 * time.Millisecond)

		s.Touch()

		if !s.expireAt.After(before) {
			t.Error("Touch() should update expireAt to a later time")
		}
	})
}

func TestNewSession(t *testing.T) {
	// Create paired in-memory transports
	clientTransport, serverTransport := mcp.NewInMemoryTransports()

	// Create and connect server
	server := mcp.NewServer(&mcp.Implementation{
		Name:    "test-server",
		Version: "1.0.0",
	}, nil)
	go server.Connect(context.Background(), serverTransport, nil)

	// Create and connect client
	clt := mcp.NewClient(&mcp.Implementation{
		Name:    "test-client",
		Version: "1.0.0",
	}, nil)

	cs, err := clt.Connect(context.Background(), clientTransport, nil)
	if err != nil {
		t.Fatalf("failed to connect: %v", err)
	}

	s := newSession(cs)
	if s == nil {
		t.Fatal("newSession returned nil")
	}
	if s.ClientSession == nil {
		t.Error("session.ClientSession should not be nil")
	}

	// expireAt should be approximately 1 hour from now
	expectedExpiry := time.Now().Add(time.Hour)
	diff := expectedExpiry.Sub(s.expireAt)
	if diff < -time.Second || diff > time.Second {
		t.Errorf("expireAt should be ~1 hour from now, got diff: %v", diff)
	}
}

func TestNewHandlerCreatesHandler(t *testing.T) {
	// Create a mock newSession function that returns a real session
	newSessionFunc := func(ctx context.Context) (*mcp.ClientSession, error) {
		clientTransport, serverTransport := mcp.NewInMemoryTransports()

		server := mcp.NewServer(&mcp.Implementation{
			Name:    "test-server",
			Version: "1.0.0",
		}, nil)
		go server.Connect(ctx, serverTransport, nil)

		clt := mcp.NewClient(&mcp.Implementation{
			Name:    "test-client",
			Version: "1.0.0",
		}, nil)

		return clt.Connect(ctx, clientTransport, nil)
	}

	h := newHandler(newSessionFunc)
	if h == nil {
		t.Fatal("newHandler returned nil")
	}
}

func TestHandlerRejectsGet(t *testing.T) {
	newSessionFunc := func(ctx context.Context) (*mcp.ClientSession, error) {
		return nil, nil
	}

	h := newHandler(newSessionFunc)
	server := httptest.NewServer(h)
	defer server.Close()

	resp, err := http.Get(server.URL)
	if err != nil {
		t.Fatalf("GET request failed: %v", err)
	}
	defer resp.Body.Close()

	// MCP streamable HTTP spec requires POST for method calls
	// Handler returns 400 Bad Request for invalid requests
	if resp.StatusCode == http.StatusOK {
		t.Errorf("GET should not return 200 OK")
	}
}

func TestHandlerAcceptsPost(t *testing.T) {
	newSessionFunc := func(ctx context.Context) (*mcp.ClientSession, error) {
		clientTransport, serverTransport := mcp.NewInMemoryTransports()

		server := mcp.NewServer(&mcp.Implementation{
			Name:    "test-server",
			Version: "1.0.0",
		}, nil)
		go server.Connect(ctx, serverTransport, nil)

		clt := mcp.NewClient(&mcp.Implementation{
			Name:    "test-client",
			Version: "1.0.0",
		}, nil)

		return clt.Connect(ctx, clientTransport, nil)
	}

	h := newHandler(newSessionFunc)
	server := httptest.NewServer(h)
	defer server.Close()

	// Send an initialize request
	body := `{"jsonrpc":"2.0","method":"initialize","params":{"protocolVersion":"2024-11-05","capabilities":{},"clientInfo":{"name":"test","version":"1.0.0"}},"id":1}`
	resp, err := http.Post(server.URL, "application/json", strings.NewReader(body))
	if err != nil {
		t.Fatalf("POST request failed: %v", err)
	}
	defer resp.Body.Close()

	// Should accept POST requests (not MethodNotAllowed)
	if resp.StatusCode == http.StatusMethodNotAllowed {
		t.Error("POST should not return MethodNotAllowed")
	}
}

// createBackendServer creates an in-memory MCP server with a test tool and waits for it to be ready
func createBackendServer(ctx context.Context, t *testing.T) *mcp.InMemoryTransport {
	t.Helper()
	clientTransport, serverTransport := mcp.NewInMemoryTransports()

	server := mcp.NewServer(&mcp.Implementation{
		Name:    "backend-server",
		Version: "1.0.0",
	}, nil)

	// Add a test tool using AddTool with proper signature
	mcp.AddTool(server, &mcp.Tool{
		Name:        "echo",
		Description: "Echoes back the input",
	}, func(ctx context.Context, req *mcp.CallToolRequest, args struct {
		Message string `json:"message"`
	}) (*mcp.CallToolResult, any, error) {
		return &mcp.CallToolResult{
			Content: []mcp.Content{&mcp.TextContent{Text: args.Message}},
		}, nil, nil
	})

	_, err := server.Connect(ctx, serverTransport, nil)
	if err != nil {
		t.Logf("server connect error: %v", err)
	}

	return clientTransport
}

func TestToolsListForwarded(t *testing.T) {
	ctx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
	defer cancel()

	backendTransport := createBackendServer(ctx, t)

	newSessionFunc := func(ctx context.Context) (*mcp.ClientSession, error) {
		clt := mcp.NewClient(&mcp.Implementation{
			Name:    "proxy-client",
			Version: "1.0.0",
		}, nil)
		return clt.Connect(ctx, backendTransport, nil)
	}

	h := newHandler(newSessionFunc)
	httpServer := httptest.NewServer(h)
	defer httpServer.Close()

	// Use the MCP client to connect to the proxy and list tools
	proxyTransport := &mcp.StreamableClientTransport{
		Endpoint: httpServer.URL,
	}

	clt := mcp.NewClient(&mcp.Implementation{
		Name:    "test-client",
		Version: "1.0.0",
	}, nil)

	session, err := clt.Connect(ctx, proxyTransport, nil)
	if err != nil {
		t.Fatalf("failed to connect to proxy: %v", err)
	}
	defer session.Close()

	tools, err := session.ListTools(ctx, nil)
	if err != nil {
		t.Fatalf("failed to list tools: %v", err)
	}

	if len(tools.Tools) != 1 {
		t.Errorf("expected 1 tool, got %d", len(tools.Tools))
	}
	if tools.Tools[0].Name != "echo" {
		t.Errorf("expected tool name 'echo', got %q", tools.Tools[0].Name)
	}
}

func TestToolsCallForwarded(t *testing.T) {
	ctx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
	defer cancel()

	backendTransport := createBackendServer(ctx, t)

	newSessionFunc := func(ctx context.Context) (*mcp.ClientSession, error) {
		clt := mcp.NewClient(&mcp.Implementation{
			Name:    "proxy-client",
			Version: "1.0.0",
		}, nil)
		return clt.Connect(ctx, backendTransport, nil)
	}

	h := newHandler(newSessionFunc)
	httpServer := httptest.NewServer(h)
	defer httpServer.Close()

	// Use the MCP client to connect to the proxy and call a tool
	proxyTransport := &mcp.StreamableClientTransport{
		Endpoint: httpServer.URL,
	}

	clt := mcp.NewClient(&mcp.Implementation{
		Name:    "test-client",
		Version: "1.0.0",
	}, nil)

	session, err := clt.Connect(ctx, proxyTransport, nil)
	if err != nil {
		t.Fatalf("failed to connect to proxy: %v", err)
	}
	defer session.Close()

	result, err := session.CallTool(ctx, &mcp.CallToolParams{
		Name: "echo",
		Arguments: map[string]any{
			"message": "hello world",
		},
	})
	if err != nil {
		t.Fatalf("failed to call tool: %v", err)
	}

	if len(result.Content) != 1 {
		t.Fatalf("expected 1 content item, got %d", len(result.Content))
	}

	textContent, ok := result.Content[0].(*mcp.TextContent)
	if !ok {
		t.Fatalf("expected TextContent, got %T", result.Content[0])
	}

	if textContent.Text != "hello world" {
		t.Errorf("expected 'hello world', got %q", textContent.Text)
	}
}
