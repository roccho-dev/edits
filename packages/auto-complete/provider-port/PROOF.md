# proof

Release proof:

- status: PASS
- assertions: 735
- provider contract assertions: 38
- red/green repair rounds: 7
- fixed failures: 33
- rendered examples: 8
- live PTY passes: 20
- full-suite passes: 3
- candidate build p95: 2.952 ms
- candidate build gate: 20 ms

Local container rerun:

- `./test/run.sh`: PASS
- assertions: 735

The local rerun changed timing JSON, so the archive hash remains the source of truth for packaged release evidence.
