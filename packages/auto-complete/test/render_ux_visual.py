#!/usr/bin/env python3
from __future__ import annotations

import html
import json
import subprocess
from pathlib import Path
from typing import Any

ROOT = Path(__file__).resolve().parents[1]
ARTIFACT_DIR = ROOT / "artifacts"
ARTIFACT_DIR.mkdir(parents=True, exist_ok=True)

RAW = "houji"
PREEDIT = "ほうじ"
DOC_TEXT = "houjinScore houjinRepository houjinbaikyakuPlan hogeBufferOnly\nhouji"
URI = "file:///ux-golden.txt"


def frame(payload: dict[str, Any]) -> bytes:
    body = json.dumps(payload, ensure_ascii=False, separators=(",", ":")).encode("utf-8")
    return b"Content-Length: " + str(len(body)).encode("ascii") + b"\r\n\r\n" + body


def read_frame(stream) -> dict[str, Any]:
    headers: dict[str, str] = {}
    while True:
        line = stream.readline()
        if not line:
            raise RuntimeError("server closed while reading headers")
        if line in (b"\r\n", b"\n"):
            break
        key, value = line.decode("ascii").split(":", 1)
        headers[key.lower()] = value.strip()
    body = stream.read(int(headers["content-length"]))
    return json.loads(body.decode("utf-8"))


def lsp_items() -> list[dict[str, Any]]:
    proc = subprocess.Popen(
        ["go", "run", "./cmd/jpcmp-lsp", "--dict", "dict/domain.jsonl"],
        cwd=ROOT,
        stdin=subprocess.PIPE,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
    )
    assert proc.stdin is not None
    assert proc.stdout is not None
    try:
        proc.stdin.write(frame({"jsonrpc": "2.0", "id": 1, "method": "initialize", "params": {}}))
        proc.stdin.write(frame({
            "jsonrpc": "2.0",
            "method": "textDocument/didOpen",
            "params": {"textDocument": {"uri": URI, "text": DOC_TEXT}},
        }))
        proc.stdin.write(frame({
            "jsonrpc": "2.0",
            "id": 2,
            "method": "textDocument/completion",
            "params": {"textDocument": {"uri": URI}, "position": {"line": 1, "character": len(RAW)}},
        }))
        proc.stdin.flush()
        _ = read_frame(proc.stdout)
        completion = read_frame(proc.stdout)
        proc.stdin.write(frame({"jsonrpc": "2.0", "method": "exit"}))
        proc.stdin.flush()
        return completion.get("result") or []
    finally:
        try:
            proc.stdin.close()
        except Exception:
            pass
        try:
            proc.wait(timeout=5)
        except subprocess.TimeoutExpired:
            proc.kill()


def render_svg(items: list[dict[str, Any]]) -> str:
    rows = []
    for idx, item in enumerate(items[:8], start=1):
        label = html.escape(str(item.get("label", "")))
        source = html.escape(str((item.get("data") or {}).get("source", "")))
        rows.append(f'<text x="42" y="{210 + idx * 36}" class="row">{idx}. {label} [{source}]</text>')
    return f'''<svg xmlns="http://www.w3.org/2000/svg" width="960" height="560" viewBox="0 0 960 560" role="img" aria-label="auto-complete UX golden visual evidence">
  <style>
    .bg {{ fill: #101418; }}
    .panel {{ fill: #171c22; stroke: #39424e; stroke-width: 2; }}
    .title {{ fill: #e6edf3; font-family: ui-monospace, SFMono-Regular, Consolas, monospace; font-size: 24px; font-weight: 700; }}
    .label {{ fill: #8b949e; font-family: ui-monospace, SFMono-Regular, Consolas, monospace; font-size: 18px; }}
    .value {{ fill: #e6edf3; font-family: ui-monospace, SFMono-Regular, Consolas, monospace; font-size: 24px; }}
    .row {{ fill: #e6edf3; font-family: ui-monospace, SFMono-Regular, Consolas, monospace; font-size: 22px; }}
    .accent {{ fill: #f2cc60; }}
  </style>
  <rect class="bg" width="960" height="560" />
  <rect class="panel" x="24" y="24" width="912" height="512" rx="16" />
  <text x="42" y="66" class="title">auto-complete UX golden evidence</text>
  <text x="42" y="112" class="label">raw buffer</text>
  <text x="210" y="112" class="value">{html.escape(RAW)}</text>
  <text x="42" y="154" class="label">preedit</text>
  <text x="210" y="154" class="value">{html.escape(PREEDIT)}</text>
  <text x="42" y="196" class="label">completion candidates</text>
  {''.join(rows)}
  <text x="42" y="510" class="label">source: Go jpcmp-lsp JSON-RPC response in CI</text>
</svg>
'''


def main() -> int:
    items = lsp_items()
    labels = [item.get("label") for item in items]
    required = ["houjinScore", "法人", "法人売却"]
    missing = [label for label in required if label not in labels]
    status = "PASS" if not missing and labels[:1] == ["houjinScore"] else "FAIL"
    payload = {
        "schema": "jpcmp_ux_visual_evidence.v1",
        "status": status,
        "raw_buffer": RAW,
        "preedit": PREEDIT,
        "labels": labels,
        "required": required,
        "missing": missing,
        "source": "go-jpcmp-lsp-jsonrpc",
    }
    (ARTIFACT_DIR / "ux-golden.json").write_text(json.dumps(payload, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    (ARTIFACT_DIR / "ux-golden.svg").write_text(render_svg(items), encoding="utf-8")
    (ARTIFACT_DIR / "ux-golden.md").write_text(
        "# auto-complete UX golden evidence\n\n"
        f"- status: `{status}`\n"
        f"- raw buffer: `{RAW}`\n"
        f"- preedit: `{PREEDIT}`\n"
        f"- candidates: {', '.join(str(x) for x in labels[:8])}\n"
        "\nThis is deterministic visual evidence rendered from the Go LSP JSON-RPC response in CI.\n",
        encoding="utf-8",
    )
    print(f"[ux-visual] {status}")
    return 0 if status == "PASS" else 1


if __name__ == "__main__":
    raise SystemExit(main())
