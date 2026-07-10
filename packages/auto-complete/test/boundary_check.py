#!/usr/bin/env python3
from __future__ import annotations
from pathlib import Path
ROOT = Path(__file__).resolve().parents[1]
REQUIRED = [
    "lib/jpcmp/core/README.md", "lib/jpcmp/core/candidate.go", "lib/jpcmp/core/completion.go",
    "lib/jpcmp/core/rank.go", "lib/jpcmp/core/replace_range.go", "lib/jpcmp/core/romaji.go",
    "lib/jpcmp/core/token.go", "lib/jpcmp/core/types.go", "lib/jpcmp/ports/README.md",
    "lib/jpcmp/ports/provider.go", "lib/jpcmp/ports/projection.go", "lib/jpcmp/ports/request.go",
    "lib/jpcmp/ports/response.go", "adapters/source/jp-jsonl/README.md", "adapters/source/jp-jsonl/provider.go",
    "adapters/source/domain-jsonl/README.md", "adapters/source/domain-jsonl/provider.go",
    "adapters/source/hq-source-jsonl/README.md", "adapters/source/hq-source-jsonl/provider.go",
    "adapters/transport/lsp/README.md", "adapters/transport/lsp/server.go",
    "adapters/editor/helix/README.md", "adapters/editor/helix/languages.toml",
    "app/jpcmp-lsp/config.go", "app/jpcmp-lsp/registry.go", "app/jpcmp-lsp/wire.go",
    "cmd/jpcmp-lsp/main.go", "test/lsp_smoke.py",
]
FORBIDDEN_IN_CORE = ["/adapters/", "encoding/json", "bufio", '"os"', "transport/lsp", "vim", "helix"]
FORBIDDEN_IN_EDITOR_ADAPTERS = ["owns dictionary parsing", "owns rank merge", "general japanese ime"]
for rel in REQUIRED:
    if not (ROOT / rel).exists():
        raise SystemExit(f"[boundary-check] missing {rel}")
if (ROOT / "internal/jpcmp").exists():
    raise SystemExit("[boundary-check] internal/jpcmp must be removed after lib/adapter split")
for path in (ROOT / "lib/jpcmp/core").glob("*.go"):
    text = path.read_text(encoding="utf-8")
    for bad in FORBIDDEN_IN_CORE:
        if bad in text:
            raise SystemExit(f"[boundary-check] forbidden core dependency in {path.relative_to(ROOT)}: {bad}")
for rel in ["adapters/editor/helix/README.md"]:
    text = (ROOT / rel).read_text(encoding="utf-8").lower()
    for bad in FORBIDDEN_IN_EDITOR_ADAPTERS:
        if bad in text:
            raise SystemExit(f"[boundary-check] forbidden phrase in {rel}: {bad}")
lsp_doc = (ROOT / "adapters/transport/lsp/README.md").read_text(encoding="utf-8")
for required in ["textDocument/completion", "textEdit", "cmd/jpcmp-lsp"]:
    if required not in lsp_doc:
        raise SystemExit(f"[boundary-check] LSP doc missing {required}")
print("[boundary-check] PASS")
