#!/usr/bin/env bash
set -euo pipefail
oci_out="$(nix build --no-link --print-out-paths --no-write-lock-file .#oci)"
skopeo_out="$(nix build --no-link --print-out-paths --no-write-lock-file .#skopeo)"
test -f "$oci_out/vim-nix-herdr-hq.docker.tar"
test -f "$oci_out/vim-nix-herdr-hq.oci.tar"
install -m 0644 "$oci_out/vim-nix-herdr-hq.docker.tar" "$DIST/"
install -m 0644 "$oci_out/vim-nix-herdr-hq.oci.tar" "$DIST/"
install -m 0644 "$oci_out/manifest.raw.json" "$DIST/"
install -m 0644 "$oci_out/inspect.json" "$DIST/"
install -m 0644 "$oci_out/image.ref" "$DIST/"
install -m 0644 "$oci_out/image.tag" "$DIST/"
echo "oci_out=$oci_out" >> "$GITHUB_OUTPUT"
echo "skopeo=$skopeo_out/bin/skopeo" >> "$GITHUB_OUTPUT"
