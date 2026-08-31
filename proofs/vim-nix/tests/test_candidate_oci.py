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
def image_refs(build_manifest: dict[str, object]) -> dict[str, str]:
    docker_ref = os.environ.get("EDITS_CANDIDATE_DOCKER_IMAGE_REF")
    oci_ref = os.environ.get("EDITS_CANDIDATE_OCI_IMAGE_REF")
    assert docker_ref == build_manifest["image"]["ref"]
    assert oci_ref == build_manifest["image"]["ociRuntimeRef"]
    assert docker_ref.startswith("roccho/edits:git-")
    assert oci_ref.startswith("roccho/edits:oci-")
    return {"docker": docker_ref, "oci": oci_ref}


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
    timeout: int = 1800,
) -> subprocess.CompletedProcess[str]:
    result = subprocess.run(
        command,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        check=False,
        timeout=timeout,
    )
    log.parent.mkdir(parents=True, exist_ok=True)
    log.write_text(
        "$ " + " ".join(command)
        + "\n\n[stdout]\n" + result.stdout
        + "\n[stderr]\n" + result.stderr,
        encoding="utf-8",
    )
    if check:
        assert result.returncode == 0, result.stdout + result.stderr
    return result


@pytest.fixture(scope="session")
def loaded_images(
    release_dir: pathlib.Path,
    build_manifest: dict[str, object],
    image_refs: dict[str, str],
    docker_log_dir: pathlib.Path,
) -> dict[str, str]:
    docker = run_command(["docker", "version"], log=docker_log_dir / "docker-version.log")
    assert docker.returncode == 0
    archive = release_dir / build_manifest["assets"]["docker"]["name"]
    loaded = run_command(
        ["docker", "load", "--input", str(archive)],
        log=docker_log_dir / "docker-load.log",
        timeout=600,
    )
    assert image_refs["docker"] in loaded.stdout + loaded.stderr
    for lane, image in image_refs.items():
        inspected = run_command(
            ["docker", "image", "inspect", image],
            log=docker_log_dir / f"{lane}-inspect.log",
        )
        rows = json.loads(inspected.stdout)
        assert len(rows) == 1
        assert rows[0]["Id"] == build_manifest["image"]["id"]
    yield image_refs
    for image in image_refs.values():
        subprocess.run(
            ["docker", "image", "rm", "--force", image],
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
            check=False,
        )


@pytest.fixture(params=("docker", "oci"))
def image_case(request: pytest.FixtureRequest, loaded_images: dict[str, str]) -> tuple[str, str]:
    lane = str(request.param)
    return lane, loaded_images[lane]


def sha256_stream(stream) -> str:
    digest = hashlib.sha256()
    for block in iter(lambda: stream.read(1024 * 1024), b""):
        digest.update(block)
    return digest.hexdigest()


def docker_files(archive_path: pathlib.Path) -> set[str]:
    files: set[str] = set()
    with tarfile.open(archive_path, "r:*") as outer:
        manifest_stream = outer.extractfile("manifest.json")
        assert manifest_stream is not None
        manifest = json.load(manifest_stream)[0]
        for layer_name in manifest["Layers"]:
            layer_stream = outer.extractfile(layer_name)
            assert layer_stream is not None
            with tarfile.open(fileobj=io.BytesIO(layer_stream.read()), mode="r:*") as layer:
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
    assert source["commitCount"] > 0
    nix = build_manifest["nix"]
    assert nix["normalOfflineSameOutputs"] is True
    assert nix["rebuildVerified"] is True
    assert nix["sourceOverride"].endswith("?rev=" + source["commit"])


def test_docker_archive_has_operator_console_contract(
    release_dir: pathlib.Path,
    build_manifest: dict[str, object],
) -> None:
    image = build_manifest["image"]
    assert image["entrypoint"] == ["/bin/edits"]
    assert image["workingDir"] == "/work/repos"
    assert image["user"] == "1000:1000"
    assert image["exposedPorts"] == 0
    assert image["labels"]["roccho.edits.product-role"] == "ops-operator-console"
    assert image["labels"]["roccho.edits.build-entrypoint"] == "nix run ./proofs/vim-nix#candidate"
    docker_tar = release_dir / build_manifest["assets"]["docker"]["name"]
    assert "sha256:" + hashlib.sha256(docker_tar.read_bytes()).hexdigest() == build_manifest["assets"]["docker"]["sha256"]


def test_docker_and_oci_archives_bind_same_config_and_layers(
    build_manifest: dict[str, object],
    release_dir: pathlib.Path,
) -> None:
    docker_receipt = json.loads((release_dir / "evidence/docker-archive.json").read_text(encoding="utf-8"))
    oci_receipt = json.loads((release_dir / "evidence/oci-archive.json").read_text(encoding="utf-8"))
    assert docker_receipt["status"] == "PASS"
    assert oci_receipt["status"] == "PASS"
    assert docker_receipt["digestMismatches"] == []
    assert oci_receipt["digestMismatches"] == []
    assert docker_receipt["configDigest"] == oci_receipt["configDigest"] == build_manifest["image"]["configDigest"]
    assert docker_receipt["layerDigests"] == oci_receipt["layerDigests"] == build_manifest["image"]["layerDigests"]


def test_role_entrypoints_and_legacy_providers_are_bundled(
    release_dir: pathlib.Path,
    build_manifest: dict[str, object],
) -> None:
    archive = release_dir / build_manifest["assets"]["docker"]["name"]
    files = docker_files(archive)
    required = {
        "bin/edits",
        "bin/edits-client",
        "bin/edits-service",
        "bin/edits-mux",
        "bin/vim",
        "bin/hq",
        "bin/herdr",
        "bin/edits-smoke",
        "bin/vim-nix-proof",
        "bin/vim-nix-history-proof",
    }
    assert required <= files
    assert "bin/edits-worker" not in files


def test_runtime_images_have_same_product_contract(
    loaded_images: dict[str, str],
    docker_log_dir: pathlib.Path,
) -> None:
    inspected = []
    for lane, image in loaded_images.items():
        result = run_command(
            ["docker", "image", "inspect", image],
            log=docker_log_dir / f"{lane}-contract-inspect.log",
        )
        row = json.loads(result.stdout)[0]
        inspected.append(row)
        config = row["Config"]
        assert config["Entrypoint"] == ["/bin/edits"]
        assert config["WorkingDir"] == "/work/repos"
        assert config["User"] == "1000:1000"
        assert not config.get("ExposedPorts")
        assert config["Labels"]["roccho.edits.product-role"] == "ops-operator-console"
    assert inspected[0]["Id"] == inspected[1]["Id"]
    assert inspected[0]["RootFS"]["Layers"] == inspected[1]["RootFS"]["Layers"]


def test_role_entrypoints_execute_exact_providers(
    image_case: tuple[str, str],
    docker_log_dir: pathlib.Path,
) -> None:
    lane, image = image_case
    service = run_command(
        ["docker", "run", "--rm", "--network", "none", "--entrypoint", "/bin/edits-service", image, "--help"],
        log=docker_log_dir / lane / "edits-service-help.log",
    )
    assert "hq" in (service.stdout + service.stderr).lower()
    client = run_command(
        ["docker", "run", "--rm", "--network", "none", "--entrypoint", "/bin/edits-client", image, "--version"],
        log=docker_log_dir / lane / "edits-client-version.log",
    )
    assert "VIM - Vi IMproved 9.2" in client.stdout
    mux = run_command(
        ["docker", "run", "--rm", "--network", "none", "--entrypoint", "/bin/edits-mux", image, "--version"],
        log=docker_log_dir / lane / "edits-mux-version.log",
    )
    assert "herdr 0.8.0" in (mux.stdout + mux.stderr).lower()


def test_interactive_product_smoke_matches_golden(
    image_case: tuple[str, str],
    docker_log_dir: pathlib.Path,
) -> None:
    lane, image = image_case
    result = run_command(
        ["docker", "run", "--rm", "--network", "none", "--name", f"edits-smoke-{lane}-{uuid.uuid4().hex[:8]}", "--entrypoint", "/bin/edits-smoke", image],
        log=docker_log_dir / lane / "interactive-smoke.log",
    )
    assert "EDITS_INTERACTIVE_PTY_SMOKE_PASS" in result.stdout


def test_full_runtime_e2e_matches_golden(
    image_case: tuple[str, str],
    release_dir: pathlib.Path,
    docker_log_dir: pathlib.Path,
) -> None:
    lane, image = image_case
    unique = uuid.uuid4().hex
    evidence = release_dir / "evidence" / "runtime" / lane / unique / "evidence"
    evidence.mkdir(parents=True)
    evidence.chmod(0o777)
    result = run_command(
        [
            "docker", "run", "--rm", "--network", "none",
            "--name", f"edits-e2e-{lane}-{unique[:8]}",
            "--volume", f"{evidence}:/work/evidence",
            "--env", "PROOF_OUTPUT_DIR=/work/evidence",
            "--env", "PROOF_RUNTIME_DIR=/tmp/proof-runtime",
            "--entrypoint", "/bin/vim-nix-proof",
            image, "all",
        ],
        log=docker_log_dir / lane / "full-runtime-e2e.log",
        timeout=1800,
    )
    assert "VIM_NIX_EDITOR_E2E_PASS" in result.stdout
    assert "VIM_NIX_RUNTIME_E2E_PASS" in result.stdout
    assert "VIM_NIX_FULL_E2E_PASS" in result.stdout
    receipt = json.loads((evidence / "receipt.json").read_text(encoding="utf-8"))
    assert receipt["status"] == "PASS"
    assert receipt["gates"]["acceptedInstructionCount"] == 1
    assert receipt["gates"]["resultKinds"] == ["accepted", "started", "stdout", "completed"]
    assert receipt["gates"]["residualProcessCount"] == 0


def test_accepted_history_e2e_matches_golden(
    image_case: tuple[str, str],
    docker_log_dir: pathlib.Path,
) -> None:
    lane, image = image_case
    result = run_command(
        ["docker", "run", "--rm", "--network", "none", "--name", f"edits-history-{lane}-{uuid.uuid4().hex[:8]}", "--entrypoint", "/bin/vim-nix-history-proof", image],
        log=docker_log_dir / lane / "accepted-history-e2e.log",
        timeout=1200,
    )
    assert "VIM_NIX_ACCEPTED_HISTORY_E2E_PASS" in result.stdout


def test_named_volumes_preserve_home_and_workspace(
    image_case: tuple[str, str],
    docker_log_dir: pathlib.Path,
) -> None:
    lane, image = image_case
    token = uuid.uuid4().hex
    home_volume = f"edits-ci-home-{lane}-{token}"
    work_volume = f"edits-ci-work-{lane}-{token}"
    try:
        run_command(["docker", "volume", "create", home_volume], log=docker_log_dir / lane / "volume-home-create.log")
        run_command(["docker", "volume", "create", work_volume], log=docker_log_dir / lane / "volume-work-create.log")
        run_command(
            [
                "docker", "run", "--rm", "--network", "none",
                "--volume", f"{home_volume}:/home/dev",
                "--volume", f"{work_volume}:/work/repos",
                "--entrypoint", "/bin/sh", image, "-eu", "-c",
                f"printf '%s' '{token}' > /home/dev/.edits-ci; printf '%s' '{token}' > /work/repos/.edits-ci",
            ],
            log=docker_log_dir / lane / "volume-write.log",
        )
        home = run_command(
            ["docker", "run", "--rm", "--network", "none", "--volume", f"{home_volume}:/home/dev", "--entrypoint", "/bin/cat", image, "/home/dev/.edits-ci"],
            log=docker_log_dir / lane / "volume-home-read.log",
        )
        work = run_command(
            ["docker", "run", "--rm", "--network", "none", "--volume", f"{work_volume}:/work/repos", "--entrypoint", "/bin/cat", image, "/work/repos/.edits-ci"],
            log=docker_log_dir / lane / "volume-work-read.log",
        )
        assert home.stdout == token
        assert work.stdout == token
    finally:
        subprocess.run(["docker", "volume", "rm", "--force", home_volume, work_volume], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, check=False)


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
        assert "digest mismatch" in result.stdout + result.stderr
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
        assert "& $Wslc load -i $Archive" in run_ps1
        assert "& $Wslc inspect $Image" in run_ps1
        assert "dev-home:/home/dev" in run_ps1
        assert "repos:/work/repos" in run_ps1
        assert build_manifest["image"]["id"] in run_ps1


def test_windows_delivery_has_no_runtime_registry_dependency(
    release_dir: pathlib.Path,
    build_manifest: dict[str, object],
) -> None:
    windows_path = release_dir / build_manifest["assets"]["windows"]["name"]
    with zipfile.ZipFile(windows_path) as archive:
        root = "edits-windows/"
        combined = "\n".join(
            archive.read(root + name).decode("utf-8", errors="replace")
            for name in ("verify.ps1", "run.ps1", "README.md")
        ).lower()
    assert "docker pull" not in combined
    assert "podman pull" not in combined
    assert "ghcr.io" not in combined
    assert "wslc" in combined


@pytest.mark.parametrize(
    ("entrypoint", "environment"),
    [
        ("/bin/edits-client", "EDITS_VIM_BIN=relative"),
        ("/bin/edits-service", "EDITS_HQ_BIN=relative"),
        ("/bin/edits-mux", "EDITS_HERDR_BIN=relative"),
    ],
)
def test_relative_provider_binding_fails_closed(
    image_case: tuple[str, str],
    entrypoint: str,
    environment: str,
    docker_log_dir: pathlib.Path,
) -> None:
    lane, image = image_case
    result = run_command(
        ["docker", "run", "--rm", "--network", "none", "--env", environment, "--entrypoint", entrypoint, image, "--help"],
        log=docker_log_dir / lane / f"relative-{pathlib.PurePosixPath(entrypoint).name}.log",
        check=False,
    )
    assert result.returncode == 64
    assert "must be absolute" in result.stderr


def test_default_product_entrypoint_requires_real_tty(
    image_case: tuple[str, str],
    docker_log_dir: pathlib.Path,
) -> None:
    lane, image = image_case
    result = run_command(
        ["docker", "run", "--rm", "--network", "none", image],
        log=docker_log_dir / lane / "default-no-tty.log",
        check=False,
    )
    assert result.returncode != 0
    assert "must be attached to a PTY" in result.stderr
