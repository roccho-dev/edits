from __future__ import annotations

import hashlib
import importlib.util
import io
import json
import os
from pathlib import Path
import sys
import tarfile

import pytest


REPO = Path(os.environ.get("EDITS_REPO", Path(__file__).resolve().parents[3])).resolve()
MODULE_PATH = REPO / "proofs" / "vim-nix" / "normalize_oci_layout.py"
SPEC = importlib.util.spec_from_file_location("edits_normalize_oci_layout", MODULE_PATH)
assert SPEC and SPEC.loader
MODULE = importlib.util.module_from_spec(SPEC)
sys.modules[SPEC.name] = MODULE
SPEC.loader.exec_module(MODULE)


def canonical_json(value) -> bytes:
    return json.dumps(value, sort_keys=True, separators=(",", ":")).encode("utf-8")


def sha256(value: bytes) -> str:
    return hashlib.sha256(value).hexdigest()


def add_tar(archive: tarfile.TarFile, name: str, payload: bytes) -> None:
    info = tarfile.TarInfo(name)
    info.size = len(payload)
    info.mode = 0o444
    info.mtime = 1
    archive.addfile(info, io.BytesIO(payload))


def image_config(*, utc_suffix: str, user: str = "1000:1000") -> dict[str, object]:
    return {
        "architecture": "amd64",
        "os": "linux",
        "created": "1970-01-01T00:00:01" + utc_suffix,
        "config": {
            "Entrypoint": ["/bin/edits"],
            "WorkingDir": "/work/repos",
            "User": user,
            "Labels": {"roccho.edits.product-role": "ops-operator-console"},
        },
        "history": [
            {
                "created": "1970-01-01T00:00:01" + utc_suffix,
                "created_by": "nix",
            }
        ],
        "rootfs": {"type": "layers", "diff_ids": ["sha256:" + "a" * 64]},
    }


def make_docker_archive(path: Path, config: dict[str, object]) -> bytes:
    config_bytes = canonical_json(config)
    config_hex = sha256(config_bytes)
    manifest = [{"Config": f"{config_hex}.json", "RepoTags": ["roccho/edits:test"], "Layers": []}]
    with tarfile.open(path, "w") as archive:
        add_tar(archive, "manifest.json", canonical_json(manifest))
        add_tar(archive, f"{config_hex}.json", config_bytes)
    return config_bytes


def write_blob(layout: Path, payload: bytes) -> str:
    digest = sha256(payload)
    target = layout / "blobs" / "sha256" / digest
    target.parent.mkdir(parents=True, exist_ok=True)
    target.write_bytes(payload)
    return f"sha256:{digest}"


def make_oci_layout(path: Path, config: dict[str, object]) -> tuple[bytes, bytes]:
    path.mkdir()
    (path / "oci-layout").write_bytes(canonical_json({"imageLayoutVersion": "1.0.0"}))
    config_bytes = canonical_json(config)
    config_digest = write_blob(path, config_bytes)
    manifest = {
        "schemaVersion": 2,
        "config": {
            "mediaType": "application/vnd.oci.image.config.v1+json",
            "digest": config_digest,
            "size": len(config_bytes),
        },
        "layers": [],
    }
    manifest_bytes = canonical_json(manifest)
    manifest_digest = write_blob(path, manifest_bytes)
    index = {
        "schemaVersion": 2,
        "manifests": [
            {
                "mediaType": "application/vnd.oci.image.manifest.v1+json",
                "digest": manifest_digest,
                "size": len(manifest_bytes),
                "annotations": {"org.opencontainers.image.ref.name": "test"},
            }
        ],
    }
    (path / "index.json").write_bytes(canonical_json(index) + b"\n")
    return config_bytes, manifest_bytes


def indexed_config(layout: Path) -> tuple[bytes, dict[str, object], dict[str, object]]:
    index = json.loads((layout / "index.json").read_text(encoding="utf-8"))
    descriptor = index["manifests"][0]
    manifest_hex = descriptor["digest"].split(":", 1)[1]
    manifest_bytes = (layout / "blobs" / "sha256" / manifest_hex).read_bytes()
    assert len(manifest_bytes) == descriptor["size"]
    manifest = json.loads(manifest_bytes)
    config_descriptor = manifest["config"]
    config_hex = config_descriptor["digest"].split(":", 1)[1]
    config_bytes = (layout / "blobs" / "sha256" / config_hex).read_bytes()
    assert len(config_bytes) == config_descriptor["size"]
    return config_bytes, manifest, index


def test_restores_exact_docker_config_after_equivalent_utc_rewrite(tmp_path: Path) -> None:
    docker = tmp_path / "candidate.docker.tar"
    layout = tmp_path / "oci-layout"
    docker_config_bytes = make_docker_archive(docker, image_config(utc_suffix="+00:00"))
    old_config_bytes, old_manifest_bytes = make_oci_layout(layout, image_config(utc_suffix="Z"))
    assert old_config_bytes != docker_config_bytes

    result = MODULE.normalize_layout(docker, layout)

    restored_config_bytes, manifest, index = indexed_config(layout)
    assert restored_config_bytes == docker_config_bytes
    assert result["configDigest"] == "sha256:" + sha256(docker_config_bytes)
    assert manifest["config"]["digest"] == result["configDigest"]
    assert index["manifests"][0]["digest"] == result["manifestDigest"]
    assert not (layout / "blobs" / "sha256" / sha256(old_config_bytes)).exists()
    assert not (layout / "blobs" / "sha256" / sha256(old_manifest_bytes)).exists()


def test_rejects_any_product_config_difference_and_leaves_index_unchanged(tmp_path: Path) -> None:
    docker = tmp_path / "candidate.docker.tar"
    layout = tmp_path / "oci-layout"
    make_docker_archive(docker, image_config(utc_suffix="+00:00", user="1000:1000"))
    make_oci_layout(layout, image_config(utc_suffix="Z", user="0:0"))
    before = (layout / "index.json").read_bytes()

    with pytest.raises(MODULE.NormalizationFailure, match="beyond UTC spelling"):
        MODULE.normalize_layout(docker, layout)

    assert (layout / "index.json").read_bytes() == before


def test_rejects_non_utc_timestamp_spelling(tmp_path: Path) -> None:
    docker = tmp_path / "candidate.docker.tar"
    layout = tmp_path / "oci-layout"
    make_docker_archive(docker, image_config(utc_suffix="+00:00"))
    config = image_config(utc_suffix="Z")
    config["created"] = "1970-01-01T01:00:01+01:00"
    make_oci_layout(layout, config)

    with pytest.raises(MODULE.NormalizationFailure, match="explicit UTC"):
        MODULE.normalize_layout(docker, layout)
