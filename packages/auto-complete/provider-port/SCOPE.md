# scope

## In

- provider port contract v1
- in-process Vimscript provider remains default
- provider-local rank stays portable
- editor orchestrator collects buffer and provider candidates
- candidate core handles cross-source merge, dedupe, final rank and Vim display decoration
- cmp owns selected index
- lane derives ghost and commit result from the same selected item
- commit remains the sole buffer writer

## Out

- LSP transport
- JSON-RPC
- Helix adapter
- Neovim adapter
- external process lifecycle
- document sync
- cancellation
- dictionary service deployment

## Reason

Immediate full LSP extraction would add process, sync and protocol cost while the core UX value still belongs to the editor adapter.
