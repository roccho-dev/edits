# Loose string -> strict DraftObject validation proof

This proof fixes the intake boundary that was missing from the previous PTY/Vim RSC proof.

## Boundary

```text
Vim loose string
  -> hq rsc-intake
  -> DraftObject
  -> soft validation + slot suggestions
  -> accept suggestion by canonical id/hash/version
  -> instruction JSONL
```

## Proven behavior

- `project hq tasks ` becomes a partial `DraftObject`.
- Soft validation reports missing `ref` as guidance, not as a hard failure.
- Strict validation rejects the same incomplete draft.
- `project hq tasks task:t1` passes strict validation.
- Suggestions carry `meaning + edit + compileDraft` and `side_effect=false`.
- Mutating a suggestion body after it was shown is rejected by canonical hash validation.
- The same loose string is visually projected into Vim popup through the PTY/Vim proof path.

## Proof

```sh
./scripts/proof_loose_draft_validation.sh
# LOOSE_DRAFT_VALIDATION_PROOF_OK
```
