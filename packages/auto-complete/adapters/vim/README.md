# adapter: vim

Vim adapter boundary.

Vim may own:

- editor integration
- optional UI experiments
- key behavior in Vim
- commit invocation
- undo/window/timer cleanup proof when rich UI is enabled

Vim must not own:

- dictionary parsing
- provider normalization
- cross-provider rank merge
- LSP completion mapping
- general Japanese conversion engine

The current package keeps Vim golden proof as a regression contract while the adapter is progressively wired to the Go core/LSP path.
