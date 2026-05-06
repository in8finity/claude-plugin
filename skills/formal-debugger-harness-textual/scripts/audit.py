#!/usr/bin/env python3
"""audit.py — pre-acceptance summary check for a hashharness investigation.

Combines verify_chain (TC30 chain integrity) and check_rejection_reasons
(TC35 U2-doc) into a single concise summary. Talks to hashharness only via
MCP HTTP — no storage import.

Usage:
    audit.py <work_package_id>

Output (one line per check, exit 0 on full pass):
    items: <type counts>
    verify_chain: ok | FAIL <error>
    rejection_reasons: ok | FAIL <count violations>
"""
from __future__ import annotations

import argparse
import importlib.util
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent))
from _hh_common import mcp_call, parse_tool_json  # noqa: E402


def load_check_rejection_reasons():
    p = Path(__file__).parent / "check_rejection_reasons.py"
    spec = importlib.util.spec_from_file_location("crr", p)
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


def find_items_by_wp(work_package_id: str, limit: int = 200) -> list[dict]:
    result = mcp_call("find_items", {
        "query": work_package_id,
        "field": "work_package_id",
        "limit": limit,
    })
    payload = parse_tool_json(result)
    if isinstance(payload, list):
        return payload
    if isinstance(payload, dict) and "items" in payload:
        return payload["items"]
    return []


def verify_chain(text_sha256: str) -> dict:
    result = mcp_call("verify_chain", {"text_sha256": text_sha256, "summary": True})
    return parse_tool_json(result)


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("work_package_id")
    args = ap.parse_args()

    items = find_items_by_wp(args.work_package_id)
    if not items:
        print(f"audit: no items found under work_package_id={args.work_package_id!r}",
              file=sys.stderr)
        return 2

    type_counts: dict[str, int] = {}
    for it in items:
        type_counts[it["type"]] = type_counts.get(it["type"], 0) + 1
    print("items: " + ", ".join(f"{t}: {c}" for t, c in sorted(type_counts.items())))

    h_events = [it for it in items if it["type"] == "HypothesisEvent"]
    candidates = h_events if h_events else items
    tip = max(candidates, key=lambda it: it.get("created_at", ""))

    overall_ok = True
    try:
        result = verify_chain(tip["text_sha256"])
        if result.get("ok"):
            print(f"verify_chain: ok ({result.get('checked_items', 0)} items reachable from {tip['type']} {tip['text_sha256'][:12]}...)")
        else:
            errors = []
            for sub in result.get("items", []) or []:
                if not sub.get("ok"):
                    errors.append(f"{sub.get('type')} {sub.get('text_sha256','')[:12]}")
            print(f"verify_chain: FAIL — {len(errors)} item(s) failed: {', '.join(errors[:5])}")
            overall_ok = False
    except Exception as e:
        print(f"verify_chain: ERROR — {type(e).__name__}: {e}")
        overall_ok = False

    crr = load_check_rejection_reasons()
    rejections = [it for it in items if crr.is_rejection(it)]
    if not rejections:
        print("rejection_reasons: skip (no rejection events)")
    else:
        probs = crr.violations(items)
        if probs:
            print(f"rejection_reasons: FAIL — {len(probs)} violation(s)")
            for loc, msg in probs[:5]:
                print(f"  {loc}: {msg}")
            overall_ok = False
        else:
            ev = sum(1 for r in rejections
                     if crr.item_fields(r).get("reason", "").lower() == "evidence")
            pf = sum(1 for r in rejections
                     if crr.item_fields(r).get("reason", "").lower() == "preference")
            print(f"rejection_reasons: ok ({len(rejections)} documented: {ev} evidence, {pf} preference)")

    return 0 if overall_ok else 1


if __name__ == "__main__":
    try:
        sys.exit(main())
    except Exception as e:
        print(f"audit error: {type(e).__name__}: {e}", file=sys.stderr)
        sys.exit(2)
