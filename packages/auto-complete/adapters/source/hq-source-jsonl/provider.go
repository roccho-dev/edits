package hqsourcejsonl

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
	Kind      string `json:"kind"`
	Word      string `json:"word"`
	Reading   string `json:"reading"`
	Romaji    string `json:"romaji"`
	Rank      int    `json:"rank"`
	Source    string `json:"source"`
	Detail    string `json:"detail"`
	TargetRef string `json:"targetRef"`
	Command   string `json:"command"`
	Queue     string `json:"queue"`
}

type Provider struct {
	CandidatesList []ports.Candidate
	Errors         []error
}

func New(candidates []ports.Candidate) *Provider {
	return &Provider{CandidatesList: normalizeCandidates(candidates)}
}

func NewFromPaths(paths []string) *Provider {
	p := &Provider{}
	for _, path := range paths {
		_ = p.loadPath(path)
	}
	p.CandidatesList = normalizeCandidates(p.CandidatesList)
	return p
}

func (p *Provider) Source() string { return "hq" }

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
		candidate, ok, err := candidateFromRecord(record)
		if err != nil {
			p.Errors = append(p.Errors, fmt.Errorf("%s:%d %w", path, lineNo, err))
			continue
		}
		if ok {
			p.CandidatesList = append(p.CandidatesList, candidate)
		}
	}
	if err := scanner.Err(); err != nil {
		p.Errors = append(p.Errors, err)
		return err
	}
	return nil
}

func candidateFromRecord(record Record) (ports.Candidate, bool, error) {
	if record.Kind != "" && record.Kind != "hq.source.candidate.v1" && record.Kind != "hq.command.v1" && record.Kind != "hq.targetRef.v1" {
		return ports.Candidate{}, false, fmt.Errorf("unknown kind %q", record.Kind)
	}
	if record.Source != "" && record.Source != "hq" && record.Source != "hq-source-jsonl" {
		return ports.Candidate{}, false, fmt.Errorf("unknown source %q", record.Source)
	}
	word := firstNonEmpty(record.Word, record.Command, record.TargetRef, record.Queue)
	if word == "" {
		return ports.Candidate{}, false, fmt.Errorf("missing word/command/targetRef/queue")
	}
	rank := record.Rank
	if rank <= 0 {
		rank = 500
	}
	reading := firstNonEmpty(record.Reading, record.Romaji, record.Detail)
	return ports.Candidate{Word: word, Source: "hq", Rank: rank, Reading: reading}, true, nil
}

func firstNonEmpty(values ...string) string {
	for _, value := range values {
		value = strings.TrimSpace(value)
		if value != "" {
			return value
		}
	}
	return ""
}

func normalizeCandidates(candidates []ports.Candidate) []ports.Candidate {
	byWord := map[string]ports.Candidate{}
	for _, candidate := range candidates {
		candidate.Word = strings.TrimSpace(candidate.Word)
		if candidate.Word == "" {
			continue
		}
		candidate.Source = "hq"
		if candidate.Rank <= 0 {
			candidate.Rank = 500
		}
		current, ok := byWord[candidate.Word]
		if !ok || candidate.Rank > current.Rank {
			byWord[candidate.Word] = candidate
		}
	}
	out := make([]ports.Candidate, 0, len(byWord))
	for _, candidate := range byWord {
		out = append(out, candidate)
	}
	sort.Slice(out, func(i, j int) bool {
		if out[i].Rank != out[j].Rank {
			return out[i].Rank > out[j].Rank
		}
		return out[i].Word < out[j].Word
	})
	return out
}

func (p *Provider) Candidates(req ports.ProviderRequest) ([]ports.Candidate, error) {
	prefix := strings.ToLower(req.Token.Raw)
	out := []ports.Candidate{}
	for _, c := range p.CandidatesList {
		word := strings.ToLower(c.Word)
		reading := strings.ToLower(c.Reading)
		if strings.HasPrefix(word, prefix) || strings.HasPrefix(reading, prefix) {
			c.Source = p.Source()
			out = append(out, c)
		}
	}
	if req.Limit > 0 && len(out) > req.Limit {
		return out[:req.Limit], nil
	}
	return out, nil
}
