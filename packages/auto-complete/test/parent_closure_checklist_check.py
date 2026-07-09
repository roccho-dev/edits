#!/usr/bin/env python3
from __future__ import annotations

from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
CHECKLIST = ROOT / "docs/parent-closure-checklist.md"


def fail(msg: str) -> None:
    raise SystemExit(f"[parent-closure-checklist-check] {msg}")


def main() -> int:
    text = CHECKLIST.read_text(encoding="utf-8")
    for issue in range(39, 49):
        if f"#{issue}" not in text:
            fail(f"missing child issue #{issue}")
    required = [
        "post-merge workflow run id",
        "provider contract result",
        "negative fixture result",
        "candidate/LSP snapshot result",
        "UX visual snapshot result",
        "performance budget result",
        "old-path/import boundary result",
        "Do not re-close #37",
    ]
    for marker in required:
        if marker not in text:
            fail(f"missing closure marker: {marker}")
    print("[parent-closure-checklist-check] PASS")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
