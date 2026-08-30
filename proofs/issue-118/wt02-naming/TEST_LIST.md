# Test list

1. Provide executable product entrypoints for client, service, and mux.
2. Add `EditsStart` while retaining `HqStart` through the same implementation.
3. Add `EditsSubmit` while retaining `HqSubmit` through the same implementation.
4. Add `EditsDoctor` while retaining `HqDoctor` through the same implementation.
5. Prefer new globals while accepting legacy globals.
6. Define deterministic new/legacy configuration precedence.
7. Keep `/bin/edits` as the normal product entry.
8. Keep persisted `hq.*` wire kinds unchanged in V1.
9. Distinguish stable product roles from exact providers in help/readback.
10. Prove old/new aliases produce semantically equal E2E receipts.
11. Cover every Golden legacy surface.
12. Prove no required journey needs only a new name.
