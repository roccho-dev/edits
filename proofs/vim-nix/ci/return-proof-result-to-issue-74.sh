#!/usr/bin/env bash
set -euo pipefail
source_commit="$(git rev-parse HEAD)"
cat > "$RUNNER_TEMP/issue-comment.md" <<EOF_COMMENT
## Vim/Nix/Herdr/HQ OCI proof run

status: \`$JOB_STATUS\`
proof source commit: \`$source_commit\`
Actions run request commit: \`$GITHUB_SHA\`
run: https://github.com/$GITHUB_REPOSITORY/actions/runs/$GITHUB_RUN_ID
semantic SHA-256: \`${SEMANTIC_SHA:-not-produced}\`
WSLC pack SHA-256: \`${PACK_SHA:-not-produced}\`
artifact ID: \`${ARTIFACT_ID:-not-produced}\`
artifact digest: \`${ARTIFACT_DIGEST:-not-produced}\`
exact-tag prerelease: ${RELEASE_URL:-not-produced}

Final Git bundles remain intentionally absent until independent WSLC acceptance.
EOF_COMMENT
gh issue comment "$ISSUE_NUMBER" --repo "$GITHUB_REPOSITORY" --body-file "$RUNNER_TEMP/issue-comment.md"
