# Issue 52 scope achievement

## Purpose lineage

| generation | contribution |
|---|---|
| scope | keeps current targetRef bridge as input to editor command completion and queue writing |
| repo boundary | prevents UI selection metadata from becoming execution or authority in edits |
| meta | keeps targetRef normalization pure and local current-target file IO as adapter |
| meta^10 | keeps UI-to-editor handoff auditable and explainable |

## Core / port / adapter

| layer | in edits |
|---|---|
| pure core | targetRef validation and `kind/id` extraction |
| port | ui-emitted targetRef shape and ops-compatible queue-row targetRef field |
| adapter | `.local/current-target.json` read/write |

## FP / FN gates

| risk | gate |
|---|---|
| false positive | valid ui-style targetRef records pass and can be copied into queue rows |
| false negative | authority-bearing, dispatch-bearing, malformed, or unknown targetRef fields fail before queue append |

## Authority rule

Current targetRef is proposal metadata only. It cannot approve, dispatch, merge, admit, or create accepted model state.
