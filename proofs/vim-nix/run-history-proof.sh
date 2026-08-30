set -Eeuo pipefail
umask 077

: "${PROOF_ROOT:?PROOF_ROOT must point to the exact composed Nix output}"
PROOF="$(readlink -f "$PROOF_ROOT")"
OUT="${PROOF_HISTORY_OUTPUT_DIR:-/work/history-evidence}"
RUNTIME="${PROOF_HISTORY_RUNTIME_DIR:-/work/history-runtime}"
SESSION="hq-history-${PROOF_RUN_SUFFIX:-$$}"
HERDR=/bin/herdr
VIM=/bin/vim
HQ=/bin/hq
HQ_TEST=/bin/hq-vim.test
HQ_VIM=/share/hq-vim
VIM9_LSP=/share/yegappan-lsp
SOURCE_MANIFEST="$PROOF/share/proof/source.json"

export HOME="$RUNTIME/home"
export XDG_CONFIG_HOME="$HOME/.config"
export XDG_RUNTIME_DIR="$RUNTIME/xdg-runtime"
export XDG_STATE_HOME="$RUNTIME/xdg-state"
export XDG_CACHE_HOME="$RUNTIME/xdg-cache"
export HERDR_CONFIG_PATH="$PROOF/share/proof/herdr.toml"
export SHELL=/bin/sh
export TERM=xterm-256color
export LANG=C.UTF-8
export LC_ALL=C.UTF-8
export PATH=/bin

require_fresh_directory() {
  local label="$1"
  local path="$2"
  if test -e "$path" && test ! -d "$path"; then
    printf 'vim-nix-history-proof: %s path is not a directory: %s\n' "$label" "$path" >&2
    exit 1
  fi
  mkdir -p "$path"
  if test -n "$(find "$path" -mindepth 1 -maxdepth 1 -print -quit)"; then
    printf 'vim-nix-history-proof: %s directory must be fresh and empty: %s\n' "$label" "$path" >&2
    exit 1
  fi
}
require_fresh_directory output "$OUT"
require_fresh_directory runtime "$RUNTIME"
mkdir -p "$OUT" "$HOME" "$XDG_CONFIG_HOME" "$XDG_RUNTIME_DIR" "$XDG_STATE_HOME" "$XDG_CACHE_HOME"
chmod 700 "$XDG_RUNTIME_DIR"

HERDR_PID=""
WORKSPACE_ID=""
ROOT_PANE_ID=""

cleanup() {
  local status=$?
  set +e
  if test -n "$WORKSPACE_ID"; then
    "$HERDR" --session "$SESSION" workspace close "$WORKSPACE_ID" \
      > "$OUT/workspace-close.cleanup.json" 2> "$OUT/workspace-close.cleanup.stderr" || true
  fi
  "$HERDR" --session "$SESSION" server stop \
    > "$OUT/herdr-stop.cleanup.txt" 2> "$OUT/herdr-stop.cleanup.stderr" || true
  if test -n "$HERDR_PID"; then
    kill "$HERDR_PID" 2>/dev/null || true
    wait "$HERDR_PID" 2>/dev/null || true
  fi
  return "$status"
}
trap cleanup EXIT INT TERM

fail() {
  printf 'vim-nix-history-proof: %s\n' "$*" >&2
  exit 1
}

pane_read() {
  "$HERDR" --session "$SESSION" pane read "$ROOT_PANE_ID" \
    --source recent-unwrapped --lines 300 > "$1" 2> "$1.stderr" || true
}

wait_for_server() {
  for _ in $(seq 1 200); do
    if "$HERDR" --session "$SESSION" status server > "$OUT/herdr-status.txt" 2> "$OUT/herdr-status.stderr"; then
      grep -Eq '^status:[[:space:]]+running$|"status"[[:space:]]*:[[:space:]]*"running"' "$OUT/herdr-status.txt" && return 0
    fi
    kill -0 "$HERDR_PID" 2>/dev/null || return 1
    sleep 0.1
  done
  return 1
}

wait_for_file() {
  local path=$1
  for _ in $(seq 1 400); do
    test -s "$path" && return 0
    kill -0 "$HERDR_PID" 2>/dev/null || return 1
    sleep 0.05
  done
  return 1
}

wait_for_exit_marker() {
  for _ in $(seq 1 600); do
    pane_read "$OUT/history-pane-read.txt"
    grep -Fxq '__VIM_NIX_HISTORY_EXIT_0__' "$OUT/history-pane-read.txt" && return 0
    if grep -E '^__VIM_NIX_HISTORY_EXIT_[1-9][0-9]*__$' "$OUT/history-pane-read.txt" >/dev/null 2>&1; then
      return 1
    fi
    sleep 0.1
  done
  return 1
}

test -s "$SOURCE_MANIFEST" || fail "missing exact source manifest"
for binding in herdr vim hq hq-vim.test; do
  test -x "/bin/$binding" || fail "missing image binding /bin/$binding"
  test "$(readlink -f "/bin/$binding")" = "$(readlink -f "$PROOF/bin/$binding")" \
    || fail "/bin/$binding does not resolve into the exact composed closure"
done
test "$(readlink -f "$HQ_VIM")" = "$(readlink -f "$PROOF/share/hq-vim")" \
  || fail "/share/hq-vim does not resolve into the exact composed closure"
test "$(readlink -f "$VIM9_LSP")" = "$(readlink -f "$PROOF/share/yegappan-lsp")" \
  || fail "/share/yegappan-lsp does not resolve into the exact composed closure"

cp "$SOURCE_MANIFEST" "$OUT/source.json"
printf '%s\n' "$PROOF" > "$OUT/proof-store-path.txt"
hq_source_sha="$(jq -er '.hqRevision' "$SOURCE_MANIFEST")"

"$HERDR" --session "$SESSION" server > "$OUT/herdr-server.stdout" 2> "$OUT/herdr-server.stderr" &
HERDR_PID=$!
wait_for_server || fail "Herdr server did not become ready"

workspace_json="$("$HERDR" --session "$SESSION" workspace create \
  --cwd "$RUNTIME" --label accepted-history-proof \
  --env "HOME=$HOME" --env "XDG_CONFIG_HOME=$XDG_CONFIG_HOME" \
  --env "XDG_RUNTIME_DIR=$XDG_RUNTIME_DIR" --env "XDG_STATE_HOME=$XDG_STATE_HOME" \
  --env "XDG_CACHE_HOME=$XDG_CACHE_HOME" --env "HERDR_CONFIG_PATH=$HERDR_CONFIG_PATH" \
  --env "SHELL=$SHELL" --env "TERM=$TERM" --env "LANG=$LANG" --env "LC_ALL=$LC_ALL" \
  --no-focus)"
printf '%s\n' "$workspace_json" > "$OUT/workspace-create.json"
WORKSPACE_ID="$(printf '%s' "$workspace_json" | jq -er '.result.workspace.workspace_id')"
ROOT_PANE_ID="$(printf '%s' "$workspace_json" | jq -er '.result.root_pane.pane_id')"
"$HERDR" --session "$SESSION" pane list --workspace "$WORKSPACE_ID" > "$OUT/pane-list.json"
test "$(jq '[.. | objects | select(has("pane_id")) | .pane_id] | unique | length' "$OUT/pane-list.json")" -eq 1 \
  || fail "accepted-history proof must use exactly one Herdr pane"

root_shell_ready=0
for _ in $(seq 1 200); do
  if "$HERDR" --session "$SESSION" pane process-info --pane "$ROOT_PANE_ID" \
    > "$OUT/root-pane-ready-process.json" 2> "$OUT/root-pane-ready-process.stderr"; then
    if jq -e '.result.process_info.foreground_processes | any(.argv == ["/bin/sh"])' \
      "$OUT/root-pane-ready-process.json" >/dev/null; then
      root_shell_ready=1
      break
    fi
  fi
  kill -0 "$HERDR_PID" 2>/dev/null || break
  sleep 0.1
done
test "$root_shell_ready" -eq 1 || fail "root pane /bin/sh did not become ready"
pane_read "$OUT/root-pane-ready-read.txt"

ready="$RUNTIME/history.ready"
done="$RUNTIME/history.done"
input_ready="$RUNTIME/history-input.ready"
input_done="$RUNTIME/history-input.done"
artifact_anchor="$OUT/conformance-anchor.json"
run_script="$RUNTIME/run-history-test.sh"
cat > "$run_script" <<EOF_RUN
#!/bin/sh
cd "$HQ_VIM" || exit 97
HQ_CHOICE_E2E=1 \\
HQ_BIN="$HQ" \\
VIM_EXE="$VIM" \\
VIM9_LSP_PATH="$VIM9_LSP" \\
VIMRUNTIME=/share/vim/vim92 \\
HQ_CANONICAL_SOURCE_SHA="$hq_source_sha" \\
HQ_CONFORMANCE_ARTIFACT="$artifact_anchor" \\
HQ_PTY_CAPTURE_READY="$ready" \\
HQ_PTY_CAPTURE_DONE="$done" \\
HQ_PTY_INPUT_READY="$input_ready" \\
HQ_PTY_INPUT_DONE="$input_done" \\
"$HQ_TEST" -test.v -test.count=1 -test.run '^TestAcceptedHistoryRecallE2E$'
status=\$?
printf '__VIM_NIX_HISTORY_EXIT_%s__\\n' "\$status"
exit "\$status"
EOF_RUN
chmod 700 "$run_script"
"$HERDR" --session "$SESSION" pane run "$ROOT_PANE_ID" "$run_script" \
  > "$OUT/history-pane-run.json" 2> "$OUT/history-pane-run.stderr"

wait_for_file "$input_ready" || fail "accepted-history PTY input latch did not become ready"
"$HERDR" --session "$SESSION" pane send-keys "$ROOT_PANE_ID" i \
  > "$OUT/history-input-send-keys.stdout" 2> "$OUT/history-input-send-keys.stderr"
"$HERDR" --session "$SESSION" pane send-text "$ROOT_PANE_ID" @ \
  > "$OUT/history-input-send-text.stdout" 2> "$OUT/history-input-send-text.stderr"
: > "$input_done"
wait_for_file "$ready" || fail "accepted-history popup/doc latch did not become ready"
pane_read "$OUT/history-pane-ready.txt"
"$HERDR" --session "$SESSION" pane process-info --pane "$ROOT_PANE_ID" > "$OUT/history-pane-process.json"
ps -eo pid=,ppid=,args= > "$OUT/processes-during-history.txt"
hq_lsp_pid="$(awk 'NF == 6 && $3 == "/bin/hq" && $4 == "lsp" && $5 == "--profile" && $6 == "local" { print $1 }' \
  "$OUT/processes-during-history.txt")"
test "$(printf '%s\n' "$hq_lsp_pid" | awk 'NF { count++ } END { print count + 0 }')" -eq 1 \
  || fail "exactly one /bin/hq lsp --profile local process is required"
jq -Rs 'split("\u0000")[:-1]' "/proc/$hq_lsp_pid/cmdline" > "$OUT/exact-hq-lsp-argv.json"
jq -e '. == ["/bin/hq","lsp","--profile","local"]' "$OUT/exact-hq-lsp-argv.json" >/dev/null \
  || fail "exact /bin/hq lsp --profile local argv is absent"

: > "$done"
wait_for_exit_marker || {
  cat "$OUT/history-pane-read.txt" >&2 || true
  fail "focused accepted-history E2E did not pass"
}
grep -F -- '--- PASS: TestAcceptedHistoryRecallE2E' "$OUT/history-pane-read.txt" >/dev/null \
  || fail "focused Go test PASS is absent from the Herdr pane"

history_artifact="$OUT/hq-vim-accepted-history-linux.json"
test -s "$history_artifact" || fail "accepted-history conformance artifact is missing"
jq -e --arg hq "$hq_source_sha" '
  .kind == "edits.hqVimAcceptedHistoryConformance.v1" and
  .status == "passed" and .hqSourceSha == $hq and
  .acceptedRows == 1 and .completionWrites == 0 and .eventWrites == 0 and
  .undoBaseline == "@" and .explicitSeedRows == 1 and
  .proof.Status == "passed" and .proof.Failure == ""
' "$history_artifact" >/dev/null || fail "accepted-history conformance artifact is invalid"

"$HERDR" --session "$SESSION" workspace close "$WORKSPACE_ID" \
  > "$OUT/workspace-close.json" 2> "$OUT/workspace-close.stderr"
WORKSPACE_ID=""
"$HERDR" --session "$SESSION" server stop > "$OUT/herdr-stop.txt" 2> "$OUT/herdr-stop.stderr"
for _ in $(seq 1 100); do
  kill -0 "$HERDR_PID" 2>/dev/null || break
  sleep 0.1
done
wait "$HERDR_PID" || true
HERDR_PID=""

sleep 0.2
ps -eo pid=,ppid=,args= > "$OUT/processes-after-cleanup.txt"
if grep -E '(/bin/(herdr|vim|hq|hq-vim\.test))([[:space:]]|$)' "$OUT/processes-after-cleanup.txt" >/dev/null; then
  grep -E '(/bin/(herdr|vim|hq|hq-vim\.test))([[:space:]]|$)' "$OUT/processes-after-cleanup.txt" >&2 || true
  fail "accepted-history proof processes remain after cleanup"
fi

artifact_sha="$(sha256sum "$history_artifact" | awk '{print $1}')"
jq -n \
  --arg proof "$PROOF" --arg session "$SESSION" --arg workspace "$(jq -r '.result.workspace.workspace_id' "$OUT/workspace-create.json")" \
  --arg pane "$ROOT_PANE_ID" --arg hq "$hq_source_sha" --arg artifactSha "sha256:$artifact_sha" \
  --slurpfile source "$SOURCE_MANIFEST" '{
    schema:"edits.vim-nix-accepted-history-e2e/1",
    status:"PASS",
    source:$source[0],
    input:{
      runtimeProofNested:false,focusedTest:"TestAcceptedHistoryRecallE2E",
      herdrActualInput:{status:"PASS",sendKeys:["i"],sendText:"@"}
    },
    runtime:{proofStorePath:$proof,hqSourceSha:$hq},
    gates:{
      herdrPane:"PASS",paneCount:1,herdrActualInputTransport:"PASS",
      exactHqLspProcess:["/bin/hq","lsp","--profile","local"],
      acceptedRows:1,completionWrites:0,eventWrites:0,undoBaseline:"@",
      workspaceClose:"PASS",herdrStop:"PASS",residualProcessCount:0
    },
    topology:{session:$session,workspaceId:$workspace,rootPaneId:$pane},
    artifact:{path:"hq-vim-accepted-history-linux.json",sha256:$artifactSha},
    limitations:{runtimeLifecycleNested:false,productionPromotion:false}
  }' > "$OUT/history-receipt.json"

manifest_tmp="$RUNTIME/SHA256SUMS"
(
  cd "$OUT"
  find . -type f ! -name SHA256SUMS -print0 | sort -z | xargs -0 sha256sum > "$manifest_tmp"
  mv "$manifest_tmp" SHA256SUMS
  sha256sum --check SHA256SUMS
)

trap - EXIT INT TERM
printf 'VIM_NIX_ACCEPTED_HISTORY_E2E_PASS\n'
