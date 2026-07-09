# hq-modeling-queue

Queue record contract for local Vim/hq modeling operations.

This package defines the local editor queue vocabulary. It does not admit records into an accepted ledger, it does not run agents, and it does not own worker runtime.

## Record kinds

| kind | meaning |
|---|---|
| `hq.modelCommitQueued.v1` | human confirmed a model-change intent |
| `hq.agentTaskQueued.v1` | human confirmed an agent task request before model commit |
| `hq.receipt.v1` | local processing result for a queue row |

## Boundary

Queue rows are intent records. They are not accepted model authority.

```text
editor command
  -> queue intent row
  -> ops-owned validation/runtime/admission path
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

## Command vocabulary

Confirmed Vim/hq commands are editor-surface names that convert into queue intent rows.

| command prefix | output kind | ownership meaning |
|---|---|---|
| `model.*` | `hq.modelCommitQueued.v1` | human-confirmed model intent only |
| `agent.*` | `hq.agentTaskQueued.v1` | human-confirmed agent-task request only |

The vocabulary lives in `commands/modeling.commands.jsonl`. Convert examples with:

```text
python3 packages/hq-modeling-queue/tools/command_to_queue.py packages/hq-modeling-queue/examples/command-request.model-add-edge.json
python3 packages/hq-modeling-queue/tools/command_to_queue.py packages/hq-modeling-queue/examples/command-request.agent-propose-model.json
```

Command conversion is pure command-to-row construction until an adapter appends the row. It never owns admission, accepted ledger, worker runtime, or UI rendering.
