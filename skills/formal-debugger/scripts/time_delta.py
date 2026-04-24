#!/usr/bin/env python3
"""
time_delta.py — compute signed time delta between two ISO 8601 timestamps.

Prints the delta in seconds (with ms precision) as a signed float.

Usage:
    python3 scripts/time_delta.py <earlier> <later>
    # -> 12.345   (positive: later is 12.345s after earlier)

    python3 scripts/time_delta.py 2026-04-25T10:30:45.000Z 2026-04-25T10:30:50.500Z
    # -> 5.500

Accepts both canonical ISO 8601 (`...T10:30:45.123Z`) and filename-safe
form (`...T10-30-45-123Z`). Signed result: positive means arg2 is after
arg1; negative means before.

Useful for verifying Timestamp-vs-ctime agreement (60s tolerance), for
computing span between first and last record, and for sanity-checking
reported intervals.
"""
import re
import sys
from datetime import datetime, timezone


def parse_ts(s: str) -> datetime:
    # Support filename-safe form: YYYY-MM-DDTHH-MM-SS(-mmm)?Z
    m = re.match(
        r"^(\d{4}-\d{2}-\d{2})T(\d{2})-(\d{2})-(\d{2})(?:-(\d{3}))?Z$",
        s.strip(),
    )
    if m:
        base = f"{m.group(1)}T{m.group(2)}:{m.group(3)}:{m.group(4)}"
        if m.group(5):
            base += f".{m.group(5)}"
        base += "+00:00"
        return datetime.fromisoformat(base).astimezone(timezone.utc)
    # Canonical ISO with Z or +00:00
    try:
        return datetime.fromisoformat(s.strip().replace("Z", "+00:00")).astimezone(timezone.utc)
    except ValueError as e:
        raise ValueError(f"not a valid ISO timestamp: {s!r}") from e


def main() -> int:
    if len(sys.argv) != 3:
        print("usage: time_delta.py <earlier-iso> <later-iso>", file=sys.stderr)
        return 2
    try:
        t1 = parse_ts(sys.argv[1])
        t2 = parse_ts(sys.argv[2])
    except ValueError as e:
        print(f"error: {e}", file=sys.stderr)
        return 2
    delta = (t2 - t1).total_seconds()
    print(f"{delta:.3f}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
