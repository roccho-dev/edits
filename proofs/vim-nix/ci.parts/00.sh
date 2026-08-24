#!/usr/bin/env bash
set -euo pipefail

cd "${GITHUB_WORKSPACE:?}"

printf '\n== Prepare artifact root ==\n'
rm -rf "$ARTIFACT"
mkdir -p "$ARTIFACT"/{product,evidence-docker,evidence-oci,source,negative}
printf '%s\n' "$GITHUB_SHA" > "$ARTIFACT/workflow-commit.txt"

printf '\n== Build exact minimal product and warm-store diagnostic ==\n'
pushd proofs/vim-nix >/dev/null
lock_before=$(sha256sum flake.lock | cut -d' ' -f1)
proof=$(nix build --no-link --print-out-paths .#default)
proof_offline=$(nix build --offline --no-write-lock-file --no-link --print-out-paths .#default)
lock_after=$(sha256sum flake.lock | cut -d' ' -f1)
test "$lock_before" = "$lock_after"
test "$proof" = "$proof_offline"
test "$proof" = "$(readlink -f "$proof")"
PROOF="$proof"
printf '%s\n' "$proof" > "$ARTIFACT/product/store-path.txt"
printf '%s\n' "$lock_before" > "$ARTIFACT/product/flake-lock.sha256"

source_manifest="$proof/share/proof/source.json"
test -s "$source_manifest"
product_source=$(jq -er '.editsRevision' "$source_manifest")
test "$product_source" = 'bfdac8df95ec435ed8aad7042fa1fc9bc1082f6a'
product_tag=${product_source:0:12}
IMAGE_REF="roccho/vim-nix-herdr-hq-proof:$product_tag"
OCI_IMAGE_REF="roccho/vim-nix-herdr-hq-proof:oci-$product_tag"
printf '%s\n' "$product_source" > "$ARTIFACT/product/product-source.txt"
printf '%s\n' "$IMAGE_REF" > "$ARTIFACT/product/image-ref.txt"
printf '%s\n' "$OCI_IMAGE_REF" > "$ARTIFACT/product/oci-image-ref.txt"

nix-store -qR "$proof" | sort > "$ARTIFACT/product/closure-paths.txt"
nix path-info -rS "$proof" > "$ARTIFACT/product/closure-size.txt"
nix path-info -r --json "$proof" > "$ARTIFACT/product/closure.json"
if grep -Eai '/nix/store/[0-9a-z]+-[^/]*(gtk|libx11|xorg|python|ruby|lua)([-0-9.]|$)' \
    "$ARTIFACT/product/closure-paths.txt"; then
  echo 'forbidden GUI/language runtime entered the minimal closure' >&2
  exit 1
fi

"$proof/bin/herdr" --version | tee "$ARTIFACT/product/herdr.version.txt"
"$proof/bin/vim" --version | sed -n '1,12p' | tee "$ARTIFACT/product/vim.version.txt"
"$proof/bin/vim" -Nu NONE -n -i NONE -es \
  '+if v:version != 902 || !has("patch-9.2.478") || !has("terminal") || has("gui_running") | cquit 42 | endif' \
  '+quitall!'
test -f "$proof/bin/proof-sh"
test ! -L "$proof/bin/proof-sh"
find "$proof/bin" -maxdepth 1 \( -type f -o -type l \) -print0 | sort -z | while IFS= read -r -d '' entry; do
  resolved=$(readlink -f "$entry")
  printf '%s\t%s\n' "$(basename "$entry")" "$resolved"
  sha256sum "$resolved"
done > "$ARTIFACT/product/binaries-and-sha256.txt"

printf '\n== Build Docker-compatible archive and pinned Skopeo ==\n'
image=$(nix build --no-link --print-out-paths .#image)
skopeo=$(nix build --no-link --print-out-paths .#skopeo)
runner=$(nix build --no-link --print-out-paths .#runner)
IMAGE="$image"
SKOPEO="$skopeo"
RUNNER="$runner"
if gzip -t "$image" >/dev/null 2>&1; then
  gzip -dc "$image" > "$ARTIFACT/vim-nix-herdr-hq.docker.tar"
else
  cp -L "$image" "$ARTIFACT/vim-nix-herdr-hq.docker.tar"
fi
file "$ARTIFACT/vim-nix-herdr-hq.docker.tar" | tee "$ARTIFACT/product/docker-archive.file.txt"
tar -tf "$ARTIFACT/vim-nix-herdr-hq.docker.tar" > "$ARTIFACT/product/docker-archive.members.txt"
popd >/dev/null

printf '\n== Execute editor 8 + runtime lifecycle from Docker archive ==\n'
docker image load --input "$ARTIFACT/vim-nix-herdr-hq.docker.tar" | tee "$ARTIFACT/docker-load.txt"
docker image inspect "$IMAGE_REF" > "$ARTIFACT/docker-image-inspect.json"
test "$(jq -r '.[0].Os + "/" + .[0].Architecture' "$ARTIFACT/docker-image-inspect.json")" = 'linux/amd64'
docker run --rm --name vim-nix-proof-docker \
  --volume "$ARTIFACT/evidence-docker:/work/evidence" \
  "$IMAGE_REF" all | tee "$ARTIFACT/docker-runtime.transcript.txt"
grep -Fxq 'VIM_NIX_RUNTIME_E2E_PASS' "$ARTIFACT/docker-runtime.transcript.txt"
grep -Fxq 'VIM_NIX_FULL_E2E_PASS' "$ARTIFACT/docker-runtime.transcript.txt"
jq -e '.status == "PASS" and .gates.testCount == 8' "$ARTIFACT/evidence-docker/editor-receipt.json" >/dev/null
jq -e '.status == "PASS" and .gates.residualProcessCount == 0' "$ARTIFACT/evidence-docker/receipt.json" >/dev/null
(cd "$ARTIFACT/evidence-docker" && sha256sum --check SHA256SUMS)

printf '\n== Project the same image to OCI and verify every descriptor ==\n'
"$SKOPEO/bin/skopeo" copy --insecure-policy \
  "docker-archive:$ARTIFACT/vim-nix-herdr-hq.docker.tar" \
  "oci-archive:$ARTIFACT/vim-nix-herdr-hq.oci.tar:$IMAGE_REF"
python3 proofs/vim-nix/verify_oci.py \
  "$ARTIFACT/vim-nix-herdr-hq.oci.tar" \
  --receipt "$ARTIFACT/oci-verification.json" \
  --expect-os linux --expect-arch amd64
jq -e '.status == "PASS" and .platform == {"architecture":"amd64","os":"linux"}' \
  "$ARTIFACT/oci-verification.json" >/dev/null

printf '\n== Reject a one-byte OCI blob mutation ==\n'
python3 - "$ARTIFACT/vim-nix-herdr-hq.oci.tar" "$ARTIFACT/negative/mutated.oci.tar" <<'PY'
import io, pathlib, tarfile, sys
src, dst = map(pathlib.Path, sys.argv[1:])
rows = []
with tarfile.open(src, 'r:*') as tf:
    for m in tf.getmembers():
        data = tf.extractfile(m).read() if m.isfile() else None
        rows.append((m, data))
target = next(i for i, (m, data) in enumerate(rows)
              if m.isfile() and m.name.lstrip('./').startswith('blobs/sha256/') and data)
m, data = rows[target]
b = bytearray(data)
b[len(b)//2] ^= 1
rows[target] = (m, bytes(b))
with tarfile.open(dst, 'w') as out:
    for m, data in rows:
        info = tarfile.TarInfo(m.name)
        info.mode, info.uid, info.gid, info.mtime = m.mode, 0, 0, 0
        if data is None:
            info.type = m.type
            out.addfile(info)
        else:
            info.size = len(data)
            out.addfile(info, io.BytesIO(data))
PY
if python3 proofs/vim-nix/verify_oci.py \
    "$ARTIFACT/negative/mutated.oci.tar" \
    --receipt "$ARTIFACT/negative/should-not-exist.json"; then
