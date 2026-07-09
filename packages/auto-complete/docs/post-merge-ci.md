# post-merge CI verification

The auto-complete workflow must run on both pull requests and pushes to `proposals` for these paths:

- `packages/auto-complete/**`
- `.github/workflows/auto-complete-golden.yml`

A PR-head green run is not enough to close #37. After the hardening PR merges, the final closure comment on #37 must record the post-merge workflow run id and conclusion.
