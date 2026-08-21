#!/usr/bin/env bash
set -euo pipefail
mkdir -p "$EVIDENCE/docker"
docker load --input "$DIST/vim-nix-herdr-hq.docker.tar" | tee "$EVIDENCE/docker/load.txt"
docker run --rm --network none --pids-limit 512 \
  --mount "type=bind,src=$EVIDENCE/docker,dst=/evidence" \
  "$IMAGE_NAME:$IMAGE_TAG" --mode docker --output /evidence \
  | tee "$RUNNER_TEMP/docker-runner.stdout.txt"
install -m 0644 "$RUNNER_TEMP/docker-runner.stdout.txt" "$EVIDENCE/docker/outer.stdout.txt"
jq -e '.status=="PASS" and .mode=="docker"' "$EVIDENCE/docker/receipt.json" >/dev/null
