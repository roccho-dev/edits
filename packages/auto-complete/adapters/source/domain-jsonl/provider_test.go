package domainjsonl

import (
	"github.com/roccho-dev/edits/packages/auto-complete/lib/jpcmp/core"
	"testing"
)

func TestProviderReadsDomainJSONL(t *testing.T) {
	p := New([]string{"../../../dict/domain.jsonl"})
	if len(p.Errors) != 0 {
		t.Fatalf("unexpected load errors: %#v", p.Errors)
	}
	token := core.Token{Raw: "houji", Reading: "ほうじ", Line: 0, StartChar: 0, EndChar: 5}
	cands, err := p.Candidates(core.ProviderRequest{Token: token, Limit: 12})
	if err != nil {
		t.Fatal(err)
	}
	labels := map[string]bool{}
	for _, c := range cands {
		labels[c.Word] = true
		if c.Source != "jp" {
			t.Fatalf("source = %s, want jp", c.Source)
		}
	}
	for _, want := range []string{"法人", "法人売却"} {
		if !labels[want] {
			t.Fatalf("missing %s in %#v", want, labels)
		}
	}
}
