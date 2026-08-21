#!/usr/bin/env bash
set -euo pipefail

script_dir=$(CDPATH= cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
repo_root=$(CDPATH= cd -- "$script_dir/../.." && pwd)
proof_dir="$repo_root/proofs/vim-nix"
out=${LOCAL_PROOF_OUT:-"$repo_root/.local/vim-nix-proof"}
rm -rf "$out"; mkdir -p "$out"/{logs,evidence}
work=$(mktemp -d); trap 'rm -rf "$work"' EXIT

lock_sha=35cdda5fa9645ab469924c69f36992db2f8637360fce128e7c7fd372c3a4ce0f
test "$(sha256sum "$proof_dir/flake.lock" | cut -d' ' -f1)" = "$lock_sha"
for rev in 0ae2bc1419c3f345984c2629e72e7a631820fa4d 3118886f34ac5615e8a7732a6297bd41900e21e1 989016ae2ae4cbf304a9ca29478f47fec794493f 8aecd377f08e9fbdf0092478ab7ec3ce5e0f04ec; do
  grep -Fq "\"rev\": \"$rev\"" "$proof_dir/flake.lock"
done

printf '== static syntax ==\n' | tee "$out/logs/summary.txt"
bash -n "$script_dir/verify.sh" "$script_dir/herdr-proof.sh"
python3 -m py_compile "$script_dir/oci-proof.py" "$proof_dir/verify_oci.py"
cat "$proof_dir"/ci.parts/*.sh >"$work/ci.sh"; bash -n "$work/ci.sh"
cat "$proof_dir"/run-proof.parts/*.sh >"$work/run-proof.sh"; bash -n "$work/run-proof.sh"

printf '== exact test-only patch RED/GREEN ==\n' | tee -a "$out/logs/summary.txt"
mapfile -t paths < <(sed -n 's/^diff --git a\/\([^ ]*\) b\/.*/\1/p' "$proof_dir/hq-vim-native-popup-proof.patch")
test "${#paths[@]}" -eq 1 && test "${paths[0]}" = packages/hq-vim/internal/smoke/smoke.go
git -C "$repo_root" apply --check "$proof_dir/hq-vim-native-popup-proof.patch"
mkdir -p "$work"/{unpatched,patched}/packages
cp -a "$repo_root/packages/hq-vim" "$work/unpatched/packages/"
cp -a "$repo_root/packages/hq-vim" "$work/patched/packages/"
red=$(printf 'HQ_SMOKE_TTY_PROOF=1 go test ./internal/smoke -run TestNativePopupArtifactUsesControllingTTY -count=1 >%q 2>&1' "$out/logs/tty-red-go-test.log")
if (cd "$work/unpatched/packages/hq-vim" && timeout 30s script -qefc "$red" "$out/evidence/tty-red.typescript" >/dev/null); then
  echo 'unpatched TTY control unexpectedly passed' >&2; exit 1
fi
grep -Fq not-tty "$out/logs/tty-red-go-test.log"
(cd "$work/patched" && git apply "$proof_dir/hq-vim-native-popup-proof.patch")
gofmt -w "$work/patched/packages/hq-vim/internal/smoke/smoke.go"
grep -Fq 'os.OpenFile("/dev/tty", os.O_RDWR, 0)' "$work/patched/packages/hq-vim/internal/smoke/smoke.go"
grep -Fq "l:index + 1), 'nx')" "$work/patched/packages/hq-vim/internal/smoke/smoke.go"
(cd "$work/patched/packages/hq-vim" && go test ./... -count=1 | tee "$out/logs/go-test.log")
green=$(printf 'HQ_SMOKE_TTY_PROOF=1 go test ./internal/smoke -run TestNativePopupArtifactUsesControllingTTY -count=1 >%q 2>&1' "$out/logs/tty-green-go-test.log")
(cd "$work/patched/packages/hq-vim" && timeout 30s script -qefc "$green" "$out/evidence/tty-green.typescript" >/dev/null)
grep -Fq ok "$out/logs/tty-green-go-test.log"

printf '== real Vim feedkeys n/nx proof ==\n' | tee -a "$out/logs/summary.txt"
vim_bin=${VIM_BIN:-$(command -v vim)}
for mode in nx n; do
  artifact="$out/evidence/feedkeys-$mode.json"
  command=$(printf 'env HQ_FEEDKEYS_PROOF_OUT=%q HQ_FEEDKEYS_MODE=%q %q --clean -Nu NONE -n -S %q' "$artifact" "$mode" "$vim_bin" "$script_dir/feedkeys-race.vim")
  timeout 20s script -qefc "$command" "$out/evidence/feedkeys-$mode.typescript" >/dev/null
done
python3 - "$out/evidence/feedkeys-nx.json" "$out/evidence/feedkeys-n.json" <<'PY'
import json, sys
nx, n = (json.load(open(path)) for path in sys.argv[1:])
assert nx["status"] == "PASS" and nx["line"] == "alpha"
assert n["status"] == "PASS" and n["line"] == "wrong"
PY

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
  "schema": "edits.vimNixLocalFirstProof/1",
  "status": "PASS",
  "source": {"flakeLockSha256": lock_sha, "testOnlyPatchPath": "proofs/vim-nix/hq-vim-native-popup-proof.patch", "patchTouches": ["packages/hq-vim/internal/smoke/smoke.go"]},
  "localLowCostGates": {
    "shellSyntax": "PASS", "ociVerifierPythonSyntax": "PASS", "patchAppliesCleanly": "PASS",
    "unpatchedTTYControl": "RED_AS_EXPECTED", "patchedGoTests": "PASS",
    "childUsesControllingTTYWhenParentOutputIsRedirected": "PASS",
    "feedkeysNxConsumesObservedCompletionBeforeRecompute": "PASS", "feedkeysNControlExposesRace": "PASS",
    "ociVerifierPositiveFixture": "PASS", "ociVerifierMutationRejection": "PASS",
    "herdrTopologyProbe": herdr,
    "vimRuntimeObserved": subprocess.check_output([vim, "--version"], text=True).splitlines()[0],
  },
  "deferredHighCostGates": [
    "exact Nix output closure materialization", "normal/offline same-store-path rebuild with empty substituters",
    "exact Vim 9.2.0478 + exact yegappan/lsp + exact HQ integration replay",
    "fresh exact-product accepted/started/stdout/completed worker lifecycle",
    "Docker archive and OCI projection runtime semantic parity", "independent WSLC physical readback",
  ],
  "decision": {"exactClosureRequiredForLocalDeltaDevelopment": False, "exactClosureRequiredForFinalPackagingClaim": True, "pushPolicy": "push only after this local receipt is PASS"},
}
pathlib.Path(path).write_text(json.dumps(receipt, indent=2) + "\n", encoding="utf-8")
PY
printf 'VIM_NIX_LOCAL_FIRST_PROOF_PASS\n' | tee -a "$out/logs/summary.txt"
(cd "$out" && find . -type f ! -name SHA256SUMS -print0 | sort -z | xargs -0 sha256sum >SHA256SUMS && sha256sum --check SHA256SUMS)
