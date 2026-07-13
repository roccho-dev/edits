package main

import (
	"bufio"
	"encoding/json"
	"fmt"
	"io"
	"os"
	"path/filepath"
	"strconv"
	"strings"
)

func main() {
	profile, err := parseProfile(os.Args[1:])
	if err != nil {
		writeStartupError("invalid_arguments", "", err.Error())
		os.Exit(2)
	}
	_, queue, startupErr := resolveProfile(profile)
	if startupErr != nil {
		writeStartupError(startupErr.code, profile, startupErr.message)
		os.Exit(1)
	}
	if err := serve(os.Stdin, os.Stdout, queue); err != nil {
		fmt.Fprintln(os.Stderr, err)
		os.Exit(1)
	}
}

type startupError struct {
	code    string
	message string
}

func parseProfile(args []string) (string, error) {
	if len(args) != 3 || args[0] != "lsp" || args[1] != "--profile" || args[2] == "" {
		return "", fmt.Errorf("usage: hq lsp --profile <name>")
	}
	if filepath.Base(args[2]) != args[2] || args[2] == "." || args[2] == ".." {
		return "", fmt.Errorf("invalid profile name: %s", args[2])
	}
	return args[2], nil
}

func resolveProfile(profile string) (string, string, *startupError) {
	root := os.Getenv("HQ_STUB_ROOT")
	if root == "" {
		return "", "", &startupError{code: "profile_root_missing", message: "HQ_STUB_ROOT is required by the test fixture"}
	}
	dir := filepath.Join(root, profile)
	world := filepath.Join(dir, "world.jsonl")
	queue := filepath.Join(dir, "queue.jsonl")
	if !regularFile(world) {
		return "", "", &startupError{code: "profile_world_missing", message: "profile world JSONL does not exist"}
	}
	if !regularFile(queue) {
		return "", "", &startupError{code: "profile_queue_missing", message: "profile queue JSONL does not exist"}
	}
	f, err := os.OpenFile(queue, os.O_APPEND|os.O_WRONLY, 0)
	if err != nil {
		return "", "", &startupError{code: "profile_queue_not_writable", message: err.Error()}
	}
	_ = f.Close()
	return world, queue, nil
}

func regularFile(path string) bool {
	info, err := os.Stat(path)
	return err == nil && info.Mode().IsRegular()
}

func writeStartupError(code, profile, message string) {
	_ = json.NewEncoder(os.Stderr).Encode(map[string]any{
		"kind":    "hq.startup.error",
		"code":    code,
		"profile": profile,
		"message": message,
	})
}

type message struct {
	JSONRPC string          `json:"jsonrpc,omitempty"`
	ID      json.RawMessage `json:"id,omitempty"`
	Method  string          `json:"method,omitempty"`
	Params  json.RawMessage `json:"params,omitempty"`
	Result  any             `json:"result,omitempty"`
	Error   any             `json:"error,omitempty"`
}

func serve(r io.Reader, w io.Writer, queue string) error {
	br := bufio.NewReader(r)
	docs := map[string]string{}
	for {
		msg, err := readMessage(br)
		if err == io.EOF {
			return nil
		}
		if err != nil {
			return err
		}
		switch msg.Method {
		case "exit":
			return nil
		case "initialize":
			if err := writeMessage(w, message{JSONRPC: "2.0", ID: msg.ID, Result: map[string]any{
				"capabilities": map[string]any{
					"textDocumentSync":       1,
					"completionProvider":     map[string]any{"triggerCharacters": []string{"{", "\"", ":", "[", ","}},
					"codeActionProvider":     true,
					"executeCommandProvider": map[string]any{"commands": []string{"hq.submit"}},
				},
				"serverInfo": map[string]any{"name": "hqstub-lsp"},
			}}); err != nil {
				return err
			}
		case "initialized":
		case "shutdown":
			if err := writeMessage(w, message{JSONRPC: "2.0", ID: msg.ID, Result: nil}); err != nil {
				return err
			}
		case "textDocument/didOpen":
			var p struct {
				TextDocument struct {
					URI  string `json:"uri"`
					Text string `json:"text"`
				} `json:"textDocument"`
			}
			_ = json.Unmarshal(msg.Params, &p)
			docs[p.TextDocument.URI] = p.TextDocument.Text
			if err := writeDiagnostics(w, p.TextDocument.URI); err != nil {
				return err
			}
		case "textDocument/didChange":
			var p struct {
				TextDocument struct {
					URI string `json:"uri"`
				} `json:"textDocument"`
				ContentChanges []struct {
					Text string `json:"text"`
				} `json:"contentChanges"`
			}
			_ = json.Unmarshal(msg.Params, &p)
			if len(p.ContentChanges) > 0 {
				docs[p.TextDocument.URI] = p.ContentChanges[len(p.ContentChanges)-1].Text
			}
			if err := writeDiagnostics(w, p.TextDocument.URI); err != nil {
				return err
			}
		case "textDocument/completion":
			if err := writeMessage(w, message{JSONRPC: "2.0", ID: msg.ID, Result: map[string]any{
				"isIncomplete": false,
				"items":        completionItems(),
			}}); err != nil {
				return err
			}
		case "textDocument/codeAction":
			var p struct {
				TextDocument struct {
					URI string `json:"uri"`
				} `json:"textDocument"`
			}
			_ = json.Unmarshal(msg.Params, &p)
			actions := []map[string]any{{
				"title": "HQ Submit", "kind": "quickfix",
				"command": map[string]any{
					"title": "HQ Submit", "command": "hq.submit",
					"arguments": []any{map[string]any{"uri": p.TextDocument.URI}},
				},
			}}
			if err := writeMessage(w, message{JSONRPC: "2.0", ID: msg.ID, Result: actions}); err != nil {
				return err
			}
		case "workspace/executeCommand":
			var p struct {
				Command   string `json:"command"`
				Arguments []struct {
					URI string `json:"uri"`
				} `json:"arguments"`
			}
			if err := json.Unmarshal(msg.Params, &p); err != nil || p.Command != "hq.submit" || len(p.Arguments) != 1 {
				if err := writeError(w, msg.ID, -32602, "invalid hq.submit request"); err != nil {
					return err
				}
				continue
			}
			var request struct {
				Path string `json:"path"`
			}
			if err := json.Unmarshal([]byte(docs[p.Arguments[0].URI]), &request); err != nil || request.Path == "" {
				if err := writeError(w, msg.ID, -32602, "invalid host-open buffer"); err != nil {
					return err
				}
				continue
			}
			row := map[string]any{
				"kind":        "hq.hostCommandQueued.v1",
				"id":          "hqcmd_stub",
				"status":      "queued",
				"command":     "host.open",
				"path":        request.Path,
				"confirmedBy": "yegappan/lsp",
			}
			if err := appendJSONL(queue, row); err != nil {
				return err
			}
			result := map[string]any{"kind": "hq.submitResult.v1", "status": "queued", "queueKind": row["kind"], "queueId": row["id"]}
			if err := writeMessage(w, message{JSONRPC: "2.0", ID: msg.ID, Result: result}); err != nil {
				return err
			}
		default:
			if len(msg.ID) != 0 {
				if err := writeMessage(w, message{JSONRPC: "2.0", ID: msg.ID, Error: map[string]any{"code": -32601, "message": "method not found"}}); err != nil {
					return err
				}
			}
		}
		_ = docs
	}
}

func completionItems() []map[string]any {
	out := []map[string]any{}
	for _, label := range []string{"task:t1", "task:t2", "task:t3"} {
		out = append(out, map[string]any{
			"label":      label,
			"kind":       14,
			"insertText": strings.TrimPrefix(label, "task:"),
			"data": map[string]any{"suggestion": map[string]any{
				"label":          label,
				"id":             "sug_stub_" + strings.ReplaceAll(label, ":", "_"),
				"hash":           "hash_stub_" + strings.ReplaceAll(label, ":", "_"),
				"buffer_version": 1,
				"compile_draft":  map[string]any{"side_effect": false},
			}},
		})
	}
	return out
}

func appendJSONL(path string, row any) error {
	if err := os.MkdirAll(filepath.Dir(path), 0o755); err != nil {
		return err
	}
	f, err := os.OpenFile(path, os.O_CREATE|os.O_APPEND|os.O_WRONLY, 0o644)
	if err != nil {
		return err
	}
	defer f.Close()
	b, err := json.Marshal(row)
	if err != nil {
		return err
	}
	_, err = f.Write(append(b, '\n'))
	return err
}

func readMessage(r *bufio.Reader) (message, error) {
	length := -1
	for {
		line, err := r.ReadString('\n')
		if err != nil {
			return message{}, err
		}
		line = strings.TrimRight(line, "\r\n")
		if line == "" {
			break
		}
		parts := strings.SplitN(line, ":", 2)
		if len(parts) == 2 && strings.EqualFold(strings.TrimSpace(parts[0]), "Content-Length") {
			n, err := strconv.Atoi(strings.TrimSpace(parts[1]))
			if err != nil {
				return message{}, err
			}
			length = n
		}
	}
	if length < 0 {
		return message{}, fmt.Errorf("missing Content-Length")
	}
	body := make([]byte, length)
	if _, err := io.ReadFull(r, body); err != nil {
		return message{}, err
	}
	var msg message
	return msg, json.Unmarshal(body, &msg)
}

func writeMessage(w io.Writer, msg message) error {
	b, err := json.Marshal(msg)
	if err != nil {
		return err
	}
	_, err = fmt.Fprintf(w, "Content-Length: %d\r\n\r\n%s", len(b), b)
	return err
}

func writeError(w io.Writer, id json.RawMessage, code int, text string) error {
	return writeMessage(w, message{
		JSONRPC: "2.0",
		ID:      id,
		Error:   map[string]any{"code": code, "message": text},
	})
}

func writeDiagnostics(w io.Writer, uri string) error {
	params, err := json.Marshal(map[string]any{"uri": uri, "diagnostics": []any{}})
	if err != nil {
		return err
	}
	return writeMessage(w, message{
		JSONRPC: "2.0",
		Method:  "textDocument/publishDiagnostics",
		Params:  params,
	})
}
