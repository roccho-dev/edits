# Exact finite world, regular proof executable binding, and one managed worker.
world="$runtime/world.jsonl"
accepted="$runtime/accepted.jsonl"
events="$runtime/events/events.jsonl"
capabilities="$runtime/capabilities.json"
bindings="$runtime/executable-bindings.json"
profile="$profile_root/local.json"
: >"$accepted"
: >"$events"
printf '{}\n' >"$capabilities"
cat >"$world" <<'JSONL'
{"kind":"hq.world.v1","world_id":"vim-nix-proof"}
{"kind":"hq.local-tool.v1","tool_id":"proof-sh","tool_version":"1","binding_ref":"local-tool.proof-sh","binding_contract_version":"1","actions":[{"action_id":"echo","argv":[{"literal":"echo"},{"literal":"hq-vim-e2e-ok"}],"stdin":{"mode":"none","max_bytes":0},"limits":{"timeout_ms":5000,"stdout_bytes":4096,"stderr_bytes":4096},"output":{"format":"text"},"lifecycle":"one-shot","risk":"low","approval":"explicit"}]}
{"kind":"hq.command.v1","command_id":"proof.echo","command_version":"1","name":"proof.echo","description":"Emit a harmless deterministic proof token","instruction":{"version":"instruction.v1","op":"run","target":"local-tool","payload":{"tool_id":"proof-sh","tool_version":"1","action_id":"echo","input":{}}}}
JSONL
proof_digest="sha256:$(sha256sum "$proof_root/bin/proof-sh" | awk '{print $1}')"
deployment="proof-sh@vim-nix-proof:${proof_digest}"
jq -n --arg exe "$proof_root/bin/proof-sh" --arg digest "$proof_digest" --arg deployment "$deployment" \
  '{schema:"envctl.verified-executable-bindings.v1",entries:[{bindingRef:"local-tool.proof-sh",resourceId:"proof-sh",contractVersion:"1",executable:$exe,materialDigest:$digest,deploymentId:$deployment,declarationEventId:"vim-nix-proof:proof-sh:declared",selectionEventId:"vim-nix-proof:proof-sh:selected"}]}' \
  >"$bindings"
jq -n --arg world "$world" --arg accepted "$accepted" --arg workspace "$workspace" \
  --arg events "$events" --arg capabilities "$capabilities" --arg bindings "$bindings" \
  '{kind:"hq.profile.v1",name:"local",deployment_id:"vim-nix-proof-runtime",world_path:$world,accepted_path:$accepted,workspace_root:$workspace,events_path:$events,capabilities_path:$capabilities,executable_bindings_path:$bindings,poll_interval_ms:50,health_timeout_ms:3000}' \
  >"$profile"

worker_cmd="'$proof_root/bin/hq-worker' serve --profile local --profile-root '$profile_root' --worker-id vim-nix-proof; s=\$?; printf '\n__WORKER_EXIT__=%s\n' \"\$s\""
h pane run "$task_pane" "$worker_cmd" >"$output/herdr-worker-run.json"
worker_started=1
worker_ready=0
for _ in $(seq 1 300); do
  if "$proof_root/bin/hq-worker" health --profile local --profile-root "$profile_root" \
      >"$output/worker-health.ready.json" 2>"$output/worker-health.ready.stderr"; then
    worker_ready=1
    break
  fi
  sleep 0.1
done
((worker_ready == 1)) || { echo 'managed worker did not become ready' >&2; exit 1; }
[[ "$(count_exact_worker)" == 1 ]] || { echo 'expected exactly one managed hq-worker' >&2; exit 1; }
h pane process-info --pane "$task_pane" >"$output/process-info.worker.json"
h pane read "$task_pane" --source recent-unwrapped --lines 100 >"$output/herdr-worker-pane.before-submit.txt"

# Real Vim -> yegappan/lsp -> exact HQ explicit submit from the Herdr root pane.
submit_cmd="cd '$proof_root/share/hq-vim' && HQ_BUFFER_TEXT='@proof.echo' '$proof_root/bin/hq-vim-smoke' -headless -hq-bin '$proof_root/bin/hq' -vim '$proof_root/bin/vim' -vim9-lsp '$proof_root/share/yegappan-lsp' -plugin-root '$proof_root/share/hq-vim' -profile local -buffer '$runtime/proof.hqjson'; s=\$?; printf '\n__SUBMIT_EXIT__=%s\n' \"\$s\""
h pane run "$root_pane" "$submit_cmd" >"$output/herdr-submit-run.json"
h pane wait-output "$root_pane" --regex '(?m)^__SUBMIT_EXIT__=0\r?$' --source recent-unwrapped --lines 300 --timeout 120000 \
  >"$output/herdr-submit-wait.json"
h pane read "$root_pane" --source recent-unwrapped --lines 300 >"$output/herdr-submit-pane.txt"

chain_ready=0
for _ in $(seq 1 300); do
  if jq -e -n --slurpfile accepted "$accepted" --slurpfile events "$events" \
      --arg digest "$proof_digest" --arg deployment "$deployment" '
        ($accepted|length)==1 and
        ($accepted[0].kind=="accepted.instruction") and
        ($accepted[0].queue=="instruction.jsonl") and
        ([ $events[] | select(.version=="result.v1") | .kind ] == ["accepted","started","stdout","completed"]) and
        (([ $events[] | select(.version=="result.v1") | .run_id ] | unique | length)==1) and
        (([ $events[] | select(.version=="result.v1") | .instruction_id ] | unique)==[$accepted[0].instruction.id]) and
        (([ $events[] | select(.version=="result.v1" and .kind=="stdout") | .message ][0] | gsub("[\\r\\n]+$";""))=="hq-vim-e2e-ok") and
        (([ $events[] | select(.version=="result.v1" and .kind=="completed") | .final.text ][0] | gsub("[\\r\\n]+$";""))=="hq-vim-e2e-ok") and
        ([ $events[] | select(.version=="result.v1" and .kind=="started") | .provider ][0].provider_id=="local-tool.proof-sh") and
        ([ $events[] | select(.version=="result.v1" and .kind=="started") | .provider ][0].contract_version=="1") and
        ([ $events[] | select(.version=="result.v1" and .kind=="started") | .provider ][0].deployment_id==$deployment) and
        ([ $events[] | select(.version=="result.v1" and .kind=="started") | .provider ][0].provider_kind=="executable") and
        ([ $events[] | select(.version=="result.v1" and .kind=="started") | .provider ][0].integrity_digest==$digest)
      ' >/dev/null 2>&1; then
    chain_ready=1
    break
  fi
  sleep 0.1
done
((chain_ready == 1)) || { echo 'worker result chain did not reach exact completed state' >&2; exit 1; }

jq -n --slurpfile accepted "$accepted" --slurpfile events "$events" '
  ([ $events[] | select(.version=="result.v1") ]) as $result |
  ($result | map(select(.kind=="started"))[0].provider) as $provider |
  {schema:"edits.vimNixProof.workerChain/1",status:"PASS",acceptedRows:($accepted|length),instructionId:$accepted[0].instruction.id,runId:$result[0].run_id,resultKinds:($result|map(.kind)),stdout:"hq-vim-e2e-ok",finalText:"hq-vim-e2e-ok",provider:$provider}
' >"$output/worker-chain.json"
"$proof_root/bin/hq-worker" health --profile local --profile-root "$profile_root" \
  >"$output/worker-health.after.json" 2>"$output/worker-health.after.stderr"
cp "$accepted" "$output/accepted.jsonl"
cp "$events" "$output/events.jsonl"
cp "$world" "$output/world.jsonl"
cp "$bindings" "$output/executable-bindings.json"
cp "$profile" "$output/profile.json"
h pane read "$task_pane" --source recent-unwrapped --lines 200 >"$output/herdr-worker-pane.after-submit.txt"
h api snapshot >"$output/herdr-api-snapshot.final.json"
