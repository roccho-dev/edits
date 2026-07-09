# edits

Editor surface and queue-writer boundary for local modeling workflows.

This repository owns the human operation surface for:

- Vim/hq command vocabulary and completion
- explicit human confirmation
- targetRef interpretation from UI metadata
- append-only local queue row writing

It does not own:

- worker runtime
- admission gates
- accepted ledger state
- projection authority
- UI rendering
- source extraction runtime
- contract authority

## Boundary declaration

```text
edits = editor surface
      + pure command/targetRef interpretation
      + queue writer adapter
      - worker
      - admission
      - accepted ledger
      - projection authority
      - UI renderer
```

## Authority boundary

`edits` may write local queue intent. It must not treat local files as accepted model authority.

| path | role | commit |
|---|---|---:|
| `.local/queue.jsonl` | local intent queue | no |
| `.local/current-target.json` | current UI targetRef cache | no |
| `examples/*.jsonl` | sample queue/receipt data | yes |
| `docs/**` | editor/queue-writer boundary docs | yes |
| `packages/hq-modeling-queue/` | command vocabulary and queue-row construction | yes |
| `packages/hq-local-worker/` | legacy/proof-only local vertical-slice evidence until ops owns runtime proof | yes |
| `adapters/ui/` | targetRef handoff recipes | yes |

Queue append means intent was recorded. It does not mean the model was accepted. Accepted model authority belongs after an ops-owned admission gate.

Receipts, local projections, previews, and generated HTML are evidence only. They are not accepted model authority.

## Dependency direction

Allowed:

```text
ui targetRef metadata -> edits queue writer
edits queue rows -> ops queue runtime
ops projection artifacts -> ui projection reader
```

Forbidden:

```text
edits -> canonical worker runtime ownership
edits -> admission ownership
edits -> accepted ledger ownership
edits -> projection authority ownership
edits -> UI renderer ownership
```

## Package map

| path | role |
|---|---|
| `packages/hq-pty-vim-rsc/` | lower-level Vim/RSC completion base |
| `packages/hq-modeling-queue/` | editor command vocabulary, pure command-to-queue conversion, local queue writer tools |
| `packages/hq-local-worker/` | legacy/proof-only local vertical-slice evidence; not canonical runtime |
| `adapters/ui/` | ui targetRef handoff recipes |

## Local modeling loop

```text
localhost UI targetRef
  -> Vim/hq completion
  -> human confirm
  -> .local/queue.jsonl append
  -> ops-owned runtime/admission/projection path
  -> ui projection preview
```

The in-repo local worker proof remains only as local/dev evidence until ops-owned runtime proof replaces it. It is not the canonical runtime boundary.
