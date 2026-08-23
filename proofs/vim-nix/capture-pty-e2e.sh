#!/usr/bin/env bash
set -Eeuo pipefail
umask 077

script_dir=$(CDPATH= cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
repo_root=$(CDPATH= cd -- "$script_dir/../.." && pwd)
: "${PROOF_ROOT:?PROOF_ROOT must point to the exact composed runtime proof}"
proof=$(readlink -f "$PROOF_ROOT")
out=${PTY_CAPTURE_OUT:-"$repo_root/.local/pty-e2e"}
work=$(mktemp -d /tmp/hqcap.XXXXXX)
export TERM=${TERM:-xterm-256color}
current_display=
xvfb_pid=
attach_pid=
runtime_pid=
choice_pid=

stop_display() {
  set +e
  if test -n "$xvfb_pid"; then
    kill "$xvfb_pid" 2>/dev/null || true
    wait "$xvfb_pid" 2>/dev/null || true
  fi
  xvfb_pid=
  current_display=
}

cleanup() {
  set +e
  test -z "$attach_pid" || kill "$attach_pid" 2>/dev/null || true
  test -z "$runtime_pid" || kill "$runtime_pid" 2>/dev/null || true
  test -z "$choice_pid" || kill "$choice_pid" 2>/dev/null || true
  stop_display
  rm -rf "$work"
}
trap cleanup EXIT INT TERM

for command in Xvfb xterm scrot xdpyinfo xwininfo jq sha256sum; do
  command -v "$command" >/dev/null 2>&1 || { echo "missing capture command: $command" >&2; exit 2; }
done
for path in "$proof/bin/hq" "$proof/bin/hq-worker" "$proof/bin/herdr" "$proof/bin/vim" "$proof/bin/hq-vim.test"; do
  test -x "$path" || { echo "missing proof executable: $path" >&2; exit 2; }
done
for path in \
  "$proof/share/yegappan-lsp/plugin/lsp.vim" \
  "$proof/share/hq-vim/plugin/hq.vim" \
  "$proof/share/proof/source.json" \
  "$proof/share/proof/runtime-world.jsonl" \
  "$proof/share/proof/runtime-accepted.jsonl"; do
  test -s "$path" || { echo "missing proof material: $path" >&2; exit 2; }
done
if test -z "${VIMRUNTIME:-}" && test -d "$proof/share/vim/vim92"; then
  export VIMRUNTIME="$proof/share/vim/vim92"
fi
"$proof/bin/vim" --clean -Nu NONE -n -es \
  -c "if empty(globpath(&runtimepath, 'autoload/dist/ft.vim')) | cquit 42 | endif" \
  -c 'qa!'

rm -rf "$out"
mkdir -p "$out"

display_seed=$((120 + ($$ % 80)))
start_display() {
  local label=$1 candidate ready=0
  stop_display
  for offset in $(seq 0 79); do
    candidate=$((display_seed + offset))
    if test "$candidate" -gt 299; then
      candidate=$((120 + (candidate % 180)))
    fi
    test ! -e "/tmp/.X${candidate}-lock" || continue
    current_display=":$candidate"
    Xvfb "$current_display" -screen 0 1600x1000x24 -nolisten tcp \
      >"$out/xvfb-${label}.log" 2>&1 &
    xvfb_pid=$!
    for _ in $(seq 1 100); do
      if xdpyinfo -display "$current_display" >/dev/null 2>&1; then
        ready=1
        break
      fi
      kill -0 "$xvfb_pid" 2>/dev/null || break
      sleep 0.05
    done
    if test "$ready" -eq 1; then
      return 0
    fi
    stop_display
  done
  echo "unable to start an isolated X display for $label" >&2
  return 1
}

wait_ready() {
  local path=$1 pid=$2
  for _ in $(seq 1 400); do
    test -s "$path" && return 0
    kill -0 "$pid" 2>/dev/null || return 1
    sleep 0.05
  done
  return 1
}

wait_choice_clean() {
  for _ in $(seq 1 100); do
    if ! ps -eo args= | grep -F "$proof/bin/hq lsp --profile local" | grep -v grep >/dev/null; then
      return 0
    fi
    sleep 0.05
  done
  echo "choice E2E left an HQ LSP process" >&2
  return 1
}

wait_window() {
  local title=$1 id=
  for _ in $(seq 1 100); do
    id=$(DISPLAY="$current_display" xwininfo -root -tree 2>/dev/null | awk -v title="$title" 'index($0, "\"" title "\"") {print $1; exit}')
    test -n "$id" && { printf '%s\n' "$id"; return 0; }
    sleep 0.05
  done
  return 1
}

capture_diagnostic_root() {
  local file=$1
  DISPLAY="$current_display" scrot "$out/$file" >/dev/null 2>&1 || true
}

capture_choice() {
  local test_name=$1 title=$2 file=$3
  local slug=${test_name#Test}
  local ready="$work/$slug.ready" done="$work/$slug.done" log="$out/$slug.log"
  start_display "$slug"
  env DISPLAY="$current_display" VIMRUNTIME="${VIMRUNTIME:-}" LANG=C.UTF-8 LC_ALL=C.UTF-8 \
    xterm -geometry 180x55+0+0 -title "$title" \
    -e bash -lc "cd '$proof/share/hq-vim' && \
      HQ_CHOICE_E2E=1 \
      HQ_PTY_CAPTURE_READY='$ready' \
      HQ_PTY_CAPTURE_DONE='$done' \
      HQ_BIN='$proof/bin/hq' \
      VIM_EXE='$proof/bin/vim' \
      VIM9_LSP_PATH='$proof/share/yegappan-lsp' \
      '$proof/bin/hq-vim.test' -test.v -test.count=1 -test.run '^${test_name}\$'; \
      rc=\$?; echo __E2E_EXIT_\$rc__; exit \$rc" \
    >"$log" 2>&1 &
  choice_pid=$!
  if ! wait_ready "$ready" "$choice_pid"; then
    capture_diagnostic_root "FAILED-$slug.png"
    kill "$choice_pid" 2>/dev/null || true
    wait "$choice_pid" 2>/dev/null || true
    choice_pid=
    cat "$log" >&2 || true
    stop_display
    return 1
  fi
  local window
  if ! window=$(wait_window "$title"); then
    capture_diagnostic_root "FAILED-$slug-window.png"
    kill "$choice_pid" 2>/dev/null || true
    wait "$choice_pid" 2>/dev/null || true
    choice_pid=
    stop_display
    return 1
  fi
  DISPLAY="$current_display" scrot -b -w "$window" "$out/$file"
  test -s "$out/$file"
  : > "$done"
  if ! wait "$choice_pid"; then
    choice_pid=
    cat "$log" >&2 || true
    stop_display
    return 1
  fi
  choice_pid=
  stop_display
  wait_choice_clean
}

# Each image observes one focused E2E. No test calls or wraps another E2E.
capture_choice TestAgentDefaultChoiceE2E 'HQ agent default choice E2E' '01-agent-default.png'
capture_choice TestDirectFallbackChoiceE2E 'HQ direct fallback choice E2E' '02-direct-fallback.png'

# Runtime lifecycle is independent from editor choice/submit. It consumes one
# exact accepted fixture and proves Herdr/worker/provider lifecycle plus cleanup.
runtime_ready="$work/runtime.ready.json"
runtime_done="$work/runtime.done"
runtime_script="$work/run-proof.sh"
cat "$script_dir"/run-proof.parts/*.sh > "$runtime_script"
chmod +x "$runtime_script"
PTY_CAPTURE_READY="$runtime_ready" \
PTY_CAPTURE_DONE="$runtime_done" \
PROOF_ROOT="$proof" \
PROOF_OUTPUT_DIR="$out/runtime-evidence" \
PROOF_RUNTIME_DIR="$work/r" \
PROOF_RUN_SUFFIX="c$$" \
"$runtime_script" >"$out/runtime.log" 2>&1 &
runtime_pid=$!
wait_ready "$runtime_ready" "$runtime_pid" || { cat "$out/runtime.log" >&2; exit 1; }
session=$(jq -er .session "$runtime_ready")
workspace=$(jq -er .workspaceId "$runtime_ready")
runtime_home="$work/r/home"
runtime_config="$runtime_home/.config"
runtime_xdg_runtime="$work/r/xdg-runtime"
runtime_xdg_state="$work/r/xdg-state"
runtime_xdg_cache="$work/r/xdg-cache"
env HOME="$runtime_home" XDG_CONFIG_HOME="$runtime_config" XDG_RUNTIME_DIR="$runtime_xdg_runtime" \
  XDG_STATE_HOME="$runtime_xdg_state" XDG_CACHE_HOME="$runtime_xdg_cache" \
  HERDR_CONFIG_PATH="$proof/share/proof/herdr.toml" \
  "$proof/bin/herdr" --session "$session" workspace focus "$workspace" >/dev/null
start_display runtime-lifecycle
env DISPLAY="$current_display" VIMRUNTIME="${VIMRUNTIME:-}" LANG=C.UTF-8 LC_ALL=C.UTF-8 \
  xterm -geometry 180x55+0+0 -title 'HQ runtime lifecycle E2E' \
  -e env HOME="$runtime_home" XDG_CONFIG_HOME="$runtime_config" XDG_RUNTIME_DIR="$runtime_xdg_runtime" \
    XDG_STATE_HOME="$runtime_xdg_state" XDG_CACHE_HOME="$runtime_xdg_cache" \
    HERDR_CONFIG_PATH="$proof/share/proof/herdr.toml" TERM=xterm-256color LANG=C.UTF-8 LC_ALL=C.UTF-8 \
    "$proof/bin/herdr" --session "$session" >"$out/herdr-attach.log" 2>&1 &
attach_pid=$!
if ! runtime_window=$(wait_window 'HQ runtime lifecycle E2E'); then
  capture_diagnostic_root 'FAILED-runtime-window.png'
  exit 1
fi
sleep 0.2
DISPLAY="$current_display" scrot -b -w "$runtime_window" "$out/03-runtime-lifecycle.png"
kill "$attach_pid" 2>/dev/null || true
wait "$attach_pid" 2>/dev/null || true
attach_pid=
stop_display
: > "$runtime_done"
wait "$runtime_pid" || { cat "$out/runtime.log" >&2; exit 1; }
runtime_pid=

jq -n \
  --arg proof "$proof" \
  --arg agent "$(sha256sum "$out/01-agent-default.png" | cut -d' ' -f1)" \
  --arg direct "$(sha256sum "$out/02-direct-fallback.png" | cut -d' ' -f1)" \
  --arg runtime "$(sha256sum "$out/03-runtime-lifecycle.png" | cut -d' ' -f1)" \
  --slurpfile source "$proof/share/proof/source.json" \
  '{schema:"edits.hq-vim-pty-capture/2",status:"PASS",source:$source[0],proofRoot:$proof,screenshots:[{file:"01-agent-default.png",sha256:$agent,e2e:"TestAgentDefaultChoiceE2E"},{file:"02-direct-fallback.png",sha256:$direct,e2e:"TestDirectFallbackChoiceE2E"},{file:"03-runtime-lifecycle.png",sha256:$runtime,e2e:"vim-nix runtime lifecycle"}],captureAddsBehavior:false,e2eComposition:false,displayIsolation:"one-fresh-Xvfb-per-screenshot"}' \
  > "$out/receipt.json"
(
  cd "$out"
  find . -type f ! -name SHA256SUMS -print0 | sort -z | xargs -0 sha256sum > SHA256SUMS
  sha256sum --check SHA256SUMS
)
printf 'PTY_E2E_CAPTURE_PASS %s\n' "$out"
