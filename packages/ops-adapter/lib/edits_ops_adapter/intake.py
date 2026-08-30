from __future__ import annotations

from dataclasses import dataclass
from typing import Any


@dataclass(frozen=True)
class IntakeResult:
    accepted: bool
    status: str
    intent: dict[str, Any] | None


class ShadowIntake:
    """In-memory proof adapter; it never executes an operation."""

    def __init__(self, *, ops_available: bool, shadow: bool = True) -> None:
        self.ops_available = ops_available
        self.shadow = shadow
        self._by_key: dict[str, dict[str, Any]] = {}

    @property
    def intake_count(self) -> int:
        return len(self._by_key)

    def observe(self, stage: str, payload: dict[str, Any] | None = None) -> IntakeResult:
        if stage != "explicit_accept":
            return IntakeResult(False, "VIEW_ONLY", None)
        if not self.ops_available:
            return IntakeResult(False, "OPS_UNAVAILABLE", None)
        value = payload or {}
        key = value.get("idempotency_key")
        if not isinstance(key, str) or not key:
            return IntakeResult(False, "INVALID_IDEMPOTENCY_KEY", None)
        existing = self._by_key.get(key)
        if existing is not None:
            return IntakeResult(True, "ALREADY_ACCEPTED", existing)
        required = ("request_id", "catalog_sha256", "operation_id", "operation_version", "input")
        if any(name not in value for name in required):
            return IntakeResult(False, "INVALID_ACCEPTANCE", None)
        intent = {
            "kind": "ops.intent.submit.v1",
            "request_id": value["request_id"],
            "idempotency_key": key,
            "catalog_sha256": value["catalog_sha256"],
            "operation_id": value["operation_id"],
            "operation_version": value["operation_version"],
            "input": value["input"],
            "shadow": self.shadow,
            "authority": False,
        }
        self._by_key[key] = intent
        return IntakeResult(True, "SHADOW_ACCEPTED" if self.shadow else "ACCEPTED", intent)
