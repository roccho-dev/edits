#!/usr/bin/env bash
set -euo pipefail

script_dir=$(CDPATH= cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
repo_root=$(CDPATH= cd -- "$script_dir/../.." && pwd)
proof_dir="$repo_root/proofs/vim-nix"
out=${LOCAL_PROOF_OUT:-"$repo_root/.local/vim-nix-proof"}
rm -rf "$out"; mkdir -p "$out"/{logs,evidence}
work=$(mktemp -d); trap 'rm -rf "$work"' EXIT
vim_bin=${VIM_BIN:-$(command -v vim)}

lock_sha=$(sha256sum "$proof_dir/flake.lock" | cut -d' ' -f1)
printf '== static syntax ==\n' | tee "$out/logs/summary.txt"
bash -n "$script_dir/verify.sh" "$script_dir/herdr-proof.sh" "$proof_dir/capture-pty-e2e.sh"
python3 -m py_compile "$script_dir/oci-proof.py" "$proof_dir/verify_oci.py"
cat "$proof_dir"/ci.parts/*.sh >"$work/ci.sh"; bash -n "$work/ci.sh"
cat "$proof_dir"/run-proof.parts/*.sh >"$work/run-proof.sh"; bash -n "$work/run-proof.sh"
for removed in \
  packages/hq-vim/autoload/hq_completion.vim \
  packages/hq-vim/docs/manual-completion.md \
  packages/hq-vim/manual_history_completion_test.go \
  packages/hq-vim/canonical_conformance_test.go \
  packages/hq-vim/internal/smoke/tty_test.go \
  proofs/vim-nix/hq-vim-native-popup-proof.patch; do
  test ! -e "$repo_root/$removed"
done
mapfile -t actual_tests < <(
  grep -Rh '^func Test' "$repo_root/packages/hq-vim" --include='*_test.go' \
    | sed -E 's/^func (Test[^ (]+).*/\1/' \
    | sort
)
expected_tests=(
  TestAcceptedSubmitKeepsDraftOnUnsafeConsumption
  TestAgentDecisionSubmitE2E
  TestAgentDefaultChoiceE2E
  TestAgentPromptFieldChoiceE2E
  TestDirectCommandSubmitE2E
  TestDirectFallbackChoiceE2E
  TestEditorSurfaceAndBindingFailClosed
  TestUnicodeDirectFieldValueE2E
)
test "${actual_tests[*]}" = "${expected_tests[*]}" || {
  printf 'focused behavior tests differ\nexpected: %s\nactual:   %s\n' \
    "${expected_tests[*]}" "${actual_tests[*]}" >&2
  exit 1
}
for fixture in "$proof_dir/fixtures/runtime-world.jsonl" "$proof_dir/fixtures/runtime-accepted.jsonl"; do
  test -s "$fixture"
  while IFS= read -r row; do test -z "$row" || jq -e . >/dev/null <<<"$row"; done < "$fixture"
done
test "$(grep -cve '^[[:space:]]*$' "$proof_dir/fixtures/runtime-accepted.jsonl")" -eq 1

printf '== behavior tests ==\n' | tee -a "$out/logs/summary.txt"
(
  cd "$repo_root/packages/hq-vim"
  go test ./... -count=1 | tee "$out/logs/go-test.log"
)

printf '== OCI positive/mutation proof ==\n' | tee -a "$out/logs/summary.txt"
python3 "$script_dir/oci-proof.py" "$proof_dir/verify_oci.py" "$work" "$out"

printf '== optional Herdr topology ==\n' | tee -a "$out/logs/summary.txt"
herdr_status=SKIP_NOT_REQUIRED_FOR_DELTA
if test -n "${HERDR_BIN:-}"; then
  "$script_dir/herdr-proof.sh" "$HERDR_BIN" "$repo_root" "$out" "$work"
  herdr_status=PASS_TWO_PANES_CLEAN_STOP
else
  printf 'SKIP: HERDR_BIN not supplied\n' >"$out/evidence/herdr.version.txt"
fi

python3 - "$out/receipt.json" "$lock_sha" "$vim_bin" "$herdr_status" <<'PY'
import json, pathlib, subprocess, sys
path, lock_sha, vim, herdr = sys.argv[1:]
receipt = {
  "schema": "edits.vimNixLocalFirstProof/2",
  "status": "PASS",
  "source": {
    "flakeLockSha256": lock_sha,
    "screenshotHarness": "proofs/vim-nix/capture-pty-e2e.sh",
    "runtimeInput": "proofs/vim-nix/fixtures/runtime-accepted.jsonl",
  },
  "localLowCostGates": {
    "shellSyntax": "PASS",
    "ociVerifierPythonSyntax": "PASS",
    "goTests": "PASS",
    "editorCommandSurface": "START_SUBMIT_DOCTOR_ONLY",
    "focusedBehaviorE2Es": [
      "TestEditorSurfaceAndBindingFailClosed",
      "TestAgentDefaultChoiceE2E",
      "TestAgentPromptFieldChoiceE2E",
      "TestDirectFallbackChoiceE2E",
      "TestUnicodeDirectFieldValueE2E",
      "TestAgentDecisionSubmitE2E",
      "TestDirectCommandSubmitE2E",
      "TestAcceptedSubmitKeepsDraftOnUnsafeConsumption",
    ],
    "e2eComposition": False,
    "exactRuntimeE2Es": "RUN_BY_SCREENSHOT_OR_EXACT_RUNTIME_LANE",
    "screenshotHarness": "OBSERVATION_ONLY",
    "runtimeLifecycleUsesEditorE2E": False,
    "ociVerifierPositiveFixture": "PASS",
    "ociVerifierMutationRejection": "PASS",
    "herdrTopologyProbe": herdr,
    "vimRuntimeObserved": subprocess.check_output([vim, "--version"], text=True).splitlines()[0],
  },
  "deferredDistributionGates": [
    "exact Nix output closure materialization",
    "normal/offline same-store-path rebuild with empty substituters",
    "Docker archive and OCI projection runtime semantic parity",
    "independent WSLC physical readback",
  ],
  "decision": {
    "exactClosureRequiredForLocalDeltaDevelopment": False,
    "exactClosureRequiredForFinalPackagingClaim": True,
    "pushPolicy": "push only after this local receipt is PASS",
  },
}
pathlib.Path(path).write_text(json.dumps(receipt, indent=2) + "\n", encoding="utf-8")
PY
printf 'VIM_NIX_LOCAL_FIRST_PROOF_PASS\n' | tee -a "$out/logs/summary.txt"
(cd "$out" && find . -type f ! -name SHA256SUMS -print0 | sort -z | xargs -0 sha256sum >SHA256SUMS && sha256sum --check SHA256SUMS)
