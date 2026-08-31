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


def load(name: str, path: Path):
    spec = importlib.util.spec_from_file_location(name, path)
    assert spec and spec.loader
    module = importlib.util.module_from_spec(spec)
    sys.modules[spec.name] = module
    spec.loader.exec_module(module)
    return module


CANDIDATE = load("edits_candidate_ci_docker_save", REPO / "proofs/vim-nix/candidate_ci.py")
WINDOWS = load("edits_windows_kit_docker_save", REPO / "proofs/vim-nix/windows_kit.py")


def add(archive: tarfile.TarFile, name: str, data: bytes) -> None:
    info = tarfile.TarInfo(name)
    info.size = len(data)
    info.mode = 0o444
    info.mtime = 1
    archive.addfile(info, io.BytesIO(data))


def make_docker_save(
    path: Path,
    *,
    corrupt_config: bool = False,
    corrupt_layer: bool = False,
) -> tuple[str, str]:
    layer = b"standard-docker-save-layer"
    layer_digest = hashlib.sha256(layer).hexdigest()
    config = {
        "config": {
            "Entrypoint": ["/bin/edits"],
            "WorkingDir": "/work/repos",
            "User": "1000:1000",
            "Labels": {"roccho.edits.product-role": "ops-operator-console"},
        },
        "rootfs": {"type": "layers", "diff_ids": [f"sha256:{layer_digest}"]},
    }
    config_bytes = CANDIDATE.canonical_json(config)
    config_digest = hashlib.sha256(config_bytes).hexdigest()
    config_payload = bytearray(config_bytes)
    if corrupt_config:
        config_payload[len(config_payload) // 2] ^= 1
    layer_payload = b"tampered-layer" if corrupt_layer else layer
    manifest = [
        {
            "Config": f"{config_digest}.json",
            "RepoTags": ["roccho/edits:test"],
            "Layers": [f"{layer_digest}/layer.tar"],
        }
    ]
    with tarfile.open(path, "w") as archive:
        add(archive, "manifest.json", CANDIDATE.canonical_json(manifest))
        add(archive, f"{config_digest}.json", bytes(config_payload))
        add(archive, f"{layer_digest}/layer.tar", layer_payload)
    return config_digest, layer_digest


def test_candidate_accepts_nixpkgs_standard_docker_save(tmp_path: Path) -> None:
    archive = tmp_path / "candidate.docker.tar"
    config_digest, layer_digest = make_docker_save(archive)

    receipt = CANDIDATE.inspect_docker_archive(archive)

    assert receipt["status"] == "PASS"
    assert receipt["format"] == "docker-save"
    assert receipt["imageId"] == f"sha256:{config_digest}"
    assert receipt["configDigest"] == f"sha256:{config_digest}"
    assert receipt["layerDigests"] == [f"sha256:{layer_digest}"]
    assert receipt["rootfsDiffIds"] == receipt["layerDigests"]
    assert receipt["archiveLayerDigests"] == receipt["layerDigests"]
    assert receipt["digestMismatches"] == []


def test_windows_kit_accepts_nixpkgs_standard_docker_save(tmp_path: Path) -> None:
    archive = tmp_path / "candidate.docker.tar"
    config_digest, _ = make_docker_save(archive)

    image_id, parsed = WINDOWS.docker_identity(archive)

    assert image_id == f"sha256:{config_digest}"
    assert parsed["manifest"]["RepoTags"] == ["roccho/edits:test"]


def test_windows_kit_rejects_tampered_config(tmp_path: Path) -> None:
    archive = tmp_path / "candidate.docker.tar"
    make_docker_save(archive, corrupt_config=True)

    try:
        WINDOWS.docker_identity(archive)
    except SystemExit as exc:
        assert "config digest mismatch" in str(exc)
    else:
        raise AssertionError("tampered Docker config must be rejected")


def test_candidate_rejects_tampered_layer(tmp_path: Path) -> None:
    archive = tmp_path / "candidate.docker.tar"
    make_docker_save(archive, corrupt_layer=True)

    receipt = CANDIDATE.inspect_docker_archive(archive)

    assert receipt["status"] == "FAIL"
    assert receipt["digestMismatches"]
