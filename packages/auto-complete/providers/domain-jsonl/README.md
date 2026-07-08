# provider: domain-jsonl

Domain dictionary provider boundary.

This provider reads small domain dictionaries shaped like:

```jsonl
{"reading":"ほうじん","romaji":"houjin","word":"法人","rank":10,"source":"jp-dict"}
```

The provider may load and validate data, but it must not own editor UI, selected candidate state, key handling, or buffer writes.

Future SKK, Anthy, Rime, or Mozc integrations should be added as provider adapters, not as core logic.
