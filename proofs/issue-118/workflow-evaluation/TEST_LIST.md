# Test list

1. Every retained workflow avoids `runner.*` in job-level `env` values.
2. The one candidate entrypoint executes the completion and workflow-evaluation Canon gates.
3. The candidate OCI build/E2E job has read-only repository permission and no release token.
4. Release publication is a separate write-scoped job that never runs for pull requests.
