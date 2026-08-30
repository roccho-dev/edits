# Candidate OCI build, E2E, and Release

There is one supported build/proof entrypoint:

```text
nix run ./proofs/vim-nix#candidate -- \
  --repo-root "$PWD" \
  --output /absolute/output/directory \
  --release-tag edits-candidate-<exact-commit>
```

The entrypoint refuses a dirty worktree and binds the flake input to the exact
current Git commit. It then performs, in order:

1. fixed Canon-TDD and archive-unit pytest gates;
2. normal Nix builds for the product closure, Docker archive, OCI archive,
   Windows ZIP, and image reference;
3. offline builds of the same outputs;
4. forced Nix rebuilds of the Docker archive, OCI archive, and Windows ZIP;
5. independent config, manifest, and every-layer digest verification;
6. Docker-archive load and OCI-archive import as separate runtime lanes;
7. mandatory pytest E2E against both runtime lanes;
8. exact Git bundle, evidence ZIP, manifests, JUnit XML, and checksums.

Mandatory E2E includes:

- `edits-client`, `edits-service`, and `edits-mux` provider execution;
- interactive PTY smoke;
- full Vim → service → accepted instruction → worker → result lifecycle;
- exact result kinds `accepted → started → stdout → completed`;
- accepted-history recall;
- durable `dev-home` and `repos` named volumes;
- Docker/OCI config and layer equality;
- one-byte OCI mutation rejection;
- relative provider-binding rejection;
- default entrypoint rejection without a real TTY;
- deterministic no-build, no-registry Windows delivery validation.

Pytest JUnit must contain zero failures, errors, and skipped cases. A successful
Docker lane cannot compensate for a failed OCI lane, and neither can claim a
physical Windows/WSLC pass.

The remaining shell programs are bounded in-container PTY/product launchers and
the pre-existing lifecycle proof. Python owns build orchestration, archive
inspection, evidence assembly, Windows packaging validation, and E2E control.
Python is not added to the production image solely for CI orchestration.

The GitHub workflow invokes the build entrypoint exactly once. Pull requests run
all gates without publishing. A successful `proposals` push, or an explicit
workflow dispatch, creates an exact-commit prerelease containing:

- `*.docker.tar` for WSLC load;
- `*.oci.tar` as the OCI release artifact;
- `*.windows.zip` containing the Docker archive plus `verify.cmd` and `run.cmd`;
- exact source Git bundle;
- build/E2E manifests, JUnit, evidence ZIP, and `SHA256SUMS`.

A Windows user downloads only the `.windows.zip`, extracts it, runs
`verify.cmd`, then `run.cmd`. Windows performs no build and needs no registry.
Physical Windows/WSLC readback remains a separate final gate after download.
