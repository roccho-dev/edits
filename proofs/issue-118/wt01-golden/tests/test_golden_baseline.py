from __future__ import annotations

import hashlib
import json
import os
from pathlib import Path
import subprocess
import unittest

REPO = Path(__file__).resolve().parents[4]
ROOT = REPO / "proofs" / "golden-baseline"
BASE = "576a701507eb1d1ceb6a64bf0aa450cda3e1ad30"
EXPECTED = {
    "image": "roccho/edits:dirty-e4614cc36968",
    "imageId": "sha256:ba3e136d7bf01f94433b91c5eebb632f70c5c25f745b5e793d735e3da393e32e",
    "dockerTar": "edits-interactive-dirty-e4614cc36968.docker.tar",
    "dockerTarSha256": "fba9c3bb803d9269c32d15b27910c4ff2a77eba44a13afa343d8e2e9815b9022",
    "lockedEditsSource": "77e1861554bc5c55da6103bac0278e63e97614f1",
    "sourceNar": "sha256-iTH9pQY/mAYX/0QkQHjOrnTsD58ByNTd1erYMw/OBIQ=",
    "gitBundleSha256": "aabf0a0b57e591d3619a926b999837b1ee61ff4c21cf0a66da99faba3fbe3cde",
    "homeVolume": "dev-home:/home/dev",
    "workVolume": "repos:/work/repos",
    "workdir": "/work/repos",
    "exposedPorts": 0,
}
RECORDED_PASS = {
    "EDITS_INTERACTIVE_PTY_SMOKE_PASS",
    "VIM_NIX_RUNTIME_E2E_PASS",
    "VIM_NIX_ACCEPTED_HISTORY_E2E_PASS",
}
REQUIRED_LEGACY = {
    "command:HqStart",
    "command:HqSubmit",
    "command:HqDoctor",
    "global:g:hq_bin",
    "global:g:hq_profile",
    "global:g:hq_server_name",
    "entrypoint:edits",
}
FORBIDDEN_ALLOWED_DIFFERENCES = {
    "command-meaning",
    "candidate-rank",
    "history-eligibility",
    "edit-content",
    "undo-count",
    "durable-write-count",
    "result-meaning",
    "state-contract",
    "failure-class",
    "authority-boundary",
}


def sha(path: Path) -> str:
    h = hashlib.sha256()
    with path.open("rb") as f:
        for chunk in iter(lambda: f.read(1024 * 1024), b""):
            h.update(chunk)
    return h.hexdigest()


def load(path: Path):
    if not path.is_file():
        raise AssertionError(f"missing Golden evidence: {path.relative_to(REPO)}")
    return json.loads(path.read_text(encoding="utf-8"))


def rows(path: Path) -> list[dict]:
    if not path.is_file():
        raise AssertionError(f"missing Golden inventory: {path.relative_to(REPO)}")
    result = []
    for n, line in enumerate(path.read_text(encoding="utf-8").splitlines(), 1):
        if not line.strip():
            continue
        try:
            result.append(json.loads(line))
        except json.JSONDecodeError as exc:
            raise AssertionError(f"invalid JSONL {path.name}:{n}: {exc}") from exc
    return result


class TestGoldenBaselineContract(unittest.TestCase):
    def test_exact_identity_is_frozen(self) -> None:
        data = load(ROOT / "identity.json")
        for key, value in EXPECTED.items():
            self.assertEqual(data.get(key), value, key)
        self.assertEqual(data.get("status"), "PASS")

    def test_external_docker_tar_hash_is_read_back(self) -> None:
        receipt = load(ROOT / "receipts" / "docker-tar-readback.json")
        artifact_root = Path(os.environ.get("EDITS_GOLDEN_DELIVERY_ROOT", "/mnt/data"))
        tar = artifact_root / EXPECTED["dockerTar"]
        self.assertTrue(tar.is_file(), tar)
        self.assertEqual(sha(tar), EXPECTED["dockerTarSha256"])
        self.assertEqual(receipt.get("observedSha256"), EXPECTED["dockerTarSha256"])
        self.assertEqual(receipt.get("status"), "PASS")

    def test_nix_and_delivery_handoff_hashes_are_read_back(self) -> None:
        receipt = load(ROOT / "receipts" / "handoff-readback.json")
        artifact_root = Path(os.environ.get("EDITS_GOLDEN_DELIVERY_ROOT", "/mnt/data"))
        expected = {
            "edits-nix-handoff-dirty-e4614cc36968.tar": "e055a1a3cb3672c7cf1df5f8ea3e47dc09daca8258eee5c86629bc1ff1c32d9d",
        }
        for name, digest in expected.items():
            path = artifact_root / name
            self.assertTrue(path.is_file(), path)
            self.assertEqual(sha(path), digest)
            self.assertEqual(receipt.get("artifacts", {}).get(name), digest)
        self.assertEqual(receipt.get("status"), "PASS")

    def test_capability_inventory_is_finite_unique_and_typed(self) -> None:
        items = rows(ROOT / "capabilities.jsonl")
        ids = [item.get("capability_id") for item in items]
        self.assertGreater(len(items), 0)
        self.assertEqual(len(ids), len(set(ids)))
        required = {"capability_id", "surface", "precondition", "action", "expected_observation", "authority", "required", "source_evidence"}
        self.assertTrue(all(required.issubset(item) for item in items))

    def test_journey_inventory_contains_recorded_wslc_pass_lanes(self) -> None:
        items = rows(ROOT / "journeys.jsonl")
        ids = [item.get("journey_id") for item in items]
        self.assertGreater(len(items), 0)
        self.assertEqual(len(ids), len(set(ids)))
        observed_tokens = {token for item in items for token in item.get("expected_tokens", [])}
        self.assertTrue(RECORDED_PASS.issubset(observed_tokens))
        self.assertTrue(all(item.get("required") is True for item in items))

    def test_failure_inventory_is_finite_unique_and_typed(self) -> None:
        items = rows(ROOT / "failures.jsonl")
        ids = [item.get("failure_id") for item in items]
        self.assertGreaterEqual(len(items), 8)
        self.assertEqual(len(ids), len(set(ids)))
        required = {"failure_id", "trigger", "expected_status", "expected_effect_count", "expected_durable_writes", "source_evidence"}
        self.assertTrue(all(required.issubset(item) for item in items))

    def test_legacy_surface_inventory_is_complete(self) -> None:
        items = rows(ROOT / "legacy-surface.jsonl")
        identities = {item.get("surface_id") for item in items}
        self.assertTrue(REQUIRED_LEGACY.issubset(identities))
        self.assertTrue(all(item.get("must_preserve") is True for item in items if item.get("surface_id") in REQUIRED_LEGACY))

    def test_allowed_differences_exclude_semantic_differences(self) -> None:
        data = load(ROOT / "allowed-differences.json")
        allowed = set(data.get("allowed", []))
        denied = set(data.get("denied", []))
        self.assertTrue(FORBIDDEN_ALLOWED_DIFFERENCES.issubset(denied))
        self.assertTrue(allowed.isdisjoint(FORBIDDEN_ALLOWED_DIFFERENCES))
        self.assertEqual(data.get("frozenBeforeCandidateObservation"), True)

    def test_every_inventory_row_has_evidence(self) -> None:
        data = load(ROOT / "evidence-map.json")
        refs = data.get("refs", {})
        all_ids = set()
        for name, key in (("capabilities.jsonl", "capability_id"), ("journeys.jsonl", "journey_id"), ("failures.jsonl", "failure_id"), ("legacy-surface.jsonl", "surface_id")):
            all_ids.update(item[key] for item in rows(ROOT / name))
        self.assertEqual(set(refs), all_ids)
        self.assertTrue(all(value for value in refs.values()))

    def test_baseline_verdict_has_full_coverage_and_zero_non_green_counts(self) -> None:
        data = load(ROOT / "baseline-verdict.json")
        self.assertEqual(data.get("status"), "PASS")
        self.assertEqual(data.get("coveragePercent"), 100)
        for key in ("failed", "unknown", "skippedMandatory", "waivers"):
            self.assertEqual(data.get(key), 0, key)

    def test_product_source_cleanliness_is_receipted_and_zero(self) -> None:
        receipt = load(ROOT / "receipts" / "product-source-cleanliness.json")
        changed = subprocess.check_output(["git", "-C", str(REPO), "diff", "--name-only", BASE, "HEAD"], text=True).splitlines()
        allowed = ("proofs/issue-118/", "proofs/golden-baseline/", "tools/issue-118-golden/")
        product_changes = [path for path in changed if not path.startswith(allowed)]
        self.assertEqual(product_changes, [])
        self.assertEqual(receipt.get("productSourceChanges"), 0)
        self.assertEqual(receipt.get("status"), "PASS")

    def test_aa_performance_contract_is_frozen_before_candidate_results(self) -> None:
        data = load(ROOT / "performance.json")
        self.assertEqual(data.get("phase"), "golden-aa")
        self.assertGreaterEqual(data.get("pairedSamples", 0), 20)
        self.assertEqual(data.get("candidateResultsObserved"), False)
        self.assertTrue(data.get("metrics"))
        self.assertEqual(data.get("status"), "PASS")


if __name__ == "__main__":
    unittest.main()
