#!/usr/bin/env python3
"""Render local projection JSON into a localhost preview artifact.

The preview is local evidence only. It refuses authoritative projections.
"""
from __future__ import annotations

import argparse
import html
import json
from pathlib import Path
from typing import Any


def as_text(value: Any) -> str:
    if value is None:
        return ""
    if isinstance(value, (dict, list)):
        return json.dumps(value, ensure_ascii=False, sort_keys=True, separators=(",", ":"))
    return str(value)


def render_html(projection: dict[str, Any]) -> str:
    if projection.get("authority") is not False:
        raise SystemExit("FAIL: localhost preview accepts only authority=false local projections")

    target_ref = projection.get("targetRef") or {}
    target_id = target_ref.get("id") if isinstance(target_ref, dict) else ""
    target_kind = target_ref.get("kind") if isinstance(target_ref, dict) else ""
    projection_json = json.dumps(projection, ensure_ascii=False, sort_keys=True, indent=2)

    def esc(value: Any) -> str:
        return html.escape(as_text(value), quote=True)

    return f"""<!doctype html>
<html lang="en">
<head>
  <meta charset="utf-8">
  <meta name="edits-local-preview-authority" content="false">
  <meta name="edits-local-projection-digest" content="{esc(projection.get('digest'))}">
  <title>edits local projection preview</title>
</head>
<body data-authority="false" data-projection-digest="{esc(projection.get('digest'))}">
  <main>
    <h1>edits local projection preview</h1>
    <p data-testid="authority">authority: <span id="authority">{esc(projection.get('authority'))}</span></p>
    <p data-testid="digest">projection digest: <span id="digest">{esc(projection.get('digest'))}</span></p>
    <p data-testid="latest-queue-id">latest queue id: <span id="latestQueueId">{esc(projection.get('latestQueueId'))}</span></p>
    <p data-testid="target-ref">target: <span id="targetKind">{esc(target_kind)}</span>/<span id="targetId">{esc(target_id)}</span></p>
    <p data-testid="model-operation-count">model operations: <span id="modelOperationCount">{esc(projection.get('modelOperationCount'))}</span></p>
    <p data-testid="agent-task-count">agent tasks: <span id="agentTaskCount">{esc(projection.get('agentTaskCount'))}</span></p>
    <pre id="projectionJson">{esc(projection_json)}</pre>
  </main>
  <script>
    async function refreshProjection() {{
      const response = await fetch('current-projection.json?ts=' + Date.now(), {{ cache: 'no-store' }});
      const projection = await response.json();
      if (projection.authority !== false) {{
        throw new Error('local preview refuses authoritative projection');
      }}
      document.body.dataset.projectionDigest = projection.digest || '';
      document.getElementById('authority').textContent = String(projection.authority);
      document.getElementById('digest').textContent = projection.digest || '';
      document.getElementById('latestQueueId').textContent = projection.latestQueueId || '';
      document.getElementById('targetKind').textContent = (projection.targetRef && projection.targetRef.kind) || '';
      document.getElementById('targetId').textContent = (projection.targetRef && projection.targetRef.id) || '';
      document.getElementById('modelOperationCount').textContent = String(projection.modelOperationCount || 0);
      document.getElementById('agentTaskCount').textContent = String(projection.agentTaskCount || 0);
      document.getElementById('projectionJson').textContent = JSON.stringify(projection, null, 2);
    }}
    setInterval(refreshProjection, 500);
  </script>
</body>
</html>
"""


def main() -> int:
    parser = argparse.ArgumentParser(description="render local projection preview")
    parser.add_argument("projection_json")
    parser.add_argument("--out", required=True)
    args = parser.parse_args()

    projection_path = Path(args.projection_json)
    out_path = Path(args.out)
    projection = json.loads(projection_path.read_text(encoding="utf-8"))
    if not isinstance(projection, dict):
        raise SystemExit("FAIL: projection must be a JSON object")

    out_path.parent.mkdir(parents=True, exist_ok=True)
    out_path.write_text(render_html(projection), encoding="utf-8")
    (out_path.parent / "current-projection.json").write_text(
        json.dumps(projection, ensure_ascii=False, indent=2, sort_keys=True) + "\n",
        encoding="utf-8",
    )
    print(json.dumps({
        "status": "PASS",
        "html": str(out_path),
        "projectionDigest": projection.get("digest"),
        "authority": projection.get("authority"),
    }, separators=(",", ":")))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
