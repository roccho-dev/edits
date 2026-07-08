#!/usr/bin/env python3
from __future__ import annotations

import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
ARTIFACT_DIR = ROOT / "artifacts"
json_path = ARTIFACT_DIR / "ux-golden.json"
svg_path = ARTIFACT_DIR / "ux-golden.svg"
md_path = ARTIFACT_DIR / "ux-golden.md"

for path in [json_path, svg_path, md_path]:
    if not path.exists():
        raise SystemExit(f"[ux-visual-check] missing {path}")

payload = json.loads(json_path.read_text(encoding="utf-8"))
if payload.get("status") != "PASS":
    raise SystemExit(f"[ux-visual-check] status not PASS: {payload}")
if payload.get("raw_buffer") != "houji":
    raise SystemExit(f"[ux-visual-check] raw_buffer mismatch: {payload}")
if payload.get("preedit") != "ほうじ":
    raise SystemExit(f"[ux-visual-check] preedit mismatch: {payload}")
labels = payload.get("labels") or []
for label in ["houjinScore", "法人", "法人売却"]:
    if label not in labels:
        raise SystemExit(f"[ux-visual-check] missing label {label}: {labels}")
svg = svg_path.read_text(encoding="utf-8")
for text in ["auto-complete UX golden evidence", "houji", "ほうじ", "houjinScore", "法人", "法人売却"]:
    if text not in svg:
        raise SystemExit(f"[ux-visual-check] SVG missing {text}")
print("[ux-visual-check] PASS")
