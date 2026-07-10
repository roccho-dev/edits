package smoke

import (
	"encoding/json"
	"errors"
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"runtime"
	"strings"
)

type Config struct {
	HQBin      string
	Vim        string
	VimLSP     string
	PluginRoot string
	Profile    string
	Buffer     string
	BufferText string
	Headless   bool
	StartOnly  bool
	Env        map[string]string
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
	if cfg.HQBin == "" || !Exists(cfg.HQBin) {
		return fmt.Errorf("hq binary not found; this edits helper does not build hq, set HQ_BIN or pass -hq-bin")
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

	script, err := writeVimScript(root, cfg)
	if err != nil {
		return err
	}
	defer os.Remove(script)

	args := []string{"--clean", "-Nu", "NONE", "-n"}
	if cfg.Headless {
		args = append(args, "-es")
	}
	args = append(args, "-S", script)
	cmd := exec.Command(cfg.Vim, args...)
	cmd.Stdout = os.Stdout
	cmd.Stderr = os.Stderr
	cmd.Stdin = os.Stdin
	cmd.Env = os.Environ()
	for key, value := range cfg.Env {
		cmd.Env = append(cmd.Env, key+"="+value)
	}
	return cmd.Run()
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
		"execute 'set runtimepath^=' . fnameescape(" + vimString(cfg.VimLSP) + ")",
		"execute 'set runtimepath^=' . fnameescape(" + vimString(root) + ")",
		"runtime plugin/lsp.vim",
		"runtime plugin/hq.vim",
		"let g:hq_bin = " + vimString(cfg.HQBin),
		"let g:hq_profile = " + vimString(cfg.Profile),
		"call mkdir(fnamemodify(" + vimString(cfg.Buffer) + ", ':h'), 'p')",
		"execute 'edit ' . fnameescape(" + vimString(cfg.Buffer) + ")",
		"set filetype=hqjson",
		"setlocal omnifunc=lsp#complete",
	}
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
		lines = append(lines,
			"call setline(1, "+vimValue(cfg.BufferText)+")",
			"call cursor(1, strlen(getline(1)) + 1)",
			"doautocmd TextChanged",
			"HqSubmit",
			"qa!",
		)
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
