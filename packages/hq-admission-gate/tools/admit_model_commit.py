#!/usr/bin/env python3
"""Admit local model commit queue rows into accepted-ledger-shaped JSONL.

This is a minimal local gate. It validates queue rows and writes accepted rows
plus admission receipts. It does not replace cue/contracts admission.
"""
from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path
from typing import Any

import sys

TOOLS_DIR = Path(__file__).resolve().parents[1] / ".." / "hq-modeling-queue" / "tools"
sys.path.insert(0, str(TOOLS_DIR.resolve()))
from validate_queue import validate_row  # noqa: E402


def digest(value: Any) -> str:
    payload = json.dumps(value, sort_keys=True, separators=(",", ":"))
    return "sha256:" + hashlib.sha256(payload.encode("utf-8")).hexdigest()


def read_jsonl(path: Path) -> list[dict[str, Any]]:
    if not path.exists():
        return []
    rows: list[dict[str, Any]] = []
    with path.open("r", encoding="utf-8") as fh:
        for line_no, line in enumerate(fh, start=1):
            if not line.strip():
                continue
            row = json.loads(line)
            if not isinstance(row, dict):
                raise SystemExit(f"FAIL {path}:{line_no}: row must be object")
            rows.append(row)
    return rows


def append_jsonl(path: Path, row: dict[str, Any]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("a", encoding="utf-8") as fh:
        fh.write(json.dumps(row, ensure_ascii=False, separators=(",", ":")))
        fh.write("\n")


def admitted_ids(ledger_rows: list[dict[str, Any]]) -> set[str]:
    return {r.get("sourceQueueId") for r in ledger_rows if isinstance(r.get("sourceQueueId"), str)}


def accepted_row(queue_row: dict[str, Any]) -> dict[str, Any]:
    return {
        "id": f"amc_{queue_row['id']}",
        "kind": "accepted.modelCommit.v1",
        "createdAt": queue_row.get("createdAt") or "1970-01-01T00:00:00Z",
        "sourceQueueId": queue_row["id"],
        "targetRef": queue_row.get("targetRef"),
        "op": queue_row.get("op"),
        "payload": queue_row.get("payload") or {},
        "reason": queue_row.get("reason"),
    }


def receipt(queue_row: dict[str, Any], status: str, message: str, ledger_digest: str | None) -> dict[str, Any]:
    return {
        "id": f"ar_{queue_row.get('id', 'unknown')}",
        "kind": "admission.receipt.v1",
        "createdAt": queue_row.get("createdAt") or "1970-01-01T00:00:00Z",
        "status": status,
        "queueId": queue_row.get("id") or "unknown",
        "targetRef": queue_row.get("targetRef"),
        "ledgerDigest": ledger_digest,
        "message": message,
    }


def main() -> int:
    parser = argparse.ArgumentParser(description="admit model commit queue rows")
    parser.add_argument("--queue", required=True)
    parser.add_argument("--ledger", required=True)
    parser.add_argument("--receipt", required=True)
    args = parser.parse_args()

    queue_path = Path(args.queue)
    ledger_path = Path(args.ledger)
    receipt_path = Path(args.receipt)

    ledger_rows = read_jsonl(ledger_path)
    done = admitted_ids(ledger_rows)
    admitted = 0
    skipped = 0

    for line_no, row in enumerate(read_jsonl(queue_path), start=1):
        try:
            validate_row(queue_path, line_no, row, set(), set())
            if row.get("kind") != "hq.modelCommitQueued.v1":
                skipped += 1
                append_jsonl(receipt_path, receipt(row, "skipped", "only modelCommitQueued rows are admitted", None))
                continue
            if row["id"] in done:
                skipped += 1
                continue
            accepted = accepted_row(row)
            append_jsonl(ledger_path, accepted)
            ledger_rows.append(accepted)
            ledger_digest = digest(ledger_rows)
            append_jsonl(receipt_path, receipt(row, "accepted", "queue row admitted into accepted-ledger-shaped output", ledger_digest))
            admitted += 1
        except Exception as exc:
            append_jsonl(receipt_path, receipt(row, "failed", str(exc), None))

    print(json.dumps({"status": "PASS", "admitted": admitted, "skipped": skipped}, separators=(",", ":")))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
