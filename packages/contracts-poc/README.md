# contracts-poc

Temporary staging area for the cue append-contract bundle concepts while the final contracts repository is not yet available.

This package is intentionally small and split-ready. It keeps queue, admission, and accepted-ledger boundaries explicit.

## Boundary

| path | role |
|---|---|
| `contracts/` | contract/meta schema notes |
| `ledgers/` | sample accepted-ledger-shaped JSONL |
| `tools/` | portable validation/proof helpers |

## Non-authority rule

`edits` is not the final contracts authority. This package is a staging area so local control-plane PRs can prove shape and admission boundaries before the contracts repo split.

## Minimal proof

```text
python3 packages/contracts-poc/tools/validate_contract_ledger.py packages/contracts-poc/ledgers/sample.contract.jsonl
```

Future PRs may replace this portable validator with the full cue/go append-contract implementation once its canonical repository is selected.
