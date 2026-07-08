#!/usr/bin/env python3
from __future__ import annotations
import json
from pathlib import Path
p = Path('test/proof_summary.json')
if not p.exists():
    raise SystemExit('[golden-check] missing proof_summary.json')
s = json.loads(p.read_text(encoding='utf-8'))
expected = {'schema': 'jpcmp_proof_summary.v1', 'status': 'PASS', 'total_assertions': 8}
for k, v in expected.items():
    if s.get(k) != v:
        raise SystemExit(f'[golden-check] {k} expected {v!r}, got {s.get(k)!r}')
print('[golden-check] PASS')
