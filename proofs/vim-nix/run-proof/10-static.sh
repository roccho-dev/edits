# Static identity and binary gates.
"$proof_root/bin/herdr" --version >"$output/herdr.version.txt"
grep -Fxq 'herdr 0.8.0' "$output/herdr.version.txt"
"$proof_root/bin/vim" --version >"$output/vim.version.txt"
grep -q '^VIM - Vi IMproved 9\.2' "$output/vim.version.txt"
grep -Eq 'patches: 1-478|Included patches: 1-478' "$output/vim.version.txt"
for feature in '+vim9script' '+channel' '+timers' '+popupwin' '+insert_expand' '+multi_byte' '+terminal'; do
  grep -Fq "$feature" "$output/vim.version.txt"
done
for forbidden in '+python' '+python3' '+ruby' '+lua' '+X11' '+wayland' '+GUI'; do
  if grep -Fq "$forbidden" "$output/vim.version.txt"; then
    echo "forbidden Vim surface present: $forbidden" >&2
    exit 1
  fi
done
"$proof_root/bin/vim" -Nu NONE -n -i NONE -es \
  '+if v:version != 902 || !has("patch-9.2.478") || !has("vim9script") || !has("channel") || !has("timers") || !has("popupwin") || !has("insert_expand") || !has("multi_byte") || !has("terminal") | cquit 41 | endif' \
  '+quitall!'
[[ -f "$proof_root/bin/proof-sh" && ! -L "$proof_root/bin/proof-sh" ]]

rows="$runtime/binaries.jsonl"
: >"$rows"
for name in herdr vim hq hq-worker hq-worker-proof-provider proof-sh hq-vim.test hq-vim-smoke run-vim-nix-proof; do
  path="$proof_root/bin/$name"
  resolved=$(readlink -f "$path")
  bytes=$(stat -c '%s' "$resolved")
  sha=$(sha256sum "$resolved" | awk '{print $1}')
  symlink=false; [[ -L "$path" ]] && symlink=true
  regular=false; [[ -f "$path" ]] && regular=true
  jq -nc --arg name "$name" --arg path "$path" --arg resolved "$resolved" \
    --arg sha "$sha" --argjson bytes "$bytes" --argjson symlink "$symlink" --argjson regular "$regular" \
    '{name:$name,path:$path,resolved:$resolved,bytes:$bytes,sha256:$sha,symlink:$symlink,regular:$regular}' >>"$rows"
done
jq -s '{schema:"edits.vimNixProof.binaries/1",status:"PASS",rows:(map({key:.name,value:(del(.name))})|from_entries)}' \
  "$rows" >"$output/binaries.json"
jq -e '.rows["proof-sh"] | .regular == true and .symlink == false' "$output/binaries.json" >/dev/null

# Existing canonical headless conformance, against the final minimal closure.
mkdir -p "$output/headless"
(
  cd "$proof_root/share/hq-vim"
  HQ_CANONICAL_BIN="$proof_root/bin/hq" \
  HQ_CANONICAL_SOURCE_SHA=3118886f34ac5615e8a7732a6297bd41900e21e1 \
  HQ_CONFORMANCE_ARTIFACT="$output/headless/canonical.json" \
  VIM_EXE="$proof_root/bin/vim" \
  VIM9_LSP_PATH="$proof_root/share/yegappan-lsp" \
  "$proof_root/bin/hq-vim.test" -test.v -test.count=1 -test.run '^TestCanonicalHQVimConformance$'
) >"$output/headless/test.log" 2>&1
jq -e '.status == "passed" and .hqSourceSha == "3118886f34ac5615e8a7732a6297bd41900e21e1" and .completionWrites == 0' \
  "$output/headless/canonical.json" >/dev/null
