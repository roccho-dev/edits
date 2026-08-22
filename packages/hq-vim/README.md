# hq Vim

Minimal edits-owned Vim adapter for the official external `hq` runtime.

```text
Vim
  -> pinned yegappan/lsp
    -> exact absolute hq binary
      -> lsp --profile <name>
```

## User surface

The complete command surface is deliberately small:

```vim
:HqStart [profile]
:HqSubmit
:HqDoctor
```

After `:HqStart`, yegappan/lsp owns automatic native completion. Typing `@`
queries the selected-world command language. Vim adds no manual completion
command, matcher, history browser, route picker, retry UI, or provider UI.

The selected world owns command order and meaning:

```text
default:true command = AI-agent decision, such as agent.exec
explicit fallback      = direct command, such as direct.open
```

Changing the default agent, adding a project command, or promoting a repeated
decision changes world/profile data. It does not change this plugin.

`HqSubmit` is the only durable-effect entry point. Completion, documentation,
selection, editing, and undo append no accepted instruction.

## Ownership

This package owns only:

- fail-closed binding to one explicit absolute `hq` executable;
- Vim/yegappan LSP startup;
- native popup undo compatibility;
- explicit submit and safe application of hq-owned draft-consumption edits;
- editor-facing conformance tests.

It must not own:

- command vocabulary, parser meaning, or candidate rank;
- accepted-history search or command promotion;
- agent/direct routing, policy, approval, timeout, cancellation, or retry;
- JSONL paths, provider bindings, worker lifecycle, or Herdr process control.

Those remain HQ/world, envs/project, worker, and Herdr responsibilities.

## Exact binding

`g:hq_bin` is mandatory, absolute, and executable. The extension never searches
`PATH`, shell profiles, environment registries, or an unqualified command name.
Vim patch `9.0.1629` or newer is required for negotiated LSP positions.

Minimal init:

```vim
set runtimepath^=/exact/path/to/yegappan-lsp
set runtimepath^=/exact/path/to/edits/packages/hq-vim
runtime plugin/lsp.vim
runtime plugin/hq.vim
let g:hq_bin='/exact/verified/path/to/hq'
let g:hq_profile='local'
```

Then:

```vim
:HqStart
```

Typing `@` opens the native completion popup. `Ctrl-N`/`Ctrl-P` navigate and
`Ctrl-Y` accepts the selected LSP text edit. One native Vim undo restores the
exact pre-selection query.

## Submit and recovery

On successful `hq.submit`, hq may return one version-bound
`hq.draftConsumption.v1` edit. hq-vim applies it only when URI, version, and
`changedtick` still match.

- safe plan: consume only the accepted object;
- stale local draft: keep the newer draft;
- missing, malformed, or unapplicable plan: keep the draft and warn;
- one native undo: restore consumed text; the accepted row remains durable.

A terminal result is never mutated in place. When recovery is explicitly
authored, the HQ contract requires a new instruction with `reply_to`; this Vim
adapter only renders a resulting draft and submits it explicitly. Automatic
recovery UI is not implemented here.

## Focused behavior E2Es

Eight editor-owned boundaries remain. None calls or wraps another E2E:

1. `TestEditorSurfaceAndBindingFailClosed` — only `HqStart`, `HqSubmit`, and
   `HqDoctor`; explicit absolute HQ binding fails closed;
2. `TestAgentDefaultChoiceE2E` — empty native completion puts the declared
   Agent command first, keeps the direct fallback visible, shows complete
   documentation, supports one undo, and writes zero accepted rows;
3. `TestAgentPromptFieldChoiceE2E` — after Agent selection, the real LSP
   completes the required `prompt` field and writes zero accepted rows;
4. `TestDirectFallbackChoiceE2E` — after an explicit direct command, the real
   LSP completes its required path field and still writes zero accepted rows;
5. `TestUnicodeDirectFieldValueE2E` — Japanese, emoji, a combining mark, and
   CRLF survive the real LSP edit and one exact undo;
6. `TestAgentDecisionSubmitE2E` — one explicit `HqSubmit` appends exactly one
   typed Codex instruction, without executing the provider;
7. `TestDirectCommandSubmitE2E` — one explicit direct submit appends exactly
   one typed host instruction, consumes only that draft, and one undo restores
   it;
8. `TestAcceptedSubmitKeepsDraftOnUnsafeConsumption` — stale or malformed
   consumption never destroys a newer draft.

The separate `vim-nix runtime lifecycle` E2E starts with one exact accepted
fixture and owns only Herdr topology, managed worker readiness, deterministic
provider execution, `accepted -> started -> stdout -> completed`, typed stop,
and zero residual processes. It does not run an editor choice or submit E2E.

HQ parser, policy, retry/replay, provider adapters, and command promotion remain
HQ/envs/project-owned and are not duplicated here.

Run the low-cost suite:

```sh
go test ./...
```

Run each exact-runtime E2E independently:

```sh
export HQ_BIN=/absolute/path/to/hq
export VIM_EXE=/absolute/path/to/vim
export VIM9_LSP_PATH=/absolute/path/to/yegappan-lsp

HQ_CHOICE_E2E=1 go test -run '^TestAgentDefaultChoiceE2E$' -v
HQ_CHOICE_E2E=1 go test -run '^TestAgentPromptFieldChoiceE2E$' -v
HQ_CHOICE_E2E=1 go test -run '^TestDirectFallbackChoiceE2E$' -v
HQ_CHOICE_E2E=1 go test -run '^TestUnicodeDirectFieldValueE2E$' -v
go test -run '^TestAgentDecisionSubmitE2E$' -v
go test -run '^TestDirectCommandSubmitE2E$' -v
```

### PTY screenshots

Screenshots are a read-only projection of the same focused E2Es:

```sh
PROOF_ROOT=/exact/composed/runtime \
  proofs/vim-nix/capture-pty-e2e.sh
```

The capture hook waits until the tested state is already asserted, takes the
image, releases the test, and records `captureAddsBehavior:false`. It captures
Agent default choice, direct fallback choice, and the independent runtime
lifecycle. It contains no fixed hold and no umbrella E2E.

The exact installed Nix/Windows/WSLC proof remains outside this package.
