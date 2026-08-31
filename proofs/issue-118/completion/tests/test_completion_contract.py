from __future__ import annotations

from pathlib import Path
import unittest


REPO = Path(__file__).resolve().parents[4]


def text(relative: str) -> str:
    path = REPO / relative
    assert path.is_file(), relative
    return path.read_text(encoding="utf-8")


class TestCompletionContract(unittest.TestCase):
    def test_completion_state_contract_exists(self) -> None:
        source = text("proofs/issue-118/COMPLETION.md")
        self.assertIn("State 1 — source integrated", source)
        self.assertIn("State 2 — CI complete and downloadable", source)
        self.assertIn("State 3 — Issue #118 physically closed", source)

    def test_workflow_uses_step_runtime_directory_not_job_runner_context(self) -> None:
        source = text(".github/workflows/candidate-oci-release.yml")
        env_block = source.split("    env:\n", 1)[1].split("    steps:\n", 1)[0]
        self.assertNotIn("runner.", env_block)
        self.assertIn("RUNNER_TEMP/edits-candidate-release", source)

    def test_release_readback_has_one_implementation(self) -> None:
        source = text(".github/workflows/candidate-oci-release.yml")
        self.assertEqual(source.count("verify_release()"), 1)

    def test_workflow_has_no_obsolete_candidate_push_branch(self) -> None:
        source = text(".github/workflows/candidate-oci-release.yml")
        self.assertNotIn("proposal/issue-118-candidate-oci-ci", source)

    def test_machine_verdict_is_ci_pass_not_physical_closure(self) -> None:
        source = text("proofs/vim-nix/candidate_ci.py")
        self.assertIn('"status": "CI_PASS"', source)
        self.assertIn('"physicalWindowsWslc": "OPEN"', source)
        self.assertIn('"issue118Closure": False', source)
        self.assertIn(
            '"finalAssertion": "CI_COMPLETE_WINDOWS_PHYSICAL_READBACK_OPEN"',
            source,
        )
