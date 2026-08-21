# Local-first development boundary

Develop and verify the product/test delta in the current sandbox before any
GitHub write. The locked Nix closure is **not** a prerequisite for this inner
loop.

```text
current source
→ static checks
→ unpatched controlling-TTY RED
→ apply the test-only patch to a temporary copy
→ patched Go tests + controlling-TTY GREEN
→ real Vim feedkeys n/nx race proof
→ OCI verifier positive/mutation proof
→ optional Herdr exactly-two-pane/clean-stop proof
→ local Receipt
→ only then push one canonical head
```

Run:

```bash
HERDR_BIN=/path/to/herdr tools/vim-nix-local/verify.sh
```

`HERDR_BIN` is optional because the current delta is the hq-vim proof harness,
not Herdr itself. Supplying the already verified Herdr 0.8.0 binary adds an
isolated server/workspace proof with exactly two panes, observed child
processes, workspace close, and server stop.

The local runner never edits `packages/hq-vim/internal/smoke/smoke.go`. It
copies the package to a temporary directory and applies
`hq-vim-native-popup-proof.patch` there. Generated evidence goes under
`.local/vim-nix-proof` by default and is excluded from Git.

## Deliberately deferred high-cost gates

These prove exact distribution and reproducibility rather than the small
source delta, so they remain a separate later CI lane:

- exact Nix output-closure materialization;
- normal/offline same-store-path rebuild with empty substituters;
- exact Vim 9.2.0478, exact yegappan/lsp, and exact HQ integration replay;
- complete exact-product Herdr/HQ/worker lifecycle;
- Docker/OCI semantic parity and mutation rejection on the real image;
- independent WSLC physical readback.

A local PASS does not claim those gates. Conversely, absence of the exact Nix
closure no longer blocks implementation, review, or targeted TTY/race/adapter
verification.

## Immediate UX and Carry

The single entrypoint is:

```bash
tools/vim-nix-local/vim-nix doctor
tools/vim-nix-local/vim-nix verify
tools/vim-nix-local/vim-nix pack --herdr /absolute/path/to/herdr
```

`verify` auto-discovers Herdr from `HERDR_BIN`, `./bin/herdr`,
`./.carry/bin/herdr`, or `PATH`. `pack` emits a deterministic ZIP, a strict
single-line standard-Base64 Carrier, and an external manifest. The extracted
pack starts with:

```bash
bash run
```

The Carry contains the low-cost local development surface, not the deferred
exact-product Nix closure.
