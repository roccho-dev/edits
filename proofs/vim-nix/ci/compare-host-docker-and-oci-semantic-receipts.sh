#!/usr/bin/env bash
set -euo pipefail
host="$(jq -er .semanticSha256 "$EVIDENCE/host/receipt.json")"
docker="$(jq -er .semanticSha256 "$EVIDENCE/docker/receipt.json")"
oci="$(jq -er .semanticSha256 "$EVIDENCE/oci/receipt.json")"
test "$host" = "$docker"
test "$host" = "$oci"
jq -n --arg sha "$host" \
  --slurpfile host "$EVIDENCE/host/receipt.json" \
  --slurpfile docker "$EVIDENCE/docker/receipt.json" \
  --slurpfile oci "$EVIDENCE/oci/receipt.json" \
  '{schema:"edits.vimNixHerdrHq.parity/1",status:"PASS",semanticSha256:$sha,modes:{host:$host[0].mode,docker:$docker[0].mode,oci:$oci[0].mode}}' \
  > "$EVIDENCE/parity.json"
echo "semantic_sha=$host" >> "$GITHUB_OUTPUT"
