#!/usr/bin/env bash
set -euo pipefail
source_commit="$(git rev-parse HEAD)"
mapfile -t assets < <(find "$RELEASE_DIR" -maxdepth 1 -type f -printf '%f\n' | sort)
test "${#assets[@]}" -ge 6
if gh release view "$RELEASE_TAG" --repo "$GITHUB_REPOSITORY" >/dev/null 2>&1; then
  existing="$RUNNER_TEMP/existing-release"
  mkdir -p "$existing"
  gh release download "$RELEASE_TAG" --repo "$GITHUB_REPOSITORY" --dir "$existing"
  for name in "${assets[@]}"; do cmp "$RELEASE_DIR/$name" "$existing/$name"; done
else
  args=()
  for name in "${assets[@]}"; do args+=("$RELEASE_DIR/$name"); done
  gh release create "$RELEASE_TAG" "${args[@]}" \
    --repo "$GITHUB_REPOSITORY" --target "$source_commit" --prerelease \
    --title "Vim/Nix/Herdr/HQ WSLC proof ${source_commit:0:12}" \
    --notes "Downloadable independent WSLC test projection for edits#74. Final Git bundles are intentionally withheld until WSLC acceptance."
fi
readback="$RUNNER_TEMP/release-readback"
rm -rf "$readback"; mkdir -p "$readback"
gh release download "$RELEASE_TAG" --repo "$GITHUB_REPOSITORY" --dir "$readback"
for name in "${assets[@]}"; do cmp "$RELEASE_DIR/$name" "$readback/$name"; done
(cd "$readback" && sha256sum --check SHA256SUMS)
url="https://github.com/$GITHUB_REPOSITORY/releases/tag/$RELEASE_TAG"
echo "url=$url" >> "$GITHUB_OUTPUT"
