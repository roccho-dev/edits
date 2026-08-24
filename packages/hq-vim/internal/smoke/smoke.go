package smoke

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"runtime"
	"strings"
	"time"
)

type Config struct {
	HQBin                     string
	Vim                       string
	Vim9LSP                   string
	PluginRoot                string
	Profile                   string
	Buffer                    string
	BufferText                string
	CompletionText            string
	ExpectedCompletionLabel   string
	ExpectedCompletionText    string
	RequireDocumentationPopup bool
	NativePopupFileFormat     string
	Headless                  bool
	StartOnly                 bool
	OmitHQBin                 bool
	SkipSubmit                bool
	SubmitCount               int
	Env                       map[string]string
	Timeout                   time.Duration
	VimLog                    string
	LSPLog                    string
	ResultPath                string
	BufferResultPath          string
	UndoResultPath            string
	MessagesPath              string
	NativePopupArtifact       string
	CaptureReadyPath          string
	CaptureDonePath           string
}

func Run(cfg Config) error {
	root, err := PackageRoot(cfg.PluginRoot)
	if err != nil {
		return err
	}
	if cfg.Vim == "" {
		cfg.Vim, err = lookPathAny("vim", "vim.exe")
		if err != nil {
			return fmt.Errorf("vim not found; set VIM_EXE or pass -vim: %w", err)
		}
	}
	if cfg.Vim9LSP == "" {
		cfg.Vim9LSP = filepath.Join(os.Getenv("LOCALAPPDATA"), "codex-proof", "yegappan-lsp")
	}
	if err := ProbeVimRuntime(cfg.Vim); err != nil {
		return err
	}
	if !Exists(filepath.Join(cfg.Vim9LSP, "plugin", "lsp.vim")) || !Exists(filepath.Join(cfg.Vim9LSP, "autoload", "lsp", "buffer.vim")) {
		return fmt.Errorf("yegappan/lsp not found; set VIM9_LSP_PATH or pass -vim9-lsp")
	}
	if !cfg.OmitHQBin {
		if cfg.HQBin == "" || !Exists(cfg.HQBin) {
			return fmt.Errorf("hq binary not found; this edits helper does not build hq, set HQ_BIN or pass -hq-bin")
		}
	}
	if cfg.Profile == "" {
		cfg.Profile = "local"
	}
	if cfg.SubmitCount == 0 {
		cfg.SubmitCount = 1
	}
	if cfg.SubmitCount < 0 {
		return errors.New("SubmitCount cannot be negative")
	}
	if cfg.Buffer == "" {
		cfg.Buffer = filepath.Join(root, ".tmp", "manual.hqjson")
	}
	if cfg.BufferText == "" {
		cfg.BufferText = `{"kind":"hq.hostOpenRequest.v1","path":"."}`
	}
	if err := os.MkdirAll(filepath.Dir(cfg.Buffer), 0o755); err != nil {
		return err
	}
	for _, path := range []string{cfg.ResultPath, cfg.BufferResultPath, cfg.UndoResultPath, cfg.MessagesPath, cfg.NativePopupArtifact, cfg.CaptureReadyPath, cfg.CaptureDonePath} {
		if path != "" {
			if err := os.MkdirAll(filepath.Dir(path), 0o755); err != nil {
				return err
			}
		}
	}
	if cfg.NativePopupArtifact != "" && cfg.ExpectedCompletionLabel == "" {
		return errors.New("native popup proof requires ExpectedCompletionLabel")
	}
	if cfg.NativePopupArtifact != "" && cfg.ExpectedCompletionText == "" {
		return errors.New("native popup proof requires ExpectedCompletionText")
	}
	if cfg.NativePopupFileFormat != "" && cfg.NativePopupFileFormat != "unix" && cfg.NativePopupFileFormat != "dos" {
		return errors.New("NativePopupFileFormat must be unix or dos")
	}
	if (cfg.CaptureReadyPath == "") != (cfg.CaptureDonePath == "") {
		return errors.New("PTY capture requires both ready and done paths")
	}

	cleanupLogs := false
	if cfg.VimLog == "" {
		cfg.VimLog = filepath.Join(os.TempDir(), fmt.Sprintf("hq-vim-verbose-%d.log", time.Now().UnixNano()))
		cleanupLogs = true
	}
	if cfg.LSPLog == "" {
		cfg.LSPLog = filepath.Join(os.TempDir(), fmt.Sprintf("hq-vim9-lsp-%d.log", time.Now().UnixNano()))
		cleanupLogs = true
	}
	if cleanupLogs {
		defer os.Remove(cfg.VimLog)
		defer os.Remove(cfg.LSPLog)
	}

	script, err := writeVimScript(root, cfg)
	if err != nil {
		return err
	}
	defer os.Remove(script)

	args := []string{"--clean", "-Nu", "NONE", "-n", "-V1" + filepath.ToSlash(cfg.VimLog)}
	if cfg.Headless {
		args = append(args, "-es")
	}
	args = append(args, "-S", filepath.ToSlash(script))
	timeout := cfg.Timeout
	if timeout <= 0 {
		timeout = 30 * time.Second
	}
	ctx, cancel := context.WithTimeout(context.Background(), timeout)
	defer cancel()
	cmd := exec.CommandContext(ctx, cfg.Vim, args...)
	cmd.Stdout = os.Stdout
	cmd.Stderr = os.Stderr
	cmd.Stdin = os.Stdin
	cmd.Env = environmentWithOverrides(os.Environ(), cfg.Env)
	if cfg.NativePopupArtifact != "" && runtime.GOOS != "windows" {
		terminal, terminalErr := os.OpenFile("/dev/tty", os.O_RDWR, 0)
		if terminalErr != nil {
			return diagnosticError(fmt.Errorf("open controlling terminal: %w", terminalErr), cfg)
		}
		defer terminal.Close()
		cmd.Stdout, cmd.Stderr, cmd.Stdin = terminal, terminal, terminal
	}
	err = cmd.Run()
	if errors.Is(ctx.Err(), context.DeadlineExceeded) {
		return diagnosticError(fmt.Errorf("Vim smoke timed out after %s", timeout), cfg)
	}
	if err != nil {
		return diagnosticError(err, cfg)
	}
	return nil
}

func diagnosticError(cause error, cfg Config) error {
	return fmt.Errorf("%w\nvim verbose log:\n%s\nyegappan/lsp log:\n%s", cause, readDiagnostic(cfg.VimLog), readDiagnostic(cfg.LSPLog))
}

func readDiagnostic(path string) string {
	data, err := os.ReadFile(path)
	if err != nil {
		return "<unavailable: " + err.Error() + ">"
	}
	const limit = 16 << 10
	if len(data) > limit {
		data = data[len(data)-limit:]
	}
	text := strings.TrimSpace(string(data))
	if text == "" {
		return "<empty>"
	}
	return text
}

func environmentWithOverrides(base []string, overrides map[string]string) []string {
	result := append([]string(nil), base...)
	for key, value := range overrides {
		replaced := false
		for i, entry := range result {
			name, _, _ := strings.Cut(entry, "=")
			matches := name == key
			if runtime.GOOS == "windows" {
				matches = strings.EqualFold(name, key)
			}
			if matches {
				result[i] = key + "=" + value
				replaced = true
			}
		}
		if !replaced {
			result = append(result, key+"="+value)
		}
	}
	return result
}

func ProbeVimRuntime(vim string) error {
	probe := "if empty(globpath(&runtimepath, 'autoload/dist/ft.vim')) | cquit 42 | endif"
	cmd := exec.Command(vim, "--clean", "-Nu", "NONE", "-n", "-es", "-c", probe, "-c", "qa!")
	if output, err := cmd.CombinedOutput(); err != nil {
		return fmt.Errorf("vim runtime is incomplete for %s: %w: %s", vim, err, strings.TrimSpace(string(output)))
	}
	return nil
}

func PackageRoot(explicit string) (string, error) {
	if explicit != "" {
		return filepath.Abs(explicit)
	}
	wd, err := os.Getwd()
	if err == nil {
		if root, ok := findRoot(wd); ok {
			return root, nil
		}
	}
	_, file, _, ok := runtime.Caller(0)
	if ok {
		if root, ok := findRoot(filepath.Dir(file)); ok {
			return root, nil
		}
	}
	return "", errors.New("hq-vim package root not found")
}

func Exists(path string) bool {
	_, err := os.Stat(path)
	return err == nil
}

func findRoot(start string) (string, bool) {
	dir, err := filepath.Abs(start)
	if err != nil {
		return "", false
	}
	for {
		if Exists(filepath.Join(dir, "plugin", "hq.vim")) && Exists(filepath.Join(dir, "autoload", "hq.vim")) {
			return dir, true
		}
		next := filepath.Dir(dir)
		if next == dir {
			return "", false
		}
		dir = next
	}
}

func lookPathAny(names ...string) (string, error) {
	for _, name := range names {
		if path, err := exec.LookPath(name); err == nil {
			return path, nil
		}
	}
	return "", exec.ErrNotFound
}

func writeVimScript(root string, cfg Config) (string, error) {
	lines := []string{
		"set nocompatible",
		"set noswapfile",
		"set encoding=utf-8",
		"set completeopt=menuone,noinsert,noselect,popup",
		"execute 'set runtimepath^=' . fnameescape(" + vimString(cfg.Vim9LSP) + ")",
		"execute 'set runtimepath^=' . fnameescape(" + vimString(root) + ")",
		"runtime plugin/lsp.vim",
		"runtime plugin/hq.vim",
	}
	if !cfg.OmitHQBin {
		lines = append(lines, "let g:hq_bin = "+vimString(cfg.HQBin))
	}
	lines = append(lines,
		"let g:hq_profile = "+vimString(cfg.Profile),
		"call mkdir(fnamemodify("+vimString(cfg.Buffer)+", ':h'), 'p')",
		"execute 'edit ' . fnameescape("+vimString(cfg.Buffer)+")",
		"set filetype=hqjson",
	)
	if cfg.StartOnly {
		lines = append(lines,
			"try",
			"  HqStart",
			"catch",
			"  cquit 43",
			"endtry",
			"qa!",
		)
	} else {
		lines = append(lines,
			"HqStart",
			"let hq_ready_deadline = reltimefloat(reltime()) + 10.0",
			"while !g:LspServerReady() && reltimefloat(reltime()) < hq_ready_deadline",
			"  sleep 10m",
			"endwhile",
			"if !g:LspServerReady() | cquit 43 | endif",
		)
	}
	if cfg.NativePopupArtifact != "" && !cfg.StartOnly {
		lines = append(lines, nativePopupProofLines(cfg)...)
	} else if cfg.Headless && !cfg.StartOnly {
		if cfg.ExpectedCompletionLabel != "" {
			lines = append(lines,
				"call setline(1, "+vimLines(cfg.CompletionText)+")",
				"call cursor(1, strlen(getline(1)) + 1)",
				"let hq_completion_response = g:HqVimCompletionRequest()",
				"let hq_completion_result = get(hq_completion_response, 'result', {})",
				"let hq_completion_items = type(hq_completion_result) == v:t_dict ? get(hq_completion_result, 'items', []) : hq_completion_result",
				"let hq_completion_found = 0",
				"for hq_item in hq_completion_items",
				"  if get(hq_item, 'label', '') ==# "+vimValue(cfg.ExpectedCompletionLabel),
				"    let hq_completion_found = 1",
				"    break",
				"  endif",
				"endfor",
				"if !hq_completion_found",
				"  cquit 44",
				"endif",
			)
		}
		if cfg.SkipSubmit {
			lines = append(lines, "qa!")
		} else {
			lines = append(lines,
				"call setline(1, "+vimLines(cfg.BufferText)+")",
				"call cursor(1, strlen(getline(1)) + 1)",
				"call feedkeys(\"\\<Esc>\", 'xt')",
			)
			lines = append(lines,
				"let hq_submit_result = {}",
				fmt.Sprintf("for hq_submit_index in range(1, %d)", cfg.SubmitCount),
				"  let hq_submit_result = g:HqVimSubmit()",
				"endfor",
			)
			if cfg.ResultPath != "" {
				lines = append(lines, "call writefile([json_encode(hq_submit_result)], "+vimString(cfg.ResultPath)+")")
			}
			if cfg.BufferResultPath != "" {
				lines = append(lines, "call writefile([json_encode({'lines': getline(1, '$'), 'changedtick': b:changedtick})], "+vimString(cfg.BufferResultPath)+")")
			}
			if cfg.UndoResultPath != "" {
				lines = append(lines,
					"silent undo",
					"call writefile([json_encode({'lines': getline(1, '$'), 'changedtick': b:changedtick})], "+vimString(cfg.UndoResultPath)+")",
				)
			}
			if cfg.MessagesPath != "" {
				lines = append(lines, "call writefile(split(execute('messages'), \"\\n\"), "+vimString(cfg.MessagesPath)+")")
			}
			lines = append(lines, "qa!")
		}
	}
	f, err := os.CreateTemp("", "hq-vim-smoke-*.vim")
	if err != nil {
		return "", err
	}
	defer f.Close()
	if _, err := f.WriteString(strings.Join(lines, "\n") + "\n"); err != nil {
		return "", err
	}
	return f.Name(), nil
}

func nativePopupProofLines(cfg Config) []string {
	prefix, trigger := splitFinalRune(cfg.CompletionText)
	insertKeys := "A" + trigger
	if prefix == "" {
		insertKeys = "i" + trigger
	}
	lines := []string{
		"let g:hq_native_expected_lines = " + vimLines(cfg.ExpectedCompletionText),
		"let g:hq_native_query_lines = " + vimLines(cfg.CompletionText),
		"let g:hq_native_completed_lines = []",
		"let g:hq_native_undo_lines = []",
		"let g:hq_native_candidate_detail = ''",
		"let g:hq_native_candidate_documentation = ''",
		"let g:hq_native_documentation_popup = []",
		"let g:hq_native_items = []",
		"let g:hq_native_expected_index = -1",
	}
	if cfg.NativePopupFileFormat != "" {
		lines = append(lines, "setlocal fileformat="+cfg.NativePopupFileFormat)
	}
	if cfg.CaptureReadyPath != "" {
		captureAccept := `    call feedkeys("\<C-Y>\<Esc>", 'n')`
		if !cfg.RequireDocumentationPopup {
			captureAccept = `    call feedkeys(repeat("\<C-N>", g:hq_native_expected_index + 1) . "\<C-Y>\<Esc>", 'int')`
		}
		lines = append(lines,
			"function! HqNativePopupCaptureWait(timer) abort",
			"  if filereadable("+vimString(cfg.CaptureDonePath)+")",
			captureAccept,
			"    call timer_start(100, function('HqNativePopupVerify'))",
			"    return",
			"  endif",
			"  if reltimefloat(reltime()) >= g:hq_native_deadline",
			"    call HqNativePopupFinish('failed', 'PTY capture observer timeout')",
			"    return",
			"  endif",
			"  call timer_start(20, function('HqNativePopupCaptureWait'))",
			"endfunction",
		)
	}
	lines = append(lines,
		"let g:hq_native_deadline = reltimefloat(reltime()) + 10.0",
		"function! HqNativePopupFinish(status, failure) abort",
		"  call writefile([json_encode({'status': a:status, 'failure': a:failure, 'lines': get(g:, 'hq_native_completed_lines', []), 'undo_lines': get(g:, 'hq_native_undo_lines', []), 'candidate_detail': get(g:, 'hq_native_candidate_detail', ''), 'candidate_documentation': get(g:, 'hq_native_candidate_documentation', ''), 'documentation_popup': get(g:, 'hq_native_documentation_popup', []), 'fileformat': &fileformat, 'items': get(g:, 'hq_native_items', [])})], "+vimString(cfg.NativePopupArtifact)+")",
		"  if a:status ==# 'passed'",
		"    qa!",
		"  else",
		"    cquit 46",
		"  endif",
		"endfunction",
		"function! HqNativePopupVerify(timer) abort",
		"  if getline(1, '$') !=# g:hq_native_expected_lines",
		"    call HqNativePopupFinish('failed', 'selected buffer does not equal expected text edit')",
		"    return",
		"  endif",
		"  let g:hq_native_completed_lines = getline(1, '$')",
		"  silent undo",
		"  let g:hq_native_undo_lines = getline(1, '$')",
		"  if g:hq_native_undo_lines !=# g:hq_native_query_lines",
		"    call HqNativePopupFinish('failed', 'one native undo did not restore the exact query')",
		"    return",
		"  endif",
		"  call HqNativePopupFinish('passed', '')",
		"endfunction",
		"function! HqNativePopupAccept(timer) abort",
		`  call feedkeys("\<C-Y>\<Esc>", 'n')`,
		"  call timer_start(100, function('HqNativePopupVerify'))",
		"endfunction",
		"function! HqNativePopupObserve(timer) abort",
		"  if reltimefloat(reltime()) >= g:hq_native_deadline",
		"    call HqNativePopupFinish('failed', 'selected completion documentation timeout')",
		"    return",
		"  endif",
		"  let l:info = complete_info(['items', 'selected'])",
		"  if get(l:info, 'selected', -1) != g:hq_native_expected_index",
		"    call timer_start(20, function('HqNativePopupObserve'))",
		"    return",
		"  endif",
		"  let l:item = l:info.items[g:hq_native_expected_index]",
		"  let l:data = get(l:item, 'user_data', {})",
		"  let g:hq_native_candidate_detail = type(l:data) == v:t_dict ? get(l:data, 'detail', get(l:item, 'menu', '')) : get(l:item, 'menu', '')",
		"  let l:doc = type(l:data) == v:t_dict ? get(l:data, 'documentation', '') : ''",
		"  if type(l:doc) == v:t_dict | let l:doc = get(l:doc, 'value', '') | endif",
		"  let g:hq_native_candidate_documentation = type(l:doc) == v:t_string ? l:doc : ''",
		"  let l:popup = popup_findinfo()",
		"  if l:popup <= 0",
		"    call timer_start(20, function('HqNativePopupObserve'))",
		"    return",
		"  endif",
		"  let g:hq_native_documentation_popup = getbufline(winbufnr(l:popup), 1, '$')",
		"  let l:expected_doc = split(g:hq_native_candidate_documentation, \"\\n\", 1)",
		"  if empty(g:hq_native_candidate_detail) || empty(l:expected_doc) || g:hq_native_documentation_popup !=# l:expected_doc",
		"    call HqNativePopupFinish('failed', 'native documentation popup is missing or truncated')",
		"    return",
		"  endif",
	)
	if cfg.CaptureReadyPath != "" {
		lines = append(lines,
			"  call writefile(['ready'], "+vimString(cfg.CaptureReadyPath)+")",
			"  call timer_start(20, function('HqNativePopupCaptureWait'))",
			"  return",
		)
	}
	lines = append(lines,
		`  call feedkeys("\<C-Y>\<Esc>", 'n')`,
		"  call timer_start(100, function('HqNativePopupVerify'))",
		"endfunction",
		"function! HqNativePopupPoll(timer) abort",
		"  if reltimefloat(reltime()) >= g:hq_native_deadline",
		"    call HqNativePopupFinish('failed', 'native popup timeout')",
		"    return",
		"  endif",
		"  let l:info = complete_info(['items'])",
		"  if !pumvisible() || empty(l:info.items)",
		"    call timer_start(20, function('HqNativePopupPoll'))",
		"    return",
		"  endif",
		"  let g:hq_native_items = map(copy(l:info.items), {_, item -> {'word': get(item, 'word', ''), 'abbr': get(item, 'abbr', ''), 'menu': get(item, 'menu', ''), 'info': get(item, 'info', '')}})",
		"  let l:index = -1",
		"  for l:i in range(len(l:info.items))",
		"    if get(l:info.items[l:i], 'word', '') =~# "+vimValue(cfg.ExpectedCompletionLabel)+" || get(l:info.items[l:i], 'abbr', '') ==# "+vimValue(cfg.ExpectedCompletionLabel),
		"      let l:index = l:i",
		"      break",
		"    endif",
		"  endfor",
		"  if l:index < 0",
		"    call HqNativePopupFinish('failed', 'expected candidate absent from native popup')",
		"    return",
		"  endif",
		"  let g:hq_native_expected_index = l:index",
		"  let l:item = l:info.items[l:index]",
		"  let l:data = get(l:item, 'user_data', {})",
		"  let g:hq_native_candidate_detail = type(l:data) == v:t_dict ? get(l:data, 'detail', get(l:item, 'menu', '')) : get(l:item, 'menu', '')",
		"  let l:doc = type(l:data) == v:t_dict ? get(l:data, 'documentation', get(l:item, 'info', '')) : get(l:item, 'info', '')",
		"  if type(l:doc) == v:t_dict | let l:doc = get(l:doc, 'value', '') | endif",
		"  let g:hq_native_candidate_documentation = type(l:doc) == v:t_string ? l:doc : ''",
		"  if empty(g:hq_native_candidate_detail) || empty(g:hq_native_candidate_documentation)",
		"    call HqNativePopupFinish('failed', 'native candidate metadata is missing')",
		"    return",
		"  endif",
	)
	if cfg.RequireDocumentationPopup {
		lines = append(lines,
			"  let l:selected = get(complete_info(['selected']), 'selected', -1)",
			"  if l:selected != l:index",
			"    let l:steps = l:selected < 0 ? l:index + 1 : (l:index - l:selected + len(l:info.items)) % len(l:info.items)",
			"    if l:steps > 0",
			"      call feedkeys(repeat(\"\\<C-N>\", l:steps), 'nt')",
			"    endif",
			"  endif",
			"  call timer_start(20, function('HqNativePopupObserve'))",
			"endfunction",
		)
	} else if cfg.CaptureReadyPath != "" {
		lines = append(lines,
			"  call writefile(['ready'], "+vimString(cfg.CaptureReadyPath)+")",
			"  call timer_start(20, function('HqNativePopupCaptureWait'))",
			"  return",
			"endfunction",
		)
	} else {
		lines = append(lines,
			"  let l:selected = get(complete_info(['selected']), 'selected', -1)",
			"  if l:selected != l:index",
			"    let l:steps = l:selected < 0 ? l:index + 1 : (l:index - l:selected + len(l:info.items)) % len(l:info.items)",
			"    if l:steps > 0",
			`      call feedkeys(repeat("\<C-N>", l:steps), 'int')`,
			"    endif",
			"  endif",
			"  call timer_start(20, function('HqNativePopupAccept'))",
			"endfunction",
		)
	}
	lines = append(lines,
		"function! HqNativePopupType(timer) abort",
		"  call setline(1, "+vimLines(prefix)+")",
		"  call cursor(line('$'), strlen(getline('$')) + 1)",
		"  call feedkeys("+vimValue(insertKeys)+", 'n')",
		"  call timer_start(20, function('HqNativePopupPoll'))",
		"endfunction",
		"call timer_start(10, function('HqNativePopupType'))",
	)
	return lines
}

func splitFinalRune(value string) (string, string) {
	runes := []rune(value)
	if len(runes) == 0 {
		return "", ""
	}
	return string(runes[:len(runes)-1]), string(runes[len(runes)-1])
}

func vimString(path string) string {
	s := filepath.ToSlash(path)
	return vimValue(s)
}

func vimValue(value string) string {
	b, _ := json.Marshal(value)
	return string(b)
}

func vimLines(value string) string {
	b, _ := json.Marshal(strings.Split(value, "\n"))
	return string(b)
}
