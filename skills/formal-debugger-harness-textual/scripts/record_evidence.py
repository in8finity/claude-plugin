#!/usr/bin/env python3
"""record_evidence.py — create one Evidence item via hashharness MCP HTTP.

Usage:
    record_evidence.py --work-package-id <wp> --evidence-id <id>
                       --source <source-name> --reliability <tag>
                       --parent-hyp-event <hash> --title <title> --text <prose>
                       [--absence-sources <N/M>] [--verdict <text>]
                       [--analysis-type <type>] [--producer-identified <yes|no>]
                       [--computation-method <method>] [--residual <pct-string>]
                       [--field-temporality <live|snapshot|scheduled>]
                       [--last-written <iso>]

Audit fields F6-F9 are optional and only included when applicable.

Prints only the new item's text_sha256 on success.
"""
from __future__ import annotations

import argparse
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent))
from _hh_common import create_item  # noqa: E402

RELIABILITIES = ["direct", "inferred", "interpreted", "unreliable-source"]


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--work-package-id", required=True)
    ap.add_argument("--evidence-id", required=True, help="e.g., E1, E2, E3")
    ap.add_argument("--source", required=True,
                    help="source identifier (e.g., 'production-db', 'datadog', "
                         "'live-api', 'repo-code', 'spec-doc', 'user-report')")
    ap.add_argument("--reliability", required=True, choices=RELIABILITIES)
    ap.add_argument("--parent-hyp-event", required=True,
                    help="text_sha256 of the H event this evidence serves")
    ap.add_argument("--title", required=True)
    ap.add_argument("--text", required=True, help="the actual observation prose")
    ap.add_argument("--absence-sources", default="", help="F6: queried/total format")
    ap.add_argument("--verdict", default="", help="F6: absence verdict in prose")
    ap.add_argument("--analysis-type", default="",
                    help="F7: 'write-path' or 'read-path'")
    ap.add_argument("--producer-identified", default="", help="F7: yes or no")
    ap.add_argument("--computation-method", default="",
                    help="F8: 'exact-local' or 'estimate' or other")
    ap.add_argument("--residual", default="", help="F8: residual percent string")
    ap.add_argument("--field-temporality", default="",
                    choices=["", "live", "snapshot", "scheduled"])
    ap.add_argument("--last-written", default="",
                    help="F9: ISO 8601 timestamp of last write to this field")
    args = ap.parse_args()

    attrs = {
        "evidence_id": args.evidence_id,
        "source": args.source,
        "reliability": args.reliability,
    }
    optional = [
        ("absence_sources", args.absence_sources),
        ("verdict", args.verdict),
        ("analysis_type", args.analysis_type),
        ("producer_identified", args.producer_identified),
        ("computation_method", args.computation_method),
        ("residual", args.residual),
        ("field_temporality", args.field_temporality),
        ("last_written", args.last_written),
    ]
    for k, v in optional:
        if v:
            attrs[k] = v

    sha = create_item(
        item_type="Evidence",
        work_package_id=args.work_package_id,
        title=args.title,
        text=args.text,
        links={"parentHypEvent": args.parent_hyp_event},
        attributes=attrs,
    )
    print(sha)
    return 0


if __name__ == "__main__":
    try:
        sys.exit(main())
    except Exception as e:
        print(f"error: {type(e).__name__}: {e}", file=sys.stderr)
        sys.exit(1)
