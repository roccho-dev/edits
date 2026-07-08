# contracts-poc meta

Portable staging notes for the append-contract model.

## Accepted row kinds

| kind | meaning |
|---|---|
| `contract.schema.v1` | schema definition row |
| `contract.field.v1` | field definition row |
| `contract.edge.v1` | semantic relation row |
| `contract.query.v1` | query/projection row |
| `contract.fixture.v1` | validation fixture row |
| `contract.authority_rule.v1` | authority/admission rule row |
| `accepted.modelCommit.v1` | admitted model commit from local queue |
| `admission.receipt.v1` | proof of admission attempt |

## Boundary

This staging file does not redefine ui read models and does not make `edits` the final contract authority.
