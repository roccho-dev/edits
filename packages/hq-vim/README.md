# hq Vim

Minimal edits-owned Vim extension for an external `hq` runtime.

```text
Vim
  -> vim-lsp
    -> external hq binary
      -> lsp --profile <name>
```

## Boundary

This package owns only:

- `plugin/hq.vim`
- `autoload/hq.vim`
- fail-fast dependency checks
- Go-based smoke tests for Vim/vim-lsp process integration

This package does not build, install, or place `hq`. The final `hq` runtime is
owned outside edits, expected in the ops/runtime side. If `hq` is missing, the
Vim extension fails immediately. Profile resolution, JSONL paths, validation,
queue persistence, receipts, and runtime errors belong to `hq`.

## Herdr Vim Init

The YAGNI integration is only these settings in the Vim init used by Herdr:

```vim
set runtimepath^=C:/Users/resta/AppData/Local/codex-proof/vim-lsp
set runtimepath^=C:/Users/resta/Codex/repos/edits/packages/hq-vim
runtime plugin/lsp.vim
runtime plugin/hq.vim
let g:hq_bin='C:/path/to/hq.exe'
```

Then in Vim:

```vim
:HqStart
:HqSubmit
```

When `hq` is on `PATH`, `g:hq_bin` is unnecessary. `:HqStart` uses the `local`
profile by default; use `:HqStart <profile>` only to override it. Vim never
receives a JSONL path.

Vim-lsp exposes completion through Vim's built-in omnifunc. `Ctrl-X Ctrl-O` is
that built-in operation, not an hq-vim mapping. This package defines no key
mapping and does not claim an automatic-popup completion UX.

## Manual Smoke

After `hq` has already been built or placed:

```sh
go run ./cmd/hq-vim-smoke -hq-bin /path/to/hq -vim-lsp /path/to/vim-lsp
```

Headless smoke:

```sh
go run ./cmd/hq-vim-smoke -headless -hq-bin /path/to/hq -vim-lsp /path/to/vim-lsp
```

## Tests

```sh
go test ./...
```

The tests build a temporary external `hq` stub to verify the Vim/vim-lsp process
path. That stub is a test dependency only; it is not runtime ownership.
