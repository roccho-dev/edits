# provider contract

Every source adapter must satisfy the same minimal contract:

- return normalized `Candidate` rows through the provider port;
- set `Word`, `Source`, and deterministic `Rank`;
- return stable ordering for equal input;
- keep format-specific parsing inside the source adapter;
- let core consume only the provider port.

This keeps `jp-jsonl`, `domain-jsonl`, and `hq-source-jsonl` interchangeable from the core engine's point of view.
