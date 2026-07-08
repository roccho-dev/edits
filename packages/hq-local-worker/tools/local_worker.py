#!/usr/bin/env python3
"""Process local hq modeling queue rows into local receipts/projection.

This worker is intentionally local/dev only. It does not admit rows into an
accepted ledger.
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


def write_json(path: Path, value: Any) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(value, ensure_ascii=False, indent=2, sort_keys=True) + "\n", encoding="utf-8")


def append_jsonl(path: Path, row: dict[str, Any]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("a", encoding="utf-8") as fh:
        fh.write(json.dumps(row, ensure_ascii=False, separators=(",", ":")))
        fh.write("\n")


def load_state(path: Path) -> dict[str, Any]:
    if path.exists():
        value = json.loads(path.read_text(encoding="utf-8"))
        if isinstance(value, dict):
            return value
    return {"modelOperations": [], "agentTasks": []}


def processed_keys(receipts: list[dict[str, Any]]) -> set[str]:
    return {r.get("idempotencyKey") for r in receipts if isinstance(r.get("idempotencyKey"), str)}


def receipt_for(row: dict[str, Any], status: str, message: str, projection_digest: str | None) -> dict[str, Any]:
    return {
        "id": f"rc_{row.get('id', 'unknown')}",
        "kind": "hq.receipt.v1",
        "createdAt": row.get("createdAt") or "1970-01-01T00:00:00Z",
        "status": status,
        "queueId": row.get("id") or "unknown",
        "idempotencyKey": row.get("idempotencyKey") or f"missing_{digest(row)[:16]}",
        "targetRef": row.get("targetRef"),
        "projectionDigest": projection_digest,
        "ledgerDigest": None,
        "message": message,
    }


def process(args: argparse.Namespace) -> int:
    queue_path = Path(args.queue)
    receipt_path = Path(args.receipt)
    state_path = Path(args.state)
    projection_path = Path(args.projection)

    state = load_state(state_path)
    receipts = read_jsonl(receipt_path)
    done = processed_keys(receipts)
    new_receipts = 0

    for line_no, row in enumerate(read_jsonl(queue_path), start=1):
        idem = row.get("idempotencyKey")
        if isinstance(idem, str) and idem in done:
            continue
        try:
            validate_row(queue_path, line_no, row, set(), set())
            kind = row.get("kind")
            if kind == "hq.modelCommitQueued.v1":
                state.setdefault("modelOperations", []).append({
                    "queueId": row["id"],
                    "op": row.get("op"),
                    "targetRef": row.get("targetRef"),
                    "payload": row.get("payload") or {},
                    "reason": row.get("reason"),
                })
                projection = {
                    "kind": "hq.localProjection.v1",
                    "authority": False,
                    "modelOperationCount": len(state.get("modelOperations", [])),
                    "agentTaskCount": len(state.get("agentTasks", [])),
                    "latestQueueId": row["id"],
                    "targetRef": row.get("targetRef"),
                }
                projection_digest = digest(projection)
                projection["digest"] = projection_digest
                write_json(projection_path, projection)
                append_jsonl(receipt_path, receipt_for(row, "processed", "local projection updated; no admission performed", projection_digest))
                new_receipts += 1
            elif kind == "hq.agentTaskQueued.v1":
                state.setdefault("agentTasks", []).append({
                    "queueId": row["id"],
                    "targetRef": row.get("targetRef"),
                    "goal": row.get("goal"),
                    "acceptance": row.get("acceptance") or [],
                })
                append_jsonl(receipt_path, receipt_for(row, "pending", "agent task queued; waiting for proposal", None))
                new_receipts += 1
        except Exception as exc:  # local proof guard; keep receipt even for bad rows
            append_jsonl(receipt_path, {
                "id": f"rc_error_{line_no}",
                "kind": "hq.receipt.v1",
                "createdAt": row.get("createdAt") or "1970-01-01T00:00:00Z",
                "status": "failed",
                "queueId": row.get("id") or f"line_{line_no}",
                "idempotencyKey": row.get("idempotencyKey") or f"error_{line_no}",
                "targetRef": row.get("targetRef"),
                "projectionDigest": None,
                "ledgerDigest": None,
                "message": str(exc),
            })
            new_receipts += 1

    write_json(state_path, state)
    print(json.dumps({"status": "PASS", "newReceipts": new_receipts}, separators=(",", ":")))
    return 0


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description="local hq queue worker")
    sub = parser.add_subparsers(dest="cmd", required=True)
    proc = sub.add_parser("process")
    proc.add_argument("--queue", required=True)
    proc.add_argument("--receipt", required=True)
    proc.add_argument("--state", required=True)
    proc.add_argument("--projection", required=True)
    proc.set_defaults(func=process)
    return parser


def main() -> int:
    args = build_parser().parse_args()
    return args.func(args)


if __name__ == "__main__":
    raise SystemExit(main())
