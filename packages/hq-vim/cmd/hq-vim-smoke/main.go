package main

import (
	"flag"
	"fmt"
	"os"

	"github.com/roccho-dev/edits/packages/hq-vim/internal/smoke"
)

func main() {
	var cfg smoke.Config
	flag.StringVar(&cfg.HQBin, "hq-bin", os.Getenv("HQ_BIN"), "existing hq binary path")
	flag.StringVar(&cfg.Vim, "vim", os.Getenv("VIM_EXE"), "vim executable path")
	flag.StringVar(&cfg.Vim9LSP, "vim9-lsp", os.Getenv("VIM9_LSP_PATH"), "yegappan/lsp checkout path")
	flag.StringVar(&cfg.PluginRoot, "plugin-root", "", "hq-vim package root")
	flag.StringVar(&cfg.Profile, "profile", "local", "hq endpoint profile")
	flag.StringVar(&cfg.Buffer, "buffer", "", "buffer path to open")
	flag.StringVar(&cfg.BufferText, "buffer-text", os.Getenv("HQ_BUFFER_TEXT"), "initial hq buffer text")
	flag.BoolVar(&cfg.Headless, "headless", false, "run completion and accept proof then exit")
	flag.Parse()

	if err := smoke.Run(cfg); err != nil {
		fmt.Fprintln(os.Stderr, err)
		os.Exit(1)
	}
}
