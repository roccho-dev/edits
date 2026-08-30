from __future__ import annotations

from typing import Any


def project_view_plan(result_view: dict[str, Any]) -> dict[str, Any]:
    if result_view.get("kind") != "edits.resultView.v1" or result_view.get("read_only") is not True:
        raise ValueError("read-only-result-view-required")
    return {
        "kind": "edits.muxViewPlan.v1",
        "canonical_run_id": result_view["canonical_run_id"],
        "provider_ref": result_view.get("provider_ref"),
        "operations": ["focus", "read", "snapshot", "close"],
        "input_allowed": False,
        "cancel_on_close": False,
        "authority": False,
    }
