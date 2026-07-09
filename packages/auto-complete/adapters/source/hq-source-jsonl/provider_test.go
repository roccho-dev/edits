package hqsourcejsonl

import (
	"testing"

	"github.com/roccho-dev/edits/packages/auto-complete/lib/jpcmp/core"
	"github.com/roccho-dev/edits/packages/auto-complete/lib/jpcmp/ports"
)

func TestHQSourceJSONLFixtureBecomesCandidates(t *testing.T) {
	provider := NewFromPaths([]string{"../../../test/fixtures/hq.source.jsonl"})
	if len(provider.Errors) != 0 {
		t.Fatalf("unexpected fixture errors: %v", provider.Errors)
	}
	got, err := provider.Candidates(ports.ProviderRequest{Token: core.Token{Raw: "model", Reading: "model"}, Limit: 10})
	if err != nil {
		t.Fatalf("Candidates returned error: %v", err)
	}
	if len(got) == 0 {
		t.Fatalf("expected hq candidates for model prefix")
	}
	if got[0].Word != "modelCommitQueued" || got[0].Source != "hq" || got[0].Rank != 720 {
		t.Fatalf("unexpected top hq candidate: %#v", got[0])
	}
	foundAddEdge := false
	for _, candidate := range got {
		if candidate.Word == "modelAddEdge" {
			foundAddEdge = true
			if candidate.Source != "hq" || candidate.Rank <= 0 {
				t.Fatalf("bad modelAddEdge candidate: %#v", candidate)
			}
		}
	}
	if !foundAddEdge {
		t.Fatalf("missing modelAddEdge in %#v", got)
	}
}
