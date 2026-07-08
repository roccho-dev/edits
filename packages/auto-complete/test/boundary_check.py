#!/usr/bin/env python3
from __future__ import annotations

from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
REQUIRED = [
    "core/README.md",
    "providers/domain-jsonl/README.md",
    "adapters/lsp/README.md",
    "adapters/vim/README.md",
    "adapters/helix/README.md",
    "adapters/helix/languages.toml",
    "proofs/vim/README.md",
    "proofs/lsp/README.md",
    "cmd/jpcmp-lsp/main.go",
    "test/lsp_smoke.py",
]

FORBIDDEN_IN_ADAPTER_DOCS = [
    "owns dictionary parsing",
    "owns rank merge",
    "general japanese ime",
]

for rel in REQUIRED:
    path = ROOT / rel
    if not path.exists():
        raise SystemExit(f"[boundary-check] missing {rel}")

for rel in ["adapters/vim/README.md", "adapters/helix/README.md"]:
    text = (ROOT / rel).read_text(encoding="utf-8").lower()
    for bad in FORBIDDEN_IN_ADAPTER_DOCS:
        if bad in text:
            raise SystemExit(f"[boundary-check] forbidden phrase in {rel}: {bad}")

lsp_doc = (ROOT / "adapters/lsp/README.md").read_text(encoding="utf-8")
for required in ["textDocument/completion", "textEdit", "cmd/jpcmp-lsp"]:
    if required not in lsp_doc:
        raise SystemExit(f"[boundary-check] LSP doc missing {required}")

print("[boundary-check] PASS")
