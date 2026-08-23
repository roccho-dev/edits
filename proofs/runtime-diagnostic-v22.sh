#!/usr/bin/env bash
set -Eeuo pipefail

SOURCE=7e7f02782315c4574affe31c7c945fdfa9e99157
EXPECTED_HQ=779a298f4efcff8df60205aaf973cb224388a82b
EVIDENCE=${EVIDENCE:-/tmp/vim-nix-runtime-diagnostic-v22}

rm -rf "$EVIDENCE"
mkdir -p "$EVIDENCE"/{product,runtime}

test "$(git rev-parse HEAD)" = "$SOURCE"

python3 - "$SOURCE" <<'PY'
from pathlib import Path
import sys
commit = sys.argv[1]
flake = Path('proofs/vim-nix/flake.nix')
text = flake.read_text(encoding='utf-8')
needle = '  inputs = {\n'
insert = '  inputs = {\n    editsSource = {\n      url = "github:roccho-dev/edits/' + commit + '";\n      flake = false;\n    };\n'
if text.count(needle) != 1:
    raise SystemExit('unexpected flake inputs shape')
flake.write_text(text.replace(needle, insert, 1), encoding='utf-8')
part = Path('proofs/vim-nix/flake.parts/00.nix')
text = part.read_text(encoding='utf-8')
old_src = '      edits-src = self.outPath;'
new_src = '      edits-src = inputs.editsSource.outPath;'
old_rev = '      editsRevision = if self ? rev then self.rev else if self ? dirtyRev then self.dirtyRev else "dirty";'
new_rev = '      editsRevision = if inputs.editsSource ? rev then inputs.editsSource.rev else "unknown";'
if text.count(old_src) != 1 or text.count(old_rev) != 1:
    raise SystemExit('unexpected source identity shape')
part.write_text(text.replace(old_src, new_src, 1).replace(old_rev, new_rev, 1), encoding='utf-8')
PY

pushd proofs/vim-nix >/dev/null
nix flake lock --update-input editsSource
before=$(sha256sum flake.lock | cut -d' ' -f1)
product=$(nix build --no-link --print-out-paths .#default)
offline=$(nix build --offline --no-write-lock-file --no-link --print-out-paths .#default)
after=$(sha256sum flake.lock | cut -d' ' -f1)
popd >/dev/null

test "$product" = "$offline"
test "$before" = "$after"
test "$(jq -r '.nodes.editsSource.locked.rev' proofs/vim-nix/flake.lock)" = "$SOURCE"
test "$(jq -r '.nodes.hq.locked.rev' proofs/vim-nix/flake.lock)" = "$EXPECTED_HQ"
jq -e --arg source "$SOURCE" '.editsRevision == $source' "$product/share/proof/source.json" >/dev/null
printf '%s\n' "$product" | tee "$EVIDENCE/product/store-path.txt"
cp "$product/share/proof/source.json" "$EVIDENCE/product/source.json"

cat proofs/vim-nix/run-proof.parts/*.sh > "$RUNNER_TEMP/runtime-proof-v22.sh"
python3 - "$RUNNER_TEMP/runtime-proof-v22.sh" <<'PY'
from pathlib import Path
import sys
p = Path(sys.argv[1])
s = p.read_text(encoding='utf-8')
needle = 'test "$result_ready" -eq 1 || fail "accepted instruction/result chain did not complete"\n'
replacement = r'''if test "$result_ready" -ne 1; then
  cp "$ACCEPTED" "$OUT/accepted-after-append.jsonl" || true
  cp "$EVENTS" "$OUT/events-after-timeout.jsonl" || true
  stat "$ACCEPTED" > "$OUT/accepted-host.stat" 2>&1 || true
  sha256sum "$ACCEPTED" > "$OUT/accepted-host.sha256" 2>&1 || true
  wc -c "$ACCEPTED" > "$OUT/accepted-host.bytes" 2>&1 || true
  "$HQ_WORKER" health --profile local --profile-root "$PROFILE_ROOT" \
    > "$OUT/worker-health-after-timeout.json" 2> "$OUT/worker-health-after-timeout.stderr" || true
  pane_read "$TASK_PANE_ID" "$OUT/worker-pane-after-timeout.txt"
  "$HERDR" --session "$SESSION" pane process-info --pane "$TASK_PANE_ID" \
    > "$OUT/worker-pane-process-after-timeout.json" 2> "$OUT/worker-pane-process-after-timeout.stderr" || true
  worker_pid="$(jq -r '.result.process_info.foreground_processes[]? | select(.name == "hq-worker") | .pid' "$OUT/worker-pane-process-after-timeout.json" 2>/dev/null | head -n1)"
  printf '%s\n' "$worker_pid" > "$OUT/worker-pid.txt"
  if test -n "$worker_pid" && test -d "/proc/$worker_pid"; then
    readlink "/proc/$worker_pid/root" > "$OUT/worker-proc-root.txt" 2>&1 || true
    readlink "/proc/$worker_pid/cwd" > "$OUT/worker-proc-cwd.txt" 2>&1 || true
    readlink "/proc/$worker_pid/ns/mnt" > "$OUT/worker-mount-namespace.txt" 2>&1 || true
    readlink "/proc/$$/ns/mnt" > "$OUT/runner-mount-namespace.txt" 2>&1 || true
    cat "/proc/$worker_pid/status" > "$OUT/worker-proc-status.txt" 2>&1 || true
    cat "/proc/$worker_pid/mountinfo" > "$OUT/worker-mountinfo.txt" 2>&1 || true
    ls -l "/proc/$worker_pid/fd" > "$OUT/worker-fd.txt" 2>&1 || true
    proc_accepted="/proc/$worker_pid/root$ACCEPTED"
    printf '%s\n' "$proc_accepted" > "$OUT/worker-proc-accepted-path.txt"
    stat "$proc_accepted" > "$OUT/worker-accepted.stat" 2>&1 || true
    sha256sum "$proc_accepted" > "$OUT/worker-accepted.sha256" 2>&1 || true
    wc -c "$proc_accepted" > "$OUT/worker-accepted.bytes" 2>&1 || true
    cat "$proc_accepted" > "$OUT/worker-accepted.jsonl" 2> "$OUT/worker-accepted.stderr" || true
  fi
  fail "accepted instruction/result chain did not complete"
fi
'''
if s.count(needle) != 1:
    raise SystemExit(f'runtime timeout gate matches={s.count(needle)}')
s = s.replace(needle, replacement, 1)
p.write_text(s, encoding='utf-8')
PY
chmod 700 "$RUNNER_TEMP/runtime-proof-v22.sh"

set +e
PROOF_ROOT="$product" \
PROOF_OUTPUT_DIR="$EVIDENCE/runtime" \
PROOF_RUNTIME_DIR="$RUNNER_TEMP/runtime-v22" \
PROOF_RUN_SUFFIX=v22 \
"$RUNNER_TEMP/runtime-proof-v22.sh" > "$EVIDENCE/runtime/stdout.log" 2> "$EVIDENCE/runtime/stderr.log"
status=$?
set -e
printf '%s\n' "$status" > "$EVIDENCE/runtime/exit-status.txt"

# The diagnostic is successful only when it captured the original failure boundary.
test "$status" -ne 0
for required in accepted-after-append.jsonl worker-health-after-timeout.json worker-pane-after-timeout.txt worker-pane-process-after-timeout.json; do
  test -e "$EVIDENCE/runtime/$required"
done

jq -n \
  --arg source "$SOURCE" \
  --arg product "$product" \
  --argjson exitStatus "$status" \
  '{schema:"edits.runtime-diagnostic-v22/1",status:"CAPTURED_FAILURE",sourceCommit:$source,productStorePath:$product,runtimeExit:$exitStatus}' \
  > "$EVIDENCE/receipt.json"
(cd "$EVIDENCE" && find . -type f ! -name SHA256SUMS -print0 | sort -z | xargs -0 sha256sum > SHA256SUMS && sha256sum --check SHA256SUMS)
printf 'V22_DIAGNOSTIC_CAPTURED source=%s product=%s exit=%s\n' "$SOURCE" "$product" "$status"
