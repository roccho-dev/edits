#!/usr/bin/env python3
"""Promote a reviewed modeling proposal into a model commit queue row.

This is a human-confirmation bridge. It does not admit the row into an accepted
ledger.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import sys
from pathlib import Path
from typing import Any

from validate_queue import validate_row


def digest(value: Any) -> str:
    payload = json.dumps(value, sort_keys=True, separators=(",", ":"))
    return hashlib.sha256(payload.encode("utf-8")).hexdigest()[:16]


def main(argv: list[str]) -> int:
    parser = argparse.ArgumentParser(description="promote modeling proposal to modelCommitQueued row")
    parser.add_argument("proposal_json")
    parser.add_argument("--confirmed-by", default="human")
    parser.add_argument("--created-at", default="1970-01-01T00:00:00Z")
    args = parser.parse_args(argv[1:])

    proposal_path = Path(args.proposal_json)
    proposal = json.loads(proposal_path.read_text(encoding="utf-8"))
    if not isinstance(proposal, dict):
      raise SystemExit("FAIL: proposal must be object")
    if proposal.get("kind") != "modeling.proposal.v1":
      raise SystemExit("FAIL: proposal kind must be modeling.proposal.v1")
    if proposal.get("status") != "proposed":
      raise SystemExit("FAIL: only proposed proposals can be promoted")

    token = digest({"proposal": proposal, "confirmedBy": args.confirmed_by})
    row = {
        "id": f"mq_from_{proposal['id']}_{token}",
        "kind": "hq.modelCommitQueued.v1",
        "createdAt": args.created_at,
        "status": "queued",
        "confirmedBy": args.confirmed_by,
        "idempotencyKey": f"idem_proposal_{proposal['id']}_{token}",
        "sourceDigest": None,
        "targetRef": proposal.get("targetRef"),
        "op": proposal["op"],
        "payload": proposal.get("payload") or {},
        "reason": f"promoted from modeling proposal {proposal['id']}",
    }
    validate_row(proposal_path, 1, row, set(), set())
    print(json.dumps(row, ensure_ascii=False, separators=(",", ":")))
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv))
