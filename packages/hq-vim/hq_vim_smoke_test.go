package main

import (
	"encoding/json"
	"os"
	"os/exec"
	"path/filepath"
	"runtime"
	"strings"
	"testing"
	"time"

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
	bufferText := "@host.open\npath=" + target
	resultRoot := t.TempDir()
	submitResult := filepath.Join(resultRoot, "submit.json")
	bufferResult := filepath.Join(resultRoot, "after.json")
	undoResult := filepath.Join(resultRoot, "undo.json")
	messages := filepath.Join(resultRoot, "messages.txt")
	cfg := smoke.Config{
		HQBin:            hqBin,
		Vim:              vim,
		Vim9LSP:          vimLSP,
		PluginRoot:       root,
		Profile:          "local",
		Buffer:           filepath.Join(t.TempDir(), "manual.hqjson"),
		BufferText:       bufferText,
		Headless:         true,
		Env:              map[string]string{"HQ_STUB_ROOT": profileRoot},
		ResultPath:       submitResult,
		BufferResultPath: bufferResult,
		UndoResultPath:   undoResult,
		MessagesPath:     messages,
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
	if got := readVimBuffer(t, bufferResult); len(got.Lines) != 1 || got.Lines[0] != "" {
		t.Fatalf("accepted draft was not consumed: %#v result=%s", got, readText(t, submitResult))
	}
	if got := readVimBuffer(t, undoResult); strings.Join(got.Lines, "\n") != bufferText {
		t.Fatalf("one Vim undo did not restore draft text: %#v", got)
	}
	if got := readText(t, messages); !strings.Contains(got, "hq accepted hqcmd_stub; draft consumed") {
		t.Fatalf("missing consumed outcome: %s", got)
	}
}

func TestVersionGuardKeepsNewerDraft(t *testing.T) {
	root := mustPackageRoot(t)
	resultPath := filepath.Join(t.TempDir(), "version-guard.json")
	script := strings.Join([]string{
		"vim9script",
		"execute 'set runtimepath^=' .. fnameescape(" + vimLiteral(requireVim9LSP(t)) + ")",
		"execute 'set runtimepath^=' .. fnameescape(" + vimLiteral(root) + ")",
		"import autoload 'hq.vim' as hq",
		"new",
		"setline(1, ['@host.open', 'path=old'])",
		"feedkeys(\"\\<Esc>\", 'xt')",
		"var submittedTick = b:changedtick",
		"var uri = 'file:///version-guard.hqjson'",
		"var accepted = {draftConsumption: {kind: 'hq.draftConsumption.v1', textDocument: {uri: uri, version: submittedTick}, edits: [{range: {start: {line: 0, character: 0}, end: {line: 1, character: 8}}, newText: ''}]}}",
		"setline(1, '@host.open.newer')",
		"var outcome = hq.ConsumeAcceptedDraft(accepted, bufnr(), uri, submittedTick, submittedTick)",
		"writefile([json_encode({outcome: outcome, lines: getline(1, '$')})], " + vimLiteral(resultPath) + ")",
		"qa!",
	}, "\n") + "\n"
	scriptPath := filepath.Join(t.TempDir(), "version-guard.vim")
	if err := os.WriteFile(scriptPath, []byte(script), 0o600); err != nil {
		t.Fatal(err)
	}
	cmd := exec.Command(requireVim(t), "--clean", "-Nu", "NONE", "-n", "-es", "-S", scriptPath)
	if output, err := cmd.CombinedOutput(); err != nil {
		t.Fatalf("version-guard Vim failed: %v\n%s\nscript:\n%s", err, output, script)
	}
	var proof struct {
		Outcome string   `json:"outcome"`
		Lines   []string `json:"lines"`
	}
	content, err := os.ReadFile(resultPath)
	if err != nil {
		t.Fatal(err)
	}
	if err := json.Unmarshal(content, &proof); err != nil {
		t.Fatal(err)
	}
	if proof.Outcome != "newer-draft-kept" || strings.Join(proof.Lines, "\n") != "@host.open.newer\npath=old" {
		t.Fatalf("version guard proof=%#v", proof)
	}
}

func TestNativeHQFuzzyAutomaticPopupDoesNotAccept(t *testing.T) {
	if os.Getenv("HQ_NATIVE_HQ_FUZZY_PROOF") != "1" {
		t.Skip("set HQ_NATIVE_HQ_FUZZY_PROOF=1 and run under a real terminal")
	}
	hqBin := os.Getenv("HQ_BIN")
	if hqBin == "" {
		t.Fatal("HQ_BIN is required for the real-hq fuzzy popup proof")
	}
	root := mustPackageRoot(t)
	profileEnv, accepted := prepareStrictHQProfile(t, root, "local")
	artifact := filepath.Join(t.TempDir(), "native-hq-fuzzy-popup.json")
	cfg := smoke.Config{
		HQBin:                   hqBin,
		Vim:                     requireVim(t),
		Vim9LSP:                 requireVim9LSP(t),
		PluginRoot:              root,
		Profile:                 "local",
		Buffer:                  filepath.Join(t.TempDir(), "native-hq-fuzzy-popup.hqjson"),
		CompletionText:          "@qce",
		ExpectedCompletionLabel: "queue.create",
		NativePopupArtifact:     artifact,
		Env:                     profileEnv,
		Timeout:                 15 * time.Second,
	}
	if err := smoke.Run(cfg); err != nil {
		artifactBody, _ := os.ReadFile(artifact)
		t.Fatalf("native real-hq fuzzy popup smoke failed: %v\nartifact: %s", err, artifactBody)
	}
	var result struct {
		Status string `json:"status"`
		Line   string `json:"line"`
	}
	b, err := os.ReadFile(artifact)
	if err != nil {
		t.Fatalf("read native real-hq popup artifact: %v", err)
	}
	if err := json.Unmarshal(b, &result); err != nil {
		t.Fatalf("decode native real-hq popup artifact: %v\n%s", err, b)
	}
	if result.Status != "passed" || result.Line != "@queue.create" {
		t.Fatalf("native real-hq fuzzy popup result = %#v", result)
	}
	acceptedBody, err := os.ReadFile(accepted)
	if err != nil {
		t.Fatalf("read accepted log after native selection: %v", err)
	}
	if strings.TrimSpace(string(acceptedBody)) != "" {
		t.Fatalf("native completion selection wrote accepted evidence: %s", acceptedBody)
	}
}

func TestAcceptedSubmitKeepsDraftWhenConsumptionPlanIsInvalid(t *testing.T) {
	root := mustPackageRoot(t)
	profileRoot := prepareProfile(t, root, "local")
	queue := filepath.Join(profileRoot, "local", "queue.jsonl")
	target := t.TempDir()
	draft := "@host.open\npath=" + target
	resultRoot := t.TempDir()
	bufferResult := filepath.Join(resultRoot, "after.json")
	messages := filepath.Join(resultRoot, "messages.txt")
	cfg := smoke.Config{
		HQBin: buildHQStub(t), Vim: requireVim(t), Vim9LSP: requireVim9LSP(t),
		PluginRoot: root, Profile: "local", Buffer: filepath.Join(t.TempDir(), "manual.hqjson"),
		BufferText: draft, Headless: true,
		Env:              map[string]string{"HQ_STUB_ROOT": profileRoot, "HQ_STUB_PLAN_MODE": "invalid"},
		BufferResultPath: bufferResult, MessagesPath: messages,
	}
	if err := smoke.Run(cfg); err != nil {
		t.Fatalf("invalid-plan smoke failed: %v", err)
	}
	if rows := readJSONLRows(t, queue); len(rows) != 1 {
		t.Fatalf("accepted rows=%#v", rows)
	}
	if got := readVimBuffer(t, bufferResult); strings.Join(got.Lines, "\n") != draft {
		t.Fatalf("draft changed after invalid plan: %#v", got)
	}
	if got := readText(t, messages); !strings.Contains(got, "draft not consumed (invalid consumption plan)") {
		t.Fatalf("missing invalid-plan outcome: %s", got)
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

func prepareStrictHQProfile(t *testing.T, packageRoot, profile string) (map[string]string, string) {
	t.Helper()
	configRoot := t.TempDir()
	profileRoot := filepath.Join(configRoot, "roccho", "hq", "profiles")
	if err := os.MkdirAll(profileRoot, 0o755); err != nil {
		t.Fatal(err)
	}
	runtimeRoot := t.TempDir()
	workspace := filepath.Join(runtimeRoot, "workspace")
	events := filepath.Join(runtimeRoot, "events", "events.jsonl")
	if err := os.MkdirAll(workspace, 0o755); err != nil {
		t.Fatal(err)
	}
	if err := os.MkdirAll(filepath.Dir(events), 0o755); err != nil {
		t.Fatal(err)
	}
	world := filepath.Join(runtimeRoot, "world.jsonl")
	worldBytes, err := os.ReadFile(filepath.Join(packageRoot, "testdata", "strict-world.jsonl"))
	if err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(world, worldBytes, 0o644); err != nil {
		t.Fatal(err)
	}
	accepted := filepath.Join(runtimeRoot, "accepted.jsonl")
	if err := os.WriteFile(accepted, nil, 0o644); err != nil {
		t.Fatal(err)
	}
	capabilities := filepath.Join(runtimeRoot, "capabilities.json")
	if err := os.WriteFile(capabilities, []byte("{}\n"), 0o644); err != nil {
		t.Fatal(err)
	}
	profileBytes, err := json.Marshal(map[string]any{
		"kind": "hq.profile.v1", "name": profile, "deployment_id": "hq-vim-native-fuzzy-proof",
		"world_path": world, "accepted_path": accepted, "workspace_root": workspace,
		"events_path": events, "capabilities_path": capabilities,
		"poll_interval_ms": 50, "health_timeout_ms": 2000,
	})
	if err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(filepath.Join(profileRoot, profile+".json"), append(profileBytes, '\n'), 0o644); err != nil {
		t.Fatal(err)
	}
	key := "XDG_CONFIG_HOME"
	if runtime.GOOS == "windows" {
		key = "APPDATA"
	}
	return map[string]string{key: configRoot}, accepted
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

type vimBufferSnapshot struct {
	Lines       []string `json:"lines"`
	ChangedTick int      `json:"changedtick"`
}

func readVimBuffer(t *testing.T, path string) vimBufferSnapshot {
	t.Helper()
	content, err := os.ReadFile(path)
	if err != nil {
		t.Fatal(err)
	}
	var snapshot vimBufferSnapshot
	if err := json.Unmarshal(content, &snapshot); err != nil {
		t.Fatalf("decode %s: %v", path, err)
	}
	return snapshot
}

func readText(t *testing.T, path string) string {
	t.Helper()
	content, err := os.ReadFile(path)
	if err != nil {
		t.Fatal(err)
	}
	return string(content)
}

func vimLiteral(value string) string {
	encoded, _ := json.Marshal(filepath.ToSlash(value))
	return string(encoded)
}
