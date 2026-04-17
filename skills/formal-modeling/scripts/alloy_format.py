#!/usr/bin/env python3
"""
Generic formatter for Alloy XML instance output.

Usage:
    java -cp .:alloy.jar AlloyRunner model.als | python3 alloy_format.py
    python3 alloy_format.py output.txt
"""

import re
import sys
import xml.etree.ElementTree as ET
from collections import defaultdict


# ---------------------------------------------------------------------------
# Atom label shortening
# ---------------------------------------------------------------------------

def _make_shortener(atoms: list[str]) -> dict[str, str]:
    """
    Build a label -> short_label map.
    "FooBar$0" -> "FB0",  "True$0" -> "True",  "univ" -> "univ"
    Collision-safe: if abbreviation clashes, fall back to the full name.
    """
    def abbrev(name: str) -> str:
        # CamelCase -> initials, e.g. FooBar -> FB, User -> U
        caps = re.findall(r"[A-Z][a-z0-9]*", name)
        if caps:
            return "".join(c[0] for c in caps).upper()
        return name[:2].upper()

    result: dict[str, str] = {}
    used: dict[str, str] = {}  # short -> original full atom

    for atom in atoms:
        m = re.match(r"^(.+?)\$(\d+)$", atom)
        if not m:
            result[atom] = atom
            continue
        name, idx = m.group(1), m.group(2)
        short = abbrev(name) + idx
        if short in used and used[short] != name:
            # collision: use full name without $
            short = name + idx
        used[short] = name
        result[atom] = short

    return result


# ---------------------------------------------------------------------------
# XML parsing
# ---------------------------------------------------------------------------

class AlloyInstance:
    def __init__(self, xml_text: str):
        root = ET.fromstring(xml_text)
        el = root.find("instance") if root.tag == "alloy" else root

        self.command: str = el.attrib.get("command", "")

        # sig_id -> {label, parent_id, atoms, builtin, abstract, one}
        self._sigs: dict[str, dict] = {}
        # (parent_label, field_name) -> [(atom, ...), ...]
        self.fields: dict[tuple, list[tuple]] = {}
        # witness_name -> [atom, ...]
        self.skolems: dict[str, list[str]] = {}

        for child in el:
            if child.tag == "sig":
                self._sigs[child.attrib["ID"]] = {
                    "label":     child.attrib["label"].removeprefix("this/"),
                    "parent_id": child.attrib.get("parentID", ""),
                    "atoms":     [a.attrib["label"] for a in child.findall("atom")],
                    "builtin":   child.attrib.get("builtin") == "yes",
                    "abstract":  child.attrib.get("abstract") == "yes",
                    "one":       child.attrib.get("one") == "yes",
                }
            elif child.tag == "field":
                parent_id = child.attrib.get("parentID", "")
                fname = child.attrib["label"]
                tuples = [
                    tuple(a.attrib["label"] for a in t.findall("atom"))
                    for t in child.findall("tuple")
                ]
                self.fields[(parent_id, fname)] = tuples
            elif child.tag == "skolem":
                raw = child.attrib["label"]
                name = raw.split("_", 1)[-1] if "_" in raw else raw.lstrip("$")
                # atoms are either direct children or inside <tuple> elements
                direct = [a.attrib["label"] for a in child.findall("atom")]
                via_tuple = [
                    a.attrib["label"]
                    for t in child.findall("tuple")
                    for a in t.findall("atom")
                ]
                self.skolems[name] = direct or via_tuple

        # remap field keys from parent_id to parent_label
        self.fields = {
            (self._sigs[pid]["label"] if pid in self._sigs else pid, fname): tuples
            for (pid, fname), tuples in self.fields.items()
        }

        # collect all atoms across all non-builtin sigs
        all_atoms = [
            a for s in self._sigs.values()
            if not s["builtin"]
            for a in s["atoms"]
        ]
        self._short = _make_shortener(all_atoms)

    # ---- public accessors --------------------------------------------------

    @property
    def sigs(self) -> dict[str, list[str]]:
        """label -> [atoms]  (non-builtin sigs only)"""
        return {
            s["label"]: s["atoms"]
            for s in self._sigs.values()
            if not s["builtin"]
        }

    def short(self, atom: str) -> str:
        return self._short.get(atom, atom)

    def atom_sig(self, atom: str):
        """Return the most-specific sig label that contains this atom."""
        for s in self._sigs.values():
            if atom in s["atoms"] and not s["builtin"] and not s["abstract"]:
                return s["label"]
        return None

    def is_abstract(self, label: str) -> bool:
        for s in self._sigs.values():
            if s["label"] == label:
                return s["abstract"]
        return False

    def is_one(self, label: str) -> bool:
        for s in self._sigs.values():
            if s["label"] == label:
                return s["one"]
        return False

    # atoms that witness a skolem variable
    def witnesses(self) -> dict[str, list[str]]:
        rev: dict[str, list[str]] = defaultdict(list)
        for name, atoms in self.skolems.items():
            for a in atoms:
                rev[a].append(name)
        return dict(rev)


# ---------------------------------------------------------------------------
# Rendering
# ---------------------------------------------------------------------------

def _box(title: str, width: int = 0) -> str:
    w = max(len(title) + 4, width)
    bar = "─" * w
    pad = " " * ((w - len(title)) // 2)
    return f"┌{bar}┐\n│{pad}{title}{' ' * (w - len(title) - len(pad))}│\n└{bar}┘"


def _col_widths(rows: list[list[str]]) -> list[int]:
    if not rows:
        return []
    return [max(len(r[i]) for r in rows) for i in range(len(rows[0]))]


def _table(headers: list[str], rows: list[list[str]]) -> list[str]:
    all_rows = [headers] + rows
    widths = _col_widths(all_rows)
    sep = "  ".join("─" * w for w in widths)

    def fmt(cells):
        return "  ".join(f"{c:<{w}}" for c, w in zip(cells, widths))

    lines = [fmt(headers), sep]
    for row in rows:
        lines.append(fmt(row))
    return lines


def render_instance(inst: AlloyInstance) -> list[str]:
    lines: list[str] = []
    wit = inst.witnesses()

    def wmark(atom: str) -> str:
        names = wit.get(atom, [])
        return f"  ← {', '.join(names)}" if names else ""

    sigs = inst.sigs

    # ---- 1. Sigs & atoms ---------------------------------------------------
    lines.append(_box("ATOMS"))

    # Group: skip abstract sigs (they're just unions), skip one-sigs that are
    # just enum values — show them as "Type  [one]  atom" in a compact list
    concrete: dict[str, list[str]] = {}
    for label, atoms in sorted(sigs.items()):
        if inst.is_abstract(label):
            continue
        if atoms:                    # skip empty sigs
            concrete[label] = atoms

    if concrete:
        rows = []
        for label, atoms in concrete.items():
            tag = "[one]" if inst.is_one(label) else ""
            for atom in atoms:
                rows.append([inst.short(atom), label, tag, wmark(atom).strip()])
        lines += _table(["atom", "sig", "kind", "witness"], rows)
    else:
        lines.append("  (no atoms)")

    # ---- 2. Fields (relations) ---------------------------------------------
    lines.append("")
    lines.append(_box("FIELDS (relations)"))

    for (parent, fname), tuples in sorted(inst.fields.items()):
        if not tuples:
            continue
        arity = len(tuples[0])
        header_cells = [f"[{parent}]"] + [f"col{i+1}" for i in range(arity - 1)]
        rows = [
            [inst.short(t[0])] + [inst.short(v) for v in t[1:]]
            for t in tuples
        ]
        lines.append(f"\n  {parent}.{fname}")
        for row in _table(header_cells, rows):
            lines.append("    " + row)

    # ---- 3. Witness / skolem summary ---------------------------------------
    if inst.skolems:
        lines.append("")
        lines.append(_box("WITNESSES (scenario variables)"))
        rows = [
            [name, ", ".join(inst.short(a) for a in atoms)]
            for name, atoms in sorted(inst.skolems.items())
        ]
        lines += _table(["variable", "value"], rows)

    return lines


# ---------------------------------------------------------------------------
# Temporal trace: parse multiple <instance> elements from one <alloy> block
# ---------------------------------------------------------------------------

def parse_trace(xml_text: str) -> list:
    """Return a list of AlloyInstance objects, one per time step."""
    root = ET.fromstring(xml_text)
    instances = root.findall("instance") if root.tag == "alloy" else [root]
    return [AlloyInstance._from_element(el) for el in instances]


# Patch AlloyInstance to support construction from an already-parsed element
_orig_init = AlloyInstance.__init__

def _from_element(cls, el):
    obj = object.__new__(cls)
    # Replicate __init__ but accept an Element directly
    obj.command = el.attrib.get("command", "")
    obj._tracelength = int(el.attrib.get("tracelength", 1))
    obj._backloop = int(el.attrib.get("backloop", 0))
    obj._sigs = {}
    obj.fields = {}
    obj.skolems = {}
    sig_id_to_label = {}

    for child in el:
        tag = child.tag
        if tag == "sig":
            label = child.attrib["label"].removeprefix("this/")
            obj._sigs[child.attrib["ID"]] = {
                "label":     label,
                "parent_id": child.attrib.get("parentID", ""),
                "atoms":     [a.attrib["label"] for a in child.findall("atom")],
                "builtin":   child.attrib.get("builtin") == "yes",
                "abstract":  child.attrib.get("abstract") == "yes",
                "one":       child.attrib.get("one") == "yes",
                "var":       child.attrib.get("var") == "yes",
            }
            sig_id_to_label[child.attrib["ID"]] = label
        elif tag == "field":
            parent_id = child.attrib.get("parentID", "")
            fname = child.attrib["label"]
            tuples = [
                tuple(a.attrib["label"] for a in t.findall("atom"))
                for t in child.findall("tuple")
            ]
            obj.fields[(parent_id, fname)] = tuples
        elif tag == "skolem":
            raw = child.attrib["label"]
            name = raw.split("_", 1)[-1] if "_" in raw else raw.lstrip("$")
            direct = [a.attrib["label"] for a in child.findall("atom")]
            via_tuple = [
                a.attrib["label"]
                for t in child.findall("tuple")
                for a in t.findall("atom")
            ]
            obj.skolems[name] = direct or via_tuple

    obj.fields = {
        (obj._sigs[pid]["label"] if pid in obj._sigs else pid, fname): tuples
        for (pid, fname), tuples in obj.fields.items()
    }

    all_atoms = [
        a for s in obj._sigs.values()
        if not s["builtin"]
        for a in s["atoms"]
    ]
    obj._short = _make_shortener(all_atoms)
    return obj

AlloyInstance._from_element = classmethod(_from_element)


def _is_temporal(xml_text: str) -> bool:
    """True if the <alloy> block contains more than one <instance> (temporal trace)."""
    root = ET.fromstring(xml_text)
    return len(root.findall("instance")) > 1


# ---------------------------------------------------------------------------
# Temporal trace renderer
# ---------------------------------------------------------------------------

def _snapshot_state(inst: AlloyInstance) -> dict:
    """Extract a minimal state dict for delta comparison."""
    state = {}
    for label, atoms in inst.sigs.items():
        if not inst.is_abstract(label) and not inst._sigs.get(
                next((k for k, v in inst._sigs.items() if v["label"] == label), None), {}
        ).get("builtin"):
            state[("sig", label)] = frozenset(atoms)
    for (parent, fname), tuples in inst.fields.items():
        state[("field", parent, fname)] = frozenset(tuples)
    return state


def _delta(prev: dict, curr: dict) -> dict:
    """Return keys that changed between two snapshots."""
    changed = {}
    all_keys = set(prev) | set(curr)
    for k in all_keys:
        p, c = prev.get(k, frozenset()), curr.get(k, frozenset())
        if p != c:
            changed[k] = (p, c)
    return changed


def render_trace(states: list) -> list:
    """Render a sequence of AlloyInstance objects as a temporal trace."""
    if not states:
        return []

    lines = []
    tracelength = getattr(states[0], "_tracelength", len(states))
    backloop    = getattr(states[0], "_backloop",    0)
    command     = states[0].command

    lines.append(f"  {command}")
    lines.append(f"  trace length: {tracelength} states  |  loop-back to state {backloop}")

    snapshots = [_snapshot_state(s) for s in states]
    wit = states[-1].witnesses()   # skolems from last (most complete) state

    def wmark(atom):
        names = wit.get(atom, [])
        return f"  ← {', '.join(names)}" if names else ""

    for i, inst in enumerate(states):
        is_loop = (i == backloop and i > 0)
        loop_tag = "  (↩ loop-back)" if is_loop else ""
        lines.append("")
        lines.append(f"━━━ State {i}{loop_tag} " + "━" * max(0, 50 - len(str(i)) - len(loop_tag)))

        # Show var sigs that are non-empty or changed
        sig_lines = []
        for label, atoms in sorted(inst.sigs.items()):
            if inst.is_abstract(label):
                continue
            sid = next((k for k, v in inst._sigs.items() if v["label"] == label), None)
            is_var = sid and inst._sigs[sid].get("var", False)
            is_one = inst.is_one(label)
            if is_one:
                continue  # skip enum singletons (True/False, SubActive, etc.)

            marker = "~" if is_var else " "
            changed = i > 0 and ("sig", label) in _delta(snapshots[i-1], snapshots[i])
            change_tag = " ◄ changed" if changed else ""
            atom_str = "{" + ", ".join(inst.short(a) + wmark(a) for a in atoms) + "}"
            sig_lines.append(f"  {marker} {label:<20} {atom_str}{change_tag}")

        if sig_lines:
            lines += sig_lines

        # Show var fields that changed or are non-empty
        for (parent, fname), tuples in sorted(inst.fields.items()):
            if not tuples:
                continue
            sid = next((k for k, v in inst._sigs.items() if v["label"] == parent), None)
            field_is_var = sid is not None  # all fields shown; var inferred from sig
            changed = i > 0 and ("field", parent, fname) in _delta(snapshots[i-1], snapshots[i])
            change_tag = " ◄" if changed else ""
            rows = "  ".join(
                f"{inst.short(t[0])}→{inst.short(t[1])}" if len(t) == 2
                else "(" + ", ".join(inst.short(x) for x in t) + ")"
                for t in tuples
            )
            lines.append(f"    {'~' if changed else ' '} {parent}.{fname:<18} {rows}{change_tag}")

    # Witness summary
    if states[-1].skolems:
        lines.append("")
        lines.append("━━━ Witnesses " + "━" * 38)
        for name, atoms in sorted(states[-1].skolems.items()):
            lines.append(f"  {name:<20} = {', '.join(states[-1].short(a) for a in atoms)}")

    return lines


# ---------------------------------------------------------------------------
# UNSAT core display
# ---------------------------------------------------------------------------

def _print_core(body: str):
    """Print UNSAT core with source text if the .als file is readable."""
    lines = body.split("\n")
    in_core = False
    core_entries = []  # list of (filename, line_num)
    for line in lines:
        if line.strip() == "CORE":
            in_core = True
            continue
        if in_core and line.startswith("  "):
            m = re.match(r"line (\d+), column \d+, filename=(.+)", line.strip())
            if m:
                core_entries.append((m.group(2), int(m.group(1))))
        elif in_core:
            break
    if not core_entries:
        return

    # Try to read source files for context
    # The filename may be absolute or relative to cwd
    file_cache = {}
    for fname, _ in core_entries:
        if fname not in file_cache:
            try:
                with open(fname) as f:
                    file_cache[fname] = f.readlines()
            except FileNotFoundError:
                # Try relative to common locations
                import os
                for prefix in ["", "formal-modeling/", "../"]:
                    try:
                        with open(os.path.join(prefix, fname)) as f:
                            file_cache[fname] = f.readlines()
                            break
                    except FileNotFoundError:
                        continue
                else:
                    file_cache[fname] = None
            except Exception:
                file_cache[fname] = None

    # Deduplicate and group by filename
    seen = set()
    unique = []
    for fname, lno in core_entries:
        key = (fname, lno)
        if key not in seen:
            seen.add(key)
            unique.append(key)

    print("  ┌─ UNSAT core (why this is unsatisfiable) ──┐")
    for fname, lno in unique:
        src_lines = file_cache.get(fname)
        if src_lines and 0 < lno <= len(src_lines):
            src = src_lines[lno - 1].rstrip()
            # Trim long lines
            if len(src) > 72:
                src = src[:69] + "..."
            print(f"  │  {fname}:{lno}  {src}")
        else:
            print(f"  │  {fname}:{lno}")
    print(f"  └─ {len(unique)} constraint(s) in minimal core ─────┘")


# ---------------------------------------------------------------------------
# I/O: split AlloyRunner output on ===RUN/===END markers
# ---------------------------------------------------------------------------

def main():
    src = open(sys.argv[1]).read() if len(sys.argv) > 1 else sys.stdin.read()

    # Split on both ===RUN label=== and ===CHECK label=== markers.
    blocks = re.split(r"^===(RUN|CHECK) (.+?)===\s*$", src, flags=re.MULTILINE)
    # blocks: [preamble, kind, label, body, kind, label, body, ...]
    it = iter(blocks[1:])
    for kind, label, body in zip(it, it, it):
        kind  = kind.strip()
        label = label.strip()
        body  = body.strip().removesuffix("===END===").strip()

        if kind == "CHECK":
            print("=" * 62)
            print(f"  check: {label}")
            print("=" * 62)
            if body.startswith("NO_COUNTEREXAMPLE"):
                print("  ✓  assertion holds — no counterexample found")
                _print_core(body)
                print()
            else:
                # body starts with "COUNTEREXAMPLE\n<alloy...>"
                print("  ✗  COUNTEREXAMPLE FOUND\n")
                xml_match = re.search(r"(<alloy\b.*?</alloy>)", body, re.DOTALL)
                if xml_match:
                    try:
                        inst = AlloyInstance(xml_match.group(1))
                        print(f"  {inst.command}\n")
                        for line in render_instance(inst):
                            print(line)
                    except Exception as e:
                        import traceback
                        print(f"  ERROR rendering counterexample: {e}")
                        traceback.print_exc()
                else:
                    print("  (no XML in counterexample output)")
            print()
            continue

        # kind == "RUN"
        print("=" * 62)
        print(f"  run: {label}")
        print("=" * 62)

        if body.startswith("UNSAT"):
            print("  (unsatisfiable — no instance exists)")
            _print_core(body)
            print()
            continue

        xml_match = re.search(r"(<alloy\b.*?</alloy>)", body, re.DOTALL)
        if not xml_match:
            print("  (no XML found)\n")
            continue

        xml_text = xml_match.group(1)
        try:
            if _is_temporal(xml_text):
                states = parse_trace(xml_text)
                for line in render_trace(states):
                    print(line)
            else:
                inst = AlloyInstance(xml_text)
                print(f"  {inst.command}\n")
                for line in render_instance(inst):
                    print(line)
        except Exception as e:
            import traceback
            print(f"  ERROR: {e}")
            traceback.print_exc()
        print()


if __name__ == "__main__":
    main()
