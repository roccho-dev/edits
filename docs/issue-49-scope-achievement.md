# Issue 49 scope achievement

## Purpose lineage

| generation | contribution |
|---|---|
| scope | keeps editor -> queue -> ui by fixing edits as the editor and queue-writer side |
| repo boundary | prevents edits from becoming ops runtime or ui renderer |
| meta | documents pure command/targetRef core and side-effect queue writer adapters |
| meta^10 | keeps the repo explainable as a small, sale-ready editor surface asset |

## Core / port / adapter

| layer | in edits |
|---|---|
| pure core | command and targetRef interpretation |
| port | queue row shape expected by downstream ops runtime |
| adapter | Vim/hq surface and local queue file append |

## FP / FN gates

| risk | gate |
|---|---|
| false positive | allowed fixtures permit proof-only local worker references and intent-only command rows |
| false negative | forbidden fixtures reject canonical worker, admission, accepted ledger, projection authority, and UI renderer claims |

## Authority rule

Queue rows written by edits are intent only. They are not accepted model authority.
