# hq-admission-gate

Minimal local admission gate for model commit queue rows.

This package is a bridge between local queue intent and an accepted-ledger-shaped output. It is not a replacement for the future contracts repository or cue admission.

## Boundary

| input | output |
|---|---|
| `hq.modelCommitQueued.v1` | `accepted.modelCommit.v1` + `admission.receipt.v1` |
| invalid queue row | failed `admission.receipt.v1` |
| `hq.agentTaskQueued.v1` | not admitted |

## Rule

Queue append is not acceptance. Only the admission gate writes accepted-ledger-shaped rows.

## Example

```text
python3 packages/hq-admission-gate/tools/admit_model_commit.py \
  --queue .local/queue.jsonl \
  --ledger .local/accepted-ledger.jsonl \
  --receipt .local/admission-receipt.jsonl
```
