#!/usr/bin/env python3
"""Validate hq modeling queue JSONL with standard-library checks.

This intentionally avoids external dependencies. It is a guard for local/dev queue
shape and authority-boundary mistakes, not a replacement for ops admission.
"""
from __future__ import annotations

import json
import sys
from pathlib import Path
from typing import Any

ALLOWED_KINDS = {
    "hq.modelCommitQueued.v1",
    "hq.agentTaskQueued.v1",
    "hq.receipt.v1",
}

FORBIDDEN_FIELDS = {
    "authority",
    "accepted",
    "approved",
    "approval",
    "merge",
    "merged",
    "fire",
    "dispatch",
}


def fail(path: Path, line_no: int, message: str) -> None:
    where = f"{path}:{line_no}" if line_no else str(path)
    raise SystemExit(f"FAIL {where}: {message}")


def require_string(path: Path, line_no: int, row: dict[str, Any], field: str) -> None:
    value = row.get(field)
    if not isinstance(value, str) or not value:
        fail(path, line_no, f"missing non-empty string field: {field}")


def require_object(path: Path, line_no: int, row: dict[str, Any], field: str) -> None:
    if not isinstance(row.get(field), dict):
        fail(path, line_no, f"missing object field: {field}")


def require_target_ref(path: Path, line_no: int, row: dict[str, Any]) -> None:
    require_object(path, line_no, row, "targetRef")
    target_ref = row["targetRef"]
    if not isinstance(target_ref.get("kind"), str) or not target_ref["kind"]:
        fail(path, line_no, "targetRef.kind must be a non-empty string")
    if not isinstance(target_ref.get("id"), str) or not target_ref["id"]:
        fail(path, line_no, "targetRef.id must be a non-empty string")


def find_forbidden_fields(value: Any, prefix: str = "") -> list[str]:
    if isinstance(value, list):
        found: list[str] = []
        for index, item in enumerate(value):
            found.extend(find_forbidden_fields(item, f"{prefix}.{index}" if prefix else str(index)))
        return found
    if not isinstance(value, dict):
        return []
    found = []
    for key, nested in value.items():
        path = f"{prefix}.{key}" if prefix else key
        if key in FORBIDDEN_FIELDS:
            found.append(path)
        found.extend(find_forbidden_fields(nested, path))
    return found


def validate_row(path: Path, line_no: int, row: dict[str, Any], seen_ids: set[str], seen_idempotency: set[str]) -> None:
    bad = find_forbidden_fields(row)
    if bad:
        fail(path, line_no, f"forbidden authority/dispatch fields: {', '.join(sorted(bad))}")

    kind = row.get("kind")
    if kind not in ALLOWED_KINDS:
        fail(path, line_no, f"unknown kind: {kind!r}")

    require_string(path, line_no, row, "id")
    require_string(path, line_no, row, "createdAt")
    require_string(path, line_no, row, "status")
    require_string(path, line_no, row, "idempotencyKey")

    row_id = row["id"]
    idem = row["idempotencyKey"]
    if row_id in seen_ids:
        fail(path, line_no, f"duplicate id: {row_id}")
    if idem in seen_idempotency:
        fail(path, line_no, f"duplicate idempotencyKey: {idem}")
    seen_ids.add(row_id)
    seen_idempotency.add(idem)

    if kind == "hq.modelCommitQueued.v1":
        if row.get("status") != "queued":
            fail(path, line_no, "modelCommitQueued status must be queued")
        require_string(path, line_no, row, "confirmedBy")
        require_target_ref(path, line_no, row)
        require_string(path, line_no, row, "op")
        require_object(path, line_no, row, "payload")
        require_string(path, line_no, row, "reason")

    if kind == "hq.agentTaskQueued.v1":
        if row.get("status") != "queued":
            fail(path, line_no, "agentTaskQueued status must be queued")
        require_string(path, line_no, row, "confirmedBy")
        require_target_ref(path, line_no, row)
        require_string(path, line_no, row, "goal")
        require_string(path, line_no, row, "reason")
        if "context" in row and not isinstance(row.get("context"), list):
            fail(path, line_no, "agentTaskQueued context must be a list when present")
        if "acceptance" in row and not isinstance(row.get("acceptance"), list):
            fail(path, line_no, "agentTaskQueued acceptance must be a list when present")

    if kind == "hq.receipt.v1":
        if row.get("status") not in {"processed", "failed", "pending"}:
            fail(path, line_no, "receipt status must be processed, failed, or pending")
        require_string(path, line_no, row, "queueId")


def main(argv: list[str]) -> int:
    if len(argv) != 2:
        print("usage: validate_queue.py <queue-or-receipt.jsonl>", file=sys.stderr)
        return 2

    path = Path(argv[1])
    seen_ids: set[str] = set()
    seen_idempotency: set[str] = set()
    count = 0

    with path.open("r", encoding="utf-8") as fh:
        for line_no, line in enumerate(fh, start=1):
            if not line.strip():
                continue
            try:
                row = json.loads(line)
            except json.JSONDecodeError as exc:
                fail(path, line_no, f"invalid JSON: {exc}")
            if not isinstance(row, dict):
                fail(path, line_no, "row must be a JSON object")
            validate_row(path, line_no, row, seen_ids, seen_idempotency)
            count += 1

    print(json.dumps({"status": "PASS", "records": count}, separators=(",", ":")))
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv))
