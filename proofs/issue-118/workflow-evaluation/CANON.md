# Canon TDD — workflow evaluation and authority

The source-integrated candidate is not complete while GitHub rejects workflows
before creating jobs. All retained workflows must use runner-specific paths only
inside steps, after a runner exists.

Pull-request code must build and test with read-only repository permission.
Exact-commit prerelease publication is a separate job, depends on the completed
build artifact, and receives write permission only on push or an explicitly
requested dispatch.

The one candidate Nix entrypoint must execute both the completion and workflow-evaluation Canon gates before planning, building, testing, or publishing artifacts.
