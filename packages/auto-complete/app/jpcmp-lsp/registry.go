package jpcmplsp

import (
	domainjsonl "github.com/roccho-dev/edits/packages/auto-complete/adapters/source/domain-jsonl"
	"github.com/roccho-dev/edits/packages/auto-complete/lib/jpcmp/core"
)

func SourceProviders(config Config) []core.Provider {
	return []core.Provider{domainjsonl.New(config.DictionaryPaths)}
}
