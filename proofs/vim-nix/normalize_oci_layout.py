#!/usr/bin/env python3
"""Restore an OCI layout's image config to the exact source Docker config.

Skopeo may rewrite representation-equivalent RFC3339 UTC timestamps while
converting Docker-save to OCI. This command accepts only that narrow difference,
then rewrites the OCI config and manifest so both transports retain the exact
same image ID and product config.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import pathlib
import tarfile
from typing import Any, Mapping


class NormalizationFailure(RuntimeError):
    pass


def canonical_json(value: Any) -> bytes:
    return json.dumps(value, ensure_ascii=False, sort_keys=True, separators=(",", ":")).encode("utf-8")


def sha256_bytes(value: bytes) -> str:
    return hashlib.sha256(value).hexdigest()


def read_tar_member(archive: tarfile.TarFile, name: str) -> bytes:
    try:
        member = archive.getmember(name)
    except KeyError as exc:
        raise NormalizationFailure(f"Docker archive member is missing: {name}") from exc
    stream = archive.extractfile(member)
    if stream is None:
        raise NormalizationFailure(f"Docker archive member is unreadable: {name}")
    return stream.read()


def expected_docker_config_digest(path: str) -> str:
    pure = pathlib.PurePosixPath(path)
    if path.startswith("blobs/sha256/") and len(pure.name) == 64:
        return pure.name
    if pure.parent == pathlib.PurePosixPath(".") and pure.suffix == ".json" and len(pure.stem) == 64:
        return pure.stem
    raise NormalizationFailure("Docker archive config path is invalid")


def load_docker_config(path: pathlib.Path) -> tuple[bytes, dict[str, Any]]:
    with tarfile.open(path, "r:*") as archive:
        manifest = json.loads(read_tar_member(archive, "manifest.json"))
        if not isinstance(manifest, list) or len(manifest) != 1 or not isinstance(manifest[0], dict):
            raise NormalizationFailure("Docker archive must contain exactly one image")
        config_path = manifest[0].get("Config")
        if not isinstance(config_path, str):
            raise NormalizationFailure("Docker archive config path is missing")
        config_bytes = read_tar_member(archive, config_path)
        expected = expected_docker_config_digest(config_path)
        actual = sha256_bytes(config_bytes)
        if actual != expected:
            raise NormalizationFailure("Docker archive config digest mismatch")
        config = json.loads(config_bytes)
        if not isinstance(config, dict):
            raise NormalizationFailure("Docker image config must be an object")
        return config_bytes, config


def load_json(path: pathlib.Path, label: str) -> dict[str, Any]:
    try:
        value = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as exc:
        raise NormalizationFailure(f"{label} is unreadable") from exc
    if not isinstance(value, dict):
        raise NormalizationFailure(f"{label} must be an object")
    return value


def canonical_image_config(config: Mapping[str, Any]) -> dict[str, Any]:
    """Normalize only explicit UTC spelling (`+00:00` versus `Z`)."""
    normalized = json.loads(json.dumps(config))
    if not isinstance(normalized, dict):
        raise NormalizationFailure("Image config must be an object")

    scopes: list[tuple[str, dict[str, Any]]] = [("created", normalized)]
    history = normalized.get("history") or []
    if not isinstance(history, list):
        raise NormalizationFailure("Image config history must be an array")
    for index, row in enumerate(history):
        if not isinstance(row, dict):
            raise NormalizationFailure(f"Image config history[{index}] must be an object")
        scopes.append((f"history[{index}].created", row))

    for label, scope in scopes:
        if "created" not in scope:
            continue
        value = scope["created"]
        if not isinstance(value, str):
            raise NormalizationFailure(f"Image config {label} must be a string")
        if value.endswith("+00:00"):
            scope["created"] = value[:-6] + "Z"
        elif not value.endswith("Z"):
            raise NormalizationFailure(f"Image config {label} must use explicit UTC")
    return normalized


def checked_blob(layout: pathlib.Path, digest: str, size: int, label: str) -> tuple[pathlib.Path, bytes]:
    if not isinstance(digest, str) or not digest.startswith("sha256:"):
        raise NormalizationFailure(f"{label} digest is invalid")
    if not isinstance(size, int) or size < 0:
        raise NormalizationFailure(f"{label} size is invalid")
    hex_digest = digest.split(":", 1)[1]
    if len(hex_digest) != 64:
        raise NormalizationFailure(f"{label} digest is invalid")
    path = layout / "blobs" / "sha256" / hex_digest
    try:
        payload = path.read_bytes()
    except OSError as exc:
        raise NormalizationFailure(f"{label} blob is missing") from exc
    if len(payload) != size or sha256_bytes(payload) != hex_digest:
        raise NormalizationFailure(f"{label} blob integrity mismatch")
    return path, payload


def write_blob(layout: pathlib.Path, payload: bytes) -> tuple[pathlib.Path, str]:
    digest = sha256_bytes(payload)
    path = layout / "blobs" / "sha256" / digest
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_bytes(payload)
    return path, f"sha256:{digest}"


def normalize_layout(docker_archive: pathlib.Path, layout: pathlib.Path) -> dict[str, str]:
    if not (layout / "oci-layout").is_file():
        raise NormalizationFailure("OCI layout marker is missing")

    docker_config_bytes, docker_config = load_docker_config(docker_archive)
    index_path = layout / "index.json"
    index = load_json(index_path, "OCI index")
    descriptors = index.get("manifests") or []
    if not isinstance(descriptors, list) or len(descriptors) != 1 or not isinstance(descriptors[0], dict):
        raise NormalizationFailure("OCI index must contain exactly one manifest")
    descriptor = descriptors[0]

    old_manifest_path, old_manifest_bytes = checked_blob(
        layout,
        descriptor.get("digest"),
        descriptor.get("size"),
        "OCI manifest",
    )
    manifest = json.loads(old_manifest_bytes)
    if not isinstance(manifest, dict):
        raise NormalizationFailure("OCI manifest must be an object")
    config_descriptor = manifest.get("config")
    if not isinstance(config_descriptor, dict):
        raise NormalizationFailure("OCI config descriptor is missing")
    old_config_path, old_config_bytes = checked_blob(
        layout,
        config_descriptor.get("digest"),
        config_descriptor.get("size"),
        "OCI config",
    )
    oci_config = json.loads(old_config_bytes)
    if not isinstance(oci_config, dict):
        raise NormalizationFailure("OCI image config must be an object")

    if canonical_image_config(docker_config) != canonical_image_config(oci_config):
        raise NormalizationFailure("Docker and OCI image configs differ beyond UTC spelling")
    docker_diff_ids = (docker_config.get("rootfs") or {}).get("diff_ids")
    oci_diff_ids = (oci_config.get("rootfs") or {}).get("diff_ids")
    if not isinstance(docker_diff_ids, list) or docker_diff_ids != oci_diff_ids:
        raise NormalizationFailure("Docker and OCI rootfs identities differ")

    new_config_path, new_config_digest = write_blob(layout, docker_config_bytes)
    config_descriptor["digest"] = new_config_digest
    config_descriptor["size"] = len(docker_config_bytes)

    new_manifest_bytes = canonical_json(manifest)
    new_manifest_path, new_manifest_digest = write_blob(layout, new_manifest_bytes)
    descriptor["digest"] = new_manifest_digest
    descriptor["size"] = len(new_manifest_bytes)
    index_path.write_bytes(canonical_json(index) + b"\n")

    layer_paths = {
        layout / "blobs" / "sha256" / str(layer.get("digest", "")).removeprefix("sha256:")
        for layer in (manifest.get("layers") or [])
        if isinstance(layer, dict)
    }
    for obsolete in (old_config_path, old_manifest_path):
        if obsolete not in {new_config_path, new_manifest_path} and obsolete not in layer_paths:
            obsolete.unlink(missing_ok=True)

    return {
        "configDigest": new_config_digest,
        "manifestDigest": new_manifest_digest,
    }


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Restore an OCI layout to the exact source Docker image config.")
    parser.add_argument("--docker-archive", type=pathlib.Path, required=True)
    parser.add_argument("--oci-layout", type=pathlib.Path, required=True)
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    result = normalize_layout(args.docker_archive.resolve(), args.oci_layout.resolve())
    print(json.dumps(result, sort_keys=True))
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except NormalizationFailure as exc:
        print(f"normalize-oci-layout: {exc}")
        raise SystemExit(1)
