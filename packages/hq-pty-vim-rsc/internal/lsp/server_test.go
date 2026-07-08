package lsp

import (
	"bufio"
	"bytes"
	"encoding/json"
	"io"
	"testing"

	"hq/internal/core"
	"hq/internal/jsonrpc"
)

func TestLSPCompletionCarriesPlanDraft(t *testing.T) {
	m, err := core.LoadWorld("../../examples/world.jsonl")
	if err != nil {
		t.Fatal(err)
	}
	input := bytes.Join([][]byte{
		jsonrpc.Frame(map[string]any{"jsonrpc": "2.0", "id": 1, "method": "initialize", "params": map[string]any{}}),
		jsonrpc.Frame(map[string]any{"jsonrpc": "2.0", "method": "textDocument/didOpen", "params": map[string]any{"textDocument": map[string]any{"uri": "file:///proof.hqcmd", "version": 2, "text": "pane.shell."}}}),
		jsonrpc.Frame(map[string]any{"jsonrpc": "2.0", "id": 2, "method": "textDocument/completion", "params": map[string]any{"textDocument": map[string]any{"uri": "file:///proof.hqcmd"}, "position": map[string]any{"line": 0, "character": 11}}}),
		jsonrpc.Frame(map[string]any{"jsonrpc": "2.0", "id": 3, "method": "shutdown"}),
	}, nil)
	var out bytes.Buffer
	if err := New(m).Serve(bytes.NewReader(input), &out); err != nil {
		t.Fatal(err)
	}
	msgs := readAllMessages(t, out.Bytes())
	var completion jsonrpc.Message
	for _, msg := range msgs {
		if string(msg.ID) == "2" {
			completion = msg
			break
		}
	}
	if len(completion.ID) == 0 {
		t.Fatalf("completion response not found; messages=%v", msgs)
	}
	b, _ := json.Marshal(completion.Result)
	var res struct {
		Items []struct {
			Label string         `json:"label"`
			Data  map[string]any `json:"data"`
		} `json:"items"`
	}
	if err := json.Unmarshal(b, &res); err != nil {
		t.Fatal(err)
	}
	if len(res.Items) == 0 {
		t.Fatalf("expected completion items")
	}
	foundPlan := false
	for _, item := range res.Items {
		if _, ok := item.Data["planDraft"]; ok {
			foundPlan = true
		}
	}
	if !foundPlan {
		t.Fatalf("completion item missing planDraft: %#v", res.Items)
	}
}

func TestLSPCompletionAfterEachTypedCharacter(t *testing.T) {
	m, err := core.LoadWorld("../../examples/world.jsonl")
	if err != nil {
		t.Fatal(err)
	}
	s := New(m)
	uri := "file:///vim-typed.hqcmd"
	_, _ = s.Handle(jsonrpc.Message{JSONRPC: "2.0", Method: "textDocument/didOpen", Params: mustRaw(map[string]any{"textDocument": map[string]any{"uri": uri, "version": 0, "text": ""}})})
	line := ""
	seenPositive := false
	for i, r := range "pane.shell." {
		line += string(r)
		_, err := s.Handle(jsonrpc.Message{JSONRPC: "2.0", Method: "textDocument/didChange", Params: mustRaw(map[string]any{"textDocument": map[string]any{"uri": uri, "version": i + 1}, "contentChanges": []map[string]any{{"text": line}}})})
		if err != nil {
			t.Fatal(err)
		}
		id, _ := json.Marshal(i + 1)
		responses, err := s.Handle(jsonrpc.Message{JSONRPC: "2.0", ID: id, Method: "textDocument/completion", Params: mustRaw(map[string]any{"textDocument": map[string]any{"uri": uri}, "position": map[string]any{"line": 0, "character": len([]rune(line))}})})
		if err != nil {
			t.Fatal(err)
		}
		if len(responses) == 0 {
			t.Fatalf("no completion response after %q", line)
		}
		b, _ := json.Marshal(responses[0].Result)
		var res struct {
			Items []struct {
				Label string `json:"label"`
			} `json:"items"`
		}
		if err := json.Unmarshal(b, &res); err != nil {
			t.Fatal(err)
		}
		if len(res.Items) > 0 {
			seenPositive = true
		}
	}
	if !seenPositive {
		t.Fatalf("expected at least one typed-prefix completion")
	}
}

func readAllMessages(t *testing.T, b []byte) []jsonrpc.Message {
	t.Helper()
	r := bufio.NewReader(bytes.NewReader(b))
	var msgs []jsonrpc.Message
	for {
		msg, err := jsonrpc.ReadMessage(r)
		if err == io.EOF {
			break
		}
		if err != nil {
			t.Fatal(err)
		}
		msgs = append(msgs, msg)
	}
	return msgs
}
