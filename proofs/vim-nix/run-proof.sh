#!/usr/bin/env bash
set -euo pipefail

: "${PROOF_SOURCE_DIR:?PROOF_SOURCE_DIR is required}"
for phase in   00-bootstrap.sh   10-static.sh   20-pty.sh   30-worker.sh   40-finish.sh; do
  # shellcheck source=/dev/null
  source "$PROOF_SOURCE_DIR/$phase"
done
