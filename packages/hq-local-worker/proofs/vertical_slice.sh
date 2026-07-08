#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../../.." && pwd)"
cd "$ROOT"

rm -rf .local
mkdir -p .local

cat > .local/current-projection.json <<'JSON'
{
  "agentTaskCount": 0,
  "authority": false,
  "digest": "sha256:baseline",
  "kind": "hq.localProjection.v1",
  "latestQueueId": null,
  "modelOperationCount": 0,
  "targetRef": null
}
JSON

python3 packages/hq-local-worker/tools/render_local_preview.py \
  .local/current-projection.json \
  --out .local/preview/index.html

python3 -m http.server 8765 --directory .local/preview >/tmp/vertical.http.log 2>&1 &
server_pid=$!
trap 'kill "$server_pid" 2>/dev/null || true' EXIT

python3 - <<'PY'
import time
import urllib.request
for _ in range(50):
    try:
        urllib.request.urlopen("http://127.0.0.1:8765/index.html", timeout=1).read()
        break
    except Exception:
        time.sleep(0.1)
else:
    raise SystemExit("FAIL: localhost preview did not start")
PY

python3 - <<'PY'
from pathlib import Path
import urllib.request
Path("/tmp/vertical.before.html").write_text(
    urllib.request.urlopen("http://127.0.0.1:8765/index.html", timeout=2).read().decode("utf-8"),
    encoding="utf-8",
)
PY

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

python3 packages/hq-local-worker/tools/render_local_preview.py \
  .local/current-projection.json \
  --out .local/preview/index.html

python3 - <<'PY'
from pathlib import Path
import urllib.request
Path("/tmp/vertical.after.html").write_text(
    urllib.request.urlopen("http://127.0.0.1:8765/index.html", timeout=2).read().decode("utf-8"),
    encoding="utf-8",
)
PY

python3 packages/hq-modeling-queue/tools/validate_queue.py .local/queue.jsonl
python3 packages/hq-modeling-queue/tools/validate_queue.py .local/receipt.jsonl

test -s .local/current-target.json
test -s .local/queue.jsonl
test -s .local/receipt.jsonl
test -s .local/current-projection.json
test -s .local/preview/index.html
test -s .local/preview/current-projection.json

grep '"kind":"hq.modelCommitQueued.v1"' .local/queue.jsonl
grep '"status":"processed"' .local/receipt.jsonl
grep '"authority": false' .local/current-projection.json
grep 'data-testid="model-operation-count">model operations: <span id="modelOperationCount">1</span>' /tmp/vertical.after.html
grep 'data-authority="false"' /tmp/vertical.after.html

python3 - <<'PY'
import hashlib
import json
from pathlib import Path

projection = json.loads(Path(".local/current-projection.json").read_text(encoding="utf-8"))
receipt = json.loads(Path(".local/receipt.jsonl").read_text(encoding="utf-8").splitlines()[0])
queue = json.loads(Path(".local/queue.jsonl").read_text(encoding="utf-8").splitlines()[0])
target = json.loads(Path(".local/current-target.json").read_text(encoding="utf-8"))
before_html = Path("/tmp/vertical.before.html").read_text(encoding="utf-8")
after_html = Path("/tmp/vertical.after.html").read_text(encoding="utf-8")

def sha(text: str) -> str:
    return "sha256:" + hashlib.sha256(text.encode("utf-8")).hexdigest()

assert projection["digest"] == receipt["projectionDigest"]
assert projection["authority"] is False
assert queue["targetRef"] == {"kind": target["kind"], "id": target["id"]}
assert before_html != after_html
assert projection["digest"] in after_html
assert queue["id"] in after_html
assert target["id"] in after_html

report = {
    "status": "PASS",
    "proof": "ui-targetRef-to-vim-command-to-queue-to-worker-to-localhost-ui-to-receipt",
    "targetRef": queue["targetRef"],
    "queueId": queue["id"],
    "beforeUiDigest": sha(before_html),
    "afterUiDigest": sha(after_html),
    "uiVisibleChanged": True,
    "projectionDigest": projection["digest"],
    "receiptStatus": receipt["status"],
    "queueIsAuthority": False,
    "localProjectionAuthority": projection["authority"],
    "acceptedLedgerWritten": False,
}
Path(".local/proof-report.json").write_text(
    json.dumps(report, ensure_ascii=False, indent=2, sort_keys=True) + "\n",
    encoding="utf-8",
)
print(json.dumps(report, separators=(",", ":")))
PY
