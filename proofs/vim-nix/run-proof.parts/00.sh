set -Eeuo pipefail
umask 077

mode="${1:-all}"
case "$mode" in
  all) ;;
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

rm -rf "$OUT" "$RUNTIME"
mkdir -p "$OUT" "$HOME" "$XDG_CONFIG_HOME" "$XDG_RUNTIME_DIR" "$XDG_STATE_HOME" "$XDG_CACHE_HOME" \
  "$PROFILE_ROOT" "$WORKSPACE_ROOT/.hq/events"
chmod 700 "$XDG_RUNTIME_DIR"
: > "$ACCEPTED"
: > "$EVENTS"

HERDR_PID=""
WORKSPACE_ID=""
ROOT_PANE_ID=""
TASK_PANE_ID=""
PROVEN_WORKSPACE_ID=""
cleanup_started=0

cleanup() {
  local status=$?
  set +e
  cleanup_started=1
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
find "$PROOF/bin" -maxdepth 1 -type f -o -type l | sort | while read -r path; do
  target="$(readlink -f "$path")"
  sha256sum "$target"
done > "$OUT/binary-SHA256SUMS"
printf 'sha256:%s\n' "$proof_sha" > "$OUT/proof-sh.digest.txt"

# Editor completion/submit E2Es run independently; this proof owns only runtime lifecycle.
