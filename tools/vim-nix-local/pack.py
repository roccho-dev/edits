#!/usr/bin/env python3
from __future__ import annotations

import argparse
import base64
import hashlib
import json
import os
import pathlib
import shutil
import stat
import subprocess
import tempfile
import zipfile

FIXED_ZIP_TIME = (2026, 8, 21, 0, 0, 0)
ROOT_NAME = "vim-nix-local-first"


def sha256(path: pathlib.Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as source:
        for block in iter(lambda: source.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()


def git_value(root: pathlib.Path, expression: str) -> str | None:
    try:
        return subprocess.check_output(
            ["git", "-C", str(root), "rev-parse", expression],
            text=True,
            stderr=subprocess.DEVNULL,
        ).strip()
    except (subprocess.CalledProcessError, FileNotFoundError):
        return None


def copy_required_source(repo_root: pathlib.Path, stage_root: pathlib.Path) -> list[str]:
    selected = [
        pathlib.Path("packages/hq-vim"),
        pathlib.Path("proofs/vim-nix"),
        pathlib.Path("tools/vim-nix-local"),
        pathlib.Path("docs/operations/vim-nix-local-first.md"),
    ]
    copied: list[str] = []
    for relative in selected:
        source = repo_root / relative
        if not source.exists():
            raise SystemExit(f"required source missing: {relative}")
        target = stage_root / relative
        if source.is_dir():
            shutil.copytree(
                source,
                target,
                ignore=shutil.ignore_patterns("__pycache__", "*.pyc", ".local"),
            )
        else:
            target.parent.mkdir(parents=True, exist_ok=True)
            shutil.copy2(source, target)
        copied.append(relative.as_posix())
    return copied


def write_text(path: pathlib.Path, text: str, mode: int = 0o644) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(text, encoding="utf-8", newline="\n")
    path.chmod(mode)


def write_checksums(root: pathlib.Path) -> None:
    rows: list[str] = []
    for path in sorted(root.rglob("*")):
        if not path.is_file() or path.name == "SHA256SUMS":
            continue
        rows.append(f"{sha256(path)}  {path.relative_to(root).as_posix()}")
    write_text(root / "SHA256SUMS", "\n".join(rows) + "\n")


def deterministic_zip(source_root: pathlib.Path, destination: pathlib.Path) -> None:
    with zipfile.ZipFile(destination, "w", zipfile.ZIP_DEFLATED, compresslevel=9) as archive:
        for path in sorted(source_root.rglob("*")):
            relative = pathlib.PurePosixPath(ROOT_NAME) / path.relative_to(source_root).as_posix()
            if path.is_dir():
                info = zipfile.ZipInfo(str(relative) + "/", FIXED_ZIP_TIME)
                info.create_system = 3
                info.external_attr = (stat.S_IFDIR | 0o755) << 16
                archive.writestr(info, b"")
                continue
            info = zipfile.ZipInfo(str(relative), FIXED_ZIP_TIME)
            info.create_system = 3
            mode = stat.S_IMODE(path.stat().st_mode)
            info.external_attr = (stat.S_IFREG | mode) << 16
            info.compress_type = zipfile.ZIP_DEFLATED
            archive.writestr(info, path.read_bytes(), compress_type=zipfile.ZIP_DEFLATED, compresslevel=9)
        bad = archive.testzip()
        if bad is not None:
            raise SystemExit(f"zip CRC failure: {bad}")


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--repo-root", type=pathlib.Path, required=True)
    parser.add_argument("--output-dir", type=pathlib.Path, required=True)
    parser.add_argument("--herdr", type=pathlib.Path)
    args = parser.parse_args()

    repo_root = args.repo_root.resolve()
    output_dir = args.output_dir.resolve()
    output_dir.mkdir(parents=True, exist_ok=True)

    with tempfile.TemporaryDirectory(prefix="vim-nix-carry-") as temporary:
        stage_root = pathlib.Path(temporary) / ROOT_NAME
        stage_root.mkdir()
        copied = copy_required_source(repo_root, stage_root)

        herdr_record: dict[str, object] | None = None
        if args.herdr is not None:
            herdr = args.herdr.resolve()
            if not herdr.is_file() or not os.access(herdr, os.X_OK):
                raise SystemExit(f"Herdr is not executable: {herdr}")
            version = subprocess.check_output([str(herdr), "--version"], text=True).strip()
            if version != "herdr 0.8.0":
                raise SystemExit(f"unsupported Herdr: {version}")
            target = stage_root / "bin/herdr"
            target.parent.mkdir(parents=True)
            shutil.copy2(herdr, target)
            target.chmod(0o755)
            herdr_record = {
                "version": version,
                "bytes": target.stat().st_size,
                "sha256": sha256(target),
                "target": "linux-x86_64",
            }

        write_text(
            stage_root / "run",
            """#!/usr/bin/env bash
set -euo pipefail
root=$(CDPATH= cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
exec "$root/tools/vim-nix-local/vim-nix" verify "$@"
""",
            0o755,
        )
        write_text(
            stage_root / "README.md",
            """# Vim/Nix local-first Carry

Run the verified editor-adapter delta without network access:

```bash
unzip <pack>.zip
cd vim-nix-local-first
bash run
```

The local proof fixes five Canon TDD boundaries only: minimal editor surface
and exact HQ binding, canonical LSP/submit behavior, agent-first/direct-fallback
native popup behavior, safe draft preservation, and controlling-TTY behavior.
It also retains the OCI mutation control and optional
Herdr exactly-two-pane/clean-stop probe.

The carry is a development surface, not the final exact Nix/HQ/yegappan/worker/
Docker/OCI distribution claim.
""",
        )

        manifest = {
            "schema": "edits.vimNixLocalFirstCarry/1",
            "kind": "source-plus-optional-native-adapter",
            "target": "linux-x86_64",
            "entrypoint": "run",
            "source": {
                "repository": "roccho-dev/edits",
                "commit": git_value(repo_root, "HEAD^{commit}"),
                "tree": git_value(repo_root, "HEAD^{tree}"),
                "paths": copied,
                "flakeLockSha256": sha256(stage_root / "proofs/vim-nix/flake.lock"),
            },
            "herdr": herdr_record,
            "contract": {
                "offlineAfterExtraction": True,
                "localLowCostProof": "AVAILABLE",
                "exactProductClosure": "DEFERRED_HIGH_COST_GATE",
                "physicalWSLC": "NOT_ATTESTED_BY_THIS_PACK",
            },
        }
        write_text(stage_root / "manifest.json", json.dumps(manifest, indent=2) + "\n")
        write_checksums(stage_root)

        temporary_zip = output_dir / "vim-nix-local-first.tmp.zip"
        deterministic_zip(stage_root, temporary_zip)
        zip_digest = sha256(temporary_zip)
        final_zip = output_dir / f"vim-nix-local-first.linux-x86_64.{zip_digest}.zip"
        temporary_zip.replace(final_zip)

        carrier = pathlib.Path(str(final_zip) + ".b64.txt")
        carrier.write_bytes(base64.b64encode(final_zip.read_bytes()))
        decoded = base64.b64decode(carrier.read_bytes(), validate=True)
        if decoded != final_zip.read_bytes():
            raise SystemExit("carrier round-trip mismatch")

        external_manifest = {
            "schema": "ops.carriedPayload/1",
            "kind": "archive",
            "target": "linux-x86_64",
            "payload": {
                "name": final_zip.name,
                "bytes": final_zip.stat().st_size,
                "sha256": zip_digest,
            },
            "carrier": {
                "name": carrier.name,
                "codec": "standard-base64-single-line",
                "bytes": carrier.stat().st_size,
                "sha256": sha256(carrier),
                "strictRoundTrip": "PASS",
            },
            "entrypointAfterExtraction": "vim-nix-local-first/run",
        }
        external_manifest_path = pathlib.Path(str(final_zip) + ".manifest.json")
        external_manifest_path.write_text(json.dumps(external_manifest, indent=2) + "\n", encoding="utf-8")

        print(json.dumps({
            "status": "PASS",
            "zip": str(final_zip),
            "zipBytes": final_zip.stat().st_size,
            "zipSha256": zip_digest,
            "carrier": str(carrier),
            "carrierBytes": carrier.stat().st_size,
            "manifest": str(external_manifest_path),
            "herdrBundled": herdr_record is not None,
        }, indent=2))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
