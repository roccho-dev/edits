# Test list

1. The Nix layered image creates `/home/dev` and `/work/repos` without privileged build-user `chown`.
2. `fakeRootCommands` records UID/GID `1000:1000` for both directories.
3. Docker archive inspection reads effective layer metadata and requires the expected UID, GID, mode, and directory type.
4. OCI archive inspection applies the same requirement.
5. OCI runtime config requires `User=1000:1000`.
6. A wrong owner, group, mode, type, missing path, or runtime user fails closed.
7. Existing writable-volume and persistence E2E remains mandatory.
