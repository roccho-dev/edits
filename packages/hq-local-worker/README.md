# hq-local-worker

Local worker for edits modeling queues.

This package reads `.local/queue.jsonl`, writes `.local/receipt.jsonl`, and materializes local shadow projection output for localhost preview.

It is local/dev only. It does not admit rows into an accepted ledger.

## Boundary

| input | local output |
|---|---|
| `hq.modelCommitQueued.v1` | shadow model operation + processed receipt |
| `hq.agentTaskQueued.v1` | pending agent task + pending receipt |
| invalid row | failed receipt |

## Non-authority rule

The worker output is local evidence only:

- local receipt is not accepted authority
- local projection is not accepted authority
- accepted ledger append is a separate admission gate

## Example

```text
python3 packages/hq-local-worker/tools/local_worker.py process \
  --queue .local/queue.jsonl \
  --receipt .local/receipt.jsonl \
  --state .local/shadow-model.json \
  --projection .local/current-projection.json
```
