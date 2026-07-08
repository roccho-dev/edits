package jpcmplsp

import (
	transportlsp "github.com/roccho-dev/edits/packages/auto-complete/adapters/transport/lsp"
	"github.com/roccho-dev/edits/packages/auto-complete/lib/jpcmp/core"
)

func NewEngine(config Config) *core.Engine {
	return core.NewEngine(core.DefaultConfig(), SourceProviders(config)...)
}
func NewServer(config Config) *transportlsp.Server { return transportlsp.NewServer(NewEngine(config)) }
