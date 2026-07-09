package main

import (
	"encoding/json"
	"flag"
	"fmt"
	"os"
)

func main() {
	if len(os.Args) < 2 {
		usage()
		os.Exit(2)
	}
	var err error
	switch os.Args[1] {
	case "windows-launcher-smoke":
		err = retiredSmoke(os.Args[2:])
	default:
		err = fmt.Errorf("%s is retired; host path opening must use hq semantic intent and an ops/runtime boundary", os.Args[1])
	}
	if err != nil {
		fmt.Fprintln(os.Stderr, "error:", err)
		os.Exit(1)
	}
}

func usage() {
	fmt.Fprintln(os.Stderr, `hq Windows launcher compatibility command:
  hq windows-launcher-smoke --home C:\Users\resta

Direct Explorer commands are retired. Reintroduce host path opening only as hq semantic intent plus ops/runtime receipt.`)
}

func retiredSmoke(args []string) error {
	fs := flag.NewFlagSet("windows-launcher-smoke", flag.ContinueOnError)
	home := fs.String("home", "", "Windows home path")
	out := fs.String("out", "", "optional output path")
	if err := fs.Parse(args); err != nil {
		return err
	}
	result := map[string]any{
		"kind":                         "windows.launcher.retired.v1",
		"home":                         *home,
		"ok":                           true,
		"direct_explorer_side_retired": true,
		"side_effect_free":             true,
		"requires_hq_semantic_intent":  true,
	}
	return writeJSON(*out, result)
}

func writeJSON(path string, v any) error {
	b, err := json.MarshalIndent(v, "", "  ")
	if err != nil {
		return err
	}
	b = append(b, '\n')
	if path == "" {
		_, err = os.Stdout.Write(b)
		return err
	}
	return os.WriteFile(path, b, 0o644)
}
