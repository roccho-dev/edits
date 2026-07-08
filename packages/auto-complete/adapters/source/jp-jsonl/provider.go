package jpjsonl

import domainjsonl "github.com/roccho-dev/edits/packages/auto-complete/adapters/source/domain-jsonl"

type Provider = domainjsonl.Provider

func New(paths []string) *Provider { return domainjsonl.New(paths) }
