# Local-first development boundary

Develop and verify the editor/test delta in the current sandbox before any
GitHub write. The exact locked Nix closure is not a prerequisite for this inner
loop.

```text
current source
→ static checks
→ unpatched controlling-TTY RED
→ apply the exact test-only patch to a temporary copy
→ five Canon TDD boundaries
→ OCI verifier positive/mutation control
→ optional Herdr exactly-two-pane/clean-stop proof
→ local Receipt
→ one canonical head
```

Run:

```bash
HERDR_BIN=/path/to/herdr tools/vim-nix-local/vim-nix verify
```

`HERDR_BIN` is optional because the source delta is owned by hq-vim, not
Herdr. Supplying the verified Herdr 0.8.0 binary adds an isolated
server/workspace proof with exactly two panes, process observation, workspace
close, and clean server stop.

The local runner never edits the tracked smoke implementation. It copies the
package to a temporary directory and applies the exact test-only patch there.
Evidence is written under `.local/vim-nix-proof` and excluded from Git.

## UX contract

```text
User -> Vim: purpose / constraints
Vim -> HQ LSP: draft and completion request
HQ world -> Vim: default:true AI-agent command first; explicit direct command remains visible
User -> Vim: select/edit/documentation/undo; no durable effect
User -> HqSubmit: explicit acceptance
HQ -> instruction JSONL: append one typed instruction
worker/Herdr -> provider: codex / claude / sh / py / js / native
provider -> result JSONL: accepted -> started -> output -> completed|failed|timeout|cancelled
HQ/Agent -> next draft: retry|repair|direct fallback|human escalation as a new instruction
```

Vim exposes no manual history, matcher, route picker, or provider UI. Durable
history, repeated-decision detection, `command.promoted`, project/shared
registry projection, policy, and routing remain outside edits.

## Deferred high-cost gates

- exact Nix output-closure materialization;
- normal/offline same-store-path rebuild with empty substituters;
- exact Vim 9.2.0478, yegappan/lsp, and HQ integration replay;
- exact worker result lifecycle;
- Docker/OCI semantic parity;
- independent physical WSLC readback.

A local PASS proves the small source delta only. The complete Carry separately
supports the exact PTY/Vim/HQ/worker replay.

## Carry

```bash
tools/vim-nix-local/vim-nix doctor
tools/vim-nix-local/vim-nix verify
tools/vim-nix-local/vim-nix pack --herdr /absolute/path/to/herdr
```
