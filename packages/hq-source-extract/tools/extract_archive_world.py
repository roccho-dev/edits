#!/usr/bin/env python3
"""Extract a minimal repoMap world JSONL from a source archive."""
from __future__ import annotations

import argparse
import hashlib
import json
import tarfile
import zipfile
from pathlib import Path
from typing import Iterable


def sha256_file(path: Path) -> str:
    h = hashlib.sha256()
    with path.open("rb") as fh:
        for chunk in iter(lambda: fh.read(1024 * 1024), b""):
            h.update(chunk)
    return "sha256:" + h.hexdigest()


def iter_archive_names(path: Path) -> Iterable[str]:
    if zipfile.is_zipfile(path):
        with zipfile.ZipFile(path) as zf:
            for name in zf.namelist():
                if not name.endswith("/"):
                    yield name
        return
    if tarfile.is_tarfile(path):
        with tarfile.open(path) as tf:
            for member in tf.getmembers():
                if member.isfile():
                    yield member.name
        return
    raise SystemExit(f"unsupported archive: {path}")


def classify_package(name: str) -> str:
    parts = [p for p in name.split("/") if p]
    if len(parts) >= 2 and parts[0] in {"packages", "pkg", "cmd", "internal"}:
        return "/".join(parts[:2])
    if len(parts) >= 1:
        return parts[0]
    return "root"


def emit(out, row: dict) -> None:
    out.write(json.dumps(row, ensure_ascii=False, separators=(",", ":")))
    out.write("\n")


def main() -> int:
    parser = argparse.ArgumentParser(description="extract minimal repoMap world from source archive")
    parser.add_argument("--archive", required=True)
    parser.add_argument("--repo-id", required=True)
    parser.add_argument("--out", required=True)
    args = parser.parse_args()

    archive = Path(args.archive)
    digest = sha256_file(archive)
    names = sorted(iter_archive_names(archive))
    packages = sorted({classify_package(name) for name in names})

    out_path = Path(args.out)
    out_path.parent.mkdir(parents=True, exist_ok=True)
    with out_path.open("w", encoding="utf-8") as out:
        emit(out, {"kind": "source.archive.v1", "id": args.repo_id, "path": str(archive), "digest": digest, "fileCount": len(names)})
        for name in names:
            emit(out, {"kind": "raw.evidence.v1", "sourceId": args.repo_id, "path": name, "packageId": classify_package(name)})
        emit(out, {"kind": "extraction.v1", "sourceId": args.repo_id, "inputDigest": digest, "outputKind": "repoMap.world.v1", "packages": len(packages), "files": len(names)})
        emit(out, {"kind": "repoMap.world.node.v1", "id": f"repo:{args.repo_id}", "role": "repo", "label": args.repo_id})
        for package in packages:
            pid = f"pkg:{args.repo_id}:{package}"
            emit(out, {"kind": "repoMap.world.node.v1", "id": pid, "role": "package", "label": package, "repoId": args.repo_id})
            emit(out, {"kind": "repoMap.world.edge.v1", "from": f"repo:{args.repo_id}", "to": pid, "relation": "contains"})
            for name in [n for n in names if classify_package(n) == package]:
                mid = f"model:{args.repo_id}:{name}"
                emit(out, {"kind": "repoMap.world.node.v1", "id": mid, "role": "model", "label": name, "repoId": args.repo_id, "packageId": package})
                emit(out, {"kind": "repoMap.world.edge.v1", "from": pid, "to": mid, "relation": "contains"})
    print(json.dumps({"status": "PASS", "records": 4 + len(names) + len(packages) * 2 + len(names) * 2, "files": len(names), "packages": len(packages)}, separators=(",", ":")))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
