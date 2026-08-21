"$HERDR" --session "$SESSION" pane process-info --pane "$TASK_PANE_ID" > "$OUT/task-pane-process.json"

# Exact finite world, executable binding, and managed worker profile.
cat > "$WORLD" <<'EOF_WORLD'
{"kind":"hq.world.v1","world_id":"vim-nix-proof"}
{"kind":"hq.local-tool.v1","tool_id":"proof-sh","tool_version":"1","binding_ref":"local-tool.proof-sh","binding_contract_version":"1","actions":[{"action_id":"echo","argv":[{"literal":"echo"},{"literal":"hq-vim-e2e-ok"}],"stdin":{"mode":"none","max_bytes":0},"limits":{"timeout_ms":5000,"stdout_bytes":4096,"stderr_bytes":4096},"output":{"format":"text"},"lifecycle":"one-shot","risk":"low","approval":"explicit"}]}
{"kind":"hq.command.v1","command_id":"proof.echo","command_version":"1","name":"proof.echo","description":"Emit a harmless deterministic proof token","instruction":{"version":"instruction.v1","op":"run","target":"local-tool","payload":{"tool_id":"proof-sh","tool_version":"1","action_id":"echo","input":{}}}}
EOF_WORLD

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

cat > "$RUNTIME/run-submit.sh" <<EOF_SUBMIT
#!/bin/sh
set +e
HOME="$HOME" \
XDG_CONFIG_HOME="$XDG_CONFIG_HOME" \
XDG_RUNTIME_DIR="$XDG_RUNTIME_DIR" \
XDG_STATE_HOME="$XDG_STATE_HOME" \
XDG_CACHE_HOME="$XDG_CACHE_HOME" \
HQ_BUFFER_TEXT='@proof.echo' \
LANG=C.UTF-8 LC_ALL=C.UTF-8 TERM=xterm-256color \
"$PROOF/bin/hq-vim-smoke" \
  -headless \
  -hq-bin "$PROOF/bin/hq" \
  -vim "$PROOF/bin/vim" \
  -vim9-lsp "$PROOF/share/yegappan-lsp" \
  -plugin-root "$PROOF/share/hq-vim" \
  -profile local \
  -buffer "$RUNTIME/proof.hqjson" \
  > "$OUT/submit.log" 2>&1
code=\$?
cat "$OUT/submit.log"
printf '\\n__VIM_NIX_SUBMIT_EXIT_%s__\\n' "\$code"
exit 0
EOF_SUBMIT
chmod 700 "$RUNTIME/run-submit.sh"

"$HERDR" --session "$SESSION" pane run "$ROOT_PANE_ID" "$RUNTIME/run-submit.sh" \
  > "$OUT/submit-pane-run.json" 2> "$OUT/submit-pane-run.stderr"
wait_for_pane_marker "$ROOT_PANE_ID" '__VIM_NIX_SUBMIT_EXIT_0__' "$OUT/submit-pane-recent.txt" 600 \
  || fail "real Vim submit failed or timed out"

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
