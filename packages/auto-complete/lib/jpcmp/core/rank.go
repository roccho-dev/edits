package core

import "sort"

func MergeCandidates(groups [][]Candidate, priority map[string]int, limit int) []Candidate {
	byWord := map[string]Candidate{}
	for _, group := range groups {
		for _, candidate := range group {
			candidate.Score = priority[candidate.Source] + candidate.Rank
			current, ok := byWord[candidate.Word]
			if !ok || current.Score < candidate.Score {
				byWord[candidate.Word] = candidate
			}
		}
	}
	out := make([]Candidate, 0, len(byWord))
	for _, candidate := range byWord {
		out = append(out, candidate)
	}
	sort.Slice(out, func(i, j int) bool {
		if out[i].Score != out[j].Score {
			return out[i].Score > out[j].Score
		}
		return out[i].Word < out[j].Word
	})
	if limit > 0 && len(out) > limit {
		return out[:limit]
	}
	return out
}
