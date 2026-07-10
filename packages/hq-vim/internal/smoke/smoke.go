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
	HQBin                   string
	Vim                     string
	VimLSP                  string
	PluginRoot              string
	Profile                 string
	Buffer                  string
	BufferText              string
	CompletionText          string
	ExpectedCompletionLabel string
	Headless                bool
	StartOnly               bool
	OmitHQBin               bool
	SkipSubmit              bool
	Env                     map[string]string
	Timeout                 time.Duration
	VimLog                  string
	LSPLog                  string
	ResultPath              string
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
	if cfg.VimLSP == "" {
		cfg.VimLSP = filepath.Join(os.Getenv("LOCALAPPDATA"), "codex-proof", "vim-lsp")
	}
	if err := ProbeVimRuntime(cfg.Vim); err != nil {
		return err
	}
	if !Exists(filepath.Join(cfg.VimLSP, "plugin", "lsp.vim")) {
		return fmt.Errorf("vim-lsp not found; set VIM_LSP_PATH or pass -vim-lsp")
	}
	if !cfg.OmitHQBin {
		if cfg.HQBin == "" || !Exists(cfg.HQBin) {
			return fmt.Errorf("hq binary not found; this edits helper does not build hq, set HQ_BIN or pass -hq-bin")
		}
	}
	if cfg.Profile == "" {
		cfg.Profile = "local"
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
	if cfg.ResultPath != "" {
		if err := os.MkdirAll(filepath.Dir(cfg.ResultPath), 0o755); err != nil {
			return err
		}
	}

	cleanupLogs := false
	if cfg.VimLog == "" {
		cfg.VimLog = filepath.Join(os.TempDir(), fmt.Sprintf("hq-vim-verbose-%d.log", time.Now().UnixNano()))
		cleanupLogs = true
	}
	if cfg.LSPLog == "" {
		cfg.LSPLog = filepath.Join(os.TempDir(), fmt.Sprintf("hq-vim-lsp-%d.log", time.Now().UnixNano()))
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
	return fmt.Errorf("%w\nvim verbose log:\n%s\nvim-lsp log:\n%s", cause, readDiagnostic(cfg.VimLog), readDiagnostic(cfg.LSPLog))
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
		"let g:lsp_log_file = " + vimString(cfg.LSPLog),
		"let g:lsp_log_verbose = 1",
		"execute 'set runtimepath^=' . fnameescape(" + vimString(cfg.VimLSP) + ")",
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
		"setlocal omnifunc=lsp#complete",
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
		lines = append(lines, "HqStart")
	}
	if cfg.Headless && !cfg.StartOnly {
		if cfg.ExpectedCompletionLabel != "" {
			lines = append(lines,
				"call setline(1, "+vimValue(cfg.CompletionText)+")",
				"call cursor(1, strlen(getline(1)) + 1)",
				"doautocmd TextChanged",
				"let hq_completion_response = hq#request('textDocument/completion', {",
				"      \\ 'textDocument': lsp#get_text_document_identifier(),",
				"      \\ 'position': {'line': 0, 'character': strlen(getline(1))},",
				"      \\ })",
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
				"call setline(1, "+vimValue(cfg.BufferText)+")",
				"call cursor(1, strlen(getline(1)) + 1)",
				"doautocmd TextChanged",
			)
			if cfg.ResultPath == "" {
				lines = append(lines, "HqSubmit")
			} else {
				lines = append(lines,
					"let hq_submit_result = hq#submit()",
					"call writefile([json_encode(hq_submit_result)], "+vimString(cfg.ResultPath)+")",
				)
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

func vimString(path string) string {
	s := filepath.ToSlash(path)
	return vimValue(s)
}

func vimValue(value string) string {
	b, _ := json.Marshal(value)
	return string(b)
}
