#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
rm -f cache/vim-visual-projection.*

go test ./...

go run ./cmd/hq pty-vim-rsc-visual-proof \
  --world examples/tree_world.jsonl \
  --out cache/vim-visual-projection.json \
  --trace cache/vim-visual-projection.trace.jsonl \
  --screen-text cache/vim-visual-projection.screen.txt \
  --raw cache/vim-visual-projection.pty.raw

python3 - <<'PY'
import json
from pathlib import Path
r=json.loads(Path('cache/vim-visual-projection.json').read_text())
assert r['visual_projection_ok'] is True, r
assert r['direct_vim_no_shell'] is True, r
assert r['vim_popup_trace_ok'] is True, r
assert r['screen_contains_popup'] is True, r
sample=r['final_popup_sample']
assert sample['slot_kind']=='array.item', sample
assert sample['slot_path']==['tasks'], sample
assert sample['labels']==['task:t1','task:t2','task:t3'], sample
screen=Path('cache/vim-visual-projection.screen.txt').read_text()
for needle in ['HQ SLOT PROJECTION','slot: array.item','task:t1','task:t2','task:t3']:
    assert needle in screen, needle
assert '\x00sh\x00' not in r['proc_cmdline'], r['proc_cmdline']
PY

python3 scripts/render_vim_visual.py \
  cache/vim-visual-projection.screen.txt \
  cache/vim-visual-projection.json \
  cache/vim-visual-projection.png \
  cache/vim-visual-projection.html

test -s cache/vim-visual-projection.png
test -s cache/vim-visual-projection.html

echo VIM_VISUAL_PROJECTION_PROOF_OK
