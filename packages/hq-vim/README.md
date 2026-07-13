# hq Vim

Minimal edits-owned Vim extension for the official external `hq` runtime.

```text
Vim
  -> pinned yegappan/lsp
    -> exact absolute hq binary
      -> lsp --profile <name>
```

## Boundary

This package owns only:

- `plugin/hq.vim`
- `autoload/hq.vim`
- fail-closed client dependency checks
- real Vim 9/yegappan-lsp conformance tests

The `hq` repository builds, tests, and publishes the official `hq` artifact.
The `envs` repository selects and places the exact artifact and generates the
profile. Edits does not build, publish, place, supervise, or execute workers and
has no dependency on an ops artifact or receipt.

Profile resolution, JSONL paths, compiler acceptance, queue persistence,
provider execution, worker lifecycle, and `result.v1` remain outside edits.

## Exact binding

`g:hq_bin` is mandatory and must be an executable absolute path. The extension
does not search `PATH`, shell profiles, user or machine environment paths, or an
unqualified executable name.

The minimal Vim init is:

```vim
set runtimepath^=C:/exact/path/to/yegappan-lsp
set runtimepath^=C:/exact/path/to/edits/packages/hq-vim
runtime plugin/lsp.vim
runtime plugin/hq.vim
let g:hq_bin='C:/exact/verified/path/to/hq.exe'
let g:hq_profile='local'
```

Then:

```vim
:HqStart
:HqSubmit
```

Vim receives the profile name only. It does not receive JSONL, provider,
worker, registry, or environment layout paths.

Yegappan/lsp owns completion presentation and is configured with
`autoComplete: true`. This package defines no completion key mapping.

## Manual smoke

After the official `hq` artifact and yegappan/lsp have already been placed:

```sh
go run ./cmd/hq-vim-smoke -hq-bin /absolute/path/to/hq -vim9-lsp /absolute/path/to/yegappan-lsp
```

Headless submit smoke:

```sh
go run ./cmd/hq-vim-smoke -headless -hq-bin /absolute/path/to/hq -vim9-lsp /absolute/path/to/yegappan-lsp
```

## Tests

```sh
go test ./...
```

The native popup proof must run under a real terminal; a redirected or
headless Vim cannot make `pumvisible()` observable. Run it explicitly with:

```sh
HQ_NATIVE_POPUP_PROOF=1 \
VIM_EXE=/absolute/path/to/vim \
VIM9_LSP_PATH=/absolute/path/to/yegappan-lsp \
go test -run '^TestNativePopupSelectionDoesNotQueue$' -v
```

The proof types through Vim, observes yegappan/lsp's native popup, selects the
expected candidate, verifies the resulting buffer, and asserts that selection
appends no queue row. It adds no hq popup or completion mapping.

Local tests use a temporary external stub only for fail-closed and process
boundary checks. CI additionally checks out the accepted `roccho-dev/hq`
`proposals` branch, builds its official binary, and proves on Windows and Linux:

```text
real Vim
  -> pinned real yegappan/lsp
  -> explicit absolute canonical hq binary
  -> expected completion candidate
  -> zero completion writes
  -> :HqSubmit
  -> exactly one accepted.instruction per explicit submit
  -> two submits have distinct accepted identities
```

The complete installed Windows proof, exact artifact placement, activation, and
deployment receipt remain owned by `roccho-dev/envs#5`.
