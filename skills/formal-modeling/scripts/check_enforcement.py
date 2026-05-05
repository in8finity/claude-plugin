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


def _dotted(node: ast.AST) -> str | None:
    if isinstance(node, ast.Name):
        return node.id
    if isinstance(node, ast.Attribute):
        base = _dotted(node.value)
        return f"{base}.{node.attr}" if base else node.attr
    return None


def _python_call_targets(tree: ast.AST) -> set[str]:
    """Collect dotted names that appear as call targets in a Python AST."""
    names: set[str] = set()
    for node in ast.walk(tree):
        if isinstance(node, ast.Call):
            d = _dotted(node.func)
            if d:
                names.add(d)
                # also expose the trailing tail (for `from x import y; y()`)
                names.add(d.rsplit(".", 1)[-1])
    return names


def _name_matches(call: str, target: str) -> bool:
    """True if a call expression's dotted name should be considered a hit
    for the named target.

    Matches: exact, dotted suffix (`a.b.c` matches `c` or `b.c`), and
    bare-tail (`from x import y; y()` matches target `x.y`).
    """
    if call == target:
        return True
    if call.endswith("." + target):
        return True
    tail = target.rsplit(".", 1)[-1]
    if call == tail or call.endswith("." + tail):
        return True
    return False


def _calls_by_enclosing_function(
    tree: ast.AST,
) -> dict[ast.AST, list[tuple[str, int]]]:
    """Map each FunctionDef/AsyncFunctionDef to its [(dotted_name, lineno), ...].

    Each Call is attributed to its NEAREST enclosing function, so calls
    inside a nested `def` belong to the nested def, not the outer one.
    Module-level calls are dropped (no enclosing function).
    """
    out: dict[ast.AST, list[tuple[str, int]]] = {}

    def visit(node: ast.AST, current: ast.AST | None) -> None:
        if isinstance(node, (ast.FunctionDef, ast.AsyncFunctionDef)):
            out[node] = []
            current = node
        if isinstance(node, ast.Call) and current is not None:
            name = _dotted(node.func)
            if name:
                out[current].append((name, node.lineno))
        for child in ast.iter_child_nodes(node):
            visit(child, current)

    visit(tree, None)
    return out


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
        if any(_name_matches(t, must_call) for t in targets):
            return GateResult(label, True)
        return GateResult(label, False, "no matching call expression")
    # non-Python fallback: regex for `<name>(`
    text = file.read_text()
    pattern = re.compile(r"\b" + re.escape(must_call.split(".")[-1]) + r"\s*\(")
    if pattern.search(text):
        return GateResult(label, True, "(regex fallback — non-Python)")
    return GateResult(label, False, "no matching call site (regex fallback)")


def _python_scopes(text: str, filename: str) -> dict[tuple[str, int], list[tuple[str, int]]] | str:
    """Return {(scope_name, scope_lineno): [(call_name, lineno), ...]}
    or an error string on parse failure."""
    try:
        tree = ast.parse(text, filename=filename)
    except SyntaxError as e:
        return f"syntax error: {e.msg}"
    out: dict[tuple[str, int], list[tuple[str, int]]] = {}
    for fn, calls in _calls_by_enclosing_function(tree).items():
        out[(fn.name, fn.lineno)] = calls
    return out


def _bashlex_module():
    """Lazy import of bashlex; emit a clear error if missing."""
    try:
        import bashlex  # type: ignore
        return bashlex
    except ImportError:
        return None


def _bash_scopes(text: str, filename: str) -> dict[tuple[str, int], list[tuple[str, int]]] | str:
    """bashlex-based scope/call extraction for bash scripts.

    Returns the same shape as `_python_scopes`. A synthetic
    ('<script>', 1) scope holds module-level commands so script-level
    lexical-precedence patterns (no functions, just top-down order)
    work the same way as in-function patterns.
    """
    bashlex = _bashlex_module()
    if bashlex is None:
        return ("bashlex not installed — "
                "`pip install bashlex` (or `--break-system-packages` on macOS)")
    try:
        trees = bashlex.parse(text)
    except (bashlex.errors.ParsingError, NotImplementedError) as e:
        return f"bash parse error: {e}"
    except Exception as e:  # bashlex raises various
        return f"bash parse error: {e}"

    # Byte-offset → 1-based line number.
    line_starts = [0]
    for i, c in enumerate(text):
        if c == "\n":
            line_starts.append(i + 1)
    import bisect

    def lineno(pos: int) -> int:
        return bisect.bisect_right(line_starts, pos)

    scopes: dict[tuple[str, int], list[tuple[str, int]]] = {}
    module_scope = ("<script>", 1)
    scopes[module_scope] = []

    def walk(node: Any, current: tuple[str, int]) -> None:
        if node is None:
            return
        kind = getattr(node, "kind", None)

        if kind == "function":
            # bashlex FunctionNode.parts = [reserved 'function'?, name_word,
            #   '(', ')'?, compound_body]. The function name is the first
            # WordNode; the body is the CompoundNode.
            fn_name: str | None = None
            body = None
            for p in getattr(node, "parts", []) or []:
                pkind = getattr(p, "kind", None)
                if pkind == "word" and fn_name is None:
                    fn_name = getattr(p, "word", None)
                elif pkind == "compound":
                    body = p
            if fn_name is not None and body is not None:
                new_scope = (fn_name, lineno(node.pos[0]))
                scopes.setdefault(new_scope, [])
                walk(body, new_scope)
                return
            # Malformed function: fall through to generic recursion.

        if kind == "command":
            # First WordNode in parts is the command name. Skip
            # AssignmentNodes (e.g. `result=$(...)` has no command word).
            for p in getattr(node, "parts", []) or []:
                if getattr(p, "kind", None) == "word":
                    cmd = getattr(p, "word", "")
                    scopes[current].append((cmd, lineno(p.pos[0])))
                    break
            # Still descend into parts to catch commands nested inside
            # `$( ... )`, `<( ... )`, heredocs, etc.
            for p in getattr(node, "parts", []) or []:
                walk(p, current)
            return

        # Generic recursion over child-bearing attributes.
        for attr in ("parts", "list", "command", "body"):
            child = getattr(node, attr, None)
            if child is None:
                continue
            if isinstance(child, list):
                for c in child:
                    if hasattr(c, "kind"):
                        walk(c, current)
            elif hasattr(child, "kind"):
                walk(child, current)

    for tree in trees:
        walk(tree, module_scope)
    return scopes


_SCOPE_EXTRACTORS = {
    "python": _python_scopes,
    "bash":   _bash_scopes,
}

_LANGUAGE_SUFFIXES = {
    "python": {".py"},
    "bash":   {".sh", ".bash"},
}


def check_closure_gate(
    project_root: Path,
    search_glob: str,
    protected: str,
    gate: str,
    language: str = "python",
) -> list[GateResult]:
    """Enumerate every call site of `protected` under `search_glob` (in
    files of the configured `language`) and verify that `gate` is called
    earlier in the same enclosing function (or earlier in script-level
    flow, for module-level commands).

    Catches the bug class where a NEW file is added that calls the
    protected primitive but isn't listed in any `code_gates` entry —
    the file-list check passes silently, this check does not.
    """
    extractor = _SCOPE_EXTRACTORS.get(language)
    if extractor is None:
        return [GateResult(
            f"closure: {protected}", False,
            f"unsupported language {language!r}; "
            f"supported: {sorted(_SCOPE_EXTRACTORS)}")]

    suffixes = _LANGUAGE_SUFFIXES[language]
    out: list[GateResult] = []
    files = sorted(project_root.glob(search_glob))
    target_files = [
        f for f in files if f.is_file() and f.suffix in suffixes
    ]

    if not target_files:
        return [GateResult(
            f"closure: {protected}", False,
            f"no {language} files match search glob {search_glob!r}")]

    found_sites = 0
    for file in target_files:
        text = file.read_text(errors="replace")
        result = extractor(text, str(file))
        rel = file.relative_to(project_root)
        if isinstance(result, str):
            out.append(GateResult(f"{rel}: parse", False, result))
            continue
        for (scope_name, _scope_line), calls in result.items():
            protected_sites = [
                (name, line) for (name, line) in calls
                if _name_matches(name, protected)
            ]
            if not protected_sites:
                continue
            gate_lines = [
                line for (name, line) in calls
                if _name_matches(name, gate)
            ]
            for _, prot_line in protected_sites:
                found_sites += 1
                label = (f"{rel}:{prot_line} {scope_name}() "
                         f"calls {protected}")
                preceding = [g for g in gate_lines if g < prot_line]
                if preceding:
                    out.append(GateResult(
                        label, True,
                        f"gated by {gate} at line {preceding[-1]}"))
                else:
                    out.append(GateResult(
                        label, False,
                        f"no preceding call to {gate} "
                        f"in {scope_name}()"))

    if found_sites == 0:
        out.append(GateResult(
            f"closure: {protected}", False,
            f"protected primitive {protected!r} has no call sites under "
            f"{search_glob!r} — model claims a gate but nothing is gated"))
    return out


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

    for cl in entry.get("closure_gates", []) or []:
        protected = str(cl["protected"])
        gate = str(cl["gate"])
        language = str(cl.get("language", "python"))
        default_glob = "**/*.py" if language == "python" else "**/*.sh"
        search = str(cl.get("search", default_glob))
        result.gates.extend(
            check_closure_gate(
                project_root, search, protected, gate, language))

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


# ─── call-site enumeration ────────────────────────────────────────────────

@dataclass
class CallSite:
    file: Path
    line: int
    scope: str


@dataclass
class PrimitiveListing:
    name: str
    language: str
    search: str
    sites: list[CallSite] = field(default_factory=list)
    audited: bool = False  # True if some closure_gates entry targets this primitive
    parse_errors: list[str] = field(default_factory=list)


def enumerate_call_sites(
    yaml_doc: dict[str, Any], project_root: Path,
) -> list[PrimitiveListing]:
    """For each declared `protected_primitives` entry, walk the search
    glob and return every call site as a `CallSite`. Cross-references
    each primitive against the YAML's `closure_gates` entries so the
    output can flag primitives with no enforcement attached.
    """
    primitives = yaml_doc.get("protected_primitives", []) or []

    closure_targets: set[str] = set()
    for entry in yaml_doc.get("properties", []) or []:
        for cg in entry.get("closure_gates", []) or []:
            closure_targets.add(str(cg["protected"]))

    out: list[PrimitiveListing] = []
    for prim in primitives:
        name = str(prim["name"])
        language = str(prim.get("language", "python"))
        default_glob = "**/*.py" if language == "python" else "**/*.sh"
        search = str(prim.get("search", default_glob))

        audited = any(
            _name_matches(name, t) or _name_matches(t, name)
            for t in closure_targets
        )
        listing = PrimitiveListing(
            name=name, language=language, search=search, audited=audited)

        extractor = _SCOPE_EXTRACTORS.get(language)
        if extractor is None:
            listing.parse_errors.append(
                f"unsupported language {language!r}")
            out.append(listing)
            continue

        suffixes = _LANGUAGE_SUFFIXES[language]
        files = sorted(project_root.glob(search))
        target_files = [
            f for f in files if f.is_file() and f.suffix in suffixes]

        for file in target_files:
            text = file.read_text(errors="replace")
            result = extractor(text, str(file))
            rel = file.relative_to(project_root)
            if isinstance(result, str):
                listing.parse_errors.append(f"{rel}: {result}")
                continue
            for (scope_name, _scope_line), calls in result.items():
                for cname, cline in calls:
                    if _name_matches(cname, name):
                        listing.sites.append(CallSite(
                            file=rel, line=cline, scope=scope_name))
        listing.sites.sort(key=lambda s: (str(s.file), s.line))
        out.append(listing)
    return out


def emit_call_site_listing(listings: list[PrimitiveListing]) -> None:
    width = 70
    print("\n" + "=" * width)
    print(" Protected primitives — call site enumeration")
    print("=" * width)

    if not listings:
        print("\n(no `protected_primitives` declared in YAML)")
        return

    for L in listings:
        print(f"\n* {L.name}  ({L.language} - {L.search})")
        if L.audited:
            print("  audited by closure_gates: yes")
        else:
            print("  audited by closure_gates: NO "
                  "- no closure_gates entry targets this primitive")
        for err in L.parse_errors:
            print(f"  ! {err}")
        if not L.sites:
            print("  call sites: (none found)")
            continue
        n_files = len({s.file for s in L.sites})
        # Pad scope column for alignment within this primitive's block.
        max_loc = max(len(f"{s.file}:{s.line}") for s in L.sites)
        for s in L.sites:
            loc = f"{s.file}:{s.line}".ljust(max_loc)
            print(f"  - {loc}  {s.scope}()")
        s_sites = "" if len(L.sites) == 1 else "s"
        s_files = "" if n_files == 1 else "s"
        print(f"  {len(L.sites)} site{s_sites} "
              f"across {n_files} file{s_files}")


# ─── output ────────────────────────────────────────────────────────────────

def emit_text(results: list[PropertyResult],
              missing_coverage: list[str],
              listings: list[PrimitiveListing] | None = None) -> None:
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

    if listings is not None:
        emit_call_site_listing(listings)

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
              missing_coverage: list[str],
              listings: list[PrimitiveListing] | None = None) -> None:
    payload: dict[str, Any] = {
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
    if listings is not None:
        payload["protected_primitives"] = [
            {
                "name": L.name,
                "language": L.language,
                "search": L.search,
                "audited": L.audited,
                "parse_errors": L.parse_errors,
                "sites": [
                    {"file": str(s.file), "line": s.line, "scope": s.scope}
                    for s in L.sites
                ],
            }
            for L in listings
        ]
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
    p.add_argument("--list-call-sites", action="store_true",
                   help="enumerate every call site of each declared "
                        "`protected_primitives` entry, marking which are "
                        "covered by a closure_gates rule (informational; "
                        "exit code unchanged)")
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
    listings = (enumerate_call_sites(doc, project_root)
                if args.list_call_sites else None)

    if args.format == "json":
        emit_json(results, missing, listings)
    else:
        emit_text(results, missing, listings)

    all_pass = all(r.ok for r in results) and not missing
    return 0 if all_pass else 1


if __name__ == "__main__":
    sys.exit(main())
