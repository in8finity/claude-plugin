"""Regression test for the retry-loop fairness worked example.

The example demonstrates the deterministic-collision class behind the
hashharness-pm 0.6.4 starvation: two workers sharing a runnable view
sort by `(ctx.priority, createdAt)` identically, so without a skip-set
they pick the SAME first-by-sort task, leaving siblings unworked. With
a skip-set, the loser-of-CAS shifts to the next task and progress is made.

Expected verdicts:
  - BuggyPreventsCollision  → COUNTEREXAMPLE FOUND
  - FixedPreventsCollision  → assertion holds

If either flips, the example is silently teaching the wrong lesson.
"""

from __future__ import annotations

import subprocess
import sys
from pathlib import Path


HERE = Path(__file__).parent
SKILL = HERE.parent
MODEL = SKILL / "references" / "retry-loop-example.als"
RUNNER = SKILL / "scripts" / "alloy_run.sh"


def main() -> int:
    if not MODEL.exists():
        print(f"FAIL — model not found: {MODEL}")
        return 1
    proc = subprocess.run(
        ["bash", str(RUNNER), str(MODEL)],
        capture_output=True, text=True, timeout=300,
    )
    if proc.returncode != 0:
        print(f"FAIL — alloy_run.sh exit {proc.returncode}\n"
              f"stderr:\n{proc.stderr[-2000:]}")
        return 1

    out = proc.stdout
    counterexamples = out.count("COUNTEREXAMPLE FOUND")
    holds = out.count("assertion holds")

    if counterexamples != 1:
        print(f"FAIL — expected 1 COUNTEREXAMPLE FOUND (buggy), "
              f"got {counterexamples}\n--- output tail ---\n{out[-3000:]}")
        return 1
    if holds != 1:
        print(f"FAIL — expected 1 'assertion holds' (fixed), "
              f"got {holds}\n--- output tail ---\n{out[-3000:]}")
        return 1
    if "BuggyPreventsCollision" not in out:
        print("FAIL — missing 'BuggyPreventsCollision' in output")
        return 1
    if "FixedPreventsCollision" not in out:
        print("FAIL — missing 'FixedPreventsCollision' in output")
        return 1

    print("OK — retry-loop example: 1 counterexample (buggy collision), "
          "1 holds (fixed with skip-set)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
