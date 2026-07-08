# UX visual evidence gate

The original `golden` wording was too broad. The existing checks proved candidate-contract behavior, but did not produce a visual artifact.

This gate adds deterministic CI visual evidence.

## What it proves

- raw buffer is shown as `houji`
- preedit projection is shown as `ほうじ`
- the rendered candidate list includes `houjinScore`, `法人`, and `法人売却`
- the source of truth is the Go `jpcmp-lsp` JSON-RPC completion response

## What it does not prove

This is not a full GUI screenshot of a human using Vim or Helix. It is CI-rendered visual evidence from the same LSP response used by the adapter proof.

A true terminal/editor screenshot can be added later as a stricter proof, but this closes the immediate evidence gap without adding brittle GUI dependencies.

## Artifacts

CI uploads:

- `artifacts/ux-golden.svg`
- `artifacts/ux-golden.json`
- `artifacts/ux-golden.md`
