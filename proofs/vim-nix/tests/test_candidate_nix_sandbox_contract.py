from __future__ import annotations

import os
from pathlib import Path


REPO = Path(os.environ.get("EDITS_REPO", Path(__file__).resolve().parents[3])).resolve()


def oci_conversion_source() -> str:
    source = (REPO / "proofs" / "vim-nix" / "flake.parts" / "01.nix").read_text(encoding="utf-8")
    return source.split("interactiveOciImage =", 1)[1].split("interactiveImageRef =", 1)[0]


def test_oci_conversion_uses_the_nix_sandbox_tempdir() -> None:
    conversion = oci_conversion_source()

    assert '--tmpdir "$TMPDIR"' in conversion
    assert "/var/tmp" not in conversion


def test_oci_archive_is_repacked_deterministically() -> None:
    conversion = oci_conversion_source()

    assert "nativeBuildInputs = [ pkgs.gnutar pkgs.skopeo ];" in conversion
    assert '"oci:$layout:${interactiveTag}"' in conversion
    assert '"oci-archive:$out:roccho/edits:${interactiveTag}"' not in conversion
    for argument in (
        "--sort=name",
        "--mtime=@1",
        "--owner=0",
        "--group=0",
        "--numeric-owner",
        "--format=ustar",
    ):
        assert argument in conversion
    assert 'LC_ALL=C ${pkgs.gnutar}/bin/tar' in conversion
    assert '-C "$layout"' in conversion
    assert "oci-layout index.json blobs" in conversion
