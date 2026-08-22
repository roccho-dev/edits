# Local-first development boundary

Develop and verify the editor delta in the current sandbox before any GitHub
write. The exact locked Nix closure is not a prerequisite for this inner loop.

```text
current source
→ static checks
→ eight focused editor behavior boundaries
→ optional Herdr topology probe
→ local Receipt
→ one canonical head
```

Run:

```bash
HERDR_BIN=/path/to/herdr tools/vim-nix-local/vim-nix verify
```

`HERDR_BIN` is optional because the source delta is owned by hq-vim, not
Herdr. Supplying the verified Herdr 0.8.0 binary adds an isolated topology probe
with exactly two panes and clean stop.

The controlling-TTY hand-off belongs to the real popup harness. The old fake-Vim
TTY debug test and test-only source patch are gone. Evidence is written under
`.local/vim-nix-proof` and excluded from Git.

## UX contract

```text
User -> Vim: purpose / constraints
Vim -> HQ LSP: completion request
HQ world -> Vim: default:true AI-agent command first
User -> Vim: explicit direct query selects direct fallback
User -> Vim: select / inspect documentation / edit / undo
Vim -> accepted JSONL: zero rows before submit
User -> HqSubmit: explicit acceptance
HQ -> accepted JSONL: exactly one typed instruction
Herdr -> worker/provider: isolated PTY execution
provider -> result JSONL: accepted -> started -> stdout -> completed
HQ/Herdr -> process state: typed stop -> zero residual process
```

Vim exposes no manual history, matcher, route picker, retry UI, or provider UI.
History, policy, retry, command promotion, provider routing, and worker lifecycle
remain outside the adapter.

## Focused behavior ownership

Each test has one observable boundary. No E2E invokes another E2E.

```text
TestEditorSurfaceAndBindingFailClosed
  = HqStart / HqSubmit / HqDoctor only; exact HQ binding

TestAgentDefaultChoiceE2E
  = empty query -> agent.exec first; direct fallback visible; zero durable write

TestAgentPromptFieldChoiceE2E
  = Agent command -> required prompt field completion; zero durable write

TestDirectFallbackChoiceE2E
  = explicit direct command -> required path field; zero durable write

TestUnicodeDirectFieldValueE2E
  = Unicode + combining mark + CRLF edit; one exact undo

TestAgentDecisionSubmitE2E
  = explicit submit -> one typed Codex instruction

TestDirectCommandSubmitE2E
  = explicit submit -> one typed host instruction; consume + one undo

TestAcceptedSubmitKeepsDraftOnUnsafeConsumption
  = stale or invalid consumption never destroys the draft

vim-nix runtime lifecycle
  = exact accepted fixture -> Herdr/worker/provider lifecycle -> clean stop
```

The screenshot script observes only three already-asserted states:

```text
TestAgentDefaultChoiceE2E
TestDirectFallbackChoiceE2E
vim-nix runtime lifecycle
```

It uses ready/release files instead of a fixed sleep and records
`captureAddsBehavior:false`. It does not combine tests or create another product
route.

## Sequence boundary

The currently implemented sequence is covered through completion, explicit
submit, typed execution, result lifecycle, and clean stop. These agreed steps are
not claimed by this adapter because their product surfaces are not implemented
here:

- interactive high-risk approval;
- failed/timeout/cancelled recovery authoring through `reply_to`;
- completed-result rendering inside Vim;
- repeated-decision detection and `command.promoted` projection.

Their contracts and tests remain HQ/envs/project-owned rather than being faked
inside an editor E2E.

## Deferred distribution gates

- exact Nix output-closure materialization;
- normal/offline same-store-path rebuild with empty substituters;
- Docker/OCI semantic parity;
- independent physical WSLC readback.

## Carry

```bash
tools/vim-nix-local/vim-nix doctor
tools/vim-nix-local/vim-nix verify
tools/vim-nix-local/vim-nix pack --herdr /absolute/path/to/herdr
```
