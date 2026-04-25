#!/usr/bin/env python3
"""materialize.py — render hashharness items as human-readable markdown logs.

Implements the Materialization Protocol from SKILL.md. Calls
`mcp__hashharness__get_work_package` (via MCP HTTP) to fetch all items for
one work_package_id, sorts them by created_at (tie-break by stored_at then
text_sha256), and writes four derived markdown files:

  <output-dir>/investigation-report.md
  <output-dir>/evidence-log.md
  <output-dir>/hypothesis-log.md
  <output-dir>/model-change-log.md

These files are rewritten from scratch each time materialize.py runs — they
are derived views of the hashharness store, not append-only records. The
hashharness items remain the source of truth.

Usage:
    materialize.py <work_package_id> <output-dir>

Setup: hashharness HTTP MCP server must be reachable at HASHHARNESS_HTTP_URL
(default http://127.0.0.1:8765/mcp). See _hh_common.py.
"""
from __future__ import annotations

import argparse
import sys
from datetime import datetime, timezone
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent))
from _hh_common import mcp_call, parse_tool_json  # noqa: E402


def fetch_work_package(work_package_id: str) -> list[dict]:
    """Call get_work_package via MCP HTTP. Returns the items list."""
    try:
        result = mcp_call("get_work_package", {"work_package_id": work_package_id})
    except RuntimeError:
        # Fallback: find_items by work_package_id (in case server is older)
        result = mcp_call("find_items", {
            "query": work_package_id,
            "field": "work_package_id",
            "limit": 1000,
        })
    payload = parse_tool_json(result)
    if isinstance(payload, list):
        return payload
    if isinstance(payload, dict):
        return payload.get("items", [])
    return []


def sort_key(item: dict) -> tuple:
    return (item.get("created_at", ""),
            item.get("stored_at", ""),
            item.get("text_sha256", ""))


def header(work_package_id: str) -> str:
    now = datetime.now(timezone.utc).isoformat(timespec="seconds").replace("+00:00", "Z")
    return (
        f"<!-- Generated from hashharness via get_work_package -->\n"
        f"<!-- Work package: {work_package_id} -->\n"
        f"<!-- Generated at: {now} -->\n"
        f"<!-- Source of truth: hashharness items; this file is a derived view -->\n\n"
    )


def fmt_links(links: dict | None) -> str:
    if not links:
        return ""
    lines = []
    for k in ("prevHyp", "prevReport", "prevModel", "parentHypEvent", "supersedes"):
        v = (links or {}).get(k)
        if isinstance(v, str):
            lines.append(f"- {k}: `{v[:16]}…`")
    cited = (links or {}).get("citedEvidence")
    if isinstance(cited, list) and cited:
        short = ", ".join(f"`{h[:16]}…`" for h in cited)
        lines.append(f"- citedEvidence: [{short}]")
        cited_hash = (links or {}).get("citedEvidenceHash")
        if cited_hash:
            lines.append(f"- citedEvidenceHash: `{cited_hash[:16]}…`")
    return "\n".join(lines) + ("\n" if lines else "")


def fmt_attributes(attrs: dict | None) -> str:
    if not attrs:
        return ""
    lines = [f"- {k}: `{v}`" for k, v in attrs.items()]
    return "\n".join(lines) + ("\n" if lines else "")


def render_item_block(item: dict) -> str:
    title = item.get("title", "(no title)")
    sha = item.get("text_sha256", "")
    created = item.get("created_at", "")
    text = item.get("text", "").rstrip()
    parts = [
        f"### {title}",
        f"- text_sha256: `{sha}`",
        f"- created_at: {created}",
    ]
    attrs_md = fmt_attributes(item.get("attributes"))
    if attrs_md:
        parts.append("**attributes:**\n" + attrs_md.rstrip())
    links_md = fmt_links(item.get("links"))
    if links_md:
        parts.append("**links:**\n" + links_md.rstrip())
    if text:
        parts.append("**text:**\n```\n" + text + "\n```")
    return "\n\n".join(parts) + "\n\n---\n\n"


def write_section(path: Path, work_package_id: str, title: str,
                  items: list[dict]) -> None:
    body = header(work_package_id) + f"# {title}\n\n"
    if not items:
        body += "_No items of this type yet._\n"
    else:
        for it in items:
            body += render_item_block(it)
    path.write_text(body, encoding="utf-8")


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("work_package_id")
    ap.add_argument("output_dir")
    args = ap.parse_args()

    out = Path(args.output_dir)
    out.mkdir(parents=True, exist_ok=True)

    items = fetch_work_package(args.work_package_id)
    if not items:
        print(f"materialize: no items found for {args.work_package_id!r}",
              file=sys.stderr)
        return 1

    items.sort(key=sort_key)
    by_type: dict[str, list[dict]] = {}
    for it in items:
        by_type.setdefault(it.get("type", "?"), []).append(it)

    write_section(out / "investigation-report.md", args.work_package_id,
                  "Investigation Report (chain of Report items)",
                  by_type.get("Report", []))
    write_section(out / "evidence-log.md", args.work_package_id,
                  "Evidence Log",
                  by_type.get("Evidence", []))
    write_section(out / "hypothesis-log.md", args.work_package_id,
                  "Hypothesis Log",
                  by_type.get("HypothesisEvent", []))
    write_section(out / "model-change-log.md", args.work_package_id,
                  "Model Change Log",
                  by_type.get("ModelChange", []))

    type_counts = ", ".join(f"{t}: {len(by_type.get(t, []))}"
                            for t in ("Report", "HypothesisEvent", "Evidence", "ModelChange"))
    print(f"materialized 4 files at {out} ({type_counts})")
    return 0


if __name__ == "__main__":
    try:
        sys.exit(main())
    except Exception as e:
        print(f"materialize error: {type(e).__name__}: {e}", file=sys.stderr)
        sys.exit(1)
