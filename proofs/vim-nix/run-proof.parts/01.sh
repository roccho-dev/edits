# Fresh isolated Herdr server and PTY workspace.
"$HERDR" --session "$SESSION" server > "$OUT/herdr-server.stdout" 2> "$OUT/herdr-server.stderr" &
HERDR_PID=$!
wait_for_server || fail "Herdr server did not become ready"

workspace_json="$("$HERDR" --session "$SESSION" workspace create \
  --cwd "$RUNTIME" --label vim-nix-proof \
  --env "HOME=$HOME" \
  --env "XDG_CONFIG_HOME=$XDG_CONFIG_HOME" \
  --env "XDG_RUNTIME_DIR=$XDG_RUNTIME_DIR" \
  --env "XDG_STATE_HOME=$XDG_STATE_HOME" \
  --env "XDG_CACHE_HOME=$XDG_CACHE_HOME" \
  --env "HERDR_CONFIG_PATH=$HERDR_CONFIG_PATH" \
  --env "SHELL=$SHELL" --env "TERM=$TERM" --env "LANG=$LANG" --env "LC_ALL=$LC_ALL" \
  --no-focus)"
printf '%s\n' "$workspace_json" > "$OUT/workspace-create.json"
WORKSPACE_ID="$(printf '%s' "$workspace_json" | jq -er '.result.workspace.workspace_id')"
PROVEN_WORKSPACE_ID="$WORKSPACE_ID"
ROOT_PANE_ID="$(printf '%s' "$workspace_json" | jq -er '.result.root_pane.pane_id')"

# Popup choice E2E is independent from this runtime lifecycle proof.

# Split exactly one task pane, then prove topology/focus/read/process evidence.
split_json="$("$HERDR" --session "$SESSION" pane split "$ROOT_PANE_ID" \
  --direction right --ratio 0.5 --cwd "$RUNTIME" --no-focus)"
printf '%s\n' "$split_json" > "$OUT/pane-split.json"
TASK_PANE_ID="$(printf '%s' "$split_json" | jq -er '.result.pane.pane_id')"
"$HERDR" --session "$SESSION" pane list --workspace "$WORKSPACE_ID" > "$OUT/pane-list.json"
pane_count="$(jq '[.result.panes[]?] | length // [.result[]?] | length' "$OUT/pane-list.json" 2>/dev/null || true)"
if test "$pane_count" != 2; then
  pane_count="$(jq '[.. | objects | select(has("pane_id")) | .pane_id] | unique | length' "$OUT/pane-list.json")"
fi
test "$pane_count" -eq 2 || fail "expected exactly two panes, got $pane_count"
"$HERDR" --session "$SESSION" pane layout --pane "$ROOT_PANE_ID" > "$OUT/pane-layout.json"
"$HERDR" --session "$SESSION" pane focus --direction right --pane "$ROOT_PANE_ID" > "$OUT/focus-right.json"
"$HERDR" --session "$SESSION" pane focus --direction left --pane "$TASK_PANE_ID" > "$OUT/focus-left.json"
pane_read "$ROOT_PANE_ID" "$OUT/root-pane-read.txt"
pane_read "$TASK_PANE_ID" "$OUT/task-pane-read.txt"
"$HERDR" --session "$SESSION" pane process-info --pane "$ROOT_PANE_ID" > "$OUT/root-pane-process.json"
