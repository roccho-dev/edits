from __future__ import annotations

from pathlib import Path
import re
import unittest


REPO = Path(__file__).resolve().parents[4]
WORKFLOWS = REPO / ".github" / "workflows"
CANDIDATE = WORKFLOWS / "candidate-oci-release.yml"


def job_env_values(source: str) -> list[str]:
    """Return values from job-level env blocks using only YAML indentation."""
    lines = source.splitlines()
    values: list[str] = []
    in_jobs = False
    in_job = False
    in_job_env = False
    for line in lines:
        stripped = line.strip()
        indent = len(line) - len(line.lstrip(" "))
        if indent == 0 and stripped == "jobs:":
            in_jobs = True
            in_job = False
            in_job_env = False
            continue
        if in_jobs and indent == 0 and stripped and not stripped.startswith("#"):
            in_jobs = False
            in_job = False
            in_job_env = False
        if not in_jobs:
            continue
        if indent == 2 and stripped.endswith(":"):
            in_job = True
            in_job_env = False
            continue
        if in_job and indent == 4 and stripped == "env:":
            in_job_env = True
            continue
        if in_job_env and indent <= 4 and stripped:
            in_job_env = False
        if in_job_env and indent >= 6 and ":" in stripped:
            values.append(stripped.split(":", 1)[1].strip())
    return values


class TestWorkflowEvaluation(unittest.TestCase):
    def test_all_workflows_avoid_runner_context_in_job_env(self) -> None:
        offenders: list[str] = []
        for path in sorted(WORKFLOWS.glob("*.y*ml")):
            for value in job_env_values(path.read_text(encoding="utf-8")):
                if "runner." in value:
                    offenders.append(f"{path.name}: {value}")
        self.assertEqual(offenders, [])


    def test_candidate_entrypoint_runs_completion_canons(self) -> None:
        source = (REPO / "proofs" / "vim-nix" / "candidate_ci.py").read_text(encoding="utf-8")
        self.assertIn("canon_runner.py", source)
        self.assertIn("proofs/issue-118/completion", source)
        self.assertIn("proofs/issue-118/workflow-evaluation", source)
        self.assertIn("--expect-green", source)

    def test_candidate_build_job_has_read_only_repository_permission(self) -> None:
        source = CANDIDATE.read_text(encoding="utf-8")
        self.assertRegex(source, r"(?m)^permissions:\n  contents: read$")
        build = source.split("  build-e2e:\n", 1)[1].split("  publish-release:\n", 1)[0]
        self.assertNotIn("contents: write", build)
        self.assertNotIn("GH_TOKEN", build)

    def test_release_transport_is_a_separate_write_scoped_job(self) -> None:
        source = CANDIDATE.read_text(encoding="utf-8")
        self.assertIn("  publish-release:\n", source)
        publish = source.split("  publish-release:\n", 1)[1]
        self.assertIn("needs: build-e2e", publish)
        self.assertIn("permissions:\n      contents: write", publish)
        self.assertIn("actions/download-artifact@", publish)
        condition = re.search(r"(?m)^    if: (.+)$", publish)
        self.assertIsNotNone(condition)
        assert condition is not None
        self.assertIn("github.event_name == 'push'", condition.group(1))
        self.assertIn("workflow_dispatch", condition.group(1))
        self.assertNotIn("pull_request", condition.group(1))
