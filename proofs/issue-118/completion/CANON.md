# Canon TDD — Issue #118 completion PR

These tests are the fixed merge contract for the post-#119 completion PR.

The PR may merge only when the exact PR head:

1. creates a GitHub Actions job instead of failing during workflow evaluation;
2. invokes the one Nix candidate entrypoint exactly once;
3. builds and tests Docker and OCI lanes through pytest;
4. creates or verifies an immutable exact-commit prerelease;
5. downloads and byte-compares every Release asset;
6. leaves physical Windows/WSLC explicitly OPEN;
7. contains no JUnit/XML projection, skip, xfail, or waiver.

No test deletion, assertion weakening, waiver, or post-result scope reduction is
permitted. The five tests in this lane are the missing post-#119 conditions; the
existing WT-05a and archive suites remain mandatory controls.
