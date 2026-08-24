# WSLC physical acceptance — pinned Vim / Herdr / HQ v25

This is the final independent host gate for Issue #74. Image load, shell startup,
or the runtime token alone are **not** completion.

The pack contains two projections of the same `linux/amd64` product:

```text
vim-nix-herdr-hq.docker.tar  # physical WSLC input
vim-nix-herdr-hq.oci.tar     # independently proved OCI projection
```

The exact image tag is:

```text
roccho/vim-nix-herdr-hq-proof:bfdac8df95ec
```

The product source authority is
`bfdac8df95ec435ed8aad7042fa1fc9bc1082f6a`. The final proof commit is recorded
in the pack manifest/Receipt and may be a proof-only descendant of
`0870fdfe761f834fe90be54df051a307086e453d`.

## 1. Host prerequisites

From PowerShell:

```powershell
wsl --update --pre-release
wsl --version
wslc version
wslc run --rm hello-world
```

The current WSLC preview used by this acceptance requires WSL 2.9.3 or later.
Preserve the exact `wsl --version` and `wslc version` output.

## 2. Verify the pack before load

```powershell
Get-FileHash .\vim-nix-herdr-hq.docker.tar -Algorithm SHA256
Get-FileHash .\vim-nix-herdr-hq.oci.tar -Algorithm SHA256
Get-Content .\SHA256SUMS
```

Every value must match `SHA256SUMS`. Stop on any mismatch. Do not repair,
repack, or regenerate either archive.

## 3. Load and inspect the exact image

```powershell
wslc image load --input .\vim-nix-herdr-hq.docker.tar
wslc image inspect roccho/vim-nix-herdr-hq-proof:bfdac8df95ec
```

Required readback:

```text
OS           = linux
Architecture = amd64
Tag          = roccho/vim-nix-herdr-hq-proof:bfdac8df95ec
```

## 4. Run the complete product proof

Create an evidence directory and run the image's default `all` command. In the
final v25 proof, `all` means **editor 8 + runtime lifecycle**. CI uses this same
`all` entrypoint for both the Docker archive and its OCI projection.

```powershell
New-Item -ItemType Directory -Force .\wslc-evidence | Out-Null
$Evidence = (Resolve-Path .\wslc-evidence).Path

wslc run --rm --name vim-nix-proof-wslc `
  --volume "${Evidence}:/work/evidence" `
  roccho/vim-nix-herdr-hq-proof:bfdac8df95ec all |
  Tee-Object -FilePath .\wslc-proof.transcript.txt

$Exit = $LASTEXITCODE
$Exit
Get-Content .\wslc-proof.transcript.txt
Get-Content .\wslc-evidence\editor-receipt.json
Get-Content .\wslc-evidence\receipt.json
Get-Content .\wslc-evidence\SHA256SUMS
```

If the preview rejects the Windows bind-mount syntax, preserve that error and
run the same command without `--volume`. A mount-adapter failure does not change
the product result, but the transcript must still satisfy the token gates below.

## 5. Required physical PASS gates

The process exit code must be `0` and the transcript must contain both exact
lines:

```text
VIM_NIX_RUNTIME_E2E_PASS
VIM_NIX_FULL_E2E_PASS
```

When the evidence mount succeeds, additionally require:

```text
editor-receipt.json:
  status = PASS
  gates.testCount = 8
  gates.ptyTestCount = 4
  gates.headlessTestCount = 4

receipt.json:
  status = PASS
  gates.paneCount = 2
  gates.resultKinds = [accepted, started, stdout, completed]
  gates.stdout = hq-vim-e2e-ok
  gates.completedFinalText = hq-vim-e2e-ok
  gates.typedWorkerStop = PASS
  gates.workspaceClose = PASS
  gates.herdrStop = PASS
  gates.residualProcessCount = 0
```

Verify the returned evidence itself:

```powershell
Push-Location .\wslc-evidence
Get-Content .\SHA256SUMS
Pop-Location
```

No `PASS` may be inferred from image load or from only one of the two proof
surfaces.

## 6. Return evidence

Return exactly these observations:

```text
wsl --version
wslc version
wslc image inspect output
wslc run exit code
wslc-proof.transcript.txt
wslc-evidence/editor-receipt.json     (when mount succeeds)
wslc-evidence/receipt.json            (when mount succeeds)
wslc-evidence/SHA256SUMS              (when mount succeeds)
```

The authoritative WSLC acceptance Receipt is produced only from those observed
outputs. It must bind the Docker archive SHA-256, exact image tag, proof commit,
and product source commit. Until that Receipt exists, `WINDOWS_WSLC_PHYSICAL`
remains `OPEN` and Issue #74 remains open.
