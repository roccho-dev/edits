# ADR 0001: main canonical runtime

Status: accepted

## Decision

`main` is the canonical Go runtime for hq. It owns:

- append-only JSONL semantic model reduction
- command LSP completion/diagnostics/hover/codeAction
- side-effect-free PlanDraft generation
- explicit dispatch with plan id/hash/buffer version checks
- adapter-only execution
- receipt JSONL append

HTTP and shell are promoted from mock to real adapters on main. Shell remains unsafe and requires explicit confirmation.

## Reason

The product identity should be one runtime, not parallel POCs. The proof artifacts live under `docs/proofs` and `cache`; generated binaries are not committed.
