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

`failed`, `timeout`, and `cancelled` results are not mutated in place. HQ/Agent
creates a new instruction with `reply_to` for retry, repair, direct-command
fallback, or human escalation. Vim only renders the resulting candidates and
submits the next explicit draft.

## Canon TDD surface

Only five behavior boundaries remain in this package:

1. minimal editor commands and fail-closed exact HQ binding;
2. canonical real Vim -> yegappan/lsp -> HQ completion and explicit submit;
3. native popup: AI-agent first, explicit direct fallback, documentation,
   Unicode/CRLF edit, one undo, and zero accepted rows before submit;
4. stale or invalid consumption never destroys a draft;
5. child Vim retains a controlling TTY when proof output is redirected.

HQ parser/worker/provider tests are intentionally not duplicated here.

Run the low-cost suite:

```sh
go test ./...
```

Run the real popup proof explicitly:

```sh
HQ_NATIVE_HQ_FUZZY_PROOF=1 \
HQ_BIN=/absolute/path/to/hq \
VIM_EXE=/absolute/path/to/vim \
VIM9_LSP_PATH=/absolute/path/to/yegappan-lsp \
go test -run '^TestNativeHQFuzzyAutomaticPopupDoesNotAccept$' -v
```

The exact installed Nix/Windows/WSLC proof remains outside this package.
