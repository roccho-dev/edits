# HTTP / shell / Vim autocmp proof

Run:

```sh
./scripts/proof.sh
```

Artifacts:

- `cache/http.dispatch.json`: real HTTP adapter response from fixture server.
- `cache/shell.dispatch.json`: real shell adapter stdout.
- `cache/main.receipt.jsonl`: dispatch receipts.
- `cache/lsp-typed.jsonl`: completion after each simulated typed character via LSP server state.
- `cache/vim-autocmp.jsonl`: Vim buffer one-character changes triggering hq completion probe.

Caveat: this repository does not vendor a Vim LSP client such as vim-lsp or coc.nvim. The Vim proof checks the Vim-side autocmp hook and the LSP proof checks the JSON-RPC completion path.
