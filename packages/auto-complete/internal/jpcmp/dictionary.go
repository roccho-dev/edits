package jpcmp

import (
	"bufio"
	"encoding/json"
	"os"
	"sort"
	"strings"
)

type DictRecord struct { Word string `json:"word"`; Reading string `json:"reading"`; Romaji string `json:"romaji"`; Rank int `json:"rank"`; Source string `json:"source"` }
type Dictionary struct { Records []DictRecord; Errors []error }
func LoadDictionary(paths []string) Dictionary { d := Dictionary{}; for _, p := range paths { _ = d.loadPath(p) }; return d }
func (d *Dictionary) loadPath(path string) error { f, err := os.Open(path); if err != nil { d.Errors = append(d.Errors, err); return err }; defer f.Close(); s := bufio.NewScanner(f); for s.Scan() { line := strings.TrimSpace(s.Text()); if line == "" { continue }; var r DictRecord; if err := json.Unmarshal([]byte(line), &r); err != nil { d.Errors = append(d.Errors, err); continue }; r.Romaji = strings.ToLower(r.Romaji); d.Records = append(d.Records, r) }; return s.Err() }
func (d Dictionary) Search(raw, reading string, limit int) []Candidate { raw = strings.ToLower(raw); out := []Candidate{}; for _, r := range d.Records { if strings.HasPrefix(r.Romaji, raw) || strings.HasPrefix(r.Reading, reading) { out = append(out, Candidate{Word:r.Word, Source:"jp", Rank:100-r.Rank, Reading:r.Reading}) } }; sort.Slice(out, func(i,j int) bool { if out[i].Rank != out[j].Rank { return out[i].Rank > out[j].Rank }; return out[i].Word < out[j].Word }); if limit > 0 && len(out) > limit { return out[:limit] }; return out }
