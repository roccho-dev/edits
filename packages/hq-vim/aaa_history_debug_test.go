package main

import (
	"encoding/json"
	"os"
	"os/exec"
	"path/filepath"
	"testing"

	"github.com/roccho-dev/edits/packages/hq-vim/internal/smoke"
)

func TestDebugEmptyDraftAcceptedHistoryResponse(t *testing.T) {
	if os.Getenv("HQ_NATIVE_HQ_FUZZY_PROOF") != "1" {
		t.Skip("debug capture runs only in the exact native conformance matrix")
	}
	hqBin := os.Getenv("HQ_BIN")
	root := mustPackageRoot(t)
	env, accepted := prepareStrictHQProfile(t, root, "local")
	enableHistoryPolicy(t, filepath.Join(filepath.Dir(accepted), "world.jsonl"))
	if err := smoke.Run(smoke.Config{HQBin: hqBin, Vim: requireVim(t), Vim9LSP: requireVim9LSP(t), PluginRoot: root, Profile: "local", Buffer: filepath.Join(t.TempDir(), "seed.hqjson"), BufferText: "@queue.create\npath=recent-safe.jsonl", Headless: true, Env: env}); err != nil {
		t.Fatal(err)
	}
	buffer := filepath.Join(t.TempDir(), "empty.hqjson")
	if err := os.WriteFile(buffer, nil, 0o600); err != nil { t.Fatal(err) }
	response := filepath.Join(t.TempDir(), "response.json")
	q := func(value string) string { b, _ := json.Marshal(filepath.ToSlash(value)); return string(b) }
	script := "set nocompatible\nset noswapfile\n" +
		"execute 'set runtimepath^=' . fnameescape(" + q(requireVim9LSP(t)) + ")\n" +
		"execute 'set runtimepath^=' . fnameescape(" + q(root) + ")\n" +
		"runtime plugin/lsp.vim\nruntime plugin/hq.vim\n" +
		"let g:hq_bin = " + q(hqBin) + "\nlet g:hq_profile = 'local'\n" +
		"execute 'edit ' . fnameescape(" + q(buffer) + ")\nset filetype=hqjson\nHqStart\n" +
		"let deadline = reltimefloat(reltime()) + 10.0\nwhile !g:LspServerReady() && reltimefloat(reltime()) < deadline | sleep 10m | endwhile\n" +
		"if !g:LspServerReady() | cquit 43 | endif\n" +
		"let response = g:HqVimCompletionRequest()\ncall writefile([json_encode(response)], " + q(response) + ")\nqa!\n"
	scriptPath := filepath.Join(t.TempDir(), "response.vim")
	if err := os.WriteFile(scriptPath, []byte(script), 0o600); err != nil { t.Fatal(err) }
	cmd := exec.Command(requireVim(t), "--clean", "-Nu", "NONE", "-n", "-es", "-S", filepath.ToSlash(scriptPath))
	cmd.Env = withOverrides(os.Environ(), env)
	if output, err := cmd.CombinedOutput(); err != nil { t.Fatalf("raw response Vim failed: %v\n%s", err, output) }
	responseBody, _ := os.ReadFile(response)
	acceptedBody, _ := os.ReadFile(accepted)
	t.Fatalf("DEBUG accepted=%s\nresponse=%s", acceptedBody, responseBody)
}
