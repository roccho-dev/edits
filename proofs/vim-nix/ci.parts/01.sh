  echo 'mutated OCI unexpectedly passed' >&2
  exit 1
fi
printf 'PASS: one-byte OCI blob mutation rejected\n' > "$ARTIFACT/negative/oci-mutation.txt"

printf '\n== Execute the complete proof from the OCI projection ==\n'
"$SKOPEO/bin/skopeo" copy --insecure-policy \
  "oci-archive:$ARTIFACT/vim-nix-herdr-hq.oci.tar" \
  "docker-daemon:$OCI_IMAGE_REF"
docker image inspect "$OCI_IMAGE_REF" > "$ARTIFACT/oci-loaded-image-inspect.json"
docker run --rm --name vim-nix-proof-oci \
  --volume "$ARTIFACT/evidence-oci:/work/evidence" \
  "$OCI_IMAGE_REF" all | tee "$ARTIFACT/oci-runtime.transcript.txt"
grep -Fxq 'VIM_NIX_RUNTIME_E2E_PASS' "$ARTIFACT/oci-runtime.transcript.txt"
jq -e '.status == "PASS"' "$ARTIFACT/evidence-oci/receipt.json" >/dev/null
(cd "$ARTIFACT/evidence-oci" && sha256sum --check SHA256SUMS)

jq -S '{status,source,input,runtime,gates,capture,limitations}' "$ARTIFACT/evidence-docker/receipt.json" > "$ARTIFACT/docker-semantic.json"
jq -S '{status,source,input,runtime,gates,capture,limitations}' "$ARTIFACT/evidence-oci/receipt.json" > "$ARTIFACT/oci-semantic.json"
cmp "$ARTIFACT/docker-semantic.json" "$ARTIFACT/oci-semantic.json"
printf 'PASS\n' > "$ARTIFACT/docker-oci-semantic-parity.txt"

printf '\n== Assemble source, WSLC handoff, and exact Git bundle ==\n'
cp proofs/vim-nix/WSLC-TEST.md "$ARTIFACT/WSLC-TEST.md"
cp proofs/vim-nix/verify_oci.py "$ARTIFACT/source/verify_oci.py"
git bundle create "$ARTIFACT/source/edits-vim-nix-herdr-oci.git.bundle" HEAD
python3 - <<'PY'
import pathlib, zipfile
root = pathlib.Path('.')
out = pathlib.Path(__import__('os').environ['ARTIFACT']) / 'source' / 'edits-vim-nix-herdr-oci.source.zip'
paths = [pathlib.Path('proofs/vim-nix'), pathlib.Path('.github/workflows/proof-vim-nix-oci.yml')]
with zipfile.ZipFile(out, 'w', compression=zipfile.ZIP_DEFLATED, compresslevel=9) as z:
    for path in paths:
        if path.is_dir():
            for f in sorted(path.rglob('*')):
                if f.is_file(): z.write(f, f.as_posix())
        else:
            z.write(path, path.as_posix())
PY
git diff --exit-code
git status --porcelain=v1 > "$ARTIFACT/source/git-status.txt"
test ! -s "$ARTIFACT/source/git-status.txt"

printf '\n== Create closure receipt and SHA manifest ==\n'
jq -n \
  --arg workflowCommit "$GITHUB_SHA" \
  --arg product "$PROOF" \
  --arg dockerSha "$(sha256sum "$ARTIFACT/vim-nix-herdr-hq.docker.tar" | cut -d' ' -f1)" \
  --arg ociSha "$(sha256sum "$ARTIFACT/vim-nix-herdr-hq.oci.tar" | cut -d' ' -f1)" \
  --arg manifest "$(jq -r '.manifest.digest' "$ARTIFACT/oci-verification.json")" \
  --arg config "$(jq -r '.config.digest' "$ARTIFACT/oci-verification.json")" '{
    schema:"edits.vim-nix-herdr-oci-ci-proof/1",
    status:"PASS",
    workflowCommit:$workflowCommit,
    sourceCommit:$workflowCommit,
    productStorePath:$product,
    dockerArchiveSha256:("sha256:"+$dockerSha),
    ociArchiveSha256:("sha256:"+$ociSha),
    ociManifestDigest:$manifest,
    ociConfigDigest:$config,
    dockerRuntime:"PASS",
    ociRuntime:"PASS",
    semanticParity:"PASS",
    mutationRejection:"PASS",
    wslcProjection:"Docker-compatible archive; physical WSLC readback pending user receipt"
  }' > "$ARTIFACT/ci-receipt.json"

find "$ARTIFACT" -type f ! -name SHA256SUMS -print0 | sort -z | xargs -0 sha256sum > "$ARTIFACT/SHA256SUMS"
(cd "$ARTIFACT" && sha256sum --check SHA256SUMS)
du -sh "$ARTIFACT"

