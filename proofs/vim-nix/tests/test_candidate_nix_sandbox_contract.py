from __future__ import annotations

import os
from pathlib import Path


REPO = Path(os.environ.get("EDITS_REPO", Path(__file__).resolve().parents[3])).resolve()


def test_oci_conversion_uses_the_nix_sandbox_tempdir() -> None:
    source = (REPO / "proofs" / "vim-nix" / "flake.parts" / "01.nix").read_text(encoding="utf-8")
    conversion = source.split("interactiveOciImage =", 1)[1].split("interactiveImageRef =", 1)[0]

    assert '--tmpdir "$TMPDIR"' in conversion
    assert "/var/tmp" not in conversion
