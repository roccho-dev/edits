package domainjsonl

import (
	"bufio"
	"encoding/json"
	"fmt"
	"os"
	"sort"
	"strings"

	"github.com/roccho-dev/edits/packages/auto-complete/lib/jpcmp/ports"
)

type Record struct {
	Kind    string `json:"kind"`
	Word    string `json:"word"`
	Reading string `json:"reading"`
	Romaji  string `json:"romaji"`
	Rank    int    `json:"rank"`
	Source  string `json:"source"`
}
type Provider struct {
	Records []Record
	Errors  []error
}

func New(paths []string) *Provider {
	p := &Provider{}
	for _, path := range paths {
		_ = p.loadPath(path)
	}
	return p
}
func (p *Provider) Source() string { return "jp" }
func (p *Provider) loadPath(path string) error {
	file, err := os.Open(path)
	if err != nil {
		p.Errors = append(p.Errors, err)
		return err
	}
	defer file.Close()
	scanner := bufio.NewScanner(file)
	lineNo := 0
	for scanner.Scan() {
		lineNo++
		line := strings.TrimSpace(scanner.Text())
		if line == "" {
			continue
		}
		var record Record
		if err := json.Unmarshal([]byte(line), &record); err != nil {
			p.Errors = append(p.Errors, fmt.Errorf("%s:%d malformed JSONL: %w", path, lineNo, err))
			continue
		}
		if err := p.addRecord(record, path, lineNo); err != nil {
			p.Errors = append(p.Errors, err)
			continue
		}
	}
	if err := scanner.Err(); err != nil {
		p.Errors = append(p.Errors, err)
		return err
	}
	return nil
}

func (p *Provider) addRecord(record Record, path string, lineNo int) error {
	record.Romaji = strings.ToLower(strings.TrimSpace(record.Romaji))
	record.Reading = strings.TrimSpace(record.Reading)
	record.Word = strings.TrimSpace(record.Word)
	record.Source = strings.TrimSpace(record.Source)
	record.Kind = strings.TrimSpace(record.Kind)
	if record.Word == "" {
		return fmt.Errorf("%s:%d missing required word", path, lineNo)
	}
	if record.Rank <= 0 {
		return fmt.Errorf("%s:%d missing or invalid rank for %q", path, lineNo, record.Word)
	}
	if record.Reading == "" && record.Romaji == "" {
		return fmt.Errorf("%s:%d reading or romaji is required for %q", path, lineNo, record.Word)
	}
	if record.Kind != "" && record.Kind != "jp-dict" && record.Kind != "domain-jsonl" && record.Kind != "completion.candidate.v1" {
		return fmt.Errorf("%s:%d unknown kind %q", path, lineNo, record.Kind)
	}
	if record.Source != "" && record.Source != "jp-dict" && record.Source != "jp" && record.Source != "domain-jsonl" {
		return fmt.Errorf("%s:%d unknown source %q", path, lineNo, record.Source)
	}
	for _, current := range p.Records {
		if current.Word == record.Word && current.Reading == record.Reading && current.Romaji == record.Romaji {
			return nil
		}
	}
	p.Records = append(p.Records, record)
	return nil
}

func (p *Provider) Candidates(req ports.ProviderRequest) ([]ports.Candidate, error) {
	raw := strings.ToLower(req.Token.Raw)
	out := []ports.Candidate{}
	for _, record := range p.Records {
		if strings.HasPrefix(record.Romaji, raw) || strings.HasPrefix(record.Reading, req.Token.Reading) {
			out = append(out, ports.Candidate{Word: record.Word, Source: p.Source(), Rank: 100 - record.Rank, Reading: record.Reading})
		}
	}
	sort.Slice(out, func(i, j int) bool {
		if out[i].Rank != out[j].Rank {
			return out[i].Rank > out[j].Rank
		}
		return out[i].Word < out[j].Word
	})
	if req.Limit > 0 && len(out) > req.Limit {
		return out[:req.Limit], nil
	}
	return out, nil
}
