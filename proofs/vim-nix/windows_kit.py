#!/usr/bin/env python3
"""Build a deterministic Windows/WSLC delivery ZIP from one Docker archive."""
from __future__ import annotations

import argparse
import hashlib
import json
import pathlib
import stat
import tarfile
import zipfile

FIXED_TIME = (1980, 1, 1, 0, 0, 0)
ROOT = "edits-windows"


def sha256_bytes(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def sha256_file(path: pathlib.Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for block in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()


def docker_identity(archive: pathlib.Path) -> tuple[str, dict[str, object]]:
    with tarfile.open(archive, "r:*") as bundle:
        manifest_member = bundle.getmember("manifest.json")
        manifest = json.load(bundle.extractfile(manifest_member))
        if not isinstance(manifest, list) or len(manifest) != 1:
            raise SystemExit("Docker archive must contain exactly one image")
        row = manifest[0]
        config_name = row.get("Config")
        tags = row.get("RepoTags")
        if not isinstance(config_name, str):
            raise SystemExit("Docker archive config identity is invalid")
        if config_name.startswith("blobs/sha256/"):
            expected = pathlib.PurePosixPath(config_name).name
        elif len(config_name) == 69 and config_name.endswith(".json") and all(
            character in "0123456789abcdef" for character in config_name[:-5]
        ):
            expected = config_name[:-5]
        else:
            raise SystemExit("Docker archive config identity is invalid")
        if not isinstance(tags, list) or len(tags) != 1 or not isinstance(tags[0], str):
            raise SystemExit("Docker archive must contain exactly one repository tag")
        config_stream = bundle.extractfile(config_name)
        if config_stream is None:
            raise SystemExit("Docker archive config is missing")
        config_raw = config_stream.read()
        if sha256_bytes(config_raw) != expected:
            raise SystemExit("Docker archive config digest mismatch")
        config = json.loads(config_raw)
        return "sha256:" + expected, {"manifest": row, "config": config}


def zip_add(archive: zipfile.ZipFile, name: str, data: bytes, mode: int = 0o644) -> None:
    info = zipfile.ZipInfo(f"{ROOT}/{name}", FIXED_TIME)
    info.create_system = 3
    info.external_attr = (stat.S_IFREG | mode) << 16
    info.compress_type = zipfile.ZIP_STORED if name.endswith(".docker.tar") else zipfile.ZIP_DEFLATED
    archive.writestr(info, data, compress_type=info.compress_type, compresslevel=9)


def powershell_verify(archive_name: str, digest: str) -> str:
    return f"""[CmdletBinding()]
param([string]$Wslc = $env:WSLC_EXE)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
if ([string]::IsNullOrWhiteSpace($Wslc)) {{ $Wslc = 'C:\\Program Files\\WSL\\wslc.exe' }}
$Archive = Join-Path $PSScriptRoot '{archive_name}'
$Expected = '{digest.upper()}'
if (-not (Test-Path -LiteralPath $Archive -PathType Leaf)) {{ throw "Docker archive not found: $Archive" }}
$Actual = (Get-FileHash -LiteralPath $Archive -Algorithm SHA256).Hash
if ($Actual -ne $Expected) {{ throw "Docker archive SHA-256 mismatch: $Actual" }}
if (-not (Test-Path -LiteralPath $Wslc -PathType Leaf)) {{ throw "WSLC not found: $Wslc" }}
& $Wslc version
if ($LASTEXITCODE -ne 0) {{ throw "wslc version failed with exit code $LASTEXITCODE" }}
Write-Host 'EDITS_WINDOWS_VERIFY_PASS'
"""


def powershell_run(archive_name: str, image_ref: str, image_id: str) -> str:
    return f"""[CmdletBinding()]
param(
  [string]$ContainerName = 'edits',
  [string]$Wslc = $env:WSLC_EXE
)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
if ([string]::IsNullOrWhiteSpace($Wslc)) {{ $Wslc = 'C:\\Program Files\\WSL\\wslc.exe' }}
& (Join-Path $PSScriptRoot 'verify.ps1') -Wslc $Wslc
if ($LASTEXITCODE -ne 0) {{ exit $LASTEXITCODE }}
$Archive = Join-Path $PSScriptRoot '{archive_name}'
$Image = '{image_ref}'
$ExpectedImageId = '{image_id}'
& $Wslc load -i $Archive
if ($LASTEXITCODE -ne 0) {{ throw "wslc load failed with exit code $LASTEXITCODE" }}
$Inspection = @(& $Wslc inspect $Image | ConvertFrom-Json)
if ($LASTEXITCODE -ne 0 -or $Inspection.Count -ne 1) {{ throw "Could not inspect exactly one image for $Image" }}
if ($Inspection[0].Id -ne $ExpectedImageId) {{ throw "Image ID mismatch: $($Inspection[0].Id)" }}
$Args = @(
  'run', '--rm', '--interactive', '--tty',
  '--name', $ContainerName,
  '--volume', 'dev-home:/home/dev',
  '--volume', 'repos:/work/repos',
  '--workdir', '/work/repos',
  $Image
)
& $Wslc @Args
exit $LASTEXITCODE
"""


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--docker-archive", type=pathlib.Path, required=True)
    parser.add_argument("--image-ref", required=True)
    parser.add_argument("--source-revision", required=True)
    parser.add_argument("--output", type=pathlib.Path, required=True)
    args = parser.parse_args()

    docker_archive = args.docker_archive.resolve()
    image_id, parsed = docker_identity(docker_archive)
    tags = parsed["manifest"]["RepoTags"]
    if tags != [args.image_ref]:
        raise SystemExit(f"image reference mismatch: {tags!r} != {[args.image_ref]!r}")

    archive_name = "edits-operator-console.docker.tar"
    docker_digest = sha256_file(docker_archive)
    manifest = {
        "schema": "edits.windowsDelivery.v1",
        "status": "PASS",
        "sourceRevision": args.source_revision,
        "imageRef": args.image_ref,
        "imageId": image_id,
        "dockerArchive": archive_name,
        "dockerArchiveBytes": docker_archive.stat().st_size,
        "dockerArchiveSha256": "sha256:" + docker_digest,
        "runtime": "Windows/WSLC",
        "buildRequiredOnWindows": False,
        "registryRequired": False,
        "volumes": ["dev-home:/home/dev", "repos:/work/repos"],
        "workdir": "/work/repos",
        "exposedPorts": 0,
    }
    manifest_bytes = (json.dumps(manifest, indent=2, sort_keys=True) + "\n").encode()
    readme = f"""# Edits operator console for Windows

This ZIP is complete. Windows does not build the image and does not need a registry.

1. Run `verify.cmd`.
2. Run `run.cmd`.

Image: `{args.image_ref}`
Image ID: `{image_id}`
Source: `{args.source_revision}`

The launcher verifies the Docker archive before `wslc load`, reads the loaded image ID back, and then starts the foreground interactive console with durable `dev-home` and `repos` volumes.
""".encode()
    verify_ps1 = powershell_verify(archive_name, docker_digest).encode("utf-8")
    run_ps1 = powershell_run(archive_name, args.image_ref, image_id).encode("utf-8")
    verify_cmd = b'@echo off\r\npowershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%~dp0verify.ps1" %*\r\nexit /b %ERRORLEVEL%\r\n'
    run_cmd = b'@echo off\r\npowershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%~dp0run.ps1" %*\r\nexit /b %ERRORLEVEL%\r\n'

    checksums = {
        archive_name: docker_digest,
        "manifest.json": sha256_bytes(manifest_bytes),
        "README.md": sha256_bytes(readme),
        "verify.ps1": sha256_bytes(verify_ps1),
        "run.ps1": sha256_bytes(run_ps1),
        "verify.cmd": sha256_bytes(verify_cmd),
        "run.cmd": sha256_bytes(run_cmd),
    }
    checksum_bytes = "".join(f"{value}  {name}\n" for name, value in sorted(checksums.items())).encode()

    args.output.parent.mkdir(parents=True, exist_ok=True)
    with zipfile.ZipFile(args.output, "w") as archive:
        zip_add(archive, archive_name, docker_archive.read_bytes())
        zip_add(archive, "manifest.json", manifest_bytes)
        zip_add(archive, "README.md", readme)
        zip_add(archive, "verify.ps1", verify_ps1)
        zip_add(archive, "run.ps1", run_ps1)
        zip_add(archive, "verify.cmd", verify_cmd)
        zip_add(archive, "run.cmd", run_cmd)
        zip_add(archive, "SHA256SUMS", checksum_bytes)
        bad = archive.testzip()
        if bad is not None:
            raise SystemExit(f"Windows ZIP CRC failure: {bad}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
