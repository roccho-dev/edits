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
	"unicode/utf16"
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

type document struct {
	text    string
	version int
}

func serve(r io.Reader, w io.Writer, queue string) error {
	br := bufio.NewReader(r)
	docs := map[string]document{}
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
					URI     string `json:"uri"`
					Text    string `json:"text"`
					Version int    `json:"version"`
				} `json:"textDocument"`
			}
			_ = json.Unmarshal(msg.Params, &p)
			docs[p.TextDocument.URI] = document{text: p.TextDocument.Text, version: p.TextDocument.Version}
			if err := writeDiagnostics(w, p.TextDocument.URI); err != nil {
				return err
			}
		case "textDocument/didChange":
			var p struct {
				TextDocument struct {
					URI     string `json:"uri"`
					Version int    `json:"version"`
				} `json:"textDocument"`
				ContentChanges []struct {
					Text string `json:"text"`
				} `json:"contentChanges"`
			}
			_ = json.Unmarshal(msg.Params, &p)
			if len(p.ContentChanges) > 0 {
				docs[p.TextDocument.URI] = document{text: p.ContentChanges[len(p.ContentChanges)-1].Text, version: p.TextDocument.Version}
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
				Range struct {
					Start struct {
						Line int `json:"line"`
					} `json:"start"`
				} `json:"range"`
			}
			_ = json.Unmarshal(msg.Params, &p)
			doc := docs[p.TextDocument.URI]
			actions := []map[string]any{{
				"title": "HQ Submit", "kind": "quickfix",
				"command": map[string]any{
					"title": "HQ Submit", "command": "hq.submit",
					"arguments": []any{map[string]any{"uri": p.TextDocument.URI, "version": doc.version, "line": p.Range.Start.Line}},
				},
			}}
			if err := writeMessage(w, message{JSONRPC: "2.0", ID: msg.ID, Result: actions}); err != nil {
				return err
			}
		case "workspace/executeCommand":
			var p struct {
				Command   string `json:"command"`
				Arguments []struct {
					URI     string `json:"uri"`
					Version int    `json:"version"`
				} `json:"arguments"`
			}
			if err := json.Unmarshal(msg.Params, &p); err != nil || p.Command != "hq.submit" || len(p.Arguments) != 1 {
				if err := writeError(w, msg.ID, -32602, "invalid hq.submit request"); err != nil {
					return err
				}
				continue
			}
			doc, ok := docs[p.Arguments[0].URI]
			if !ok || doc.version != p.Arguments[0].Version {
				if err := writeError(w, msg.ID, -32602, "stale hq.submit document"); err != nil {
					return err
				}
				continue
			}
			path := hostOpenPath(doc.text)
			if path == "" {
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
				"path":        path,
				"confirmedBy": "yegappan/lsp",
			}
			if err := appendJSONL(queue, row); err != nil {
				return err
			}
			result := map[string]any{"kind": "hq.submitResult.v1", "status": "queued", "queueKind": row["kind"], "queueId": row["id"]}
			switch os.Getenv("HQ_STUB_PLAN_MODE") {
			case "none":
			case "invalid":
				result["draftConsumption"] = draftConsumption(p.Arguments[0].URI, doc.version, map[string]int{"line": 999, "character": 0})
			default:
				result["draftConsumption"] = draftConsumption(p.Arguments[0].URI, doc.version, documentEnd(doc.text))
			}
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

func hostOpenPath(text string) string {
	var request struct {
		Path string `json:"path"`
	}
	if json.Unmarshal([]byte(text), &request) == nil && request.Path != "" {
		return request.Path
	}
	for _, line := range strings.Split(text, "\n") {
		key, value, ok := strings.Cut(strings.TrimSpace(line), "=")
		if ok && key == "path" {
			return strings.Trim(strings.TrimSpace(value), `"`)
		}
	}
	return ""
}

func documentEnd(text string) map[string]int {
	lines := strings.Split(text, "\n")
	last := strings.TrimSuffix(lines[len(lines)-1], "\r")
	return map[string]int{"line": len(lines) - 1, "character": len(utf16.Encode([]rune(last)))}
}

func draftConsumption(uri string, version int, end map[string]int) map[string]any {
	return map[string]any{
		"kind":         "hq.draftConsumption.v1",
		"textDocument": map[string]any{"uri": uri, "version": version},
		"edits": []any{map[string]any{
			"range":   map[string]any{"start": map[string]int{"line": 0, "character": 0}, "end": end},
			"newText": "",
		}},
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
