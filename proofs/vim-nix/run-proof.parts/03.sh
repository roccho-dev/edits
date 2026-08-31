jq -e '[.[] | select(.version == "result.v1" and .kind == "stdout") | (.message | gsub("[\\r\\n]+$";""))] == ["hq-vim-e2e-ok"]' \
  "$OUT/result-events.json" >/dev/null || fail "stdout token mismatch"
jq -e '[.[] | select(.version == "result.v1" and .kind == "completed") | .final.text] == ["hq-vim-e2e-ok"]' \
  "$OUT/result-events.json" >/dev/null || fail "completed final text mismatch"
jq -e --arg digest "sha256:$proof_sha" --arg configuration "$configuration_digest" '[.[] | select(.version == "result.v1" and .kind == "started") | .provider] | length == 1 and .[0].capability_id == "local-tool:proof-sh@1/echo" and .[0].provider_id == "local-tool.proof-sh" and .[0].contract_version == "2" and .[0].deployment_id == ("proof-sh@1:" + $digest) and .[0].provider_kind == "executable" and .[0].integrity_digest == $digest and .[0].configuration_digest == $configuration' \
  "$OUT/result-events.json" >/dev/null || fail "started provider identity missing or mismatched"

"$HQ_WORKER" health --profile local --profile-root "$PROFILE_ROOT" > "$OUT/worker-health-after.json"
jq -e '.ready == true and .state == "configured_ready"' "$OUT/worker-health-after.json" >/dev/null \
  || fail "worker is not ready after completed run"

run_id="$(jq -r '[.[] | select(.version == "result.v1") | .run_id] | unique | .[0]' "$OUT/result-events.json")"
instruction_id="$(jq -r '[.[] | select(.version == "result.v1") | .instruction_id] | unique | .[0]' "$OUT/result-events.json")"
accepted_instruction_id="$(jq -r 'select(.kind == "accepted.instruction") | .instruction.id' "$ACCEPTED")"
test "$accepted_instruction_id" = "$instruction_id" || fail "accepted/result instruction identity mismatch"

# Screenshot observation is optional and read-only. It starts only after all
# runtime assertions have passed, prints a finite summary into the otherwise
# idle root pane, and waits for the observer to release it.
if test -n "${PTY_CAPTURE_READY:-}"; then
  test -n "${PTY_CAPTURE_DONE:-}" || fail "PTY_CAPTURE_DONE is required with PTY_CAPTURE_READY"
  summary_script="$RUNTIME/show-runtime-e2e.sh"
  cat > "$summary_script" <<EOF_SUMMARY
#!/bin/sh
printf '\\033[2J\\033[H'
printf '%s\\n' 'HQ runtime lifecycle E2E'
printf '%s\\n' '------------------------'
printf 'accepted rows : 1\\n'
printf 'run id        : %s\\n' '$run_id'
printf 'instruction id: %s\\n' '$instruction_id'
printf '%s\\n' 'lifecycle     : accepted -> started -> stdout -> completed'
printf '%s\\n' 'stdout/final  : hq-vim-e2e-ok'
printf '%s\\n' 'worker        : configured_ready'
printf '%s\\n' 'PTY panes     : exactly 2'
printf '%s\\n' '__HQ_RUNTIME_E2E_CAPTURE_READY__'
printf '%s\\n' '{"session":"$SESSION","workspaceId":"$WORKSPACE_ID","rootPaneId":"$ROOT_PANE_ID","taskPaneId":"$TASK_PANE_ID"}' > '$PTY_CAPTURE_READY'
while test ! -e '$PTY_CAPTURE_DONE'; do
  sleep 0.05
done
printf '%s\\n' '__HQ_RUNTIME_E2E_CAPTURE_DONE__'
exit 0
EOF_SUMMARY
  chmod 700 "$summary_script"
  "$HERDR" --session "$SESSION" pane run "$ROOT_PANE_ID" "$summary_script" \
    > "$OUT/capture-summary-pane-run.json" 2> "$OUT/capture-summary-pane-run.stderr"
  wait_for_pane_marker "$ROOT_PANE_ID" '__HQ_RUNTIME_E2E_CAPTURE_READY__' "$OUT/capture-summary-pane-read.txt" 200 \
    || fail "runtime capture summary did not become visible"
  capture_done=0
  for _ in $(seq 1 400); do
    if test -e "$PTY_CAPTURE_DONE"; then
      capture_done=1
      break
    fi
    sleep 0.05
  done
  test "$capture_done" -eq 1 || fail "PTY capture observer did not release runtime"
  wait_for_pane_marker "$ROOT_PANE_ID" '__HQ_RUNTIME_E2E_CAPTURE_DONE__' "$OUT/capture-summary-pane-done.txt" 100 \
    || fail "runtime capture summary did not exit cleanly"
fi

# Typed stop, workspace/session cleanup, and residual-process check.
"$HQ_WORKER" stop --profile local --profile-root "$PROFILE_ROOT" --timeout 15s \
  > "$OUT/worker-stop.jsonl" 2> "$OUT/worker-stop.stderr"
for _ in $(seq 1 100); do
  if ! "$HQ_WORKER" health --profile local --profile-root "$PROFILE_ROOT" \
      > "$OUT/worker-health-stopped.json" 2> "$OUT/worker-health-stopped.stderr"; then
    break
  fi
  sleep 0.1
done

"$HERDR" --session "$SESSION" workspace close "$WORKSPACE_ID" \
  > "$OUT/workspace-close.json" 2> "$OUT/workspace-close.stderr"
WORKSPACE_ID=""
"$HERDR" --session "$SESSION" server stop \
  > "$OUT/herdr-stop.txt" 2> "$OUT/herdr-stop.stderr"
for _ in $(seq 1 100); do
  kill -0 "$HERDR_PID" 2>/dev/null || break
  sleep 0.1
done
wait "$HERDR_PID" || true
HERDR_PID=""

sleep 0.2
ps -eo pid=,ppid=,args= > "$OUT/processes-after-cleanup.txt"
if grep -F "$PROOF/bin/" "$OUT/processes-after-cleanup.txt" | grep -E '/(herdr|vim|hq|hq-worker)( |$)' >/dev/null; then
  grep -F "$PROOF/bin/" "$OUT/processes-after-cleanup.txt" >&2 || true
  fail "proof processes remain after cleanup"
fi

herdr_version="$("$HERDR" --version | tr -d '\r\n')"
vim_version="$("$VIM" --version | sed -n '1s/.*Vi IMproved \([0-9.]*\).*/\1/p')"
hq_sha="$(sha256sum "$PROOF/bin/hq" | awk '{print $1}')"
worker_sha="$(sha256sum "$PROOF/bin/hq-worker" | awk '{print $1}')"

jq -n \
  --arg proof "$PROOF" \
  --arg herdr "$herdr_version" \
  --arg vim "$vim_version" \
  --arg hqSha "sha256:$hq_sha" \
  --arg workerSha "sha256:$worker_sha" \
  --arg proofSha "sha256:$proof_sha" \
  --arg workspace "$PROVEN_WORKSPACE_ID" \
  --arg rootPane "$ROOT_PANE_ID" \
  --arg taskPane "$TASK_PANE_ID" \
  --arg run "$run_id" \
  --arg instruction "$instruction_id" \
  --slurpfile source "$SOURCE_MANIFEST" '{
    schema:"edits.vim-nix-runtime-e2e/2",
    status:"PASS",
    source:$source[0],
    input:{acceptedInstructionSource:"exact-fixture",editorSubmitIncluded:false},
    runtime:{proofStorePath:$proof,herdrVersion:$herdr,vimVersion:$vim,hqSha256:$hqSha,workerSha256:$workerSha,proofProviderSha256:$proofSha},
    gates:{
      paneCount:2,
      paneTopology:"PASS",
      workerReady:"PASS",
      acceptedInstructionCount:1,
      resultKinds:["accepted","started","stdout","completed"],
      stdout:"hq-vim-e2e-ok",
      completedFinalText:"hq-vim-e2e-ok",
      typedWorkerStop:"PASS",
      workspaceClose:"PASS",
      herdrStop:"PASS",
      residualProcessCount:0
    },
    topology:{workspaceId:$workspace,rootPaneId:$rootPane,taskPaneId:$taskPane},
    execution:{runId:$run,instructionId:$instruction},
    capture:{supported:true,addsProductBehavior:false},
    limitations:{
      hostOuterLayer:"OCI/Linux amd64; WSLC host integration remains user readback",
      productionPromotion:false,
      providerSideLogRequired:false
    }
  }' > "$OUT/receipt.json"

manifest_tmp="$RUNTIME/runtime-SHA256SUMS.tmp"
(
  cd "$OUT"
  find . -type f ! -name SHA256SUMS -print0 | sort -z | xargs -0 sha256sum > "$manifest_tmp"
  mv "$manifest_tmp" SHA256SUMS
  sha256sum --check SHA256SUMS
)

trap - EXIT INT TERM
printf 'VIM_NIX_RUNTIME_E2E_PASS\n'
if test "$RUN_EDITOR" -eq 1; then
  jq -e '.status == "PASS" and .gates.testCount == 8' "$OUT/editor-receipt.json" >/dev/null
  printf 'VIM_NIX_EDITOR_E2E_PASS\n'
  printf 'VIM_NIX_FULL_E2E_PASS\n'
fi
