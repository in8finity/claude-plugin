#!/usr/bin/env python3
"""record_report.py — create one Report item via hashharness MCP HTTP.

Usage:
    record_report.py --work-package-id <wp> --version <N> --step <step>
                     --severity <level> --title <title> --text <prose>
                     [--prev-report <hash>]

Setup: run hashharness as HTTP server (HASHHARNESS_MCP_TRANSPORT=http) and
set HASHHARNESS_HTTP_URL if not on the default port. See _hh_common.py.

Prints only the new item's text_sha256 on success.
"""
from __future__ import annotations

import argparse
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent))
from _hh_common import create_item  # noqa: E402


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--work-package-id", required=True)
    ap.add_argument("--version", type=int, required=True)
    ap.add_argument("--step", required=True,
                    help="step at which this report version was made (0, 0b, 4, 7, 8)")
    ap.add_argument("--severity", required=True,
                    choices=["security-critical", "business-critical",
                             "data-integrity-critical", "normal"])
    ap.add_argument("--title", required=True)
    ap.add_argument("--text", required=True, help="narrative prose")
    ap.add_argument("--prev-report", default=None,
                    help="text_sha256 of the previous Report (omit for v1)")
    args = ap.parse_args()

    if args.version == 1 and args.prev_report:
        print("error: Report v1 must not have --prev-report", file=sys.stderr)
        return 1
    if args.version >= 2 and not args.prev_report:
        print(f"error: Report v{args.version} requires --prev-report", file=sys.stderr)
        return 1

    sha = create_item(
        item_type="Report",
        work_package_id=args.work_package_id,
        title=args.title,
        text=args.text,
        links={"prevReport": args.prev_report} if args.prev_report else None,
        attributes={
            "version": args.version,
            "step": args.step,
            "severity": args.severity,
        },
    )
    print(sha)
    return 0


if __name__ == "__main__":
    try:
        sys.exit(main())
    except Exception as e:
        print(f"error: {type(e).__name__}: {e}", file=sys.stderr)
        sys.exit(1)
