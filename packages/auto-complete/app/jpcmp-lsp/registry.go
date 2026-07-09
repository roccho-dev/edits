package jpcmplsp

import (
	domainjsonl "github.com/roccho-dev/edits/packages/auto-complete/adapters/source/domain-jsonl"
	hqsourcejsonl "github.com/roccho-dev/edits/packages/auto-complete/adapters/source/hq-source-jsonl"
	"github.com/roccho-dev/edits/packages/auto-complete/lib/jpcmp/core"
)

func SourceProviders(config Config) []core.Provider {
	providers := []core.Provider{domainjsonl.New(config.DictionaryPaths)}
	if len(config.HQSourcePaths) > 0 {
		providers = append(providers, hqsourcejsonl.NewFromPaths(config.HQSourcePaths))
	}
	return providers
}
