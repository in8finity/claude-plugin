#!/usr/bin/env python3
"""record_model_change.py — create one ModelChange item via hashharness MCP HTTP.

Usage:
    record_model_change.py --work-package-id <wp> --model-id <id> --step <N>
                           --trigger <type> --solver-result <result>
                           --prev-model <hash> --parent-hyp-event <hash>
                           --title <title> --text <prose>
                           [--acknowledgement <text>]

For trigger=skip, --acknowledgement holds the user's verbatim affirmative reply.

Prints only the new item's text_sha256 on success.
"""
from __future__ import annotations

import argparse
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent))
from _hh_common import create_item  # noqa: E402

TRIGGERS = ["initial", "fact-integration", "deepening", "fix-verification", "skip"]
RESULTS = ["sat", "unsat", "timeout", "partial", "skipped"]


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--work-package-id", required=True)
    ap.add_argument("--model-id", required=True, help="e.g., M1, M2")
    ap.add_argument("--step", type=int, required=True,
                    help="step number this model change belongs to (1, 5, 7)")
    ap.add_argument("--trigger", required=True, choices=TRIGGERS)
    ap.add_argument("--solver-result", required=True, choices=RESULTS)
    ap.add_argument("--prev-model", required=True,
                    help="text_sha256 of previous M, or Report v1 for the first M")
    ap.add_argument("--parent-hyp-event", required=True,
                    help="text_sha256 of the H event that triggered this iteration")
    ap.add_argument("--title", required=True)
    ap.add_argument("--text", required=True,
                    help="what changed, optional embedded model snippets, observations")
    ap.add_argument("--acknowledgement", default="",
                    help="when --trigger=skip, the user's verbatim affirmative reply")
    args = ap.parse_args()

    if args.trigger == "skip" and not args.acknowledgement:
        print("error: --acknowledgement required when --trigger=skip", file=sys.stderr)
        return 1
    if args.trigger == "skip" and args.solver_result != "skipped":
        print("error: --solver-result must be 'skipped' when --trigger=skip", file=sys.stderr)
        return 1

    attrs = {
        "model_id": args.model_id,
        "step": args.step,
        "trigger": args.trigger,
        "solver_result": args.solver_result,
    }
    if args.acknowledgement:
        attrs["acknowledgement"] = args.acknowledgement

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
