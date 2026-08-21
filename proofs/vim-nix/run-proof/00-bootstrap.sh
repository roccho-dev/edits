usage() {
  echo 'usage: run-vim-nix-proof --proof-root PATH --output PATH [--mode NAME]' >&2
  exit 2
}

proof_root=""
output=""
mode="host"
while (($#)); do
  case "$1" in
    --proof-root) proof_root=${2:-}; shift 2 ;;
    --output) output=${2:-}; shift 2 ;;
    --mode) mode=${2:-}; shift 2 ;;
    *) usage ;;
  esac
done
[[ -n "$proof_root" && -n "$output" ]] || usage
proof_root=$(readlink -f "$proof_root")
mkdir -p "$output"
output=$(readlink -f "$output")

required=(herdr vim hq hq-worker proof-sh hq-vim.test hq-vim-smoke)
for name in "${required[@]}"; do
  [[ -e "$proof_root/bin/$name" ]] || { echo "missing proof binary: $name" >&2; exit 1; }
done
[[ -d "$proof_root/share/hq-vim" ]] || { echo 'missing hq-vim runtime' >&2; exit 1; }
[[ -d "$proof_root/share/yegappan-lsp" ]] || { echo 'missing yegappan/lsp runtime' >&2; exit 1; }

# Herdr uses filesystem Unix sockets. Keep the runtime root independent of the
# potentially long GitHub Actions TMPDIR and fail before startup if any socket
# pathname would exceed Linux sockaddr_un.sun_path (108 bytes including NUL).
runtime=$(mktemp -d /tmp/vnp.XXXXXX)
home="$runtime/h"
config="$runtime/c"
state="$runtime/s"
cache="$runtime/k"
run="$runtime/r"
workspace="$runtime/w"
profile_root="$config/roccho/hq/profiles"
mkdir -p "$home" "$config" "$state" "$cache" "$run" "$workspace" "$profile_root" "$runtime/events"
chmod 700 "$run"

case "$mode" in
  host) mode_tag=h ;;
  docker) mode_tag=d ;;
  oci) mode_tag=o ;;
  wslc) mode_tag=w ;;
  *) mode_tag=x ;;
esac
session="vnp-${mode_tag}-$$"
socket_path="$config/herdr/sessions/$session/herdr.sock"
client_socket_path="$config/herdr/sessions/$session/herdr-client.sock"
socket_bytes=$(printf '%s' "$socket_path" | wc -c)
client_socket_bytes=$(printf '%s' "$client_socket_path" | wc -c)
if ((socket_bytes > 107 || client_socket_bytes > 107)); then
  printf 'Herdr Unix socket path exceeds sun_path: server=%s client=%s\n' "$socket_bytes" "$client_socket_bytes" >&2
  exit 1
fi
jq -n --arg runtime "$runtime" --arg session "$session" \
  --arg server "$socket_path" --arg client "$client_socket_path" \
  --argjson serverBytes "$socket_bytes" --argjson clientBytes "$client_socket_bytes" \
  '{schema:"edits.vimNixProof.socketPaths/1",status:"PASS",runtimeRoot:$runtime,session:$session,limitBytes:107,server:{path:$server,bytes:$serverBytes},client:{path:$client,bytes:$clientBytes}}' \
  >"$output/socket-paths.json"

server_pid=""
workspace_id=""
root_pane=""
task_pane=""
worker_started=0
cleanup_started=0

export HOME="$home"
export XDG_CONFIG_HOME="$config"
export XDG_STATE_HOME="$state"
export XDG_CACHE_HOME="$cache"
export XDG_RUNTIME_DIR="$run"
export HERDR_CONFIG_PATH="$proof_root/share/proof/herdr.toml"
export SHELL=/bin/sh
export TERM=xterm-256color
export LANG=C.UTF-8
export LC_ALL=C.UTF-8

h() { "$proof_root/bin/herdr" --session "$session" "$@"; }

copy_runtime_diagnostics() {
  mkdir -p "$output/runtime"
  cp -a "$runtime"/. "$output/runtime/" 2>/dev/null || true
}

read_proc_argv() {
  local pid=$1 arg
  PROC_ARGV=()
  [[ -r "/proc/$pid/cmdline" ]] || return 1
  while IFS= read -r -d '' arg; do PROC_ARGV+=("$arg"); done <"/proc/$pid/cmdline"
  ((${#PROC_ARGV[@]} > 0))
}

resolved_exe() {
  readlink -f "/proc/$1/exe" 2>/dev/null || true
}

proof_processes() {
  local targets_file="$runtime/target-executables.txt" pid exe
  : >"$targets_file"
  for name in herdr vim hq hq-worker hq-worker-proof-provider proof-sh hq-vim.test hq-vim-smoke; do
    readlink -f "$proof_root/bin/$name" >>"$targets_file"
  done
  sort -u -o "$targets_file" "$targets_file"
  for proc in /proc/[0-9]*; do
    pid=${proc##*/}
    exe=$(resolved_exe "$pid")
    [[ -n "$exe" ]] || continue
    if grep -Fxq "$exe" "$targets_file"; then
      if read_proc_argv "$pid"; then
        printf '%s\t' "$pid"
        printf '%q ' "${PROC_ARGV[@]}"
        printf '\n'
      fi
    fi
  done | sort -n
}

count_exact_worker() {
  local wanted pid exe count=0
  wanted=$(readlink -f "$proof_root/bin/hq-worker")
  for proc in /proc/[0-9]*; do
    pid=${proc##*/}
    exe=$(resolved_exe "$pid")
    [[ "$exe" == "$wanted" ]] || continue
    if read_proc_argv "$pid" && ((${#PROC_ARGV[@]} >= 2)) && [[ "${PROC_ARGV[1]}" == serve ]]; then
      count=$((count + 1))
    fi
  done
  printf '%s\n' "$count"
}

capture_vim_hq_binding() {
  local info=$1 out=$2 wanted_hq wanted_vim pid exe ppid pexe
  wanted_hq=$(readlink -f "$proof_root/bin/hq")
  wanted_vim=$(readlink -f "$proof_root/bin/vim")
  for proc in /proc/[0-9]*; do
    pid=${proc##*/}
    exe=$(resolved_exe "$pid")
    [[ "$exe" == "$wanted_hq" ]] || continue
    read_proc_argv "$pid" || continue
    ((${#PROC_ARGV[@]} == 4)) || continue
    [[ "${PROC_ARGV[1]}" == lsp && "${PROC_ARGV[2]}" == --profile && "${PROC_ARGV[3]}" == local ]] || continue
    ppid=$(awk '{print $4}' "/proc/$pid/stat" 2>/dev/null || true)
    [[ -n "$ppid" ]] || continue
    pexe=$(resolved_exe "$ppid")
    [[ "$pexe" == "$wanted_vim" ]] || continue
    grep -Eq "(^|[^0-9])(${pid}|${ppid})([^0-9]|$)" "$info" || continue
    jq -n \
      --arg schema 'edits.vimNixProof.processBinding/1' \
      --arg hq "$wanted_hq" --arg vim "$wanted_vim" \
      --argjson hqPid "$pid" --argjson vimPid "$ppid" \
      '{schema:$schema,status:"PASS",hq:{pid:$hqPid,executable:$hq,argv:["lsp","--profile","local"]},vim:{pid:$vimPid,executable:$vim}}' \
      >"$out"
    return 0
  done
  return 1
}

cleanup() {
  local status=$?
  if ((cleanup_started == 0)); then
    cleanup_started=1
    set +e
    if ((worker_started == 1)); then
      "$proof_root/bin/hq-worker" stop --profile local --profile-root "$profile_root" --timeout 20s \
        >"$output/cleanup-worker-stop.jsonl" 2>"$output/cleanup-worker-stop.stderr" || true
    fi
    if [[ -n "$workspace_id" ]]; then
      h workspace close "$workspace_id" >"$output/cleanup-workspace-close.json" 2>"$output/cleanup-workspace-close.stderr" || true
    fi
    "$proof_root/bin/herdr" session stop "$session" --json \
      >"$output/cleanup-session-stop.json" 2>"$output/cleanup-session-stop.stderr" || true
    if [[ -n "$server_pid" ]]; then
      for _ in $(seq 1 100); do
        kill -0 "$server_pid" 2>/dev/null || break
        sleep 0.05
      done
      kill "$server_pid" 2>/dev/null || true
      wait "$server_pid" 2>/dev/null || true
    fi
    proof_processes >"$output/processes-after-cleanup.txt" 2>&1 || true
    copy_runtime_diagnostics
  fi
  exit "$status"
}
trap cleanup EXIT INT TERM
