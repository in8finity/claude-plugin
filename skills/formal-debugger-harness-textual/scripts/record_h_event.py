#!/usr/bin/env python3
"""record_h_event.py — create one HypothesisEvent item via hashharness MCP HTTP.

Usage:
    record_h_event.py --work-package-id <wp> --event <type> --hypothesis-id <id>
                      --event-seq <N> --prev-hyp <hash> --title <title>
                      --text <prose>
                      [--cited-evidence <h1,h2,...>]
                      [--supersedes <hash>]
                      [--new-status <status>]
                      [--reason <evidence|preference>]
                      [--priority <name>]
                      [--rationale <text>]

For status-changed / accepted events: include --cited-evidence and --reason.
For reason=preference, also include --priority and --rationale.

To repair a broken state-change, include --supersedes.

Prints only the new item's text_sha256 on success.
"""
from __future__ import annotations

import argparse
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent))
from _hh_common import create_item  # noqa: E402

EVENT_TYPES = [
    "symptom-claimed", "created", "mechanism-stated", "counterfactual-stated",
    "observability-assessed", "alternative-considered", "status-changed",
    "equivalence-checked", "accepted",
]
NEW_STATUSES = ["compatible", "weakened", "rejected", "undistinguished", "accepted"]
REASONS = ["evidence", "preference"]
ALLOWED_PRIORITIES = [
    "Occam", "BlastRadius", "Severity", "RecencyOfDeploy",
    "Reproducibility", "FixCost",
]


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--work-package-id", required=True)
    ap.add_argument("--event", required=True, choices=EVENT_TYPES)
    ap.add_argument("--hypothesis-id", required=True,
                    help="e.g., H0, H1, H2 — the hypothesis this event belongs to")
    ap.add_argument("--event-seq", type=int, required=True,
                    help="sequence number of this event within the hypothesis lifecycle")
    ap.add_argument("--prev-hyp", required=True,
                    help="text_sha256 of the previous H event (or Report v1 for H0-1)")
    ap.add_argument("--title", required=True)
    ap.add_argument("--text", required=True, help="prose content of the event")
    ap.add_argument("--cited-evidence", default="",
                    help="comma-separated text_sha256 list (state-change events only)")
    ap.add_argument("--supersedes", default="")
    ap.add_argument("--new-status", default="", choices=[""] + NEW_STATUSES)
    ap.add_argument("--reason", default="", choices=[""] + REASONS)
    ap.add_argument("--priority", default="", choices=[""] + ALLOWED_PRIORITIES)
    ap.add_argument("--rationale", default="")
    args = ap.parse_args()

    is_state_change = args.event in ("status-changed", "accepted")
    if is_state_change:
        if args.event == "status-changed" and not args.new_status:
            print("error: --new-status required when --event=status-changed", file=sys.stderr)
            return 1
        if args.new_status == "rejected" and not args.reason:
            print("error: --reason required for status-changed=rejected (evidence|preference)",
                  file=sys.stderr)
            return 1
        if args.reason == "preference":
            if not args.priority:
                print("error: --priority required when --reason=preference", file=sys.stderr)
                return 1
            if not args.rationale:
                print("error: --rationale required when --reason=preference", file=sys.stderr)
                return 1
        if args.reason == "evidence" and not args.cited_evidence:
            print("error: --cited-evidence required when --reason=evidence", file=sys.stderr)
            return 1

    attrs: dict = {
        "event": args.event,
        "hypothesis_id": args.hypothesis_id,
        "event_seq": args.event_seq,
    }
    for key, val in [("new_status", args.new_status), ("reason", args.reason),
                     ("priority", args.priority), ("rationale", args.rationale)]:
        if val:
            attrs[key] = val

    links: dict = {"prevHyp": args.prev_hyp}
    if args.cited_evidence:
        links["citedEvidence"] = [h.strip() for h in args.cited_evidence.split(",") if h.strip()]
    if args.supersedes:
        links["supersedes"] = args.supersedes

    sha = create_item(
        item_type="HypothesisEvent",
        work_package_id=args.work_package_id,
        title=args.title,
        text=args.text,
        links=links,
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
