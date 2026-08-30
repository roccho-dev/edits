# Issue #118 completion states

This file prevents source merge, CI completion, downloadable delivery, and full
physical closure from being reported as the same state.

## State 1 — source integrated

```text
proposals contains the exact operator-console source tree
+ edits-client / edits-service / edits-mux roles
+ legacy compatibility
+ one Nix-backed candidate entrypoint
```

PR #119 reached this state. It did not prove a candidate image or create a
Release.

## State 2 — CI complete and downloadable

The completion PR reaches this state only when one exact Git head passes:

```text
nix run ./proofs/vim-nix#candidate
→ normal and offline Nix outputs are identical
→ forced rebuild returns the same output paths
→ Docker archive integrity passes
→ OCI archive integrity passes
→ Docker-imported pytest E2E passes
→ OCI-imported pytest E2E passes
→ skips / xfail / xpass / waiver = 0
→ exact-commit prerelease is created
→ every Release asset is downloaded and compared byte-for-byte
```

Required Release assets include:

```text
*.docker.tar
*.oci.tar
*.windows.zip
*.git.bundle
*.evidence.zip
build-manifest.json
e2e-report.json
release-manifest.json
RELEASE.md
SHA256SUMS
```

The Windows ZIP is complete at this state. A Windows user only extracts it and
runs:

```text
verify.cmd
run.cmd
```

Windows performs no Nix build, source checkout, registry pull, or compiler
installation.

## State 3 — Issue #118 physically closed

CI cannot make this claim. It additionally requires the released Windows ZIP to
pass on a physical Windows/WSLC host:

```text
archive hash verification
→ WSLC load
→ image-ID readback
→ foreground interactive TTY
→ PTY smoke
→ Vim/HQ runtime E2E
→ accepted-history E2E
→ dev-home and repos persistence
```

Until that receipt exists, machine records must say:

```text
status = CI_PASS
physicalWindowsWslc = OPEN
issue118Closure = false
finalAssertion = CI_COMPLETE_WINDOWS_PHYSICAL_READBACK_OPEN
```

The delivered historical Golden remains the frozen comparison authority:

```text
image     roccho/edits:dirty-e4614cc36968
image ID  sha256:ba3e136d7bf01f94433b91c5eebb632f70c5c25f745b5e793d735e3da393e32e
tar SHA   fba9c3bb803d9269c32d15b27910c4ff2a77eba44a13afa343d8e2e9815b9022
source    77e1861554bc5c55da6103bac0278e63e97614f1
```
