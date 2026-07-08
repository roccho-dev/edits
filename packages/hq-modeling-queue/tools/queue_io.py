#!/usr/bin/env python3
"""Append/read/tail local hq modeling JSONL queues.

This is local/dev IO only. It records intent rows and reads them back; it does
not admit rows into an accepted ledger.
"""
from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path
from typing import Any

from validate_queue import validate_row


def load_json_object(text: str) -> dict[str, Any]:
    row = json.loads(text)
    if not isinstance(row, dict):
        raise SystemExit("FAIL: input must be a JSON object")
    return row


def append_row(path: Path, row: dict[str, Any]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("a", encoding="utf-8") as fh:
        fh.write(json.dumps(row, ensure_ascii=False, separators=(",", ":")))
        fh.write("\n")


def iter_rows(path: Path):
    if not path.exists():
        return
    with path.open("r", encoding="utf-8") as fh:
        for line_no, line in enumerate(fh, start=1):
            if not line.strip():
                continue
            try:
                row = json.loads(line)
            except json.JSONDecodeError as exc:
                raise SystemExit(f"FAIL {path}:{line_no}: invalid JSON: {exc}")
            if not isinstance(row, dict):
                raise SystemExit(f"FAIL {path}:{line_no}: row must be object")
            yield line_no, row


def cmd_append(args: argparse.Namespace) -> int:
    text = Path(args.from_file).read_text(encoding="utf-8") if args.from_file else sys.stdin.read()
    row = load_json_object(text)
    # Validate this single row shape and forbidden authority fields.
    validate_row(Path(args.path), 1, row, set(), set())
    append_row(Path(args.path), row)
    print(json.dumps({"status": "APPENDED", "path": args.path, "id": row.get("id")}, separators=(",", ":")))
    return 0


def cmd_read(args: argparse.Namespace) -> int:
    count = 0
    for _, row in iter_rows(Path(args.path)) or []:
        print(json.dumps(row, ensure_ascii=False, separators=(",", ":")))
        count += 1
    if args.summary:
        print(json.dumps({"status": "READ", "records": count}, separators=(",", ":")), file=sys.stderr)
    return 0


def cmd_tail(args: argparse.Namespace) -> int:
    rows = [row for _, row in (iter_rows(Path(args.path)) or [])]
    for row in rows[-args.n:]:
        print(json.dumps(row, ensure_ascii=False, separators=(",", ":")))
    return 0


def cmd_validate(args: argparse.Namespace) -> int:
    seen_ids: set[str] = set()
    seen_idempotency: set[str] = set()
    count = 0
    for line_no, row in iter_rows(Path(args.path)) or []:
        validate_row(Path(args.path), line_no, row, seen_ids, seen_idempotency)
        count += 1
    print(json.dumps({"status": "PASS", "records": count}, separators=(",", ":")))
    return 0


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description="local hq modeling queue IO")
    sub = parser.add_subparsers(dest="cmd", required=True)

    append = sub.add_parser("append")
    append.add_argument("path")
    append.add_argument("--from-file")
    append.set_defaults(func=cmd_append)

    read = sub.add_parser("read")
    read.add_argument("path")
    read.add_argument("--summary", action="store_true")
    read.set_defaults(func=cmd_read)

    tail = sub.add_parser("tail")
    tail.add_argument("path")
    tail.add_argument("-n", type=int, default=1)
    tail.set_defaults(func=cmd_tail)

    validate = sub.add_parser("validate")
    validate.add_argument("path")
    validate.set_defaults(func=cmd_validate)
    return parser


def main(argv: list[str]) -> int:
    parser = build_parser()
    args = parser.parse_args(argv[1:])
    return args.func(args)


if __name__ == "__main__":
    raise SystemExit(main(sys.argv))
