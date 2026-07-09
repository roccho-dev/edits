# Issue 54 scope achievement

## Purpose lineage

| generation | contribution |
|---|---|
| scope | keeps `agent.*` inside editor -> queue by making it queue intent only |
| repo boundary | prevents edits from absorbing agent runtime, proposal promotion, admission, or ledger writes |
| meta | keeps command parsing pure and side effects limited to queue-writer adapters |
| meta^10 | keeps agent automation explainable as a request surface, not hidden authority |

## Core / port / adapter

| layer | in edits |
|---|---|
| pure core | `agent.*` command classification and agentTask queue-row construction |
| port | `hq.agentTaskQueued.v1` queue kind expected by downstream ops runtime |
| adapter | Vim/hq display and local queue append |

## FP / FN gates

| risk | gate |
|---|---|
| false positive | valid `agent.* -> hq.agentTaskQueued.v1` command templates pass |
| false negative | proposal generation, promotion, real agent execution, admission, or accepted-ledger claims in edits fail |

## Authority rule

Agent commands create request intent only. They do not generate proposals, promote proposals, run agents, or write accepted state in edits.
