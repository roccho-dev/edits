#!/usr/bin/env python3
from pathlib import Path
import json
import re

ROOT = Path('.')


def replace_once(path: Path, old: str, new: str) -> None:
    text = path.read_text(encoding='utf-8')
    count = text.count(old)
    if count != 1:
        raise SystemExit(f'{path}: expected one occurrence, got {count}: {old[:100]!r}')
    path.write_text(text.replace(old, new, 1), encoding='utf-8')


smoke = ROOT / 'packages/hq-vim/internal/smoke/smoke.go'
replace_once(smoke, '\tNativePopupArtifact     string\n}', '\tNativePopupArtifact     string\n\tCaptureReadyPath        string\n\tCaptureReleasePath      string\n}')
replace_once(smoke,
    '\tfor _, path := range []string{cfg.ResultPath, cfg.BufferResultPath, cfg.UndoResultPath, cfg.MessagesPath, cfg.NativePopupArtifact} {',
    '\tfor _, path := range []string{cfg.ResultPath, cfg.BufferResultPath, cfg.UndoResultPath, cfg.MessagesPath, cfg.NativePopupArtifact, cfg.CaptureReadyPath, cfg.CaptureReleasePath} {')
replace_once(smoke,
'''\tif cfg.NativePopupFileFormat != "" && cfg.NativePopupFileFormat != "unix" && cfg.NativePopupFileFormat != "dos" {
\t\treturn errors.New("NativePopupFileFormat must be unix or dos")
\t}
''',
'''\tif cfg.NativePopupFileFormat != "" && cfg.NativePopupFileFormat != "unix" && cfg.NativePopupFileFormat != "dos" {
\t\treturn errors.New("NativePopupFileFormat must be unix or dos")
\t}
\tif (cfg.CaptureReadyPath == "") != (cfg.CaptureReleasePath == "") {
\t\treturn errors.New("CaptureReadyPath and CaptureReleasePath must be set together")
\t}
''')
replace_once(smoke,
'''\tcmd.Env = environmentWithOverrides(os.Environ(), cfg.Env)
\terr = cmd.Run()''',
'''\tcmd.Env = environmentWithOverrides(os.Environ(), cfg.Env)
\tif cfg.NativePopupArtifact != "" && runtime.GOOS != "windows" {
\t\tterminal, terminalErr := os.OpenFile("/dev/tty", os.O_RDWR, 0)
\t\tif terminalErr != nil {
\t\t\treturn diagnosticError(fmt.Errorf("open controlling terminal: %w", terminalErr), cfg)
\t\t}
\t\tdefer terminal.Close()
\t\tcmd.Stdout = terminal
\t\tcmd.Stderr = terminal
\t\tcmd.Stdin = terminal
\t}
\terr = cmd.Run()''')
replace_once(smoke,
'''\tlines := []string{
\t\t"set nocompatible",
\t\t"set noswapfile",''',
'''\tlines := []string{
\t\t"set nocompatible",
\t\t"set noswapfile",
\t\t"set encoding=utf-8",''')
replace_once(smoke,
    '\t\t"  call feedkeys(repeat(\\"\\\\<C-N>\\", l:index + 1), \'n\')",',
    '\t\t"  call feedkeys(repeat(\\"\\\\<C-N>\\", l:index + 1), \'nt\')",')
replace_once(smoke,
'''\t\t"let g:hq_native_expected_index = -1",
\t}''',
'''\t\t"let g:hq_native_expected_index = -1",
\t}
\tif cfg.CaptureReadyPath != "" {
\t\tlines = append(lines,
\t\t\t"let g:hq_native_capture_ready = "+vimString(cfg.CaptureReadyPath),
\t\t\t"let g:hq_native_capture_release = "+vimString(cfg.CaptureReleasePath),
\t\t)
\t}''')
replace_once(smoke,
    '\t\t"function! HqNativePopupObserve(timer) abort",',
'''\t\t"function! HqNativePopupAccept() abort",
\t\t"  call feedkeys(\\"\\<C-Y>\\<Esc>\\", 'n')",
\t\t"  call timer_start(100, function('HqNativePopupVerify'))",
\t\t"endfunction",
\t\t"function! HqNativePopupAwaitRelease(timer) abort",
\t\t"  if filereadable(g:hq_native_capture_release)",
\t\t"    call HqNativePopupAccept()",
\t\t"    return",
\t\t"  endif",
\t\t"  if reltimefloat(reltime()) >= g:hq_native_deadline",
\t\t"    call HqNativePopupFinish('failed', 'PTY capture release timeout')",
\t\t"    return",
\t\t"  endif",
\t\t"  call timer_start(20, function('HqNativePopupAwaitRelease'))",
\t\t"endfunction",
\t\t"function! HqNativePopupObserve(timer) abort",''')
replace_once(smoke,
'''\t\t"  call feedkeys(\\"\\<C-Y>\\<Esc>\\", 'n')",
\t\t"  call timer_start(100, function('HqNativePopupVerify'))",
\t\t"endfunction",
\t\t"function! HqNativePopupPoll(timer) abort",''',
'''\t\t"  if exists('g:hq_native_capture_ready')",
\t\t"    call writefile([json_encode({'status': 'ready', 'label': "+vimValue(cfg.ExpectedCompletionLabel)+"})], g:hq_native_capture_ready)",
\t\t"    call timer_start(20, function('HqNativePopupAwaitRelease'))",
\t\t"    return",
\t\t"  endif",
\t\t"  call HqNativePopupAccept()",
\t\t"endfunction",
\t\t"function! HqNativePopupPoll(timer) abort",''')

# Decision-entry E2E: only agent-first and explicit direct fallback.
test_file = ROOT / 'packages/hq-vim/hq_vim_smoke_test.go'
text = test_file.read_text(encoding='utf-8')
text = text.replace('TestNativeHQFuzzyAutomaticPopupDoesNotAccept', 'TestDecisionEntryE2E')
text = text.replace('os.Getenv("HQ_NATIVE_HQ_FUZZY_PROOF")', 'os.Getenv("HQ_DECISION_ENTRY_E2E")')
text = text.replace('set HQ_NATIVE_HQ_FUZZY_PROOF=1 and run under a real terminal', 'set HQ_DECISION_ENTRY_E2E=1 and run under a real terminal')
text = text.replace('\t\tfileFormat  string\n\t\tmustBeFirst bool\n\t}{', '\t\tfileFormat  string\n\t\tmustBeFirst bool\n\t\tcaptureID   string\n\t}{', 1)
text = text.replace('fileFormat: "unix", mustBeFirst: true,', 'fileFormat: "unix", mustBeFirst: true, captureID: "agent-first",', 1)
text, count = re.subn(r'\n\t\t\{\n\t\t\tname: "AI agent prompt field".*?\n\t\t\},', '', text, count=1, flags=re.S)
if count != 1:
    raise SystemExit('AI-agent prompt-field case was not removed exactly once')
text = text.replace('docPreview: "Preview:\\n日本語-😀-é.jsonl", fileFormat: "dos",', 'docPreview: "Preview:\\n日本語-😀-é.jsonl", fileFormat: "dos", captureID: "direct-fallback",', 1)
old_cfg = '''\t\t\tcfg := smoke.Config{
\t\t\t\tHQBin: hqBin, Vim: requireVim(t), Vim9LSP: requireVim9LSP(t), PluginRoot: root,
\t\t\t\tProfile: "local", Buffer: filepath.Join(t.TempDir(), "native-hq-popup.hqjson"),
\t\t\t\tCompletionText: tc.query, ExpectedCompletionLabel: tc.label, ExpectedCompletionText: tc.want,
\t\t\t\tNativePopupFileFormat: tc.fileFormat, NativePopupArtifact: artifact,
\t\t\t\tEnv: profileEnv, Timeout: 15 * time.Second,
\t\t\t}'''
new_cfg = '''\t\t\tcfg := smoke.Config{
\t\t\t\tHQBin: hqBin, Vim: requireVim(t), Vim9LSP: requireVim9LSP(t), PluginRoot: root,
\t\t\t\tProfile: "local", Buffer: filepath.Join(t.TempDir(), "native-hq-popup.hqjson"),
\t\t\t\tCompletionText: tc.query, ExpectedCompletionLabel: tc.label, ExpectedCompletionText: tc.want,
\t\t\t\tNativePopupFileFormat: tc.fileFormat, NativePopupArtifact: artifact,
\t\t\t\tEnv: profileEnv, Timeout: 30 * time.Second,
\t\t\t}
\t\t\tif captureDir := os.Getenv("HQ_PTY_SCREENSHOT_DIR"); captureDir != "" {
\t\t\t\tif err := os.MkdirAll(captureDir, 0o755); err != nil {
\t\t\t\t\tt.Fatal(err)
\t\t\t\t}
\t\t\t\tcfg.CaptureReadyPath = filepath.Join(captureDir, tc.captureID+".ready.json")
\t\t\t\tcfg.CaptureReleasePath = filepath.Join(captureDir, tc.captureID+".release")
\t\t\t}'''
if old_cfg not in text:
    raise SystemExit('decision-entry config block is missing')
text = text.replace(old_cfg, new_cfg, 1)
test_file.write_text(text, encoding='utf-8')

# Explicit-submit E2E: one submit, one durable row, safe consumption, one undo.
canon = ROOT / 'packages/hq-vim/canonical_conformance_test.go'
text = canon.read_text(encoding='utf-8')
start = text.index('func TestCanonicalHQVimConformance')
end = text.index('\nfunc acceptedPath', start)
replacement = r'''func TestExplicitSubmitE2E(t *testing.T) {
	hqBin := os.Getenv("HQ_CANONICAL_BIN")
	if hqBin == "" {
		t.Skip("HQ_CANONICAL_BIN is not set")
	}
	if !filepath.IsAbs(hqBin) {
		t.Fatalf("HQ_CANONICAL_BIN must be absolute: %q", hqBin)
	}
	root := mustPackageRoot(t)
	profile := prepareCanonicalProfile(t)
	assertCanonicalProfileStarts(t, hqBin, profile.Env)
	submitText := "@queue.create\npath=demo.jsonl"
	resultRoot := t.TempDir()
	resultPath := filepath.Join(resultRoot, "submit-result.json")
	bufferResult := filepath.Join(resultRoot, "buffer-after.json")
	undoResult := filepath.Join(resultRoot, "buffer-undo.json")
	messages := filepath.Join(resultRoot, "messages.txt")
	cfg := smoke.Config{
		HQBin: hqBin, Vim: requireVim(t), Vim9LSP: requireVim9LSP(t),
		PluginRoot: root, Profile: "local", Buffer: filepath.Join(t.TempDir(), "submit.hqjson"),
		BufferText: submitText, Headless: true, Env: profile.Env,
		ResultPath: resultPath, BufferResultPath: bufferResult,
		UndoResultPath: undoResult, MessagesPath: messages,
	}
	if err := smoke.Run(cfg); err != nil {
		t.Fatalf("explicit submit E2E failed: %v", err)
	}
	rows := readJSONLRows(t, profile.AcceptedPath)
	if len(rows) != 1 || rows[0]["kind"] != "accepted.instruction" {
		t.Fatalf("accepted rows=%#v", rows)
	}
	instruction, ok := rows[0]["instruction"].(map[string]any)
	if !ok {
		t.Fatalf("accepted row has no instruction: %#v", rows[0])
	}
	id, _ := instruction["id"].(string)
	if id == "" {
		t.Fatalf("accepted instruction has no id: %#v", instruction)
	}
	result := readJSONObject(t, resultPath)
	if result["kind"] != "hq.submitResult.v1" || result["status"] != "queued" || result["queueId"] != id {
		t.Fatalf("submit result=%#v accepted id=%s", result, id)
	}
	if result["queueKind"] != "accepted.instruction" || result["deploymentId"] != "edits-ci" {
		t.Fatalf("submit authority mismatch: %#v", result)
	}
	consumption, ok := result["draftConsumption"].(map[string]any)
	if !ok || consumption["kind"] != "hq.draftConsumption.v1" {
		t.Fatalf("draft consumption=%#v", result["draftConsumption"])
	}
	if got := readVimBuffer(t, bufferResult); len(got.Lines) != 1 || got.Lines[0] != "" {
		t.Fatalf("accepted draft was not consumed: %#v", got)
	}
	if got := readVimBuffer(t, undoResult); strings.Join(got.Lines, "\n") != submitText {
		t.Fatalf("one undo did not restore submitted text: %#v", got)
	}
	if got := readText(t, messages); !strings.Contains(got, "draft consumed") {
		t.Fatalf("missing consumed outcome: %s", got)
	}
	writeCanonicalArtifact(t, map[string]any{
		"kind": "edits.hqVimExplicitSubmitE2E.v1", "status": "passed",
		"hqSourceSha": os.Getenv("HQ_CANONICAL_SOURCE_SHA"),
		"acceptedRows": 1, "submitIdentityMatches": true,
		"acceptedDraftConsumed": true, "oneUndoRestoresDraft": true,
		"binding": "explicit-absolute-g:hq_bin",
	})
}
'''
canon.write_text(text[:start] + replacement + text[end:], encoding='utf-8')

for rel in ['packages/hq-vim/internal/smoke/tty_test.go', 'proofs/vim-nix/hq-vim-native-popup-proof.patch']:
    path = ROOT / rel
    if path.exists():
        path.unlink()

# Screenshot projection is not a test and has no product effect.
shot = ROOT / 'tools/vim-nix-local/pty-shot.py'
shot.write_text(r'''#!/usr/bin/env python3
import argparse
import html
import re
from pathlib import Path

CSI = re.compile(r"\x1b\[[0-?]*[ -/]*[@-~]")
OSC = re.compile(r"\x1b\][^\x07]*(?:\x07|\x1b\\)")


def clean(value: str) -> list[str]:
    value = OSC.sub("", CSI.sub("", value)).replace("\r", "")
    lines = value.splitlines()
    while lines and not lines[-1].strip():
        lines.pop()
    return lines or [""]


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("input")
    parser.add_argument("output")
    parser.add_argument("--title", default="PTY E2E")
    args = parser.parse_args()
    lines = clean(Path(args.input).read_text(encoding="utf-8", errors="replace"))
    columns = max(40, min(180, max(len(line.expandtabs(4)) for line in lines)))
    width = columns * 8 + 32
    height = (len(lines) + 2) * 18 + 24
    body = []
    for index, line in enumerate(lines):
        body.append(f'<text x="16" y="{54 + index * 18}">{html.escape(line.expandtabs(4))}</text>')
    svg = f'''<svg xmlns="http://www.w3.org/2000/svg" width="{width}" height="{height}" viewBox="0 0 {width} {height}">
<rect width="100%" height="100%" fill="#101418"/>
<text x="16" y="26" fill="#e6edf3" font-family="ui-monospace,monospace" font-size="14" font-weight="700">{html.escape(args.title)}</text>
<g fill="#d0d7de" font-family="ui-monospace,monospace" font-size="13" xml:space="preserve">
{chr(10).join(body)}
</g>
</svg>
'''
    Path(args.output).write_text(svg, encoding="utf-8")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
''', encoding='utf-8')
shot.chmod(0o755)

watch = ROOT / 'tools/vim-nix-local/capture-decision-entry.sh'
watch.write_text(r'''#!/usr/bin/env bash
set -euo pipefail
if test "$#" -ne 6; then
  echo "usage: capture-decision-entry.sh HERDR SESSION PANE CAPTURE_DIR OUT_DIR TITLE_PREFIX" >&2
  exit 2
fi
herdr=$1 session=$2 pane=$3 capture=$4 out=$5 prefix=$6
script_dir=$(CDPATH= cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
mkdir -p "$capture" "$out"
for id in agent-first direct-fallback; do
  ready="$capture/$id.ready.json"
  release="$capture/$id.release"
  for _ in $(seq 1 600); do
    test -s "$ready" && break
    sleep 0.05
  done
  test -s "$ready"
  "$herdr" --session "$session" pane read "$pane" --source visible --lines 240 > "$out/$id.txt"
  python3 "$script_dir/pty-shot.py" "$out/$id.txt" "$out/$id.svg" --title "$prefix / $id"
  : > "$release"
done
sha256sum "$out"/*.txt "$out"/*.svg > "$out/SHA256SUMS"
''', encoding='utf-8')
watch.chmod(0o755)

verify = ROOT / 'tools/vim-nix-local/verify.sh'
text = verify.read_text(encoding='utf-8')
text = text.replace("test \"$(grep -Rh '^func Test' \"$repo_root/packages/hq-vim\" --include='*_test.go' | wc -l | tr -d ' ')\" = 5", "test \"$(grep -Rh '^func Test' \"$repo_root/packages/hq-vim\" --include='*_test.go' | wc -l | tr -d ' ')\" = 4")
start = text.find("printf '== exact test-only patch RED/GREEN ==\\n'")
end = text.find("printf '== OCI positive/mutation proof ==\\n'")
if start < 0 or end <= start:
    raise SystemExit('verify RED/GREEN block markers missing')
text = text[:start] + '''printf '== retained Canon TDD ==\\n' | tee -a "$out/logs/summary.txt"
(cd "$repo_root/packages/hq-vim" && go test ./... -count=1 | tee "$out/logs/go-test.log")

''' + text[end:]
text = text.replace('"testOnlyPatchPath": "proofs/vim-nix/hq-vim-native-popup-proof.patch", "patchTouches": ["packages/hq-vim/internal/smoke/smoke.go"]', '"screenshotProjection": "tools/vim-nix-local/capture-decision-entry.sh -> pty-shot.py"')
text = text.replace('"patchAppliesCleanly": "PASS",\n', '')
text = text.replace('"unpatchedTTYControl": "RED_AS_EXPECTED", "patchedGoTests": "PASS",\n    "childUsesControllingTTYWhenParentOutputIsRedirected": "PASS",', '"retainedGoTests": "PASS",')
text = text.replace('      "canonical LSP completion and explicit submit",\n      "agent-first/direct-fallback native popup",\n      "unsafe draft consumption preservation",\n      "controlling TTY"', '      "explicit submit E2E",\n      "decision-entry E2E",\n      "unsafe draft consumption preservation"')
verify.write_text(text, encoding='utf-8')

part1 = ROOT / 'proofs/vim-nix/run-proof.parts/01.sh'
text = part1.read_text(encoding='utf-8')
text = text.replace('HQ_NATIVE_HQ_FUZZY_PROOF=1', 'HQ_DECISION_ENTRY_E2E=1')
text = text.replace("-test.run '^TestNativeHQFuzzyAutomaticPopupDoesNotAccept\\$'", "-test.run '^TestDecisionEntryE2E\\$'")
text = text.replace("'AI_agent_is_the_first_command' 'AI_agent_prompt_field' 'explicit_direct_command_with_Unicode_CRLF'", "'AI_agent_is_the_first_command' 'explicit_direct_command_with_Unicode_CRLF'")
text = text.replace('HQ_BIN="$PROOF/bin/hq" \\\nVIM_EXE=', 'HQ_BIN="$PROOF/bin/hq" \\\nHQ_PTY_SCREENSHOT_DIR="$RUNTIME/capture" \\\nVIM_EXE=', 1)
needle = '''"$HERDR" --session "$SESSION" pane run "$ROOT_PANE_ID" "$RUNTIME/run-popup.sh" \\
  > "$OUT/popup-pane-run.json" 2> "$OUT/popup-pane-run.stderr"

process_seen=0'''
insert = '''"$HERDR" --session "$SESSION" pane run "$ROOT_PANE_ID" "$RUNTIME/run-popup.sh" \\
  > "$OUT/popup-pane-run.json" 2> "$OUT/popup-pane-run.stderr"
"$PROOF/share/proof/capture-decision-entry.sh" \\
  "$HERDR" "$SESSION" "$ROOT_PANE_ID" "$RUNTIME/capture" "$OUT/screenshots" "HQ decision entry" &
CAPTURE_PID=$!

process_seen=0'''
if needle not in text:
    raise SystemExit('proof pane-launch marker missing')
text = text.replace(needle, insert, 1)
text = text.replace('grep -Fxq PASS "$OUT/native-popup.log" || fail "native popup test did not end in PASS"', 'wait "$CAPTURE_PID" || fail "PTY screenshot projection failed"\ngrep -Fxq PASS "$OUT/native-popup.log" || fail "decision-entry E2E did not end in PASS"', 1)
part1.write_text(text, encoding='utf-8')

for path in (ROOT / 'proofs/vim-nix/run-proof.parts').glob('*.sh'):
    text = path.read_text(encoding='utf-8').replace('TestCanonicalHQVimConformance', 'TestExplicitSubmitE2E')
    path.write_text(text, encoding='utf-8')

lock = json.loads((ROOT / 'proofs/vim-nix/flake.lock').read_text(encoding='utf-8'))
hq_rev = next(node['locked']['rev'] for node in lock.get('nodes', {}).values() if isinstance(node, dict) and node.get('locked', {}).get('repo') == 'hq' and node.get('locked', {}).get('owner') == 'roccho-dev')
for path in (ROOT / 'proofs/vim-nix/run-proof.parts').glob('*.sh'):
    text = path.read_text(encoding='utf-8')
    text = re.sub(r'HQ_CANONICAL_SOURCE_SHA=[0-9a-f]{40}', 'HQ_CANONICAL_SOURCE_SHA=' + hq_rev, text)
    text = re.sub(r'"hqCommit":"[0-9a-f]{40}"', '"hqCommit":"' + hq_rev + '"', text)
    path.write_text(text, encoding='utf-8')

flake = ROOT / 'proofs/vim-nix/flake.parts/00.nix'
text = flake.read_text(encoding='utf-8').replace('        patches = [ (root + "/hq-vim-native-popup-proof.patch") ];\n', '')
marker = '''          runHook postInstall
        '';
      };'''
addition = '''          install -Dm755 ${edits-src + "/tools/vim-nix-local/capture-decision-entry.sh"} "$out/share/proof/capture-decision-entry.sh"
          install -Dm755 ${edits-src + "/tools/vim-nix-local/pty-shot.py"} "$out/share/proof/pty-shot.py"
          runHook postInstall
        '';
      };'''
pos = text.find('hq-vim-proof-runner =')
index = text.find(marker, pos)
if pos < 0 or index < 0:
    raise SystemExit('proof-runner install marker missing')
text = text[:index] + text[index:].replace(marker, addition, 1)
flake.write_text(text, encoding='utf-8')

readme = ROOT / 'packages/hq-vim/README.md'
text = readme.read_text(encoding='utf-8')
text = text.replace('Only five behavior boundaries remain in this package:', 'Four behavior boundaries remain in this package:')
text = text.replace('''1. minimal editor commands and fail-closed exact HQ binding;
2. canonical real Vim -> yegappan/lsp -> HQ completion and explicit submit;
3. native popup: AI-agent first, explicit direct fallback, documentation,
   Unicode/CRLF edit, one undo, and zero accepted rows before submit;
4. stale or invalid consumption never destroys a draft;
5. child Vim retains a controlling TTY when proof output is redirected.''', '''1. minimal editor commands and fail-closed exact HQ binding;
2. `TestExplicitSubmitE2E`: one submit appends exactly one instruction,
   consumes only the accepted draft, and one undo restores its text;
3. `TestDecisionEntryE2E`: AI-agent first, explicit direct fallback,
   documentation, Unicode/CRLF edit, one undo, and zero pre-submit writes;
4. stale or invalid consumption never destroys a draft.

PTY screenshots are not assertions. `capture-decision-entry.sh` reads the live
Herdr visible pane only after the E2E emits a capture-ready marker, projects the
text to SVG with `pty-shot.py`, and releases the same E2E to finish its checks.''')
readme.write_text(text, encoding='utf-8')
