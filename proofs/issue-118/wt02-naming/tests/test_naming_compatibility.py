from __future__ import annotations

import json
from pathlib import Path
import os
import re
import stat
import unittest

REPO = Path(__file__).resolve().parents[4]
PLUGIN = REPO / "packages" / "hq-vim" / "plugin" / "hq.vim"
AUTOLOAD = REPO / "packages" / "hq-vim" / "autoload" / "hq.vim"
EVIDENCE = REPO / "proofs" / "issue-118" / "naming-compatibility"
ROLES = ("edits-client", "edits-service", "edits-mux")
LEGACY = {
    "command:HqStart",
    "command:HqSubmit",
    "command:HqDoctor",
    "global:g:hq_bin",
    "global:g:hq_profile",
    "global:g:hq_server_name",
    "entrypoint:edits",
}


def text(path: Path) -> str:
    if not path.is_file():
        raise AssertionError(f"required source is absent: {path.relative_to(REPO)}")
    return path.read_text(encoding="utf-8")


def load(path: Path):
    if not path.is_file():
        raise AssertionError(f"required naming evidence is absent: {path.relative_to(REPO)}")
    return json.loads(path.read_text(encoding="utf-8"))


class TestNamingCompatibility(unittest.TestCase):
    def test_product_role_entrypoints_exist_and_are_executable(self) -> None:
        for role in ROLES:
            path = REPO / "cmd" / role / role
            self.assertTrue(path.is_file(), path)
            self.assertTrue(path.stat().st_mode & stat.S_IXUSR, path)

    def test_edits_start_and_hq_start_share_one_implementation(self) -> None:
        source = text(PLUGIN)
        self.assertRegex(source, r"command!\s+-nargs=\?\s+EditsStart\s+g:EditsVimStart")
        self.assertRegex(source, r"command!\s+-nargs=\?\s+HqStart\s+g:EditsVimStart")

    def test_edits_submit_and_hq_submit_share_one_implementation(self) -> None:
        source = text(PLUGIN)
        self.assertRegex(source, r"command!\s+EditsSubmit\s+g:EditsVimSubmit")
        self.assertRegex(source, r"command!\s+HqSubmit\s+g:EditsVimSubmit")

    def test_edits_doctor_and_hq_doctor_share_one_implementation(self) -> None:
        source = text(PLUGIN)
        self.assertRegex(source, r"command!\s+EditsDoctor\s+g:EditsVimDoctor")
        self.assertRegex(source, r"command!\s+HqDoctor\s+g:EditsVimDoctor")

    def test_new_globals_are_preferred_and_legacy_globals_remain_supported(self) -> None:
        source = text(AUTOLOAD)
        self.assertIn("edits_service_bin", source)
        self.assertIn("hq_bin", source)
        self.assertIn("edits_profile", source)
        self.assertIn("hq_profile", source)
        self.assertIn("edits_server_name", source)
        self.assertIn("hq_server_name", source)

    def test_configuration_precedence_is_explicit_and_deterministic(self) -> None:
        data = load(EVIDENCE / "configuration-precedence.json")
        self.assertEqual(data.get("serviceBinary"), ["g:edits_service_bin", "g:hq_bin"])
        self.assertEqual(data.get("profile"), ["g:edits_profile", "g:hq_profile", "local"])
        self.assertEqual(data.get("serverName"), ["g:edits_server_name", "g:hq_server_name", "edits-service"])
        self.assertEqual(data.get("status"), "PASS")

    def test_edits_remains_the_normal_product_entrypoint(self) -> None:
        data = load(EVIDENCE / "entrypoint-readback.json")
        self.assertEqual(data.get("normalEntrypoint"), "/bin/edits")
        self.assertEqual(data.get("starts"), ["edits-mux", "edits-client", "edits-service"])
        self.assertEqual(data.get("status"), "PASS")

    def test_persisted_hq_wire_kinds_are_not_bulk_renamed(self) -> None:
        data = load(EVIDENCE / "wire-compatibility.json")
        self.assertEqual(data.get("readKinds"), ["hq.*", "edits.*"])
        self.assertEqual(data.get("writeKinds"), ["hq.*"])
        self.assertEqual(data.get("bulkRewriteCount"), 0)
        self.assertEqual(data.get("status"), "PASS")

    def test_help_distinguishes_product_roles_from_providers(self) -> None:
        data = load(EVIDENCE / "help-readback.json")
        roles = data.get("roles", {})
        self.assertEqual(roles.get("edits-client", {}).get("provider"), "vim")
        self.assertEqual(roles.get("edits-service", {}).get("provider"), "hq")
        self.assertEqual(roles.get("edits-mux", {}).get("provider"), "herdr")
        self.assertEqual(data.get("status"), "PASS")

    def test_old_and_new_aliases_have_semantically_equal_e2e_receipts(self) -> None:
        data = load(EVIDENCE / "alias-e2e.json")
        for operation in ("start", "submit", "doctor"):
            pair = data.get(operation, {})
            self.assertEqual(pair.get("legacySemanticDigest"), pair.get("newSemanticDigest"), operation)
            self.assertEqual(pair.get("durableWriteDelta"), 0 if operation != "submit" else 1)
        self.assertEqual(data.get("status"), "PASS")

    def test_every_golden_legacy_surface_has_a_compatibility_mapping(self) -> None:
        data = load(EVIDENCE / "compatibility-map.json")
        mapping = data.get("mapping", {})
        self.assertTrue(LEGACY.issubset(mapping))
        self.assertTrue(all(mapping[item].get("status") == "PASS" for item in LEGACY))

    def test_no_required_journey_is_new_name_only(self) -> None:
        data = load(EVIDENCE / "journey-name-parity.json")
        required = data.get("journeys", [])
        self.assertGreater(len(required), 0)
        self.assertTrue(all(row.get("legacyPass") is True for row in required))
        self.assertTrue(all(row.get("newPass") is True for row in required))
        self.assertTrue(all(row.get("semanticEqual") is True for row in required))
        self.assertEqual(data.get("newNameOnlyRequiredJourneys"), 0)


if __name__ == "__main__":
    unittest.main()
