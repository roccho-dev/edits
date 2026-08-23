"$HERDR" --session "$SESSION" pane process-info --pane "$TASK_PANE_ID" > "$OUT/task-pane-process.json"

# Runtime lifecycle E2E input is an exact accepted instruction fixture. Editor
# choice and submit are proved by their own focused E2Es and are not re-run here.
cp "$RUNTIME_WORLD_FIXTURE" "$WORLD"

test "$(grep -cve '^[[:space:]]*$' "$RUNTIME_ACCEPTED_FIXTURE")" -eq 1 \
  || fail "runtime accepted fixture must contain exactly one row"
jq -e '.kind == "accepted.instruction" and .instruction.version == "instruction.v1"' \
  "$RUNTIME_ACCEPTED_FIXTURE" >/dev/null || fail "runtime accepted fixture is invalid"

jq -n --arg digest "sha256:$proof_sha" --arg executable "$PROOF/bin/proof-sh" '{
  schema:"envctl.verified-executable-bindings.v1",
  entries:[{
    bindingRef:"local-tool.proof-sh",
    resourceId:"proof-sh",
    contractVersion:"1",
    executable:$executable,
    materialDigest:$digest,
    deploymentId:("proof-sh@1:" + $digest),
    declarationEventId:"vim-nix-proof.declare.proof-sh.v1",
    selectionEventId:"vim-nix-proof.select.proof-sh.v1"
  }]
}' > "$BINDINGS"

jq -n \
  --arg world "$WORLD" \
  --arg accepted "$ACCEPTED" \
  --arg workspace "$WORKSPACE_ROOT" \
  --arg events "$EVENTS" \
  --arg bindings "$BINDINGS" '{
    kind:"hq.profile.v1",
    name:"local",
    deployment_id:"vim-nix-proof-deployment-1",
    world_path:$world,
    accepted_path:$accepted,
    workspace_root:$workspace,
    events_path:$events,
    executable_bindings_path:$bindings,
    poll_interval_ms:50,
    health_timeout_ms:2000
  }' > "$PROFILE"

cat > "$RUNTIME/run-worker.sh" <<EOF_WORKER
#!/bin/sh
exec "$HQ_WORKER" serve --profile local --profile-root "$PROFILE_ROOT" --worker-id vim-nix-proof
EOF_WORKER
chmod 700 "$RUNTIME/run-worker.sh"
"$HERDR" --session "$SESSION" pane run "$TASK_PANE_ID" "$RUNTIME/run-worker.sh" \
  > "$OUT/worker-pane-run.json" 2> "$OUT/worker-pane-run.stderr"

worker_ready=0
for _ in $(seq 1 400); do
  if "$HQ_WORKER" health --profile local --profile-root "$PROFILE_ROOT" \
      > "$OUT/worker-health.json" 2> "$OUT/worker-health.stderr"; then
    if jq -e '.ready == true and .state == "configured_ready"' "$OUT/worker-health.json" >/dev/null; then
      worker_ready=1
      break
    fi
  fi
  sleep 0.1
done
test "$worker_ready" -eq 1 || fail "managed worker never became ready"
pane_read "$TASK_PANE_ID" "$OUT/worker-pane-read.txt"
"$HERDR" --session "$SESSION" pane process-info --pane "$TASK_PANE_ID" > "$OUT/worker-pane-process.json"

# Append only the exact fixture after readiness. This is the sole input effect of
# the runtime E2E; no Vim/editor E2E is nested inside it.
cat "$RUNTIME_ACCEPTED_FIXTURE" >> "$ACCEPTED"

result_ready=0
for _ in $(seq 1 400); do
  if test "$(grep -cve '^[[:space:]]*$' "$ACCEPTED" || true)" -eq 1 && test -s "$EVENTS"; then
    if jq -s -e 'map(select(.version == "result.v1" and .kind == "completed")) | length == 1' "$EVENTS" >/dev/null 2>&1; then
      result_ready=1
      break
    fi
  fi
  sleep 0.1
done
test "$result_ready" -eq 1 || fail "accepted instruction/result chain did not complete"

test "$(grep -cve '^[[:space:]]*$' "$ACCEPTED")" -eq 1 || fail "accepted instruction count is not exactly one"
jq -s '.' "$EVENTS" > "$OUT/result-events.json"
result_count="$(jq '[.[] | select(.version == "result.v1")] | length' "$OUT/result-events.json")"
test "$result_count" -eq 4 || fail "expected exactly four result events, got $result_count"
jq -e '[.[] | select(.version == "result.v1") | .kind] == ["accepted","started","stdout","completed"]' \
  "$OUT/result-events.json" >/dev/null || fail "result event sequence is not accepted→started→stdout→completed"
test "$(jq '[.[] | select(.version == "result.v1") | .run_id] | unique | length' "$OUT/result-events.json")" -eq 1 \
  || fail "result chain has multiple run IDs"
test "$(jq '[.[] | select(.version == "result.v1") | .instruction_id] | unique | length' "$OUT/result-events.json")" -eq 1 \
  || fail "result chain has multiple instruction IDs"
