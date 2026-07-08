#!/usr/bin/env python3
"""Validate the minimal contracts-poc JSONL ledger shape."""
from __future__ import annotations

import json
import sys
from pathlib import Path

ALLOWED = {
    "contract.schema.v1",
    "contract.field.v1",
    "contract.edge.v1",
    "contract.query.v1",
    "contract.fixture.v1",
    "contract.authority_rule.v1",
    "accepted.modelCommit.v1",
    "admission.receipt.v1",
}


def fail(path: Path, line_no: int, message: str) -> None:
    raise SystemExit(f"FAIL {path}:{line_no}: {message}")


def main(argv: list[str]) -> int:
    if len(argv) != 2:
        print("usage: validate_contract_ledger.py <ledger.jsonl>", file=sys.stderr)
        return 2
    path = Path(argv[1])
    ids: set[str] = set()
    count = 0
    with path.open("r", encoding="utf-8") as fh:
        for line_no, line in enumerate(fh, start=1):
            if not line.strip():
                continue
            row = json.loads(line)
            if not isinstance(row, dict):
                fail(path, line_no, "row must be object")
            if row.get("kind") not in ALLOWED:
                fail(path, line_no, f"unknown kind: {row.get('kind')!r}")
            row_id = row.get("id")
            if not isinstance(row_id, str) or not row_id:
                fail(path, line_no, "missing id")
            if row_id in ids:
                fail(path, line_no, f"duplicate id: {row_id}")
            ids.add(row_id)
            count += 1
    print(json.dumps({"status": "PASS", "records": count}, separators=(",", ":")))
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv))
