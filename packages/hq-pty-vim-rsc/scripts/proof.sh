#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
rm -f cache/model.reduced.json cache/*.plan.json cache/*receipt*.jsonl cache/lsp-typed.jsonl cache/vim-autocmp.jsonl cache/vim-autocmp-buffer.txt cache/*.out

go test ./...
go run ./cmd/hq model --world examples/world.jsonl --out cache/model.reduced.json

go run ./cmd/hq complete --world examples/world.jsonl --line 'http.' > cache/http-completion.json
go run ./cmd/hq complete --world examples/world.jsonl --line 'shell.' > cache/shell-completion.json

python3 scripts/http_fixture.py &
HTTP_PID=$!
trap 'kill "$HTTP_PID" 2>/dev/null || true' EXIT
sleep 0.25

go run ./cmd/hq plan --world examples/world.jsonl --command 'http.get http://127.0.0.1:18080/health save=health' --version 2 --out cache/http.plan.json
go run ./cmd/hq dispatch --plan cache/http.plan.json --receipts cache/main.receipt.jsonl > cache/http.dispatch.json

go run ./cmd/hq plan --world examples/world.jsonl --command 'shell.exec "printf hq-shell-ok" timeout=2s' --version 3 --out cache/shell.plan.json
if go run ./cmd/hq dispatch --plan cache/shell.plan.json --receipts cache/main.receipt.jsonl > cache/shell.no-confirm.out 2>&1; then
  echo 'expected shell dispatch without confirm to fail' >&2
  exit 1
fi
go run ./cmd/hq dispatch --plan cache/shell.plan.json --confirmed --receipts cache/main.receipt.jsonl > cache/shell.dispatch.json

go run ./cmd/hq lsp-type-smoke --world examples/world.jsonl --chars 'pane.shell.' --out cache/lsp-typed.jsonl
vim -Nu NONE -n -es -S scripts/vim_char_autocmp.vim >/tmp/hq_vim_autocmp.out 2>/tmp/hq_vim_autocmp.err || { cat /tmp/hq_vim_autocmp.err >&2; exit 1; }

grep -q 'hq-http-ok' cache/http.dispatch.json
grep -q 'hq-shell-ok' cache/shell.dispatch.json
grep -q 'send git status' cache/lsp-typed.jsonl
grep -q 'send git status' cache/vim-autocmp.jsonl

echo PROOF_OK
