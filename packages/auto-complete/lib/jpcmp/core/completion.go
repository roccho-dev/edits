package core

import "fmt"

func (e *Engine) CompletionItems(text string, line, character int) []CompletionItem {
	token, candidates := e.Complete(text, line, character)
	out := make([]CompletionItem, 0, len(candidates))
	for i, candidate := range candidates {
		out = append(out, CompletionItem{Label: candidate.Word, Detail: candidate.Reading, FilterText: token.Raw, SortText: fmt.Sprintf("%06d-%04d", 999999-candidate.Score, i), TextEdit: &TextEdit{Range: ReplaceRange(token), NewText: candidate.Word}, Data: candidate})
	}
	return out
}
