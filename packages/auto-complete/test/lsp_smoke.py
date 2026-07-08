#!/usr/bin/env python3
from __future__ import annotations

import json
import subprocess
import sys
from pathlib import Path
from typing import Any

ROOT = Path(__file__).resolve().parents[1]


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
    length = int(headers["content-length"])
    body = stdout.read(length)
    return json.loads(body.decode("utf-8"))


def main() -> int:
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
            "params": {
                "textDocument": {
                    "uri": "file:///golden.txt",
                    "text": "houjinScore houjinRepository houjinbaikyakuPlan hogeBufferOnly\nhouji",
                }
            },
        }))
        proc.stdin.write(frame({
            "jsonrpc": "2.0",
            "id": 2,
            "method": "textDocument/completion",
            "params": {"textDocument": {"uri": "file:///golden.txt"}, "position": {"line": 1, "character": 5}},
        }))
        proc.stdin.flush()

        init = read_frame(proc.stdout)
        if init.get("id") != 1:
            raise AssertionError(f"bad initialize response: {init}")
        completion = read_frame(proc.stdout)
        items = completion.get("result") or []
        labels = [item.get("label") for item in items]
        for label in ["houjinScore", "法人", "法人売却"]:
            if label not in labels:
                raise AssertionError(f"missing {label}: {labels}")
        if labels[0] != "houjinScore":
            raise AssertionError(f"top candidate mismatch: {labels[:5]}")
        target = next(item for item in items if item.get("label") == "法人売却")
        text_edit = target.get("textEdit") or {}
        rng = text_edit.get("range") or {}
        if text_edit.get("newText") != "法人売却":
            raise AssertionError(f"bad newText: {text_edit}")
        if rng.get("start") != {"line": 1, "character": 0} or rng.get("end") != {"line": 1, "character": 5}:
            raise AssertionError(f"bad range: {rng}")
        if target.get("filterText") != "houji":
            raise AssertionError(f"bad filterText: {target}")
        proc.stdin.write(frame({"jsonrpc": "2.0", "method": "exit"}))
        proc.stdin.flush()
        print("[lsp-smoke] PASS")
        return 0
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


if __name__ == "__main__":
    raise SystemExit(main())
