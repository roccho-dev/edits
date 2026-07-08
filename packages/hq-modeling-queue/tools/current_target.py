#!/usr/bin/env python3
"""Read and write the local current targetRef bridge file."""
from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path
from typing import Any

REQUIRED = {"kind", "id", "source", "projectionDigest", "updatedAt"}


def fail(message: str) -> None:
    raise SystemExit(f"FAIL: {message}")


def validate_target(row: dict[str, Any]) -> None:
    missing = sorted(REQUIRED - set(row.keys()))
    if missing:
        fail(f"missing current-target fields: {', '.join(missing)}")
    for field in ["kind", "id", "source", "updatedAt"]:
        if not isinstance(row.get(field), str) or not row[field]:
            fail(f"field must be non-empty string: {field}")
    if row.get("projectionDigest") is not None and not isinstance(row.get("projectionDigest"), str):
        fail("projectionDigest must be string or null")
    if "metadata" in row and not isinstance(row["metadata"], dict):
        fail("metadata must be object when present")
    extra = sorted(set(row.keys()) - {"kind", "id", "source", "projectionDigest", "updatedAt", "metadata"})
    if extra:
        fail(f"unknown current-target fields: {', '.join(extra)}")


def cmd_write(args: argparse.Namespace) -> int:
    data = json.loads(Path(args.from_file).read_text(encoding="utf-8")) if args.from_file else json.load(sys.stdin)
    if not isinstance(data, dict):
        fail("current target must be object")
    validate_target(data)
    path = Path(args.path)
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(data, ensure_ascii=False, separators=(",", ":")) + "\n", encoding="utf-8")
    print(json.dumps({"status": "WROTE", "path": str(path), "kind": data["kind"], "id": data["id"]}, separators=(",", ":")))
    return 0


def cmd_read(args: argparse.Namespace) -> int:
    path = Path(args.path)
    data = json.loads(path.read_text(encoding="utf-8"))
    if not isinstance(data, dict):
        fail("current target must be object")
    validate_target(data)
    print(json.dumps(data, ensure_ascii=False, separators=(",", ":")))
    return 0


def cmd_validate(args: argparse.Namespace) -> int:
    path = Path(args.path)
    data = json.loads(path.read_text(encoding="utf-8"))
    if not isinstance(data, dict):
        fail("current target must be object")
    validate_target(data)
    print(json.dumps({"status": "PASS", "kind": data["kind"], "id": data["id"]}, separators=(",", ":")))
    return 0


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description="local current targetRef bridge")
    sub = parser.add_subparsers(dest="cmd", required=True)

    write = sub.add_parser("write")
    write.add_argument("path")
    write.add_argument("--from-file")
    write.set_defaults(func=cmd_write)

    read = sub.add_parser("read")
    read.add_argument("path")
    read.set_defaults(func=cmd_read)

    validate = sub.add_parser("validate")
    validate.add_argument("path")
    validate.set_defaults(func=cmd_validate)
    return parser


def main(argv: list[str]) -> int:
    args = build_parser().parse_args(argv[1:])
    return args.func(args)


if __name__ == "__main__":
    raise SystemExit(main(sys.argv))
