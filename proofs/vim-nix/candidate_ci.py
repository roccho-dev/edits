#!/usr/bin/env python3
"""One build/proof entrypoint for the edits operator-console OCI release.

The command owns source readback, Nix materialization, archive validation,
Docker+OCI runtime E2E, Windows delivery assembly validation, and release-ready
evidence. GitHub Actions is only the runner and Release transport adapter.
"""
from __future__ import annotations

import argparse
import hashlib
import io
import json
import os
import pathlib
import re
import shutil
import stat
import subprocess
import sys
import tarfile
import time
import uuid
import xml.etree.ElementTree as ET
import zipfile
from dataclasses import dataclass
from typing import Any, Iterable, Mapping, Sequence

import pytest


FIXED_ZIP_TIME = (1980, 1, 1, 0, 0, 0)
TOOL_PATHS = {
    "git": "@git@",
    "nix": "@nix@",
    "skopeo": "@skopeo@",
}


@dataclass(frozen=True)
class SourceIdentity:
    commit: str
    tree: str
    branch: str
    commit_count: int


class BuildFailure(RuntimeError):
    pass


def resolve_tool(name: str) -> str:
    override = os.environ.get(f"EDITS_{name.upper()}_BIN")
    if override:
        return override
    configured = TOOL_PATHS.get(name, "")
    if configured and not configured.startswith("@"):
        return configured
    found = shutil.which(name)
    if found:
        return found
    raise BuildFailure(f"required CI command is missing: {name}")


def canonical_json(value: Any) -> bytes:
    return json.dumps(value, ensure_ascii=False, sort_keys=True, separators=(",", ":")).encode("utf-8")


def sha256_file(path: pathlib.Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for block in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()


def write_json(path: pathlib.Path, value: object) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_bytes(canonical_json(value) + b"\n")


def run(
    command: Sequence[str],
    *,
    cwd: pathlib.Path,
    log_dir: pathlib.Path,
    label: str,
    env: Mapping[str, str] | None = None,
    check: bool = True,
    timeout: int | None = None,
) -> subprocess.CompletedProcess[str]:
    log_dir.mkdir(parents=True, exist_ok=True)
    merged_env = os.environ.copy()
    if env:
        merged_env.update(env)
    started = time.monotonic()
    result = subprocess.run(
        list(command),
        cwd=cwd,
        env=merged_env,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        check=False,
        timeout=timeout,
    )
    duration_ms = round((time.monotonic() - started) * 1000, 3)
    log_path = log_dir / f"{label}.log"
    log_path.write_text(
        "$ " + " ".join(command)
        + "\n\n[stdout]\n" + result.stdout
        + "\n[stderr]\n" + result.stderr,
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
        sys.stderr.write(result.stderr)
        raise BuildFailure(f"{label} failed with exit code {result.returncode}")
    return result


def git_output(repo: pathlib.Path, *args: str) -> str:
    return subprocess.check_output([resolve_tool("git"), "-C", str(repo), *args], text=True).strip()


def source_identity(repo: pathlib.Path) -> SourceIdentity:
    status = git_output(repo, "status", "--porcelain=v1")
    if status:
        raise BuildFailure("candidate build requires a clean Git worktree")
    return SourceIdentity(
        commit=git_output(repo, "rev-parse", "HEAD^{commit}"),
        tree=git_output(repo, "rev-parse", "HEAD^{tree}"),
        branch=git_output(repo, "branch", "--show-current") or "detached",
        commit_count=int(git_output(repo, "rev-list", "--count", "HEAD")),
    )


def tar_json(archive: tarfile.TarFile, name: str) -> Any:
    stream = archive.extractfile(name)
    if stream is None:
        raise BuildFailure(f"archive member is missing: {name}")
    return json.loads(stream.read().decode("utf-8"))


def inspect_docker_archive(path: pathlib.Path) -> dict[str, Any]:
    mismatches: list[str] = []
    with tarfile.open(path, "r:*") as archive:
        docker_manifest = tar_json(archive, "manifest.json")
        index = tar_json(archive, "index.json")
        if not isinstance(docker_manifest, list) or len(docker_manifest) != 1:
            raise BuildFailure("Docker archive must contain exactly one image")
        row = docker_manifest[0]
        tags = row.get("RepoTags") or []
        if len(tags) != 1 or not isinstance(tags[0], str):
            raise BuildFailure("Docker archive must contain exactly one repository tag")

        config_path = row.get("Config")
        if not isinstance(config_path, str) or not config_path.startswith("blobs/sha256/"):
            raise BuildFailure("Docker archive config path is invalid")
        config_member = archive.getmember(config_path)
        config_stream = archive.extractfile(config_member)
        if config_stream is None:
            raise BuildFailure("Docker config blob is missing")
        config_bytes = config_stream.read()
        config_hex = hashlib.sha256(config_bytes).hexdigest()
        if pathlib.PurePosixPath(config_path).name != config_hex:
            mismatches.append(config_path)
        config = json.loads(config_bytes)

        descriptors = index.get("manifests") or []
        if len(descriptors) != 1:
            raise BuildFailure("Docker archive OCI index must contain exactly one manifest")
        descriptor = descriptors[0]
        manifest_digest = descriptor.get("digest")
        if not isinstance(manifest_digest, str) or not manifest_digest.startswith("sha256:"):
            raise BuildFailure("Docker archive manifest digest is invalid")
        manifest_hex = manifest_digest.split(":", 1)[1]
        manifest_path = f"blobs/sha256/{manifest_hex}"
        manifest_stream = archive.extractfile(manifest_path)
        if manifest_stream is None:
            raise BuildFailure("Docker archive OCI manifest is missing")
        manifest_bytes = manifest_stream.read()
        if hashlib.sha256(manifest_bytes).hexdigest() != manifest_hex:
            mismatches.append(manifest_path)
        manifest = json.loads(manifest_bytes)

        layers: list[str] = []
        for layer in manifest.get("layers") or []:
            digest = layer.get("digest")
            size = layer.get("size")
            if not isinstance(digest, str) or not digest.startswith("sha256:") or not isinstance(size, int):
                mismatches.append("manifest:invalid-layer-descriptor")
                continue
            layers.append(digest)
            member_name = f"blobs/sha256/{digest.split(':', 1)[1]}"
            try:
                member = archive.getmember(member_name)
            except KeyError:
                mismatches.append(member_name)
                continue
            layer_stream = archive.extractfile(member)
            if layer_stream is None:
                mismatches.append(member_name)
                continue
            h = hashlib.sha256()
            for chunk in iter(lambda: layer_stream.read(1024 * 1024), b""):
                h.update(chunk)
            if f"sha256:{h.hexdigest()}" != digest or member.size != size:
                mismatches.append(member_name)

        expected_layers = [f"blobs/sha256/{value.split(':', 1)[1]}" for value in layers]
        if row.get("Layers") != expected_layers:
            mismatches.append("manifest.json:Layers")

    runtime = config.get("config") or {}
    labels = runtime.get("Labels") or {}
    return {
        "schema": "edits.ociArchiveInspection.v1",
        "format": "docker-archive+oci-descriptors",
        "archive": path.name,
        "archiveSha256": "sha256:" + sha256_file(path),
        "archiveBytes": path.stat().st_size,
        "imageRef": tags[0],
        "imageId": f"sha256:{config_hex}",
        "configDigest": f"sha256:{config_hex}",
        "manifestDigest": manifest_digest,
        "layerDigests": layers,
        "entrypoint": runtime.get("Entrypoint"),
        "workingDir": runtime.get("WorkingDir"),
        "user": runtime.get("User"),
        "exposedPorts": len(runtime.get("ExposedPorts") or {}),
        "labels": labels,
        "digestMismatches": mismatches,
        "status": "PASS" if not mismatches else "FAIL",
    }


def inspect_oci_archive(path: pathlib.Path) -> dict[str, Any]:
    mismatches: list[str] = []
    with tarfile.open(path, "r:*") as archive:
        index = tar_json(archive, "index.json")
        descriptors = index.get("manifests") or []
        if len(descriptors) != 1:
            raise BuildFailure("OCI archive index must contain exactly one manifest")
        descriptor = descriptors[0]
        manifest_digest = descriptor.get("digest")
        if not isinstance(manifest_digest, str) or not manifest_digest.startswith("sha256:"):
            raise BuildFailure("OCI archive manifest digest is invalid")
        manifest_hex = manifest_digest.split(":", 1)[1]
        manifest_path = f"blobs/sha256/{manifest_hex}"
        manifest_stream = archive.extractfile(manifest_path)
        if manifest_stream is None:
            raise BuildFailure("OCI manifest blob is missing")
        manifest_bytes = manifest_stream.read()
        if hashlib.sha256(manifest_bytes).hexdigest() != manifest_hex:
            mismatches.append(manifest_path)
        manifest = json.loads(manifest_bytes)

        config_descriptor = manifest.get("config") or {}
        config_digest = config_descriptor.get("digest")
        config_size = config_descriptor.get("size")
        if not isinstance(config_digest, str) or not config_digest.startswith("sha256:") or not isinstance(config_size, int):
            raise BuildFailure("OCI config descriptor is invalid")
        config_path = f"blobs/sha256/{config_digest.split(':', 1)[1]}"
        config_member = archive.getmember(config_path)
        config_stream = archive.extractfile(config_member)
        if config_stream is None:
            raise BuildFailure("OCI config blob is missing")
        config_bytes = config_stream.read()
        if f"sha256:{hashlib.sha256(config_bytes).hexdigest()}" != config_digest or config_member.size != config_size:
            mismatches.append(config_path)
        config = json.loads(config_bytes)

        layers: list[str] = []
        for layer in manifest.get("layers") or []:
            digest = layer.get("digest")
            size = layer.get("size")
            if not isinstance(digest, str) or not digest.startswith("sha256:") or not isinstance(size, int):
                mismatches.append("manifest:invalid-layer-descriptor")
                continue
            layers.append(digest)
            member_name = f"blobs/sha256/{digest.split(':', 1)[1]}"
            try:
                member = archive.getmember(member_name)
            except KeyError:
                mismatches.append(member_name)
                continue
            layer_stream = archive.extractfile(member)
            if layer_stream is None:
                mismatches.append(member_name)
                continue
            h = hashlib.sha256()
            for chunk in iter(lambda: layer_stream.read(1024 * 1024), b""):
                h.update(chunk)
            if f"sha256:{h.hexdigest()}" != digest or member.size != size:
                mismatches.append(member_name)

    runtime = config.get("config") or {}
    annotations = descriptor.get("annotations") or {}
    return {
        "schema": "edits.ociArchiveInspection.v1",
        "format": "oci-archive",
        "archive": path.name,
        "archiveSha256": "sha256:" + sha256_file(path),
        "archiveBytes": path.stat().st_size,
        "imageRef": annotations.get("org.opencontainers.image.ref.name") or annotations.get("io.containerd.image.name"),
        "imageId": config_digest,
        "configDigest": config_digest,
        "manifestDigest": manifest_digest,
        "layerDigests": layers,
        "entrypoint": runtime.get("Entrypoint"),
        "workingDir": runtime.get("WorkingDir"),
        "user": runtime.get("User"),
        "exposedPorts": len(runtime.get("ExposedPorts") or {}),
        "labels": runtime.get("Labels") or {},
        "digestMismatches": mismatches,
        "status": "PASS" if not mismatches else "FAIL",
    }


def nix_build(
    *,
    repo: pathlib.Path,
    flake: pathlib.Path,
    source_url: str,
    attribute: str,
    log_dir: pathlib.Path,
    offline: bool = False,
    rebuild: bool = False,
) -> pathlib.Path:
    command = [
        resolve_tool("nix"),
        "--extra-experimental-features",
        "nix-command flakes",
        "build",
        "--no-write-lock-file",
        "--no-link",
        "--print-out-paths",
    ]
    if offline:
        command.append("--offline")
    if rebuild:
        command.append("--rebuild")
    command.extend(
        [
            f"{flake}#{attribute}",
            "--override-input",
            "editsSource",
            source_url,
        ]
    )
    label = "nix-" + ("offline-" if offline else "") + ("rebuild-" if rebuild else "") + attribute
    result = run(command, cwd=repo, log_dir=log_dir, label=label, timeout=2 * 60 * 60)
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


def stable_zip(source_roots: Iterable[pathlib.Path], destination: pathlib.Path) -> None:
    with zipfile.ZipFile(destination, "w", compression=zipfile.ZIP_DEFLATED, compresslevel=9) as archive:
        for root in source_roots:
            if not root.exists():
                continue
            for path in sorted(root.rglob("*")):
                if not path.is_file():
                    continue
                relative = pathlib.PurePosixPath(root.name) / path.relative_to(root).as_posix()
                info = zipfile.ZipInfo(str(relative), FIXED_ZIP_TIME)
                info.create_system = 3
                info.external_attr = (stat.S_IFREG | (path.stat().st_mode & 0o777)) << 16
                info.compress_type = zipfile.ZIP_DEFLATED
                archive.writestr(info, path.read_bytes(), compress_type=zipfile.ZIP_DEFLATED, compresslevel=9)
        bad = archive.testzip()
        if bad is not None:
            raise BuildFailure(f"ZIP CRC failure: {bad}")


def release_asset(path: pathlib.Path) -> dict[str, object]:
    return {
        "name": path.name,
        "bytes": path.stat().st_size,
        "sha256": "sha256:" + sha256_file(path),
    }


def write_checksums(root: pathlib.Path) -> None:
    rows = [
        f"{sha256_file(path)}  {path.name}"
        for path in sorted(root.iterdir())
        if path.is_file() and path.name != "SHA256SUMS"
    ]
    (root / "SHA256SUMS").write_text("\n".join(rows) + "\n", encoding="utf-8")


def assert_junit_green(path: pathlib.Path) -> dict[str, int]:
    root = ET.parse(path).getroot()
    suites = [root] if root.tag == "testsuite" else list(root.findall("testsuite"))
    counts = {
        name: sum(int(suite.attrib.get(name, "0")) for suite in suites)
        for name in ("tests", "failures", "errors", "skipped")
    }
    if counts["tests"] < 1 or any(counts[name] for name in ("failures", "errors", "skipped")):
        raise BuildFailure(f"pytest JUnit is not strictly Green: {counts}")
    return counts


def run_pytest(
    *,
    repo: pathlib.Path,
    paths: Sequence[pathlib.Path],
    junit: pathlib.Path,
    env: Mapping[str, str],
) -> dict[str, int]:
    previous = {key: os.environ.get(key) for key in env}
    os.environ.update(env)
    try:
        status = pytest.main(
            [
                "-q",
                "-ra",
                "--strict-markers",
                f"--junitxml={junit}",
                *(str(path) for path in paths),
            ]
        )
    finally:
        for key, value in previous.items():
            if value is None:
                os.environ.pop(key, None)
            else:
                os.environ[key] = value
    if status != pytest.ExitCode.OK:
        raise BuildFailure(f"pytest failed with exit code {status}")
    return assert_junit_green(junit)


def source_bundle(repo: pathlib.Path, output: pathlib.Path, commit: str, suffix: str, log_dir: pathlib.Path) -> pathlib.Path:
    git = resolve_tool("git")
    temporary_ref = f"refs/heads/release/edits-candidate-{suffix}-{uuid.uuid4().hex[:8]}"
    target = output / f"edits-source-{suffix}.git.bundle"
    run([git, "update-ref", temporary_ref, commit], cwd=repo, log_dir=log_dir, label="git-release-ref-create")
    try:
        run([git, "bundle", "create", str(target), temporary_ref], cwd=repo, log_dir=log_dir, label="git-bundle-create")
        run([git, "bundle", "verify", str(target)], cwd=repo, log_dir=log_dir, label="git-bundle-verify")
    finally:
        run([git, "update-ref", "-d", temporary_ref], cwd=repo, log_dir=log_dir, label="git-release-ref-delete")
    return target


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Build and prove one release-ready edits OCI candidate.")
    parser.add_argument("--repo-root", type=pathlib.Path, required=True)
    parser.add_argument("--output", type=pathlib.Path, required=True)
    parser.add_argument("--release-tag", default="")
    parser.add_argument("--plan-only", action="store_true")
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    repo = args.repo_root.resolve()
    output = args.output.resolve()
    flake = repo / "proofs/vim-nix"
    tests = flake / "tests"
    canon_tests = repo / "proofs/issue-118/wt05a-ci-release/tests/test_candidate_ci_release.py"
    unit_tests = tests / "test_candidate_archive_unit.py"
    if not (flake / "flake.nix").is_file() or not tests.is_dir() or not canon_tests.is_file() or not unit_tests.is_file():
        raise BuildFailure("candidate flake, Canon RED, or pytest suite is missing")

    identity = source_identity(repo)
    if output.exists():
        shutil.rmtree(output)
    output.mkdir(parents=True)
    log_dir = output / "logs"
    evidence_dir = output / "evidence"
    evidence_dir.mkdir()
    write_json(
        evidence_dir / "source.json",
        {
            "repository": "roccho-dev/edits",
            "commit": identity.commit,
            "tree": identity.tree,
            "branch": identity.branch,
            "commitCount": identity.commit_count,
            "clean": True,
        },
    )

    plan_junit = evidence_dir / "pytest-plan.xml"
    plan_counts = run_pytest(
        repo=repo,
        paths=[canon_tests, unit_tests],
        junit=plan_junit,
        env={"EDITS_REPO": str(repo)},
    )
    if args.plan_only:
        manifest = {
            "schema": "edits.candidateRelease.v1",
            "status": "PLAN_PASS",
            "source": {
                "commit": identity.commit,
                "tree": identity.tree,
                "branch": identity.branch,
                "commitCount": identity.commit_count,
                "clean": True,
            },
            "buildEntrypoint": "nix run ./proofs/vim-nix#candidate",
            "pytest": plan_counts,
        }
        write_json(output / "release-manifest.json", manifest)
        write_checksums(output)
        print(json.dumps(manifest, indent=2, sort_keys=True))
        return 0

    for tool in ("nix", "git", "skopeo", "docker"):
        resolve_tool(tool)

    source_url = "git+" + repo.as_uri() + f"?rev={identity.commit}"
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
    for attribute in ("interactiveImage", "interactiveOciImage", "interactiveWindowsKit"):
        rebuilt = nix_build(
            repo=repo,
            flake=flake,
            source_url=source_url,
            attribute=attribute,
            log_dir=log_dir,
            rebuild=True,
        )
        if rebuilt != normal[attribute]:
            raise BuildFailure(f"Nix rebuild output path drift for {attribute}")
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

    docker_inspection = inspect_docker_archive(docker_tar)
    oci_inspection = inspect_oci_archive(oci_tar)
    if docker_inspection["status"] != "PASS":
        raise BuildFailure(f"Docker archive digest mismatch: {docker_inspection['digestMismatches']}")
    if oci_inspection["status"] != "PASS":
        raise BuildFailure(f"OCI archive digest mismatch: {oci_inspection['digestMismatches']}")
    if docker_inspection["imageRef"] != image_ref:
        raise BuildFailure("Docker archive tag differs from interactiveImageRef")
    if docker_inspection["configDigest"] != oci_inspection["configDigest"]:
        raise BuildFailure("Docker and OCI config digests differ")
    if docker_inspection["layerDigests"] != oci_inspection["layerDigests"]:
        raise BuildFailure("Docker and OCI layer digests differ")
    write_json(evidence_dir / "docker-archive.json", docker_inspection)
    write_json(evidence_dir / "oci-archive.json", oci_inspection)

    verify_oci = flake / "verify_oci.py"
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

    docker = resolve_tool("docker")
    skopeo = resolve_tool("skopeo")
    run([docker, "info"], cwd=repo, log_dir=log_dir, label="docker-info", timeout=120)
    oci_runtime_ref = f"roccho/edits:oci-{suffix}"
    run(
        [skopeo, "--insecure-policy", "copy", f"oci-archive:{oci_tar}", f"docker-daemon:{oci_runtime_ref}"],
        cwd=repo,
        log_dir=log_dir,
        label="skopeo-oci-to-docker",
        timeout=10 * 60,
    )

    build_manifest = {
        "schema": "edits.candidateBuild.v1",
        "status": "PASS",
        "source": {
            "repository": "roccho-dev/edits",
            "commit": identity.commit,
            "tree": identity.tree,
            "branch": identity.branch,
            "commitCount": identity.commit_count,
            "clean": True,
        },
        "nix": {
            "flake": "proofs/vim-nix",
            "flakeLockSha256": "sha256:" + lock_before,
            "sourceOverride": source_url,
            "normalOfflineSameOutputs": True,
            "rebuildVerified": True,
            "outputs": {key: str(value) for key, value in normal.items()},
        },
        "image": {
            "ref": image_ref,
            "ociRuntimeRef": oci_runtime_ref,
            "id": docker_inspection["imageId"],
            "configDigest": docker_inspection["configDigest"],
            "manifestDigest": docker_inspection["manifestDigest"],
            "layerDigests": docker_inspection["layerDigests"],
            "user": docker_inspection["user"],
            "entrypoint": docker_inspection["entrypoint"],
            "workingDir": docker_inspection["workingDir"],
            "exposedPorts": docker_inspection["exposedPorts"],
            "labels": docker_inspection["labels"],
        },
        "assets": {
            "docker": release_asset(docker_tar),
            "oci": release_asset(oci_tar),
            "windows": release_asset(windows_zip),
        },
        "releaseTag": args.release_tag or None,
    }
    write_json(output / "build-manifest.json", build_manifest)

    os.environ["EDITS_CANDIDATE_RELEASE_DIR"] = str(output)
    os.environ["EDITS_CANDIDATE_DOCKER_IMAGE_REF"] = image_ref
    os.environ["EDITS_CANDIDATE_OCI_IMAGE_REF"] = oci_runtime_ref
    os.environ["EDITS_CANDIDATE_SOURCE_COMMIT"] = identity.commit
    pytest_xml = output / "pytest.xml"
    full_counts = run_pytest(
        repo=repo,
        paths=[canon_tests, tests],
        junit=pytest_xml,
        env={
            "EDITS_REPO": str(repo),
            "EDITS_CANDIDATE_RELEASE_DIR": str(output),
            "EDITS_CANDIDATE_DOCKER_IMAGE_REF": image_ref,
            "EDITS_CANDIDATE_OCI_IMAGE_REF": oci_runtime_ref,
            "EDITS_CANDIDATE_SOURCE_COMMIT": identity.commit,
        },
    )

    bundle = source_bundle(repo, output, identity.commit, suffix, log_dir)
    e2e_report = {
        "schema": "edits.candidateE2E.v1",
        "status": "PASS",
        "sourceCommit": identity.commit,
        "sourceTree": identity.tree,
        "dockerImageRef": image_ref,
        "ociImageRef": oci_runtime_ref,
        "imageId": docker_inspection["imageId"],
        "runner": "pytest",
        "pytest": full_counts,
        "mandatorySkips": 0,
        "xfail": 0,
        "waivers": 0,
        "goldenTokens": [
            "EDITS_INTERACTIVE_PTY_SMOKE_PASS",
            "VIM_NIX_RUNTIME_E2E_PASS",
            "VIM_NIX_FULL_E2E_PASS",
            "VIM_NIX_ACCEPTED_HISTORY_E2E_PASS",
        ],
        "dockerArchiveE2E": "PASS",
        "ociArchiveE2E": "PASS",
        "windowsPhysicalWslc": "OPEN",
        "claim": "Linux CI built and exercised both Docker-imported and OCI-imported candidate images; the Windows ZIP is ready for direct download and physical WSLC readback.",
    }
    write_json(output / "e2e-report.json", e2e_report)
    evidence_zip = output / f"edits-operator-console-{suffix}.evidence.zip"
    stable_zip([log_dir, evidence_dir], evidence_zip)

    release_manifest = {
        "schema": "edits.candidateRelease.v1",
        "status": "PASS",
        "releaseTag": args.release_tag or None,
        "buildEntrypoint": "nix run ./proofs/vim-nix#candidate",
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
            "canonRedFixedGreen": "PASS",
            "nixNormalOfflineSameOutputs": "PASS",
            "nixRebuild": "PASS",
            "dockerArchiveIntegrity": "PASS",
            "ociArchiveIntegrity": "PASS",
            "dockerArchiveE2E": "PASS",
            "ociArchiveE2E": "PASS",
            "pytestE2E": "PASS",
            "windowsNoBuildKit": "PASS",
            "physicalWindowsWslc": "OPEN",
        },
        "nonGreenCounts": {
            "failed": 0,
            "errors": 0,
            "skipped": 0,
            "xfail": 0,
            "waivers": 0,
            "falseSuccess": 0,
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
                f"- Docker image: `{image_ref}`",
                f"- OCI runtime image: `{oci_runtime_ref}`",
                f"- image ID: `{docker_inspection['imageId']}`",
                "- Nix clean/offline/rebuild gates: **PASS**",
                "- Docker-imported pytest E2E: **PASS**",
                "- OCI-imported pytest E2E: **PASS**",
                "- physical Windows/WSLC readback: **OPEN**",
                "",
                "For Windows, download the `.windows.zip`, extract it, run `verify.cmd`, then `run.cmd`.",
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
    except (BuildFailure, subprocess.TimeoutExpired) as exc:
        print(f"candidate-ci: {exc}", file=sys.stderr)
        raise SystemExit(1)
