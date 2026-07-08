# Local modeling control plane

`edits` is the local/dev control plane for modeling operations.

It exists to connect a developer-facing editor surface to local projections and receipts without turning local files, UI state, or generated artifacts into authority.

## Core loop

```text
localhost UI targetRef
  -> Vim/hq completion
  -> human confirm
  -> queue append
  -> local worker
  -> projection update
  -> localhost UI refresh
  -> receipt append
```

## Runtime files

These files are local runtime state and are not committed:

| path | meaning |
|---|---|
| `.local/queue.jsonl` | append-only local intent queue |
| `.local/receipt.jsonl` | local processing receipts |
| `.local/current-target.json` | current UI `targetRef` for completion context |
| `.local/current-projection.json` | current local projection for preview |

## Committed files

These files are committed:

| path | meaning |
|---|---|
| `examples/*.jsonl` | sample queues, receipts, and projections |
| `docs/**` | operation contracts and boundaries |
| `packages/**` | implementation packages |
| `adapters/**` | integration recipes |

## Authority boundary

`edits` can record intent and receipts. It cannot make local intent authoritative.

| event | meaning |
|---|---|
| queue append | a confirmed local intent was recorded |
| worker receipt | the local worker processed or rejected intent |
| admission receipt | a gate promoted a valid model change |
| accepted ledger append | the model authority changed |

## Dependency rule

`edits` may call downstream repositories through adapters. Downstream repositories must not depend on `edits`.

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

## First implementation lanes

| issue | lane |
|---|---|
| #8 | repo boundary and local control plane |
| #9 | Vim/RSC completion base |
| #10 | modeling queue record contract |
| #11 | single JSONL queue append/readback |
| #12 | Vim command vocabulary |
| #13 | UI targetRef bridge |
| #14 | local worker and receipt writer |
| #20 | vertical local proof |
