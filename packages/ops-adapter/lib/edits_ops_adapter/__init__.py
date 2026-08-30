"""Pure adapters between the edits console and released ops contracts."""

from .catalog import CatalogError, canonical_json, catalog_digest, load_catalog, project_candidates
from .intake import IntakeResult, ShadowIntake
from .results import ProjectionError, project_result
from .view_plan import project_view_plan

__all__ = [
    "CatalogError",
    "IntakeResult",
    "ProjectionError",
    "ShadowIntake",
    "canonical_json",
    "catalog_digest",
    "load_catalog",
    "project_candidates",
    "project_result",
    "project_view_plan",
]
