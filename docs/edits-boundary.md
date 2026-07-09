# edits boundary

`edits` is the editor surface and queue-writer boundary for the editor-to-queue-to-ui flow.

## Owned by edits

| area | boundary |
|---|---|
| command vocabulary | editor-facing `model.*` and `agent.*` names |
| command interpretation | pure command/targetRef to queue-row construction |
| queue writer adapter | local append/readback helpers for queue intent |
| editor adapters | Vim/hq integration and human confirmation surface |

## Not owned by edits

| area | owner |
|---|---|
| queue validator contract authority | ops |
| worker runtime | ops |
| receipt writer authority | ops |
| admission gate | ops |
| accepted ledger | ops / accepted contract ledger |
| projection builder | ops |
| UI renderer and preview adapter | ui |

## Completion meaning

An edits-side change is complete only when it preserves this rule:

```text
edits writes intent; ops validates/processes/admits; ui renders read models
```

Queue rows from edits are intent only. They are not accepted model authority.

## Local worker proof rule

`packages/hq-local-worker` may remain only as legacy/proof-only evidence. Any doc or package that presents it as the canonical runtime owner must fail the boundary check.
