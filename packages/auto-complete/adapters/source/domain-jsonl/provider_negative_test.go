package domainjsonl

import (
	"os"
	"path/filepath"
	"testing"

	"github.com/roccho-dev/edits/packages/auto-complete/lib/jpcmp/core"
	"github.com/roccho-dev/edits/packages/auto-complete/lib/jpcmp/ports"
)

func TestDomainJSONLNegativeFixtures(t *testing.T) {
	path := filepath.Join(t.TempDir(), "negative.jsonl")
	content := "{bad-json}\n" +
		"{\"reading\":\"ほう\",\"romaji\":\"hou\",\"rank\":10,\"source\":\"jp-dict\"}\n" +
		"{\"reading\":\"ほう\",\"romaji\":\"hou\",\"word\":\"missingRank\",\"source\":\"jp-dict\"}\n" +
		"{\"word\":\"missingReading\",\"rank\":10,\"source\":\"jp-dict\"}\n" +
		"{\"reading\":\"ほう\",\"romaji\":\"hou\",\"word\":\"badSource\",\"rank\":10,\"source\":\"unknown\"}\n" +
		"{\"reading\":\"ほう\",\"romaji\":\"hou\",\"word\":\"houGood\",\"rank\":10,\"source\":\"jp-dict\"}\n" +
		"{\"reading\":\"ほう\",\"romaji\":\"hou\",\"word\":\"houGood\",\"rank\":10,\"source\":\"jp-dict\"}\n"
	if err := os.WriteFile(path, []byte(content), 0o600); err != nil {
		t.Fatal(err)
	}

	provider := New([]string{path})
	if len(provider.Errors) < 5 {
		t.Fatalf("expected negative fixture errors, got %d: %v", len(provider.Errors), provider.Errors)
	}
	got, err := provider.Candidates(ports.ProviderRequest{Token: core.Token{Raw: "hou", Reading: "ほう"}, Limit: 10})
	if err != nil {
		t.Fatalf("Candidates returned error: %v", err)
	}
	if len(got) != 1 || got[0].Word != "houGood" {
		t.Fatalf("bad rows must not become candidates and duplicates must dedupe: %#v", got)
	}
	empty, err := provider.Candidates(ports.ProviderRequest{Token: core.Token{Raw: "zzz", Reading: "zzz"}, Limit: 10})
	if err != nil {
		t.Fatalf("empty output returned error: %v", err)
	}
	if len(empty) != 0 {
		t.Fatalf("expected empty provider output for zzz, got %#v", empty)
	}
}
