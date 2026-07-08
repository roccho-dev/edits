# LSP migration plan

## Goal

Move from Vimscript-owned candidate generation to a Go LSP server while keeping the existing Japanese completion behavior.

## Phases

1. Golden CI freezes current behavior.
2. Go core reproduces candidate, rank, and textEdit behavior.
3. Vim calls LSP for candidates.
4. Vimscript stops owning dictionary, rank, and candidate generation.
5. Helix uses the same LSP server as a normal LSP client.

## Non-goals

- Build a general Japanese IME.
- Replace Mozc, Anthy, Rime, or SKK.
- Add custom Helix UI.
- Depend on ghost UI.
