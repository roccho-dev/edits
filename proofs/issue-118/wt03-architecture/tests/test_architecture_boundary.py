from __future__ import annotations

import json
from pathlib import Path
import re
import unittest

REPO = Path(__file__).resolve().parents[4]
EVIDENCE = REPO / "proofs" / "issue-118" / "architecture"
PRODUCTION_ROOTS = [REPO / "cmd", REPO / "packages", REPO / "adapters", REPO / "README.md", REPO / "docs"]


def load(path: Path):
    if not path.is_file():
        raise AssertionError(f"missing architecture evidence: {path.relative_to(REPO)}")
    return json.loads(path.read_text(encoding="utf-8"))


def files(root: Path):
    if root.is_file():
        yield root
    elif root.is_dir():
        for path in root.rglob("*"):
            if path.is_file() and ".git" not in path.parts and "__pycache__" not in path.parts:
                yield path


def source_text(paths) -> str:
    chunks = []
    for root in paths:
        for path in files(root):
            try:
                chunks.append(path.read_text(encoding="utf-8"))
            except UnicodeDecodeError:
                pass
    return "\n".join(chunks)


class TestArchitectureBoundary(unittest.TestCase):
    def test_provider_independent_core_exists(self) -> None:
        root = REPO / "packages" / "core"
        self.assertTrue(root.is_dir(), root)
        self.assertTrue((root / "ports").is_dir())
        self.assertTrue((root / "README.md").is_file())

    def test_client_service_mux_and_ops_ports_exist(self) -> None:
        expected = [
            REPO / "packages" / "client" / "port",
            REPO / "packages" / "service" / "port",
            REPO / "packages" / "mux" / "port",
            REPO / "packages" / "ops-adapter" / "port",
        ]
        self.assertTrue(all(path.is_dir() for path in expected), expected)

    def test_edits_worker_is_absent_from_production_paths(self) -> None:
        receipt = load(EVIDENCE / "forbidden-authority.json")
        production = source_text(PRODUCTION_ROOTS).lower()
        self.assertNotIn("edits-worker", production)
        self.assertEqual(receipt.get("editsWorkerCount"), 0)
        self.assertEqual(receipt.get("status"), "PASS")

    def test_core_contains_no_provider_specific_semantic_branch(self) -> None:
        receipt = load(EVIDENCE / "core-provider-guard.json")
        core = source_text([REPO / "packages" / "core"]).lower()
        for token in ("vim", "herdr", "hq", "codex", "claude", "gosh", "envctl"):
            self.assertNotRegex(core, rf"\b{re.escape(token)}\b")
        self.assertEqual(receipt.get("providerSemanticBranches"), 0)
        self.assertEqual(receipt.get("status"), "PASS")

    def test_provider_adapters_are_exact_references_not_source_copies(self) -> None:
        data = load(EVIDENCE / "provider-bindings.json")
        expected = {"vim", "hq", "herdr"}
        providers = data.get("providers", {})
        self.assertEqual(set(providers), expected)
        for provider in expected:
            row = providers[provider]
            self.assertEqual(row.get("sourceMode"), "exact-reference")
            self.assertEqual(row.get("vendoredSourceFiles"), 0)
            self.assertEqual(len(row.get("sourceRevision", "")), 40)
            self.assertEqual(len(row.get("artifactSha256", "")), 64)

    def test_dependency_graph_contains_only_allowed_edges(self) -> None:
        data = load(EVIDENCE / "dependency-graph.json")
        allowed = {
            ("client", "core"),
            ("service", "core"),
            ("service", "ops-adapter"),
            ("mux", "core"),
            ("provider-vim", "client"),
            ("provider-hq", "service"),
            ("provider-herdr", "mux"),
        }
        edges = {(row["from"], row["to"]) for row in data.get("edges", [])}
        self.assertTrue(edges)
        self.assertTrue(edges.issubset(allowed), edges - allowed)
        self.assertEqual(data.get("unknownEdges"), 0)

    def test_ops_internal_import_count_is_zero(self) -> None:
        data = load(EVIDENCE / "forbidden-imports.json")
        self.assertEqual(data.get("opsInternalImports"), 0)
        self.assertEqual(data.get("opsRuntimeSourceCopies"), 0)
        self.assertEqual(data.get("status"), "PASS")

    def test_direct_business_effect_count_is_zero(self) -> None:
        data = load(EVIDENCE / "forbidden-authority.json")
        self.assertEqual(data.get("directBusinessEffects"), 0)
        self.assertEqual(data.get("arbitraryShellInvocations"), 0)

    def test_retry_and_cancel_policy_count_is_zero(self) -> None:
        data = load(EVIDENCE / "forbidden-authority.json")
        self.assertEqual(data.get("retryPolicyDefinitions"), 0)
        self.assertEqual(data.get("cancelPolicyDefinitions"), 0)

    def test_canonical_result_writer_count_is_zero(self) -> None:
        data = load(EVIDENCE / "forbidden-authority.json")
        self.assertEqual(data.get("canonicalResultWriters"), 0)
        self.assertEqual(data.get("canonicalReceiptWriters"), 0)

    def test_local_worker_remains_legacy_proof_only(self) -> None:
        data = load(EVIDENCE / "legacy-worker-boundary.json")
        self.assertEqual(data.get("path"), "packages/hq-local-worker")
        self.assertEqual(data.get("canonicalRuntime"), False)
        self.assertEqual(data.get("proofOnly"), True)
        self.assertEqual(data.get("status"), "PASS")

    def test_jsonl_shell_program_count_is_zero(self) -> None:
        data = load(EVIDENCE / "jsonl-language-guard.json")
        self.assertEqual(data.get("shellCommandStrings"), 0)
        self.assertEqual(data.get("shellExpansionForms"), 0)
        self.assertEqual(data.get("status"), "PASS")

    def test_jsonl_workflow_graph_count_is_zero(self) -> None:
        data = load(EVIDENCE / "jsonl-language-guard.json")
        self.assertEqual(data.get("workflowBranches"), 0)
        self.assertEqual(data.get("workflowLoops"), 0)
        self.assertEqual(data.get("embeddedPrograms"), 0)

    def test_dependency_graph_is_acyclic(self) -> None:
        data = load(EVIDENCE / "dependency-graph.json")
        self.assertEqual(data.get("cycleCount"), 0)
        self.assertEqual(data.get("status"), "PASS")


if __name__ == "__main__":
    unittest.main()
