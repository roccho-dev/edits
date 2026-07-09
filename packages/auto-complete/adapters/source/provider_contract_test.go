package source_test

import (
	"os"
	"path/filepath"
	"testing"

	domainjsonl "github.com/roccho-dev/edits/packages/auto-complete/adapters/source/domain-jsonl"
	hqsourcejsonl "github.com/roccho-dev/edits/packages/auto-complete/adapters/source/hq-source-jsonl"
	jpjsonl "github.com/roccho-dev/edits/packages/auto-complete/adapters/source/jp-jsonl"
	"github.com/roccho-dev/edits/packages/auto-complete/lib/jpcmp/core"
	"github.com/roccho-dev/edits/packages/auto-complete/lib/jpcmp/ports"
)

func writeFixture(t *testing.T, name string) string {
	t.Helper()
	path := filepath.Join(t.TempDir(), name)
	content := "{\"reading\":\"ほう\",\"romaji\":\"hou\",\"word\":\"houProviderCandidate\",\"rank\":10,\"source\":\"jp-dict\"}\n"
	if err := os.WriteFile(path, []byte(content), 0o600); err != nil {
		t.Fatal(err)
	}
	return path
}

func TestProviderPortContractAcrossSourceAdapters(t *testing.T) {
	domainPath := writeFixture(t, "domain.jsonl")
	jpPath := writeFixture(t, "jp.jsonl")
	req := ports.ProviderRequest{Token: core.Token{Raw: "hou", Reading: "ほう"}, Limit: 10}

	cases := []struct {
		name     string
		provider ports.Provider
	}{
		{name: "domain-jsonl", provider: domainjsonl.New([]string{domainPath})},
		{name: "jp-jsonl", provider: jpjsonl.New([]string{jpPath})},
		{name: "hq-source-jsonl", provider: hqsourcejsonl.New([]ports.Candidate{{Word: "houModelCommand", Reading: "hou model command", Rank: 700}})},
	}

	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			first, err := tc.provider.Candidates(req)
			if err != nil {
				t.Fatalf("Candidates returned error: %v", err)
			}
			second, err := tc.provider.Candidates(req)
			if err != nil {
				t.Fatalf("Candidates second run returned error: %v", err)
			}
			if len(first) == 0 {
				t.Fatalf("expected at least one normalized candidate")
			}
			if len(first) != len(second) {
				t.Fatalf("non-deterministic length: first=%d second=%d", len(first), len(second))
			}
			for i, candidate := range first {
				if candidate.Word == "" {
					t.Fatalf("candidate %d missing word: %#v", i, candidate)
				}
				if candidate.Source == "" {
					t.Fatalf("candidate %d missing source: %#v", i, candidate)
				}
				if candidate.Rank == 0 {
					t.Fatalf("candidate %d missing rank: %#v", i, candidate)
				}
				if candidate.Word != second[i].Word || candidate.Source != second[i].Source || candidate.Rank != second[i].Rank {
					t.Fatalf("non-deterministic candidate at %d: %#v != %#v", i, candidate, second[i])
				}
			}
		})
	}
}
