#!/usr/bin/env bash
set -euo pipefail
evidence="$RUNNER_TEMP/evidence"
mkdir -p "$evidence/host" "$evidence/closure" "$RUNNER_TEMP/dist"
lock_before="$(sha256sum flake.lock | cut -d' ' -f1)"

proof="$(nix build --no-link --print-out-paths --no-write-lock-file .#default)"
test -d "$proof"
offline="$(nix build --offline --no-link --print-out-paths --no-write-lock-file .#default)"
test "$offline" = "$proof"
test "$(sha256sum flake.lock | cut -d' ' -f1)" = "$lock_before"
git diff --exit-code -- flake.lock

nix-store --query --requisites "$proof" | sort -u > "$evidence/closure/runtime-paths.txt"
nix path-info -rSh "$proof" > "$evidence/closure/runtime-path-info.txt"
nix path-info --json "$proof" > "$evidence/closure/output-path.json"
du -sb "$proof" > "$evidence/closure/output-bytes.txt"
closure_bytes="$(nix path-info -S "$proof" | awk 'END {print $2}')"
printf '%s\n' "$closure_bytes" > "$evidence/closure/recursive-closure-bytes.txt"
test "$closure_bytes" -gt 0

forbidden='-(gtk[0-9+.-]*|libx11-[^/]*|xorg-server-[^/]*|python[0-9.-]*|ruby-[0-9][^/]*|lua[0-9.-]*)$'
if sed 's#^.*/##' "$evidence/closure/runtime-paths.txt" | grep -Eiq -- "$forbidden"; then
  echo 'forbidden GUI/language runtime dependency found:' >&2
  sed 's#^.*/##' "$evidence/closure/runtime-paths.txt" | grep -Ei -- "$forbidden" >&2
  exit 1
fi

"$proof/bin/run-vim-nix-proof" \
  --proof-root "$proof" \
  --output "$evidence/host" \
  --mode host | tee "$RUNNER_TEMP/host-runner.stdout.txt"
install -m 0644 "$RUNNER_TEMP/host-runner.stdout.txt" "$evidence/host/outer.stdout.txt"

printf '%s\n' "$proof" > "$evidence/closure/final-output-path.txt"
printf '%s\n' "$offline" > "$evidence/closure/offline-output-path.txt"
echo "proof=$proof" >> "$GITHUB_OUTPUT"
echo "closure_bytes=$closure_bytes" >> "$GITHUB_OUTPUT"
echo "evidence=$evidence" >> "$GITHUB_OUTPUT"
echo "dist=$RUNNER_TEMP/dist" >> "$GITHUB_OUTPUT"
