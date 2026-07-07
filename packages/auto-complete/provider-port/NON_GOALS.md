# non-goals

This step does not add:

- LSP transport
- JSON-RPC transport
- Helix client adapter
- Neovim client adapter
- external provider service
- document synchronization
- request cancellation
- installer or release packaging

The proposal only fixes the source boundary so those can be added later without moving editor-owned UX state into the provider.
