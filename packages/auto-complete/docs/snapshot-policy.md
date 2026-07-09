# snapshot policy

Candidate and LSP snapshots freeze behavior that is easy to break silently:

- candidate labels;
- source;
- rank and score;
- `filterText`;
- `sortText`;
- `textEdit.range`;
- `textEdit.newText`.

UX snapshots freeze the semantic visual evidence payload instead of pixel output.

A snapshot update is allowed only when the PR intentionally changes the completion contract and explains why the new behavior is better.
