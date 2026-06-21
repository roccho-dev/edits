# implementation note

This PR is intentionally a proposal/evidence step, not an exploded full source-tree import.

The import-ready artifact exists as `edits-auto-complete-provider-port.260621.zip` with sha256:

```text
3d6fa18b7ecbbb649cf520dec62e765af7c6a1f26eeede0ee570f26bf618dd14
```

The intended implementation merge is:

```sh
unzip edits-auto-complete-provider-port.260621.zip
rsync -a edits-provider-overlay/ ./
rm -rf packages/auto-complete/test/__pycache__
cd packages/auto-complete
./test/run.sh
```

Boundary preserved:

- provider port is transport-neutral
- default provider remains in-process Vimscript
- LSP/JSON-RPC is not implemented
- editor owns selected state, ghost, final rank, and commit
