  HQ_CANONICAL_BIN="$PROOF/bin/hq" \
  HQ_CANONICAL_SOURCE_SHA=3118886f34ac5615e8a7732a6297bd41900e21e1 \
  HQ_CONFORMANCE_ARTIFACT="$OUT/canonical-conformance.json" \
  VIM_EXE="$PROOF/bin/vim" \
  VIM9_LSP_PATH="$PROOF/share/yegappan-lsp" \
  "$PROOF/bin/hq-vim.test" \
    -test.v -test.count=1 \
    -test.run '^TestCanonicalHQVimConformance$'
) > "$OUT/canonical-conformance.log" 2>&1

grep -Fxq PASS "$OUT/canonical-conformance.log" || fail "canonical conformance did not end in PASS"
test -s "$OUT/canonical-conformance.json" || fail "canonical conformance artifact missing"

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

cat > "$RUNTIME/run-popup.sh" <<EOF_POPUP
#!/bin/sh
set +e
cd "$PROOF/share/hq-vim" || exit 97
HQ_NATIVE_HQ_FUZZY_PROOF=1 \
HQ_BIN="$PROOF/bin/hq" \
VIM_EXE="$PROOF/bin/vim" \
VIM9_LSP_PATH="$PROOF/share/yegappan-lsp" \
HOME="$HOME" \
XDG_CONFIG_HOME="$XDG_CONFIG_HOME" \
XDG_RUNTIME_DIR="$XDG_RUNTIME_DIR" \
XDG_STATE_HOME="$XDG_STATE_HOME" \
XDG_CACHE_HOME="$XDG_CACHE_HOME" \
LANG=C.UTF-8 LC_ALL=C.UTF-8 TERM=xterm-256color \
"$PROOF/bin/hq-vim.test" -test.v -test.count=1 -test.run '^TestNativeHQFuzzyAutomaticPopupDoesNotAccept\$' \
  > "$OUT/native-popup.log" 2>&1
code=\$?
cat "$OUT/native-popup.log"
printf '__VIM_NIX_POPUP_EXIT_%s__\\n' "\$code"
exit 0
EOF_POPUP
chmod 700 "$RUNTIME/run-popup.sh"

"$HERDR" --session "$SESSION" pane run "$ROOT_PANE_ID" "$RUNTIME/run-popup.sh" \
  > "$OUT/popup-pane-run.json" 2> "$OUT/popup-pane-run.stderr"

process_seen=0
: > "$OUT/popup-process-samples.txt"
for _ in $(seq 1 900); do
  {
    printf '\n=== sample %s ===\n' "$(date -u +%Y-%m-%dT%H:%M:%S.%NZ)"
    "$HERDR" --session "$SESSION" pane process-info --pane "$ROOT_PANE_ID" 2>&1 || true
    ps -eo pid=,ppid=,args= | grep -F "$PROOF/bin/" | grep -v grep || true
  } >> "$OUT/popup-process-samples.txt"
  if grep -F "$PROOF/bin/hq lsp --profile local" "$OUT/popup-process-samples.txt" >/dev/null 2>&1; then
    process_seen=1
  fi
  pane_read "$ROOT_PANE_ID" "$OUT/popup-pane-recent.txt"
  if grep -Fxq '__VIM_NIX_POPUP_EXIT_0__' "$OUT/popup-pane-recent.txt"; then
    break
  fi
  if grep -E '^__VIM_NIX_POPUP_EXIT_[1-9][0-9]*__$' "$OUT/popup-pane-recent.txt" >/dev/null 2>&1; then
    cat "$OUT/popup-pane-recent.txt" >&2
    fail "native popup proof failed"
  fi
  sleep 0.1
done
wait_for_pane_marker "$ROOT_PANE_ID" '__VIM_NIX_POPUP_EXIT_0__' "$OUT/popup-pane-recent.txt" 20 \
  || fail "native popup proof timed out"
grep -Fxq PASS "$OUT/native-popup.log" || fail "native popup test did not end in PASS"
for subtest in 'AI_agent_is_the_first_command' 'AI_agent_prompt_field' 'explicit_direct_command_with_Unicode_CRLF'; do
  grep -E -- "--- PASS: TestNativeHQFuzzyAutomaticPopupDoesNotAccept/$subtest" "$OUT/native-popup.log" >/dev/null \
    || fail "missing popup subtest PASS: $subtest"
done
test "$process_seen" -eq 1 || fail "process evidence did not bind Vim to exact HQ lsp --profile local"

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
