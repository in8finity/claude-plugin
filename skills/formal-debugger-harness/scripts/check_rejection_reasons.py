#!/usr/bin/env python3
"""
check_rejection_reasons.py — TC35/U2-doc enforcement (hashharness variant).

Queries the hashharness data store for HypothesisEvent items in a given
`work_package_id` and validates that every status-changed-to-rejected
event documents its rejection per U2-doc:

  reason=evidence     +  citedEvidence link non-empty
  reason=preference   +  priority=<allowed name>  +  rationale=<non-empty>

The rejection schema lives in the item's `attributes` dict (a structured
JSON object stored on the item alongside `text` and `links`). For backward
compatibility, the script also accepts the legacy form where the same
fields are encoded as semicolon-separated key=value pairs in the `text`.

Allowed priorities: Occam, BlastRadius, Severity, RecencyOfDeploy,
Reproducibility, FixCost.

Usage:
    check_rejection_reasons.py <work_package_id>

Talks to hashharness only via MCP HTTP — see _hh_common.py for setup.
HASHHARNESS_HTTP_URL controls the server endpoint.

Exit 0 = pass, 1 = fail, 2 = usage / MCP error.
"""
from __future__ import annotations

import argparse
import re
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent))
from _hh_common import mcp_call, parse_tool_json  # noqa: E402

ALLOWED_PRIORITIES = {
    "Occam",
    "BlastRadius",
    "Severity",
    "RecencyOfDeploy",
    "Reproducibility",
    "FixCost",
}

KV_LINE_RE = re.compile(r"^\s*([A-Za-z_][A-Za-z0-9_]*)\s*[=:]\s*(.+?)\s*$")


def parse_text_kvs(text: str) -> dict[str, str]:
    """Parse `Key: value` or `key=value` pairs, one per line, from a text field
    (legacy form). Values may contain internal punctuation (semicolons, etc.)
    and run to end-of-line. Last value wins on duplicate keys. Keys are
    lowercased.

    The `attributes` field on the item is the canonical home for structured
    values; this parser is a fallback for items written before `attributes`
    was introduced. Going forward, prefer attributes — they are JSON-typed,
    integrity-bound to meta_sha256, and don't require text parsing.
    """
    out: dict[str, str] = {}
    for line in text.splitlines():
        m = KV_LINE_RE.match(line)
        if m:
            out[m.group(1).lower()] = m.group(2).strip()
    return out


def item_fields(item: dict) -> dict[str, str]:
    """Return a flat dict of normalized lowercase keys from `attributes` first,
    falling back to legacy text-encoded key=value pairs.

    `attributes` (the hashharness structured field) is preferred — it is a
    proper JSON dict, integrity-bound to meta_sha256, and not parsed from
    free-form text. Items written before the attributes field was introduced
    fall back to the legacy text encoding.
    """
    attrs = item.get("attributes") or {}
    if isinstance(attrs, dict) and attrs:
        return {str(k).lower(): str(v) for k, v in attrs.items()}
    return parse_text_kvs(item.get("text", ""))


def is_rejection(item: dict) -> bool:
    """True iff the item is a state-change-to-rejected HypothesisEvent."""
    if item.get("type") != "HypothesisEvent":
        return False
    kvs = item_fields(item)
    return (
        kvs.get("event") == "status-changed"
        and kvs.get("new_status") == "rejected"
    )


def cited_evidence_count(item: dict) -> int:
    """Number of evidence items cited by this state-change."""
    links = item.get("links", {}) or {}
    cited = links.get("citedEvidence")
    if isinstance(cited, list):
        return len(cited)
    return 0


def short_id(item: dict) -> str:
    """Short identifier for an item for human-readable error messages."""
    return f"{item.get('type','?')} {item.get('text_sha256','?')[:12]}... ({item.get('title') or ''})".strip()


def violations(items: list[dict]) -> list[tuple[str, str]]:
    """Return list of (short_id, human-readable problem) for each violation."""
    out: list[tuple[str, str]] = []
    for it in items:
        if not is_rejection(it):
            continue
        kvs = item_fields(it)
        loc = short_id(it)
        reason = kvs.get("reason")
        if reason is None:
            out.append((loc, "missing reason field (must be 'evidence' or 'preference')"))
            continue
        reason = reason.lower()
        if reason == "evidence":
            if cited_evidence_count(it) == 0:
                out.append((loc, "reason=evidence but citedEvidence link is empty/missing"))
        elif reason == "preference":
            prio = kvs.get("priority")
            rationale = kvs.get("rationale") or ""
            if not prio:
                out.append((loc, "reason=preference but no priority field"))
            elif prio not in ALLOWED_PRIORITIES:
                out.append((
                    loc,
                    f"priority={prio!r} not in allowed set "
                    f"({', '.join(sorted(ALLOWED_PRIORITIES))})",
                ))
            if not rationale:
                out.append((loc, "reason=preference but rationale field is missing or empty"))
        else:
            out.append((loc, f"reason={reason!r} not one of {{evidence, preference}}"))
    return out


def main() -> int:
    ap = argparse.ArgumentParser(
        description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter
    )
    ap.add_argument("work_package_id", help="the work_package_id of the investigation to audit")
    ap.add_argument("--quiet", action="store_true", help="only print on failure")
    args = ap.parse_args()

    try:
        result = mcp_call("find_items", {
            "query": args.work_package_id,
            "field": "work_package_id",
            "limit": 200,
        })
        payload = parse_tool_json(result)
        if isinstance(payload, list):
            items = payload
        elif isinstance(payload, dict) and "items" in payload:
            items = payload["items"]
        else:
            items = []
    except Exception as e:
        print(f"error: hashharness MCP query failed: {type(e).__name__}: {e}", file=sys.stderr)
        return 2

    rejections = [it for it in items if is_rejection(it)]
    if not rejections:
        if not args.quiet:
            print(
                f"TC35 SKIP: no rejection events under work_package_id="
                f"{args.work_package_id!r} — nothing to check"
            )
        return 0

    probs = violations(items)
    if probs:
        plural = "y" if len(probs) == 1 else "ies"
        print(
            f"TC35 FAIL: {len(probs)} rejection entr{plural} "
            f"missing or malformed in {args.work_package_id!r}:"
        )
        for loc, msg in probs:
            print(f"  {loc}: {msg}")
        print()
        print("U2-doc requires every rejection to document WHY:")
        print("  reason=evidence   + non-empty citedEvidence link")
        print("  reason=preference + priority=<name> + rationale=<text>")
        print(f"Allowed priorities: {', '.join(sorted(ALLOWED_PRIORITIES))}")
        return 1

    evidence_count = sum(
        1 for it in rejections
        if item_fields(it).get("reason", "").lower() == "evidence"
    )
    pref_count = sum(
        1 for it in rejections
        if item_fields(it).get("reason", "").lower() == "preference"
    )
    if not args.quiet:
        print(
            f"TC35 PASS: {len(rejections)} rejection(s) properly documented "
            f"({evidence_count} evidence-based, {pref_count} preference-based) "
            f"under work_package_id={args.work_package_id!r}"
        )
    return 0


if __name__ == "__main__":
    sys.exit(main())
