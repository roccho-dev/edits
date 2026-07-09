# Issue 50 scope achievement

## Purpose lineage

| generation | contribution |
|---|---|
| scope | keeps Vim/hq command vocabulary as the editor-facing start of editor -> queue -> ui |
| repo boundary | prevents command names from implying runtime, admission, ledger, or renderer ownership |
| meta | treats vocabulary validation as pure data checks and Vim/hq/file actions as adapters |
| meta^10 | keeps the human language layer explainable and separable from runtime authority |

## Core / port / adapter

| layer | in edits |
|---|---|
| pure core | command template data and command lookup |
| port | queueKind declaration consumed by downstream queue validation |
| adapter | Vim/hq completion display and local append path |

## FP / FN gates

| risk | gate |
|---|---|
| false positive | valid `model.*` and `agent.*` commands with intent-only queueKind declarations pass |
| false negative | vocabulary that claims admission, accepted ledger, worker, dispatch, merge, or renderer ownership fails |

## Authority rule

Command selection and human confirmation prepare queue intent only. They do not create accepted model authority.
