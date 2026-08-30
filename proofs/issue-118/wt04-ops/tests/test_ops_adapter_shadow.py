from __future__ import annotations

import json
from pathlib import Path
import unittest

REPO = Path(__file__).resolve().parents[4]
EVIDENCE = REPO / "proofs" / "issue-118" / "ops-adapter"


def load(name: str):
    path = EVIDENCE / name
    if not path.is_file():
        raise AssertionError(f"missing ops-adapter evidence: {path.relative_to(REPO)}")
    return json.loads(path.read_text(encoding="utf-8"))


class TestOpsAdapterShadow(unittest.TestCase):
    def test_catalog_intake_result_and_view_plan_packages_exist(self) -> None:
        for name in ("catalog", "intake", "results", "view-plan"):
            path = REPO / "packages" / "ops-adapter" / name
            self.assertTrue(path.is_dir(), path)

    def test_exact_ops_release_and_catalog_digest_are_bound(self) -> None:
        data = load("release-binding.json")
        self.assertTrue(data.get("opsReleaseId"))
        self.assertEqual(len(data.get("opsReleaseDigest", "")), 64)
        self.assertEqual(len(data.get("operationCatalogDigest", "")), 64)
        self.assertEqual(data.get("mutableRefCount"), 0)
        self.assertEqual(data.get("status"), "PASS")

    def test_catalog_validation_rejects_malformed_duplicate_orphan_and_unknown_rows(self) -> None:
        data = load("catalog-validation.json")
        for case in ("malformed", "duplicate-operation", "orphan-command", "unknown-operation-kind"):
            self.assertEqual(data.get("negative", {}).get(case), "REJECTED", case)
        self.assertEqual(data.get("acceptedInvalidRows"), 0)
        self.assertEqual(data.get("status"), "PASS")

    def test_shadow_candidates_are_semantically_equal_to_legacy_candidates(self) -> None:
        data = load("shadow-candidates.json")
        self.assertGreater(data.get("fixtureCount", 0), 0)
        self.assertEqual(data.get("candidateSetMismatches"), 0)
        self.assertEqual(data.get("relativeOrderMismatches"), 0)
        self.assertEqual(data.get("editPlanMismatches"), 0)
        self.assertEqual(data.get("status"), "PASS")

    def test_pre_accept_ops_intake_count_is_zero(self) -> None:
        data = load("acceptance-effects.json")
        self.assertEqual(data.get("completionIntakeCount"), 0)
        self.assertEqual(data.get("previewIntakeCount"), 0)
        self.assertEqual(data.get("selectionIntakeCount"), 0)
        self.assertEqual(data.get("undoIntakeCount"), 0)

    def test_one_explicit_accept_produces_exactly_one_ops_intake(self) -> None:
        data = load("acceptance-effects.json")
        self.assertGreater(data.get("submitFixtures", 0), 0)
        self.assertEqual(data.get("intakePerExplicitSubmit"), 1)
        self.assertEqual(data.get("duplicateIntakes"), 0)
        self.assertEqual(data.get("status"), "PASS")

    def test_edits_direct_executable_start_count_is_zero(self) -> None:
        data = load("effect-boundary.json")
        self.assertEqual(data.get("directPackageExecutableStarts"), 0)
        self.assertEqual(data.get("workerProcessControls"), 0)
        self.assertEqual(data.get("arbitraryShellStarts"), 0)

    def test_ops_unavailable_fails_closed_without_local_fallback(self) -> None:
        data = load("ops-unavailable.json")
        self.assertEqual(data.get("status"), "NON_GREEN")
        self.assertEqual(data.get("localFallbackEffects"), 0)
        self.assertEqual(data.get("acceptedAsSuccess"), False)

    def test_stale_result_generation_is_rejected(self) -> None:
        data = load("result-generation.json")
        self.assertGreater(data.get("staleFixtures", 0), 0)
        self.assertEqual(data.get("staleRenderedAsCurrent"), 0)
        self.assertEqual(data.get("staleAcceptedAsSuccess"), 0)
        self.assertEqual(data.get("status"), "PASS")

    def test_provider_reference_never_replaces_canonical_run_id(self) -> None:
        data = load("identity-separation.json")
        self.assertGreater(data.get("fixtureCount", 0), 0)
        self.assertEqual(data.get("providerRefAsRunId"), 0)
        self.assertEqual(data.get("paneRefAsRunId"), 0)
        self.assertEqual(data.get("status"), "PASS")

    def test_result_projection_is_read_only(self) -> None:
        data = load("result-projection.json")
        self.assertEqual(data.get("canonicalWrites"), 0)
        self.assertEqual(data.get("statusMutations"), 0)
        self.assertEqual(data.get("retryDecisions"), 0)
        self.assertEqual(data.get("cancelDecisions"), 0)
        self.assertEqual(data.get("status"), "PASS")

    def test_runtime_ops_head_reads_are_zero(self) -> None:
        data = load("release-binding.json")
        self.assertEqual(data.get("runtimeRepositoryHeadReads"), 0)
        self.assertEqual(data.get("runtimeMutableBranchReads"), 0)

    def test_new_released_operation_projects_without_edits_source_change(self) -> None:
        data = load("data-only-extension.json")
        self.assertGreater(data.get("newOperationFixtures", 0), 0)
        self.assertEqual(data.get("editsSourceChanges"), 0)
        self.assertEqual(data.get("projectedOperations"), data.get("newOperationFixtures"))
        self.assertEqual(data.get("status"), "PASS")

    def test_shadow_mode_effect_count_is_zero(self) -> None:
        data = load("shadow-effects.json")
        self.assertGreater(data.get("shadowRequests", 0), 0)
        self.assertEqual(data.get("effects"), 0)
        self.assertEqual(data.get("durableWrites"), 0)
        self.assertEqual(data.get("status"), "PASS")


if __name__ == "__main__":
    unittest.main()
