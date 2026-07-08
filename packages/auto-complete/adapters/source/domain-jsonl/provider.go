package domainjsonl

import (
	"bufio"
	"encoding/json"
	"os"
	"sort"
	"strings"

	"github.com/roccho-dev/edits/packages/auto-complete/lib/jpcmp/ports"
)

type Record struct {
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
	for scanner.Scan() {
		line := strings.TrimSpace(scanner.Text())
		if line == "" {
			continue
		}
		var record Record
		if err := json.Unmarshal([]byte(line), &record); err != nil {
			p.Errors = append(p.Errors, err)
			continue
		}
		record.Romaji = strings.ToLower(record.Romaji)
		p.Records = append(p.Records, record)
	}
	return scanner.Err()
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
