#!/usr/bin/env python3
"""Create one minimal OCI fixture, prove it, mutate one blob, and require rejection."""
from __future__ import annotations

import hashlib
import io
import json
import pathlib
import subprocess
import sys
import tarfile


def digest(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def add_tar(path: pathlib.Path, entries: dict[str, bytes]) -> None:
    with tarfile.open(path, "w") as archive:
        for name, data in entries.items():
            info = tarfile.TarInfo(name)
            info.size = len(data)
            info.mtime = 0
            info.uid = info.gid = 0
            info.mode = 0o644
            archive.addfile(info, io.BytesIO(data))


def main() -> int:
    if len(sys.argv) != 4:
        raise SystemExit("usage: oci-proof.py VERIFY_OCI WORK OUT")
    verifier, work, out = map(pathlib.Path, sys.argv[1:])
    evidence = out / "evidence"
    logs = out / "logs"

    config = json.dumps(
        {"architecture": "amd64", "os": "linux", "config": {"Cmd": ["/bin/true"]}},
        separators=(",", ":"),
    ).encode()
    layer_buffer = io.BytesIO()
    with tarfile.open(fileobj=layer_buffer, mode="w"):
        pass
    layer = layer_buffer.getvalue()
    config_digest, layer_digest = digest(config), digest(layer)
    manifest = json.dumps(
        {
            "schemaVersion": 2,
            "mediaType": "application/vnd.oci.image.manifest.v1+json",
            "config": {
                "mediaType": "application/vnd.oci.image.config.v1+json",
                "digest": "sha256:" + config_digest,
                "size": len(config),
            },
            "layers": [
                {
                    "mediaType": "application/vnd.oci.image.layer.v1.tar",
                    "digest": "sha256:" + layer_digest,
                    "size": len(layer),
                }
            ],
        },
        separators=(",", ":"),
    ).encode()
    manifest_digest = digest(manifest)
    index = json.dumps(
        {
            "schemaVersion": 2,
            "manifests": [
                {
                    "mediaType": "application/vnd.oci.image.manifest.v1+json",
                    "digest": "sha256:" + manifest_digest,
                    "size": len(manifest),
                    "platform": {"architecture": "amd64", "os": "linux"},
                }
            ],
        },
        separators=(",", ":"),
    ).encode()
    entries = {
        "oci-layout": b'{"imageLayoutVersion":"1.0.0"}\n',
        "index.json": index,
        "blobs/sha256/" + config_digest: config,
        "blobs/sha256/" + layer_digest: layer,
        "blobs/sha256/" + manifest_digest: manifest,
    }

    valid = work / "minimal.oci.tar"
    mutated = work / "minimal-mutated.oci.tar"
    add_tar(valid, entries)
    subprocess.run(
        [
            sys.executable,
            str(verifier),
            str(valid),
            "--receipt",
            str(evidence / "oci-positive.json"),
            "--expect-os",
            "linux",
            "--expect-arch",
            "amd64",
        ],
        check=True,
    )

    changed = dict(entries)
    name = "blobs/sha256/" + manifest_digest
    body = bytearray(changed[name])
    body[len(body) // 2] ^= 1
    changed[name] = bytes(body)
    add_tar(mutated, changed)
    negative = subprocess.run(
        [
            sys.executable,
            str(verifier),
            str(mutated),
            "--receipt",
            str(evidence / "oci-should-not-exist.json"),
        ],
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        text=True,
        check=False,
    )
    (logs / "oci-negative.log").write_text(negative.stdout, encoding="utf-8")
    if negative.returncode == 0:
        raise SystemExit("mutated OCI unexpectedly passed")
    (evidence / "oci-negative.txt").write_text("PASS: mutated OCI rejected\n", encoding="utf-8")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
