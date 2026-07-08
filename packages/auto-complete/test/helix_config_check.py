#!/usr/bin/env python3
from __future__ import annotations

from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
text = (ROOT / "adapters/helix/languages.toml").read_text(encoding="utf-8")
for required in ["[language-server.jpcmp]", 'command = "jpcmp-lsp"', '"--dict"', "language-servers"]:
    if required not in text:
        raise SystemExit(f"[helix-config-check] missing {required}")
print("[helix-config-check] PASS")
