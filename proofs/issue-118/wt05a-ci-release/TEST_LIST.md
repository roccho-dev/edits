# Test list

1. One candidate build entrypoint exists.
2. The flake exposes that entrypoint as one app.
3. Nix exposes Docker, OCI, and Windows-kit outputs.
4. Candidate orchestration is Python and invokes pytest.
5. Candidate pytest contains no skip or xfail path.
6. Pytest covers interactive PTY smoke.
7. Pytest covers full runtime lifecycle and accepted history.
8. Pytest covers volume persistence and OCI mutation rejection.
9. The Windows kit verifies the tar and loaded image ID before run.
10. The GitHub workflow invokes the one entrypoint exactly once.
11. The workflow retains OCI and Windows assets in an exact-commit prerelease.
12. Legacy shell CI concatenation is not used by the candidate workflow.
