
# The previous part intentionally creates only a pre-final distribution receipt.
# From here on, no umbrella PASS exists until clean replay and all three full
# product surfaces agree.
if test -f "$ARTIFACT/ci-receipt.json"; then
  mv "$ARTIFACT/ci-receipt.json" "$ARTIFACT/distribution-precheck.json"
fi
rm -f "$ARTIFACT/SHA256SUMS"

printf '\n== Assert Docker and OCI executed the full editor + runtime proof ==\n'
for surface in docker oci; do
  evidence="$ARTIFACT/evidence-$surface"
  jq -e '.status == "PASS" and .gates.testCount == 8 and .gates.ptyTestCount == 4 and .gates.headlessTestCount == 4' \
    "$evidence/editor-receipt.json" >/dev/null
  jq -e '.status == "PASS" and .gates.paneCount == 2 and .gates.resultKinds == ["accepted","started","stdout","completed"] and .gates.residualProcessCount == 0' \
    "$evidence/receipt.json" >/dev/null
  grep -Fxq 'VIM_NIX_EDITOR_E2E_PASS' "$ARTIFACT/${surface}-runtime.transcript.txt" || true
  grep -Fxq 'VIM_NIX_RUNTIME_E2E_PASS' "$ARTIFACT/${surface}-runtime.transcript.txt"
  grep -Fxq 'VIM_NIX_FULL_E2E_PASS' "$ARTIFACT/${surface}-runtime.transcript.txt"
done

printf '\n== Execute the same complete proof on the host surface ==\n'
rm -rf "$ARTIFACT/evidence-host" "$RUNNER_TEMP/vim-nix-host-runtime"
mkdir -p "$ARTIFACT/evidence-host"
PROOF_ROOT="$PROOF" \
PROOF_OUTPUT_DIR="$ARTIFACT/evidence-host" \
PROOF_RUNTIME_DIR="$RUNNER_TEMP/vim-nix-host-runtime" \
PROOF_RUN_SUFFIX=host-final \
  "$RUNNER/bin/vim-nix-proof" all | tee "$ARTIFACT/host-runtime.transcript.txt"
grep -Fxq 'VIM_NIX_RUNTIME_E2E_PASS' "$ARTIFACT/host-runtime.transcript.txt"
grep -Fxq 'VIM_NIX_FULL_E2E_PASS' "$ARTIFACT/host-runtime.transcript.txt"
jq -e '.status == "PASS" and .gates.testCount == 8' "$ARTIFACT/evidence-host/editor-receipt.json" >/dev/null
jq -e '.status == "PASS" and .gates.residualProcessCount == 0' "$ARTIFACT/evidence-host/receipt.json" >/dev/null
(cd "$ARTIFACT/evidence-host" && sha256sum --check SHA256SUMS)

printf '\n== Compare Host / Docker / OCI semantic receipts ==\n'
for surface in host docker oci; do
  evidence="$ARTIFACT/evidence-$surface"
  jq -S '{status,source,runtime,gates}' "$evidence/editor-receipt.json" > "$ARTIFACT/${surface}-editor-semantic.json"
  jq -S '{status,source,input,runtime,gates,capture,limitations}' "$evidence/receipt.json" > "$ARTIFACT/${surface}-runtime-semantic.json"
  jq -n \
    --slurpfile editor "$ARTIFACT/${surface}-editor-semantic.json" \
    --slurpfile runtime "$ARTIFACT/${surface}-runtime-semantic.json" \
    '{editor:$editor[0],runtime:$runtime[0]}' > "$ARTIFACT/${surface}-full-semantic.json"
done
cmp "$ARTIFACT/host-full-semantic.json" "$ARTIFACT/docker-full-semantic.json"
cmp "$ARTIFACT/host-full-semantic.json" "$ARTIFACT/oci-full-semantic.json"
printf 'PASS\n' > "$ARTIFACT/host-docker-oci-semantic-parity.txt"

printf '\n== Clean offline replay in an independent chrooted Nix store ==\n'
# Hosted runners deny the bind mounts required by a nested Nix sandbox. Instead,
# place the independent store under a trusted parent, import the exact build
# prerequisites plus the Nix CLI runtime, and make that store the entire chroot.
# The outer chroot hides the host store; the outer network namespace removes all
# network routes. Nix's inner sandbox is therefore intentionally unnecessary.
CLEAN_ROOT="$HOME/.vim-nix-clean-store-${GITHUB_RUN_ID:-manual}"
CLEAN_STORE="local?root=$CLEAN_ROOT"
PREREQ_CACHE="$ARTIFACT/nix-build-prerequisite-cache"
NIX_BIN="$(readlink -f "$(command -v nix)")"
NIX_PACKAGE="$(dirname "$(dirname "$NIX_BIN")")"
rm -rf "$CLEAN_ROOT" "$PREREQ_CACHE"
mkdir -p "$CLEAN_ROOT" "$PREREQ_CACHE"
printf '%s\n' "$NIX_PACKAGE" > "$ARTIFACT/product/nix-tool-store-path.txt"

pushd proofs/vim-nix >/dev/null
drv="$(nix path-info --derivation .#default)"
popd >/dev/null
printf '%s\n' "$drv" > "$ARTIFACT/product/default-derivation.txt"

# Include the top-level derivation, every realised build prerequisite, and only
# the Nix runtime needed to operate the independent store. Exclude the final
# product output itself.
{
  printf '%s\n' "$drv" "$NIX_PACKAGE"
  nix-store --query --requisites --include-outputs "$drv"
  nix-store --query --requisites "$NIX_PACKAGE"
} | sort -u | grep -vxF "$PROOF" > "$ARTIFACT/product/build-prerequisites.txt"
grep -Fxq "$drv" "$ARTIFACT/product/build-prerequisites.txt"
grep -Fxq "$NIX_PACKAGE" "$ARTIFACT/product/build-prerequisites.txt"
! grep -Fxq "$PROOF" "$ARTIFACT/product/build-prerequisites.txt"
mapfile -t prereqs < "$ARTIFACT/product/build-prerequisites.txt"
test "${#prereqs[@]}" -gt 0

nix copy --to "file://$PREREQ_CACHE" "${prereqs[@]}"

if nix path-info --store "$CLEAN_STORE" "$PROOF" >/dev/null 2>&1; then
  echo 'clean store unexpectedly contains the final product before import' >&2
  exit 1
fi
STRICT_CURRENT_PHASE="clean-store-import"
nix copy --no-check-sigs --from "file://$PREREQ_CACHE" --to "$CLEAN_STORE" "${prereqs[@]}"
nix path-info --store "$CLEAN_STORE" "$drv" > "$ARTIFACT/product/clean-top-level-derivation.txt"
test "$(cat "$ARTIFACT/product/clean-top-level-derivation.txt")" = "$drv"
nix path-info --store "$CLEAN_STORE" "$NIX_PACKAGE" > "$ARTIFACT/product/clean-nix-tool-path.txt"
test "$(cat "$ARTIFACT/product/clean-nix-tool-path.txt")" = "$NIX_PACKAGE"
if nix path-info --store "$CLEAN_STORE" "$PROOF" >/dev/null 2>&1; then
  echo 'prerequisite import unexpectedly materialised the final product' >&2
  exit 1
fi
printf 'ABSENT\n' > "$ARTIFACT/product/clean-final-before-build.txt"

# Supply only the operating-system nodes needed by the Nix CLI and builders.
sudo install -d -m 0755 "$CLEAN_ROOT/etc" "$CLEAN_ROOT/dev" "$CLEAN_ROOT/root"
sudo install -d -m 1777 "$CLEAN_ROOT/tmp"
printf 'root:x:0:0:root:/root:/bin/sh\n' | sudo tee "$CLEAN_ROOT/etc/passwd" >/dev/null
printf 'root:x:0:\n' | sudo tee "$CLEAN_ROOT/etc/group" >/dev/null
sudo rm -f "$CLEAN_ROOT/dev/null" "$CLEAN_ROOT/dev/zero" "$CLEAN_ROOT/dev/random" "$CLEAN_ROOT/dev/urandom"
sudo mknod -m 0666 "$CLEAN_ROOT/dev/null" c 1 3
sudo mknod -m 0666 "$CLEAN_ROOT/dev/zero" c 1 5
sudo mknod -m 0444 "$CLEAN_ROOT/dev/random" c 1 8
sudo mknod -m 0444 "$CLEAN_ROOT/dev/urandom" c 1 9

# The Nix executable below is the copy inside CLEAN_ROOT because chroot changes
# the meaning of /nix. No host /nix/store path is addressable from the process.
STRICT_CURRENT_PHASE="clean-offline-build"
sudo unshare --net -- ip -brief addr > "$ARTIFACT/product/clean-network-namespace.txt"
sudo --preserve-env=PATH unshare --net -- \
  chroot "$CLEAN_ROOT" \
  "$NIX_PACKAGE/bin/nix" build \
    --extra-experimental-features 'nix-command flakes' \
    --store local \
    --offline \
    --option substituters '' \
    --option sandbox false \
    --no-link \
    "$drv^*" \
    > "$ARTIFACT/product/clean-offline-build.stdout" \
    2> "$ARTIFACT/product/clean-offline-build.stderr"

nix path-info --store "$CLEAN_STORE" "$PROOF" > "$ARTIFACT/product/clean-product-path.txt"
test "$(cat "$ARTIFACT/product/clean-product-path.txt")" = "$PROOF"
printf '%s\n' "$PROOF" > "$ARTIFACT/product/normal-product-path.txt"

nix path-info -r "$PROOF" | sort > "$ARTIFACT/product/normal-runtime-closure.txt"
nix path-info --store "$CLEAN_STORE" -r "$PROOF" | sort > "$ARTIFACT/product/clean-runtime-closure.txt"
cmp "$ARTIFACT/product/normal-runtime-closure.txt" "$ARTIFACT/product/clean-runtime-closure.txt"

normal_nar="$(nix hash path "$PROOF")"
clean_physical="$CLEAN_ROOT$PROOF"
test -e "$clean_physical"
clean_nar="$(nix hash path "$clean_physical")"
test "$normal_nar" = "$clean_nar"
printf '%s\n' "$normal_nar" > "$ARTIFACT/product/normal-product-nar-hash.txt"
printf '%s\n' "$clean_nar" > "$ARTIFACT/product/clean-product-nar-hash.txt"

jq -n \
  --arg product "$PROOF" \
  --arg drv "$drv" \
  --arg nar "$normal_nar" \
  --arg nixTool "$NIX_PACKAGE" \
  --arg prereqCache "nix-build-prerequisite-cache" '{
    schema:"edits.vim-nix-clean-offline-replay/2",
    status:"PASS",
    productStorePath:$product,
    derivation:$drv,
    nixToolStorePath:$nixTool,
    topLevelDerivationImported:true,
    finalOutputAbsentBeforeBuild:true,
    separateStore:true,
    hostStoreVisible:false,
    outerFilesystemIsolation:"chroot",
    networkNamespace:"isolated",
    nixSandbox:false,
    nixSandboxReason:"hosted-runner-denies-nested-bind-mounts; outer chroot hides host store",
    substituters:"empty",
    offline:true,
    noWriteLockFile:true,
    sameStorePath:true,
    sameRuntimeClosure:true,
    sameNarHash:true,
    prerequisiteImportSignaturePolicy:"local-cache-no-check-sigs",
    prerequisiteIntegrity:"narHash-verified-by-nix-copy",
    narHash:$nar,
    prerequisiteCache:$prereqCache
  }' > "$ARTIFACT/clean-offline-replay.receipt.json"

printf '\n== Final Linux distribution closure receipt ==\n'
jq -n \
  --arg proofCommit "$GITHUB_SHA" \
  --arg productSource "bfdac8df95ec435ed8aad7042fa1fc9bc1082f6a" \
  --arg product "$PROOF" \
  --arg dockerSha "$(sha256sum "$ARTIFACT/vim-nix-herdr-hq.docker.tar" | cut -d' ' -f1)" \
  --arg ociSha "$(sha256sum "$ARTIFACT/vim-nix-herdr-hq.oci.tar" | cut -d' ' -f1)" \
  --arg manifest "$(jq -r '.manifest.digest' "$ARTIFACT/oci-verification.json")" \
  --arg config "$(jq -r '.config.digest' "$ARTIFACT/oci-verification.json")" '{
    schema:"edits.vim-nix-distribution-closure/2",
    status:"DISTRIBUTION_CLOSURE_PASS",
    proofCommit:$proofCommit,
    productSource:$productSource,
    productStorePath:$product,
    gates:{
      normalNixMaterialization:"PASS",
      cleanOfflineReplay:"PASS",
      hostEditor8:"PASS",
      hostRuntimeLifecycle:"PASS",
      dockerEditor8:"PASS",
      dockerRuntimeLifecycle:"PASS",
      ociIntegrity:"PASS",
      ociEditor8:"PASS",
      ociRuntimeLifecycle:"PASS",
      hostDockerOciSemanticParity:"PASS",
      ociOneByteMutationRejection:"PASS"
    },
    dockerArchiveSha256:("sha256:"+$dockerSha),
    ociArchiveSha256:("sha256:"+$ociSha),
    ociManifestDigest:$manifest,
    ociConfigDigest:$config,
    physicalWindowsWslc:"OPEN",
    issue74Complete:false
  }' > "$ARTIFACT/ci-receipt.json"

find "$ARTIFACT" -type f ! -name SHA256SUMS -print0 | sort -z | xargs -0 sha256sum > "$ARTIFACT/SHA256SUMS"
(cd "$ARTIFACT" && sha256sum --check SHA256SUMS)
printf 'VIM_NIX_DISTRIBUTION_CLOSURE_PASS\n'
