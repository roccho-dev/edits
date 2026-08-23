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

// TestEditorSurfaceAndBindingFailClosed fixes the complete editor-owned UX
// surface. Vim may start HQ, submit one draft, or inspect its binding. Command
// discovery, history, routing, retry, and provider policy stay HQ/world-owned.
func TestEditorSurfaceAndBindingFailClosed(t *testing.T) {
	root := mustPackageRoot(t)
	lspFixture := minimalLSPFixture(t)
	assertMinimalEditorSurface(t, root, lspFixture)

	t.Run("missing explicit binding", func(t *testing.T) {
		cfg := smoke.Config{
			Vim: requireVim(t), Vim9LSP: lspFixture, PluginRoot: root,
			Profile: "local", Buffer: filepath.Join(t.TempDir(), "draft.hqjson"),
			Headless: true, StartOnly: true, OmitHQBin: true,
		}
		if err := smoke.Run(cfg); err == nil {
			t.Fatal("expected missing g:hq_bin to fail")
		}
	})

	t.Run("relative binding", func(t *testing.T) {
		relativeDir := filepath.Join(root, ".tmp", "relative-hq-test")
		if err := os.MkdirAll(relativeDir, 0o755); err != nil {
			t.Fatal(err)
		}
		defer os.RemoveAll(relativeDir)
		relative := filepath.Join(".tmp", "relative-hq-test", exeName("hqstub"))
		if err := os.WriteFile(filepath.Join(root, relative), []byte("not executed"), 0o755); err != nil {
			t.Fatal(err)
		}
		cfg := smoke.Config{
			HQBin: relative, Vim: requireVim(t), Vim9LSP: lspFixture,
			PluginRoot: root, Profile: "local", Buffer: filepath.Join(t.TempDir(), "draft.hqjson"),
			Headless: true, StartOnly: true,
		}
		if err := smoke.Run(cfg); err == nil {
			t.Fatal("expected relative g:hq_bin to fail")
		}
	})

	t.Run("non executable binding", func(t *testing.T) {
		path := filepath.Join(t.TempDir(), "hq")
		if err := os.WriteFile(path, []byte("not executable"), 0o644); err != nil {
			t.Fatal(err)
		}
		cfg := smoke.Config{
			HQBin: path, Vim: requireVim(t), Vim9LSP: lspFixture,
			PluginRoot: root, Profile: "local", Buffer: filepath.Join(t.TempDir(), "draft.hqjson"),
			Headless: true, StartOnly: true,
		}
		if err := smoke.Run(cfg); err == nil {
			t.Fatal("expected non-executable g:hq_bin to fail")
		}
	})
}

type choiceE2ECase struct {
	query      string
	label      string
	want       string
	detail     string
	docPreview string
	fileFormat string
	first      bool
	contains   string
}

// TestAgentDefaultChoiceE2E fixes one pre-effect UX decision: an empty command
// query puts the selected world's default AI-agent command first, while the
// explicit direct fallback remains visible. Completion writes no durable row.
func TestAgentDefaultChoiceE2E(t *testing.T) {
	runChoiceE2E(t, choiceE2ECase{
		query: "@", label: "agent.exec", want: "@agent.exec\nprompt=",
		detail:     "schema_template | world declaration",
		docPreview: "Preview:\n@agent.exec\nprompt=",
		fileFormat: "unix", first: true, contains: "direct.open",
	})
}

// TestAgentPromptFieldChoiceE2E fixes the next independent editor step after
// choosing the Agent command: the real LSP completes its required prompt field,
// and completion still has no durable effect.
func TestAgentPromptFieldChoiceE2E(t *testing.T) {
	runChoiceE2E(t, choiceE2ECase{
		query: "@agent.exec\npr", label: "prompt", want: "@agent.exec\nprompt=",
		detail:     "missing_key | string | world declaration",
		docPreview: "Preview:\nprompt=",
		fileFormat: "unix",
	})
}

// TestDirectFallbackChoiceE2E fixes the separate business fallback step:
// after an explicit direct command, the real LSP completes its required path
// field. The Agent default is bypassed and completion writes no durable row.
func TestDirectFallbackChoiceE2E(t *testing.T) {
	runChoiceE2E(t, choiceE2ECase{
		query: "@direct.open\npa", label: "path", want: "@direct.open\npath=",
		detail:     "missing_key | path | world declaration",
		docPreview: "Preview:\npath=",
		fileFormat: "unix",
	})
}

// TestUnicodeDirectFieldValueE2E fixes only the negotiated text-edit boundary:
// Japanese, emoji, a combining mark, and CRLF are applied by the real native
// popup, and one native undo restores the exact original query.
func TestUnicodeDirectFieldValueE2E(t *testing.T) {
	runChoiceE2E(t, choiceE2ECase{
		query: "@direct.open\npath=日😀éj", label: "日本語-😀-é.jsonl",
		want:       "@direct.open\npath=日本語-😀-é.jsonl",
		detail:     "field_value | sources: field.example | world declaration",
		docPreview: "Preview:\n日本語-😀-é.jsonl",
		fileFormat: "dos",
	})
}

func runChoiceE2E(t *testing.T, tc choiceE2ECase) {
	t.Helper()
	if os.Getenv("HQ_CHOICE_E2E") != "1" {
		t.Skip("set HQ_CHOICE_E2E=1 and run under a real terminal")
	}
	hqBin := os.Getenv("HQ_BIN")
	if hqBin == "" {
		t.Fatal("HQ_BIN is required for the real-hq choice E2E")
	}
	root := mustPackageRoot(t)
	profileEnv, accepted := prepareStrictHQProfile(t, root, "local")
	artifact := filepath.Join(t.TempDir(), "native-hq-popup.json")
	cfg := smoke.Config{
		HQBin: hqBin, Vim: requireVim(t), Vim9LSP: requireVim9LSP(t), PluginRoot: root,
		Profile: "local", Buffer: filepath.Join(t.TempDir(), "native-hq-popup.hqjson"),
		CompletionText: tc.query, ExpectedCompletionLabel: tc.label, ExpectedCompletionText: tc.want,
		NativePopupFileFormat: tc.fileFormat, NativePopupArtifact: artifact,
		Env: profileEnv, Timeout: 15 * time.Second,
		CaptureReadyPath: os.Getenv("HQ_PTY_CAPTURE_READY"),
		CaptureDonePath:  os.Getenv("HQ_PTY_CAPTURE_DONE"),
	}
	if err := smoke.Run(cfg); err != nil {
		artifactBody, _ := os.ReadFile(artifact)
		t.Fatalf("native real-hq choice E2E failed: %v\nartifact: %s", err, artifactBody)
	}
	var result struct {
		Status                 string   `json:"status"`
		Failure                string   `json:"failure"`
		CandidateDetail        string   `json:"candidate_detail"`
		CandidateDocumentation string   `json:"candidate_documentation"`
		Lines                  []string `json:"lines"`
		UndoLines              []string `json:"undo_lines"`
		DocumentationPopup     []string `json:"documentation_popup"`
		FileFormat             string   `json:"fileformat"`
		Items                  []struct {
			Word string `json:"word"`
			Abbr string `json:"abbr"`
		} `json:"items"`
	}
	body, err := os.ReadFile(artifact)
	if err != nil {
		t.Fatal(err)
	}
	if err := json.Unmarshal(body, &result); err != nil {
		t.Fatalf("decode popup artifact: %v\n%s", err, body)
	}
	if result.Status != "passed" || result.Failure != "" {
		t.Fatalf("native popup result = %#v", result)
	}
	if strings.Join(result.Lines, "\n") != tc.want || strings.Join(result.UndoLines, "\n") != tc.query {
		t.Fatalf("native edit/undo result = %#v", result)
	}
	if result.CandidateDetail != tc.detail || !strings.Contains(result.CandidateDocumentation, tc.docPreview) {
		t.Fatalf("native detail/documentation result = %#v", result)
	}
	if strings.Join(result.DocumentationPopup, "\n") != result.CandidateDocumentation || result.FileFormat != tc.fileFormat {
		t.Fatalf("native documentation/format result = %#v", result)
	}
	if tc.first {
		if len(result.Items) == 0 || (!strings.Contains(result.Items[0].Word, tc.label) && result.Items[0].Abbr != tc.label) {
			t.Fatalf("expected candidate is not first: %#v", result.Items)
		}
	}
	if tc.contains != "" {
		found := false
		for _, item := range result.Items {
			if strings.Contains(item.Word, tc.contains) || item.Abbr == tc.contains {
				found = true
				break
			}
		}
		if !found {
			t.Fatalf("fallback candidate %q is not visible: %#v", tc.contains, result.Items)
		}
	}
	if acceptedBody, err := os.ReadFile(accepted); err != nil || strings.TrimSpace(string(acceptedBody)) != "" {
		t.Fatalf("completion changed durable accepted history: err=%v body=%s", err, acceptedBody)
	}
}

// TestAgentDecisionSubmitE2E fixes the next distinct UX boundary after choice:
// one explicit HqSubmit queues exactly one typed task for the default agent. It
// does not execute the provider or duplicate worker/policy E2Es.
func TestAgentDecisionSubmitE2E(t *testing.T) {
	hqBin := os.Getenv("HQ_BIN")
	if hqBin == "" {
		t.Skip("HQ_BIN is required")
	}
	root := mustPackageRoot(t)
	profileEnv, accepted := prepareStrictHQProfile(t, root, "local")
	resultPath := filepath.Join(t.TempDir(), "agent-submit.json")
	prompt := "inspect-change"
	cfg := smoke.Config{
		HQBin: hqBin, Vim: requireVim(t), Vim9LSP: requireVim9LSP(t), PluginRoot: root,
		Profile: "local", Buffer: filepath.Join(t.TempDir(), "agent-submit.hqjson"),
		BufferText: "@agent.exec\nprompt=" + prompt, Headless: true, Env: profileEnv,
		ResultPath: resultPath,
	}
	if err := smoke.Run(cfg); err != nil {
		t.Fatalf("agent decision submit E2E failed: %v", err)
	}
	rows := readJSONLRows(t, accepted)
	if len(rows) != 1 || rows[0]["kind"] != "accepted.instruction" {
		t.Fatalf("accepted rows=%#v", rows)
	}
	instruction, ok := rows[0]["instruction"].(map[string]any)
	if !ok || instruction["target"] != "codex" || instruction["op"] != "run" {
		t.Fatalf("agent instruction=%#v", instruction)
	}
	payload, ok := instruction["payload"].(map[string]any)
	if !ok || payload["action"] != "exec" || payload["prompt"] != prompt {
		t.Fatalf("agent payload=%#v", payload)
	}
	result := readJSONObject(t, resultPath)
	if result["kind"] != "hq.submitResult.v1" || result["status"] != "queued" || result["queueId"] != instruction["id"] {
		t.Fatalf("agent submit result=%#v", result)
	}
}

// TestAcceptedSubmitKeepsDraftOnUnsafeConsumption fixes the editor's only
// failure policy: acceptance remains durable, but a stale or malformed
// consumption projection must never destroy the newer draft.
func TestAcceptedSubmitKeepsDraftOnUnsafeConsumption(t *testing.T) {
	root := mustPackageRoot(t)
	lspFixture := minimalLSPFixture(t)
	for _, tc := range []struct {
		name         string
		plan         string
		newerEdit    string
		wantOutcome  string
		wantComplete string
	}{
		{
			name:        "newer local edit",
			plan:        "{draftConsumption: {kind: 'hq.draftConsumption.v1', textDocument: {uri: uri, version: submittedTick}, edits: [{range: {start: {line: 0, character: 0}, end: {line: 1, character: 8}}, newText: ''}]}}",
			newerEdit:   "setline(1, '@direct.open.newer')",
			wantOutcome: "newer-draft-kept", wantComplete: "@direct.open.newer\npath=old",
		},
		{
			name:        "invalid consumption plan",
			plan:        "{draftConsumption: {kind: 'hq.draftConsumption.v1', textDocument: {uri: uri, version: submittedTick}, edits: [{range: {start: {line: 999, character: 0}, end: {line: 999, character: 0}}, newText: ''}]}}",
			wantOutcome: "invalid-plan", wantComplete: "@direct.open\npath=old",
		},
	} {
		t.Run(tc.name, func(t *testing.T) {
			resultPath := filepath.Join(t.TempDir(), "draft-guard.json")
			lines := []string{
				"vim9script",
				"execute 'set runtimepath^=' .. fnameescape(" + vimLiteral(lspFixture) + ")",
				"execute 'set runtimepath^=' .. fnameescape(" + vimLiteral(root) + ")",
				"import autoload 'hq.vim' as hq",
				"new", "setline(1, ['@direct.open', 'path=old'])", "feedkeys(\"\\<Esc>\", 'xt')",
				"var submittedTick = b:changedtick", "var uri = 'file:///draft-guard.hqjson'",
				"var accepted = " + tc.plan,
			}
			if tc.newerEdit != "" {
				lines = append(lines, tc.newerEdit)
			}
			lines = append(lines,
				"var outcome = hq.ConsumeAcceptedDraft(accepted, bufnr(), uri, submittedTick, submittedTick)",
				"writefile([json_encode({outcome: outcome, lines: getline(1, '$')})], "+vimLiteral(resultPath)+")", "qa!",
			)
			script := strings.Join(lines, "\n") + "\n"
			scriptPath := filepath.Join(t.TempDir(), "draft-guard.vim")
			if err := os.WriteFile(scriptPath, []byte(script), 0o600); err != nil {
				t.Fatal(err)
			}
			if output, err := exec.Command(requireVim(t), "--clean", "-Nu", "NONE", "-n", "-es", "-S", scriptPath).CombinedOutput(); err != nil {
				t.Fatalf("draft-guard Vim failed: %v\n%s\n%s", err, output, script)
			}
			var proof struct {
				Outcome string   `json:"outcome"`
				Lines   []string `json:"lines"`
			}
			body, err := os.ReadFile(resultPath)
			if err != nil {
				t.Fatal(err)
			}
			if err := json.Unmarshal(body, &proof); err != nil {
				t.Fatal(err)
			}
			if proof.Outcome != tc.wantOutcome || strings.Join(proof.Lines, "\n") != tc.wantComplete {
				t.Fatalf("draft guard proof=%#v", proof)
			}
		})
	}
}

func assertMinimalEditorSurface(t *testing.T, root, lspFixture string) {
	t.Helper()
	resultPath := filepath.Join(t.TempDir(), "surface.json")
	script := strings.Join([]string{
		"set nocompatible", "set noswapfile",
		"execute 'set runtimepath^=' . fnameescape(" + vimLiteral(lspFixture) + ")",
		"execute 'set runtimepath^=' . fnameescape(" + vimLiteral(root) + ")",
		"runtime plugin/lsp.vim", "runtime plugin/hq.vim",
		"call writefile([json_encode({'start': exists(':HqStart'), 'submit': exists(':HqSubmit'), 'doctor': exists(':HqDoctor'), 'complete': exists(':HqComplete')})], " + vimLiteral(resultPath) + ")",
		"qa!",
	}, "\n") + "\n"
	scriptPath := filepath.Join(t.TempDir(), "surface.vim")
	if err := os.WriteFile(scriptPath, []byte(script), 0o600); err != nil {
		t.Fatal(err)
	}
	if output, err := exec.Command(requireVim(t), "--clean", "-Nu", "NONE", "-n", "-es", "-S", scriptPath).CombinedOutput(); err != nil {
		t.Fatalf("surface Vim failed: %v\n%s", err, output)
	}
	var got struct{ Start, Submit, Doctor, Complete int }
	body, err := os.ReadFile(resultPath)
	if err != nil {
		t.Fatal(err)
	}
	if err := json.Unmarshal(body, &got); err != nil {
		t.Fatal(err)
	}
	if got.Start != 2 || got.Submit != 2 || got.Doctor != 2 || got.Complete != 0 {
		t.Fatalf("unexpected editor command surface: %#v", got)
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

func minimalLSPFixture(t *testing.T) string {
	t.Helper()
	root := t.TempDir()
	files := map[string]string{
		"plugin/lsp.vim": `vim9script

def g:LspAddServer(servers: list<dict<any>>)
enddef

def g:LspOptionsSet(options: dict<any>)
enddef

def g:LspEnable()
enddef

def g:LspServerReady(): bool
  return false
enddef
`,
		"autoload/lsp/buffer.vim": `vim9script
export def CurbufGetServerByName(name: string): dict<any>
  return {}
enddef
`,
		"autoload/lsp/completion.vim": `vim9script
export def LspComplete(force: bool)
enddef
`,
		"autoload/lsp/util.vim": `vim9script
export def LspBufnrToUri(bnr: number): string
  return 'file:///fixture.hqjson'
enddef
`,
		"autoload/lsp/offset.vim": `vim9script
export def EncodePosition(server: dict<any>, bnr: number, position: dict<number>)
enddef
export def EncodeRange(server: dict<any>, bnr: number, range: dict<dict<number>>)
enddef
`,
		"autoload/lsp/textedit.vim": `vim9script
export def ApplyTextEdits(bnr: number, edits: list<dict<any>>)
enddef
`,
	}
	for relative, body := range files {
		path := filepath.Join(root, filepath.FromSlash(relative))
		if err := os.MkdirAll(filepath.Dir(path), 0o755); err != nil {
			t.Fatal(err)
		}
		if err := os.WriteFile(path, []byte(body), 0o600); err != nil {
			t.Fatal(err)
		}
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
		"kind": "hq.profile.v1", "name": profile, "deployment_id": "hq-vim-agent-first-proof",
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
