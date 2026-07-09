# hq-source-jsonl adapter

`hq-source-jsonl` turns stable hq-shaped rows into normalized completion candidates without giving the editor a custom hq-only path.

Accepted row examples include:

- command vocabulary rows such as `modelAddEdge`;
- targetRef-like rows such as `targetRefRepoMapNode`;
- queue/source identifiers such as `queueLocalJsonl`.

The adapter remains a source adapter. Core sees only the provider port.
