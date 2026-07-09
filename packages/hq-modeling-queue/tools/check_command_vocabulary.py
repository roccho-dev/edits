#!/usr/bin/env python3
"""Validate that hq command vocabulary is editor-surface intent only."""
from __future__ import annotations

import argparse
import json
import re
import sys
from pathlib import Path
from typing import Any

FORBIDDEN_CLAIMS = [
    re.compile(r"\bowns?\s+admission\b", re.I),
    re.compile(r"\bwrites?\s+accepted\s+ledger\b", re.I),
    re.compile(r"\baccepted\.modelCommit\.v1\b", re.I),
    re.compile(r"\bowns?\s+worker\b", re.I),
    re.compile(r"\bowns?\s+ui\s+renderer\b", re.I),
    re.compile(r"\bdispatch\b", re.I),
    re.compile(r"\bmerge\b", re.I),
]

MODEL_QUEUE = "hq.modelCommitQueued.v1"
AGENT_QUEUE = "hq.agentTaskQueued.v1"


def fail(path: Path, line_no: int, message: str) -> None:
    raise SystemExit(f"FAIL {path}:{line_no}: {message}")


def read_jsonl(path: Path) -> list[tuple[int, dict[str, Any]]]:
    rows: list[tuple[int, dict[str, Any]]] = []
    with path.open("r", encoding="utf-8") as fh:
        for line_no, line in enumerate(fh, start=1):
            if not line.strip():
                continue
            try:
                row = json.loads(line)
            except json.JSONDecodeError as exc:
                fail(path, line_no, f"invalid JSON: {exc}")
            if not isinstance(row, dict):
                fail(path, line_no, "row must be object")
            rows.append((line_no, row))
    return rows


def require_string(path: Path, line_no: int, row: dict[str, Any], field: str) -> str:
    value = row.get(field)
    if not isinstance(value, str) or not value:
        fail(path, line_no, f"missing non-empty string field: {field}")
    return value


def validate_row(path: Path, line_no: int, row: dict[str, Any]) -> None:
    if row.get("kind") != "hq.commandTemplate.v1":
        fail(path, line_no, "command kind must be hq.commandTemplate.v1")
    name = require_string(path, line_no, row, "name")
    effect = require_string(path, line_no, row, "effect")
    queue_kind = require_string(path, line_no, row, "queueKind")
    require_string(path, line_no, row, "op")
    claim = require_string(path, line_no, row, "claim")
    if not isinstance(row.get("targetKinds"), list):
        fail(path, line_no, "targetKinds must be list")
    if not isinstance(row.get("requiresTarget"), bool):
        fail(path, line_no, "requiresTarget must be bool")

    if name.startswith("model."):
        if effect != "model_commit" or queue_kind != MODEL_QUEUE:
            fail(path, line_no, "model.* must map to model_commit and hq.modelCommitQueued.v1")
    elif name.startswith("agent."):
        if effect != "agent_task" or queue_kind != AGENT_QUEUE:
            fail(path, line_no, "agent.* must map to agent_task and hq.agentTaskQueued.v1")
    else:
        fail(path, line_no, "command name must start with model. or agent.")

    for pattern in FORBIDDEN_CLAIMS:
        if pattern.search(name) or pattern.search(queue_kind) or pattern.search(claim):
            fail(path, line_no, f"command claims forbidden ownership: {pattern.pattern}")


def validate_file(path: Path) -> int:
    rows = read_jsonl(path)
    seen: set[str] = set()
    for line_no, row in rows:
        validate_row(path, line_no, row)
        name = row["name"]
        if name in seen:
            fail(path, line_no, f"duplicate command name: {name}")
        seen.add(name)
    return len(rows)


def expect_failure(path: Path) -> None:
    try:
        validate_file(path)
    except SystemExit as exc:
        if str(exc).startswith("FAIL "):
            return
        raise
    raise SystemExit(f"FAIL {path}: invalid fixture unexpectedly passed")


def main(argv: list[str]) -> int:
    parser = argparse.ArgumentParser(description="check command vocabulary boundary")
    parser.add_argument("commands", nargs="?", default="packages/hq-modeling-queue/commands/modeling.commands.jsonl")
    parser.add_argument("--valid-fixture", default="packages/hq-modeling-queue/examples/command-vocabulary.valid.jsonl")
    parser.add_argument("--invalid-fixture", default="packages/hq-modeling-queue/examples/command-vocabulary.invalid.jsonl")
    args = parser.parse_args(argv[1:])

    count = validate_file(Path(args.commands))
    validate_file(Path(args.valid_fixture))
    expect_failure(Path(args.invalid_fixture))
    print(json.dumps({"status": "PASS", "commands": count}, separators=(",", ":")))
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv))
