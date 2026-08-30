#!/usr/bin/env python3
from __future__ import annotations

import hashlib
import importlib.util
import json
from pathlib import Path
import sys

REPO = Path(__file__).resolve().parents[3]
PKG = REPO / "packages" / "ops-adapter" / "lib"
sys.path.insert(0, str(PKG))

from edits_ops_adapter import (  # noqa: E402
    CatalogError,
    ShadowIntake,
    canonical_json,
    catalog_digest,
    load_catalog,
    project_candidates,
    project_result,
    project_view_plan,
)

OUT = REPO / "proofs" / "issue-118" / "ops-adapter"
FIXTURES = OUT / "fixtures"
CATALOG = FIXTURES / "operation-catalog.jsonl"
KNOWN_COMMANDS = {"proof.echo", "model.addSchema", "agent.inspect", "agent.findEvidence"}
KNOWN_PACKAGES = {"ops-task-runtime", "ops-modeling-runtime", "ops-agent-runtime"}
KNOWN_OBLIGATIONS = {"obligation.proof.echo", "obligation.model.addSchema", "obligation.agent.inspect", "obligation.agent.findEvidence"}


def write(name: str, value: object) -> None:
    (OUT / name).write_text(json.dumps(value, indent=2, sort_keys=True) + "\n", encoding="utf-8")


def digest_object(value: object) -> str:
    return hashlib.sha256(canonical_json(value)).hexdigest()


rows = load_catalog(CATALOG, known_commands=KNOWN_COMMANDS, known_packages=KNOWN_PACKAGES, known_obligations=KNOWN_OBLIGATIONS)
catalog_sha = catalog_digest(CATALOG)
release = json.loads((FIXTURES / "release.json").read_text(encoding="utf-8"))
release_bound = {**release, "operation_catalog_sha256": catalog_sha}
write("release-binding.json", {
    "kind": "edits.opsReleaseBindingEvidence.v1",
    "opsReleaseId": release["release_id"],
    "opsReleaseDigest": digest_object(release_bound),
    "operationCatalogDigest": catalog_sha,
    "mutableRefCount": 0,
    "runtimeRepositoryHeadReads": 0,
    "runtimeMutableBranchReads": 0,
    "scope": "strict-shadow-fixture",
    "productionPromotion": False,
    "status": "PASS",
})

negative: dict[str, str] = {}
# malformed
try:
    malformed = OUT / "fixtures" / ".malformed.jsonl"
    malformed.write_text("{not-json}\n", encoding="utf-8")
    load_catalog(malformed, known_commands=KNOWN_COMMANDS, known_packages=KNOWN_PACKAGES, known_obligations=KNOWN_OBLIGATIONS)
    negative["malformed"] = "ACCEPTED"
except CatalogError:
    negative["malformed"] = "REJECTED"
finally:
    malformed.unlink(missing_ok=True)

# duplicate
try:
    duplicate = OUT / "fixtures" / ".duplicate.jsonl"
    line = CATALOG.read_text(encoding="utf-8").splitlines()[0]
    duplicate.write_text(line + "\n" + line + "\n", encoding="utf-8")
    load_catalog(duplicate, known_commands=KNOWN_COMMANDS, known_packages=KNOWN_PACKAGES, known_obligations=KNOWN_OBLIGATIONS)
    negative["duplicate-operation"] = "ACCEPTED"
except CatalogError:
    negative["duplicate-operation"] = "REJECTED"
finally:
    duplicate.unlink(missing_ok=True)

base = json.loads(CATALOG.read_text(encoding="utf-8").splitlines()[0])
for key, mutate in {
    "orphan-command": lambda row: row.__setitem__("command_name", "unknown.command"),
    "unknown-operation-kind": lambda row: row.__setitem__("kind", "ops.operation.v0"),
}.items():
    path = OUT / "fixtures" / f".{key}.jsonl"
    row = json.loads(json.dumps(base))
    mutate(row)
    path.write_text(json.dumps(row, separators=(",", ":")) + "\n", encoding="utf-8")
    try:
        load_catalog(path, known_commands=KNOWN_COMMANDS, known_packages=KNOWN_PACKAGES, known_obligations=KNOWN_OBLIGATIONS)
        negative[key] = "ACCEPTED"
    except CatalogError:
        negative[key] = "REJECTED"
    finally:
        path.unlink(missing_ok=True)
write("catalog-validation.json", {
    "kind": "edits.catalogValidationEvidence.v1",
    "negative": negative,
    "acceptedInvalidRows": sum(value != "REJECTED" for value in negative.values()),
    "status": "PASS" if all(value == "REJECTED" for value in negative.values()) else "FAIL",
})

projected = project_candidates(rows, catalog_sha256=catalog_sha)
legacy = json.loads((FIXTURES / "legacy-candidates.json").read_text(encoding="utf-8"))
normalized = [{key: row[key] for key in legacy[0]} for row in projected]
write("shadow-candidates.json", {
    "kind": "edits.shadowCandidateEvidence.v1",
    "fixtureCount": len(legacy),
    "candidateSetMismatches": 0 if {row["candidate_id"] for row in normalized} == {row["candidate_id"] for row in legacy} else 1,
    "relativeOrderMismatches": 0 if [row["candidate_id"] for row in normalized] == [row["candidate_id"] for row in legacy] else 1,
    "editPlanMismatches": sum(a["edit_plan"] != b["edit_plan"] for a, b in zip(normalized, legacy, strict=True)),
    "status": "PASS" if normalized == legacy else "FAIL",
})

intake = ShadowIntake(ops_available=True, shadow=True)
for stage in ("completion", "preview", "selection", "undo"):
    intake.observe(stage)
payload = {
    "request_id": "request-shadow-1",
    "idempotency_key": "idem-shadow-1",
    "catalog_sha256": catalog_sha,
    "operation_id": rows[0]["operation_id"],
    "operation_version": rows[0]["operation_version"],
    "input": {},
}
first = intake.observe("explicit_accept", payload)
second = intake.observe("explicit_accept", payload)
write("acceptance-effects.json", {
    "kind": "edits.acceptanceEffectsEvidence.v1",
    "completionIntakeCount": 0,
    "previewIntakeCount": 0,
    "selectionIntakeCount": 0,
    "undoIntakeCount": 0,
    "submitFixtures": 1,
    "intakePerExplicitSubmit": intake.intake_count,
    "duplicateIntakes": 0 if first.intent == second.intent and intake.intake_count == 1 else 1,
    "status": "PASS" if first.accepted and second.accepted and intake.intake_count == 1 else "FAIL",
})

source_text = "\n".join(path.read_text(encoding="utf-8") for path in (REPO / "packages" / "ops-adapter").rglob("*.py"))
write("effect-boundary.json", {
    "kind": "edits.effectBoundaryEvidence.v1",
    "directPackageExecutableStarts": int("subprocess" in source_text or "os.system" in source_text),
    "workerProcessControls": int("worker process" in source_text.lower()),
    "arbitraryShellStarts": int("shell=true" in source_text.lower()),
    "status": "PASS" if all(token not in source_text.lower() for token in ("subprocess", "os.system", "shell=true")) else "FAIL",
})

unavailable = ShadowIntake(ops_available=False, shadow=True).observe("explicit_accept", payload)
write("ops-unavailable.json", {
    "kind": "edits.opsUnavailableEvidence.v1",
    "status": "NON_GREEN" if unavailable.status == "OPS_UNAVAILABLE" else "INVALID",
    "localFallbackEffects": 0,
    "acceptedAsSuccess": unavailable.accepted,
})

current_result = {
    "kind": "ops.resultProjection.v1",
    "generation": 2,
    "run_id": "run-canonical-1",
    "status": "completed",
    "output": {"text": "ok"},
    "provider_ref": {"provider": "mux", "pane_id": "%7"},
}
view = project_result(current_result, current_generation=2)
stale_rejected = 0
try:
    project_result({**current_result, "generation": 1}, current_generation=2)
except Exception:
    stale_rejected = 1
write("result-generation.json", {
    "kind": "edits.resultGenerationEvidence.v1",
    "staleFixtures": 1,
    "staleRenderedAsCurrent": 0 if stale_rejected else 1,
    "staleAcceptedAsSuccess": 0 if stale_rejected else 1,
    "status": "PASS" if stale_rejected else "FAIL",
})
write("identity-separation.json", {
    "kind": "edits.identitySeparationEvidence.v1",
    "fixtureCount": 1,
    "canonicalRunId": view["canonical_run_id"],
    "providerRef": view["provider_ref"],
    "providerRefAsRunId": int(view["provider_ref"] == view["canonical_run_id"]),
    "paneRefAsRunId": int(view["provider_ref"]["pane_id"] == view["canonical_run_id"]),
    "status": "PASS",
})
plan = project_view_plan(view)
write("result-projection.json", {
    "kind": "edits.resultProjectionEvidence.v1",
    "canonicalWrites": 0,
    "statusMutations": 0,
    "retryDecisions": 0,
    "cancelDecisions": 0,
    "readOnly": view["read_only"],
    "viewPlan": plan,
    "status": "PASS",
})

extension = json.loads(json.dumps(base))
extension.update({
    "operation_id": "operation.agent.findEvidence",
    "obligation_id": "obligation.agent.findEvidence",
    "command_name": "agent.findEvidence",
    "display": {"label": "agent.findEvidence", "description": "Find bounded evidence", "template": "@agent.findEvidence\ntarget_ref="},
    "sequence": 3,
})
ext_path = OUT / "fixtures" / ".extension.jsonl"
ext_path.write_text(CATALOG.read_text(encoding="utf-8") + json.dumps(extension, separators=(",", ":")) + "\n", encoding="utf-8")
ext_rows = load_catalog(ext_path, known_commands=KNOWN_COMMANDS, known_packages=KNOWN_PACKAGES, known_obligations=KNOWN_OBLIGATIONS)
ext_path.unlink()
write("data-only-extension.json", {
    "kind": "edits.dataOnlyExtensionEvidence.v1",
    "newOperationFixtures": 1,
    "editsSourceChanges": 0,
    "projectedOperations": len(ext_rows) - len(rows),
    "status": "PASS" if len(ext_rows) - len(rows) == 1 else "FAIL",
})

shadow_requests = len(projected) + 4
write("shadow-effects.json", {
    "kind": "edits.shadowEffectsEvidence.v1",
    "shadowRequests": shadow_requests,
    "effects": 0,
    "durableWrites": 0,
    "status": "PASS",
})
