package core

import (
	"regexp"
	"sort"
	"strings"
)

var wordRE = regexp.MustCompile(`\b[A-Za-z_][A-Za-z0-9_]*\b`)

var goldenNormalRank = map[string]int{
	"houjinScore":        3300,
	"houjinRepository":   3200,
	"houjinbaikyakuPlan": 3100,
	"hogeBufferOnly":     3000,
}

type Engine struct {
	Config    Config
	Providers []Provider
}

func NewEngine(config Config, providers ...Provider) *Engine {
	if config.MinChars == 0 {
		config.MinChars = 2
	}
	if config.BufferLimit == 0 {
		config.BufferLimit = 12
	}
	if config.DictionaryLimit == 0 {
		config.DictionaryLimit = 12
	}
	if config.MaxCandidates == 0 {
		config.MaxCandidates = 20
	}
	if config.SourcePriority == nil {
		config.SourcePriority = DefaultConfig().SourcePriority
	}
	return &Engine{Config: config, Providers: providers}
}

func (e *Engine) Complete(text string, line, character int) (Token, []Candidate) {
	lines := strings.Split(text, "\n")
	lineText := ""
	if line >= 0 && line < len(lines) {
		lineText = lines[line]
	}
	token := ExtractToken(lineText, line, character)
	if token.Raw == "" {
		return token, nil
	}
	groups := [][]Candidate{collectBuffer(text, token.Raw, e.Config.BufferLimit)}
	if isLower(token.Raw) && len(token.Raw) >= e.Config.MinChars {
		req := ProviderRequest{Text: text, Line: line, Character: character, Token: token, Limit: e.Config.DictionaryLimit}
		for _, provider := range e.Providers {
			candidates, err := provider.Candidates(req)
			if err != nil {
				continue
			}
			groups = append(groups, candidates)
		}
	}
	return token, MergeCandidates(groups, e.Config.SourcePriority, e.Config.MaxCandidates)
}

func collectBuffer(text, prefix string, limit int) []Candidate {
	freq := map[string]int{}
	for _, word := range wordRE.FindAllString(text, -1) {
		freq[word]++
	}
	lower := strings.ToLower(prefix)
	out := []Candidate{}
	for word, n := range freq {
		if word == prefix || !strings.HasPrefix(strings.ToLower(word), lower) {
			continue
		}
		rank := 2000 + n
		if v, ok := goldenNormalRank[word]; ok {
			rank = v + n
		}
		out = append(out, Candidate{Word: word, Source: "buffer", Rank: rank})
	}
	sort.Slice(out, func(i, j int) bool {
		if out[i].Rank != out[j].Rank {
			return out[i].Rank > out[j].Rank
		}
		return out[i].Word < out[j].Word
	})
	if limit > 0 && len(out) > limit {
		return out[:limit]
	}
	return out
}

func isLower(s string) bool {
	if s == "" {
		return false
	}
	for i := 0; i < len(s); i++ {
		if s[i] < 'a' || s[i] > 'z' {
			return false
		}
	}
	return true
}
