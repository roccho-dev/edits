package main

import (
	"bufio"
	"bytes"
	"encoding/json"
	"flag"
	"fmt"
	"io"
	"os"
	"strings"

	"hq/internal/core"
	"hq/internal/dispatcher"
	"hq/internal/jsonrpc"
	"hq/internal/lsp"
)

func main() {
	if len(os.Args) < 2 {
		usage()
		os.Exit(2)
	}
	var err error
	switch os.Args[1] {
	case "model", "reduce":
		err = cmdModel(os.Args[2:])
	case "complete":
		err = cmdComplete(os.Args[2:])
	case "plan":
		err = cmdPlan(os.Args[2:])
	case "dispatch":
		err = cmdDispatch(os.Args[2:])
	case "lsp":
		err = cmdLSP(os.Args[2:])
	case "lsp-type-smoke":
		err = cmdLSPTypeSmoke(os.Args[2:])
	case "rsc-model":
		err = cmdRSCModel(os.Args[2:])
	case "rsc-complete":
		err = cmdRSCComplete(os.Args[2:])
	case "rsc-intake":
		err = cmdRSCIntake(os.Args[2:])
	case "rsc-accept":
		err = cmdRSCAccept(os.Args[2:])
	case "pty-vim-rsc-proof":
		err = cmdPTYVimRSCProof(os.Args[2:])
	case "pty-vim-rsc-visual-proof":
		err = cmdPTYVimRSCVisualProof(os.Args[2:])
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
	fmt.Fprintln(os.Stderr, `hq commands:
  hq model          --world examples/world.jsonl [--out cache/model.reduced.json]
  hq complete       --world examples/world.jsonl --line 'pane.shell.' [--version 1]
  hq plan           --world examples/world.jsonl --command 'pane.shell.send "git status" enter' [--version 1] [--out plan.json]
  hq dispatch       --plan plan.json --plan-id <id> --plan-hash <hash> --buffer-version <n> --receipts receipt.jsonl [--confirmed]
  hq lsp            --world examples/world.jsonl
  hq lsp-type-smoke --world examples/world.jsonl --chars 'pane.shell.' --out cache/lsp-typed.jsonl
  hq rsc-model      --world examples/tree_world.jsonl
  hq rsc-complete   --world examples/tree_world.jsonl --buffer '{"kind":"project","tasks":[' --cursor end
  hq rsc-intake     --world examples/tree_world.jsonl --input 'project hq tasks ' [--strict]
  hq rsc-accept     --suggestion cache/suggestion.json --queue cache/instruction.jsonl
  hq pty-vim-rsc-proof        --world examples/tree_world.jsonl --out cache/pty-vim-proof.json
  hq pty-vim-rsc-visual-proof --world examples/tree_world.jsonl --out cache/vim-visual-projection.json`)
}

func cmdModel(args []string) error {
	fs := flag.NewFlagSet("model", flag.ContinueOnError)
	world := fs.String("world", "examples/world.jsonl", "append-only world jsonl")
	out := fs.String("out", "", "optional reduced model cache path")
	if err := fs.Parse(args); err != nil {
		return err
	}
	model, err := core.LoadWorld(*world)
	if err != nil {
		return err
	}
	return writeJSON(*out, model)
}

func cmdComplete(args []string) error {
	fs := flag.NewFlagSet("complete", flag.ContinueOnError)
	world := fs.String("world", "examples/world.jsonl", "append-only world jsonl")
	line := fs.String("line", "", "current line/prefix")
	version := fs.Int("version", 1, "buffer version")
	if err := fs.Parse(args); err != nil {
		return err
	}
	model, err := core.LoadWorld(*world)
	if err != nil {
		return err
	}
	suggestions := core.Complete(model, core.CursorContext{Line: *line, Prefix: *line, BufferVersion: *version})
	return writeJSON("", suggestions)
}

func cmdPlan(args []string) error {
	fs := flag.NewFlagSet("plan", flag.ContinueOnError)
	world := fs.String("world", "examples/world.jsonl", "append-only world jsonl")
	command := fs.String("command", "", "command text")
	version := fs.Int("version", 1, "buffer version")
	out := fs.String("out", "", "optional plan json path")
	if err := fs.Parse(args); err != nil {
		return err
	}
	model, err := core.LoadWorld(*world)
	if err != nil {
		return err
	}
	plan, err := core.BuildPlan(model, *command, *version)
	if err != nil {
		return err
	}
	return writeJSON(*out, plan)
}

func cmdDispatch(args []string) error {
	fs := flag.NewFlagSet("dispatch", flag.ContinueOnError)
	planPath := fs.String("plan", "", "plan json path, or '-' for stdin")
	planID := fs.String("plan-id", "", "plan id user saw")
	planHash := fs.String("plan-hash", "", "plan hash user saw")
	version := fs.Int("buffer-version", 0, "buffer version user saw")
	receipts := fs.String("receipts", "receipt.jsonl", "receipt jsonl path")
	confirmed := fs.Bool("confirmed", false, "confirmed by user")
	if err := fs.Parse(args); err != nil {
		return err
	}
	if *planPath == "" {
		return fmt.Errorf("--plan required")
	}
	var r io.Reader
	if *planPath == "-" {
		r = os.Stdin
	} else {
		f, err := os.Open(*planPath)
		if err != nil {
			return err
		}
		defer f.Close()
		r = f
	}
	var plan core.PlanDraft
	if err := json.NewDecoder(r).Decode(&plan); err != nil {
		return err
	}
	if *planID == "" {
		*planID = plan.ID
	}
	if *planHash == "" {
		*planHash = plan.Hash
	}
	if *version == 0 {
		*version = plan.BufferVersion
	}
	d := dispatcher.NewDefault()
	receipt, err := d.Dispatch(dispatcher.Request{Plan: plan, PlanID: *planID, PlanHash: *planHash, BufferVersion: *version, Confirmed: *confirmed})
	if err != nil {
		return err
	}
	if err := dispatcher.AppendReceipt(*receipts, receipt); err != nil {
		return err
	}
	return writeJSON("", receipt)
}

func cmdLSP(args []string) error {
	fs := flag.NewFlagSet("lsp", flag.ContinueOnError)
	world := fs.String("world", "examples/world.jsonl", "append-only world jsonl")
	if err := fs.Parse(args); err != nil {
		return err
	}
	model, err := core.LoadWorld(*world)
	if err != nil {
		return err
	}
	return lsp.New(model).Serve(os.Stdin, os.Stdout)
}

func cmdLSPTypeSmoke(args []string) error {
	fs := flag.NewFlagSet("lsp-type-smoke", flag.ContinueOnError)
	world := fs.String("world", "examples/world.jsonl", "append-only world jsonl")
	chars := fs.String("chars", "pane.shell.", "characters to type one by one")
	out := fs.String("out", "", "jsonl output path")
	if err := fs.Parse(args); err != nil {
		return err
	}
	model, err := core.LoadWorld(*world)
	if err != nil {
		return err
	}
	server := lsp.New(model)
	uri := "file:///vim-typed.hqcmd"
	var log bytes.Buffer
	send := func(msg jsonrpc.Message) ([]jsonrpc.Message, error) { return server.Handle(msg) }
	if _, err := send(message(1, "initialize", map[string]any{})); err != nil {
		return err
	}
	if _, err := send(jsonrpc.Message{JSONRPC: "2.0", Method: "textDocument/didOpen", Params: raw(map[string]any{"textDocument": map[string]any{"uri": uri, "version": 0, "text": ""}})}); err != nil {
		return err
	}
	line := ""
	id := 2
	for i, r := range *chars {
		line += string(r)
		version := i + 1
		if _, err := send(jsonrpc.Message{JSONRPC: "2.0", Method: "textDocument/didChange", Params: raw(map[string]any{"textDocument": map[string]any{"uri": uri, "version": version}, "contentChanges": []map[string]any{{"text": line}}})}); err != nil {
			return err
		}
		responses, err := send(message(id, "textDocument/completion", map[string]any{"textDocument": map[string]any{"uri": uri}, "position": map[string]any{"line": 0, "character": len([]rune(line))}}))
		if err != nil {
			return err
		}
		id++
		count := 0
		labels := []string{}
		for _, res := range responses {
			if len(res.ID) == 0 {
				continue
			}
			b, _ := json.Marshal(res.Result)
			var parsed struct {
				Items []struct {
					Label string `json:"label"`
				} `json:"items"`
			}
			_ = json.Unmarshal(b, &parsed)
			count = len(parsed.Items)
			for _, item := range parsed.Items {
				labels = append(labels, item.Label)
			}
		}
		row, _ := json.Marshal(map[string]any{"kind": "vim.typed.completion", "version": version, "line": line, "completion_count": count, "labels": labels})
		log.Write(row)
		log.WriteByte('\n')
	}
	if *out == "" {
		_, err := io.Copy(os.Stdout, &log)
		return err
	}
	return os.WriteFile(*out, log.Bytes(), 0o644)
}

func message(id int, method string, params any) jsonrpc.Message {
	b, _ := json.Marshal(id)
	return jsonrpc.Message{JSONRPC: "2.0", ID: b, Method: method, Params: raw(params)}
}

func raw(v any) json.RawMessage {
	b, _ := json.Marshal(v)
	return b
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

func readJSONL(path string) ([]map[string]any, error) {
	f, err := os.Open(path)
	if err != nil {
		return nil, err
	}
	defer f.Close()
	var out []map[string]any
	s := bufio.NewScanner(f)
	for s.Scan() {
		line := strings.TrimSpace(s.Text())
		if line == "" {
			continue
		}
		var row map[string]any
		if err := json.Unmarshal([]byte(line), &row); err != nil {
			return nil, err
		}
		out = append(out, row)
	}
	return out, s.Err()
}
