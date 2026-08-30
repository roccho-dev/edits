from __future__ import annotations

import hashlib
import io
import json
import os
import pathlib
import subprocess
import tarfile
import tempfile
import uuid
import zipfile

import pytest


@pytest.fixture(scope="session")
def release_dir() -> pathlib.Path:
    raw = os.environ.get("EDITS_CANDIDATE_RELEASE_DIR")
    assert raw, "EDITS_CANDIDATE_RELEASE_DIR is required"
    root = pathlib.Path(raw)
    assert root.is_dir()
    return root


@pytest.fixture(scope="session")
def build_manifest(release_dir: pathlib.Path) -> dict[str, object]:
    return json.loads((release_dir / "build-manifest.json").read_text(encoding="utf-8"))


@pytest.fixture(scope="session")
def image_ref(build_manifest: dict[str, object]) -> str:
    value = build_manifest["image"]["ref"]
    assert isinstance(value, str) and value.startswith("roccho/edits:git-")
    return value


@pytest.fixture(scope="session")
def docker_log_dir(release_dir: pathlib.Path) -> pathlib.Path:
    path = release_dir / "evidence" / "pytest-docker"
    path.mkdir(parents=True, exist_ok=True)
    return path


def run_command(
    command: list[str],
    *,
    log: pathlib.Path,
    check: bool = True,
) -> subprocess.CompletedProcess[str]:
    result = subprocess.run(
        command,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        check=False,
    )
    log.write_text("$ " + " ".join(command) + "\n" + result.stdout, encoding="utf-8")
    if check:
        assert result.returncode == 0, result.stdout
    return result


@pytest.fixture(scope="session")
def loaded_image(
    release_dir: pathlib.Path,
    build_manifest: dict[str, object],
    image_ref: str,
    docker_log_dir: pathlib.Path,
) -> str:
    docker = subprocess.run(["docker", "version"], stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True)
    assert docker.returncode == 0, docker.stdout
    docker_asset = pathlib.Path(build_manifest["assets"]["docker"]["name"])
    archive = release_dir / docker_asset
    load = run_command(
        ["docker", "load", "--input", str(archive)],
        log=docker_log_dir / "docker-load.log",
    )
    assert image_ref in load.stdout
    inspect = run_command(
        ["docker", "image", "inspect", image_ref],
        log=docker_log_dir / "docker-inspect.log",
    )
    rows = json.loads(inspect.stdout)
    assert len(rows) == 1
    assert rows[0]["Id"] == build_manifest["image"]["id"]
    yield image_ref
    subprocess.run(["docker", "image", "rm", "--force", image_ref], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)


def sha256_stream(stream) -> str:
    digest = hashlib.sha256()
    for block in iter(lambda: stream.read(1024 * 1024), b""):
        digest.update(block)
    return digest.hexdigest()


def docker_files(archive_path: pathlib.Path) -> set[str]:
    files: set[str] = set()
    with tarfile.open(archive_path, "r:*") as outer:
        manifest = json.load(outer.extractfile("manifest.json"))[0]
        for layer_name in manifest["Layers"]:
            layer_stream = outer.extractfile(layer_name)
            assert layer_stream is not None
            raw = layer_stream.read()
            with tarfile.open(fileobj=io.BytesIO(raw), mode="r:*") as layer:
                for member in layer.getmembers():
                    name = member.name.lstrip("./")
                    if not name:
                        continue
                    base = pathlib.PurePosixPath(name).name
                    if base.startswith(".wh."):
                        target = str(pathlib.PurePosixPath(name).with_name(base.removeprefix(".wh.")))
                        files.discard(target)
                    else:
                        files.add(name)
    return files


def test_build_contract_is_exact_and_clean(build_manifest: dict[str, object]) -> None:
    assert build_manifest["status"] == "PASS"
    source = build_manifest["source"]
    assert source["clean"] is True
    assert len(source["commit"]) == 40
    assert len(source["tree"]) == 40
    assert build_manifest["nix"]["normalOfflineSameOutputs"] is True
    assert build_manifest["nix"]["flake"] == "proofs/vim-nix"


def test_docker_archive_has_operator_console_contract(
    release_dir: pathlib.Path,
    build_manifest: dict[str, object],
) -> None:
    image = build_manifest["image"]
    assert image["entrypoint"] == ["/bin/edits"]
    assert image["user"] == "1000:1000"
    assert image["workingDir"] == "/work/repos"
    assert image["exposedPorts"] in ({}, None)
    docker_path = release_dir / build_manifest["assets"]["docker"]["name"]
    assert "sha256:" + sha256_stream(docker_path.open("rb")) == build_manifest["assets"]["docker"]["sha256"]


def test_role_entrypoints_and_legacy_providers_are_bundled(
    release_dir: pathlib.Path,
    build_manifest: dict[str, object],
) -> None:
    docker_path = release_dir / build_manifest["assets"]["docker"]["name"]
    files = docker_files(docker_path)
    required = {
        "bin/edits",
        "bin/edits-client",
        "bin/edits-service",
        "bin/edits-mux",
        "bin/edits-smoke",
        "bin/vim-nix-proof",
        "bin/vim-nix-history-proof",
        "bin/vim",
        "bin/hq",
        "bin/hq-worker",
        "bin/herdr",
    }
    assert required <= files
    assert "bin/edits-worker" not in files


def test_role_entrypoints_execute_exact_providers(
    loaded_image: str,
    docker_log_dir: pathlib.Path,
) -> None:
    service = run_command(
        ["docker", "run", "--rm", "--network", "none", "--entrypoint", "/bin/edits-service", loaded_image, "--help"],
        log=docker_log_dir / "edits-service-help.log",
    )
    assert "hq" in service.stdout.lower()
    client = run_command(
        ["docker", "run", "--rm", "--network", "none", "--entrypoint", "/bin/edits-client", loaded_image, "--version"],
        log=docker_log_dir / "edits-client-version.log",
    )
    assert "VIM - Vi IMproved 9.2" in client.stdout
    mux = run_command(
        ["docker", "run", "--rm", "--network", "none", "--entrypoint", "/bin/edits-mux", loaded_image, "--version"],
        log=docker_log_dir / "edits-mux-version.log",
    )
    assert mux.stdout.strip() == "herdr 0.8.0"


def test_interactive_product_smoke_matches_golden(
    loaded_image: str,
    docker_log_dir: pathlib.Path,
) -> None:
    result = run_command(
        ["docker", "run", "--rm", "--network", "none", "--entrypoint", "/bin/edits-smoke", loaded_image],
        log=docker_log_dir / "interactive-smoke.log",
    )
    assert "EDITS_INTERACTIVE_PTY_SMOKE_PASS" in result.stdout


def test_full_runtime_e2e_matches_golden(
    loaded_image: str,
    docker_log_dir: pathlib.Path,
) -> None:
    result = run_command(
        ["docker", "run", "--rm", "--network", "none", "--entrypoint", "/bin/vim-nix-proof", loaded_image, "all"],
        log=docker_log_dir / "full-runtime-e2e.log",
    )
    assert "VIM_NIX_EDITOR_E2E_PASS" in result.stdout
    assert "VIM_NIX_RUNTIME_E2E_PASS" in result.stdout
    assert "VIM_NIX_FULL_E2E_PASS" in result.stdout


def test_accepted_history_e2e_matches_golden(
    loaded_image: str,
    docker_log_dir: pathlib.Path,
) -> None:
    result = run_command(
        ["docker", "run", "--rm", "--network", "none", "--entrypoint", "/bin/vim-nix-history-proof", loaded_image],
        log=docker_log_dir / "accepted-history-e2e.log",
    )
    assert "VIM_NIX_ACCEPTED_HISTORY_E2E_PASS" in result.stdout


def test_named_volumes_preserve_home_and_workspace(
    loaded_image: str,
    docker_log_dir: pathlib.Path,
) -> None:
    token = uuid.uuid4().hex
    home_volume = f"edits-ci-home-{token}"
    work_volume = f"edits-ci-work-{token}"
    try:
        run_command(["docker", "volume", "create", home_volume], log=docker_log_dir / "volume-home-create.log")
        run_command(["docker", "volume", "create", work_volume], log=docker_log_dir / "volume-work-create.log")
        run_command(
            [
                "docker", "run", "--rm", "--network", "none",
                "--volume", f"{home_volume}:/home/dev",
                "--volume", f"{work_volume}:/work/repos",
                "--entrypoint", "/bin/sh", loaded_image, "-eu", "-c",
                f"printf '%s' '{token}' > /home/dev/.edits-ci; printf '%s' '{token}' > /work/repos/.edits-ci",
            ],
            log=docker_log_dir / "volume-write.log",
        )
        home = run_command(
            ["docker", "run", "--rm", "--network", "none", "--volume", f"{home_volume}:/home/dev", "--entrypoint", "/bin/cat", loaded_image, "/home/dev/.edits-ci"],
            log=docker_log_dir / "volume-home-read.log",
        )
        work = run_command(
            ["docker", "run", "--rm", "--network", "none", "--volume", f"{work_volume}:/work/repos", "--entrypoint", "/bin/cat", loaded_image, "/work/repos/.edits-ci"],
            log=docker_log_dir / "volume-work-read.log",
        )
        assert home.stdout == token
        assert work.stdout == token
    finally:
        subprocess.run(["docker", "volume", "rm", "--force", home_volume, work_volume], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)


def test_oci_archive_is_fail_closed_on_mutation(
    release_dir: pathlib.Path,
    build_manifest: dict[str, object],
    docker_log_dir: pathlib.Path,
) -> None:
    oci_path = release_dir / build_manifest["assets"]["oci"]["name"]
    verifier = pathlib.Path(__file__).resolve().parents[1] / "verify_oci.py"
    with tempfile.TemporaryDirectory(prefix="edits-oci-negative-") as raw:
        temp = pathlib.Path(raw)
        files: dict[str, tuple[tarfile.TarInfo, bytes]] = {}
        with tarfile.open(oci_path, "r:*") as archive:
            for member in archive.getmembers():
                if member.isdir():
                    files[member.name] = (member, b"")
                elif member.isfile():
                    stream = archive.extractfile(member)
                    assert stream is not None
                    files[member.name] = (member, stream.read())
        index = json.loads(files["index.json"][1])
        manifest_name = "blobs/sha256/" + index["manifests"][0]["digest"].removeprefix("sha256:")
        member, raw_manifest = files[manifest_name]
        mutated = bytearray(raw_manifest)
        mutated[len(mutated) // 2] ^= 1
        files[manifest_name] = (member, bytes(mutated))
        bad = temp / "mutated.oci.tar"
        with tarfile.open(bad, "w") as archive:
            for name in sorted(files):
                original, data = files[name]
                info = tarfile.TarInfo(name)
                info.mode = original.mode
                info.uid = original.uid
                info.gid = original.gid
                info.mtime = 0
                if original.isdir():
                    info.type = tarfile.DIRTYPE
                    archive.addfile(info)
                else:
                    info.size = len(data)
                    archive.addfile(info, io.BytesIO(data))
        result = run_command(
            ["python3", str(verifier), str(bad), "--receipt", str(temp / "must-not-exist.json")],
            log=docker_log_dir / "oci-mutated-rejection.log",
            check=False,
        )
        assert result.returncode != 0
        assert "digest mismatch" in result.stdout
        assert not (temp / "must-not-exist.json").exists()


def test_windows_zip_is_complete_no_build_delivery(
    release_dir: pathlib.Path,
    build_manifest: dict[str, object],
) -> None:
    windows_path = release_dir / build_manifest["assets"]["windows"]["name"]
    with zipfile.ZipFile(windows_path) as archive:
        names = set(archive.namelist())
        root = "edits-windows/"
        required = {
            root + "edits-operator-console.docker.tar",
            root + "manifest.json",
            root + "README.md",
            root + "verify.ps1",
            root + "run.ps1",
            root + "verify.cmd",
            root + "run.cmd",
            root + "SHA256SUMS",
        }
        assert required <= names
        manifest = json.loads(archive.read(root + "manifest.json"))
        assert manifest["status"] == "PASS"
        assert manifest["buildRequiredOnWindows"] is False
        assert manifest["registryRequired"] is False
        assert manifest["imageRef"] == build_manifest["image"]["ref"]
        assert manifest["imageId"] == build_manifest["image"]["id"]
        with archive.open(root + "edits-operator-console.docker.tar") as stream:
            embedded_digest = sha256_stream(stream)
        assert "sha256:" + embedded_digest == build_manifest["assets"]["docker"]["sha256"]
        run_ps1 = archive.read(root + "run.ps1").decode("utf-8")
        assert "wslc load -i" not in run_ps1  # invocation uses argument array, not a reparsed shell string
        assert "& $Wslc load -i $Archive" in run_ps1
        assert "dev-home:/home/dev" in run_ps1
        assert "repos:/work/repos" in run_ps1
        assert build_manifest["image"]["id"] in run_ps1
