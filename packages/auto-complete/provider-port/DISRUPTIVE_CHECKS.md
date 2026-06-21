# disruptive checks

The proposal is blocked unless these stay true after the provider-port import.

1. LSP wire types do not enter core.
2. Provider adapter errors are preserved and not rewritten as missing adapter errors.
3. Provider item without rank fails closed.
4. Request without limit fails closed.
5. Alias candidate remains reachable through `filter_text`.
6. Alias does not force hiragana preedit mutation.
7. Candidate core does not read Vim buffer directly.
8. Commit remains the only buffer writer.
9. Selected state remains editor-owned.
10. Ghost and commit derive from the same selected candidate.
11. Tab stays editor-owned when popup is absent.
12. Rerun-updated timing JSON is not treated as canonical archive hash evidence.
