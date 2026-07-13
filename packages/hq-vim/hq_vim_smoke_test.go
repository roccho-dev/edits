package main

import (
	"encoding/json"
	"os"
	"os/exec"
	"path/filepath"
	"runtime"
	"strings"
	"testing"

	"github.com/roccho-dev/edits/packages/hq-vim/internal/smoke"
)

func TestMissingHQBinaryFailsFast(t *testing.T) {
	root := mustPackageRoot(t)
	vimLSP := requireVim9LSP(t)
	vim := requireVim(t)
	missing := filepath.Join(t.TempDir(), exeName("missing-hq"))
	cfg := smoke.Config{
		HQBin:      missing,
		Vim:        vim,
		Vim9LSP:    vimLSP,
		PluginRoot: root,
		Profile:    "local",
		Buffer:     filepath.Join(t.TempDir(), "manual.hqjson"),
		Headless:   true,
	}
	err := smoke.Run(cfg)
	if err == nil {
		t.Fatal("expected missing hq binary to fail")
	}
	if !strings.Contains(err.Error(), "hq binary not found") {
		t.Fatalf("unexpected error: %v", err)
	}
}

func TestReadableNonExecutableHQFailsFast(t *testing.T) {
	root := mustPackageRoot(t)
	notExecutable := filepath.Join(t.TempDir(), "not-hq.txt")
	if err := os.WriteFile(notExecutable, []byte("not an executable"), 0o644); err != nil {
		t.Fatal(err)
	}
	cfg := smoke.Config{
		HQBin:      notExecutable,
		Vim:        requireVim(t),
		Vim9LSP:    requireVim9LSP(t),
		PluginRoot: root,
		Profile:    "local",
		Buffer:     filepath.Join(t.TempDir(), "manual.hqjson"),
		Headless:   true,
		StartOnly:  true,
	}
	if err := smoke.Run(cfg); err == nil {
		t.Fatal("expected readable non-executable hq path to fail during HqStart")
	}
}

func TestRealVim9LspConfirmQueueSmoke(t *testing.T) {
	root := mustPackageRoot(t)
	vimLSP := requireVim9LSP(t)
	vim := requireVim(t)
	hqBin := buildHQStub(t)
	profileRoot := prepareProfile(t, root, "local")
	queue := filepath.Join(profileRoot, "local", "queue.jsonl")
	target := t.TempDir()
	bufferText, err := json.Marshal(map[string]any{"kind": "hq.hostOpenRequest.v1", "path": target})
	if err != nil {
		t.Fatal(err)
	}
	cfg := smoke.Config{
		HQBin:      hqBin,
		Vim:        vim,
		Vim9LSP:    vimLSP,
		PluginRoot: root,
		Profile:    "local",
		Buffer:     filepath.Join(t.TempDir(), "manual.hqjson"),
		BufferText: string(bufferText),
		Headless:   true,
		Env:        map[string]string{"HQ_STUB_ROOT": profileRoot},
	}
	if err := smoke.Run(cfg); err != nil {
		t.Fatalf("smoke failed: %v", err)
	}
	b, err := os.ReadFile(queue)
	if err != nil {
		t.Fatalf("queue not written: %v", err)
	}
	var row struct {
		Kind string `json:"kind"`
		Path string `json:"path"`
	}
	if err := json.Unmarshal(bytesTrimLine(b), &row); err != nil {
		t.Fatalf("queue row json: %v\n%s", err, b)
	}
	if row.Kind != "hq.hostCommandQueued.v1" {
		t.Fatalf("unexpected queue kind: %s", row.Kind)
	}
	if row.Path != target {
		t.Fatalf("queue path = %q, want buffer path %q", row.Path, target)
	}
}

func TestHQRejectsProfileWithMissingJSONL(t *testing.T) {
	hqBin := buildHQStub(t)
	for _, tc := range []struct {
		name  string
		setup func(*testing.T, string)
		code  string
	}{
		{name: "world", code: "profile_world_missing"},
		{name: "queue", code: "profile_queue_missing", setup: func(t *testing.T, dir string) {
			t.Helper()
			if err := os.WriteFile(filepath.Join(dir, "world.jsonl"), []byte("{}\n"), 0o644); err != nil {
				t.Fatal(err)
			}
		}},
	} {
		t.Run(tc.name, func(t *testing.T) {
			profileRoot := t.TempDir()
			dir := filepath.Join(profileRoot, "local")
			if err := os.MkdirAll(dir, 0o755); err != nil {
				t.Fatal(err)
			}
			if tc.setup != nil {
				tc.setup(t, dir)
			}
			cmd := exec.Command(hqBin, "lsp", "--profile", "local")
			cmd.Env = append(os.Environ(), "HQ_STUB_ROOT="+profileRoot)
			b, err := cmd.CombinedOutput()
			if err == nil {
				t.Fatal("expected missing profile JSONL to fail")
			}
			if !strings.Contains(string(b), `"code":"`+tc.code+`"`) {
				t.Fatalf("unexpected startup error: %s", b)
			}
		})
	}
}

func mustPackageRoot(t *testing.T) string {
	t.Helper()
	root, err := smoke.PackageRoot("")
	if err != nil {
		t.Fatal(err)
	}
	return root
}

func requireVim9LSP(t *testing.T) string {
	t.Helper()
	if v := os.Getenv("VIM9_LSP_PATH"); v != "" && smoke.Exists(filepath.Join(v, "plugin", "lsp.vim")) {
		return v
	}
	if runtime.GOOS == "windows" {
		cand := filepath.Join(os.Getenv("LOCALAPPDATA"), "codex-proof", "yegappan-lsp")
		if smoke.Exists(filepath.Join(cand, "plugin", "lsp.vim")) {
			return cand
		}
	}
	t.Skip("yegappan/lsp not found; set VIM9_LSP_PATH")
	return ""
}

func requireVim(t *testing.T) string {
	t.Helper()
	if v := os.Getenv("VIM_EXE"); v != "" && smoke.Exists(v) {
		return v
	}
	for _, name := range []string{"vim", "vim.exe"} {
		if path, err := exec.LookPath(name); err == nil {
			return path
		}
	}
	t.Skip("vim not found; set VIM_EXE")
	return ""
}

func buildHQStub(t *testing.T) string {
	t.Helper()
	out := filepath.Join(t.TempDir(), exeName("hqstub"))
	cmd := exec.Command("go", "build", "-o", out, "./testfixture/hqstub")
	cmd.Dir = mustPackageRoot(t)
	if b, err := cmd.CombinedOutput(); err != nil {
		t.Fatalf("build hq stub: %v\n%s", err, b)
	}
	return out
}

func prepareProfile(t *testing.T, packageRoot, profile string) string {
	t.Helper()
	root := t.TempDir()
	dir := filepath.Join(root, profile)
	if err := os.MkdirAll(dir, 0o755); err != nil {
		t.Fatal(err)
	}
	world, err := os.ReadFile(filepath.Join(packageRoot, "testdata", "world.jsonl"))
	if err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(filepath.Join(dir, "world.jsonl"), world, 0o644); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(filepath.Join(dir, "queue.jsonl"), nil, 0o644); err != nil {
		t.Fatal(err)
	}
	return root
}

func exeName(name string) string {
	if runtime.GOOS == "windows" {
		return name + ".exe"
	}
	return name
}

func bytesTrimLine(b []byte) []byte {
	parts := strings.SplitN(strings.TrimSpace(string(b)), "\n", 2)
	return []byte(parts[0])
}
