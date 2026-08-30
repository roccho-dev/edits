from __future__ import annotations

import json
from pathlib import Path
import re
import stat
import unittest

REPO = Path(__file__).resolve().parents[4]
EVIDENCE = REPO / "proofs" / "issue-118" / "parity"
GOLDEN_SHA = "fba9c3bb803d9269c32d15b27910c4ff2a77eba44a13afa343d8e2e9815b9022"
GOLDEN_ID = "sha256:ba3e136d7bf01f94433b91c5eebb632f70c5c25f745b5e793d735e3da393e32e"


def load(name: str):
    path = EVIDENCE / name
    if not path.is_file():
        raise AssertionError(f"missing parity evidence: {path.relative_to(REPO)}")
    return json.loads(path.read_text(encoding="utf-8"))


def source(path: Path) -> str:
    if not path.is_file():
        raise AssertionError(f"missing required file: {path.relative_to(REPO)}")
    return path.read_text(encoding="utf-8")


class TestNixWindowsParity(unittest.TestCase):
    def test_nix_product_candidate_and_parity_entrypoints_exist(self) -> None:
        for name in ("product.nix", "candidate-image.nix", "parity-proof.nix"):
            self.assertTrue((REPO / "nix" / name).is_file(), name)

    def test_exact_candidate_inputs_are_bound(self) -> None:
        data = load("candidate-source-lock.json")
        for key in ("editsCommit", "hqCommit", "vimCommit", "yegappanCommit", "herdrVersion", "nixpkgsRevision"):
            self.assertTrue(data.get(key), key)
        self.assertEqual(data.get("mutableInputs"), 0)
        self.assertEqual(data.get("dirtySources"), 0)
        self.assertEqual(data.get("status"), "PASS")

    def test_two_clean_builds_have_identical_image_identity(self) -> None:
        data = load("reproducible-build.json")
        self.assertEqual(data.get("cleanBuildCount"), 2)
        self.assertEqual(data.get("buildA", {}).get("imageId"), data.get("buildB", {}).get("imageId"))
        self.assertEqual(data.get("buildA", {}).get("manifestDigest"), data.get("buildB", {}).get("manifestDigest"))
        self.assertEqual(data.get("status"), "PASS")

    def test_archive_config_manifest_and_layers_are_verified(self) -> None:
        data = load("candidate-image-inspect.json")
        self.assertTrue(data.get("archiveSha256"))
        self.assertTrue(data.get("imageId", "").startswith("sha256:"))
        self.assertTrue(data.get("configDigest", "").startswith("sha256:"))
        self.assertTrue(data.get("manifestDigest", "").startswith("sha256:"))
        self.assertGreater(len(data.get("layerDigests", [])), 0)
        self.assertEqual(data.get("digestMismatches"), 0)
        self.assertEqual(data.get("status"), "PASS")

    def test_windows_verify_checks_tar_hash_before_load(self) -> None:
        script = source(REPO / "dist" / "windows" / "verify.ps1")
        hash_pos = script.find("Get-FileHash")
        load_pos = script.lower().find("wslc.exe' load")
        self.assertGreaterEqual(hash_pos, 0)
        self.assertGreater(load_pos, hash_pos)
        self.assertIn("throw", script)

    def test_windows_verify_checks_image_id_before_run(self) -> None:
        script = source(REPO / "dist" / "windows" / "run.ps1")
        inspect_pos = script.lower().find("wslc.exe' inspect")
        run_pos = script.lower().find("wslc.exe' run")
        self.assertGreaterEqual(inspect_pos, 0)
        self.assertGreater(run_pos, inspect_pos)
        self.assertIn("EXPECTED_IMAGE_ID", script)

    def test_launch_preserves_tty_volumes_workdir_and_no_ports(self) -> None:
        data = load("launch-contract.json")
        self.assertEqual(data.get("interactive"), True)
        self.assertEqual(data.get("tty"), True)
        self.assertEqual(data.get("volumes"), ["dev-home:/home/dev", "repos:/work/repos"])
        self.assertEqual(data.get("workdir"), "/work/repos")
        self.assertEqual(data.get("exposedPorts"), 0)
        self.assertEqual(data.get("status"), "PASS")

    def test_golden_tar_identity_is_unchanged_and_read_back(self) -> None:
        data = load("golden-readback.json")
        self.assertEqual(data.get("dockerTarSha256"), GOLDEN_SHA)
        self.assertEqual(data.get("imageId"), GOLDEN_ID)
        self.assertEqual(data.get("modified"), False)
        self.assertEqual(data.get("status"), "PASS")

    def test_physical_windows_wslc_journey_passes(self) -> None:
        data = load("physical-windows-wslc.json")
        self.assertEqual(data.get("physicalWindows"), True)
        self.assertTrue(data.get("wslcVersion"))
        self.assertEqual(data.get("goldenStatus"), "PASS")
        self.assertEqual(data.get("candidateStatus"), "PASS")
        self.assertEqual(data.get("status"), "PASS")

    def test_semantic_parity_is_complete(self) -> None:
        data = load("semantic-parity.json")
        self.assertGreater(data.get("requiredJourneys", 0), 0)
        self.assertEqual(data.get("coveredJourneys"), data.get("requiredJourneys"))
        self.assertEqual(data.get("semanticMismatches"), 0)
        self.assertEqual(data.get("status"), "PASS")

    def test_state_and_persistence_parity_is_complete(self) -> None:
        data = load("state-parity.json")
        self.assertEqual(data.get("homeVolumePass"), True)
        self.assertEqual(data.get("reposVolumePass"), True)
        self.assertEqual(data.get("acceptedHistoryPass"), True)
        self.assertEqual(data.get("completedResultReadbackPass"), True)
        self.assertEqual(data.get("stateMismatches"), 0)
        self.assertEqual(data.get("status"), "PASS")

    def test_failure_parity_is_complete(self) -> None:
        data = load("failure-parity.json")
        self.assertGreater(data.get("requiredCases", 0), 0)
        self.assertEqual(data.get("coveredCases"), data.get("requiredCases"))
        self.assertEqual(data.get("falseSuccesses"), 0)
        self.assertEqual(data.get("duplicateEffects"), 0)
        self.assertEqual(data.get("lostResults"), 0)
        self.assertEqual(data.get("status"), "PASS")

    def test_predeclared_paired_performance_parity_passes(self) -> None:
        data = load("performance-parity.json")
        self.assertEqual(data.get("budgetFrozenBeforeCandidate"), True)
        self.assertGreaterEqual(data.get("goldenAaPairs", 0), 20)
        self.assertGreaterEqual(data.get("oldNewPairs", 0), 20)
        self.assertEqual(data.get("budgetViolations"), 0)
        self.assertEqual(data.get("indeterminateMetrics"), 0)
        self.assertEqual(data.get("status"), "PASS")

    def test_all_non_green_counts_are_zero(self) -> None:
        data = load("parity-verdict.json")
        for key in ("failed", "mandatorySkipped", "waivers", "unknown", "observableRegressions", "falseSuccesses", "duplicateEffects", "lostResults"):
            self.assertEqual(data.get(key), 0, key)
        self.assertEqual(data.get("status"), "PASS")

    def test_delivery_requires_no_external_registry(self) -> None:
        data = load("delivery-contract.json")
        self.assertEqual(data.get("externalRegistryRequired"), False)
        self.assertEqual(data.get("localArchiveLoad"), True)
        self.assertEqual(data.get("runtimeNetworkInstall"), False)
        self.assertEqual(data.get("status"), "PASS")

    def test_exact_candidate_git_bundle_is_carried_and_verified(self) -> None:
        data = load("candidate-source-bundle.json")
        self.assertEqual(len(data.get("commit", "")), 40)
        self.assertEqual(len(data.get("tree", "")), 40)
        self.assertEqual(len(data.get("bundleSha256", "")), 64)
        self.assertEqual(data.get("bundleVerify"), "PASS")
        self.assertEqual(data.get("cloneReadback"), "PASS")
        self.assertEqual(data.get("status"), "PASS")


if __name__ == "__main__":
    unittest.main()
