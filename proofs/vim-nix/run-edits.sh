# shellcheck shell=bash
set -Eeuo pipefail
umask 077

fail() {
  printf 'edits: %s\n' "$*" >&2
  exit 1
}

case "$#" in
  0) workspace_input=$PWD ;;
  1) workspace_input=$1 ;;
  *) fail 'usage: edits [workspace-directory]' ;;
esac

test -t 0 && test -t 1 || fail 'stdin and stdout must be attached to a PTY'
test -d "$workspace_input" || fail "workspace is not a directory: $workspace_input"
workspace="$(cd -- "$workspace_input" && pwd -P)"

HERDR=/bin/edits-mux
VIM=/bin/edits-client
HQ=/bin/edits-service
HQ_VIM=/share/hq-vim
VIM9_LSP=/share/yegappan-lsp
VIMRUNTIME=/share/vim/vim92
PROFILE=local
DEFAULT_WORLD=/share/edits/default-world.jsonl

for binding in "$HERDR" "$VIM" "$HQ"; do
  test -x "$binding" || fail "missing executable image binding: $binding"
done
test -d "$HQ_VIM" || fail "missing image binding: $HQ_VIM"
test -d "$VIM9_LSP" || fail "missing image binding: $VIM9_LSP"
test -d "$VIMRUNTIME" || fail "missing image binding: $VIMRUNTIME"
test -s "$DEFAULT_WORLD" || fail "missing image binding: $DEFAULT_WORLD"

: "${HOME:=/home/dev}"
: "${XDG_CONFIG_HOME:=$HOME/.config}"
: "${XDG_STATE_HOME:=$HOME/.local/state}"
: "${XDG_CACHE_HOME:=$HOME/.cache}"
: "${HERDR_CONFIG_PATH:=/share/proof/herdr.toml}"
export HOME XDG_CONFIG_HOME XDG_STATE_HOME XDG_CACHE_HOME HERDR_CONFIG_PATH VIMRUNTIME
export SHELL=/bin/sh TERM="${TERM:-xterm-256color}" LANG=C.UTF-8 LC_ALL=C.UTF-8 PATH=/bin

test -d "$HOME" && test -w "$HOME" || fail "HOME must be an existing writable directory: $HOME"
profile_path="$XDG_CONFIG_HOME/roccho/hq/profiles/$PROFILE.json"
test -s "$HERDR_CONFIG_PATH" || fail "Herdr config is missing or empty: $HERDR_CONFIG_PATH"
runtime_parent="${XDG_RUNTIME_DIR:-/tmp}"
mkdir -p "$runtime_parent"
test -d "$runtime_parent" && test -w "$runtime_parent" \
  || fail "runtime parent must be a writable directory: $runtime_parent"
runtime="$(mktemp -d "$runtime_parent/edits.XXXXXXXX")"
export XDG_RUNTIME_DIR="$runtime/xdg-runtime"
mkdir -p "$XDG_RUNTIME_DIR"
chmod 700 "$XDG_RUNTIME_DIR"

install_if_absent() {
  local source=$1
  local target=$2
  local target_dir
  local temporary
  target_dir="$(dirname "$target")"
  mkdir -p "$target_dir"
  if test -e "$target"; then
    test -f "$target" && test -s "$target" \
      || fail "durable file exists but is not a non-empty regular file: $target"
    return
  fi
  temporary="$(mktemp "$target_dir/.edits-new.XXXXXXXX")"
  cp "$source" "$temporary"
  chmod 600 "$temporary"
  ln "$temporary" "$target" 2>/dev/null || true
  rm -f "$temporary"
  test -f "$target" && test -s "$target" \
    || fail "could not create durable state without overwriting: $target"
}

create_empty_if_absent() {
  local target=$1
  local target_dir
  local temporary
  target_dir="$(dirname "$target")"
  mkdir -p "$target_dir"
  if test -e "$target"; then
    test -f "$target" || fail "durable path is not a regular file: $target"
    return
  fi
  temporary="$(mktemp "$target_dir/.edits-new.XXXXXXXX")"
  ln "$temporary" "$target" 2>/dev/null || true
  rm -f "$temporary"
  test -f "$target" || fail "could not create durable state without overwriting: $target"
}

if test ! -e "$profile_path"; then
  config_root="$XDG_CONFIG_HOME/roccho/hq/config/$PROFILE"
  state_root="$XDG_STATE_HOME/roccho/hq/$PROFILE"
  workspace_key="$(printf '%s' "$workspace" | sha256sum | cut -c1-16)"
  world_path="$config_root/world.jsonl"
  capabilities_path="$config_root/capabilities.json"
  accepted_path="$state_root/accepted.jsonl"
  events_path="$state_root/workspaces/$workspace_key/events.jsonl"
  install_if_absent "$DEFAULT_WORLD" "$world_path"
  capabilities_source="$runtime/capabilities.json"
  printf '{}\n' > "$capabilities_source"
  install_if_absent "$capabilities_source" "$capabilities_path"
  rm -f "$capabilities_source"
  create_empty_if_absent "$accepted_path"
  create_empty_if_absent "$events_path"
  mkdir -p "$(dirname "$profile_path")"
  profile_source="$runtime/profile.json"
  jq -n \
    --arg world "$world_path" --arg accepted "$accepted_path" --arg workspace "$workspace" \
    --arg events "$events_path" --arg capabilities "$capabilities_path" '{
      kind:"hq.profile.v1",name:"local",deployment_id:"edits-local",
      world_path:$world,accepted_path:$accepted,workspace_root:$workspace,
      events_path:$events,capabilities_path:$capabilities,
      poll_interval_ms:50,health_timeout_ms:2000
    }' > "$profile_source"
  install_if_absent "$profile_source" "$profile_path"
  rm -f "$profile_source"
fi

test -s "$profile_path" || fail "HQ profile is missing or empty: $profile_path"
profile_workspace="$(jq -er 'select(.kind == "hq.profile.v1" and .name == "local") | .workspace_root | strings' \
  "$profile_path")" || fail "HQ profile is not a valid local profile: $profile_path"
test -d "$profile_workspace" || fail "HQ profile workspace root is not a directory: $profile_workspace"
profile_workspace="$(cd -- "$profile_workspace" && pwd -P)"
if test "$profile_workspace" != /; then
  case "$workspace" in
    "$profile_workspace"|"$profile_workspace"/*) ;;
    *) fail "workspace is outside the local HQ profile root: $profile_workspace" ;;
  esac
fi

session="edits-$$"
vimrc="$runtime/vimrc"
draft="$runtime/draft.hqjson"
run_vim="$runtime/run-vim.sh"
herdr_pid=
workspace_id=
root_pane_id=
server_started=0

# shellcheck disable=SC2329
cleanup() {
  local status=$?
  set +e
  if test -n "$workspace_id"; then
    "$HERDR" --session "$session" workspace close "$workspace_id" \
      > "$runtime/workspace-close.json" 2> "$runtime/workspace-close.stderr" || true
    workspace_id=
  fi
  if test "$server_started" -eq 1; then
    "$HERDR" --session "$session" server stop \
      > "$runtime/herdr-stop.txt" 2> "$runtime/herdr-stop.stderr" || true
  fi
  if test -n "$herdr_pid"; then
    for _ in $(seq 1 100); do
      kill -0 "$herdr_pid" 2>/dev/null || break
      if test "$(awk '{ print $3 }' "/proc/$herdr_pid/stat" 2>/dev/null)" = Z; then
        wait "$herdr_pid" 2>/dev/null || true
        herdr_pid=
        break
      fi
      sleep 0.1
    done
    if test -n "$herdr_pid" && kill -0 "$herdr_pid" 2>/dev/null; then
      printf 'edits: Herdr server did not stop within 10 seconds\n' >&2
      test "$status" -ne 0 || status=1
    elif test -n "$herdr_pid"; then
      wait "$herdr_pid" 2>/dev/null || true
    fi
  fi
  return "$status"
}

# shellcheck disable=SC2329
on_signal() {
  exit 130
}

trap cleanup EXIT
trap on_signal HUP INT TERM

cat > "$vimrc" <<'EOF_VIMRC'
set nocompatible
set nomodeline
set noswapfile
set encoding=utf-8
set completeopt=menuone,noinsert,noselect,popup
set nomore
set runtimepath^=/share/yegappan-lsp
set runtimepath^=/share/hq-vim
let g:edits_service_bin = '/bin/edits-service'
let g:edits_profile = 'local'
let g:hq_bin = '/bin/edits-service'
let g:hq_profile = 'local'
EOF_VIMRC
: > "$draft"
cat > "$run_vim" <<EOF_RUN_VIM
#!/bin/sh
exec /bin/edits-client -Nu "$vimrc" -n -i NONE \
  "+set filetype=hqjson" "+HqStart" "$draft"
EOF_RUN_VIM
chmod 700 "$run_vim"

"$HERDR" --session "$session" server \
  > "$runtime/herdr-server.stdout" 2> "$runtime/herdr-server.stderr" &
herdr_pid=$!
server_started=1

server_ready=0
for _ in $(seq 1 200); do
  if "$HERDR" --session "$session" status server \
      > "$runtime/herdr-status.txt" 2> "$runtime/herdr-status.stderr"; then
    if grep -Eq '^status:[[:space:]]+running$|"status"[[:space:]]*:[[:space:]]*"running"' \
        "$runtime/herdr-status.txt"; then
      server_ready=1
      break
    fi
  fi
  kill -0 "$herdr_pid" 2>/dev/null || break
  sleep 0.1
done
test "$server_ready" -eq 1 || fail 'Herdr server did not become ready'

workspace_json="$("$HERDR" --session "$session" workspace create \
  --cwd "$workspace" --label edits \
  --env "HOME=$HOME" \
  --env "XDG_CONFIG_HOME=$XDG_CONFIG_HOME" \
  --env "XDG_RUNTIME_DIR=$XDG_RUNTIME_DIR" \
  --env "XDG_STATE_HOME=$XDG_STATE_HOME" \
  --env "XDG_CACHE_HOME=$XDG_CACHE_HOME" \
  --env "HERDR_CONFIG_PATH=$HERDR_CONFIG_PATH" \
  --env "VIMRUNTIME=$VIMRUNTIME" \
  --env "SHELL=$SHELL" --env "TERM=$TERM" --env "LANG=$LANG" --env "LC_ALL=$LC_ALL")"
printf '%s\n' "$workspace_json" > "$runtime/workspace-create.json"
workspace_id="$(printf '%s' "$workspace_json" | jq -er '.result.workspace.workspace_id')"
root_pane_id="$(printf '%s' "$workspace_json" | jq -er '.result.root_pane.pane_id')"

root_shell_ready=0
for _ in $(seq 1 200); do
  if "$HERDR" --session "$session" pane process-info --pane "$root_pane_id" \
      > "$runtime/root-pane-ready.json" 2> "$runtime/root-pane-ready.stderr"; then
    if jq -e '.result.process_info.foreground_processes | any(.argv == ["/bin/sh"])' \
        "$runtime/root-pane-ready.json" >/dev/null; then
      root_shell_ready=1
      break
    fi
  fi
  kill -0 "$herdr_pid" 2>/dev/null || break
  sleep 0.1
done
test "$root_shell_ready" -eq 1 || fail 'Herdr root pane shell did not become ready'

"$HERDR" --session "$session" pane run "$root_pane_id" "$run_vim" \
  > "$runtime/vim-pane-run.json" 2> "$runtime/vim-pane-run.stderr"

printf 'edits: session=%s workspace=%s pane=%s\n' \
  "$session" "$workspace_id" "$root_pane_id" >&2

attach_stderr="$runtime/herdr-attach.stderr"
set +e
"$HERDR" --session "$session" 2> "$attach_stderr"
attach_status=$?
set -e
printf '\n' >&2
cat "$attach_stderr" >&2

orderly_shutdown_marker='herdr: server shut down: server is shutting down'
normalized_attach_error="$(tr -d '\r' < "$attach_stderr")"
if test "$attach_status" -ne 0 && test "$normalized_attach_error" != "$orderly_shutdown_marker"; then
  exit "$attach_status"
fi
exit 0
