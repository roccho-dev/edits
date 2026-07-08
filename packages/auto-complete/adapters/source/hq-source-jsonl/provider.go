package hqsourcejsonl

import (
	"github.com/roccho-dev/edits/packages/auto-complete/lib/jpcmp/ports"
	"strings"
)

type Provider struct{ CandidatesList []ports.Candidate }

func New(candidates []ports.Candidate) *Provider { return &Provider{CandidatesList: candidates} }
func (p *Provider) Source() string               { return "hq" }
func (p *Provider) Candidates(req ports.ProviderRequest) ([]ports.Candidate, error) {
	prefix := strings.ToLower(req.Token.Raw)
	out := []ports.Candidate{}
	for _, c := range p.CandidatesList {
		if strings.HasPrefix(strings.ToLower(c.Word), prefix) {
			c.Source = p.Source()
			out = append(out, c)
		}
	}
	if req.Limit > 0 && len(out) > req.Limit {
		return out[:req.Limit], nil
	}
	return out, nil
}
