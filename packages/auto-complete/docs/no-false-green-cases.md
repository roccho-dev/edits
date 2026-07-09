# no-false-green cases

The hardening PR blocks these false-green paths:

1. PR-head CI passes but `proposals` post-merge state is not checked.
2. Core accidentally imports concrete source, LSP, editor, app, or command code.
3. Old implementation paths return beside the new lib/adapter layout.
4. A source adapter exists by directory shape but does not satisfy provider behavior.
5. hq-source-jsonl has no real JSONL fixture path.
6. Malformed source rows silently become candidates.
7. Candidate ordering, rank, or textEdit changes without a visible diff.
8. UX artifact is uploaded but no longer represents intended semantics.
9. Small fixtures pass while realistic fixture size is unusable.
10. Parent #37 closes without final evidence.
