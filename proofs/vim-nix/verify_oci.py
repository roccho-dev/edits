#!/usr/bin/env python3
"""Fail-closed verifier for the proof OCI archive.

The OCI content digests are image identity. The outer tar digest is retained as
transport evidence and is not treated as semantic image identity.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import pathlib
import re
import tarfile
from typing import Any

DIGEST_RE = re.compile(r"^sha256:([0-9a-f]{64})$")


def fail(message: str) -> None:
    raise SystemExit(f"verify-oci: {message}")


def canonical_name(name: str) -> str:
    while name.startswith("./"):
        name = name[2:]
    p = pathlib.PurePosixPath(name)
    if p.is_absolute() or ".." in p.parts or "" in p.parts:
        fail(f"unsafe tar entry: {name!r}")
    return p.as_posix()


def sha256(data: bytes) -> str:
    return "sha256:" + hashlib.sha256(data).hexdigest()


def load_json(raw: bytes, label: str) -> Any:
    try:
        return json.loads(raw)
    except Exception as exc:  # noqa: BLE001 - proof CLI emits exact boundary
        fail(f"invalid {label}: {exc}")


def require_descriptor(files: dict[str, bytes], descriptor: dict[str, Any], label: str) -> bytes:
    digest = descriptor.get("digest")
    size = descriptor.get("size")
    if not isinstance(digest, str) or not DIGEST_RE.fullmatch(digest):
        fail(f"{label} digest is invalid")
    if not isinstance(size, int) or size < 0:
        fail(f"{label} size is invalid")
    path = "blobs/sha256/" + digest.removeprefix("sha256:")
    if path not in files:
        fail(f"{label} blob is missing: {path}")
    raw = files[path]
    if len(raw) != size:
        fail(f"{label} size mismatch: expected {size}, got {len(raw)}")
    if sha256(raw) != digest:
        fail(f"{label} digest mismatch")
    return raw


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("archive", type=pathlib.Path)
    ap.add_argument("--receipt", type=pathlib.Path, required=True)
    ap.add_argument("--expect-os", default="linux")
    ap.add_argument("--expect-arch", default="amd64")
    args = ap.parse_args()

    files: dict[str, bytes] = {}
    with tarfile.open(args.archive, "r:*") as tf:
        for member in tf.getmembers():
            name = canonical_name(member.name)
            if member.isdir():
                continue
            if not member.isfile():
                fail(f"non-regular OCI tar member: {name}")
            if name in files:
                fail(f"duplicate OCI tar member: {name}")
            stream = tf.extractfile(member)
            if stream is None:
                fail(f"cannot read OCI tar member: {name}")
            files[name] = stream.read()

    layout = load_json(files.get("oci-layout", b""), "oci-layout")
    if layout != {"imageLayoutVersion": "1.0.0"}:
        fail(f"unexpected OCI layout: {layout!r}")
    index = load_json(files.get("index.json", b""), "index.json")
    manifests = index.get("manifests") if isinstance(index, dict) else None
    if not isinstance(manifests, list) or len(manifests) != 1:
        fail("index must contain exactly one manifest")

    manifest_desc = manifests[0]
    if manifest_desc.get("mediaType") != "application/vnd.oci.image.manifest.v1+json":
        fail("unexpected manifest media type")
    manifest_raw = require_descriptor(files, manifest_desc, "manifest")
    manifest = load_json(manifest_raw, "manifest")
    if manifest.get("schemaVersion") != 2:
        fail("manifest schemaVersion must be 2")

    config_desc = manifest.get("config")
    layers = manifest.get("layers")
    if not isinstance(config_desc, dict) or not isinstance(layers, list) or not layers:
        fail("manifest config/layers are invalid")
    config_raw = require_descriptor(files, config_desc, "config")
    config = load_json(config_raw, "config")
    if config.get("os") != args.expect_os or config.get("architecture") != args.expect_arch:
        fail(
            f"platform mismatch: expected {args.expect_os}/{args.expect_arch}, "
            f"got {config.get('os')}/{config.get('architecture')}"
        )

    layer_rows: list[dict[str, Any]] = []
    for index_value, layer in enumerate(layers):
        if not isinstance(layer, dict):
            fail(f"layer {index_value} descriptor is invalid")
        require_descriptor(files, layer, f"layer {index_value}")
        layer_rows.append(
            {
                "digest": layer["digest"],
                "size": layer["size"],
                "mediaType": layer.get("mediaType"),
            }
        )

    receipt = {
        "schema": "edits.vim-nix-oci-verification/1",
        "status": "PASS",
        "archive": str(args.archive),
        "archiveBytes": args.archive.stat().st_size,
        "archiveSha256": sha256(args.archive.read_bytes()),
        "layoutVersion": layout["imageLayoutVersion"],
        "platform": {"os": config["os"], "architecture": config["architecture"]},
        "manifest": {"digest": manifest_desc["digest"], "size": manifest_desc["size"]},
        "config": {"digest": config_desc["digest"], "size": config_desc["size"]},
        "layers": layer_rows,
        "entrypoint": config.get("config", {}).get("Entrypoint"),
        "command": config.get("config", {}).get("Cmd"),
    }
    args.receipt.parent.mkdir(parents=True, exist_ok=True)
    args.receipt.write_text(json.dumps(receipt, indent=2, sort_keys=True) + "\n")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
