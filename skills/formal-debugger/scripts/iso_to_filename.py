#!/usr/bin/env python3
"""
iso_to_filename.py — convert an ISO 8601 timestamp to filename-safe form.

Takes `2026-04-25T10:30:45.123Z` on stdin or as argv[1], prints
`2026-04-25T10-30-45-123Z`. Inverse direction (filename → ISO) is also
available via --reverse.

Used to keep filename suffix and in-field `Timestamp:` in sync.

Usage:
    python3 scripts/iso_to_filename.py 2026-04-25T10:30:45.123Z
    echo 2026-04-25T10:30:45.123Z | python3 scripts/iso_to_filename.py
    python3 scripts/iso_to_filename.py --reverse 2026-04-25T10-30-45-123Z

When --reverse is given, the script converts filename-safe form back to
canonical ISO 8601 (colons and decimal dot restored). This is useful when
grepping filenames and needing to compute offsets or compare to in-field
values.
"""
import re
import sys


def filename_to_iso(s: str) -> str:
    # Pattern: YYYY-MM-DDTHH-MM-SS-mmmZ -> YYYY-MM-DDTHH:MM:SS.mmmZ
    m = re.match(r"^(\d{4}-\d{2}-\d{2})T(\d{2})-(\d{2})-(\d{2})-(\d{3})Z$", s)
    if not m:
        # Try without ms
        m = re.match(r"^(\d{4}-\d{2}-\d{2})T(\d{2})-(\d{2})-(\d{2})Z$", s)
        if m:
            return f"{m.group(1)}T{m.group(2)}:{m.group(3)}:{m.group(4)}Z"
        raise ValueError(f"not a filename-safe ISO timestamp: {s!r}")
    return f"{m.group(1)}T{m.group(2)}:{m.group(3)}:{m.group(4)}.{m.group(5)}Z"


def iso_to_filename(s: str) -> str:
    return s.replace(":", "-").replace(".", "-")


def main() -> int:
    args = sys.argv[1:]
    reverse = False
    if args and args[0] == "--reverse":
        reverse = True
        args = args[1:]
    if args:
        s = args[0]
    else:
        s = sys.stdin.read().strip()
    if not s:
        print("usage: iso_to_filename.py [--reverse] <ts>", file=sys.stderr)
        return 2
    try:
        out = filename_to_iso(s) if reverse else iso_to_filename(s)
    except ValueError as e:
        print(f"error: {e}", file=sys.stderr)
        return 2
    print(out)
    return 0


if __name__ == "__main__":
    sys.exit(main())
