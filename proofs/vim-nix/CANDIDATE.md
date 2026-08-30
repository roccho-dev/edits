# Candidate OCI build and release

There is one supported build entrypoint:

```text
nix run ./proofs/vim-nix#candidate -- \
  --repo-root "$PWD" \
  --output /absolute/output/directory \
  --release-tag edits-candidate-<exact-commit>
```

It refuses a dirty worktree, overrides the flake's `editsSource` with the exact
current Git commit, builds the same Nix outputs normally and offline, and then
runs the mandatory pytest E2E suite.

Nix outputs:

- interactive Docker archive for WSLC;
- OCI image-layout archive;
- deterministic Windows ZIP containing the Docker archive, hash gate, image-ID
  readback, and `verify.cmd` / `run.cmd`;
- exact image reference and source-bound runtime closure.

Pytest gates:

- Docker archive config and role entrypoints;
- `edits-client`, `edits-service`, and `edits-mux` provider execution;
- interactive PTY smoke;
- full Vim/HQ/worker lifecycle;
- accepted-history recall;
- durable `dev-home` and `repos` named volumes;
- OCI digest verification and one-byte mutation rejection;
- Windows kit completeness and embedded Docker-archive identity.

No test is skipped or xfailed. The remaining shell programs are the existing
PTY/product launcher and the already-proved in-container lifecycle scripts.
Build orchestration, archive verification, release assembly, Windows packaging,
and E2E control are Python.

The GitHub workflow `candidate-oci-release.yml` invokes only this entrypoint.
After all gates pass, it creates an exact-commit prerelease containing both OCI
forms, the ready-to-run Windows ZIP, machine receipts, pytest JUnit output, and
an exact source Git bundle.
