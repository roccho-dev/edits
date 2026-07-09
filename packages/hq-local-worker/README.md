# hq-local-worker

Legacy/proof-only local vertical-slice evidence for edits modeling queues.

This package reads `.local/queue.jsonl`, writes `.local/receipt.jsonl`, and materializes local shadow projection output for localhost preview only to preserve historical local/dev evidence.

It is not the canonical worker runtime. It is not the admission layer. It does not admit rows into an accepted ledger. Ops owns canonical worker, receipt, and projection responsibilities.

## Boundary

| input | local proof output |
|---|---|
| `hq.modelCommitQueued.v1` | shadow model operation + processed evidence receipt |
| `hq.agentTaskQueued.v1` | pending agent task evidence + pending receipt |
| invalid row | failed evidence receipt |

## Non-authority rule

The worker output is local evidence only:

- local receipt is not accepted authority
- local projection is not accepted authority
- local preview is not accepted authority
- accepted ledger append is a separate ops-owned admission gate

## Allowed reason to remain in edits

This package may remain only because it is explicitly marked as legacy/proof-only evidence for the original editor-to-queue-to-preview proof. It must not be described as the canonical runtime owner.

## Replacement boundary

Canonical responsibilities now point outward:

| responsibility | canonical owner |
|---|---|
| queue validation | ops |
| worker runtime | ops |
| receipt writing | ops |
| projection building | ops |
| UI rendering | ui |

## Example

```text
python3 packages/hq-local-worker/tools/local_worker.py process \
  --queue .local/queue.jsonl \
  --receipt .local/receipt.jsonl \
  --state .local/shadow-model.json \
  --projection .local/current-projection.json
```
