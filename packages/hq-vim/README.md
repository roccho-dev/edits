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

The selected client integration requires Vim patch `9.0.1629` or newer. This is
the first yegappan/lsp patch gate used for negotiated UTF-8, UTF-16, and UTF-32
position conversion. hq-vim converts the current Vim byte location to the
client's UTF-32 input and delegates final LSP encoding to the pinned client. It
does not send raw `col()` or `strlen()` byte offsets as LSP positions.

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

Local tests use a temporary external stub only for fail-closed and process
boundary checks. CI additionally checks out the accepted `roccho-dev/hq`
`proposals` branch, builds its official binary, and proves on native Windows Vim
and Linux Vim `9.2.0478`:

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
deployment receipt remain owned by `roccho-dev/envs#5`. Native popup detail,
multi-line acceptance, one-step undo, and the complete Unicode/CRLF matrix remain
owned by `roccho-dev/edits#70`.
