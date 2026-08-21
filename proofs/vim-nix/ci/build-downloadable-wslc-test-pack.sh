#!/usr/bin/env bash
set -euo pipefail
source_commit="$(git rev-parse HEAD)"
packroot="$RUNNER_TEMP/packroot"
release="$RUNNER_TEMP/release"
mkdir -p "$packroot/evidence" "$release"
cp -a "$EVIDENCE"/. "$packroot/evidence/"
cp "$DIST/vim-nix-herdr-hq.docker.tar" "$packroot/"
cp "$DIST/vim-nix-herdr-hq.oci.tar" "$packroot/"
cp "$DIST/manifest.raw.json" "$DIST/inspect.json" "$DIST/image.ref" "$packroot/"

cat > "$packroot/WSLC-TEST.ps1" <<'PS1'
param(
  [string]$PackRoot = $PSScriptRoot,
  [string]$Wslc = 'C:\Program Files\WSL\wslc.exe',
  [string]$EvidenceDir = (Join-Path $PSScriptRoot 'wslc-evidence')
)
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
$PackRoot = [IO.Path]::GetFullPath($PackRoot)
$EvidenceDir = [IO.Path]::GetFullPath($EvidenceDir)
if (-not (Test-Path -LiteralPath $Wslc -PathType Leaf)) { throw "wslc not found: $Wslc" }
$docker = Join-Path $PackRoot 'vim-nix-herdr-hq.docker.tar'
$sums = Join-Path $PackRoot 'SHA256SUMS'
foreach ($path in @($docker, $sums)) { if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { throw "missing pack file: $path" } }
foreach ($line in Get-Content -LiteralPath $sums -Encoding ascii) {
  if ($line -notmatch '^([0-9a-f]{64})  (.+)$') { throw "invalid SHA256SUMS row: $line" }
  $path = Join-Path $PackRoot $Matches[2]
  if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { throw "missing checksum target: $path" }
  if ((Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash.ToLowerInvariant() -cne $Matches[1]) { throw "digest mismatch: $path" }
}
New-Item -ItemType Directory -Path $EvidenceDir -Force | Out-Null
& $Wslc version
if ($LASTEXITCODE -ne 0) { throw 'wslc version failed' }
& $Wslc image load --input $docker
if ($LASTEXITCODE -ne 0) { throw 'wslc image load failed' }
& $Wslc run --rm --network none -v "${EvidenceDir}:/evidence" vim-nix-herdr-hq:d83bf4c4860e --mode wslc --output /evidence
if ($LASTEXITCODE -ne 0) { throw 'WSLC runtime proof failed' }
$receiptPath = Join-Path $EvidenceDir 'receipt.json'
$receipt = Get-Content -LiteralPath $receiptPath -Raw | ConvertFrom-Json
if ($receipt.status -cne 'PASS' -or $receipt.mode -cne 'wslc' -or $receipt.semanticSha256 -cne '__SEMANTIC_SHA__') {
  throw 'WSLC receipt does not match the CI semantic identity'
}
Copy-Item -LiteralPath $receiptPath -Destination (Join-Path $EvidenceDir 'wslc-runtime.receipt.json') -Force
Write-Output "WSLC PASS semantic_sha256=$($receipt.semanticSha256) evidence=$EvidenceDir"
PS1
sed -i "s/__SEMANTIC_SHA__/$SEMANTIC_SHA/g" "$packroot/WSLC-TEST.ps1"

cat > "$packroot/WSLC-TEST.md" <<EOF_MD
# WSLC independent runtime test

## Required host

- Windows 11 x64
- WSL 2.9.3 or newer with \`wslc.exe\`
- one consistent elevation context for all commands
- at least 4 GiB available memory recommended for this proof workload

## Why the Docker archive is loaded

The pack contains both projections of the same Nix-built image:

- \`vim-nix-herdr-hq.docker.tar\`: WSLC runtime input
- \`vim-nix-herdr-hq.oci.tar\`: independently structure-verified and executed in CI through Skopeo

Current WSLC preview accepts Docker-compatible archives through \`wslc image load --input\`; direct OCI image-layout archive loading is not assumed. The two paths are bound by the same image config and CI semantic Receipt.

## Execute

Open PowerShell in the extracted pack directory:

\`\`\`powershell
Set-ExecutionPolicy -Scope Process Bypass
.\\WSLC-TEST.ps1
\`\`\`

The script verifies every file in \`SHA256SUMS\`, loads the Docker-compatible archive, runs the full Herdr/Vim/HQ/worker proof inside WSLC, and requires:

\`\`\`text
semanticSha256=$SEMANTIC_SHA
\`\`\`

Return the generated \`wslc-evidence\` directory or its ZIP for any failure or for final host acceptance.

## CI-bound identity

- exact edits base: \`$EXACT_BASE\`
- proof source commit: \`$source_commit\`
- Actions run request commit: \`$GITHUB_SHA\` (transport metadata only when rerunning an older run)
- recursive Nix closure bytes: \`$CLOSURE_BYTES\`
- semantic Receipt SHA-256: \`$SEMANTIC_SHA\`
- OCI manifest digest: \`$MANIFEST_DIGEST\`
- OCI config digest: \`$CONFIG_DIGEST\`
- handoff ZIP SHA-256: \`$HANDOFF_SHA256\`
EOF_MD

git archive --format=zip --output "$packroot/vim-nix-herdr-hq.source.zip" "$source_commit" \
  .github/workflows/proof-vim-nix-herdr-oci.yml proofs/vim-nix
(cd "$packroot/evidence" && zip -qr -0 ../vim-nix-herdr-hq.ci-evidence.zip .)
rm -rf "$packroot/evidence"

jq -n \
  --arg schema 'edits.vimNixHerdrHq.releaseManifest/1' \
  --arg sourceCommit "$source_commit" --arg actionsRequestCommit "$GITHUB_SHA" --arg exactBase "$EXACT_BASE" \
  --arg handoffSha256 "$HANDOFF_SHA256" --arg semanticSha256 "$SEMANTIC_SHA" \
  --arg manifestDigest "$MANIFEST_DIGEST" --arg configDigest "$CONFIG_DIGEST" \
  --arg image "$IMAGE_NAME:$IMAGE_TAG" --argjson closureBytes "$CLOSURE_BYTES" \
  '{schema:$schema,status:"PASS",sourceCommit:$sourceCommit,actionsRequestCommit:$actionsRequestCommit,exactBase:$exactBase,handoffSha256:$handoffSha256,image:$image,closureBytes:$closureBytes,semanticSha256:$semanticSha256,oci:{manifestDigest:$manifestDigest,configDigest:$configDigest},runtimeProofs:["host","docker","oci"],wslcStatus:"READY_FOR_INDEPENDENT_TEST",finalGitBundlesIncluded:false}' \
  > "$packroot/manifest.json"

(cd "$packroot" && find . -maxdepth 1 -type f ! -name SHA256SUMS -printf '%f\0' | sort -z | xargs -0 sha256sum > SHA256SUMS)
(cd "$packroot" && sha256sum --check SHA256SUMS)
pack="$RUNNER_TEMP/vim-nix-herdr-hq-wslc-test-pack-${source_commit:0:12}.zip"
(cd "$packroot" && zip -qr -0 "$pack" .)
pack_name="$(basename "$pack")"
pack_sha="$(sha256sum "$pack" | cut -d' ' -f1)"

install -m 0644 "$pack" "$release/$pack_name"
printf '%s  %s\n' "$pack_sha" "$pack_name" > "$release/$pack_name.sha256"
install -m 0644 "$packroot/manifest.json" "$release/manifest.json"
install -m 0644 "$packroot/WSLC-TEST.md" "$release/WSLC-TEST.md"
install -m 0644 "$packroot/WSLC-TEST.ps1" "$release/WSLC-TEST.ps1"
(cd "$release" && find . -maxdepth 1 -type f ! -name SHA256SUMS -printf '%f\0' | sort -z | xargs - sha256sum > SHA256SUMS)
