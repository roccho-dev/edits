#!/usr/bin/env python3
from __future__ import annotations

import argparse
import hashlib
import json
import os
from pathlib import Path
import subprocess
import sys
import unittest
from typing import Iterable

SCHEMA = "edits.issue118.canonTdd.v1"


def sha256(path: Path) -> str:
    h = hashlib.sha256()
    with path.open("rb") as f:
        for chunk in iter(lambda: f.read(1024 * 1024), b""):
            h.update(chunk)
    return h.hexdigest()


def load_json(path: Path) -> dict:
    with path.open("r", encoding="utf-8") as f:
        return json.load(f)


def validate_spec(spec: dict) -> None:
    required = {
        "schema",
        "issue",
        "lane",
        "baseCommit",
        "purpose",
        "mergeCondition",
        "requiredTests",
        "forbiddenGreenMechanisms",
    }
    missing = sorted(required - spec.keys())
    if missing:
        raise ValueError(f"missing canon fields: {missing}")
    if spec["schema"] != SCHEMA:
        raise ValueError(f"unexpected schema: {spec['schema']!r}")
    if spec["issue"] != "roccho-dev/edits#118":
        raise ValueError(f"unexpected issue: {spec['issue']!r}")
    tests = spec["requiredTests"]
    if not isinstance(tests, list) or not tests or len(tests) != len(set(tests)):
        raise ValueError("requiredTests must be a non-empty unique list")
    forbidden = set(spec["forbiddenGreenMechanisms"])
    expected_forbidden = {
        "skip",
        "xfail",
        "waiver",
        "delete-test",
        "weaken-assertion",
        "change-expected-output",
    }
    if not expected_forbidden.issubset(forbidden):
        raise ValueError("forbiddenGreenMechanisms is incomplete")


def verify_lock(lane_dir: Path) -> list[str]:
    lock = lane_dir / "SPEC.sha256"
    if not lock.is_file():
        return ["missing SPEC.sha256"]
    errors: list[str] = []
    for line in lock.read_text(encoding="utf-8").splitlines():
        if not line.strip():
            continue
        try:
            expected, rel = line.split("  ", 1)
        except ValueError:
            errors.append(f"malformed lock line: {line!r}")
            continue
        path = lane_dir / rel
        if not path.is_file():
            errors.append(f"missing locked file: {rel}")
            continue
        actual = sha256(path)
        if actual != expected:
            errors.append(f"digest mismatch: {rel}: expected {expected}, got {actual}")
    return errors


def git(repo: Path, *args: str) -> subprocess.CompletedProcess[str]:
    return subprocess.run(
        ["git", "-C", str(repo), *args],
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        check=False,
    )


def flatten(suite: unittest.TestSuite) -> Iterable[unittest.TestCase]:
    for item in suite:
        if isinstance(item, unittest.TestSuite):
            yield from flatten(item)
        else:
            yield item


def short_id(test_id: str) -> str:
    parts = test_id.split(".")
    return ".".join(parts[-2:])


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("lane_dir", type=Path)
    mode = parser.add_mutually_exclusive_group(required=True)
    mode.add_argument("--expect-red", action="store_true")
    mode.add_argument("--expect-green", action="store_true")
    parser.add_argument("--result", type=Path)
    args = parser.parse_args()

    lane_dir = args.lane_dir.resolve()
    repo = lane_dir.parents[2]
    spec = load_json(lane_dir / "canon.json")
    validate_spec(spec)

    lock_errors = verify_lock(lane_dir)
    base = spec["baseCommit"]
    ancestor = git(repo, "merge-base", "--is-ancestor", base, "HEAD")
    ancestor_ok = ancestor.returncode == 0

    suite = unittest.defaultTestLoader.discover(
        str(lane_dir / "tests"), pattern="test_*.py", top_level_dir=str(lane_dir)
    )
    discovered = sorted(short_id(t.id()) for t in flatten(suite))
    declared = sorted(spec["requiredTests"])
    missing_declared = sorted(set(declared) - set(discovered))
    undeclared = sorted(set(discovered) - set(declared))

    stream = unittest.runner._WritelnDecorator(sys.stderr)
    result = unittest.TextTestRunner(stream=stream, verbosity=2).run(suite)
    failed = sorted(short_id(t.id()) for t, _ in result.failures)
    errored = sorted(short_id(t.id()) for t, _ in result.errors)
    skipped = sorted(short_id(t.id()) for t, _ in result.skipped)
    expected_failures = sorted(short_id(t.id()) for t, _ in result.expectedFailures)
    unexpected_successes = sorted(short_id(t.id()) for t in result.unexpectedSuccesses)

    if args.expect_red:
        status = (
            not lock_errors
            and ancestor_ok
            and not missing_declared
            and not undeclared
            and not errored
            and not skipped
            and not expected_failures
            and not unexpected_successes
            and failed == declared
        )
        assertion = "all declared tests fail as assertions"
    else:
        status = (
            not lock_errors
            and ancestor_ok
            and not missing_declared
            and not undeclared
            and not failed
            and not errored
            and not skipped
            and not expected_failures
            and not unexpected_successes
        )
        assertion = "all declared tests pass"

    payload = {
        "schema": "edits.issue118.canonTddResult.v1",
        "issue": spec["issue"],
        "lane": spec["lane"],
        "mode": "red" if args.expect_red else "green",
        "status": "PASS" if status else "FAIL",
        "assertion": assertion,
        "baseCommit": base,
        "headCommit": git(repo, "rev-parse", "HEAD").stdout.strip(),
        "specLock": "PASS" if not lock_errors else "FAIL",
        "specLockErrors": lock_errors,
        "baseAncestor": ancestor_ok,
        "declaredTests": declared,
        "discoveredTests": discovered,
        "missingDeclaredTests": missing_declared,
        "undeclaredTests": undeclared,
        "failures": failed,
        "errors": errored,
        "skipped": skipped,
        "expectedFailures": expected_failures,
        "unexpectedSuccesses": unexpected_successes,
    }
    text = json.dumps(payload, indent=2, sort_keys=True) + "\n"
    sys.stdout.write(text)
    if args.result:
        args.result.parent.mkdir(parents=True, exist_ok=True)
        args.result.write_text(text, encoding="utf-8")
    return 0 if status else 1


if __name__ == "__main__":
    raise SystemExit(main())
