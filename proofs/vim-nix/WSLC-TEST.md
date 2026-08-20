# WSLC readback — pinned Vim / Herdr / HQ proof

This pack contains two representations of the same `linux/amd64` image:

```text
vim-nix-herdr-hq.docker.tar  # load into current WSLC
vim-nix-herdr-hq.oci.tar     # OCI semantic/proof archive
```

As of the WSLC 2.9.x public preview, `wslc image load --input` accepts the
Docker-compatible archive but does not yet accept an OCI image-layout archive.
The OCI archive is still verified and executed independently in CI through
Skopeo and Docker. Use the Docker archive for the physical WSLC readback.

## 1. Prerequisites

From PowerShell:

```powershell
wsl --update --pre-release
wsl --version
wslc version
wslc run --rm hello-world
```

The current preview requires WSL 2.9.3 or later. Preserve the exact `wslc
version` output in the returned transcript.

## 2. Verify the downloaded pack

```powershell
Get-FileHash .\vim-nix-herdr-hq.docker.tar -Algorithm SHA256
Get-FileHash .\vim-nix-herdr-hq.oci.tar -Algorithm SHA256
Get-Content .\SHA256SUMS
```

Compare the values with `SHA256SUMS`. Stop on any mismatch; do not repair or
repack the archive.

## 3. Load the WSLC-compatible image

```powershell
wslc image load --input .\vim-nix-herdr-hq.docker.tar
wslc image list
wslc image inspect roccho/vim-nix-herdr-hq-proof:d83bf4c
```

The selected image must be `linux/amd64` and must retain the exact tag above.

## 4. Run the complete proof

The simplest readback streams the proof transcript to the terminal:

```powershell
wslc run --rm --name vim-nix-proof-wslc `
  roccho/vim-nix-herdr-hq-proof:d83bf4c all |
  Tee-Object -FilePath .\wslc-proof.transcript.txt
```

The final exact line must be:

```text
VIM_NIX_HERDR_OCI_RUNTIME_PROOF_PASS
```

This line is emitted only after canonical conformance, all three native Vim
popup journeys in a fresh Herdr PTY, exact two-pane topology, managed worker
health, one real Vim-to-HQ submit, the exact four-event result chain, typed
worker stop, workspace/server close, and residual-process readback.

## 5. Optional evidence directory mount

WSLC exposes Docker-like `--volume` support. To preserve the full Receipt and
logs outside the container:

```powershell
New-Item -ItemType Directory -Force .\wslc-evidence | Out-Null
$Evidence = (Resolve-Path .\wslc-evidence).Path

wslc run --rm --name vim-nix-proof-wslc `
  --volume "${Evidence}:/work/evidence" `
  roccho/vim-nix-herdr-hq-proof:d83bf4c all |
  Tee-Object -FilePath .\wslc-proof.transcript.txt

Get-Content .\wslc-evidence\receipt.json
Get-Content .\wslc-evidence\SHA256SUMS
```

If the current WSLC preview rejects the Windows path syntax, retain the full
error and run step 4 without a mount. The stdout terminal token remains the
minimal independent runtime readback; the mount failure is a WSLC adapter
finding, not a product-runtime failure.

## 6. Return evidence

Return exactly:

```text
wsl --version
wslc version
wslc image inspect output
wslc run exit code
wslc-proof.transcript.txt
wslc-evidence/receipt.json and SHA256SUMS when the mount succeeds
```

Do not report completion from image load alone. A valid user-side result must
show the final PASS token and exit code 0.
