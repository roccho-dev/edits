from __future__ import annotations

import hashlib
import importlib.util
import io
import json
import os
from pathlib import Path
import sys
import tarfile


REPO = Path(os.environ.get("EDITS_REPO", Path(__file__).resolve().parents[3])).resolve()
MODULE_PATH = REPO / "proofs" / "vim-nix" / "candidate_ci.py"
SPEC = importlib.util.spec_from_file_location("edits_candidate_ci", MODULE_PATH)
assert SPEC and SPEC.loader
MODULE = importlib.util.module_from_spec(SPEC)
sys.modules[SPEC.name] = MODULE
SPEC.loader.exec_module(MODULE)


def add(archive: tarfile.TarFile, name: str, data: bytes) -> None:
    info = tarfile.TarInfo(name)
    info.size = len(data)
    info.mode = 0o444
    info.mtime = 1
    archive.addfile(info, io.BytesIO(data))


def payloads(*, corrupt_layer: bool = False) -> dict[str, bytes | str | list[str]]:
    layer = b"layer-bytes"
    layer_hex = hashlib.sha256(layer).hexdigest()
    config = {
        "config": {
            "Entrypoint": ["/bin/edits"],
            "WorkingDir": "/work/repos",
            "User": "1000:1000",
            "Labels": {"roccho.edits.product-role": "ops-operator-console"},
        },
        "rootfs": {"type": "layers", "diff_ids": [f"sha256:{layer_hex}"]},
    }
    config_bytes = MODULE.canonical_json(config)
    config_hex = hashlib.sha256(config_bytes).hexdigest()
    manifest = {
        "schemaVersion": 2,
        "config": {
            "mediaType": "application/vnd.oci.image.config.v1+json",
            "digest": f"sha256:{config_hex}",
            "size": len(config_bytes),
        },
        "layers": [
            {
                "mediaType": "application/vnd.oci.image.layer.v1.tar",
                "digest": f"sha256:{layer_hex}",
                "size": len(layer),
            }
        ],
    }
    manifest_bytes = MODULE.canonical_json(manifest)
    manifest_hex = hashlib.sha256(manifest_bytes).hexdigest()
    return {
        "layer": b"tampered" if corrupt_layer else layer,
        "layer_hex": layer_hex,
        "config": config_bytes,
        "config_hex": config_hex,
        "manifest": manifest_bytes,
        "manifest_hex": manifest_hex,
        "layers": [f"sha256:{layer_hex}"],
    }


def synthetic_docker(path: Path, *, corrupt_layer: bool = False) -> None:
    data = payloads(corrupt_layer=corrupt_layer)
    config_hex = data["config_hex"]
    manifest_hex = data["manifest_hex"]
    layer_hex = data["layer_hex"]
    docker_manifest = [
        {
            "Config": f"blobs/sha256/{config_hex}",
            "RepoTags": ["roccho/edits:test"],
            "Layers": [f"blobs/sha256/{layer_hex}"],
        }
    ]
    index = {
        "schemaVersion": 2,
        "manifests": [
            {
                "mediaType": "application/vnd.oci.image.manifest.v1+json",
                "digest": f"sha256:{manifest_hex}",
                "size": len(data["manifest"]),
            }
        ],
    }
    with tarfile.open(path, "w") as archive:
        add(archive, "manifest.json", MODULE.canonical_json(docker_manifest))
        add(archive, "index.json", MODULE.canonical_json(index))
        add(archive, f"blobs/sha256/{config_hex}", data["config"])
        add(archive, f"blobs/sha256/{manifest_hex}", data["manifest"])
        add(archive, f"blobs/sha256/{layer_hex}", data["layer"])


def synthetic_oci(path: Path, *, corrupt_layer: bool = False) -> None:
    data = payloads(corrupt_layer=corrupt_layer)
    config_hex = data["config_hex"]
    manifest_hex = data["manifest_hex"]
    layer_hex = data["layer_hex"]
    index = {
        "schemaVersion": 2,
        "manifests": [
            {
                "mediaType": "application/vnd.oci.image.manifest.v1+json",
                "digest": f"sha256:{manifest_hex}",
                "size": len(data["manifest"]),
                "annotations": {"org.opencontainers.image.ref.name": "roccho/edits:test"},
            }
        ],
    }
    with tarfile.open(path, "w") as archive:
        add(archive, "oci-layout", MODULE.canonical_json({"imageLayoutVersion": "1.0.0"}))
        add(archive, "index.json", MODULE.canonical_json(index))
        add(archive, f"blobs/sha256/{config_hex}", data["config"])
        add(archive, f"blobs/sha256/{manifest_hex}", data["manifest"])
        add(archive, f"blobs/sha256/{layer_hex}", data["layer"])


def test_docker_archive_inspection_accepts_complete_digest_bound_image(tmp_path: Path) -> None:
    archive = tmp_path / "candidate.docker.tar"
    synthetic_docker(archive)
    receipt = MODULE.inspect_docker_archive(archive)
    assert receipt["status"] == "PASS"
    assert receipt["digestMismatches"] == []
    assert receipt["entrypoint"] == ["/bin/edits"]
    assert receipt["workingDir"] == "/work/repos"
    assert receipt["user"] == "1000:1000"
    assert receipt["labels"]["roccho.edits.product-role"] == "ops-operator-console"


def test_oci_archive_inspection_accepts_same_config_and_layers(tmp_path: Path) -> None:
    docker = tmp_path / "candidate.docker.tar"
    oci = tmp_path / "candidate.oci.tar"
    synthetic_docker(docker)
    synthetic_oci(oci)
    docker_receipt = MODULE.inspect_docker_archive(docker)
    oci_receipt = MODULE.inspect_oci_archive(oci)
    assert oci_receipt["status"] == "PASS"
    assert docker_receipt["configDigest"] == oci_receipt["configDigest"]
    assert docker_receipt["layerDigests"] == oci_receipt["layerDigests"]


def test_docker_archive_inspection_marks_tampered_layer_non_green(tmp_path: Path) -> None:
    archive = tmp_path / "tampered.docker.tar"
    synthetic_docker(archive, corrupt_layer=True)
    receipt = MODULE.inspect_docker_archive(archive)
    assert receipt["status"] == "FAIL"
    assert len(receipt["digestMismatches"]) == 1


def test_oci_archive_inspection_marks_tampered_layer_non_green(tmp_path: Path) -> None:
    archive = tmp_path / "tampered.oci.tar"
    synthetic_oci(archive, corrupt_layer=True)
    receipt = MODULE.inspect_oci_archive(archive)
    assert receipt["status"] == "FAIL"
    assert len(receipt["digestMismatches"]) == 1
