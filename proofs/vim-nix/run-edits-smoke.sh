# shellcheck shell=bash
set -Eeuo pipefail
umask 077

HERDR=/bin/edits-mux
runtime="$(mktemp -d /tmp/edits-smoke.XXXXXXXX)"
home="$runtime/home"
config="$home/.config"
profile_root="$config/roccho/hq/profiles"
workspace="$runtime/workspace"
events="$workspace/.hq/events/events.jsonl"
world="$runtime/world.jsonl"
accepted="$runtime/accepted.jsonl"
capabilities="$runtime/capabilities.json"
transcript="$runtime/edits.typescript"
output="$runtime/edits.stdout"
processes="$runtime/processes.txt"
session=
workspace_id=
root_pane_id=
driver_pid=

# shellcheck disable=SC2329
cleanup() {
  set +e
  if test -n "$session"; then
    "$HERDR" --session "$session" server stop >/dev/null 2>&1 || true
  fi
  if test -n "$driver_pid"; then
    wait "$driver_pid" 2>/dev/null || true
  fi
}
trap cleanup EXIT

mkdir -p "$profile_root" "$workspace/.hq/events" "$runtime/launcher-runtime"
cp /share/hq-vim/testdata/strict-world.jsonl "$world"
: > "$accepted"
: > "$events"
printf '{}\n' > "$capabilities"
jq -n \
  --arg world "$world" --arg accepted "$accepted" --arg workspace "$workspace" \
  --arg events "$events" --arg capabilities "$capabilities" '{
    kind:"hq.profile.v1",name:"local",deployment_id:"edits-interactive-smoke",
    world_path:$world,accepted_path:$accepted,workspace_root:$workspace,
    events_path:$events,capabilities_path:$capabilities,
    poll_interval_ms:50,health_timeout_ms:2000
  }' > "$profile_root/local.json"

export HOME="$home"
export XDG_CONFIG_HOME="$config"
export XDG_RUNTIME_DIR="$runtime/launcher-runtime"
export XDG_STATE_HOME="$home/.local/state"
export XDG_CACHE_HOME="$home/.cache"
# util-linux script allocates the real PTY but is not a terminal emulator.
# TERM=dumb prevents Herdr's attach client from waiting for palette replies.
export TERM=dumb LANG=C.UTF-8 LC_ALL=C.UTF-8

timeout --signal=TERM --kill-after=5s 45s \
  script -qefc "/bin/edits $workspace" "$transcript" > "$output" 2>&1 &
driver_pid=$!

metadata=
for _ in $(seq 1 400); do
  metadata="$(tr -d '\r' < "$output" \
    | grep -Eo 'edits: session=[^ ]+ workspace=[^ ]+ pane=[^[:space:]]+' \
    | tail -n 1 || true)"
  test -n "$metadata" && break
  kill -0 "$driver_pid" 2>/dev/null || break
  sleep 0.05
done
test -n "$metadata" || {
  cat "$output" >&2
  printf 'edits-smoke: launcher metadata did not appear\n' >&2
  exit 1
}

session="${metadata#edits: session=}"
session="${session%% *}"
workspace_id="${metadata#* workspace=}"
workspace_id="${workspace_id%% *}"
root_pane_id="${metadata##* pane=}"

"$HERDR" --session "$session" pane list --workspace "$workspace_id" \
  > "$runtime/pane-list.json"
test "$(jq '[.. | objects | select(has("pane_id")) | .pane_id] | unique | length' \
  "$runtime/pane-list.json")" -eq 1

vim_pid=
hq_pid=
for _ in $(seq 1 400); do
  if "$HERDR" --session "$session" pane process-info --pane "$root_pane_id" \
      > "$runtime/pane-process.json" 2> "$runtime/pane-process.stderr"; then
    vim_pid="$(jq -er '.result.process_info.foreground_processes[]
      | select((.argv[0] == "/bin/vim" or .argv[0] == "/bin/edits-client")) | .pid' "$runtime/pane-process.json" 2>/dev/null || true)"
  fi
  ps -eo pid=,args= > "$processes"
  hq_pid="$(awk 'NF == 5 && ($2 == "/bin/hq" || $2 == "/bin/edits-service") && $3 == "lsp" && $4 == "--profile" && $5 == "local" { print $1 }' \
    "$processes")"
  if test -n "$vim_pid" && test "$(printf '%s\n' "$hq_pid" | awk 'NF { count++ } END { print count+0 }')" -eq 1; then
    break
  fi
  kill -0 "$driver_pid" 2>/dev/null || break
  sleep 0.05
done
test -n "$vim_pid" || {
  "$HERDR" --session "$session" pane read "$root_pane_id" \
    --source recent-unwrapped --lines 120 >&2 2>/dev/null || true
  cat "$output" >&2
  printf 'edits-smoke: Vim did not become the Herdr pane foreground process\n' >&2
  exit 1
}
test "$(printf '%s\n' "$hq_pid" | awk 'NF { count++ } END { print count+0 }')" -eq 1 || {
  "$HERDR" --session "$session" pane read "$root_pane_id" \
    --source recent-unwrapped --lines 120 >&2 2>/dev/null || true
  cat "$output" >&2
  cat "$processes" >&2
  printf 'edits-smoke: exact edits-service/HQ lsp --profile local process was not observed\n' >&2
  exit 1
}

"$HERDR" --session "$session" server stop > "$runtime/server-stop.txt"
session=
set +e
wait "$driver_pid"
driver_status=$?
set -e
driver_pid=
test "$driver_status" -eq 0 || {
  cat "$output" >&2
  printf 'edits-smoke: launcher exited %s\n' "$driver_status" >&2
  exit 1
}
tr -d '\r' < "$output" > "$runtime/edits.stdout.normalized"
grep -Fxq 'herdr: server shut down: server is shutting down' \
  "$runtime/edits.stdout.normalized" || {
  cat "$output" >&2
  printf 'edits-smoke: orderly shutdown marker was not observed\n' >&2
  exit 1
}
test ! -e "/proc/$vim_pid"
test ! -e "/proc/$hq_pid"
printf 'EDITS_INTERACTIVE_PTY_SMOKE_PASS\n'
