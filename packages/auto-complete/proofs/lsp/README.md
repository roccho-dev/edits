# proof: lsp

LSP proof checks the process boundary, not editor UI.

Current CI command:

```sh
python3 test/lsp_smoke.py
```

The proof asserts that `jpcmp-lsp` returns the same candidate contract as the Vim golden proof and uses explicit `textEdit` replacement range for Japanese candidates.
