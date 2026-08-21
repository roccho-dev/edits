#!/usr/bin/env bash
set -euo pipefail
mkdir -p "$EVIDENCE/oci" "$RUNNER_TEMP/skopeo-runtime"
"$SKOPEO" --tmpdir "$RUNNER_TEMP/skopeo-runtime" copy --insecure-policy \
  "oci-archive:$DIST/vim-nix-herdr-hq.oci.tar" \
  "docker-daemon:$IMAGE_NAME:oci-$IMAGE_TAG" \
  | tee "$EVIDENCE/oci/skopeo-to-daemon.txt"
docker run --rm --network none --pids-limit 512 \
  --mount "type=bind,src=$EVIDENCE/oci,dst=/evidence" \
  "$IMAGE_NAME:oci-$IMAGE_TAG" --mode oci --output /evidence \
  | tee "$RUNNER_TEMP/oci-runner.stdout.txt"
install -m 0644 "$RUNNER_TEMP/oci-runner.stdout.txt" "$EVIDENCE/oci/outer.stdout.txt"
jq -e '.status=="PASS" and .mode=="oci"' "$EVIDENCE/oci/receipt.json" >/dev/null
