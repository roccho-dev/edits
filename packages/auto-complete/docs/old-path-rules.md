# old path rules

Executable implementation must not return to these legacy paths:

- `internal/jpcmp`
- `providers/*`
- `adapters/lsp`
- `adapters/vim`
- `adapters/helix`

Canonical locations are:

- `lib/jpcmp/core` for pure candidate behavior
- `lib/jpcmp/ports` for provider/request/response boundaries
- `adapters/source/*` for concrete source readers
- `adapters/transport/lsp` for LSP transport
- `adapters/editor/*` for editor assets
- `app/jpcmp-lsp` for concrete wiring

Historical docs may exist only when clearly marked as historical or non-authority.
