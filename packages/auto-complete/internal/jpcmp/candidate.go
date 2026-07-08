package jpcmp

import (
	"fmt"
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

type Engine struct { Config Config; Dict Dictionary }
func NewEngine(config Config) *Engine { if config.MinChars == 0 { config.MinChars = 2 }; if config.BufferLimit == 0 { config.BufferLimit = 12 }; if config.DictionaryLimit == 0 { config.DictionaryLimit = 12 }; if config.MaxCandidates == 0 { config.MaxCandidates = 20 }; if config.SourcePriority == nil { config.SourcePriority = DefaultConfig().SourcePriority }; return &Engine{Config: config, Dict: LoadDictionary(config.DictionaryPaths)} }
func (e *Engine) Complete(text string, line, character int) (Token, []Candidate) { lines := strings.Split(text, "\n"); lineText := ""; if line >= 0 && line < len(lines) { lineText = lines[line] }; token := ExtractToken(lineText, line, character); if token.Raw == "" { return token, nil }; buffer := collectBuffer(text, token.Raw, e.Config.BufferLimit); jp := []Candidate{}; if isLower(token.Raw) && len(token.Raw) >= e.Config.MinChars { jp = e.Dict.Search(token.Raw, token.Reading, e.Config.DictionaryLimit) }; return token, e.merge([][]Candidate{buffer,jp}, e.Config.MaxCandidates) }
func (e *Engine) CompletionItems(text string, line, character int) []CompletionItem { token, cands := e.Complete(text,line,character); out := make([]CompletionItem,0,len(cands)); for i,c := range cands { out = append(out, CompletionItem{Label:c.Word, Detail:c.Reading, FilterText:token.Raw, SortText:fmt.Sprintf("%06d-%04d",999999-c.Score,i), TextEdit:&TextEdit{Range:Range{Start:Position{Line:token.Line,Character:token.StartChar},End:Position{Line:token.Line,Character:token.EndChar}},NewText:c.Word}, Data:c}) }; return out }
func collectBuffer(text,prefix string,limit int) []Candidate { freq := map[string]int{}; for _, w := range wordRE.FindAllString(text,-1) { freq[w]++ }; lower := strings.ToLower(prefix); out := []Candidate{}; for w,n := range freq { if w == prefix || !strings.HasPrefix(strings.ToLower(w), lower) { continue }; rank := 2000+n; if v, ok := goldenNormalRank[w]; ok { rank = v+n }; out = append(out, Candidate{Word:w, Source:"buffer", Rank:rank}) }; sort.Slice(out, func(i,j int) bool { if out[i].Rank != out[j].Rank { return out[i].Rank > out[j].Rank }; return out[i].Word < out[j].Word }); if limit > 0 && len(out) > limit { return out[:limit] }; return out }
func (e *Engine) merge(groups [][]Candidate, limit int) []Candidate { by := map[string]Candidate{}; for _, g := range groups { for _, x := range g { x.Score = e.Config.SourcePriority[x.Source] + x.Rank; if cur, ok := by[x.Word]; !ok || cur.Score < x.Score { by[x.Word] = x } } }; out := []Candidate{}; for _, x := range by { out = append(out,x) }; sort.Slice(out, func(i,j int) bool { if out[i].Score != out[j].Score { return out[i].Score > out[j].Score }; return out[i].Word < out[j].Word }); if limit > 0 && len(out) > limit { return out[:limit] }; return out }
func isLower(s string) bool { if s == "" { return false }; for i:=0;i<len(s);i++ { if s[i] < 'a' || s[i] > 'z' { return false } }; return true }
