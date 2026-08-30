from __future__ import annotations

from copy import deepcopy
from typing import Any


class ProjectionError(ValueError):
    pass


def project_result(row: dict[str, Any], *, current_generation: int) -> dict[str, Any]:
    original = deepcopy(row)
    required = {"kind", "generation", "run_id", "status", "output", "provider_ref"}
    if set(row) != required or row.get("kind") != "ops.resultProjection.v1":
        raise ProjectionError("result-contract")
    if row["generation"] != current_generation:
        raise ProjectionError("stale-result-generation")
    if not isinstance(row["run_id"], str) or not row["run_id"]:
        raise ProjectionError("run-id")
    provider_ref = row["provider_ref"]
    if provider_ref is not None and not isinstance(provider_ref, dict):
        raise ProjectionError("provider-ref")
    projected = {
        "kind": "edits.resultView.v1",
        "generation": row["generation"],
        "canonical_run_id": row["run_id"],
        "status": row["status"],
        "output": row["output"],
        "provider_ref": deepcopy(provider_ref),
        "read_only": True,
        "authority": False,
    }
    if row != original:
        raise ProjectionError("input-mutated")
    return projected
