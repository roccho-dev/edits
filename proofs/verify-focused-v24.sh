#!/usr/bin/env bash
set -Eeuo pipefail

BASE=05f10d7105682f2346f8f741fa609af3faf33ee1
SOURCE=788245e5a19b40f6392511c28297227ccb2e8f30
SOURCE_TREE=8fff279877e722f02d7d7894602bfeb7187d5c11
FINAL_BRANCH=ux/focused-e2e-merge-final-v24-20260824
EXPECTED_HQ=779a298f4efcff8df60205aaf973cb224388a82b
EXPECTED_WORLD=sha256:b6a0305d852a06178338bac8a49f5087b080895447f743a1e5981ab85e389dec
EXPECTED_ACCEPTED_INPUT=sha256:bad5b8f0ef8fa588fdd325049839563289211bf986a8d5a3c72a8ee84dd9f4da
EVIDENCE=${EVIDENCE:-/tmp/focused-e2e-v24}

rm -rf "$EVIDENCE"
mkdir -p "$EVIDENCE"/{source,product,e2e,runtime}

test "$(git rev-parse HEAD)" = "$SOURCE"
test "$(git rev-parse HEAD^)" = "$BASE"
test "$(git rev-parse HEAD^{tree})" = "$SOURCE_TREE"

git diff --check "$BASE" "$SOURCE"
(cd packages/hq-vim && go test ./... -count=1) | tee "$EVIDENCE/source/go-test.log"
mapfile -t focused < <(grep -Rh '^func Test' packages/hq-vim --include='*_test.go' | sed -E 's/^func (Test[^ (]+).*/\1/' | sort)
expected=(TestAcceptedSubmitKeepsDraftOnUnsafeConsumption TestAgentDecisionSubmitE2E TestAgentDefaultChoiceE2E TestAgentPromptFieldChoiceE2E TestDirectCommandSubmitE2E TestDirectFallbackChoiceE2E TestEditorSurfaceAndBindingFailClosed TestUnicodeDirectFieldValueE2E)
test "${focused[*]}" = "${expected[*]}"
printf '%s\n' "${focused[@]}" > "$EVIDENCE/source/focused-tests.txt"
for removed in packages/hq-vim/internal/smoke/tty_test.go proofs/vim-nix/hq-vim-native-popup-proof.patch tools/vim-nix-local/feedkeys-race.vim; do test ! -e "$removed"; done
test -z "$(git diff --name-only "$BASE" "$SOURCE" | grep -F '.github/workflows/' || true)"
test -z "$(git diff --name-only "$BASE" "$SOURCE" | grep -Fx proofs/vim-nix/run.trigger || true)"
test -z "$(git diff --name-only "$BASE" "$SOURCE" | grep -E '\.(png|jpe?g|webp)$' || true)"

accepted=proofs/vim-nix/fixtures/runtime-accepted.jsonl
test "$(jq -r '.provenance.world.digest' "$accepted")" = "$EXPECTED_WORLD"
test "$(jq -r '.accepted_input.world.digest' "$accepted")" = "$EXPECTED_WORLD"
test "$(jq -r '.accepted_input.accepted_input_digest' "$accepted")" = "$EXPECTED_ACCEPTED_INPUT"
test "$(jq -r 'select(.kind=="hq.local-tool.v1" and .tool_id=="proof-sh") | .binding_contract_version' proofs/vim-nix/fixtures/runtime-world.jsonl)" = 2
printf 'base=%s\nsource=%s\ntree=%s\n' "$BASE" "$SOURCE" "$SOURCE_TREE" > "$EVIDENCE/source/identity.txt"
git diff --name-status "$BASE" "$SOURCE" > "$EVIDENCE/source/change-paths.txt"

python3 - "$SOURCE" <<'PY'
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
test "$(jq -r '.nodes.editsSource.locked.rev' proofs/vim-nix/flake.lock)" = "$SOURCE"
test "$(jq -r '.nodes.hq.locked.rev' proofs/vim-nix/flake.lock)" = "$EXPECTED_HQ"
git add proofs/vim-nix/flake.nix proofs/vim-nix/flake.parts/00.nix proofs/vim-nix/flake.lock
git diff --cached --check -- . ':(exclude)proofs/vim-nix/yegappan-lsp-unicode.patch'
proof_tree=$(git write-tree)
export GIT_AUTHOR_NAME=roccho GIT_AUTHOR_EMAIL=40359643+roccho-dev@users.noreply.github.com
export GIT_COMMITTER_NAME=roccho GIT_COMMITTER_EMAIL=40359643+roccho-dev@users.noreply.github.com
export GIT_AUTHOR_DATE=2026-08-24T00:00:07Z GIT_COMMITTER_DATE=2026-08-24T00:00:07Z
proof=$(printf '%s\n' 'proof(vim-nix): pin exact v24 focused source' | git commit-tree "$proof_tree" -p "$SOURCE")
git checkout --detach "$proof"
test "$(git rev-parse HEAD^)" = "$SOURCE"
printf 'source=%s\nproof=%s\ntree=%s\n' "$SOURCE" "$proof" "$proof_tree" | tee "$EVIDENCE/product/proof-identity.txt"

pushd proofs/vim-nix >/dev/null
before=$(sha256sum flake.lock | cut -d' ' -f1)
product=$(nix build --no-link --print-out-paths .#default)
offline=$(nix build --offline --no-write-lock-file --no-link --print-out-paths .#default)
after=$(sha256sum flake.lock | cut -d' ' -f1)
popd >/dev/null
test "$product" = "$offline"
test "$before" = "$after"
jq -e --arg source "$SOURCE" '.editsRevision == $source' "$product/share/proof/source.json" >/dev/null
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

cat proofs/vim-nix/run-proof.parts/*.sh > "$RUNNER_TEMP/runtime-proof-v24.sh"
chmod 700 "$RUNNER_TEMP/runtime-proof-v24.sh"
PROOF_ROOT="$product" PROOF_OUTPUT_DIR="$EVIDENCE/runtime" PROOF_RUNTIME_DIR="$RUNNER_TEMP/runtime-v24" PROOF_RUN_SUFFIX=v24 "$RUNNER_TEMP/runtime-proof-v24.sh" | tee "$EVIDENCE/runtime/stdout.log"
jq -e '.status == "PASS" and .gates.resultKinds == ["accepted", "started", "stdout", "completed"] and .gates.finalText == "hq-vim-e2e-ok" and .gates.residualProcessCount == 0' "$EVIDENCE/runtime/receipt.json" >/dev/null
test -s "$EVIDENCE/runtime/provider-invocations.jsonl"
jq -s -e 'length == 1 and .[0].version == "worker.provider-invocation-proof.v1" and .[0].fixture_only == true and .[0].provider == "sh" and .[0].argv == ["echo","hq-vim-e2e-ok"] and .[0].stdin_bytes == 0' "$EVIDENCE/runtime/provider-invocations.jsonl" >/dev/null

if git ls-remote --exit-code --heads origin "$FINAL_BRANCH" >/dev/null 2>&1; then
  test "$(git ls-remote --heads origin "$FINAL_BRANCH" | awk '{print $1}')" = "$proof"
else
  git push origin "$proof:refs/heads/$FINAL_BRANCH"
fi
jq -n --arg base "$BASE" --arg source "$SOURCE" --arg sourceTree "$SOURCE_TREE" --arg proof "$proof" --arg proofTree "$proof_tree" --arg product "$product" '{schema:"edits.focused-v24-final/1",status:"PASS",base:$base,sourceCommit:$source,sourceTree:$sourceTree,proofCommit:$proof,proofTree:$proofTree,productStorePath:$product,nixNormalOfflineSameStorePath:true,editorBehaviorE2Es:8,runtimeLifecycleE2Es:1,resultKinds:["accepted","started","stdout","completed"],finalText:"hq-vim-e2e-ok",residualProcessCount:0,providerInvocationEvidence:true}' > "$EVIDENCE/receipt.json"
(cd "$EVIDENCE" && find . -type f ! -name SHA256SUMS -print0 | sort -z | xargs -0 sha256sum > SHA256SUMS && sha256sum --check SHA256SUMS)
printf 'V24_PASS source=%s tree=%s proof=%s product=%s\n' "$SOURCE" "$SOURCE_TREE" "$proof" "$product"
