# hq-source-extract

Minimal source archive extraction path for local repo-map modeling.

This package converts a source archive into JSONL records that can feed a future `repoMap.world.v1` projection.

## Output kinds

| kind | meaning |
|---|---|
| `source.archive.v1` | archive input and digest |
| `raw.evidence.v1` | file entry evidence |
| `extraction.v1` | extraction run receipt |
| `repoMap.world.node.v1` | repo/package/model node |
| `repoMap.world.edge.v1` | minimal containment edge |

## Boundary

This is extraction evidence, not accepted authority. Admission remains separate.

## Example

```text
python3 packages/hq-source-extract/tools/extract_archive_world.py \
  --archive /tmp/source.zip \
  --repo-id sample-repo \
  --out /tmp/repoMap.world.jsonl
```
