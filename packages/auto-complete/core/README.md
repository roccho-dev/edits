# core

Editor-neutral completion core.

Responsibilities:

- extract the current romaji run
- project romaji to kana through a small wrapper or existing library
- normalize provider candidates
- merge and rank candidates deterministically
- calculate replacement ranges
- expose editor-neutral completion records

Non-responsibilities:

- Vimscript UI
- Helix UI
- popup or ghost rendering
- key handling
- general Japanese IME conversion

Current Go implementation lives under `internal/jpcmp` and is exercised through `cmd/jpcmp-lsp` and tests.
