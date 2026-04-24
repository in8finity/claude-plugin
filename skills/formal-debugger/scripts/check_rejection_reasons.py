#!/usr/bin/env python3
"""
check_rejection_reasons.py — TC35/U2-doc enforcement.

Every status-changed-to-rejected event under `hypothesis/` MUST document why:

  Reason: evidence     +  Evidence: E<N>
  Reason: preference   +  Priority: <allowed name>  +  Rationale: <text>

Allowed priorities: Occam, BlastRadius, Severity, RecencyOfDeploy,
Reproducibility, FixCost.

Each hypothesis event is its own file under `hypothesis/` with a timestamp
suffix (e.g., `H2-4_2026-04-25T10-45-00Z.md`). The script scans all such
files, keeps only the `status-changed`-to-`rejected` ones, and validates
their Reason/Evidence/Priority/Rationale fields.

Purpose: distinguish "rejected because of evidence" from "rejected because
the investigator prefers another hypothesis." Preference-based rejection is
permitted, but ONLY when the priority criterion is named from the allowed
set and a rationale is given. A grep-based auditor can tell the two apart.

Exit 0 = pass, 1 = fail, 2 = usage error.

Usage:
    check_rejection_reasons.py <investigation_dir>
"""
from __future__ import annotations

import argparse
import os
import re
import sys
from pathlib import Path

ALLOWED_PRIORITIES = {
    "Occam",
    "BlastRadius",
    "Severity",
    "RecencyOfDeploy",
    "Reproducibility",
    "FixCost",
}

FILENAME_RE = re.compile(r"^H(\d+)-(\d+)_.*\.md$")
HEADER_RE = re.compile(r"^H(\d+)-(\d+):")
EVENT_RE = re.compile(r"^\s*(?:[-*]\s*)?\*{0,2}Event\*{0,2}\s*:\s*(\S+)", re.IGNORECASE)
DETAIL_NEW_STATUS_RE = re.compile(
    r"(?:status|new_status|to|new)\s*[:=]?\s*`?(rejected)`?", re.IGNORECASE
)
REASON_RE = re.compile(r"^\s*(?:[-*]\s*)?\*{0,2}Reason\*{0,2}\s*:\s*(\S+)", re.IGNORECASE)
EVIDENCE_RE = re.compile(r"^\s*(?:[-*]\s*)?\*{0,2}Evidence\*{0,2}\s*:\s*(E\d+)", re.IGNORECASE)
PRIORITY_RE = re.compile(r"^\s*(?:[-*]\s*)?\*{0,2}Priority\*{0,2}\s*:\s*(\S+)", re.IGNORECASE)
RATIONALE_RE = re.compile(r"^\s*(?:[-*]\s*)?\*{0,2}Rationale\*{0,2}\s*:\s*(.+)$", re.IGNORECASE)


def rel(p: Path | str) -> str:
    try:
        return os.path.relpath(str(p))
    except ValueError:
        return str(p)


def parse_hypothesis_file(path: Path) -> dict | None:
    """Parse a single hypothesis record file. Return a dict only if it's a
    status-changed-to-rejected event; otherwise None."""
    fn_match = FILENAME_RE.match(path.name)
    if not fn_match:
        return None
    entry = {
        "label": f"H{fn_match.group(1)}-{fn_match.group(2)}",
        "file": path,
        "event": "",
        "new_status": None,
        "reason": None,
        "evidence": None,
        "priority": None,
        "rationale": None,
    }
    try:
        for line in path.read_text().splitlines():
            m = EVENT_RE.match(line)
            if m:
                entry["event"] = m.group(1).strip().rstrip(".,").lower()
                continue
            m = DETAIL_NEW_STATUS_RE.search(line)
            if m and entry["new_status"] is None:
                entry["new_status"] = m.group(1).lower()
                continue
            m = REASON_RE.match(line)
            if m:
                entry["reason"] = m.group(1).strip().rstrip(".,").lower()
                continue
            m = EVIDENCE_RE.match(line)
            if m:
                entry["evidence"] = m.group(1).strip()
                continue
            m = PRIORITY_RE.match(line)
            if m:
                entry["priority"] = m.group(1).strip().rstrip(".,")
                continue
            m = RATIONALE_RE.match(line)
            if m:
                entry["rationale"] = m.group(1).strip()
                continue
    except Exception:
        return None
    if entry["event"] == "status-changed" and entry["new_status"] == "rejected":
        return entry
    return None


def collect_rejection_entries(base: Path) -> list[dict]:
    """Scan hypothesis/ subdirectory for status-changed-to-rejected records."""
    hyp_dir = base / "hypothesis"
    if not hyp_dir.is_dir():
        return []
    out: list[dict] = []
    for f in sorted(hyp_dir.iterdir()):
        if not f.is_file() or not f.name.endswith(".md"):
            continue
        e = parse_hypothesis_file(f)
        if e is not None:
            out.append(e)
    return out


def violations(entries: list[dict]) -> list[tuple[str, str]]:
    """Return list of (entry_label, human_readable_reason) for each violation."""
    out: list[tuple[str, str]] = []
    for e in entries:
        loc = f"{e['label']} ({rel(e['file'])})"
        reason = e.get("reason")
        if reason is None:
            out.append((loc, "missing Reason: field"))
            continue
        if reason == "evidence":
            if not e.get("evidence"):
                out.append((loc, "Reason: evidence but no Evidence: E<N> cited"))
        elif reason == "preference":
            prio = e.get("priority")
            rationale = e.get("rationale") or ""
            if not prio:
                out.append((loc, "Reason: preference but no Priority: field"))
            elif prio not in ALLOWED_PRIORITIES:
                out.append((
                    loc,
                    f"Priority: {prio!r} not in allowed set "
                    f"({', '.join(sorted(ALLOWED_PRIORITIES))})",
                ))
            if not rationale:
                out.append((loc, "Reason: preference but no Rationale: text"))
        else:
            out.append((loc, f"Reason: {reason!r} not one of {{evidence, preference}}"))
    return out


def main() -> int:
    ap = argparse.ArgumentParser(
        description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter
    )
    ap.add_argument("investigation_dir", help="path to investigations/<slug>/")
    ap.add_argument("--quiet", action="store_true", help="only print on failure")
    args = ap.parse_args()

    base = Path(args.investigation_dir)
    if not base.is_dir():
        print(f"error: {rel(base)} is not a directory", file=sys.stderr)
        return 2

    entries = collect_rejection_entries(base)

    if not entries:
        if not args.quiet:
            print(
                f"TC35 SKIP: no status-changed-to-rejected entries under "
                f"{rel(base / 'hypothesis')} — nothing to check"
            )
        return 0

    probs = violations(entries)
    if probs:
        print(f"TC35 FAIL: {len(probs)} rejection entr{'y' if len(probs)==1 else 'ies'} "
              f"missing or malformed:")
        for loc, msg in probs:
            print(f"  {loc}: {msg}")
        print()
        print("U2-doc requires every rejected hypothesis to document WHY:")
        print("  Reason: evidence   + Evidence: E<N>")
        print("  Reason: preference + Priority: <name> + Rationale: <text>")
        print(f"Allowed priorities: {', '.join(sorted(ALLOWED_PRIORITIES))}")
        return 1

    if not args.quiet:
        evidence_count = sum(1 for e in entries if e.get("reason") == "evidence")
        preference_count = sum(1 for e in entries if e.get("reason") == "preference")
        print(
            f"TC35 PASS: {len(entries)} rejection(s) properly documented "
            f"({evidence_count} evidence-based, {preference_count} preference-based)"
        )
    return 0


if __name__ == "__main__":
    sys.exit(main())
