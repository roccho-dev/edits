# Vim editor adapter

Vim proof adapter for calling the Go LSP process.

This adapter does not parse dictionaries, merge rank, or generate candidates. It asks `cmd/jpcmp-lsp` for completion items and checks the response shape.
