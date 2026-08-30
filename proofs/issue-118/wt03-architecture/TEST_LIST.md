# Test list

1. Materialize one provider-independent core package.
2. Materialize client, service, mux, and ops-adapter ports.
3. Keep `edits-worker` absent from production paths.
4. Keep provider-specific semantic branches out of core.
5. Bind Vim, HQ, and Herdr as exact provider references rather than copied sources.
6. Publish one closed dependency graph with only allowed edges.
7. Keep ops internal packages out of edits imports.
8. Keep direct business-effect execution out of edits.
9. Keep retry/cancel policy out of edits.
10. Keep canonical result/receipt writing out of edits.
11. Keep local worker code explicitly legacy/proof-only.
12. Keep JSONL free of shell command programs.
13. Keep JSONL free of workflow branches and loops.
14. Prove the target dependency graph is acyclic.
