# Typed cleanup, followed by process disappearance proof.
"$proof_root/bin/hq-worker" stop --profile local --profile-root "$profile_root" --timeout 20s \
  >"$output/cleanup-worker-stop.jsonl" 2>"$output/cleanup-worker-stop.stderr"
worker_started=0
h pane wait-output "$task_pane" --regex '(?m)^__WORKER_EXIT__=0\r?$' --source recent-unwrapped --lines 200 --timeout 30000 \
  >"$output/cleanup-worker-wait.json" || true
h workspace close "$workspace_id" >"$output/cleanup-workspace-close.json"
workspace_id=""
"$proof_root/bin/herdr" session stop "$session" --json >"$output/cleanup-session-stop.json"
for _ in $(seq 1 200); do
  kill -0 "$server_pid" 2>/dev/null || break
  sleep 0.05
done
wait "$server_pid" 2>/dev/null || true
server_pid=""
sleep 0.2
proof_processes >"$output/processes-after-cleanup.txt"
[[ ! -s "$output/processes-after-cleanup.txt" ]] || { echo 'proof processes remain after cleanup' >&2; cat "$output/processes-after-cleanup.txt" >&2; exit 1; }

jq -n \
  --slurpfile binaries "$output/binaries.json" \
  --slurpfile canonical "$output/headless/canonical.json" \
  --slurpfile process "$output/process-binding.json" \
  --slurpfile worker "$output/worker-chain.json" '
  {
    schema:"edits.vimNixHerdrHq.semantic/1",status:"PASS",
    pins:{nixpkgs:"0ae2bc1419c3f345984c2629e72e7a631820fa4d",goNixpkgs:"cbb826608f7d081948eeb4ea0211b0cbd867b9d1",go:"1.23.12",herdr:"0.8.0",vim:"9.2.0478",hq:"3118886f34ac5615e8a7732a6297bd41900e21e1",yegappanLsp:"989016ae2ae4cbf304a9ca29478f47fec794493f",edits:"d83bf4c4860e02f37d6b41cc54fe8c881af4c779"},
    binaries:($binaries[0].rows|with_entries(.value |= {bytes,sha256,regular,symlink})),
    headless:{status:$canonical[0].status,completionWrites:$canonical[0].completionWrites,acceptedIDsDistinct:$canonical[0].acceptedIDsDistinct,explicitSubmitRuns:$canonical[0].explicitSubmitRuns},
    pty:{nativePopupJourneys:["fuzzy schema template","field key","unicode CRLF field value"],exactVimToHqLspBinding:($process[0].status=="PASS"),workspaceCount:1,paneCount:2,splitFocusRead:"PASS"},
    worker:{readyBeforeSubmit:true,readyAfterSubmit:true,managedWorkerCount:1,acceptedRows:$worker[0].acceptedRows,resultKinds:$worker[0].resultKinds,stdout:$worker[0].stdout,finalText:$worker[0].finalText,provider:$worker[0].provider},
    cleanup:{typedWorkerStop:true,workspaceClosed:true,sessionStopped:true,remainingProofProcesses:0}
  }
' >"$output/semantic.json"
semantic_sha=$(jq -cS . "$output/semantic.json" | sha256sum | awk '{print $1}')
jq -n --arg mode "$mode" --arg sha "$semantic_sha" --slurpfile semantic "$output/semantic.json" \
  '{schema:"edits.vimNixHerdrHq.runtimeReceipt/1",status:"PASS",mode:$mode,semantic:$semantic[0],semanticSha256:$sha,limitations:["WSLC host boundary is independently user-tested from the downloadable OCI artifact"]}' \
  >"$output/receipt.json"

copy_runtime_diagnostics
(
  cd "$output"
  find . -type f ! -name SHA256SUMS -print0 | sort -z | xargs -0 sha256sum > SHA256SUMS
  sha256sum --check SHA256SUMS
)
trap - EXIT INT TERM
rm -rf "$runtime"
printf 'PASS %s %s\n' "$mode" "$semantic_sha"
