# provider-port proposal

This folder advances the merged `auto-complete` package proposal with a transport-neutral provider boundary.

It does not import the full runnable tree directly. It records:

- proposal body
- artifact hashes
- file list
- ADR raw event
- verification notes
- scope and disruptive checks

Merge target remains `packages/auto-complete`. The provider port keeps current Vimscript implementation in-process and leaves LSP as a future adapter.
