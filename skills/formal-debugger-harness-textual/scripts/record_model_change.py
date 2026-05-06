#!/usr/bin/env python3
"""record_model_change.py — create one ModelChange item via hashharness MCP HTTP.

Usage:
    record_model_change.py --work-package-id <wp> --model-id <id> --step <N>
                           --trigger <type>
                           --menu-kinds <kind>[,<kind>...]
                           --walkthrough-summary "<pass=N, fail=N, pending=N, n/a=N>"
                           --prev-model <hash> --parent-hyp-event <hash>
                           --title <title> --text <prose>
                           [--acknowledgement <text>]

For trigger=skip, --acknowledgement holds the user's verbatim affirmative reply
and replaces --menu-kinds / --walkthrough-summary (which must be omitted).

Prints only the new item's text_sha256 on success.
"""
from __future__ import annotations

import argparse
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent))
from _hh_common import create_item  # noqa: E402

TRIGGERS = ["initial", "fact-integration", "deepening", "fix-verification", "skip"]
MENU_KINDS = [
    "state-machine",
    "sequence-diagram",
    "dag",
    "schema",
    "decision-table",
    "invariant-table",
    "type-taxonomy",
    "worked-example",
]


def parse_menu_kinds(raw: str) -> list[str]:
    kinds = [k.strip() for k in raw.split(",") if k.strip()]
    bad = [k for k in kinds if k not in MENU_KINDS]
    if bad:
        raise SystemExit(
            f"error: unknown menu kind(s): {bad}. Valid: {MENU_KINDS}"
        )
    if not kinds:
        raise SystemExit("error: --menu-kinds must list ≥1 kind")
    return kinds


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--work-package-id", required=True)
    ap.add_argument("--model-id", required=True, help="e.g., M1, M2")
    ap.add_argument("--step", type=int, required=True,
                    help="step number this model change belongs to (1, 5, 7)")
    ap.add_argument("--trigger", required=True, choices=TRIGGERS)
    ap.add_argument("--menu-kinds", default="",
                    help="comma-separated list from references/representation-menu.md "
                         f"(values: {','.join(MENU_KINDS)})")
    ap.add_argument("--walkthrough-summary", default="",
                    help='counts e.g. "pass=3, fail=0, pending=2, n/a=1"')
    ap.add_argument("--prev-model", required=True,
                    help="text_sha256 of previous M, or Report v1 for the first M")
    ap.add_argument("--parent-hyp-event", required=True,
                    help="text_sha256 of the H event that triggered this iteration")
    ap.add_argument("--title", required=True)
    ap.add_argument("--text", required=True,
                    help="what changed, optional embedded model snippets, "
                         "row-by-row hand walkthrough against current evidence")
    ap.add_argument("--acknowledgement", default="",
                    help="when --trigger=skip, the user's verbatim affirmative reply")
    args = ap.parse_args()

    if args.trigger == "skip":
        if not args.acknowledgement:
            print("error: --acknowledgement required when --trigger=skip", file=sys.stderr)
            return 1
        if args.menu_kinds or args.walkthrough_summary:
            print("error: --menu-kinds and --walkthrough-summary must be omitted "
                  "when --trigger=skip", file=sys.stderr)
            return 1
    else:
        if not args.menu_kinds:
            print("error: --menu-kinds required when --trigger != skip", file=sys.stderr)
            return 1
        if not args.walkthrough_summary:
            print("error: --walkthrough-summary required when --trigger != skip",
                  file=sys.stderr)
            return 1

    attrs: dict[str, object] = {
        "model_id": args.model_id,
        "step": args.step,
        "trigger": args.trigger,
    }
    if args.trigger == "skip":
        attrs["acknowledgement"] = args.acknowledgement
    else:
        attrs["menu_kinds"] = parse_menu_kinds(args.menu_kinds)
        attrs["walkthrough_summary"] = args.walkthrough_summary

    sha = create_item(
        item_type="ModelChange",
        work_package_id=args.work_package_id,
        title=args.title,
        text=args.text,
        links={"prevModel": args.prev_model, "parentHypEvent": args.parent_hyp_event},
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
