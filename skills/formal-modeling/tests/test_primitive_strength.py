"""Regression test for the primitive-strength worked example.

The example demonstrates the TOCTOU gap between an abstract model
precondition and a CAS-on-pointer primitive. If either verdict flips,
the example is silently teaching the wrong lesson — fail loudly here
so we notice on every release.

Expected:
  - BuggyCallerEnforcesPrecondition → COUNTEREXAMPLE FOUND
  - FixedCallerEnforcesPrecondition → assertion holds
"""

from __future__ import annotations

import subprocess
import sys
from pathlib import Path


HERE = Path(__file__).parent
SKILL = HERE.parent
MODEL = SKILL / "references" / "primitive-strength-example.als"
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
        print(f"FAIL — expected 1 COUNTEREXAMPLE FOUND (the buggy caller), "
              f"got {counterexamples}\n--- output tail ---\n{out[-3000:]}")
        return 1
    if holds != 1:
        print(f"FAIL — expected 1 'assertion holds' (the fixed caller), "
              f"got {holds}\n--- output tail ---\n{out[-3000:]}")
        return 1

    # Sanity — the right assertions, not just the right counts.
    if "BuggyCallerEnforcesPrecondition" not in out:
        print("FAIL — missing 'BuggyCallerEnforcesPrecondition' in output")
        return 1
    if "FixedCallerEnforcesPrecondition" not in out:
        print("FAIL — missing 'FixedCallerEnforcesPrecondition' in output")
        return 1

    print("OK — primitive-strength example: "
          "1 counterexample (buggy), 1 holds (fixed)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
