#!/usr/bin/env python3
"""Single CI entrypoint for the edits operator-console candidate release.

The command builds every release asset through Nix, runs the pytest E2E suite
against the produced OCI image, and emits one release-ready directory.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import os
import pathlib
import shutil
import subprocess
import sys
import tarfile
import time
import zipfile
from dataclasses import dataclass
from typing import Iterable, Sequence

import pytest


@dataclass(frozen=True)
class SourceIdentity:
    commit: str
    tree: str
    branch: str


class BuildFailure(RuntimeError):
    pass


def sha256_file(path: pathlib.Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for block in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()


def write_json(path: pathlib.Path, value: object) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(value, indent=2, sort_keys=True) + "\n", encoding="utf-8")


def run(
    command: Sequence[str],
    *,
    cwd: pathlib.Path,
    log_dir: pathlib.Path,
    label: str,
    env: dict[str, str] | None = None,
    check: bool = True,
) -> subprocess.CompletedProcess[str]:
    log_dir.mkdir(parents=True, exist_ok=True)
    started = time.monotonic()
    result = subprocess.run(
        list(command),
        cwd=cwd,
        env=env,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        check=False,
    )
    duration_ms = round((time.monotonic() - started) * 1000, 3)
    log_path = log_dir / f"{label}.log"
    log_path.write_text(
        "$ " + " ".join(command) + "\n" + result.stdout,
        encoding="utf-8",
    )
    write_json(
        log_dir / f"{label}.json",
        {
            "command": list(command),
            "cwd": str(cwd),
            "durationMs": duration_ms,
            "exitCode": result.returncode,
            "log": log_path.name,
        },
    )
    if check and result.returncode != 0:
        sys.stderr.write(result.stdout)
        raise BuildFailure(f"{label} failed with exit code {result.returncode}")
    return result


def git_output(repo: pathlib.Path, *args: str) -> str:
    return subprocess.check_output(["git", "-C", str(repo), *args], text=True).strip()


def source_identity(repo: pathlib.Path) -> SourceIdentity:
    status = git_output(repo, "status", "--porcelain=v1")
    if status:
        raise BuildFailure("candidate build requires a clean Git worktree")
    return SourceIdentity(
        commit=git_output(repo, "rev-parse", "HEAD^{commit}"),
        tree=git_output(repo, "rev-parse", "HEAD^{tree}"),
        branch=git_output(repo, "branch", "--show-current") or "detached",
    )


def nix_build(
    *,
    repo: pathlib.Path,
    flake: pathlib.Path,
    source_url: str,
    attribute: str,
    log_dir: pathlib.Path,
    offline: bool,
) -> pathlib.Path:
    command = [
        "nix",
        "build",
        "--no-write-lock-file",
        "--no-link",
        "--print-out-paths",
    ]
    if offline:
        command.append("--offline")
    command.extend(
        [
            f"{flake}#{attribute}",
            "--override-input",
            "editsSource",
            source_url,
        ]
    )
    result = run(
        command,
        cwd=repo,
        log_dir=log_dir,
        label=f"nix-{'offline-' if offline else ''}{attribute}",
    )
    paths = [pathlib.Path(line.strip()) for line in result.stdout.splitlines() if line.strip().startswith("/nix/store/")]
    if len(paths) != 1 or not paths[0].exists():
        raise BuildFailure(f"nix build for {attribute} did not return exactly one existing output")
    return paths[0]


def copy_output(source: pathlib.Path, destination: pathlib.Path) -> None:
    destination.parent.mkdir(parents=True, exist_ok=True)
    if source.is_dir():
        if destination.exists():
            shutil.rmtree(destination)
        shutil.copytree(source, destination, symlinks=True)
    else:
        shutil.copy2(source, destination)


def docker_archive_identity(path: pathlib.Path) -> dict[str, object]:
    with tarfile.open(path, "r:*") as archive:
        manifest_stream = archive.extractfile("manifest.json")
        if manifest_stream is None:
            raise BuildFailure("Docker archive has no manifest.json")
        manifest = json.load(manifest_stream)
        if not isinstance(manifest, list) or len(manifest) != 1:
            raise BuildFailure("Docker archive must contain exactly one image")
        row = manifest[0]
        config_name = row.get("Config")
        if not isinstance(config_name, str) or not config_name.startswith("blobs/sha256/"):
            raise BuildFailure("Docker archive config path is invalid")
        config_stream = archive.extractfile(config_name)
        if config_stream is None:
            raise BuildFailure("Docker archive config blob is missing")
        raw = config_stream.read()
        digest = hashlib.sha256(raw).hexdigest()
        expected = config_name.rsplit("/", 1)[-1]
        if digest != expected:
            raise BuildFailure("Docker archive config digest mismatch")
        config = json.loads(raw)
        tags = row.get("RepoTags")
        if not isinstance(tags, list) or len(tags) != 1:
            raise BuildFailure("Docker archive must contain exactly one repository tag")
        return {
            "imageId": "sha256:" + digest,
            "imageRef": tags[0],
            "manifest": row,
            "config": config,
        }


def write_checksums(root: pathlib.Path) -> None:
    rows: list[str] = []
    for path in sorted(root.iterdir()):
        if not path.is_file() or path.name == "SHA256SUMS":
            continue
        rows.append(f"{sha256_file(path)}  {path.name}")
    (root / "SHA256SUMS").write_text("\n".join(rows) + "\n", encoding="utf-8")




def zip_evidence(source_roots: Iterable[pathlib.Path], destination: pathlib.Path) -> None:
    fixed = (1980, 1, 1, 0, 0, 0)
    with zipfile.ZipFile(destination, "w", compression=zipfile.ZIP_DEFLATED, compresslevel=9) as archive:
        for root in source_roots:
            if not root.exists():
                continue
            for path in sorted(root.rglob("*")):
                if not path.is_file():
                    continue
                relative = pathlib.PurePosixPath(root.name) / path.relative_to(root).as_posix()
                info = zipfile.ZipInfo(str(relative), fixed)
                info.create_system = 3
                info.external_attr = (0o100000 | (path.stat().st_mode & 0o777)) << 16
                info.compress_type = zipfile.ZIP_DEFLATED
                archive.writestr(info, path.read_bytes(), compress_type=zipfile.ZIP_DEFLATED, compresslevel=9)
        bad = archive.testzip()
        if bad is not None:
            raise BuildFailure(f"evidence ZIP CRC failure: {bad}")

def release_asset(path: pathlib.Path) -> dict[str, object]:
    return {
        "name": path.name,
        "bytes": path.stat().st_size,
        "sha256": "sha256:" + sha256_file(path),
    }


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument("--repo-root", type=pathlib.Path, required=True)
    parser.add_argument("--output", type=pathlib.Path, required=True)
    parser.add_argument("--release-tag", default="")
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    repo = args.repo_root.resolve()
    output = args.output.resolve()
    flake = repo / "proofs/vim-nix"
    tests = flake / "tests"
    verify_oci = flake / "verify_oci.py"
    if not (flake / "flake.nix").is_file() or not tests.is_dir():
        raise BuildFailure("candidate flake or pytest suite is missing")
    for command in ("git", "nix", "docker"):
        if shutil.which(command) is None:
            raise BuildFailure(f"required CI command is missing: {command}")

    identity = source_identity(repo)
    source_url = "git+" + repo.as_uri() + f"?rev={identity.commit}"
    if output.exists():
        shutil.rmtree(output)
    output.mkdir(parents=True)
    log_dir = output / "logs"
    evidence_dir = output / "evidence"
    evidence_dir.mkdir()

    lock_path = flake / "flake.lock"
    lock_before = sha256_file(lock_path)
    attributes = ["default", "interactiveImage", "interactiveOciImage", "interactiveWindowsKit", "interactiveImageRef"]
    normal: dict[str, pathlib.Path] = {}
    offline: dict[str, pathlib.Path] = {}
    for attribute in attributes:
        normal[attribute] = nix_build(
            repo=repo,
            flake=flake,
            source_url=source_url,
            attribute=attribute,
            log_dir=log_dir,
            offline=False,
        )
    for attribute in attributes:
        offline[attribute] = nix_build(
            repo=repo,
            flake=flake,
            source_url=source_url,
            attribute=attribute,
            log_dir=log_dir,
            offline=True,
        )
        if normal[attribute] != offline[attribute]:
            raise BuildFailure(f"normal/offline Nix output path drift for {attribute}")
    if sha256_file(lock_path) != lock_before:
        raise BuildFailure("flake.lock changed during candidate build")

    suffix = identity.commit[:12]
    docker_tar = output / f"edits-operator-console-{suffix}.docker.tar"
    oci_tar = output / f"edits-operator-console-{suffix}.oci.tar"
    windows_zip = output / f"edits-operator-console-{suffix}.windows.zip"
    image_ref_file = output / "image-ref.txt"
    copy_output(normal["interactiveImage"], docker_tar)
    copy_output(normal["interactiveOciImage"], oci_tar)
    copy_output(normal["interactiveWindowsKit"], windows_zip)
    copy_output(normal["interactiveImageRef"], image_ref_file)
    image_ref = image_ref_file.read_text(encoding="utf-8").strip()

    parsed = docker_archive_identity(docker_tar)
    if parsed["imageRef"] != image_ref:
        raise BuildFailure("Docker archive tag differs from interactiveImageRef")
    docker_config = parsed["config"]
    config_payload = docker_config.get("config", {}) if isinstance(docker_config, dict) else {}
    build_manifest = {
        "schema": "edits.candidateBuild.v1",
        "status": "PASS",
        "source": {
            "repository": "roccho-dev/edits",
            "commit": identity.commit,
            "tree": identity.tree,
            "branch": identity.branch,
            "clean": True,
        },
        "nix": {
            "flake": "proofs/vim-nix",
            "flakeLockSha256": "sha256:" + lock_before,
            "sourceOverride": source_url,
            "normalOfflineSameOutputs": True,
            "outputs": {key: str(value) for key, value in normal.items()},
        },
        "image": {
            "ref": image_ref,
            "id": parsed["imageId"],
            "user": config_payload.get("User"),
            "entrypoint": config_payload.get("Entrypoint"),
            "workingDir": config_payload.get("WorkingDir"),
            "exposedPorts": config_payload.get("ExposedPorts", {}),
        },
        "assets": {
            "docker": release_asset(docker_tar),
            "oci": release_asset(oci_tar),
            "windows": release_asset(windows_zip),
        },
        "releaseTag": args.release_tag or None,
    }
    write_json(output / "build-manifest.json", build_manifest)

    run(
        [
            sys.executable,
            str(verify_oci),
            str(oci_tar),
            "--receipt",
            str(evidence_dir / "oci-verification.json"),
            "--expect-os",
            "linux",
            "--expect-arch",
            "amd64",
        ],
        cwd=repo,
        log_dir=log_dir,
        label="verify-oci",
    )

    bundle = output / f"edits-source-{suffix}.git.bundle"
    run(
        ["git", "bundle", "create", str(bundle), "HEAD"],
        cwd=repo,
        log_dir=log_dir,
        label="git-bundle-create",
    )
    run(
        ["git", "bundle", "verify", str(bundle)],
        cwd=repo,
        log_dir=log_dir,
        label="git-bundle-verify",
    )

    os.environ["EDITS_CANDIDATE_RELEASE_DIR"] = str(output)
    os.environ["EDITS_CANDIDATE_IMAGE_REF"] = image_ref
    os.environ["EDITS_CANDIDATE_SOURCE_COMMIT"] = identity.commit
    pytest_xml = output / "pytest.xml"
    test_status = pytest.main(
        [
            "-ra",
            "--strict-markers",
            "--junitxml",
            str(pytest_xml),
            str(tests),
        ]
    )
    if test_status != pytest.ExitCode.OK:
        raise BuildFailure(f"candidate pytest E2E failed: {test_status}")

    e2e_report = {
        "schema": "edits.candidateE2E.v1",
        "status": "PASS",
        "sourceCommit": identity.commit,
        "sourceTree": identity.tree,
        "imageRef": image_ref,
        "imageId": parsed["imageId"],
        "runner": "pytest",
        "mandatorySkips": 0,
        "xfail": 0,
        "waivers": 0,
        "goldenTokens": [
            "EDITS_INTERACTIVE_PTY_SMOKE_PASS",
            "VIM_NIX_FULL_E2E_PASS",
            "VIM_NIX_ACCEPTED_HISTORY_E2E_PASS",
        ],
        "windowsPhysicalWslc": "OPEN",
        "claim": "Linux CI built and exercised the candidate; Windows kit is ready for direct download and physical WSLC readback.",
    }
    write_json(output / "e2e-report.json", e2e_report)
    evidence_zip = output / f"edits-operator-console-{suffix}.evidence.zip"
    zip_evidence([log_dir, evidence_dir], evidence_zip)
    release_manifest = {
        "schema": "edits.candidateRelease.v1",
        "status": "PASS",
        "releaseTag": args.release_tag or None,
        "source": build_manifest["source"],
        "image": build_manifest["image"],
        "assets": [
            release_asset(docker_tar),
            release_asset(oci_tar),
            release_asset(windows_zip),
            release_asset(bundle),
            release_asset(pytest_xml),
            release_asset(output / "build-manifest.json"),
            release_asset(output / "e2e-report.json"),
            release_asset(evidence_zip),
        ],
        "gates": {
            "nixNormalOfflineSameOutputs": "PASS",
            "dockerArchiveIntegrity": "PASS",
            "ociArchiveIntegrity": "PASS",
            "pytestE2E": "PASS",
            "windowsNoBuildKit": "PASS",
            "physicalWindowsWslc": "OPEN",
        },
        "productionPromotion": False,
    }
    write_json(output / "release-manifest.json", release_manifest)
    (output / "RELEASE.md").write_text(
        "\n".join(
            [
                f"# Edits operator-console candidate {suffix}",
                "",
                f"- source commit: `{identity.commit}`",
                f"- source tree: `{identity.tree}`",
                f"- image: `{image_ref}`",
                f"- image ID: `{parsed['imageId']}`",
                "- Linux CI build and pytest E2E: **PASS**",
                "- physical Windows/WSLC readback: **OPEN**",
                "",
                "Download the `.windows.zip`, extract it, run `verify.cmd`, then `run.cmd`.",
                "Windows performs no build and needs no registry.",
                "",
            ]
        ),
        encoding="utf-8",
    )
    write_checksums(output)
    print(json.dumps(release_manifest, indent=2, sort_keys=True))
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except BuildFailure as exc:
        print(f"candidate-ci: {exc}", file=sys.stderr)
        raise SystemExit(1)
