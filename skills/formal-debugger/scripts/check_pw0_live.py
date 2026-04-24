#!/usr/bin/env python3
"""
check_pw0_live.py — TC30 enforcement: no burst writes on termination turn.

Scans evidence-log.md, hypothesis-log.md, model-change-log.md under an
investigation directory. Each entry begins with a header line such as
"E3: description", "H1-2: event", or "M4: description". The entry's
body must include a `Turn:` field declaring the turn in which the entry
was written.

Termination turn is the maximum Turn: value across all three logs.
The rule: no two consecutive entries within the same log may share a
Turn: value equal to the termination turn. A shared termination-turn
pair is a "burst" and fails TC30.

Also flags entries missing the Turn: field — a separate PW0-live
violation (the field itself is mandatory per SKILL.md).

Exit 0 = pass, 1 = fail, 2 = usage error.

Usage:
    check_pw0_live.py <investigation_dir>
    check_pw0_live.py investigations/my-bug
"""
from __future__ import annotations

import argparse
import os
import re
import sys
from pathlib import Path


def rel(p: Path | str) -> str:
    """Normalize a path to cwd-relative for echo (keeps output free of absolute
    home/user paths when the caller passes a resolvable absolute path)."""
    try:
        return os.path.relpath(str(p))
    except ValueError:
        return str(p)

ENTRY_PATTERNS = {
    "evidence-log.md": re.compile(r"^E(\d+):"),
    "hypothesis-log.md": re.compile(r"^H(\d+)-(\d+):"),
    "model-change-log.md": re.compile(r"^M(\d+):"),
}

TURN_RE = re.compile(r"^\s*(?:[-*]\s*)?\*{0,2}Turn\*{0,2}\s*:\s*(\d+)", re.IGNORECASE)


def parse_log(path: Path, pattern: re.Pattern) -> list[tuple[tuple[int, ...], int | None, int]]:
    """Return list of (entry_key, turn, line_number) in file order.

    entry_key is a tuple of the integer groups in the header (e.g. (3,) for E3,
    or (1, 2) for H1-2). turn is None if no Turn: field was found in the body.
    """
    if not path.exists():
        return []

    entries: list[tuple[tuple[int, ...], int | None, int]] = []
    current_key: tuple[int, ...] | None = None
    current_turn: int | None = None
    current_line = 0

    for i, line in enumerate(path.read_text().splitlines(), start=1):
        header = pattern.match(line)
        if header:
            if current_key is not None:
                entries.append((current_key, current_turn, current_line))
            current_key = tuple(int(g) for g in header.groups())
            current_turn = None
            current_line = i
            continue
        if current_key is not None and current_turn is None:
            t = TURN_RE.match(line)
            if t:
                current_turn = int(t.group(1))

    if current_key is not None:
        entries.append((current_key, current_turn, current_line))
    return entries


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("investigation_dir", help="path to investigations/<slug>/")
    ap.add_argument("--quiet", action="store_true", help="only print on failure")
    args = ap.parse_args()

    base = Path(args.investigation_dir)
    if not base.is_dir():
        print(f"error: {rel(base)} is not a directory", file=sys.stderr)
        return 2

    logs: dict[str, list[tuple[tuple[int, ...], int | None, int]]] = {}
    all_turns: list[int] = []
    for fname, pat in ENTRY_PATTERNS.items():
        entries = parse_log(base / fname, pat)
        logs[fname] = entries
        all_turns.extend(t for _, t, _ in entries if t is not None)

    total_entries = sum(len(e) for e in logs.values())

    if total_entries == 0:
        if not args.quiet:
            print(f"TC30 SKIP: no entries under {rel(base)} — nothing to check")
        return 0

    missing = [(f, key, ln) for f, es in logs.items() for key, t, ln in es if t is None]
    if missing:
        print(f"TC30 FAIL: {len(missing)} entries missing Turn: field (PW0-live requires it):")
        for f, key, ln in missing:
            label = "E" + "-".join(map(str, key)) if f == "evidence-log.md" else \
                    "H" + "-".join(map(str, key)) if f == "hypothesis-log.md" else \
                    "M" + "-".join(map(str, key))
            print(f"  {f}:{ln}  {label}")
        return 1

    if not all_turns:
        if not args.quiet:
            print(f"TC30 SKIP: entries found but no Turn: values parsed — nothing to check")
        return 0

    termination_turn = max(all_turns)

    burst_violations: list[tuple[str, str, str, int, int]] = []
    for fname, entries in logs.items():
        prefix = {"evidence-log.md": "E", "hypothesis-log.md": "H", "model-change-log.md": "M"}[fname]
        prev: tuple[tuple[int, ...], int, int] | None = None
        for key, turn, ln in entries:
            if prev is not None and prev[1] == termination_turn and turn == termination_turn:
                prev_label = prefix + "-".join(map(str, prev[0]))
                curr_label = prefix + "-".join(map(str, key))
                burst_violations.append((fname, prev_label, curr_label, prev[2], ln))
            prev = (key, turn, ln)  # type: ignore[assignment]

    if burst_violations:
        print(f"TC30 FAIL: {len(burst_violations)} burst write(s) on termination turn {termination_turn}:")
        for f, a, b, la, lb in burst_violations:
            print(f"  {f}: {a} (line {la}) and {b} (line {lb}) both have Turn: {termination_turn}")
        print()
        print("PW0-live requires entries to be written in the turn the observation")
        print("is made. Two consecutive entries sharing the termination turn is a")
        print("burst — likely retroactive log-writing at the end of the investigation.")
        return 1

    if not args.quiet:
        print(
            f"TC30 PASS: {total_entries} entries across {len([f for f, e in logs.items() if e])} logs, "
            f"termination turn {termination_turn}, no burst writes"
        )
    return 0


if __name__ == "__main__":
    sys.exit(main())
