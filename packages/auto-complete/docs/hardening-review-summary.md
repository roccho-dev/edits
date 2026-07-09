# hardening review summary

This hardening set is intentionally evidence-heavy because #37 was reopened for no-false-green/no-degrade reasons.

The review should focus on whether the new gates reject the right failure modes:

- hidden core-to-adapter import coupling;
- legacy path resurrection;
- source adapter shape drift;
- malformed JSONL becoming candidates;
- hq source rows not passing through the real provider/LSP path;
- candidate order, score, or textEdit range drift;
- visual artifact upload without semantic audit;
- large fixture performance drift;
- parent #37 closing without post-merge evidence.
