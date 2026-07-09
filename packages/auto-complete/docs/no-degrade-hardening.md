# auto-complete no-degrade hardening

This document records the scope-to-meta contribution for the #37 hardening follow-up.

| generation | purpose | direct contribution |
|---:|---|---|
| G0 | keep current Japanese completion UX from regressing | snapshots, fixture gates, and visual audit freeze raw buffer / preedit / candidates / textEdit behavior |
| G1 | prevent false green CI | post-merge trigger check, negative fixtures, and snapshot diffs make partial success visible |
| G2 | keep core reusable | import graph and old-path guards keep core/ports separate from adapters and app wiring |
| G3 | make hq/modeling source connectable | hq-source-jsonl fixture proves hq rows can become completion candidates through the same provider port |
| G4 | keep editor adapters thin | LSP/Vim/Helix paths remain adapters; core does not import editor or transport code |
| G5 | preserve reviewable evidence | canonical candidate/LSP/UX snapshots turn behavior into data that can be diffed |
| G6 | support handoff and third-party review | explicit checklist, measured budgets, and failure messages make the proof repeatable |
| G7 | reduce DD risk | architecture boundaries and evidence reduce hidden coupling and false claims |
| G8 | improve asset transferability | the completion package remains reusable across Vim, Helix, hq, and future UI adapters |
| G9 | improve company sale readiness | small, tested, low-coupling product components are easier to value, maintain, and transfer |

## Issue coverage

| issue | gate |
|---:|---|
| #39 | post-merge workflow config check |
| #40 | Go import graph boundary check |
| #41 | provider port contract test across source adapters |
| #42 | hq-source-jsonl real fixture and LSP configuration |
| #43 | negative fixtures for malformed/bad source rows |
| #44 | canonical candidate and LSP output snapshots |
| #45 | canonical UX visual evidence audit |
| #46 | source adapter performance budget |
| #47 | old path absence and migration guard |
| #48 | parent closure checklist |
