# WT-02 naming and compatibility RED

Purpose: expose the stable `edits-client`, `edits-service`, and `edits-mux` product roles without changing behavior or deleting any existing `hq` Vim/config surface.

Merge condition: new and legacy surfaces invoke the same semantic path, old persisted `hq.*` contracts remain readable, and no required journey is available only through the new names.
