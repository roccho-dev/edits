#!/usr/bin/env python3
from __future__ import annotations

import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
ACTUAL = ROOT / "artifacts/ux-golden.json"
SVG = ROOT / "artifacts/ux-golden.svg"
MD = ROOT / "artifacts/ux-golden.md"
EXPECTED = ROOT / "test/snapshots/ux-golden.canonical.json"


def fail(msg: str) -> None:
    raise SystemExit(f"[ux-snapshot-audit] {msg}")


def main() -> int:
    if not ACTUAL.exists():
        fail("missing artifacts/ux-golden.json; render step must run first")
    actual = json.loads(ACTUAL.read_text(encoding="utf-8"))
    expected = json.loads(EXPECTED.read_text(encoding="utf-8"))
    for key in ["schema", "status", "raw_buffer", "preedit", "required", "missing", "source"]:
        if actual.get(key) != expected.get(key):
            fail(f"{key} mismatch: expected={expected.get(key)!r} actual={actual.get(key)!r}")
    if actual.get("labels", [])[: len(expected["labels"])] != expected["labels"]:
        fail(f"label prefix mismatch: expected={expected['labels']!r} actual={actual.get('labels')!r}")
    svg_text = SVG.read_text(encoding="utf-8")
    md_text = MD.read_text(encoding="utf-8")
    for marker in [expected["raw_buffer"], expected["preedit"], *expected["labels"]]:
        if marker not in svg_text:
            fail(f"SVG missing {marker!r}")
        if marker not in md_text:
            fail(f"Markdown missing {marker!r}")
    print("[ux-snapshot-audit] PASS")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
