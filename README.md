# edits

Local/dev control plane for editor-related modeling workflows.

This repository owns the local operation surface for:

- Vim/hq completion and explicit human confirmation
- append-only local queue rows
- local workers that update shadow projections
- adapters to ui, contracts, and source repositories

It is not:

- a source-of-truth ledger
- a UI state store
- a renderer implementation
- a source repository
- an accepted decision authority

## Authority boundary

`edits` may write local intent and local receipts. It must not treat those local files as accepted model authority.

| path | role | commit |
|---|---|---:|
| `.local/queue.jsonl` | local intent queue | no |
| `.local/receipt.jsonl` | local processing receipt | no |
| `.local/current-target.json` | current UI targetRef | no |
| `.local/current-projection.json` | local preview projection | no |
| `examples/*.jsonl` | sample queue/receipt data | yes |
| `docs/**` | operation contracts | yes |
| `packages/**` | implementation packages | yes |
| `adapters/**` | repo integration recipes | yes |

Queue append means intent was recorded. It does not mean the model was accepted. Accepted model authority belongs to a contracts ledger or temporary contracts-poc package until that ledger is split into its own repository.

## Dependency direction

Allowed:

```text
edits -> ui
edits -> contracts or contracts-poc
edits -> source repositories
```

Forbidden:

```text
ui -> edits
contracts -> edits
source repositories -> edits
```

## Package map

| path | role |
|---|---|
| `packages/hq-pty-vim-rsc/` | lower-level Vim/RSC completion base |
| `packages/hq-modeling-queue/` | modeling queue record contract and vocabulary |
| `packages/hq-local-worker/` | local queue worker and receipt writer |
| `packages/contracts-poc/` | temporary cue append-contract staging area |
| `adapters/ui/` | ui.git adapter recipes |
| `adapters/contracts/` | contracts/cue adapter recipes |
| `adapters/repos/` | source repository adapter recipes |

## Local modeling loop

```text
localhost UI targetRef
  -> Vim/hq completion
  -> human confirm
  -> .local/queue.jsonl append
  -> local worker
  -> projection update
  -> localhost UI refresh
  -> .local/receipt.jsonl append
```

This loop is for local/dev feedback. Promotion to accepted ledger is a separate admission step.
