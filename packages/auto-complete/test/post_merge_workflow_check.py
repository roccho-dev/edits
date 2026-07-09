#!/usr/bin/env python3
from __future__ import annotations

from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
WORKFLOW = ROOT.parents[1] / ".github/workflows/auto-complete-golden.yml"


def fail(msg: str) -> None:
    raise SystemExit(f"[post-merge-workflow-check] {msg}")


def main() -> int:
    text = WORKFLOW.read_text(encoding="utf-8")
    required = [
        "pull_request:",
        "push:",
        "branches:",
        "- proposals",
        "packages/auto-complete/**",
        ".github/workflows/auto-complete-golden.yml",
    ]
    for marker in required:
        if marker not in text:
            fail(f"workflow missing {marker!r}")
    if text.count("push:") != 1:
        fail("workflow must have exactly one push trigger")
    print("[post-merge-workflow-check] PASS")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
