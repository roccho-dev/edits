#!/usr/bin/env python3
"""Convert a confirmed modeling command request into a local queue row."""
from __future__ import annotations

import argparse
import hashlib
import json
import sys
from pathlib import Path
from typing import Any

from validate_queue import validate_row


def load_templates(path: Path) -> dict[str, dict[str, Any]]:
    templates: dict[str, dict[str, Any]] = {}
    with path.open("r", encoding="utf-8") as fh:
        for line_no, line in enumerate(fh, start=1):
            if not line.strip():
                continue
            row = json.loads(line)
            if row.get("kind") != "hq.commandTemplate.v1":
                raise SystemExit(f"FAIL {path}:{line_no}: expected hq.commandTemplate.v1")
            name = row.get("name")
            if not isinstance(name, str) or not name:
                raise SystemExit(f"FAIL {path}:{line_no}: missing name")
            templates[name] = row
    return templates


def short_digest(value: dict[str, Any]) -> str:
    payload = json.dumps(value, sort_keys=True, separators=(",", ":"))
    return hashlib.sha256(payload.encode("utf-8")).hexdigest()[:16]


def make_queue_row(request: dict[str, Any], template: dict[str, Any]) -> dict[str, Any]:
    command = request["command"]
    effect = template["effect"]
    digest = short_digest(request)
    common = {
        "id": f"q_{digest}",
        "createdAt": request.get("createdAt") or "1970-01-01T00:00:00Z",
        "status": "queued",
        "confirmedBy": request.get("confirmedBy") or "human",
        "idempotencyKey": f"idem_{digest}",
        "sourceDigest": request.get("sourceDigest"),
        "targetRef": request.get("targetRef"),
        "reason": request.get("reason") or f"confirmed command {command}",
    }

    if effect == "model_commit":
        return {
            **common,
            "kind": "hq.modelCommitQueued.v1",
            "op": template["op"],
            "payload": request.get("payload") or {},
        }

    if effect == "agent_task":
        return {
            **common,
            "kind": "hq.agentTaskQueued.v1",
            "goal": request.get("goal") or f"run {command}",
            "context": request.get("context") or [],
            "acceptance": request.get("acceptance") or ["produce proposal", "do not mutate accepted ledger"],
        }

    raise SystemExit(f"FAIL: unsupported command effect: {effect}")


def main(argv: list[str]) -> int:
    parser = argparse.ArgumentParser(description="convert confirmed command to queue row")
    parser.add_argument("request_json")
    parser.add_argument("--templates", default="packages/hq-modeling-queue/commands/modeling.commands.jsonl")
    args = parser.parse_args(argv[1:])

    request_path = Path(args.request_json)
    request = json.loads(request_path.read_text(encoding="utf-8"))
    if not isinstance(request, dict):
        raise SystemExit("FAIL: command request must be a JSON object")

    command = request.get("command")
    if not isinstance(command, str) or not command:
        raise SystemExit("FAIL: command request must include command")

    templates = load_templates(Path(args.templates))
    if command not in templates:
        raise SystemExit(f"FAIL: unknown command: {command}")

    template = templates[command]
    if template.get("requiresTarget") and not request.get("targetRef"):
        raise SystemExit(f"FAIL: command requires targetRef: {command}")

    row = make_queue_row(request, template)
    validate_row(Path(request_path), 1, row, set(), set())
    print(json.dumps(row, ensure_ascii=False, separators=(",", ":")))
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv))
