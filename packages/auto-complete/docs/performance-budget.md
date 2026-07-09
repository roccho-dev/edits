# source adapter performance budget

The performance gate uses a deterministic generated fixture with 2,500 JSONL rows and repeated completion checks for representative prefixes.

The CI budget is intentionally loose: 2,500ms for 640 completion checks. It is not a benchmark score. It is a regression guard that prevents tiny-fixture-only false green while avoiding flaky CI failures.
