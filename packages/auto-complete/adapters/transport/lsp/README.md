# LSP transport adapter

Owns JSON-RPC framing and the `textDocument/completion` transport mapping.

It maps LSP requests to the core engine and returns completion items with explicit `textEdit` ranges. It is wired by `cmd/jpcmp-lsp` through `app/jpcmp-lsp`.
