#!/usr/bin/env python3
"""
check_enforcement.py — mechanical audit of an enforcement.yaml artifact.

Each entry in enforcement.yaml maps a verified property to:
  - the model assertions that prove it (.als/.dfy)
  - the code gate sites that enforce it at runtime
  - the skill/spec text that documents it
  - the tests that exercise it

This checker fails CI if any claimed evidence is missing. It is the
mechanical counterpart to the prose enforcement report described in
SKILL.md step 10b — the prose explains, the YAML proves.

Usage:
  check_enforcement.py <enforcement.yaml> [--project-root <path>]
                                          [--format text|json]
                                          [--check-coverage]

Exits 0 if every entry's claimed evidence is present; non-zero otherwise.
"""

from __future__ import annotations

import argparse
import ast
import json
import re
import sys
from dataclasses import dataclass, field
from pathlib import Path
from typing import Any

try:
    import yaml  # type: ignore
except ImportError:
    sys.stderr.write(
        "error: PyYAML is required. Install with: pip install pyyaml\n"
    )
    sys.exit(2)


# ─── result types ──────────────────────────────────────────────────────────

@dataclass
class GateResult:
    label: str
    ok: bool
    detail: str = ""


@dataclass
class PropertyResult:
    id: str
    description: str
    gates: list[GateResult] = field(default_factory=list)

    @property
    def ok(self) -> bool:
        return all(g.ok for g in self.gates)


# ─── per-gate checkers ─────────────────────────────────────────────────────

ALS_ASSERT_RE = re.compile(r"^\s*assert\s+(\w+)\b", re.MULTILINE)
ALS_CHECK_RE = re.compile(r"^\s*check\s+(\w+)\b", re.MULTILINE)
DFY_LEMMA_RE = re.compile(r"^\s*(?:lemma|method)\s+(\w+)\b", re.MULTILINE)


def check_model_asserts(file: Path, asserts: list[str]) -> list[GateResult]:
    out: list[GateResult] = []
    if not file.exists():
        return [GateResult(f"model {file}", False, "file not found")]
    text = file.read_text()
    suffix = file.suffix.lower()
    if suffix == ".als":
        defined = set(ALS_ASSERT_RE.findall(text))
        checked = set(ALS_CHECK_RE.findall(text))
        for name in asserts:
            if name not in defined:
                out.append(GateResult(
                    f"{file.name}: assert {name}", False,
                    "no `assert <name>` found"))
            elif name not in checked:
                out.append(GateResult(
                    f"{file.name}: assert {name}", False,
                    "assert defined but no paired `check`"))
            else:
                out.append(GateResult(
                    f"{file.name}: assert {name}", True))
    elif suffix == ".dfy":
        defined = set(DFY_LEMMA_RE.findall(text))
        for name in asserts:
            ok = name in defined
            out.append(GateResult(
                f"{file.name}: lemma {name}", ok,
                "" if ok else "no `lemma`/`method` of that name"))
    else:
        out.append(GateResult(
            f"{file.name}: asserts", False,
            f"unsupported model extension: {suffix}"))
    return out


def _python_call_targets(tree: ast.AST) -> set[str]:
    """Collect dotted names that appear as call targets in a Python AST."""
    names: set[str] = set()

    def dotted(node: ast.AST) -> str | None:
        if isinstance(node, ast.Name):
            return node.id
        if isinstance(node, ast.Attribute):
            base = dotted(node.value)
            return f"{base}.{node.attr}" if base else node.attr
        return None

    for node in ast.walk(tree):
        if isinstance(node, ast.Call):
            d = dotted(node.func)
            if d:
                names.add(d)
                # also expose the trailing tail (for `from x import y; y()`)
                names.add(d.rsplit(".", 1)[-1])
    return names


def check_must_call(file: Path, must_call: str) -> GateResult:
    label = f"{file.name}: calls {must_call}"
    if not file.exists():
        return GateResult(label, False, "file not found")
    if file.suffix == ".py":
        try:
            tree = ast.parse(file.read_text(), filename=str(file))
        except SyntaxError as e:
            return GateResult(label, False, f"parse error: {e.msg}")
        targets = _python_call_targets(tree)
        if must_call in targets:
            return GateResult(label, True)
        # also accept a suffix match (e.g. `check_sticky_eligibility` matches
        # `self.store.check_sticky_eligibility`)
        tail = must_call.rsplit(".", 1)[-1]
        if any(t == must_call or t.endswith("." + must_call) or t == tail
               for t in targets):
            return GateResult(label, True)
        return GateResult(label, False, "no matching call expression")
    # non-Python fallback: regex for `<name>(`
    text = file.read_text()
    pattern = re.compile(r"\b" + re.escape(must_call.split(".")[-1]) + r"\s*\(")
    if pattern.search(text):
        return GateResult(label, True, "(regex fallback — non-Python)")
    return GateResult(label, False, "no matching call site (regex fallback)")


def check_must_exit(file: Path, code: int) -> GateResult:
    label = f"{file.name}: exits with {code}"
    if not file.exists():
        return GateResult(label, False, "file not found")
    text = file.read_text()
    n = re.escape(str(code))
    pattern = re.compile(
        rf"\b(?:return\s+{n}\b"
        rf"|sys\.exit\s*\(\s*{n}\s*\)"
        rf"|exit\s*\(\s*{n}\s*\)"
        rf"|raise\s+SystemExit\s*\(\s*{n}\s*\))"
    )
    return (GateResult(label, True)
            if pattern.search(text)
            else GateResult(label, False, "no matching exit path"))


def check_must_mention(file: Path, phrases: list[str]) -> list[GateResult]:
    out: list[GateResult] = []
    if not file.exists():
        return [GateResult(f"{file.name}: mentions", False, "file not found")]
    text = file.read_text().lower()
    for phrase in phrases:
        ok = phrase.lower() in text
        out.append(GateResult(
            f"{file.name}: mentions {phrase!r}", ok,
            "" if ok else "phrase not found"))
    return out


def check_tests(test_names: list[str], project_root: Path,
                tests_glob: str) -> list[GateResult]:
    out: list[GateResult] = []
    test_files = list(project_root.glob(tests_glob))
    if not test_files:
        return [GateResult(
            f"tests: glob {tests_glob}", False,
            "no files match glob")]
    blob = "\n".join(p.read_text(errors="replace") for p in test_files
                     if p.is_file())
    for name in test_names:
        n = re.escape(name)
        pattern = re.compile(rf"def\s+(?:test_)?{n}\b")
        ok = bool(pattern.search(blob))
        out.append(GateResult(
            f"tests: def {name}", ok,
            "" if ok else f"no matching `def` in {tests_glob}"))
    return out


# ─── per-entry driver ──────────────────────────────────────────────────────

def check_entry(entry: dict[str, Any], project_root: Path,
                tests_glob: str) -> PropertyResult:
    pid = str(entry.get("id", "<unnamed>"))
    desc = str(entry.get("description", ""))
    result = PropertyResult(pid, desc)

    for m in entry.get("models", []) or []:
        file = (project_root / m["file"]).resolve()
        result.gates.extend(
            check_model_asserts(file, list(m.get("asserts", []))))

    for cg in entry.get("code_gates", []) or []:
        file = (project_root / cg["file"]).resolve()
        if "must_call" in cg:
            result.gates.append(check_must_call(file, str(cg["must_call"])))
        if "must_exit" in cg:
            result.gates.append(check_must_exit(file, int(cg["must_exit"])))

    for st in entry.get("skill_texts", []) or []:
        file = (project_root / st["file"]).resolve()
        phrases = list(st.get("must_mention", []))
        if phrases:
            result.gates.extend(check_must_mention(file, phrases))

    test_names = entry.get("tests", []) or []
    if test_names:
        result.gates.extend(
            check_tests([str(t) for t in test_names], project_root, tests_glob))

    return result


# ─── coverage pass ─────────────────────────────────────────────────────────

def check_coverage(yaml_doc: dict[str, Any], project_root: Path) -> list[str]:
    """Return a list of model `check`s that have no enforcement entry."""
    covered: set[tuple[str, str]] = set()
    for entry in yaml_doc.get("properties", []):
        for m in entry.get("models", []) or []:
            for name in m.get("asserts", []) or []:
                covered.add((Path(m["file"]).name, str(name)))

    missing: list[str] = []
    seen_files: set[Path] = set()
    for entry in yaml_doc.get("properties", []):
        for m in entry.get("models", []) or []:
            seen_files.add((project_root / m["file"]).resolve())
    for file in seen_files:
        if not file.exists() or file.suffix != ".als":
            continue
        text = file.read_text()
        for name in ALS_CHECK_RE.findall(text):
            if (file.name, name) not in covered:
                missing.append(f"{file.name}: check {name} has no entry")
    return missing


# ─── output ────────────────────────────────────────────────────────────────

def emit_text(results: list[PropertyResult],
              missing_coverage: list[str]) -> None:
    total = len(results)
    passed = sum(1 for r in results if r.ok)
    width = 70

    print("=" * width)
    print(f" Enforcement audit — {passed}/{total} properties pass")
    print("=" * width)

    for r in results:
        marker = "✓" if r.ok else "✗"
        print(f"\n{marker} {r.id} — {r.description}")
        for g in r.gates:
            mark = "  ✓" if g.ok else "  ✗"
            line = f"{mark} {g.label}"
            if g.detail:
                line += f"  ({g.detail})"
            print(line)

    if missing_coverage:
        print("\n" + "-" * width)
        print(" Coverage gaps — model checks with no enforcement entry")
        print("-" * width)
        for line in missing_coverage:
            print(f"  ! {line}")

    print()
    if passed == total and not missing_coverage:
        print("ALL PASS")
    else:
        failed = total - passed
        msg = f"{failed} propert{'y' if failed == 1 else 'ies'} failed"
        if missing_coverage:
            msg += f", {len(missing_coverage)} coverage gap(s)"
        print(f"FAIL — {msg}")


def emit_json(results: list[PropertyResult],
              missing_coverage: list[str]) -> None:
    payload = {
        "total": len(results),
        "passed": sum(1 for r in results if r.ok),
        "properties": [
            {
                "id": r.id,
                "description": r.description,
                "ok": r.ok,
                "gates": [
                    {"label": g.label, "ok": g.ok, "detail": g.detail}
                    for g in r.gates
                ],
            }
            for r in results
        ],
        "coverage_gaps": missing_coverage,
    }
    json.dump(payload, sys.stdout, indent=2)
    sys.stdout.write("\n")


# ─── main ──────────────────────────────────────────────────────────────────

def main(argv: list[str] | None = None) -> int:
    p = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    p.add_argument("yaml_file", type=Path,
                   help="path to enforcement.yaml")
    p.add_argument("--project-root", type=Path, default=None,
                   help="root for resolving relative paths "
                        "(default: yaml file's parent)")
    p.add_argument("--format", choices=("text", "json"), default="text")
    p.add_argument("--check-coverage", action="store_true",
                   help="also flag model `check`s without enforcement entries")
    args = p.parse_args(argv)

    if not args.yaml_file.exists():
        sys.stderr.write(f"error: {args.yaml_file} not found\n")
        return 2

    doc = yaml.safe_load(args.yaml_file.read_text()) or {}
    if isinstance(doc, list):
        doc = {"properties": doc}
    if "properties" not in doc:
        sys.stderr.write(
            "error: YAML must be a list of entries or "
            "{properties: [...]} mapping\n")
        return 2

    project_root = (args.project_root
                    or args.yaml_file.parent).resolve()
    tests_glob = str(doc.get("tests_glob", "tests/**/test_*.py"))

    results = [check_entry(e, project_root, tests_glob)
               for e in doc["properties"]]
    missing = (check_coverage(doc, project_root)
               if args.check_coverage else [])

    if args.format == "json":
        emit_json(results, missing)
    else:
        emit_text(results, missing)

    all_pass = all(r.ok for r in results) and not missing
    return 0 if all_pass else 1


if __name__ == "__main__":
    sys.exit(main())
