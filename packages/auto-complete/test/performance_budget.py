#!/usr/bin/env python3
from __future__ import annotations

import subprocess
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
BUDGET_MS = 15000

GO_PROG = r'''
package main

import (
    "fmt"
    "os"
    "time"

    domainjsonl "github.com/roccho-dev/edits/packages/auto-complete/adapters/source/domain-jsonl"
    "github.com/roccho-dev/edits/packages/auto-complete/lib/jpcmp/core"
)

func main() {
    if len(os.Args) != 2 {
        panic("fixture path required")
    }
    provider := domainjsonl.New([]string{os.Args[1]})
    if len(provider.Errors) != 0 {
        panic(fmt.Sprintf("fixture errors: %v", provider.Errors))
    }
    engine := core.NewEngine(core.DefaultConfig(), provider)
    prefixes := []string{"hou", "houjin", "houjin1", "houjin12"}
    start := time.Now()
    checks := 0
    for i := 0; i < 80; i++ {
        for _, prefix := range prefixes {
            _, candidates := engine.Complete(prefix, 0, len(prefix))
            if len(candidates) == 0 {
                panic("no candidates for " + prefix)
            }
            checks++
        }
    }
    elapsed := time.Since(start)
    fmt.Printf("checks=%d elapsed_ms=%d\n", checks, elapsed.Milliseconds())
    if elapsed > 15000*time.Millisecond {
        panic(fmt.Sprintf("performance budget exceeded: %s", elapsed))
    }
}
'''


def main() -> int:
    with tempfile.TemporaryDirectory() as tmp:
        tmp_path = Path(tmp)
        fixture = tmp_path / "large-domain.jsonl"
        rows = []
        for i in range(2500):
            rows.append(
                '{{"reading":"ほうじん{0}","romaji":"houjin{0:04d}","word":"houjinCandidate{0:04d}","rank":{1},"source":"jp-dict"}}'.format(
                    i, 1 + (i % 90)
                )
            )
        fixture.write_text("\n".join(rows) + "\n", encoding="utf-8")
        prog = ROOT / "tmp_perf_budget_check.go"
        prog.write_text(GO_PROG, encoding="utf-8")
        try:
            result = subprocess.run(
                ["go", "run", str(prog.name), str(fixture)],
                cwd=ROOT,
                text=True,
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                check=False,
            )
        finally:
            try:
                prog.unlink()
            except FileNotFoundError:
                pass
        if result.returncode != 0:
            raise SystemExit(result.stdout + result.stderr)
        print(result.stdout.strip())
        print(f"[performance-budget] PASS budget_ms={BUDGET_MS}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
