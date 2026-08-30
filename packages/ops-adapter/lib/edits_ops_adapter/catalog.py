from __future__ import annotations

import hashlib
import json
from pathlib import Path
from typing import Any, Iterable

ROW_FIELDS = {
    "kind",
    "operation_id",
    "operation_version",
    "package_id",
    "obligation_id",
    "command_name",
    "display",
    "input_schema",
    "result_schema",
    "effect_class",
    "queue_kind",
    "target",
    "risk",
    "approval",
    "view_policy",
    "authority",
    "sequence",
}


class CatalogError(ValueError):
    """Raised when a catalog cannot be accepted as an exact closed input."""


def canonical_json(value: Any) -> bytes:
    return json.dumps(value, ensure_ascii=False, sort_keys=True, separators=(",", ":")).encode("utf-8")


def catalog_digest(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def _read_jsonl(path: Path) -> list[dict[str, Any]]:
    data = path.read_bytes()
    if data and not data.endswith(b"\n"):
        raise CatalogError("catalog-final-newline-required")
    rows: list[dict[str, Any]] = []
    for number, raw in enumerate(data.splitlines(), start=1):
        if not raw:
            continue
        try:
            row = json.loads(raw)
        except json.JSONDecodeError as exc:
            raise CatalogError(f"catalog-json:{number}:{exc.msg}") from exc
        if not isinstance(row, dict):
            raise CatalogError(f"catalog-object-required:{number}")
        rows.append(row)
    return rows


def _validate_schema(name: str, schema: Any) -> None:
    if not isinstance(schema, dict):
        raise CatalogError(f"{name}-object-required")
    if schema.get("type") != "object":
        raise CatalogError(f"{name}-object-type-required")
    if schema.get("additionalProperties") is not False:
        raise CatalogError(f"{name}-closed-required")
    if not isinstance(schema.get("properties"), dict):
        raise CatalogError(f"{name}-properties-required")


def validate_row(row: dict[str, Any], *, known_commands: set[str], known_packages: set[str], known_obligations: set[str]) -> None:
    if set(row) != ROW_FIELDS:
        missing = sorted(ROW_FIELDS - set(row))
        extra = sorted(set(row) - ROW_FIELDS)
        raise CatalogError(f"catalog-fields:missing={missing}:extra={extra}")
    if row["kind"] != "ops.operation.v1":
        raise CatalogError(f"operation-kind:{row['kind']}")
    for key in ("operation_id", "operation_version", "package_id", "obligation_id", "command_name", "effect_class", "queue_kind", "target", "risk", "approval", "view_policy"):
        if not isinstance(row[key], str) or not row[key].strip():
            raise CatalogError(f"operation-string-required:{key}")
    if row["authority"] is not False:
        raise CatalogError("operation-authority-must-be-false")
    if not isinstance(row["sequence"], int) or row["sequence"] < 0:
        raise CatalogError("operation-sequence")
    if row["command_name"] not in known_commands:
        raise CatalogError(f"orphan-command:{row['command_name']}")
    if row["package_id"] not in known_packages:
        raise CatalogError(f"orphan-package:{row['package_id']}")
    if row["obligation_id"] not in known_obligations:
        raise CatalogError(f"orphan-obligation:{row['obligation_id']}")
    display = row["display"]
    if not isinstance(display, dict) or set(display) != {"label", "description", "template"}:
        raise CatalogError("operation-display-closed")
    if not all(isinstance(display[key], str) and display[key] for key in display):
        raise CatalogError("operation-display-values")
    _validate_schema("input-schema", row["input_schema"])
    _validate_schema("result-schema", row["result_schema"])


def load_catalog(path: Path, *, known_commands: Iterable[str], known_packages: Iterable[str], known_obligations: Iterable[str]) -> list[dict[str, Any]]:
    rows = _read_jsonl(path)
    command_set = set(known_commands)
    package_set = set(known_packages)
    obligation_set = set(known_obligations)
    seen: set[tuple[str, str]] = set()
    for row in rows:
        validate_row(row, known_commands=command_set, known_packages=package_set, known_obligations=obligation_set)
        key = (row["operation_id"], row["operation_version"])
        if key in seen:
            raise CatalogError(f"duplicate-operation:{key[0]}:{key[1]}")
        seen.add(key)
    return sorted(rows, key=lambda row: (row["sequence"], row["operation_id"], row["operation_version"]))


def project_candidates(rows: Iterable[dict[str, Any]], *, catalog_sha256: str) -> list[dict[str, Any]]:
    return [
        {
            "candidate_id": f"{row['operation_id']}@{row['operation_version']}",
            "label": row["display"]["label"],
            "detail": row["display"]["description"],
            "edit_plan": row["display"]["template"],
            "operation_id": row["operation_id"],
            "operation_version": row["operation_version"],
            "catalog_sha256": catalog_sha256,
        }
        for row in rows
    ]
