# Candidate rootfs ownership fix

The first real PR #120 candidate build reached the Nix layered-image derivation and failed because ordinary `extraCommands` attempted privileged numeric `chown` as the Nix build user.

The repaired contract is:

```text
extraCommands
  = create directories and set modes

fakeRootCommands
  = record uid/gid 1000:1000 in the image layer

Docker + OCI archive inspection
  = read effective layer metadata and fail closed on mismatch

runtime E2E
  = prove the non-root user can use and persist both mounted state roots
```

Merge remains blocked unless the exact PR merge head passes the one Nix candidate entrypoint, Docker and OCI pytest E2E, Windows ZIP generation, and all pre-existing controls without skip, xfail, or waiver. Physical Windows/WSLC remains a later external gate.
