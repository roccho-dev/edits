package lsp

import (
	"bytes"
	"strings"
	"testing"

	"github.com/roccho-dev/edits/packages/auto-complete/lib/jpcmp/core"
)

type testProvider struct{}

func (testProvider) Source() string { return "jp" }
func (testProvider) Candidates(req core.ProviderRequest) ([]core.Candidate, error) {
	return []core.Candidate{{Word: "法人", Source: "jp", Rank: 90, Reading: "ほうじん"}, {Word: "法人売却", Source: "jp", Rank: 80, Reading: "ほうじんばいきゃく"}}, nil
}

func TestServerCompletion(t *testing.T) {
	server := NewServer(core.NewEngine(core.DefaultConfig(), testProvider{}))
	frames := [][]byte{
		Frame([]byte(`{"jsonrpc":"2.0","id":1,"method":"initialize","params":{}}`)),
		Frame([]byte(`{"jsonrpc":"2.0","method":"textDocument/didOpen","params":{"textDocument":{"uri":"file:///x.txt","text":"houjinScore houjinbaikyakuPlan\nhouji"}}}`)),
		Frame([]byte(`{"jsonrpc":"2.0","id":2,"method":"textDocument/completion","params":{"textDocument":{"uri":"file:///x.txt"},"position":{"line":1,"character":5}}}`)),
		Frame([]byte(`{"jsonrpc":"2.0","method":"exit"}`)),
	}
	var in bytes.Buffer
	for _, frame := range frames {
		in.Write(frame)
	}
	var out bytes.Buffer
	if err := server.Serve(&in, &out); err != nil {
		t.Fatal(err)
	}
	if !strings.Contains(out.String(), "法人") {
		t.Fatalf("expected jp candidate in response: %s", out.String())
	}
	if !strings.Contains(out.String(), "houjinScore") {
		t.Fatalf("expected buffer candidate in response: %s", out.String())
	}
}
