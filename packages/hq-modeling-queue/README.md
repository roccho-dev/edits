# hq-modeling-queue

Queue record contract for local Vim/hq modeling operations.

This package defines the local queue vocabulary. It does not admit records into an accepted ledger and it does not run agents.

## Record kinds

| kind | meaning |
|---|---|
| `hq.modelCommitQueued.v1` | human confirmed a model-change intent |
| `hq.agentTaskQueued.v1` | human confirmed an agent task request before model commit |
| `hq.receipt.v1` | local processing result for a queue row |

## Boundary

Queue rows are intent records. They are not accepted model authority.

```text
queue append
  -> local worker
  -> receipt
  -> optional admission gate
  -> accepted ledger
```

## Required shared fields

| field | meaning |
|---|---|
| `id` | queue or receipt id |
| `kind` | record kind |
| `createdAt` | RFC3339 timestamp |
| `status` | local status |
| `sourceDigest` | digest of source context when known |
| `idempotencyKey` | duplicate-processing guard |

## Forbidden authority fields

Local queue rows must not contain these fields:

```text
authority
accepted
approved
approval
merge
merged
fire
dispatch
```

Those concepts belong to admission, accepted ledger, or later explicit dispatch layers.

## Validation

Use the standard-library validator:

```text
python3 packages/hq-modeling-queue/tools/validate_queue.py packages/hq-modeling-queue/examples/queue.sample.jsonl
python3 packages/hq-modeling-queue/tools/validate_queue.py packages/hq-modeling-queue/examples/receipt.sample.jsonl
```

## Local queue IO

Use the standard-library queue tool for local/dev append, readback, tail, and full-file validation:

```text
python3 packages/hq-modeling-queue/tools/queue_io.py append .local/queue.jsonl --from-file packages/hq-modeling-queue/examples/model-commit.input.json
python3 packages/hq-modeling-queue/tools/queue_io.py read .local/queue.jsonl
python3 packages/hq-modeling-queue/tools/queue_io.py tail .local/queue.jsonl -n 1
python3 packages/hq-modeling-queue/tools/queue_io.py validate .local/queue.jsonl
```

`.local/queue.jsonl` and `.local/receipt.jsonl` remain local runtime files and must not be committed.
