# auto-complete

A small domain Japanese completion package.

This package keeps the current Vim proof behavior as a golden contract while exposing a cleaner reusable boundary:

```text
lib/jpcmp/core + lib/jpcmp/ports
  <- source adapters
  <- transport adapters
  <- editor adapters
  <- app wiring
```

## Current golden behavior

- raw buffer remains romaji / English while typing
- normal candidates and Japanese domain dictionary candidates coexist
- normal candidates keep priority in the current default rank
- Japanese candidates replace only the active romaji run at commit time

## Commands

```sh
bash test/run.sh
python3 test/golden_check.py
go test ./...
python3 test/lsp_smoke.py
vim --clean -Nu NONE -n -es -S test/vim_lsp_adapter.vim
python3 test/render_ux_visual.py
python3 test/ux_visual_check.py
python3 test/boundary_check.py
python3 test/helix_config_check.py
```

## Scope

This is not a general Japanese IME. It is a domain completion core plus adapter wiring for LSP/editor clients.
