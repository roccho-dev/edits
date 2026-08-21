#!/usr/bin/env bash
set -euxo pipefail

git merge-base --is-ancestor "$EXACT_BASE" HEAD
test "$(git rev-list --count "$EXACT_BASE"..HEAD)" -eq 1
mapfile -t changed < <(git diff --name-only "$EXACT_BASE"..HEAD | sort)
expected=(
  '.github/workflows/proof-vim-nix-herdr-oci.yml'
  'proofs/vim-nix/ci/build-docker-archive-and-oci-projection.sh'
  'proofs/vim-nix/ci/build-downloadable-wslc-test-pack.sh'
  'proofs/vim-nix/ci/build-exact-closure-and-replay-offline.sh'
  'proofs/vim-nix/ci/compare-host-docker-and-oci-semantic-receipts.sh'
  'proofs/vim-nix/ci/execute-complete-proof-from-docker-archive.sh'
  'proofs/vim-nix/ci/execute-complete-proof-from-oci-projection.sh'
  'proofs/vim-nix/ci/fail-closed-on-source-drift.sh'
  'proofs/vim-nix/ci/publish-exact-tag-prerelease-and-independently-read-it-back.sh'
  'proofs/vim-nix/ci/return-proof-result-to-issue-74.sh'
  'proofs/vim-nix/ci/verify-oci-structure-and-destructive-cases.sh'
  'proofs/vim-nix/flake.lock'
  'proofs/vim-nix/flake.nix'
  'proofs/vim-nix/hq-vim-native-popup-proof.patch'
  'proofs/vim-nix/run-proof/00-bootstrap.sh'
  'proofs/vim-nix/run-proof/10-static.sh'
  'proofs/vim-nix/run-proof/20-pty.sh'
  'proofs/vim-nix/run-proof/30-worker.sh'
  'proofs/vim-nix/run-proof/40-finish.sh'
  'proofs/vim-nix/run-proof.sh'
)
printf '%s\n' "${changed[@]}" | tee "$RUNNER_TEMP/changed-paths.txt"
test "${#changed[@]}" -eq "${#expected[@]}"
cmp <(printf '%s\n' "${expected[@]}" | sort) <(printf '%s\n' "${changed[@]}")
test "$(sha256sum "$PROOF_DIR/flake.lock" | cut -d' ' -f1)" = \
  '35cdda5fa9645ab469924c69f36992db2f8637360fce128e7c7fd372c3a4ce0f'
test "$(sha256sum "$PROOF_DIR/hq-vim-native-popup-proof.patch" | cut -d' ' -f1)" = \
  '19a091affec1f1d80530be75397f191eee630bade57fd1431b2e23b0986518a5'
git diff --exit-code
