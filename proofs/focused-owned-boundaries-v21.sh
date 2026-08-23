#!/usr/bin/env bash
set -Eeuo pipefail

BASE=05f10d7105682f2346f8f741fa609af3faf33ee1
V20=a7c252d338342349cc352798b46f954f7de8a5a4
SOURCE_BRANCH=ux/focused-e2e-merge-source-v21-20260824
FINAL_BRANCH=ux/focused-e2e-merge-final-v21-20260824
EXPECTED_HQ=779a298f4efcff8df60205aaf973cb224388a82b
EVIDENCE=${EVIDENCE:-/tmp/focused-e2e-owned-boundaries-v21}

rm -rf "$EVIDENCE"
mkdir -p "$EVIDENCE"/{source,product,e2e,runtime}

test "$(git rev-parse HEAD)" = "$V20"
test "$(git rev-parse HEAD^)" = "$BASE"

python3 - <<'PY'
from pathlib import Path
p = Path('packages/hq-vim/hq_vim_smoke_test.go')
s = p.read_text(encoding='utf-8')
old = '''\tt.Run("relative binding", func(t *testing.T) {\n\t\trelativeDir := filepath.Join(root, ".tmp", "relative-hq-test")\n\t\tif err := os.MkdirAll(relativeDir, 0o755); err != nil {\n\t\t\tt.Fatal(err)\n\t\t}\n\t\tdefer os.RemoveAll(relativeDir)\n\t\trelative := filepath.Join(".tmp", "relative-hq-test", exeName("hqstub"))\n\t\tif err := os.WriteFile(filepath.Join(root, relative), []byte("not executed"), 0o755); err != nil {\n\t\t\tt.Fatal(err)\n\t\t}\n'''
new = '''\tt.Run("relative binding", func(t *testing.T) {\n\t\tabsolute := filepath.Join(t.TempDir(), exeName("hqstub"))\n\t\tif err := os.WriteFile(absolute, []byte("not executed"), 0o755); err != nil {\n\t\t\tt.Fatal(err)\n\t\t}\n\t\trelative, err := filepath.Rel(root, absolute)\n\t\tif err != nil {\n\t\t\tt.Fatal(err)\n\t\t}\n\t\tif filepath.IsAbs(relative) || filepath.Clean(filepath.Join(root, relative)) != filepath.Clean(absolute) {\n\t\t\tt.Fatalf("fixture is not an existing relative path: root=%q absolute=%q relative=%q", root, absolute, relative)\n\t\t}\n'''
if s.count(old) != 1:
    raise SystemExit(f'relative binding fixture matches={s.count(old)}')
p.write_text(s.replace(old, new, 1), encoding='utf-8')
PY

git diff --check
test "$(git diff --name-only "$V20" | tr -d '\n')" = packages/hq-vim/hq_vim_smoke_test.go
(cd packages/hq-vim && go test ./... -count=1) | tee "$EVIDENCE/source/go-test.log"
mapfile -t focused < <(grep -Rh '^func Test' packages/hq-vim --include='*_test.go' | sed -E 's/^func (Test[^ (]+).*/\1/' | sort)
expected=(TestAcceptedSubmitKeepsDraftOnUnsafeConsumption TestAgentDecisionSubmitE2E TestAgentDefaultChoiceE2E TestAgentPromptFieldChoiceE2E TestDirectCommandSubmitE2E TestDirectFallbackChoiceE2E TestEditorSurfaceAndBindingFailClosed TestUnicodeDirectFieldValueE2E)
test "${focused[*]}" = "${expected[*]}"
printf '%s\n' "${focused[@]}" > "$EVIDENCE/source/focused-tests.txt"
for removed in packages/hq-vim/internal/smoke/tty_test.go proofs/vim-nix/hq-vim-native-popup-proof.patch tools/vim-nix-local/feedkeys-race.vim; do test ! -e "$removed"; done
test -z "$(git diff --name-only "$BASE" | grep -F '.github/workflows/' || true)"
test -z "$(git diff --name-only "$BASE" | grep -Fx proofs/vim-nix/run.trigger || true)"
test -z "$(git diff --name-only "$BASE" | grep -E '\.(png|jpe?g|webp)$' || true)"

git add packages/hq-vim/hq_vim_smoke_test.go
tree=$(git write-tree)
export GIT_AUTHOR_NAME=roccho GIT_AUTHOR_EMAIL=40359643+roccho-dev@users.noreply.github.com
export GIT_COMMITTER_NAME=roccho GIT_COMMITTER_EMAIL=40359643+roccho-dev@users.noreply.github.com
export GIT_AUTHOR_DATE=2026-08-24T00:00:03Z GIT_COMMITTER_DATE=2026-08-24T00:00:03Z
source=$(printf '%s\n' 'fix(hq-vim): keep relative binding fixture outside immutable source' | git commit-tree "$tree" -p "$BASE")
test "$(git rev-parse "$source^")" = "$BASE"
printf 'base=%s\nv20=%s\nsource=%s\ntree=%s\n' "$BASE" "$V20" "$source" "$tree" | tee "$EVIDENCE/source/identity.txt"
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
export GIT_AUTHOR_DATE=2026-08-24T00:00:04Z GIT_COMMITTER_DATE=2026-08-24T00:00:04Z
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

cat proofs/vim-nix/run-proof.parts/*.sh > "$RUNNER_TEMP/runtime-proof-v21.sh"
chmod 700 "$RUNNER_TEMP/runtime-proof-v21.sh"
PROOF_ROOT="$product" PROOF_OUTPUT_DIR="$EVIDENCE/runtime" PROOF_RUNTIME_DIR="$RUNNER_TEMP/runtime-v21" PROOF_RUN_SUFFIX=v21 "$RUNNER_TEMP/runtime-proof-v21.sh" | tee "$EVIDENCE/runtime/stdout.log"
jq -e '.status == "PASS" and .gates.resultKinds == ["accepted", "started", "stdout", "completed"] and .gates.residualProcessCount == 0' "$EVIDENCE/runtime/receipt.json" >/dev/null

if git ls-remote --exit-code --heads origin "$FINAL_BRANCH" >/dev/null 2>&1; then
  test "$(git ls-remote --heads origin "$FINAL_BRANCH" | awk '{print $1}')" = "$proof"
else
  git push origin "$proof:refs/heads/$FINAL_BRANCH"
fi
jq -n --arg base "$BASE" --arg source "$source" --arg sourceTree "$tree" --arg proof "$proof" --arg proofTree "$proof_tree" --arg product "$product" '{schema:"edits.focused-e2e-owned-boundaries/10",status:"PASS",base:$base,sourceCommit:$source,sourceTree:$sourceTree,proofCommit:$proof,proofTree:$proofTree,productStorePath:$product,editorBehaviorE2Es:8,runtimeLifecycleE2Es:1,popupUndo:"CompleteChanged synchronously prepends Ctrl-G u before candidate selection",relativeBindingFixture:"writable t.TempDir projected as relative path from package root",resultKinds:["accepted","started","stdout","completed"],residualProcessCount:0,screenshotsPushed:false,e2eComposition:false}' > "$EVIDENCE/receipt.json"
(cd "$EVIDENCE" && find . -type f ! -name SHA256SUMS -print0 | sort -z | xargs -0 sha256sum > SHA256SUMS && sha256sum --check SHA256SUMS)
printf 'V21_PASS source=%s proof=%s product=%s\n' "$source" "$proof" "$product"
