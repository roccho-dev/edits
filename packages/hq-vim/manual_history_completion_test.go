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

func TestNativeHQManualEmptyDraftAcceptedHistory(t *testing.T) {
	if os.Getenv("HQ_NATIVE_HQ_FUZZY_PROOF") != "1" {
		t.Skip("set HQ_NATIVE_HQ_FUZZY_PROOF=1 and run under a real terminal")
	}
	hqBin := os.Getenv("HQ_BIN")
	if hqBin == "" || !filepath.IsAbs(hqBin) {
		t.Fatalf("HQ_BIN must be an absolute current hq binary: %q", hqBin)
	}
	root := mustPackageRoot(t)
	profileEnv, acceptedPath := prepareStrictHQProfile(t, root, "local")
	enableHistoryPolicy(t, filepath.Join(filepath.Dir(acceptedPath), "world.jsonl"))

	const materialized = "@queue.create\npath=recent-safe.jsonl"
	if err := smoke.Run(smoke.Config{
		HQBin: hqBin, Vim: requireVim(t), Vim9LSP: requireVim9LSP(t),
		PluginRoot: root, Profile: "local", Buffer: filepath.Join(t.TempDir(), "seed.hqjson"),
		BufferText: materialized, Headless: true, Env: profileEnv,
	}); err != nil {
		t.Fatalf("seed accepted_input through explicit submit: %v", err)
	}
	rows := readJSONLRows(t, acceptedPath)
	if len(rows) != 1 {
		t.Fatalf("seed accepted rows = %d, want 1", len(rows))
	}
	input, ok := rows[0]["accepted_input"].(map[string]any)
	if !ok || input["recall_complete"] != true {
		t.Fatalf("seed lacks complete safe accepted_input: %#v", rows[0])
	}

	bufferPath := filepath.Join(t.TempDir(), "canonical-empty.hqjson")
	if err := os.WriteFile(bufferPath, nil, 0o600); err != nil {
		t.Fatal(err)
	}
	proofPath := filepath.Join(t.TempDir(), "history-popup.json")
	scriptPath := writeHistoryPopupScript(t, root, requireVim9LSP(t), hqBin, bufferPath, proofPath)
	vimLog := filepath.Join(t.TempDir(), "vim.log")
	cmd := exec.Command(requireVim(t), "--clean", "-Nu", "NONE", "-n", "-V1"+filepath.ToSlash(vimLog), "-S", filepath.ToSlash(scriptPath))
	cmd.Env = withOverrides(os.Environ(), profileEnv)
	cmd.Stdout, cmd.Stderr, cmd.Stdin = os.Stdout, os.Stderr, os.Stdin
	if err := cmd.Run(); err != nil {
		proof, _ := os.ReadFile(proofPath)
		log, _ := os.ReadFile(vimLog)
		t.Fatalf("empty-draft accepted-history popup failed: %v\nproof=%s\nvim=%s", err, proof, log)
	}

	var proof struct {
		Status, Failure, Detail, Documentation string
		Lines, Undo, Popup                     []string
	}
	body, err := os.ReadFile(proofPath)
	if err != nil {
		t.Fatal(err)
	}
	if err := json.Unmarshal(body, &proof); err != nil {
		t.Fatalf("decode history popup proof: %v\n%s", err, body)
	}
	if proof.Status != "passed" || proof.Failure != "" {
		t.Fatalf("history popup proof = %#v", proof)
	}
	if strings.Join(proof.Lines, "\n") != materialized {
		t.Fatalf("history materialization = %#v", proof.Lines)
	}
	if len(proof.Undo) != 1 || proof.Undo[0] != "" {
		t.Fatalf("one undo did not restore canonical empty draft: %#v", proof.Undo)
	}
	if proof.Detail != "object_preset | accepted history" {
		t.Fatalf("history detail = %q", proof.Detail)
	}
	for _, want := range []string{"Accepted history", "Preview:\n" + materialized} {
		if !strings.Contains(proof.Documentation, want) {
			t.Fatalf("history documentation missing %q: %q", want, proof.Documentation)
		}
	}
	if strings.Join(proof.Popup, "\n") != proof.Documentation {
		t.Fatalf("native documentation popup is not complete: %#v", proof)
	}
	if got := len(readJSONLRows(t, acceptedPath)); got != 1 {
		t.Fatalf("completion or selection appended accepted rows: %d", got)
	}
	writeHistoryConformanceArtifact(t, proof)
}

func enableHistoryPolicy(t *testing.T, path string) {
	t.Helper()
	body, err := os.ReadFile(path)
	if err != nil {
		t.Fatal(err)
	}
	before := `"required":true,"description":"context JSONL path"`
	after := `"required":true,"history_policy":"search","description":"context JSONL path"`
	updated := strings.Replace(string(body), before, after, 1)
	if updated == string(body) {
		t.Fatal("history policy insertion point not found")
	}
	if err := os.WriteFile(path, []byte(updated), 0o600); err != nil {
		t.Fatal(err)
	}
}

func writeHistoryPopupScript(t *testing.T, root, lspRoot, hqBin, bufferPath, proofPath string) string {
	t.Helper()
	q := func(value string) string { b, _ := json.Marshal(filepath.ToSlash(value)); return string(b) }
	expected, _ := json.Marshal([]string{"@queue.create", "path=recent-safe.jsonl"})
	lines := []string{
		"set nocompatible", "set noswapfile",
		"execute 'set runtimepath^=' . fnameescape(" + q(lspRoot) + ")",
		"execute 'set runtimepath^=' . fnameescape(" + q(root) + ")",
		"runtime plugin/lsp.vim", "runtime plugin/hq.vim",
		"let g:hq_bin = " + q(hqBin), "let g:hq_profile = 'local'",
		"execute 'edit ' . fnameescape(" + q(bufferPath) + ")", "set filetype=hqjson",
		"let g:hq_history_expected = " + string(expected),
		"let g:hq_history_deadline = reltimefloat(reltime()) + 10.0",
		"let g:hq_history_index = -1", "let g:hq_history_lines = []", "let g:hq_history_undo = []",
		"let g:hq_history_detail = ''", "let g:hq_history_doc = ''", "let g:hq_history_popup = []",
		"function! HqHistoryFinish(status, failure) abort",
		"  call writefile([json_encode({'Status': a:status, 'Failure': a:failure, 'Detail': g:hq_history_detail, 'Documentation': g:hq_history_doc, 'Lines': g:hq_history_lines, 'Undo': g:hq_history_undo, 'Popup': g:hq_history_popup})], " + q(proofPath) + ")",
		"  if a:status ==# 'passed' | qa! | else | cquit 46 | endif", "endfunction",
		"function! HqHistoryVerify(timer) abort",
		"  if getline(1, '$') !=# g:hq_history_expected | call HqHistoryFinish('failed', 'selected edit mismatch') | return | endif",
		"  let g:hq_history_lines = getline(1, '$')", "  silent undo", "  let g:hq_history_undo = getline(1, '$')",
		"  if g:hq_history_undo !=# [''] | call HqHistoryFinish('failed', 'one undo mismatch') | return | endif",
		"  call HqHistoryFinish('passed', '')", "endfunction",
		"function! HqHistoryObserve(timer) abort",
		"  if reltimefloat(reltime()) >= g:hq_history_deadline | call HqHistoryFinish('failed', 'documentation timeout') | return | endif",
		"  let l:info = complete_info(['items', 'selected'])",
		"  if get(l:info, 'selected', -1) != g:hq_history_index | call timer_start(20, function('HqHistoryObserve')) | return | endif",
		"  let l:item = l:info.items[g:hq_history_index]", "  let l:data = get(l:item, 'user_data', {})",
		"  let g:hq_history_detail = type(l:data) == v:t_dict ? get(l:data, 'detail', '') : ''",
		"  let l:doc = type(l:data) == v:t_dict ? get(l:data, 'documentation', '') : ''",
		"  if type(l:doc) == v:t_dict | let l:doc = get(l:doc, 'value', '') | endif",
		"  let g:hq_history_doc = type(l:doc) == v:t_string ? l:doc : ''",
		"  let l:popup = popup_findinfo()",
		"  if l:popup <= 0 | call timer_start(20, function('HqHistoryObserve')) | return | endif",
		"  let g:hq_history_popup = getbufline(winbufnr(l:popup), 1, '$')",
		"  if g:hq_history_popup !=# split(g:hq_history_doc, \"\\n\", 1) | call HqHistoryFinish('failed', 'documentation popup mismatch') | return | endif",
		"  call feedkeys(\"\\<C-Y>\\<Esc>\", 'n')", "  call timer_start(100, function('HqHistoryVerify'))", "endfunction",
		"function! HqHistoryPoll(timer) abort",
		"  if reltimefloat(reltime()) >= g:hq_history_deadline | call HqHistoryFinish('failed', 'native popup timeout') | return | endif",
		"  let l:info = complete_info(['items'])",
		"  if !pumvisible() || empty(l:info.items) | call timer_start(20, function('HqHistoryPoll')) | return | endif",
		"  let l:index = -1",
		"  for l:i in range(len(l:info.items))",
		"    let l:item = l:info.items[l:i] | let l:data = get(l:item, 'user_data', {})",
		"    if type(l:data) == v:t_dict && get(l:data, 'detail', '') ==# 'object_preset | accepted history' | let l:index = l:i | break | endif",
		"  endfor",
		"  if l:index < 0 | call HqHistoryFinish('failed', 'accepted-history preset absent') | return | endif",
		"  let g:hq_history_index = l:index", "  call feedkeys(repeat(\"\\<C-N>\", l:index + 1), 'n')",
		"  call timer_start(20, function('HqHistoryObserve'))", "endfunction",
		"function! HqHistoryComplete(timer) abort",
		"  if mode(1) !~# '^i' | call timer_start(20, function('HqHistoryComplete')) | return | endif",
		"  try | call g:HqVimComplete() | catch | call HqHistoryFinish('failed', v:exception) | return | endtry",
		"  call timer_start(20, function('HqHistoryPoll'))", "endfunction",
		"HqStart",
		"let g:hq_ready_deadline = reltimefloat(reltime()) + 10.0",
		"while !g:LspServerReady() && reltimefloat(reltime()) < g:hq_ready_deadline | sleep 10m | endwhile",
		"if !g:LspServerReady() | cquit 43 | endif",
		"call cursor(1, 1)", "call feedkeys('i', 'n')", "call timer_start(20, function('HqHistoryComplete'))",
	}
	path := filepath.Join(t.TempDir(), "history-popup.vim")
	if err := os.WriteFile(path, []byte(strings.Join(lines, "\n")+"\n"), 0o600); err != nil {
		t.Fatal(err)
	}
	return path
}

func withOverrides(base []string, overrides map[string]string) []string {
	out := append([]string(nil), base...)
	for key, value := range overrides {
		matched := false
		for i, entry := range out {
			name, _, _ := strings.Cut(entry, "=")
			if name == key || (runtime.GOOS == "windows" && strings.EqualFold(name, key)) {
				out[i], matched = key+"="+value, true
			}
		}
		if !matched { out = append(out, key+"="+value) }
	}
	return out
}

func writeHistoryConformanceArtifact(t *testing.T, proof any) {
	t.Helper()
	base := os.Getenv("HQ_CONFORMANCE_ARTIFACT")
	if base == "" { return }
	body, err := json.MarshalIndent(map[string]any{
		"kind": "edits.hqVimAcceptedHistoryConformance.v1", "status": "passed",
		"hqSourceSha": os.Getenv("HQ_CANONICAL_SOURCE_SHA"),
		"manualOperation": "HqComplete -> yegappan/lsp LspComplete(true)",
		"completionWrites": 0, "explicitSeedRows": 1, "proof": proof,
	}, "", "  ")
	if err != nil { t.Fatal(err) }
	path := filepath.Join(filepath.Dir(base), "hq-vim-accepted-history-"+runtime.GOOS+".json")
	if err := os.WriteFile(path, append(body, '\n'), 0o600); err != nil { t.Fatal(err) }
}
