#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../../.." && pwd)"
cd "$ROOT"

rm -rf .local
mkdir -p .local

python3 packages/hq-modeling-queue/tools/current_target.py \
  write .local/current-target.json \
  --from-file packages/hq-modeling-queue/examples/current-target.sample.json

python3 packages/hq-modeling-queue/tools/command_to_queue.py \
  packages/hq-modeling-queue/examples/command-request.model-add-edge.no-target.json \
  --target-file .local/current-target.json \
  > /tmp/vertical.queue.row.json

python3 packages/hq-modeling-queue/tools/queue_io.py \
  append .local/queue.jsonl \
  --from-file /tmp/vertical.queue.row.json

python3 packages/hq-local-worker/tools/local_worker.py \
  process \
  --queue .local/queue.jsonl \
  --receipt .local/receipt.jsonl \
  --state .local/shadow-model.json \
  --projection .local/current-projection.json

python3 packages/hq-modeling-queue/tools/validate_queue.py .local/queue.jsonl
python3 packages/hq-modeling-queue/tools/validate_queue.py .local/receipt.jsonl

test -s .local/current-target.json
test -s .local/queue.jsonl
test -s .local/receipt.jsonl
test -s .local/current-projection.json

grep '"kind":"hq.modelCommitQueued.v1"' .local/queue.jsonl
grep '"status":"processed"' .local/receipt.jsonl
grep '"authority": false' .local/current-projection.json

python3 - <<'PY'
import json
from pathlib import Path
projection = json.loads(Path('.local/current-projection.json').read_text())
receipt = json.loads(Path('.local/receipt.jsonl').read_text().splitlines()[0])
assert projection['digest'] == receipt['projectionDigest']
print(json.dumps({
  'status': 'PASS',
  'target': json.loads(Path('.local/current-target.json').read_text())['id'],
  'projectionDigest': projection['digest'],
  'receiptStatus': receipt['status'],
  'authority': projection['authority'],
}, separators=(',', ':')))
PY
