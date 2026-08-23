#!/usr/bin/env bash
set -Eeuo pipefail

BASE=05f10d7105682f2346f8f741fa609af3faf33ee1
V21=7e7f02782315c4574affe31c7c945fdfa9e99157
SOURCE_BRANCH=ux/focused-e2e-merge-source-v23-20260824
FINAL_BRANCH=ux/focused-e2e-merge-final-v23-20260824
EXPECTED_HQ=779a298f4efcff8df60205aaf973cb224388a82b
EVIDENCE=${EVIDENCE:-/tmp/focused-e2e-owned-boundaries-v23}

rm -rf "$EVIDENCE"
mkdir -p "$EVIDENCE"/{source,product,e2e,runtime}

test "$(git rev-parse HEAD)" = "$V21"
test "$(git rev-parse HEAD^)" = "$BASE"

python3 - <<'PY'
from pathlib import Path
import json

world = Path('proofs/vim-nix/fixtures/runtime-world.jsonl')
lines = world.read_text(encoding='utf-8').splitlines()
if len(lines) != 3:
    raise SystemExit(f'unexpected runtime world rows={len(lines)}')
rows = [json.loads(line) for line in lines]
tools = [row for row in rows if row.get('kind') == 'hq.local-tool.v1' and row.get('tool_id') == 'proof-sh']
if len(tools) != 1 or tools[0].get('binding_contract_version') != '1':
    raise SystemExit(f'unexpected proof-sh binding contract: {tools}')
tools[0]['binding_contract_version'] = '2'
world.write_text('\n'.join(json.dumps(row, ensure_ascii=False, separators=(',', ':')) for row in rows) + '\n', encoding='utf-8')

part = Path('proofs/vim-nix/run-proof.parts/02.sh')
s = part.read_text(encoding='utf-8')
old = '''jq -n --arg digest "sha256:$proof_sha" --arg executable "$PROOF/bin/proof-sh" '{
  schema:"envctl.verified-executable-bindings.v1",
  entries:[{
    bindingRef:"local-tool.proof-sh",
    resourceId:"proof-sh",
    contractVersion:"1",
    executable:$executable,
    materialDigest:$digest,
    deploymentId:("proof-sh@1:" + $digest),
    declarationEventId:"vim-nix-proof.declare.proof-sh.v1",
    selectionEventId:"vim-nix-proof.select.proof-sh.v1"
  }]
}' > "$BINDINGS"
'''
new = '''provider_log="$RUNTIME/provider-invocations.jsonl"
configuration_sha="$(printf 'envctl.verifiedExecutableBinding.environment.v1\\0HQ_PROOF_PROVIDER_LOG\\0%s\\0' "$provider_log" | sha256sum | awk '{print $1}')"
configuration_digest="sha256:$configuration_sha"
jq -n \\
  --arg digest "sha256:$proof_sha" \\
  --arg executable "$PROOF/bin/proof-sh" \\
  --arg provider_log "$provider_log" \\
  --arg configuration_digest "$configuration_digest" '{
  schema:"envctl.verified-executable-bindings.v1",
  entries:[{
    bindingRef:"local-tool.proof-sh",
    resourceId:"proof-sh",
    contractVersion:"2",
    executable:$executable,
    materialDigest:$digest,
    environment:[{name:"HQ_PROOF_PROVIDER_LOG",value:$provider_log}],
    configurationDigest:$configuration_digest,
    deploymentId:("proof-sh@1:" + $digest),
    declarationEventId:"vim-nix-proof.declare.proof-sh.v1",
    selectionEventId:"vim-nix-proof.select.proof-sh.v1"
  }]
}' > "$BINDINGS"
'''
if s.count(old) != 1:
    raise SystemExit(f'binding block matches={s.count(old)}')
s = s.replace(old, new, 1)
needle = '''test "$(jq '[.[] | select(.version == "result.v1") | .instruction_id] | unique | length' "$OUT/result-events.json")" -eq 1 \\
  || fail "result chain has multiple instruction IDs"
'''
extra = needle + '''
test -s "$provider_log" || fail "proof provider invocation log is missing"
jq -s -e 'length == 1 and .[0].version == "worker.provider-invocation-proof.v1" and .[0].fixture_only == true and .[0].provider == "sh" and .[0].argv == ["echo","hq-vim-e2e-ok"] and .[0].stdin_bytes == 0' "$provider_log" >/dev/null \\
  || fail "proof provider invocation evidence is invalid"
cp "$provider_log" "$OUT/provider-invocations.jsonl"
'''
if s.count(needle) != 1:
    raise SystemExit(f'result tail matches={s.count(needle)}')
s = s.replace(needle, extra, 1)
part.write_text(s, encoding='utf-8')
PY

git diff --check
changed=$(git diff --name-only "$V21" | sort)
printf '%s\n' "$changed" | tee "$EVIDENCE/source/v21-delta-paths.txt"
test "$changed" = $'proofs/vim-nix/fixtures/runtime-world.jsonl\nproofs/vim-nix/run-proof.parts/02.sh'
(cd packages/hq-vim && go test ./... -count=1) | tee "$EVIDENCE/source/go-test.log"
mapfile -t focused < <(grep -Rh '^func Test' packages/hq-vim --include='*_test.go' | sed -E 's/^func (Test[^ (]+).*/\1/' | sort)
expected=(TestAcceptedSubmitKeepsDraftOnUnsafeConsumption TestAgentDecisionSubmitE2E TestAgentDefaultChoiceE2E TestAgentPromptFieldChoiceE2E TestDirectCommandSubmitE2E TestDirectFallbackChoiceE2E TestEditorSurfaceAndBindingFailClosed TestUnicodeDirectFieldValueE2E)
test "${focused[*]}" = "${expected[*]}"
printf '%s\n' "${focused[@]}" > "$EVIDENCE/source/focused-tests.txt"
for removed in packages/hq-vim/internal/smoke/tty_test.go proofs/vim-nix/hq-vim-native-popup-proof.patch tools/vim-nix-local/feedkeys-race.vim; do test ! -e "$removed"; done
test -z "$(git diff --name-only "$BASE" | grep -F '.github/workflows/' || true)"
test -z "$(git diff --name-only "$BASE" | grep -Fx proofs/vim-nix/run.trigger || true)"
test -z "$(git diff --name-only "$BASE" | grep -E '\.(png|jpe?g|webp)$' || true)"

git add proofs/vim-nix/fixtures/runtime-world.jsonl proofs/vim-nix/run-proof.parts/02.sh
tree=$(git write-tree)
export GIT_AUTHOR_NAME=roccho GIT_AUTHOR_EMAIL=40359643+roccho-dev@users.noreply.github.com
export GIT_COMMITTER_NAME=roccho GIT_COMMITTER_EMAIL=40359643+roccho-dev@users.noreply.github.com
export GIT_AUTHOR_DATE=2026-08-24T00:00:05Z GIT_COMMITTER_DATE=2026-08-24T00:00:05Z
source=$(printf '%s\n' 'fix(vim-nix): bind proof provider log to writable runtime' | git commit-tree "$tree" -p "$BASE")
test "$(git rev-parse "$source^")" = "$BASE"
printf 'base=%s\nv21=%s\nsource=%s\ntree=%s\n' "$BASE" "$V21" "$source" "$tree" | tee "$EVIDENCE/source/identity.txt"
git diff --name-status "$BASE" "$source" > "$EVIDENCE/source/change-paths.txt"
if git ls-remote --exit-code --heads origin "$SOURCE_BRANCH" >/dev/null 2>&1; then
  test "$(git ls-remote --heads origin "$SOURCE_BRANCH" | awk '{print $1}')" = "$source"
else
  git push origin "$source:refs/heads/$SOURCE_BRANCH"
fi

git checkout --detach "$source"
python3 - "$source" <<'PY'
from pathlib import Path
import sys
commit = sys.argv[1]
flake = Path('proofs/vim-nix/flake.nix')
text = flake.read_text(encoding='utf-8')
needle = '  inputs = {\n'
insert = '  inputs = {\n    editsSource = {\n      url = "github:roccho-dev/edits/' + commit + '";\n      flake = false;\n    };\n'
if text.count(needle) != 1:
    raise SystemExit('unexpected flake inputs shape')
flake.write_text(text.replace(needle, insert, 1), encoding='utf-8')
part = Path('proofs/vim-nix/flake.parts/00.nix')
text = part.read_text(encoding='utf-8')
old_src = '      edits-src = self.outPath;'
new_src = '      edits-src = inputs.editsSource.outPath;'
old_rev = '      editsRevision = if self ? rev then self.rev else if self ? dirtyRev then self.dirtyRev else "dirty";'
new_rev = '      editsRevision = if inputs.editsSource ? rev then inputs.editsSource.rev else "unknown";'
if text.count(old_src) != 1 or text.count(old_rev) != 1:
    raise SystemExit('unexpected source identity shape')
part.write_text(text.replace(old_src, new_src, 1).replace(old_rev, new_rev, 1), encoding='utf-8')
PY
pushd proofs/vim-nix >/dev/null
nix flake lock --update-input editsSource
popd >/dev/null
test "$(jq -r '.nodes.editsSource.locked.rev' proofs/vim-nix/flake.lock)" = "$source"
test "$(jq -r '.nodes.hq.locked.rev' proofs/vim-nix/flake.lock)" = "$EXPECTED_HQ"
git add proofs/vim-nix/flake.nix proofs/vim-nix/flake.parts/00.nix proofs/vim-nix/flake.lock
git diff --cached --check -- . ':(exclude)proofs/vim-nix/yegappan-lsp-unicode.patch'
proof_tree=$(git write-tree)
export GIT_AUTHOR_DATE=2026-08-24T00:00:06Z GIT_COMMITTER_DATE=2026-08-24T00:00:06Z
proof=$(printf '%s\n' 'proof(vim-nix): pin exact focused E2E source' | git commit-tree "$proof_tree" -p "$source")
git checkout --detach "$proof"
test "$(git rev-parse HEAD^)" = "$source"
printf 'source=%s\nproof=%s\ntree=%s\n' "$source" "$proof" "$proof_tree" | tee "$EVIDENCE/product/proof-identity.txt"

pushd proofs/vim-nix >/dev/null
before=$(sha256sum flake.lock | cut -d' ' -f1)
product=$(nix build --no-link --print-out-paths .#default)
offline=$(nix build --offline --no-write-lock-file --no-link --print-out-paths .#default)
after=$(sha256sum flake.lock | cut -d' ' -f1)
popd >/dev/null
test "$product" = "$offline"
test "$before" = "$after"
jq -e --arg source "$source" '.editsRevision == $source' "$product/share/proof/source.json" >/dev/null
printf '%s\n' "$product" | tee "$EVIDENCE/product/store-path.txt"
cp "$product/share/proof/source.json" "$EVIDENCE/product/source.json"

export HQ_BIN="$product/bin/hq" VIM_EXE="$product/bin/vim" VIM9_LSP_PATH="$product/share/yegappan-lsp" VIMRUNTIME="$product/share/vim/vim92" LANG=C.UTF-8 LC_ALL=C.UTF-8 TERM=xterm-256color
for t in TestAgentDefaultChoiceE2E TestAgentPromptFieldChoiceE2E TestDirectFallbackChoiceE2E TestUnicodeDirectFieldValueE2E; do
  echo "E2E $t"
  cmd=$(printf 'cd %q && stty cols 180 rows 55 && HQ_CHOICE_E2E=1 HQ_BIN=%q VIM_EXE=%q VIM9_LSP_PATH=%q VIMRUNTIME=%q LANG=C.UTF-8 LC_ALL=C.UTF-8 TERM=xterm-256color %q -test.v -test.count=1 -test.run %q' "$product/share/hq-vim" "$HQ_BIN" "$VIM_EXE" "$VIM9_LSP_PATH" "$VIMRUNTIME" "$product/bin/hq-vim.test" "^${t}$")
  timeout 90s script -qefc "$cmd" "$EVIDENCE/e2e/${t}.typescript" | tee "$EVIDENCE/e2e/${t}.log"
  grep -F -- "--- PASS: $t" "$EVIDENCE/e2e/${t}.log" >/dev/null
done
for t in TestEditorSurfaceAndBindingFailClosed TestAgentDecisionSubmitE2E TestDirectCommandSubmitE2E TestAcceptedSubmitKeepsDraftOnUnsafeConsumption; do
  echo "E2E $t"
  (cd "$product/share/hq-vim" && "$product/bin/hq-vim.test" -test.v -test.count=1 -test.run "^${t}$") | tee "$EVIDENCE/e2e/${t}.log"
  grep -F -- "--- PASS: $t" "$EVIDENCE/e2e/${t}.log" >/dev/null
done

cat proofs/vim-nix/run-proof.parts/*.sh > "$RUNNER_TEMP/runtime-proof-v23.sh"
chmod 700 "$RUNNER_TEMP/runtime-proof-v23.sh"
PROOF_ROOT="$product" PROOF_OUTPUT_DIR="$EVIDENCE/runtime" PROOF_RUNTIME_DIR="$RUNNER_TEMP/runtime-v23" PROOF_RUN_SUFFIX=v23 "$RUNNER_TEMP/runtime-proof-v23.sh" | tee "$EVIDENCE/runtime/stdout.log"
jq -e '.status == "PASS" and .gates.resultKinds == ["accepted", "started", "stdout", "completed"] and .gates.residualProcessCount == 0' "$EVIDENCE/runtime/receipt.json" >/dev/null
test -s "$EVIDENCE/runtime/provider-invocations.jsonl"

if git ls-remote --exit-code --heads origin "$FINAL_BRANCH" >/dev/null 2>&1; then
  test "$(git ls-remote --heads origin "$FINAL_BRANCH" | awk '{print $1}')" = "$proof"
else
  git push origin "$proof:refs/heads/$FINAL_BRANCH"
fi
jq -n --arg base "$BASE" --arg source "$source" --arg sourceTree "$tree" --arg proof "$proof" --arg proofTree "$proof_tree" --arg product "$product" '{schema:"edits.focused-e2e-owned-boundaries/11",status:"PASS",base:$base,sourceCommit:$source,sourceTree:$sourceTree,proofCommit:$proof,proofTree:$proofTree,productStorePath:$product,editorBehaviorE2Es:8,runtimeLifecycleE2Es:1,popupUndo:"CompleteChanged synchronously prepends Ctrl-G u before candidate selection",relativeBindingFixture:"writable t.TempDir projected as relative path from package root",providerLogBinding:"verified binding contract 2 to writable runtime path",resultKinds:["accepted","started","stdout","completed"],residualProcessCount:0,screenshotsPushed:false,e2eComposition:false}' > "$EVIDENCE/receipt.json"
(cd "$EVIDENCE" && find . -type f ! -name SHA256SUMS -print0 | sort -z | xargs -0 sha256sum > SHA256SUMS && sha256sum --check SHA256SUMS)
printf 'V23_PASS source=%s proof=%s product=%s\n' "$source" "$proof" "$product"
