#!/usr/bin/env python3
from __future__ import annotations

import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
MODULE = "github.com/roccho-dev/edits/packages/auto-complete"
IMPORT_RE = re.compile(r'(?m)^\s*import\s+(?:\((?P<block>.*?)\)|(?P<single>"[^"]+"))', re.S)
STRING_RE = re.compile(r'"([^"]+)"')

FORBIDDEN_CORE_PREFIXES = (
    f"{MODULE}/adapters/",
    f"{MODULE}/app/",
    f"{MODULE}/cmd/",
)
FORBIDDEN_CORE_IMPORTS = {"bufio", "encoding/json", "os"}
FORBIDDEN_PORT_PREFIXES = (
    f"{MODULE}/adapters/",
    f"{MODULE}/app/",
    f"{MODULE}/cmd/",
)


def imports(path: Path) -> list[str]:
    text = path.read_text(encoding="utf-8")
    out: list[str] = []
    for match in IMPORT_RE.finditer(text):
        if match.group("single"):
            out.extend(STRING_RE.findall(match.group("single")))
        else:
            out.extend(STRING_RE.findall(match.group("block") or ""))
    return out


def fail(msg: str) -> None:
    raise SystemExit(f"[import-graph-check] {msg}")


def check_prefixes(path: Path, values: list[str], prefixes: tuple[str, ...], label: str) -> None:
    rel = path.relative_to(ROOT)
    for value in values:
        for prefix in prefixes:
            if value.startswith(prefix):
                fail(f"{label} forbidden import in {rel}: {value}")


def main() -> int:
    go_files = sorted(p for p in ROOT.rglob("*.go") if "/.git/" not in str(p))
    if not go_files:
        fail("no Go files found")

    for path in (ROOT / "lib/jpcmp/core").glob("*.go"):
        imps = imports(path)
        check_prefixes(path, imps, FORBIDDEN_CORE_PREFIXES, "core")
        for value in imps:
            if value in FORBIDDEN_CORE_IMPORTS:
                fail(f"core must stay pure; {path.relative_to(ROOT)} imports {value}")

    for path in (ROOT / "lib/jpcmp/ports").glob("*.go"):
        imps = imports(path)
        check_prefixes(path, imps, FORBIDDEN_PORT_PREFIXES, "ports")

    for path in ROOT.rglob("*.go"):
        imps = imports(path)
        rel = path.relative_to(ROOT)
        for value in imps:
            if "/internal/jpcmp" in value:
                fail(f"old internal import in {rel}: {value}")

    print("[import-graph-check] PASS")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
