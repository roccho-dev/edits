# import graph boundary

The reusable core boundary is mechanical:

- `lib/jpcmp/core` must not import concrete adapters, app wiring, commands, JSONL/file parsing, LSP, Vim, or Helix code.
- `lib/jpcmp/ports` must not import concrete source, transport, editor, app, or command packages.
- source adapters may import core and ports.
- app wiring owns concrete adapter composition.

This is checked by `test/import_graph_check.py`.
