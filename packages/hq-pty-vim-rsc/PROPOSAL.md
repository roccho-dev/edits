# hq PTY/Vim RSC explorer launcher proposal

## Placement

Target package path: `packages/hq-pty-vim-rsc`.

This proposal records the `hq-pty-vim-rsc-validated-proof.260708-094249.zip`
artifact as evidence for a Vim-first command/completion direction. The immediate
Windows target is narrower than the artifact's Unix PTY proof:

```text
Windows Terminal
  -> Herdr
    -> direct Vim process
      -> hq completion candidates
      -> explicit accept boundary
      -> explorer.exe open/select command
```

## User intent

The working shell should not be the primary interface. The user should be able
to start in Herdr's default Vim pane, complete a known target, and open the
corresponding Windows Explorer location immediately.

Examples of intended accepted actions:

```text
open home           -> explorer.exe %USERPROFILE%
open codex          -> explorer.exe C:\Users\resta\Codex
open repos          -> explorer.exe C:\Users\resta\Codex\repos
open edits          -> explorer.exe C:\Users\resta\Codex\repos\edits
select current-file -> explorer.exe /select,<current-file>
```

For future `kite` / SSOT SSH sessions, remote panes must not be assumed to be
able to start `explorer.exe` directly. The host-side Vim/Herdr layer should own
the Windows Explorer action, using explicit local path mappings or allowlisted
targets.

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
The intended repo import should not blindly explode the archive. At minimum,
drop `.git`, generated binaries, and any cache artifact that is not meant to be
reviewed as proof evidence.

## What the artifact proves

The artifact report claims:

- `go test ./...` passed in the proof environment.
- `scripts/proof_loose_draft_validation.sh` reached
  `LOOSE_DRAFT_VALIDATION_PROOF_OK`.
- `scripts/proof_rsc_pty_vim.sh` reached `RSC_PTY_VIM_PROOF_OK`.
- `scripts/proof_visual_projection.sh` reached
  `VIM_VISUAL_PROJECTION_PROOF_OK`.

The proof direction is useful: text typed in Vim becomes an RSC draft, soft
validation and completion candidates are shown first, and only an explicit
accept appends an instruction JSONL row.

## Windows host finding

This archive is not immediately usable on the current Windows host by simply
running `go build ./cmd/hq`.

Observed on Windows:

```text
mise x go@1.23.2 -- go version
  go version go1.23.2 windows/amd64

mise x go@1.23.2 -- go test ./...
  hq/internal/core      ok
  hq/internal/jsonrpc   ok
  hq/internal/pty       ok
  hq/internal/lsp       ok
  hq/internal/rsc       ok
  hq/cmd/hq             build failed
  hq/internal/dispatcher failed Windows shell expectations

mise x go@1.23.2 -- go build -o .\bin\hq.exe .\cmd\hq
  build failed
```

Blocking errors:

```text
cmd\hq\rsc_cmd.go: sess.Master undefined
```

The Unix PTY implementation exposes `Session.Master`; the non-Unix stub does
not. The dispatcher tests also assume a Unix `printf` command. So the core RSC
logic is promising, but the Windows executable boundary needs a small porting
step before this can be used from Herdr/Vim.

## Proposed implementation boundary

Keep three layers separate:

```text
RSC completion core:
  Pure Go, cross-platform.

Vim adapter:
  Completion UI and explicit accept commands.

Windows launcher adapter:
  explorer.exe open/select actions, allowlisted and side-effect-free until
  explicit accept.
```

Do not make the Windows host depend on Unix PTY proof code for simple
Explorer-launch completion. The direct Herdr/Vim start remains shell-free; only
the accepted launcher command starts `explorer.exe`.

## Acceptance gates

- `go build ./cmd/hq` succeeds on Windows, or Windows-only build tags exclude
  PTY proof commands from the host launcher binary.
- `go test ./...` succeeds on Windows, or Unix-only tests are correctly tagged.
- Vim command completion can suggest at least `home`, `codex`, `repos`, and
  `edits`.
- Accepting a directory candidate opens Explorer for that directory.
- Accepting a file candidate uses `explorer.exe /select,<file>`.
- Candidate preview has no side effects.
- Remote SSOT/kite targets require explicit local mapping before Explorer is
  invoked.

## Non-goals

- Do not import the nested `.git` directory from the archive.
- Do not claim the Unix PTY visual proof is a Windows ConPTY proof.
- Do not make remote SSH panes directly responsible for Windows Explorer.
- Do not browse repos from Vim as a primary workflow; the first workflow is
  fast open/select of known paths.
