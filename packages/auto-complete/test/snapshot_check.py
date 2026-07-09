#!/usr/bin/env python3
from __future__ import annotations

import difflib
import json
import subprocess
import sys
from pathlib import Path
from typing import Any

ROOT = Path(__file__).resolve().parents[1]
SNAPSHOT = ROOT / "test/snapshots/candidate_lsp_outputs.json"
DOC_HEADER = "houjinScore houjinRepository houjinbaikyakuPlan hogeBufferOnly"


def frame(payload: dict[str, Any]) -> bytes:
    body = json.dumps(payload, ensure_ascii=False, separators=(",", ":")).encode("utf-8")
    return b"Content-Length: " + str(len(body)).encode("ascii") + b"\r\n\r\n" + body


def read_frame(stdout) -> dict[str, Any]:
    headers: dict[str, str] = {}
    while True:
        line = stdout.readline()
        if not line:
            raise RuntimeError("server closed while reading headers")
        if line in (b"\r\n", b"\n"):
            break
        name, value = line.decode("ascii").split(":", 1)
        headers[name.lower()] = value.strip()
    return json.loads(stdout.read(int(headers["content-length"])).decode("utf-8"))


def simplify(items: list[dict[str, Any]]) -> list[dict[str, Any]]:
    out = []
    for item in items[:5]:
        data = item.get("data") or {}
        out.append({
            "label": item.get("label"),
            "source": data.get("source"),
            "rank": data.get("rank"),
            "score": data.get("score"),
            "filterText": item.get("filterText"),
            "sortText": item.get("sortText"),
            "textEdit": item.get("textEdit"),
        })
    return out


def collect(command: list[str], prefixes: list[str], line: int) -> dict[str, list[dict[str, Any]]]:
    proc = subprocess.Popen(command, cwd=ROOT, stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    assert proc.stdin is not None
    assert proc.stdout is not None
    try:
        proc.stdin.write(frame({"jsonrpc": "2.0", "id": 1, "method": "initialize", "params": {}}))
        responses: dict[str, list[dict[str, Any]]] = {}
        request_id = 2
        _ = read_frame(proc.stdout)
        for prefix in prefixes:
            uri = f"file:///snapshot-{prefix}.txt"
            text = f"{DOC_HEADER}\n{prefix}" if line == 1 else prefix
            proc.stdin.write(frame({
                "jsonrpc": "2.0",
                "method": "textDocument/didOpen",
                "params": {"textDocument": {"uri": uri, "text": text}},
            }))
            proc.stdin.write(frame({
                "jsonrpc": "2.0",
                "id": request_id,
                "method": "textDocument/completion",
                "params": {"textDocument": {"uri": uri}, "position": {"line": line, "character": len(prefix)}},
            }))
            proc.stdin.flush()
            completion = read_frame(proc.stdout)
            responses[prefix] = simplify(completion.get("result") or [])
            request_id += 1
        proc.stdin.write(frame({"jsonrpc": "2.0", "method": "exit"}))
        proc.stdin.flush()
        return responses
    finally:
        try:
            proc.stdin.close()
        except Exception:
            pass
        try:
            proc.wait(timeout=5)
        except subprocess.TimeoutExpired:
            proc.kill()
        err = proc.stderr.read().decode("utf-8", "replace") if proc.stderr else ""
        if proc.returncode not in (0, None):
            sys.stderr.write(err)


def main() -> int:
    actual = {
        "schema": "jpcmp_candidate_lsp_snapshot.v1",
        "default": collect(["go", "run", "./cmd/jpcmp-lsp", "--dict", "dict/domain.jsonl"], ["houji", "houjin", "houjinb", "houjinScore"], 1),
        "hq": collect(["go", "run", "./cmd/jpcmp-lsp", "--dict", "dict/domain.jsonl", "--hq-source", "test/fixtures/hq.source.jsonl"], ["model"], 0),
    }
    expected = json.loads(SNAPSHOT.read_text(encoding="utf-8"))
    if actual != expected:
        a = json.dumps(actual, ensure_ascii=False, indent=2, sort_keys=True).splitlines()
        e = json.dumps(expected, ensure_ascii=False, indent=2, sort_keys=True).splitlines()
        diff = "\n".join(difflib.unified_diff(e, a, fromfile="expected", tofile="actual", lineterm=""))
        raise SystemExit("[snapshot-check] mismatch\n" + diff)
    print("[snapshot-check] PASS")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
