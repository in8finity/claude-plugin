"""Smoke test for bash language support in closure_gates.

Mirrors test_closure_gates.py but against tests/fixtures/closure_gates_bash/.
Skips with a clear message if `bashlex` isn't installed (since it's an
optional dep — see references/enforcement-map.reference §"Closure gates").

Verifies:
  1. Exit non-zero (some sites are unguarded).
  2. 2 guarded sites in guarded.sh report as passing.
  3. 2 unguarded sites in unguarded.sh report as failing.
  4. The result of `result=$(append_claim ...)` is detected as a call site
     (command-substitution descent works).
"""

from __future__ import annotations

import json
import subprocess
import sys
from pathlib import Path

try:
    import bashlex  # noqa: F401
except ImportError:
    print("SKIP — bashlex not installed (optional dep)")
    sys.exit(0)


HERE = Path(__file__).parent
SCRIPT = HERE.parent / "scripts" / "check_enforcement.py"
FIXTURE = HERE / "fixtures" / "closure_gates_bash"


def main() -> int:
    proc = subprocess.run(
        [sys.executable, str(SCRIPT),
         str(FIXTURE / "enforcement.yaml"),
         "--project-root", str(FIXTURE),
         "--format", "json"],
        capture_output=True, text=True,
    )
    assert proc.returncode != 0, (
        f"expected non-zero exit, got {proc.returncode}\n"
        f"stdout:\n{proc.stdout}\nstderr:\n{proc.stderr}")

    payload = json.loads(proc.stdout)
    gates = payload["properties"][0]["gates"]

    passing = [g for g in gates if g["ok"]]
    failing = [g for g in gates if not g["ok"]]

    assert len(passing) == 2, f"expected 2 passing, got {len(passing)}: {passing}"
    assert len(failing) == 2, f"expected 2 failing, got {len(failing)}: {failing}"

    failing_files = {g["label"].split(":")[0] for g in failing}
    passing_files = {g["label"].split(":")[0] for g in passing}
    assert failing_files == {"scripts/unguarded.sh"}, failing_files
    assert passing_files == {"scripts/guarded.sh"}, passing_files

    # Specifically: pull_after_check uses `result=$(append_claim ...)` —
    # the call site must be discovered via command-substitution descent.
    assert any("pull_after_check" in g["label"] for g in failing), \
        f"expected pull_after_check in failing labels: {failing}"

    print("OK — bash closure_gates: 2 guarded sites pass, 2 unguarded sites fail")
    return 0


if __name__ == "__main__":
    sys.exit(main())
