# adapter: helix

Helix adapter boundary.

Helix should use this package as a normal LSP client. Do not add custom Helix UI or key handling for this package.

Expected usage:

```toml
[language-server.jpcmp]
command = "jpcmp-lsp"
args = ["--dict", "dict/domain.jsonl"]
```

Helix-specific proof is limited to config shape and LSP behavior. Candidate generation remains in the Go core and LSP adapter.
