# Persist the exact failing command for strict proof-only diagnosis.
# This does not alter product inputs, outputs, or gate semantics.
strict_failure_report() {
  local rc="$1"
  local line="$2"
  local command="$3"
  trap - ERR
  printf 'STRICT_FAILURE rc=%s line=%s command=%q\n' "$rc" "$line" "$command" >&2
  if test -n "${ARTIFACT:-}"; then
    mkdir -p "$ARTIFACT"
    jq -n \
      --argjson exitCode "$rc" \
      --argjson line "$line" \
      --arg command "$command" \
      '{schema:"edits.v25-strict-failure/1",exitCode:$exitCode,line:$line,command:$command}' \
      > "$ARTIFACT/strict-failure.json" || true
    if test -s "$ARTIFACT/product/clean-offline-build.stderr"; then
      tail -c 65536 "$ARTIFACT/product/clean-offline-build.stderr" \
        > "$ARTIFACT/strict-failure.stderr.tail.txt" || true
      cat "$ARTIFACT/strict-failure.stderr.tail.txt" >&2 || true
    fi
  fi
  exit "$rc"
}
trap 'strict_failure_report "$?" "$LINENO" "$BASH_COMMAND"' ERR
