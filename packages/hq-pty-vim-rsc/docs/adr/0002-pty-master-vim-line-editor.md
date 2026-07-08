# ADR 0002: PTY master owns Vim, not shell/readline

## Decision

The final line editor architecture is not `shell -> readline -> completion`.
It is:

```text
terminal emulator
  -> herdr-like single PTY owner
      -> PTY master
          -> PTY slave
              -> vim
      -> input middleware
          -> recursive slot completion
          -> candidate protocol
```

Vim is started directly as the child TUI. No `sh -c vim` layer is used.
The PTY master observes the input stream, maintains the current line buffer, and asks the recursive slot compiler for candidates after each typed character.

## Why

- readline is a shell-local line editor; this proof replaces that layer.
- Vim is a strong editing surface, but it remains a child TUI, not the semantic core.
- Completion belongs to the PTY owner middleware, so it can later be projected to Vim popup, palette, Ghostty overlay, or herdr control UI.
- Candidate semantics stay in Go protocol code: `JsonlWorld -> CursorContext -> Slot -> Suggestion -> CompileDraft -> Acceptance -> Instruction`.

## Guardrails

- Completion is side-effect-free.
- Candidates carry edit + meaning + compileDraft.
- Accept writes instruction JSONL only after identity/hash/version checks.
- Dispatch remains outside this proof.
- Shell fallback can exist as another PTY node, but Vim startup does not pass through shell.
