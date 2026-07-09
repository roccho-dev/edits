#!/usr/bin/env python3
"""Check that edits remains an editor surface and queue-writer boundary."""
from __future__ import annotations

import argparse
import json
import re
import sys
from pathlib import Path

FORBIDDEN_PATTERNS = [
    ("canonical worker runtime", re.compile(r"\bcanonical\s+worker\s+runtime\b", re.I)),
    ("primary worker runtime", re.compile(r"\bprimary\s+worker\s+runtime\b", re.I)),
    ("admission ownership", re.compile(r"\badmission\s+ownership\b", re.I)),
    ("accepted ledger authority", re.compile(r"\baccepted\s+ledger\s+authority\b", re.I)),
    ("projection authority ownership", re.compile(r"\bprojection\s+authority\s+ownership\b", re.I)),
    ("ui renderer ownership", re.compile(r"\bui\s+renderer\s+ownership\b", re.I)),
]

ALLOWING_CONTEXT = re.compile(r"\b(not|no|never|forbidden|without|must not|does not|do not)\b", re.I)
PROOF_ONLY_CONTEXT = re.compile(r"\b(proof-only|legacy|evidence|non-authority|not canonical|not the canonical)\b", re.I)
REQUIRED_README = [
    "edits = editor surface",
    "queue writer adapter",
    "- worker",
    "- admission",
    "- accepted ledger",
    "- projection authority",
    "- UI renderer",
]


def fail(message: str) -> None:
    raise SystemExit(f"FAIL: {message}")


def has_forbidden_claim(text: str) -> list[str]:
    failures: list[str] = []
    lines = text.splitlines()
    for line_no, line in enumerate(lines, start=1):
        for name, pattern in FORBIDDEN_PATTERNS:
            if not pattern.search(line):
                continue
            if ALLOWING_CONTEXT.search(line) or PROOF_ONLY_CONTEXT.search(line):
                continue
            failures.append(f"line {line_no}: forbidden {name}: {line.strip()}")
    return failures


def check_required_docs(root: Path) -> None:
    readme = (root / "README.md").read_text(encoding="utf-8")
    for needle in REQUIRED_README:
        if needle not in readme:
            fail(f"README.md missing boundary phrase: {needle}")

    worker_readme = (root / "packages/hq-local-worker/README.md").read_text(encoding="utf-8")
    if "legacy/proof-only" not in worker_readme:
        fail("hq-local-worker README must mark the worker as legacy/proof-only")
    if "not the canonical worker runtime" not in worker_readme:
        fail("hq-local-worker README must deny canonical runtime ownership")

    boundary_doc = (root / "docs/edits-boundary.md").read_text(encoding="utf-8")
    if "edits writes intent; ops validates/processes/admits; ui renders read models" not in boundary_doc:
        fail("docs/edits-boundary.md missing flow ownership rule")


def check_fixtures(root: Path) -> None:
    fixture_dir = root / "packages/hq-modeling-queue/examples"
    fixture_paths = sorted(fixture_dir.glob("boundary.*.md"))
    if not fixture_paths:
        fail("missing boundary fixtures")
    saw_allowed = False
    saw_forbidden = False
    for path in fixture_paths:
        failures = has_forbidden_claim(path.read_text(encoding="utf-8"))
        if "forbidden" in path.name:
            saw_forbidden = True
            if not failures:
                fail(f"forbidden boundary fixture did not fail: {path.name}")
        else:
            saw_allowed = True
            if failures:
                fail(f"allowed boundary fixture failed: {path.name}: " + "; ".join(failures))
    if not saw_allowed:
        fail("missing allowed boundary fixture")
    if not saw_forbidden:
        fail("missing forbidden boundary fixture")


def check_repository_text(root: Path) -> None:
    paths = [
        root / "README.md",
        root / "docs/edits-boundary.md",
        root / "packages/hq-local-worker/README.md",
        root / "packages/hq-modeling-queue/README.md",
    ]
    failures: list[str] = []
    for path in paths:
        text = path.read_text(encoding="utf-8")
        for failure in has_forbidden_claim(text):
            failures.append(f"{path.relative_to(root)}: {failure}")
    if failures:
        fail("boundary violations: " + "; ".join(failures))


def main(argv: list[str]) -> int:
    parser = argparse.ArgumentParser(description="check edits boundary ownership")
    parser.add_argument("root", nargs="?", default=".")
    args = parser.parse_args(argv[1:])

    root = Path(args.root).resolve()
    check_required_docs(root)
    check_fixtures(root)
    check_repository_text(root)
    print(json.dumps({"status": "PASS", "check": "edits-boundary"}, separators=(",", ":")))
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv))
