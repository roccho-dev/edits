# refactor: add transport-neutral candidate provider port

## Decision

Keep the working Japanese candidate implementation in-process, but route it through a versioned provider port. LSP remains a future transport adapter rather than the package's core type system.

## Changes

- add `jpcmp.complete.request.v1` / `jpcmp.complete.response.v1`
- validate required request `limit` and provider-item `rank`
- preserve adapter-internal errors instead of misreporting them as a missing adapter
- add the default `provider/inprocess` adapter
- add an editor orchestrator that collects buffer and provider sources
- make candidate core merge/decorate only
- keep cross-source rank, selected state, ghost and commit editor-owned
- keep alias candidates reachable without forcing alias text into hiragana preedit
- map alias `filter_text` to the matching alias
- document future LSP mapping without implementing JSON-RPC

## Proof

- 735 assertions PASS
- provider contract: 38 assertions PASS
- rendered example matrix: 8/8 PASS
- live PTY: PASS
- three independent full-suite runs: 3/3 PASS
- candidate build: 500 runs, p95 2.952 ms, gate below 20 ms

## Explicitly not included

LSP, JSON-RPC, Helix/Neovim clients, document synchronization, cancellation and external process lifecycle.

## Commits

- initial provider-port implementation: `5a3e871f58a8276d3c69187e50c0bc012c600402`
- contract hardening / tested commit: `4b8477c5171293642b2d5f1a6c3983e36ae37b81`
- proof release: `0629e7cfada32afe29f851cbd0923b9b9adc6fc6`
- tag: `proof-provider-port-260621`
