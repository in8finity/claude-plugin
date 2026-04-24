#!/usr/bin/env python3
"""
now_iso.py — print the current UTC timestamp in ISO 8601 with ms precision.

Used for the `Timestamp:` field inside record files.

Output format: `2026-04-25T10:30:45.123Z`

Options:
  --filename   Output filename-safe variant (dashes replace both `:` and `.`).
               Example: `2026-04-25T10-30-45-123Z` — drop-in for filename suffix.

Usage:
    python3 scripts/now_iso.py
    python3 scripts/now_iso.py --filename
"""
import sys
from datetime import datetime, timezone


def main() -> int:
    filename_safe = "--filename" in sys.argv[1:]
    now = datetime.now(timezone.utc).isoformat(timespec="milliseconds")
    # datetime.isoformat gives 2026-04-25T10:30:45.123+00:00 — normalize to Z
    iso = now.replace("+00:00", "Z")
    if filename_safe:
        # dashes replace colons in time AND the decimal dot
        iso = iso.replace(":", "-").replace(".", "-")
    print(iso)
    return 0


if __name__ == "__main__":
    sys.exit(main())
