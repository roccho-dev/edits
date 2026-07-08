# PR stack for local modeling control plane

This document maps parent issues to implementation PR lanes.

## edits lanes

| issue | PR lane | done state |
|---|---|---|
| #8 | local control plane docs and paths | repo boundaries are explicit |
| #9 | hq-pty-vim-rsc stabilization | Vim/RSC base is safe for later queue work |
| #10 | modeling queue contract | queue record kinds are defined and testable |
| #11 | local JSONL queue IO | append/readback/tail works on one local queue |
| #12 | command vocabulary | `model.*` and `agent.*` create queue rows |
| #13 | targetRef bridge | localhost UI selection reaches Vim/hq context |
| #14 | local worker | queue rows produce projection and receipts |
| #15 | contracts-poc | cue append-contract bundle is staged safely |
| #16 | admission gate | valid model rows promote to accepted ledger |
| #17 | source archive extraction | source input can produce repoMap world |
| #18 | agent proposal loop | agent task can return proposal for human confirm |
| #20 | vertical proof | Vim queue to localhost UI to receipt is proven |

## stack rule

Keep PRs small. A PR may close one parent issue or land a narrow part under it. If a PR is partial, its body must state which done checklist items remain.

## authority rule

No PR may treat local queue, UI state, projection, or generated artifact as authority.

## dependency rule

No PR may add a dependency from `ui`, contracts, or source repositories back to `edits`.
