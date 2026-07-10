#!/usr/bin/env python3
from __future__ import annotations

import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
MODULE = "github.com/roccho-dev/edits/packages/auto-complete"
OLD_DIRS = [
    "internal/jpcmp",
    "providers",
    "adapters/lsp",
    "adapters/vim",
    "adapters/helix",
]
OLD_IMPORT_MARKERS = [
    f"{MODULE}/internal/jpcmp",
    f"{MODULE}/providers/",
    f"{MODULE}/adapters/lsp",
    f"{MODULE}/adapters/vim",
    f"{MODULE}/adapters/helix",
]
IMPORT_RE = re.compile(r'"([^"]+)"')
EXECUTABLE_SUFFIXES = {".go", ".vim", ".lua", ".toml", ".py", ".sh"}


def fail(msg: str) -> None:
    raise SystemExit(f"[old-path-absence-check] {msg}")


def main() -> int:
    for rel in OLD_DIRS:
        path = ROOT / rel
        if not path.exists():
            continue
        executable = [p for p in path.rglob("*") if p.is_file() and p.suffix in EXECUTABLE_SUFFIXES]
        if executable:
            listed = ", ".join(str(p.relative_to(ROOT)) for p in executable[:8])
            fail(f"old implementation path has executable files: {listed}")
        for doc in path.rglob("*.md"):
            text = doc.read_text(encoding="utf-8").lower()
            if "historical" not in text and "non-authority" not in text:
                fail(f"old docs path must be explicitly historical/non-authority: {doc.relative_to(ROOT)}")

    for path in ROOT.rglob("*.go"):
        text = path.read_text(encoding="utf-8")
        rel = path.relative_to(ROOT)
        for marker in OLD_IMPORT_MARKERS:
            if marker in text:
                fail(f"old import path in {rel}: {marker}")

    required_new_dirs = [
        "adapters/source/jp-jsonl",
        "adapters/source/domain-jsonl",
        "adapters/source/hq-source-jsonl",
        "adapters/transport/lsp",
        "adapters/editor/helix",
    ]
    for rel in required_new_dirs:
        if not (ROOT / rel).exists():
            fail(f"missing canonical adapter path: {rel}")

    print("[old-path-absence-check] PASS")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
