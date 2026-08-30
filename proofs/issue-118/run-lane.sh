#!/usr/bin/env bash
set -euo pipefail
mode=${1:?usage: run-lane.sh --expect-red|--expect-green lane-dir [result-file]}
lane=${2:?usage: run-lane.sh --expect-red|--expect-green lane-dir [result-file]}
result=${3:-}
args=("$lane" "$mode")
if [[ -n "$result" ]]; then
  args+=(--result "$result")
fi
export PYTHONDONTWRITEBYTECODE=1
exec python3 "$(dirname "$0")/canon_runner.py" "${args[@]}"
