# adapter: lsp

Portable LSP adapter boundary.

Current runnable server:

```sh
go run ./cmd/jpcmp-lsp --dict dict/domain.jsonl
```

Required behavior:

- answer `initialize`
- accept `textDocument/didOpen`
- answer `textDocument/completion`
- return candidates using `label`, `filterText`, `sortText`, and explicit `textEdit`
- keep all UI, key binding, popup, preview, and undo behavior in the editor client

CI proof:

```sh
python3 test/lsp_smoke.py
```
