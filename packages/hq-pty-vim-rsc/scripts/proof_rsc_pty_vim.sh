#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
rm -f cache/rsc-*.json cache/instruction.jsonl cache/pty-vim-*.json cache/pty-vim-*.jsonl cache/pty-vim-proof.json.screen

go test ./...

go run ./cmd/hq rsc-model --world examples/tree_world.jsonl --out cache/rsc-model.json

go run ./cmd/hq rsc-complete --world examples/tree_world.jsonl --buffer '{"kind":"project",' --cursor end --version 101 --out cache/rsc-key-complete.json
python3 - <<'PY'
import json,sys
r=json.load(open('cache/rsc-key-complete.json'))
labels=[s['label'] for s in r['suggestions']]
assert r['context']['slot']['kind']=='object.key', r['context']
for x in ['id','name','tasks']:
    assert x in labels, labels
assert 'kind' not in labels, labels
for s in r['suggestions']:
    assert s['compile_draft']['side_effect'] is False, s
PY

go run ./cmd/hq rsc-complete --world examples/tree_world.jsonl --buffer '{"kind":"project","status":' --cursor end --version 102 --out cache/rsc-value-complete.json
python3 - <<'PY'
import json
r=json.load(open('cache/rsc-value-complete.json'))
labels=[s['label'] for s in r['suggestions']]
assert r['context']['slot']['kind']=='object.value', r['context']
for x in ['active','paused','archived']:
    assert x in labels, labels
PY

go run ./cmd/hq rsc-complete --world examples/tree_world.jsonl --buffer '{"kind":"project","tasks":[' --cursor end --version 103 --out cache/rsc-array-complete.json
python3 - <<'PY'
import json
r=json.load(open('cache/rsc-array-complete.json'))
labels=[s['label'] for s in r['suggestions']]
assert r['context']['slot']['kind']=='array.item', r['context']
assert r['context']['slot']['path']==['tasks'], r['context']
for x in ['task:t1','task:t2','task:t3']:
    assert x in labels, labels
for s in r['suggestions']:
    assert s['compile_draft']['operation']=='append-ref', s
    assert s['compile_draft']['side_effect'] is False, s
PY

go run ./cmd/hq rsc-accept --suggestion cache/rsc-array-complete.json --index 0 --queue cache/instruction.jsonl --out cache/rsc-accepted-instruction.json
python3 - <<'PY'
import json
row=json.loads(open('cache/instruction.jsonl').read().strip())
assert row['kind']=='instruction.accepted', row
assert row['compile_draft']['operation']=='append-ref', row
assert row['compile_draft']['ref']=='task:t1', row
PY

go run ./cmd/hq pty-vim-rsc-proof --world examples/tree_world.jsonl --out cache/pty-vim-proof.json --trace cache/pty-vim-slot-autocmp.jsonl
python3 - <<'PY'
import json
r=json.load(open('cache/pty-vim-proof.json'))
assert r['direct_vim_no_shell'] is True, r
assert r['vim_buffer_saved'] is True, r
assert r['slot_autocomplete_ok'] is True, r
assert r['final_slot_sample']['slot_kind']=='array.item', r
assert r['final_slot_sample']['labels']==['task:t1','task:t2','task:t3'], r
assert '\x00sh\x00' not in r['proc_cmdline'], r
PY

echo RSC_PTY_VIM_PROOF_OK
