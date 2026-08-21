#!/usr/bin/env bash
set -euo pipefail

herdr=$1
repo_root=$2
out=$3
work=$4

test -x "$herdr"
"$herdr" --version | tee "$out/evidence/herdr.version.txt"
grep -Fxq 'herdr 0.8.0' "$out/evidence/herdr.version.txt"

root="$work/herdr"
mkdir -p "$root"/{home,config,state,cache}
export HOME="$root/home"
export XDG_CONFIG_HOME="$root/config"
export XDG_STATE_HOME="$root/state"
export XDG_CACHE_HOME="$root/cache"
export TERM=${TERM:-xterm-256color}

"$herdr" server >"$out/logs/herdr-server.stdout.txt" 2>"$out/logs/herdr-server.stderr.txt" &
server_pid=$!
cleanup() {
  "$herdr" server stop >/dev/null 2>&1 || true
  kill "$server_pid" >/dev/null 2>&1 || true
  wait "$server_pid" >/dev/null 2>&1 || true
}
trap cleanup EXIT
for _ in $(seq 1 100); do
  if "$herdr" status server --json >"$out/evidence/herdr-status-running.json" 2>/dev/null; then break; fi
  sleep 0.05
done
python3 - "$out/evidence/herdr-status-running.json" <<'PY'
import json, sys
state = json.load(open(sys.argv[1]))
assert state["running"] and state["compatible"] and state["version"] == "0.8.0"
PY

"$herdr" workspace create --cwd "$repo_root" --label local-first --no-focus >"$out/evidence/herdr-workspace-create.json"
workspace=$(python3 - "$out/evidence/herdr-workspace-create.json" <<'PY'
import json, sys
print(json.load(open(sys.argv[1]))["result"]["workspace"]["workspace_id"])
PY
)
"$herdr" pane list --workspace "$workspace" >"$out/evidence/herdr-panes-one.json"
pane1=$(python3 - "$out/evidence/herdr-panes-one.json" <<'PY'
import json, sys
panes = json.load(open(sys.argv[1]))["result"]["panes"]
assert len(panes) == 1
print(panes[0]["pane_id"])
PY
)
"$herdr" pane run "$pane1" sleep 30 >"$out/evidence/herdr-pane-one-run.json"
"$herdr" pane split --pane "$pane1" --direction right --ratio 0.5 --cwd "$repo_root" --no-focus >"$out/evidence/herdr-split.json"
"$herdr" pane list --workspace "$workspace" >"$out/evidence/herdr-panes-two.json"
pane2=$(python3 - "$out/evidence/herdr-panes-two.json" "$pane1" <<'PY'
import json, sys
panes = json.load(open(sys.argv[1]))["result"]["panes"]
assert len(panes) == 2
print(next(p["pane_id"] for p in panes if p["pane_id"] != sys.argv[2]))
PY
)
"$herdr" pane run "$pane2" sleep 30 >"$out/evidence/herdr-pane-two-run.json"

for label in one two; do
  if test "$label" = one; then pane=$pane1; else pane=$pane2; fi
  ready=0
  for _ in $(seq 1 100); do
    target="$out/evidence/herdr-pane-$label-process.json"
    "$herdr" pane process-info --pane "$pane" >"$target"
    if python3 - "$target" <<'PY'
import json, sys
rows = json.load(open(sys.argv[1]))["result"]["process_info"]["foreground_processes"]
raise SystemExit(0 if any(row.get("argv") == ["sleep", "30"] for row in rows) else 1)
PY
    then ready=1; break; fi
    sleep 0.05
  done
  test "$ready" -eq 1
done

"$herdr" workspace close "$workspace" >"$out/evidence/herdr-workspace-close.json"
"$herdr" server stop >"$out/evidence/herdr-server-stop.json"
wait "$server_pid" || true
trap - EXIT
printf '{"running":false,"status":"not-running"}\n' >"$out/evidence/herdr-status-stopped.json"
