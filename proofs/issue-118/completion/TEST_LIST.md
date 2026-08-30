# Test list

1. A completion-state contract distinguishes source integration, CI-complete delivery, and physical Windows closure.
2. The workflow resolves its output directory at step runtime and does not use `runner.*` in job-level environment values.
3. The Release readback implementation exists exactly once.
4. The workflow no longer retains a superseded candidate-only push branch.
5. Machine output reports `CI_PASS` while physical Windows/WSLC and Issue #118 closure remain explicitly open.

Existing WT-05a and archive tests continue to enforce the single Nix entrypoint,
required Release assets, byte-exact readback, PR non-publication, Docker/OCI E2E,
no JUnit/XML, and no skip/xfail/waiver behavior.
