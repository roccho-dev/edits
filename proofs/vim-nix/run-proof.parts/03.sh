jq -e '[.[] | select(.version == "result.v1" and .kind == "stdout") | (.message | gsub("[\\r\\n]+$";""))] == ["hq-vim-e2e-ok"]' \
  "$OUT/result-events.json" >/dev/null || fail "stdout token mismatch"
jq -e '[.[] | select(.version == "result.v1" and .kind == "completed") | .final.text] == ["hq-vim-e2e-ok"]' \
  "$OUT/result-events.json" >/dev/null || fail "completed final text mismatch"
jq -e --arg digest "sha256:$proof_sha" '[.[] | select(.version == "result.v1" and .kind == "started") | .provider] | length == 1 and .[0].capability_id == "local-tool:proof-sh@1/echo" and .[0].provider_id == "local-tool.proof-sh" and .[0].contract_version == "1" and .[0].deployment_id == ("proof-sh@1:" + $digest) and .[0].integrity_digest == $digest' \
  "$OUT/result-events.json" >/dev/null || fail "started provider identity missing or mismatched"

"$HQ_WORKER" health --profile local --profile-root "$PROFILE_ROOT" > "$OUT/worker-health-after.json"
jq -e '.ready == true and .state == "configured_ready"' "$OUT/worker-health-after.json" >/dev/null \
  || fail "worker is not ready after completed run"

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

run_id="$(jq -r '[.[] | select(.version == "result.v1") | .run_id] | unique | .[0]' "$OUT/result-events.json")"
instruction_id="$(jq -r '[.[] | select(.version == "result.v1") | .instruction_id] | unique | .[0]' "$OUT/result-events.json")"
accepted_instruction_id="$(jq -r 'select(.kind == "accepted.instruction") | .instruction.id' "$ACCEPTED")"
test "$accepted_instruction_id" = "$instruction_id" || fail "accepted/result instruction identity mismatch"
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
  --arg instruction "$instruction_id" '{
    schema:"edits.vim-nix-herdr-oci-runtime-proof/1",
    status:"PASS",
    source:{
      handoffSha256:"6a88215c073a43b82f6e584466b07f6c8265e7d4b48ff5e92acbd14626248d38",
      editsCommit:"d83bf4c4860e02f37d6b41cc54fe8c881af4c779",
      hqCommit:"3118886f34ac5615e8a7732a6297bd41900e21e1",
      yegappanLspCommit:"989016ae2ae4cbf304a9ca29478f47fec794493f"
    },
    runtime:{proofStorePath:$proof,herdrVersion:$herdr,vimVersion:$vim,hqSha256:$hqSha,workerSha256:$workerSha,proofProviderSha256:$proofSha},
    gates:{
      canonicalConformance:"PASS",
      nativePopupJourneys:3,
      nativePopup:"PASS",
      exactHqLspProcess:"PASS",
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
    limitations:{
      hostOuterLayer:"OCI/Linux amd64; WSLC host integration remains user readback",
      productionPromotion:false,
      providerSideLogRequired:false
    }
  }' > "$OUT/receipt.json"

(
  cd "$OUT"
  find . -type f ! -name SHA256SUMS -print0 | sort -z | xargs -0 sha256sum > SHA256SUMS
  sha256sum --check SHA256SUMS
)

trap - EXIT INT TERM
printf 'VIM_NIX_HERDR_OCI_RUNTIME_PROOF_PASS\n'
