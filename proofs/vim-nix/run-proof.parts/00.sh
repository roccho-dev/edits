set -Eeuo pipefail
umask 077

mode="${1:-all}"
case "$mode" in
  all|full) RUN_EDITOR=1; RUN_RUNTIME=1 ;;
  editor) RUN_EDITOR=1; RUN_RUNTIME=0 ;;
  runtime) RUN_EDITOR=0; RUN_RUNTIME=1 ;;
  *) printf 'vim-nix-proof: unsupported mode: %s\n' "$mode" >&2; exit 2 ;;
esac

: "${PROOF_ROOT:?PROOF_ROOT must point to the exact composed Nix output}"
PROOF="$(readlink -f "$PROOF_ROOT")"
OUT="${PROOF_OUTPUT_DIR:-/work/evidence}"
RUNTIME="${PROOF_RUNTIME_DIR:-/work/runtime}"
SESSION="hq-vim-${PROOF_RUN_SUFFIX:-$$}"
PROFILE_ROOT="$RUNTIME/home/.config/roccho/hq/profiles"
PROFILE="$PROFILE_ROOT/local.json"
WORKSPACE_ROOT="$RUNTIME/workspace"
WORLD="$RUNTIME/world.jsonl"
ACCEPTED="$RUNTIME/accepted.jsonl"
EVENTS="$WORKSPACE_ROOT/.hq/events/events.jsonl"
BINDINGS="$RUNTIME/executable-bindings.json"
HERDR="$PROOF/bin/herdr"
HQ="$PROOF/bin/hq"
HQ_WORKER="$PROOF/bin/hq-worker"
VIM="$PROOF/bin/vim"
SOURCE_MANIFEST="$PROOF/share/proof/source.json"
RUNTIME_WORLD_FIXTURE="$PROOF/share/proof/runtime-world.jsonl"
RUNTIME_ACCEPTED_FIXTURE="$PROOF/share/proof/runtime-accepted.jsonl"

export HOME="$RUNTIME/home"
export XDG_CONFIG_HOME="$RUNTIME/home/.config"
export XDG_RUNTIME_DIR="$RUNTIME/xdg-runtime"
export XDG_STATE_HOME="$RUNTIME/xdg-state"
export XDG_CACHE_HOME="$RUNTIME/xdg-cache"
export HERDR_CONFIG_PATH="$PROOF/share/proof/herdr.toml"
export SHELL=/bin/sh
export TERM=xterm-256color
export LANG=C.UTF-8
export LC_ALL=C.UTF-8
export PATH="/bin:${PATH:-}"

mkdir -p "$OUT" "$RUNTIME"
find "$OUT" -mindepth 1 -maxdepth 1 -exec rm -rf -- {} +
find "$RUNTIME" -mindepth 1 -maxdepth 1 -exec rm -rf -- {} +
mkdir -p "$HOME" "$XDG_CONFIG_HOME" "$XDG_RUNTIME_DIR" "$XDG_STATE_HOME" "$XDG_CACHE_HOME" \
  "$PROFILE_ROOT" "$WORKSPACE_ROOT/.hq/events"
chmod 700 "$XDG_RUNTIME_DIR"
: > "$ACCEPTED"
: > "$EVENTS"

HERDR_PID=""
WORKSPACE_ID=""
ROOT_PANE_ID=""
TASK_PANE_ID=""
PROVEN_WORKSPACE_ID=""

cleanup() {
  local status=$?
  set +e
  if test -f "$PROFILE"; then
    "$HQ_WORKER" stop --profile local --profile-root "$PROFILE_ROOT" --timeout 10s \
      > "$OUT/worker-stop.cleanup.jsonl" 2> "$OUT/worker-stop.cleanup.stderr" || true
  fi
  if test -n "$WORKSPACE_ID"; then
    "$HERDR" --session "$SESSION" workspace close "$WORKSPACE_ID" \
      > "$OUT/workspace-close.cleanup.json" 2> "$OUT/workspace-close.cleanup.stderr" || true
  fi
  "$HERDR" --session "$SESSION" server stop \
    > "$OUT/herdr-stop.cleanup.txt" 2> "$OUT/herdr-stop.cleanup.stderr" || true
  if test -n "$HERDR_PID"; then
    for _ in $(seq 1 50); do
      kill -0 "$HERDR_PID" 2>/dev/null || break
      sleep 0.1
    done
    kill "$HERDR_PID" 2>/dev/null || true
    wait "$HERDR_PID" 2>/dev/null || true
  fi
  if test "$status" -ne 0; then
    printf 'vim-nix-proof: FAILED with status %s\n' "$status" >&2
  fi
  return "$status"
}
trap cleanup EXIT INT TERM

fail() {
  printf 'vim-nix-proof: %s\n' "$*" >&2
  exit 1
}

wait_for_server() {
  for _ in $(seq 1 200); do
    if "$HERDR" --session "$SESSION" status server > "$OUT/herdr-status.txt" 2> "$OUT/herdr-status.stderr"; then
      if grep -Eq '^status:[[:space:]]+running$|"status"[[:space:]]*:[[:space:]]*"running"' "$OUT/herdr-status.txt"; then
        return 0
      fi
    fi
    kill -0 "$HERDR_PID" 2>/dev/null || {
      cat "$OUT/herdr-server.stderr" >&2 || true
      return 1
    }
    sleep 0.1
  done
  return 1
}

pane_read() {
  local pane="$1" target="$2"
  "$HERDR" --session "$SESSION" pane read "$pane" --source recent-unwrapped --lines 240 \
    > "$target" 2> "$target.stderr" || true
}

wait_for_pane_marker() {
  local pane="$1" marker="$2" target="$3" max="${4:-900}"
  for _ in $(seq 1 "$max"); do
    pane_read "$pane" "$target"
    if grep -Fxq "$marker" "$target"; then
      return 0
    fi
    if grep -E '^__VIM_NIX_[A-Z_]+_EXIT_[1-9][0-9]*__$' "$target" >/dev/null 2>&1; then
      cat "$target" >&2
      return 1
    fi
    sleep 0.1
  done
  cat "$target" >&2 || true
  return 1
}

test -s "$SOURCE_MANIFEST" || fail "missing exact source manifest"
test -s "$RUNTIME_WORLD_FIXTURE" || fail "missing runtime world fixture"
test -s "$RUNTIME_ACCEPTED_FIXTURE" || fail "missing runtime accepted fixture"
printf '%s\n' "$PROOF" > "$OUT/proof-store-path.txt"
cp "$SOURCE_MANIFEST" "$OUT/source.json"
{
  "$HERDR" --version
  "$VIM" --version | sed -n '1,6p'
  "$HQ" --help 2>&1 | sed -n '1,20p' || true
  "$HQ_WORKER" --help 2>&1 | sed -n '1,20p' || true
} > "$OUT/versions.txt"

"$VIM" -Nu NONE -n -i NONE -es \
  '+if v:version != 902 || !has("patch-9.2.478") || !has("vim9script") || !has("channel") || !has("timers") || !has("popupwin") || !has("insert_expand") || !has("multi_byte") || !has("terminal") | cquit 42 | endif' \
  '+quitall!'

for name in herdr vim hq hq-worker hq-worker-proof-provider hq-vim.test hq-vim-smoke proof-sh; do
  path="$PROOF/bin/$name"
  test -e "$path" || fail "missing $path"
  target="$(readlink -f "$path")"
  printf '%s\t%s\n' "$name" "$target"
done > "$OUT/symlink-targets.tsv"

test -f "$PROOF/bin/proof-sh" || fail "proof-sh is not a regular file"
test ! -L "$PROOF/bin/proof-sh" || fail "proof-sh is unexpectedly a symlink"
proof_sha="$(sha256sum "$PROOF/bin/proof-sh" | awk '{print $1}')"
find "$PROOF/bin" -maxdepth 1 \( -type f -o -type l \) | sort | while read -r path; do
  target="$(readlink -f "$path")"
  sha256sum "$target"
done > "$OUT/binary-SHA256SUMS"
printf 'sha256:%s\n' "$proof_sha" > "$OUT/proof-sh.digest.txt"

run_editor_proof() {
  local test_name command
  local -a pty_tests=(
    TestAgentDefaultChoiceE2E
    TestAgentPromptFieldChoiceE2E
    TestDirectFallbackChoiceE2E
    TestUnicodeDirectFieldValueE2E
  )
  local -a headless_tests=(
    TestEditorSurfaceAndBindingFailClosed
    TestAgentDecisionSubmitE2E
    TestDirectCommandSubmitE2E
    TestAcceptedSubmitKeepsDraftOnUnsafeConsumption
  )

  for test_name in "${pty_tests[@]}"; do
    command=$(printf 'cd %q && HQ_CHOICE_E2E=1 HQ_BIN=%q VIM_EXE=%q VIM9_LSP_PATH=%q LANG=C.UTF-8 LC_ALL=C.UTF-8 TERM=xterm-256color %q -test.v -test.count=1 -test.run %q' \
      "$PROOF/share/hq-vim" "$HQ" "$VIM" "$PROOF/share/yegappan-lsp" \
      "$PROOF/bin/hq-vim.test" "^${test_name}$")
    timeout 90s script -qefc "$command" "$OUT/editor-${test_name}.typescript" \
      > "$OUT/editor-${test_name}.log" 2>&1
    grep -F -- "--- PASS: $test_name" "$OUT/editor-${test_name}.log" >/dev/null \
      || fail "editor PTY test did not pass: $test_name"
  done

  (
    cd "$PROOF/share/hq-vim"
    HQ_BIN="$HQ" VIM_EXE="$VIM" VIM9_LSP_PATH="$PROOF/share/yegappan-lsp" \
      LANG=C.UTF-8 LC_ALL=C.UTF-8 TERM=xterm-256color \
      "$PROOF/bin/hq-vim.test" -test.v -test.count=1 \
      -test.run '^(TestEditorSurfaceAndBindingFailClosed|TestAgentDecisionSubmitE2E|TestDirectCommandSubmitE2E|TestAcceptedSubmitKeepsDraftOnUnsafeConsumption)$' \
      > "$OUT/editor-headless.log" 2>&1
  )
  for test_name in "${headless_tests[@]}"; do
    grep -F -- "--- PASS: $test_name" "$OUT/editor-headless.log" >/dev/null \
      || fail "editor headless test did not pass: $test_name"
  done

  jq -n \
    --arg proof "$PROOF" \
    --slurpfile source "$SOURCE_MANIFEST" '{
      schema:"edits.vim-nix-editor-e2e/1",
      status:"PASS",
      source:$source[0],
      runtime:{proofStorePath:$proof},
      gates:{
        testCount:8,
        ptyTestCount:4,
        headlessTestCount:4,
        tests:[
          "TestAgentDefaultChoiceE2E",
          "TestAgentPromptFieldChoiceE2E",
          "TestDirectFallbackChoiceE2E",
          "TestUnicodeDirectFieldValueE2E",
          "TestEditorSurfaceAndBindingFailClosed",
          "TestAgentDecisionSubmitE2E",
          "TestDirectCommandSubmitE2E",
          "TestAcceptedSubmitKeepsDraftOnUnsafeConsumption"
        ]
      }
    }' > "$OUT/editor-receipt.json"
}

if test "$RUN_EDITOR" -eq 1; then
  run_editor_proof
fi

if test "$RUN_RUNTIME" -eq 0; then
  manifest_tmp="$RUNTIME/editor-SHA256SUMS.tmp"
  (
    cd "$OUT"
    find . -type f ! -name SHA256SUMS -print0 | sort -z | xargs -0 sha256sum > "$manifest_tmp"
    mv "$manifest_tmp" SHA256SUMS
    sha256sum --check SHA256SUMS
  )
  trap - EXIT INT TERM
  printf 'VIM_NIX_EDITOR_E2E_PASS\n'
  exit 0
fi
