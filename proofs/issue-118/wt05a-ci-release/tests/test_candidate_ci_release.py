from __future__ import annotations

from pathlib import Path
import unittest

REPO = Path(__file__).resolve().parents[4]


def text(relative: str) -> str:
    path = REPO / relative
    if not path.is_file():
        raise AssertionError(f"missing required file: {relative}")
    return path.read_text(encoding="utf-8")


class TestCandidateCiRelease(unittest.TestCase):
    def test_candidate_build_entrypoint_exists(self) -> None:
        self.assertTrue((REPO / "proofs/vim-nix/candidate_ci.py").is_file())

    def test_flake_exposes_one_candidate_app(self) -> None:
        source = text("proofs/vim-nix/flake.parts/01.nix")
        self.assertEqual(source.count("apps.${system}.candidate"), 1)

    def test_nix_exposes_all_release_materializations(self) -> None:
        source = text("proofs/vim-nix/flake.parts/01.nix")
        for token in ("interactiveImage", "interactiveOciImage", "interactiveWindowsKit"):
            self.assertIn(token, source)

    def test_orchestration_is_python_and_invokes_pytest(self) -> None:
        source = text("proofs/vim-nix/candidate_ci.py")
        self.assertIn("import pytest", source)
        self.assertIn("pytest.main", source)

    def test_candidate_pytest_has_no_skip_or_xfail(self) -> None:
        source = text("proofs/vim-nix/tests/test_candidate_oci.py")
        self.assertNotIn("pytest.skip", source)
        self.assertNotIn("pytest.mark.skip", source)
        self.assertNotIn("pytest.mark.xfail", source)

    def test_pytest_covers_interactive_pty_smoke(self) -> None:
        source = text("proofs/vim-nix/tests/test_candidate_oci.py")
        self.assertIn("EDITS_INTERACTIVE_PTY_SMOKE_PASS", source)

    def test_pytest_covers_runtime_and_history(self) -> None:
        source = text("proofs/vim-nix/tests/test_candidate_oci.py")
        self.assertIn("VIM_NIX_FULL_E2E_PASS", source)
        self.assertIn("VIM_NIX_ACCEPTED_HISTORY_E2E_PASS", source)

    def test_pytest_covers_persistence_and_mutation_rejection(self) -> None:
        source = text("proofs/vim-nix/tests/test_candidate_oci.py")
        self.assertIn("test_named_volumes_preserve_home_and_workspace", source)
        self.assertIn("test_oci_archive_is_fail_closed_on_mutation", source)

    def test_windows_kit_hashes_and_inspects_before_run(self) -> None:
        source = text("proofs/vim-nix/windows_kit.py")
        self.assertLess(source.index("Get-FileHash"), source.index("& $Wslc load -i $Archive"))
        self.assertLess(source.index("& $Wslc inspect $Image"), source.index("& $Wslc @Args"))

    def test_workflow_calls_one_entrypoint_once(self) -> None:
        source = text(".github/workflows/candidate-oci-release.yml")
        self.assertEqual(source.count("nix run ./proofs/vim-nix#candidate"), 1)

    def test_workflow_releases_oci_and_windows_assets(self) -> None:
        source = text(".github/workflows/candidate-oci-release.yml")
        self.assertIn("*.oci.tar", source)
        self.assertIn("*.windows.zip", source)
        self.assertIn("gh release create", source)
        self.assertIn("--prerelease", source)

    def test_workflow_does_not_concatenate_legacy_shell_ci(self) -> None:
        source = text(".github/workflows/candidate-oci-release.yml")
        self.assertNotIn("ci.parts", source)
        self.assertNotIn("cat proofs/vim-nix", source)


if __name__ == "__main__":
    unittest.main()
