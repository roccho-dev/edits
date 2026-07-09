# negative fixtures

Bad source rows must not silently become completion candidates.

The negative fixture gate covers:

- malformed JSONL;
- missing `word`;
- missing or invalid `rank`;
- missing `reading` and `romaji`;
- unknown `source` or `kind`;
- duplicate candidate rows;
- valid empty provider output.

Optional unknown fields are allowed when they do not change candidate semantics.
