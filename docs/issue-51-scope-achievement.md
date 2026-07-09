# Issue 51 scope achievement

## Purpose lineage

| generation | contribution |
|---|---|
| scope | proves edits writes queue rows compatible with the ops-owned queue contract |
| repo boundary | keeps edits as queue writer while ops owns validation/runtime/admission |
| meta | aligns local prechecks with the ops port without copying ops runtime ownership |
| meta^10 | makes the editor-to-runtime handoff explainable and auditable |

## Core / port / adapter

| layer | in edits |
|---|---|
| pure core | command-to-queue construction and queue row digest shape |
| port | ops queue contract fields: kind, status, targetRef.kind/id, goal/op/payload, idempotency |
| adapter | local file append/readback and editor integration |

## FP / FN gates

| risk | gate |
|---|---|
| false positive | valid model and agent command outputs with targetRef pass local ops-compatible validation |
| false negative | missing targetRef, malformed targetRef, duplicate ids, and nested authority fields fail before append or validation |

## Authority rule

edits writes ops-compatible queue intent only. It does not run the ops worker, write accepted ledger, render ui preview, or generate ops receipts.
