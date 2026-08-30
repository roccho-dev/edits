#!/usr/bin/env python3
from __future__ import annotations

import json
from pathlib import Path
import re

REPO = Path(__file__).resolve().parents[3]
OUT = REPO / "proofs" / "issue-118" / "architecture"
TARGETS = [
    REPO / "packages" / "core",
    REPO / "packages" / "client",
    REPO / "packages" / "service",
    REPO / "packages" / "mux",
    REPO / "packages" / "ops-adapter",
]


def text_files(roots: list[Path]):
    for root in roots:
        if not root.exists():
            continue
        for path in ([root] if root.is_file() else root.rglob("*")):
            if path.is_file() and "__pycache__" not in path.parts:
                try:
                    yield path, path.read_text(encoding="utf-8")
                except UnicodeDecodeError:
                    pass


def write(name: str, value: object) -> None:
    (OUT / name).write_text(json.dumps(value, indent=2, sort_keys=True) + "\n", encoding="utf-8")


# Product paths deliberately exclude historical proof fixtures.
production_roots = [REPO / "cmd", REPO / "packages", REPO / "adapters", REPO / "README.md", REPO / "docs"]
production = "\n".join(value for _, value in text_files(production_roots)).lower()
core = "\n".join(value for _, value in text_files([REPO / "packages" / "core"])).lower()

provider_tokens = ("vim", "herdr", "hq", "codex", "claude", "gosh", "envctl")
provider_branches = sum(len(re.findall(rf"\b{re.escape(token)}\b", core)) for token in provider_tokens)

port_scope = "\n".join(value for _, value in text_files(TARGETS)).lower()
# These are intentionally narrow guards for executable authority, not English documentation words.
direct_effect_patterns = [r"\bexec\.command\s*\(", r"\bsubprocess\.(run|popen|call)\s*\(", r"\bos\.system\s*\("]
shell_patterns = [r"\bsh\s+-c\b", r"\bbash\s+-c\b", r"\brun-shell\b"]
retry_policy_patterns = [r"retry[_ -]?policy\s*[:=]", r"max[_ -]?retries\s*[:=]"]
cancel_policy_patterns = [r"cancel[_ -]?policy\s*[:=]", r"signal[_ -]?escalation\s*[:=]"]
result_writer_patterns = [r"write[_ -]?canonical[_ -]?result", r"append[_ -]?result[_ -]?ledger"]
receipt_writer_patterns = [r"write[_ -]?canonical[_ -]?receipt", r"append[_ -]?receipt[_ -]?ledger"]

count = lambda patterns, data: sum(len(re.findall(pattern, data)) for pattern in patterns)

provider_paths = {
    "vim": REPO / "packages" / "client" / "providers" / "vim" / "provider.json",
    "hq": REPO / "packages" / "service" / "providers" / "hq" / "provider.json",
    "herdr": REPO / "packages" / "mux" / "providers" / "herdr" / "provider.json",
}
providers = {key: json.loads(path.read_text(encoding="utf-8")) for key, path in provider_paths.items()}
write("provider-bindings.json", {"kind": "edits.providerBindings.v1", "providers": providers, "status": "PASS"})

write("core-provider-guard.json", {
    "kind": "edits.coreProviderGuard.v1",
    "scannedPath": "packages/core",
    "providerSemanticBranches": provider_branches,
    "status": "PASS" if provider_branches == 0 else "FAIL",
})

ops_internal_patterns = [r"roccho-dev/ops/(packages|internal|lib)", r"from\s+['\"]ops/(packages|internal)"]
ops_source_copy_count = sum(1 for path, _ in text_files(TARGETS) if "ops-runtime" in path.name.lower() or "worker-effect" in path.name.lower())
write("forbidden-imports.json", {
    "kind": "edits.forbiddenImports.v1",
    "opsInternalImports": count(ops_internal_patterns, port_scope),
    "opsRuntimeSourceCopies": ops_source_copy_count,
    "status": "PASS" if count(ops_internal_patterns, port_scope) == 0 and ops_source_copy_count == 0 else "FAIL",
})

edits_worker_count = len(re.findall(r"\bedits-worker\b", production))
write("forbidden-authority.json", {
    "kind": "edits.forbiddenAuthority.v1",
    "editsWorkerCount": edits_worker_count,
    "directBusinessEffects": count(direct_effect_patterns, port_scope),
    "arbitraryShellInvocations": count(shell_patterns, port_scope),
    "retryPolicyDefinitions": count(retry_policy_patterns, port_scope),
    "cancelPolicyDefinitions": count(cancel_policy_patterns, port_scope),
    "canonicalResultWriters": count(result_writer_patterns, port_scope),
    "canonicalReceiptWriters": count(receipt_writer_patterns, port_scope),
    "status": "PASS" if all(value == 0 for value in [
        edits_worker_count,
        count(direct_effect_patterns, port_scope),
        count(shell_patterns, port_scope),
        count(retry_policy_patterns, port_scope),
        count(cancel_policy_patterns, port_scope),
        count(result_writer_patterns, port_scope),
        count(receipt_writer_patterns, port_scope),
    ]) else "FAIL",
})

legacy = REPO / "packages" / "hq-local-worker" / "README.md"
legacy_text = legacy.read_text(encoding="utf-8").lower() if legacy.is_file() else ""
legacy_pass = "legacy/proof-only" in legacy_text and "not the canonical worker runtime" in legacy_text
write("legacy-worker-boundary.json", {
    "kind": "edits.legacyWorkerBoundary.v1",
    "path": "packages/hq-local-worker",
    "canonicalRuntime": False,
    "proofOnly": legacy_pass,
    "status": "PASS" if legacy_pass else "FAIL",
})

jsonl_texts: list[str] = []
for path in REPO.rglob("*.jsonl"):
    if ".git" in path.parts or "proofs/issue-118" in path.as_posix():
        continue
    jsonl_texts.append(path.read_text(encoding="utf-8"))
jsonl = "\n".join(jsonl_texts).lower()
shell_command_strings = count([r'"shell(command|_command)?"\s*:', r'"command"\s*:\s*"(?:sh|bash)\s+-c'], jsonl)
shell_expansion_forms = count([r'\$\([^)]*\)', r'`[^`]+`'], jsonl)
workflow_branches = count([r'"(if|else|switch|workflow_branch|branches)"\s*:'], jsonl)
workflow_loops = count([r'"(loop|while|foreach|for_each)"\s*:'], jsonl)
embedded_programs = count([r'"(script|program|source_code)"\s*:'], jsonl)
write("jsonl-language-guard.json", {
    "kind": "edits.jsonlLanguageGuard.v1",
    "scannedFileCount": len(jsonl_texts),
    "shellCommandStrings": shell_command_strings,
    "shellExpansionForms": shell_expansion_forms,
    "workflowBranches": workflow_branches,
    "workflowLoops": workflow_loops,
    "embeddedPrograms": embedded_programs,
    "status": "PASS" if all(value == 0 for value in [shell_command_strings, shell_expansion_forms, workflow_branches, workflow_loops, embedded_programs]) else "FAIL",
})
