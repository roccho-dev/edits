# hardening stack order

Logical order for review and future split if needed:

1. #40 import graph boundary check
2. #47 old path absence and migration guard
3. #41 provider port contract tests
4. #42 hq-source-jsonl real fixture gate
5. #43 negative fixtures
6. #44 canonical candidate/LSP snapshots
7. #45 UX visual snapshot audit
8. #46 performance budget
9. #39 post-merge CI verification
10. #48 parent closure checklist

This PR keeps the work in one branch because these gates share the same workflow and should be reviewed as one no-false-green hardening unit.
