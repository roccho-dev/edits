# Vim LSP auto-popup UX proof

This proof keeps `<C-x><C-u>` as a manual fallback, not as the product UX.

The Vim-side adapter remains thin:

- `TextChangedI` is the trigger surface.
- The adapter requests completion through the LSP bridge.
- The LSP process owns candidate generation.
- The editor adapter records popup-eligible candidates.
- Completion and preview remain side-effect free.
- Side effects require a later explicit confirm/action path.

Run:

```sh
vim --clean -Nu NONE -n -es -S test/vim_lsp_adapter.vim
cat test/vim_lsp_adapter_result.json
```

The proof uses the hq source fixture through the same LSP command path:

```sh
go run ./cmd/jpcmp-lsp --dict dict/domain.jsonl --hq-source test/fixtures/hq.source.jsonl
```

Expected:

```json
{"status":"PASS","manual_insert_completion_required":0}
```

This is intentionally not a `vim-lsp` lock-in proof. A real Vim setup may use
`vim-lsp` plus `asyncomplete.vim`, or another completion UI. The contract here
is that automatic typing-triggered popup candidates come from the reusable LSP
adapter, not from hq-specific candidate logic embedded in Vimscript.
