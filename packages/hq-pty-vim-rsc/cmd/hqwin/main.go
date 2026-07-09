package main

import (
	"encoding/json"
	"flag"
	"fmt"
	"hq/internal/hostopen"
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
	case "host-open-append":
		err = hostOpenAppend(os.Args[2:])
	case "host-open-dispatch":
		err = hostOpenDispatch(os.Args[2:])
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
  hq host-open-append --queue cache\host-open.jsonl --id <id> --path C:\path --confirmed
  hq host-open-dispatch --queue cache\host-open.jsonl --receipts cache\host-open.receipts.jsonl --execute

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

func hostOpenAppend(args []string) error {
	fs := flag.NewFlagSet("host-open-append", flag.ContinueOnError)
	queue := fs.String("queue", "cache/host-open.queue.jsonl", "host open queue jsonl path")
	id := fs.String("id", "", "queue row id")
	path := fs.String("path", "", "local Windows host path")
	mode := fs.String("mode", "open", "host open mode: open or select")
	source := fs.String("source", "hqwin", "source client")
	confirmed := fs.Bool("confirmed", false, "explicit confirmation gate")
	out := fs.String("out", "", "optional output path")
	if err := fs.Parse(args); err != nil {
		return err
	}
	row := hostopen.NewQueueRow(*id, *path, *mode, *source, *confirmed)
	if err := hostopen.AppendQueue(*queue, row); err != nil {
		return err
	}
	result := map[string]any{
		"kind":  "hq.hostPathOpenAppendResult.v1",
		"ok":    true,
		"queue": *queue,
		"row":   row,
	}
	return writeJSON(*out, result)
}

func hostOpenDispatch(args []string) error {
	fs := flag.NewFlagSet("host-open-dispatch", flag.ContinueOnError)
	queue := fs.String("queue", "cache/host-open.queue.jsonl", "host open queue jsonl path")
	receipts := fs.String("receipts", "cache/host-open.receipts.jsonl", "host open receipt jsonl path")
	explorerBin := fs.String("explorer-bin", "explorer.exe", "explorer-compatible executable")
	execute := fs.Bool("execute", false, "execute the confirmed host open intent")
	out := fs.String("out", "", "optional output path")
	if err := fs.Parse(args); err != nil {
		return err
	}
	receipt, err := hostopen.DispatchQueue(*queue, *receipts, *explorerBin, *execute)
	if err != nil {
		return err
	}
	return writeJSON(*out, receipt)
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
