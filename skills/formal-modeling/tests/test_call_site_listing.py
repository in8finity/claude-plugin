"""Smoke test for --list-call-sites (Extension 3 sub-bullet).

Reuses the python closure_gates fixture, which now declares two
`protected_primitives`:
  - store.append_claim — audited (closure_gates targets it)
  - store.check_sticky_eligibility — dangling (no closure_gates entry)

Verifies:
  1. JSON payload contains a `protected_primitives` array of length 2.
  2. The audited primitive enumerates 4 call sites across 2 files.
  3. The dangling primitive is flagged audited=false.
  4. Each site carries file, line, and enclosing scope.
  5. Exit code is governed by the closure_gates check (failures unrelated
     to the listing flag), proving --list-call-sites is informational.
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
         "--list-call-sites",
         "--format", "json"],
        capture_output=True, text=True,
    )
    payload = json.loads(proc.stdout)

    listings = payload.get("protected_primitives")
    assert isinstance(listings, list), \
        f"expected protected_primitives list, got: {type(listings)}"
    assert len(listings) == 2, f"expected 2 primitives, got {len(listings)}"

    by_name = {L["name"]: L for L in listings}

    # Audited primitive — closure_gates targets it.
    ap = by_name["store.append_claim"]
    assert ap["audited"] is True, ap
    assert ap["language"] == "python", ap
    assert len(ap["sites"]) == 4, f"expected 4 sites, got {len(ap['sites'])}"
    files = {s["file"] for s in ap["sites"]}
    assert files == {"skills/guarded.py", "skills/unguarded.py"}, files
    scopes = {s["scope"] for s in ap["sites"]}
    assert scopes == {"claim_one", "claim_two", "pull", "pull_after_check"}, scopes

    # Dangling primitive — no closure_gates entry targets it.
    cse = by_name["store.check_sticky_eligibility"]
    assert cse["audited"] is False, cse
    assert len(cse["sites"]) >= 1, cse  # at least one call exists in fixtures

    # The flag is informational — failures here come from the closure_gates
    # property, not the listing. Sanity-check that.
    assert proc.returncode == 1, proc.returncode
    assert payload["passed"] == 0 and payload["total"] == 1

    print(f"OK — call-site listing: {len(listings)} primitives "
          f"({sum(1 for L in listings if L['audited'])} audited, "
          f"{sum(1 for L in listings if not L['audited'])} dangling)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
