"""Smoke test for closure_gates support in check_enforcement.py.

Runs the checker against tests/fixtures/closure_gates/ which contains:
  - skills/guarded.py    — two functions, both call append_claim AFTER
                           check_sticky_eligibility (must pass).
  - skills/unguarded.py  — one function calls append_claim with no gate;
                           one calls the gate AFTER (still ungated).
                           Both call sites must fail.

Verifies:
  1. Exit code is non-zero (overall fail).
  2. Two unguarded sites are reported as failing GateResults.
  3. Two guarded sites are reported as passing GateResults.
  4. The label includes file:line and the enclosing function name.

No pytest dependency — run directly: python tests/test_closure_gates.py
"""

from __future__ import annotations

import json
import subprocess
import sys
from pathlib import Path


HERE = Path(__file__).parent
SCRIPT = HERE.parent / "scripts" / "check_enforcement.py"
FIXTURE = HERE / "fixtures" / "closure_gates"


def main() -> int:
    proc = subprocess.run(
        [sys.executable, str(SCRIPT),
         str(FIXTURE / "enforcement.yaml"),
         "--project-root", str(FIXTURE),
         "--format", "json"],
        capture_output=True, text=True,
    )

    # Overall exit non-zero (some closure sites are unguarded).
    assert proc.returncode != 0, (
        f"expected non-zero exit, got {proc.returncode}\n"
        f"stdout:\n{proc.stdout}\nstderr:\n{proc.stderr}")

    payload = json.loads(proc.stdout)
    assert len(payload["properties"]) == 1
    gates = payload["properties"][0]["gates"]

    passing = [g for g in gates if g["ok"]]
    failing = [g for g in gates if not g["ok"]]

    # 2 guarded call sites in guarded.py
    assert len(passing) == 2, f"expected 2 passing, got {len(passing)}: {passing}"
    # 2 unguarded call sites in unguarded.py
    assert len(failing) == 2, f"expected 2 failing, got {len(failing)}: {failing}"

    # Labels must carry file:line + enclosing function.
    for g in gates:
        assert "store.append_claim" in g["label"], g
        assert "()" in g["label"], g  # `funcname()` appears
        assert ":" in g["label"], g   # `path:line` appears

    failing_files = {g["label"].split(":")[0] for g in failing}
    passing_files = {g["label"].split(":")[0] for g in passing}
    assert failing_files == {"skills/unguarded.py"}, failing_files
    assert passing_files == {"skills/guarded.py"}, passing_files

    print("OK — closure_gates: 2 guarded sites pass, 2 unguarded sites fail")
    return 0


if __name__ == "__main__":
    sys.exit(main())
