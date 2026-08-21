# Start a fresh named Herdr server and create one workspace/root pane.
h config check >"$output/herdr-config-check.stdout" 2>"$output/herdr-config-check.stderr"
h server >"$output/herdr-server.stdout" 2>"$output/herdr-server.stderr" &
server_pid=$!
ready=0
for _ in $(seq 1 300); do
  if h api snapshot >"$output/herdr-api-snapshot.initial.json" 2>"$output/herdr-api-snapshot.initial.stderr"; then
    ready=1
    break
  fi
  kill -0 "$server_pid" 2>/dev/null || break
  sleep 0.1
done
if ((ready != 1)); then
  set +e
  server_state=running
  server_exit=not-observed
  if ! kill -0 "$server_pid" 2>/dev/null; then
    wait "$server_pid"
    server_exit=$?
    server_state=exited
    server_pid=""
  fi
  set -e
  {
    echo 'Herdr server did not become ready'
    printf 'state=%s exit=%s\n' "$server_state" "$server_exit"
    printf 'session=%s\n' "$session"
    printf 'HOME=%s\nXDG_CONFIG_HOME=%s\nXDG_RUNTIME_DIR=%s\nHERDR_CONFIG_PATH=%s\nSHELL=%s\n' \
      "$HOME" "$XDG_CONFIG_HOME" "$XDG_RUNTIME_DIR" "$HERDR_CONFIG_PATH" "$SHELL"
    echo '--- config check stdout ---'
    cat "$output/herdr-config-check.stdout" 2>/dev/null || true
    echo '--- config check stderr ---'
    cat "$output/herdr-config-check.stderr" 2>/dev/null || true
    echo '--- server stdout ---'
    cat "$output/herdr-server.stdout" 2>/dev/null || true
    echo '--- server stderr ---'
    cat "$output/herdr-server.stderr" 2>/dev/null || true
    echo '--- initial API stderr ---'
    cat "$output/herdr-api-snapshot.initial.stderr" 2>/dev/null || true
    echo '--- session files ---'
    find "$config" -maxdepth 6 -printf '%M %s %p\n' 2>/dev/null | sort || true
  } >&2
  exit 1
fi

h workspace create --cwd "$workspace" --label vim-nix-proof --focus >"$output/herdr-workspace-create.json"
workspace_id=$(jq -er '.result.workspace.workspace_id' "$output/herdr-workspace-create.json")
root_pane=$(jq -er '.result.root_pane.pane_id' "$output/herdr-workspace-create.json")

# Run all three real native-popup journeys inside the Herdr-owned PTY. Keep the
# authoritative Go output in a file and poll pane readback for one exact marker;
# the Herdr 0.8.0 wait-output path is not used as completion authority.
cat >"$runtime/run-popup.sh" <<EOF_POPUP
#!/bin/sh
set +e
cd "$proof_root/share/hq-vim" || exit 97
HQ_NATIVE_HQ_FUZZY_PROOF=1 \
HQ_BIN="$proof_root/bin/hq" \
VIM_EXE="$proof_root/bin/vim" \
VIM9_LSP_PATH="$proof_root/share/yegappan-lsp" \
HOME="$HOME" \
XDG_CONFIG_HOME="$XDG_CONFIG_HOME" \
XDG_RUNTIME_DIR="$XDG_RUNTIME_DIR" \
XDG_STATE_HOME="$XDG_STATE_HOME" \
XDG_CACHE_HOME="$XDG_CACHE_HOME" \
LANG=C.UTF-8 LC_ALL=C.UTF-8 TERM=xterm-256color \
"$proof_root/bin/hq-vim.test" -test.v -test.count=1 -test.run '^TestNativeHQFuzzyAutomaticPopupDoesNotAccept\$' \
  > "$output/native-popup.log" 2>&1
code=\$?
cat "$output/native-popup.log"
printf '__VIM_NIX_POPUP_EXIT_%s__\\n' "\$code"
exit 0
EOF_POPUP
chmod 700 "$runtime/run-popup.sh"
h pane run "$root_pane" "$runtime/run-popup.sh" >"$output/herdr-popup-run.json"

process_bound=0
popup_done=0
: >"$output/popup-process-samples.txt"
for _ in $(seq 1 900); do
  h pane process-info --pane "$root_pane" >"$output/process-info.latest.json" 2>/dev/null || true
  {
    printf '\n=== sample %s ===\n' "$(date -u +%Y-%m-%dT%H:%M:%S.%NZ)"
    cat "$output/process-info.latest.json" 2>/dev/null || true
    ps -eo pid=,ppid=,args= | grep -F "$proof_root/bin/" | grep -v grep || true
  } >>"$output/popup-process-samples.txt"
  if capture_vim_hq_binding "$output/process-info.latest.json" "$output/process-binding.json"; then
    process_bound=1
  fi
  h pane read "$root_pane" --source recent-unwrapped --lines 500 \
    >"$output/herdr-popup-pane.txt" 2>"$output/herdr-popup-pane.stderr" || true
  if grep -Fxq '__VIM_NIX_POPUP_EXIT_0__' "$output/herdr-popup-pane.txt"; then
    popup_done=1
    break
  fi
  if grep -E '^__VIM_NIX_POPUP_EXIT_[1-9][0-9]*__$' "$output/herdr-popup-pane.txt" >/dev/null 2>&1; then
    cat "$output/herdr-popup-pane.txt" >&2
    echo 'native popup proof failed' >&2
    exit 1
  fi
  sleep 0.1
done
if ((popup_done != 1)); then
  echo 'native popup proof timed out' >&2
  cat "$output/herdr-popup-pane.txt" >&2 || true
  cat "$output/native-popup.log" >&2 || true
  exit 1
fi
((process_bound == 1)) || { echo 'exact Vim -> HQ lsp process binding was not observed' >&2; exit 1; }
cp "$output/process-info.latest.json" "$output/process-info.popup.json"

grep -Fxq PASS "$output/native-popup.log" || { echo 'native popup test did not end in PASS' >&2; exit 1; }
for name in fuzzy_schema_template field_key unicode_CRLF_field_value; do
  grep -E -- "--- PASS: TestNativeHQFuzzyAutomaticPopupDoesNotAccept/$name" "$output/native-popup.log" >/dev/null \
    || { echo "missing popup subtest PASS: $name" >&2; exit 1; }
done

# Exactly one split: one workspace, exactly two panes.
h pane split "$root_pane" --direction right --ratio 0.5 --cwd "$workspace" --no-focus >"$output/herdr-pane-split.json"
task_pane=$(jq -er '.result.pane.pane_id' "$output/herdr-pane-split.json")
h pane list --workspace "$workspace_id" >"$output/herdr-pane-list.json"
mapfile -t observed_panes < <(jq -r --arg ws "$workspace_id" \
  '.. | objects | select((.pane_id? | type) == "string") | select((.workspace_id? // $ws) == $ws) | .pane_id' \
  "$output/herdr-pane-list.json" | sort -u)
((${#observed_panes[@]} == 2)) || { printf 'expected two panes, got: %s\n' "${observed_panes[*]}" >&2; exit 1; }
printf '%s\n' "${observed_panes[@]}" | grep -Fxq "$root_pane"
printf '%s\n' "${observed_panes[@]}" | grep -Fxq "$task_pane"
h pane focus --direction right --pane "$root_pane" >"$output/herdr-focus-right.json"
h pane focus --direction left --pane "$task_pane" >"$output/herdr-focus-left.json"
h pane layout --pane "$root_pane" >"$output/herdr-layout.json"
h pane read "$root_pane" --source visible >"$output/herdr-root-visible.txt"
[[ -s "$output/herdr-root-visible.txt" ]]
