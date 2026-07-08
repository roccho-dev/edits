#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
rm -f cache/loose-*.json cache/loose-*.jsonl cache/loose-visual.*

go test ./...

go run ./cmd/hq rsc-intake \
  --world examples/tree_world.jsonl \
  --input 'project hq tasks ' \
  --version 301 \
  --out cache/loose-partial.json

python3 - <<'PY'
import json
r=json.load(open('cache/loose-partial.json'))
assert r['surface']=='loose-string', r
assert r['draft']['kind']=='project.patch', r['draft']
assert r['draft']['root_id']=='project:hq', r['draft']
assert r['draft']['operation']=='append-ref', r['draft']
assert r['draft']['path']==['tasks'], r['draft']
assert r['draft']['partial'] is True, r['draft']
assert 'ref' in r['draft']['missing'], r['draft']
assert r['context']['slot']['kind']=='draft.ref', r['context']
assert not any(v['severity']=='error' for v in r['validation']), r['validation']
labels=[s['label'] for s in r['suggestions']]
assert labels==['task:t1','task:t2','task:t3'], labels
for s in r['suggestions']:
    assert s['meaning'], s
    assert s['compile_draft']['side_effect'] is False, s
    assert s['compile_draft']['operation']=='append-ref', s
PY

if go run ./cmd/hq rsc-intake \
  --world examples/tree_world.jsonl \
  --input 'project hq tasks ' \
  --version 301 \
  --strict \
  --out cache/loose-partial-strict.json >/tmp/hq_loose_strict.out 2>/tmp/hq_loose_strict.err; then
  echo 'expected strict validation to reject incomplete draft' >&2
  exit 1
fi

go run ./cmd/hq rsc-intake \
  --world examples/tree_world.jsonl \
  --input 'project hq tasks task:t1' \
  --version 302 \
  --strict \
  --out cache/loose-complete-strict.json

python3 - <<'PY'
import json
r=json.load(open('cache/loose-complete-strict.json'))
assert r['draft']['partial'] is False, r['draft']
assert r['draft']['ref']=='task:t1', r['draft']
assert not any(v['severity']=='error' for v in (r['validation'] or [])), r['validation']
PY

go run ./cmd/hq rsc-accept \
  --suggestion cache/loose-partial.json \
  --index 0 \
  --queue cache/loose-instruction.jsonl \
  --out cache/loose-accepted-instruction.json

python3 - <<'PY'
import json
row=json.loads(open('cache/loose-instruction.jsonl').read().strip())
assert row['kind']=='instruction.accepted', row
assert row['compile_draft']['operation']=='append-ref', row
assert row['compile_draft']['ref']=='task:t1', row
assert row['compile_draft']['side_effect'] is False, row
r=json.load(open('cache/loose-partial.json'))
s=r['suggestions'][0]
s['compile_draft']['ref']='task:t2'
json.dump(s, open('cache/loose-mutated-suggestion.json','w'))
PY

if go run ./cmd/hq rsc-accept \
  --suggestion cache/loose-mutated-suggestion.json \
  --queue cache/loose-mutated-instruction.jsonl >/tmp/hq_mutated_accept.out 2>/tmp/hq_mutated_accept.err; then
  echo 'expected mutated suggestion to be rejected by canonical hash validation' >&2
  exit 1
fi

go run ./cmd/hq pty-vim-rsc-visual-proof \
  --world examples/tree_world.jsonl \
  --chars 'project hq tasks ' \
  --out cache/loose-visual.json \
  --trace cache/loose-visual.trace.jsonl \
  --screen-text cache/loose-visual.screen.txt \
  --raw cache/loose-visual.pty.raw

python3 - <<'PY'
import json
from pathlib import Path
r=json.load(open('cache/loose-visual.json'))
assert r['visual_projection_ok'] is True, r
assert r['direct_vim_no_shell'] is True, r
sample=r['final_popup_sample']
assert sample['slot_kind']=='draft.ref', sample
assert sample['slot_path']==['tasks'], sample
assert sample['labels']==['task:t1','task:t2','task:t3'], sample
screen=Path('cache/loose-visual.screen.txt').read_text()
for needle in ['HQ SLOT PROJECTION','slot: draft.ref','draft: project.patch op: append-ref','task:t1','task:t2','task:t3']:
    assert needle in screen, needle
PY

echo LOOSE_DRAFT_VALIDATION_PROOF_OK
