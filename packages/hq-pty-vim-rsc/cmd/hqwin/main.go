package main

import (
	"flag"
	"fmt"
	"os"

	"hq/internal/launcher"
)

func main() {
	if len(os.Args) < 2 {
		usage()
		os.Exit(2)
	}
	var err error
	switch os.Args[1] {
	case "windows-explorer-complete":
		err = complete(os.Args[2:])
	case "windows-explorer-preview":
		err = preview(os.Args[2:])
	case "windows-launcher-smoke":
		err = smoke(os.Args[2:])
	default:
		usage()
		os.Exit(2)
	}
	if err != nil {
		fmt.Fprintln(os.Stderr, "error:", err)
		os.Exit(1)
	}
}

func usage() {
	fmt.Fprintln(os.Stderr, `hq Windows launcher commands:
  hq windows-explorer-complete --base re
  hq windows-explorer-preview --target edits
  hq windows-explorer-preview --select C:\\path\\file.txt
  hq windows-launcher-smoke --home C:\\Users\\resta`)
}

func complete(args []string) error {
	fs := flag.NewFlagSet("windows-explorer-complete", flag.ContinueOnError)
	home := fs.String("home", "", "Windows home path")
	base := fs.String("base", "", "target prefix")
	out := fs.String("out", "", "optional output path")
	if err := fs.Parse(args); err != nil {
		return err
	}
	return writeJSON(*out, map[string]any{"kind": "windows.explorer.complete", "items": launcher.CompleteTargets(launcher.HomeFromEnvOrDefault(*home), *base)})
}

func preview(args []string) error {
	fs := flag.NewFlagSet("windows-explorer-preview", flag.ContinueOnError)
	home := fs.String("home", "", "Windows home path")
	target := fs.String("target", "", "known target")
	selectPath := fs.String("select", "", "file path to select")
	execute := fs.Bool("execute", false, "actually start explorer.exe")
	out := fs.String("out", "", "optional output path")
	if err := fs.Parse(args); err != nil {
		return err
	}
	var plan launcher.ExplorerPlan
	var err error
	if *selectPath != "" {
		plan, err = launcher.PreviewSelect(*selectPath)
	} else {
		if *target == "" {
			return fmt.Errorf("--target or --select required")
		}
		t, err2 := launcher.ResolveTarget(launcher.HomeFromEnvOrDefault(*home), *target)
		if err2 != nil {
			return err2
		}
		plan, err = launcher.PreviewOpen(t)
	}
	if err != nil {
		return err
	}
	if *execute {
		if err := launcher.Execute(plan); err != nil {
			return err
		}
		plan.SideEffect = true
	}
	return writeJSON(*out, plan)
}

func smoke(args []string) error {
	fs := flag.NewFlagSet("windows-launcher-smoke", flag.ContinueOnError)
	home := fs.String("home", "", "Windows home path")
	out := fs.String("out", "", "optional output path")
	if err := fs.Parse(args); err != nil {
		return err
	}
	result, err := launcher.Smoke(launcher.HomeFromEnvOrDefault(*home))
	if writeErr := writeJSON(*out, result); writeErr != nil {
		return writeErr
	}
	if err != nil {
		return err
	}
	if !result.OK {
		return fmt.Errorf("windows launcher smoke failed")
	}
	return nil
}

func writeJSON(path string, v any) error {
	b := launcher.MarshalPretty(v)
	if path == "" {
		_, err := os.Stdout.Write(b)
		return err
	}
	return os.WriteFile(path, b, 0o644)
}
