package build

import (
	"archive/tar"
	"bytes"
	"compress/gzip"
	"crypto/sha256"
	"encoding/hex"
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"testing"
)

// runPrepare executes the embedded prepare.py with the given environment,
// against a fixture tarball, in a temp directory. Returns combined output and
// the exit status.
func runPrepare(t *testing.T, artifact []byte, digest string, env map[string]string) (string, bool, string) {
	t.Helper()
	if _, err := exec.LookPath("python3"); err != nil {
		t.Skip("python3 not available")
	}

	dir := t.TempDir()
	src := filepath.Join(dir, "src")
	out := filepath.Join(dir, "out")
	if err := os.MkdirAll(src, 0o755); err != nil {
		t.Fatal(err)
	}

	artifactPath := filepath.Join(dir, "artifact.tar.gz")
	if err := os.WriteFile(artifactPath, artifact, 0o644); err != nil {
		t.Fatal(err)
	}

	fullEnv := append(os.Environ(),
		"SOURCE_DIR="+src,
		"OUT_DIR="+out,
		"ARTIFACT_URL=file://"+artifactPath,
		"ARTIFACT_DIGEST="+digest,
		"TAG={{ version }}-{{ base }}",
	)
	for k, v := range env {
		fullEnv = append(fullEnv, k+"="+v)
	}

	cmd := exec.Command("python3", "-c", prepareScript)
	cmd.Env = fullEnv
	output, err := cmd.CombinedOutput()

	tag := ""
	if data, readErr := os.ReadFile(filepath.Join(out, "tag")); readErr == nil {
		tag = string(data)
	}
	return string(output), err == nil, tag
}

// fixtureTar builds an in-memory artifact containing a Dockerfile and VERSION
// under images/dae/.
func fixtureTar(t *testing.T, members map[string]string, links map[string]string) []byte {
	t.Helper()
	var buf bytes.Buffer
	gz := gzip.NewWriter(&buf)
	tw := tar.NewWriter(gz)
	for name, content := range members {
		if err := tw.WriteHeader(&tar.Header{
			Name: name,
			Mode: 0o644,
			Size: int64(len(content)),
		}); err != nil {
			t.Fatal(err)
		}
		if _, err := tw.Write([]byte(content)); err != nil {
			t.Fatal(err)
		}
	}
	for name, target := range links {
		if err := tw.WriteHeader(&tar.Header{
			Name:     name,
			Mode:     0o777,
			Linkname: target,
			Typeflag: tar.TypeSymlink,
		}); err != nil {
			t.Fatal(err)
		}
	}
	if err := tw.Close(); err != nil {
		t.Fatal(err)
	}
	if err := gz.Close(); err != nil {
		t.Fatal(err)
	}
	return buf.Bytes()
}

func artifactDigest(artifact []byte) string {
	sum := sha256.Sum256(artifact)
	return "sha256:" + hex.EncodeToString(sum[:])
}

var happyMembers = map[string]string{
	"images/dae/Dockerfile": "FROM scratch\n",
	"images/dae/update.py":  "# update helper\n",
}

func TestPrepareHappyPath(t *testing.T) {
	artifact := fixtureTar(t, happyMembers, nil)
	output, ok, tag := runPrepare(t, artifact, artifactDigest(artifact), map[string]string{
		"CONTEXT":      "images/dae",
		"VERSION_FILE": "VERSION",
		"UPDATE_CMD":   `["python3","-c","open('VERSION','w').write('2.0.2')"]`,
		"VAR_BASE":     "testing-20260824",
	})
	if !ok {
		t.Fatalf("prepare failed: %s", output)
	}
	if tag != "2.0.2-testing-20260824" {
		t.Fatalf("tag = %q", tag)
	}
}

func TestPrepareVersionLiteral(t *testing.T) {
	artifact := fixtureTar(t, happyMembers, nil)
	output, ok, tag := runPrepare(t, artifact, artifactDigest(artifact), map[string]string{
		"CONTEXT":         "images/dae",
		"VERSION_LITERAL": "0.1.0",
	})
	if !ok {
		t.Fatalf("prepare failed: %s", output)
	}
	if tag != "0.1.0-" {
		t.Fatalf("tag = %q", tag)
	}
}

func TestPrepareDigestMismatch(t *testing.T) {
	artifact := fixtureTar(t, happyMembers, nil)
	output, ok, _ := runPrepare(t, artifact, "sha256:"+strings.Repeat("0", 64), map[string]string{
		"CONTEXT":         "images/dae",
		"VERSION_LITERAL": "0.1.0",
	})
	if ok {
		t.Fatal("digest mismatch must fail")
	}
	if !strings.Contains(output, "digest mismatch") {
		t.Fatalf("want digest mismatch marker, got: %s", output)
	}
}

func TestPrepareRejectsPathTraversal(t *testing.T) {
	artifact := fixtureTar(t, map[string]string{"../escape": "x"}, nil)
	output, ok, _ := runPrepare(t, artifact, artifactDigest(artifact), map[string]string{
		"CONTEXT":         "images/dae",
		"VERSION_LITERAL": "0.1.0",
	})
	if ok {
		t.Fatal("traversal member must be rejected")
	}
	if !strings.Contains(output, "unsafe path") {
		t.Fatalf("want unsafe path marker, got: %s", output)
	}
}

func TestPrepareRejectsAbsoluteMember(t *testing.T) {
	artifact := fixtureTar(t, map[string]string{"/etc/passwd": "x"}, nil)
	_, ok, _ := runPrepare(t, artifact, artifactDigest(artifact), map[string]string{
		"CONTEXT":         "images/dae",
		"VERSION_LITERAL": "0.1.0",
	})
	if ok {
		t.Fatal("absolute member must be rejected")
	}
}

func TestPrepareAllowsInTreeSymlink(t *testing.T) {
	// A symlink committed anywhere in the repo (pointing inside the repo)
	// must not brick every build; the data filter only rejects links that
	// escape the extraction root.
	artifact := fixtureTar(t, happyMembers, map[string]string{
		"images/dae/link":   "update.py",
		"docs/elsewhere.md": "../README.md",
	})
	output, ok, _ := runPrepare(t, artifact, artifactDigest(artifact), map[string]string{
		"CONTEXT":         "images/dae",
		"VERSION_LITERAL": "0.1.0",
	})
	if !ok {
		t.Fatalf("in-tree symlinks must extract: %s", output)
	}
}

func TestPrepareRejectsEscapingSymlink(t *testing.T) {
	artifact := fixtureTar(t, happyMembers, map[string]string{"images/dae/link": "/etc"})
	output, ok, _ := runPrepare(t, artifact, artifactDigest(artifact), map[string]string{
		"CONTEXT":         "images/dae",
		"VERSION_LITERAL": "0.1.0",
	})
	if ok {
		t.Fatal("escaping symlink member must be rejected")
	}
	if !strings.Contains(output, "artifact fetch failed") {
		t.Fatalf("want failure marker, got: %s", output)
	}
}

func TestPrepareRejectsContextEscape(t *testing.T) {
	artifact := fixtureTar(t, happyMembers, nil)
	output, ok, _ := runPrepare(t, artifact, artifactDigest(artifact), map[string]string{
		"CONTEXT":         "../../etc",
		"VERSION_LITERAL": "0.1.0",
	})
	if ok {
		t.Fatal("context escape must be rejected")
	}
	if !strings.Contains(output, "context escapes source") {
		t.Fatalf("want escape marker, got: %s", output)
	}
}

func TestPrepareMissingDockerfile(t *testing.T) {
	artifact := fixtureTar(t, map[string]string{"images/dae/README": "x"}, nil)
	output, ok, _ := runPrepare(t, artifact, artifactDigest(artifact), map[string]string{
		"CONTEXT":         "images/dae",
		"VERSION_LITERAL": "0.1.0",
	})
	if ok {
		t.Fatal("missing Dockerfile must fail")
	}
	if !strings.Contains(output, "no Dockerfile") {
		t.Fatalf("want Dockerfile marker, got: %s", output)
	}
}

func TestPrepareWhitespaceTagVariables(t *testing.T) {
	// tagVarPattern (validation) accepts any inner whitespace; the renderer
	// must substitute every form it lets through.
	artifact := fixtureTar(t, happyMembers, nil)
	output, ok, tag := runPrepare(t, artifact, artifactDigest(artifact), map[string]string{
		"CONTEXT":         "images/dae",
		"VERSION_LITERAL": "0.1.0",
		"TAG":             "{{version}}-{{  version  }}-{{ base }}",
		"VAR_BASE":        "testing-1",
	})
	if !ok {
		t.Fatalf("whitespace tag variables must render: %s", output)
	}
	if tag != "0.1.0-0.1.0-testing-1" {
		t.Fatalf("tag = %q", tag)
	}
}

func TestPrepareUnresolvedVariable(t *testing.T) {
	artifact := fixtureTar(t, happyMembers, nil)
	output, ok, _ := runPrepare(t, artifact, artifactDigest(artifact), map[string]string{
		"CONTEXT":      "images/dae",
		"TAG":          "{{ version }}-{{ flavour }}",
		"UPDATE_CMD":   `["python3","-c","open('VERSION','w').write('1.0')"]`,
		"VERSION_FILE": "VERSION",
	})
	if ok {
		t.Fatal("unresolved variable must fail")
	}
	if !strings.Contains(output, "unresolved template variable") {
		t.Fatalf("want unresolved marker, got: %s", output)
	}
}

func TestPrepareInvalidTagCharset(t *testing.T) {
	artifact := fixtureTar(t, happyMembers, nil)
	output, ok, _ := runPrepare(t, artifact, artifactDigest(artifact), map[string]string{
		"CONTEXT":      "images/dae",
		"TAG":          "{{ version }}",
		"UPDATE_CMD":   `["python3","-c","open('VERSION','w').write('1.0/evil:tag')"]`,
		"VERSION_FILE": "VERSION",
	})
	if ok {
		t.Fatal("invalid tag charset must fail")
	}
	if !strings.Contains(output, "invalid tag") {
		t.Fatalf("want invalid tag marker, got: %s", output)
	}
}

func TestPrepareEmptyVersionFile(t *testing.T) {
	artifact := fixtureTar(t, happyMembers, nil)
	output, ok, _ := runPrepare(t, artifact, artifactDigest(artifact), map[string]string{
		"CONTEXT":      "images/dae",
		"VERSION_FILE": "VERSION",
		"UPDATE_CMD":   `["python3","-c","open('VERSION','w').write('')"]`,
	})
	if ok {
		t.Fatal("empty version file must fail")
	}
	if !strings.Contains(output, "empty version file") {
		t.Fatalf("want empty version marker, got: %s", output)
	}
}
