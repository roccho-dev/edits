package core

import "testing"

type testProvider struct{}

func (testProvider) Source() string { return "jp" }
func (testProvider) Candidates(req ProviderRequest) ([]Candidate, error) {
	rows := []struct {
		romaji, reading, word string
		rank                  int
	}{{"houjin", "ほうじん", "法人", 10}, {"houjinbaikyaku", "ほうじんばいきゃく", "法人売却", 20}}
	out := []Candidate{}
	for _, row := range rows {
		if hasPrefix(row.romaji, req.Token.Raw) || hasPrefix(row.reading, req.Token.Reading) {
			out = append(out, Candidate{Word: row.word, Source: "jp", Rank: 100 - row.rank, Reading: row.reading})
		}
	}
	return out, nil
}
func hasPrefix(s, prefix string) bool { return len(s) >= len(prefix) && s[:len(prefix)] == prefix }

func TestCompletionMatchesGoldenCandidateShape(t *testing.T) {
	engine := NewEngine(DefaultConfig(), testProvider{})
	text := "houjinScore houjinRepository houjinbaikyakuPlan hogeBufferOnly\nhouji"
	items := engine.CompletionItems(text, 1, len("houji"))
	if len(items) == 0 {
		t.Fatal("expected candidates")
	}
	if items[0].Label != "houjinScore" {
		t.Fatalf("top = %s, want houjinScore", items[0].Label)
	}
	labels := map[string]bool{}
	for _, item := range items {
		labels[item.Label] = true
	}
	for _, want := range []string{"houjinScore", "法人", "法人売却"} {
		if !labels[want] {
			t.Fatalf("missing %s in %#v", want, labels)
		}
	}
	for _, item := range items {
		if item.Label == "法人売却" {
			if item.TextEdit == nil || item.TextEdit.Range.Start.Character != 0 || item.TextEdit.Range.End.Character != len("houji") {
				t.Fatalf("bad textEdit: %#v", item.TextEdit)
			}
			if item.FilterText != "houji" {
				t.Fatalf("filterText = %s", item.FilterText)
			}
			return
		}
	}
	t.Fatal("法人売却 not found")
}
