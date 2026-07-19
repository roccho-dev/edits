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

func TestNativeHQManualEmptyDraftAcceptedHistory(t *testing.T) {
	if os.Getenv("HQ_NATIVE_HQ_FUZZY_PROOF") != "1" {
		t.Skip("set HQ_NATIVE_HQ_FUZZY_PROOF=1 and run under a real terminal")
	}
	hqBin := os.Getenv("HQ_BIN")
	if hqBin == "" {
		t.Fatal("HQ_BIN is required for the accepted-history native popup proof")
	}
	if !filepath.IsAbs(hqBin) {
		t.Fatalf("HQ_BIN must be absolute: %q", hqBin)
	}

	root := mustPackageRoot(t)
	profileEnv, acceptedPath := prepareStrictHQProfile(t, root, "local")
	enableSafeHistoryPolicy(t, filepath.Join(filepath.Dir(acceptedPath), "world.jsonl"))

	const submitted = "@queue.create\npath=recent-safe.jsonl"
	seedCfg := smoke.Config{
		HQBin:      hqBin,
		Vim:        requireVim(t),
		Vim9LSP:    requireVim9LSP(t),
		PluginRoot: root,
		Profile:    "local",
		Buffer:     filepath.Join(t.TempDir(), "history-seed.hqjson"),
		BufferText: submitted,
		Headless:   true,
		Env:        profileEnv,
	}
	if err := smoke.Run(seedCfg); err != nil {
		t.Fatalf("seed accepted history through explicit submit: %v", err)
	}
	rows := readJSONLRows(t, acceptedPath)
	if len(rows) != 1 {
		t.Fatalf("accepted rows after seed = %d, want 1", len(rows))
	}
	if _, ok := rows[0]["accepted_input"].(map[string]any); !ok {
		t.Fatalf("seed row has no provenance-safe accepted_input: %#v", rows[0])
	}

	proofPath := filepath.Join(t.TempDir(), "manual-history-popup.json")
	bufferPath := filepath.Join(t.TempDir(), "empty-history.hqjson")
	if err := os.WriteFile(bufferPath, nil, 0o600); err != nil {
		t.Fatal(err)
	}
	scriptPath := writeManualHistoryVimScript(t, root, hqBin, requireVim9LSP(t), bufferPath, proofPath)
	vimLog := filepath.Join(t.TempDir(), "vim.log")
	cmd := exec.Command(requireVim(t), "--clean", "-Nu", "NONE", "-n", "-V1"+filepath.ToSlash(vimLog), "-S", filepath.ToSlash(scriptPath))
	cmd.Env = envWithOverrides(os.Environ(), profileEnv)
	cmd.Stdout = os.Stdout
	cmd.Stderr = os.Stderr
	cmd.Stdin = os.Stdin
	if err := cmd.Run(); err != nil {
		log, _ := os.ReadFile(vimLog)
		proof, _ := os.ReadFile(proofPath)
		t.Fatalf("manual accepted-history Vim proof failed: %v\nproof=%s\nvim=%s", err, proof, log)
	}

	var proof struct {
		Status                 string   `json:"status"`
		Failure                string   `json:"failure"`
		Lines                  []string `json:"lines"`
		UndoLines              []string `json:"undo_lines"`
		CandidateDetail        string   `json:"candidate_detail"`
		CandidateDocumentation string   `json:"candidate_documentation"`
		DocumentationPopup     []string `json:"documentation_popup"`
	}
	body, err := os.ReadFile(proofPath)
	if err != nil {
		t.Fatal(err)
	}
	if err := json.Unmarshal(body, &proof); err != nil {
		t.Fatalf("decode manual history proof: %v\n%s", err, body)
	}
	if proof.Status != "passed" || proof.Failure != "" {
		t.Fatalf("manual history proof = %#v", proof)
	}
	if got := strings.Join(proof.Lines, "\n"); got != submitted {
		t.Fatalf("accepted-history materialization = %q, want %q", got, submitted)
	}
	if len(proof.UndoLines) != 1 || proof.UndoLines[0] != "" {
		t.Fatalf("one native undo did not restore canonical empty draft: %#v", proof.UndoLines)
	}
	if proof.CandidateDetail != "object_preset | accepted history" {
		t.Fatalf("candidate detail = %q", proof.CandidateDetail)
	}
	for _, want := range []string{"Accepted history", "Preview:\n" + submitted} {
		if !strings.Contains(proof.CandidateDocumentation, want) {
			t.Fatalf("candidate documentation missing %q: %q", want, proof.CandidateDocumentation)
		}
	}
	if strings.Join(proof.DocumentationPopup, "\n") != proof.CandidateDocumentation {
		t.Fatalf("native documentation popup differs from server documentation: %#v", proof)
	}
	if got := len(readJSONLRows(t, acceptedPath)); got != 1 {
		t.Fatalf("manual completion/selection appended accepted rows: got %d want 1", got)
	}

	writeManualHistoryArtifact(t, proof, hqBin)
}

func enableSafeHistoryPolicy(t *testing.T, worldPath string) {
	t.Helper()
	body, err := os.ReadFile(worldPath)
	if err != nil {
		t.Fatal(err)
	}
	const before = `"required":true,"description":"context JSONL path"`
	const after = `"required":true,"history_policy":"search","description":"context JSONL path"`
	updated := strings.Replace(string(body), before, after, 1)
	if updated == string(body) {
		t.Fatal("strict world history-policy insertion point not found")
	}
	if err := os.WriteFile(worldPath, []byte(updated), 0o600); err != nil {
		t.Fatal(err)
	}
}

func writeManualHistoryVimScript(t *testing.T, root, hqBin, lspRoot, bufferPath, proofPath string) string {
	t.Helper()
	q := func(value string) string {
		encoded, _ := json.Marshal(filepath.ToSlash(value))
		return string(encoded)
	}
	expected := []string{"@queue.create", "path=recent-safe.jsonl"}
	expectedJSON, _ := json.Marshal(expected)
	lines := []string{
		"set nocompatible",
		"set noswapfile",
		"execute 'set runtimepath^=' . fnameescape(" + q(lspRoot) + ")",
		"execute 'set runtimepath^=' . fnameescape(" + q(root) + ")",
		"runtime plugin/lsp.vim",
		"runtime plugin/hq.vim",
		"let g:hq_bin = " + q(hqBin),
		"let g:hq_profile = 'local'",
		"execute 'edit ' . fnameescape(" + q(bufferPath) + ")",
		"set filetype=hqjson",
		"HqStart",
		"let g:hq_history_ready_deadline = reltimefloat(reltime()) + 10.0",
		"while !g:LspServerReady() && reltimefloat(reltime()) < g:hq_history_ready_deadline",
		"  sleep 10m",
		"endwhile",
		"if !g:LspServerReady() | cquit 43 | endif",
		"let g:hq_history_deadline = reltimefloat(reltime()) + 10.0",
		"let g:hq_history_expected = " + string(expectedJSON),
		"let g:hq_history_selected = -1",
		"let g:hq_history_lines = []",
		"let g:hq_history_undo_lines = []",
		"let g:hq_history_detail = ''",
		"let g:hq_history_documentation = ''",
		"let g:hq_history_documentation_popup = []",
		"function! HqHistoryFinish(status, failure) abort",
		"  call writefile([json_encode({'status': a:status, 'failure': a:failure, 'lines': g:hq_history_lines, 'undo_lines': g:hq_history_undo_lines, 'candidate_detail': g:hq_history_detail, 'candidate_documentation': g:hq_history_documentation, 'documentation_popup': g:hq_history_documentation_popup})], " + q(proofPath) + ")",
		"  if a:status ==# 'passed' | qa! | else | cquit 46 | endif",
		"endfunction",
		"function! HqHistoryVerify(timer) abort",
		"  if getline(1, '$') !=# g:hq_history_expected",
		"    call HqHistoryFinish('failed', 'accepted-history edit differs from expected object')",
		"    return",
		"  endif",
		"  let g:hq_history_lines = getline(1, '$')",
		"  silent undo",
		"  let g:hq_history_undo_lines = getline(1, '$')",
		"  if g:hq_history_undo_lines !=# ['']",
		"    call HqHistoryFinish('failed', 'one undo did not restore canonical empty draft')",
		"    return",
		"  endif",
		"  call HqHistoryFinish('passed', '')",
		"endfunction",
		"function! HqHistoryObserve(timer) abort",
		"  if reltimefloat(reltime()) >= g:hq_history_deadline",
		"    call HqHistoryFinish('failed', 'accepted-history documentation timeout')",
		"    return",
		"  endif",
		"  let l:info = complete_info(['items', 'selected'])",
		"  if get(l:info, 'selected', -1) != g:hq_history_selected",
		"    call timer_start(20, function('HqHistoryObserve'))",
		"    return",
		"  endif",
		"  let l:item = l:info.items[g:hq_history_selected]",
		"  let l:data = get(l:item, 'user_data', {})",
		"  let g:hq_history_detail = type(l:data) == v:t_dict ? get(l:data, 'detail', get(l:item, 'menu', '')) : get(l:item, 'menu', '')",
		"  let l:doc = type(l:data) == v:t_dict ? get(l:data, 'documentation', '') : ''",
		"  if type(l:doc) == v:t_dict | let l:doc = get(l:doc, 'value', '') | endif",
		"  let g:hq_history_documentation = type(l:doc) == v:t_string ? l:doc : ''",
		"  let l:popup = popup_findinfo()",
		"  if l:popup <= 0",
		"    call timer_start(20, function('HqHistoryObserve'))",
		"    return",
		"  endif",
		"  let g:hq_history_documentation_popup = getbufline(winbufnr(l:popup), 1, '$')",
		"  if g:hq_history_documentation_popup !=# split(g:hq_history_documentation, \"\\n\", 1)",
		"    call HqHistoryFinish('failed', 'accepted-history documentation popup is missing or truncated')",
		"    return",
		"  endif",
		"  call feedkeys(\"\\<C-Y>\\<Esc>\", 'n')",
		"  call timer_start(100, function('HqHistoryVerify'))",
		"endfunction",
		"function! HqHistoryPoll(timer) abort",
		"  if reltimefloat(reltime()) >= g:hq_history_deadline",
		"    call HqHistoryFinish('failed', 'accepted-history native popup timeout')",
		"    return",
		"  endif",
		"  let l:info = complete_info(['items'])",
		"  if !pumvisible() || empty(l:info.items)",
		"    call timer_start(20, function('HqHistoryPoll'))",
		"    return",
		"  endif",
		"  let l:index = -1",
		"  for l:i in range(len(l:info.items))",
		"    let l:item = l:info.items[l:i]",
		"    let l:data = get(l:item, 'user_data', {})",
		"    if (get(l:item, 'word', '') =~# 'queue.create' || get(l:item, 'abbr', '') ==# 'queue.create') && type(l:data) == v:t_dict && get(l:data, 'detail', '') ==# 'object_preset | accepted history'",
		"      let l:index = l:i",
		"      break",
		"    endif",
		"  endfor",
		"  if l:index < 0",
		"    call HqHistoryFinish('failed', 'accepted-history preset absent from manual native popup')",
		"    return",
		"  endif",
		"  let g:hq_history_selected = l:index",
		"  call feedkeys(repeat(\"\\<C-N>\", l:index + 1), 'n')",
		"  call timer_start(20, function('HqHistoryObserve'))",
		"endfunction",
		"function! HqHistoryComplete(timer) abort",
		"  if mode(1) !~# '^i'",
		"    if reltimefloat(reltime()) >= g:hq_history_deadline | call HqHistoryFinish('failed', 'failed to enter Insert mode') | return | endif",
		"    call timer_start(20, function('HqHistoryComplete'))",
		"    return",
		"  endif",
		"  try",
		"    call g:HqVimComplete()",
		"  catch",
		"    call HqHistoryFinish('failed', v:exception)",
		"    return",
		"  endtry",
		"  call timer_start(20, function('HqHistoryPoll'))",
		"endfunction",
		"call setline(1, [''])",
		"call cursor(1, 1)",
		"call feedkeys('i', 'n')",
		"call timer_start(20, function('HqHistoryComplete'))",
	}
	path := filepath.Join(t.TempDir(), "manual-history.vim")
	if err := os.WriteFile(path, []byte(strings.Join(lines, "\n")+"\n"), 0o600); err != nil {
		t.Fatal(err)
	}
	return path
}

func envWithOverrides(base []string, overrides map[string]string) []string {
	result := append([]string(nil), base...)
	for key, value := range overrides {
		found := false
		for index, entry := range result {
			name, _, _ := strings.Cut(entry, "=")
			match := name == key
			if runtime.GOOS == "windows" {
				match = strings.EqualFold(name, key)
			}
			if match {
				result[index] = key + "=" + value
				found = true
			}
		}
		if !found {
			result = append(result, key+"="+value)
		}
	}
	return result
}

func writeManualHistoryArtifact(t *testing.T, proof any, hqBin string) {
	t.Helper()
	base := os.Getenv("HQ_CONFORMANCE_ARTIFACT")
	if base == "" {
		return
	}
	artifact := filepath.Join(filepath.Dir(base), "hq-vim-accepted-history-"+runtime.GOOS+".json")
	body, err := json.MarshalIndent(map[string]any{
		"kind":            "edits.hqVimAcceptedHistoryConformance.v1",
		"status":          "passed",
		"editsHead":       "d83bf4c4860e02f37d6b41cc54fe8c881af4c779",
		"hqSourceSha":     os.Getenv("HQ_CANONICAL_SOURCE_SHA"),
		"hqBinary":        hqBin,
		"manualOperation": "HqComplete -> yegappan/lsp LspComplete(true)",
		"query":           "canonical one-line empty draft",
		"source":          "provenance-safe accepted_input",
		"completionWrites": 0,
		"explicitSeedRows": 1,
		"proof":           proof,
	}, "", "  ")
	if err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(artifact, append(body, '\n'), 0o600); err != nil {
		t.Fatal(err)
	}
}

var _ = time.Second
