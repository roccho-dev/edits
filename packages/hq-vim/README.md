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
- version-guarded application of hq-owned standard LSP draft edits
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
`autoComplete: true`. In Insert mode, `Ctrl-N`/`Ctrl-P` navigate the popup and
`Ctrl-Y` accepts the selected item. This package defines no completion key
mapping or manual-completion fallback.

## Submit result

`HqSubmit` remains the only durable-effect entry point. After hq reports a
successful append and supplies `hq.draftConsumption.v1`, hq-vim applies its
single standard LSP text edit only when the submitted URI/version still match
the current Vim buffer. It does not parse command syntax or calculate object
boundaries.

- unchanged accepted object: consume it from the draft;
- last object consumed: return to Vim's canonical one-line empty buffer;
- other objects present: preserve them byte-for-byte;
- newer local edit: keep it unchanged;
- missing, malformed, or locally unapplicable edit: keep the draft and show a
  warning;
- one native Vim undo: restore consumed text only; the accepted row remains.

There is no submitted marker, duplicate guard, force-submit path, confirmation,
new buffer, or editor-owned accepted state.

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

The native popup proof starts non-headless Vim with an exact external hq
executable and a temporary strict selected-world profile. Run it explicitly
with:

```sh
HQ_NATIVE_HQ_FUZZY_PROOF=1 \
HQ_BIN=/absolute/path/to/hq \
VIM_EXE=/absolute/path/to/vim \
VIM9_LSP_PATH=/absolute/path/to/yegappan-lsp \
go test -run '^TestNativeHQFuzzyAutomaticPopupDoesNotAccept$' -v
```

This proof types a non-prefix query through Vim, waits for yegappan/lsp's
automatic native popup without forcing completion, selects the hq candidate,
verifies the resulting buffer, and asserts that selection appends no accepted
row. It adds no hq popup, matcher, completion mapping, or fallback.

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
  -> accepted object consumed only after success
  -> successive objects can be submitted from the same buffer
  -> one Vim undo restores the last consumed object text only
  -> two submits have distinct accepted identities
```

The complete installed Windows proof, exact artifact placement, activation, and
deployment receipt remain owned by `roccho-dev/envs#5`. Native popup detail,
multi-line completion acceptance, accepted-history recall, and the complete
cross-platform Unicode/CRLF presentation matrix remain closure gates of
`roccho-dev/edits#70`.
