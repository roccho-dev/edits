# WT-05A Canon: candidate OCI CI and release

This lane is Green only when one Nix-backed Python entrypoint builds the candidate Docker archive, OCI archive, and no-build Windows kit; the mandatory pytest E2E suite is the only candidate runtime gate; and the exact tested commit is retained as a prerelease. Physical Windows/WSLC readback remains WT-05 and is not promoted by this lane.
