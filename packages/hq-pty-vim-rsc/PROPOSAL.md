# hq PTY/Vim RSC proposal

## Placement

Target package path: `packages/hq-pty-vim-rsc`.

This proposal records the `hq-pty-vim-rsc-validated-proof.260708-094249.zip`
artifact as evidence for a Vim-first command/completion direction.

The active scope is now only:

```text
Windows Terminal / Herdr
  -> direct Vim process
    -> hq completion candidates
    -> explicit accept boundary
    -> RSC / JSONL proof artifacts
```

## Retired direct Explorer side

The earlier Explorer launcher side is retired.

Vim must not directly expose `HqExplorerOpen`, call an Explorer-specific helper,
or execute `explorer.exe` through this package. If opening a host path becomes a
product feature, it must first be represented as hq-owned meaning, for example a
typed target or local command intent, and only then handled by an explicit
confirmation and ops/runtime boundary.

Allowed future shape:

```text
Vim client
  -> hq semantic candidate / target
  -> human confirm
  -> typed hq queue intent
  -> ops/runtime validation
  -> host action receipt
```

Forbidden shape:

```text
Vim command
  -> explorer.exe open/select
```

## Source artifact

Source archive:

```text
C:\Users\resta\Downloads\hq-pty-vim-rsc-validated-proof.260708-094249.zip
```

Archive sha256:

```text
e8a3f8e1b4175c08a7307c9b909cce488da241dde731abbea91bc84b776b0d52
```

The archive includes a Go `hq` command, Vim plugin/autoload files, RSC proof
scripts, JSONL examples, proof cache artifacts, and a nested `.git` directory.
The imported repo state intentionally does not treat every archive path as an
active product surface.

## What the artifact proves

The artifact report claims:

- `go test ./...` passed in the proof environment.
- `scripts/proof_loose_draft_validation.sh` reached
  `LOOSE_DRAFT_VALIDATION_PROOF_OK`.
- `scripts/proof_rsc_pty_vim.sh` reached `RSC_PTY_VIM_PROOF_OK`.
- `scripts/proof_visual_projection.sh` reached
  `VIM_VISUAL_PROJECTION_PROOF_OK`.

The useful direction is: text typed in Vim becomes an RSC draft, soft validation
and completion candidates are shown first, and only an explicit accept appends an
instruction JSONL row.

## Windows host finding

The proof is not a drop-in Windows product executable by `go build ./cmd/hq`.
Windows ConPTY/Vim proof remains separate from any host side-effect launcher.

## Acceptance gates

- RSC proof scripts stay reproducible.
- Vim adapter code remains completion/accept focused.
- No direct Explorer command is exposed from Vim.
- No `explorer.exe` launcher is shipped from this package.
- Host path opening requires a future hq semantic queue/receipt boundary.

## Non-goals

- Do not import the nested `.git` directory from the archive.
- Do not claim the Unix PTY visual proof is a Windows ConPTY proof.
- Do not make remote SSH panes directly responsible for Windows Explorer.
- Do not browse repos from Vim as a primary workflow.
