package jpcmp

import (
	"bytes"
	"strings"
	"testing"
)

func TestServerCompletion(t *testing.T) { cfg := DefaultConfig(); cfg.DictionaryPaths = []string{"../../dict/domain.jsonl"}; server := NewServer(NewEngine(cfg)); frames := [][]byte{ Frame([]byte(`{"jsonrpc":"2.0","id":1,"method":"initialize","params":{}}`)), Frame([]byte(`{"jsonrpc":"2.0","method":"textDocument/didOpen","params":{"textDocument":{"uri":"file:///x.txt","text":"houjinScore houjinbaikyakuPlan\nhouji"}}}`)), Frame([]byte(`{"jsonrpc":"2.0","id":2,"method":"textDocument/completion","params":{"textDocument":{"uri":"file:///x.txt"},"position":{"line":1,"character":5}}}`)), Frame([]byte(`{"jsonrpc":"2.0","method":"exit"}`)), }; var in bytes.Buffer; for _, f := range frames { in.Write(f) }; var out bytes.Buffer; if err := server.Serve(&in,&out); err != nil { t.Fatal(err) }; if !strings.Contains(out.String(), "法人") { t.Fatalf("expected jp candidate in response: %s", out.String()) }; if !strings.Contains(out.String(), "houjinScore") { t.Fatalf("expected buffer candidate in response: %s", out.String()) } }
