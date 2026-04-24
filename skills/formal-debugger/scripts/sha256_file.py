#!/usr/bin/env python3
"""
sha256_file.py — print the SHA-256 hex digest of one file.

Used to compute PrevHypHash, PrevModelHash, PrevReportHash, and
ParentHypHash when constructing records. Prints only the 64-character
lowercase hex digest to stdout (newline-terminated).

Usage:
    sha256_file.py <path>

Example:
    python3 scripts/sha256_file.py investigations/my-bug/investigation-report-1_*.md
    # -> 3e8a9f... (64 hex chars)
"""
import hashlib
import sys
from pathlib import Path


def main() -> int:
    if len(sys.argv) != 2:
        print("usage: sha256_file.py <path>", file=sys.stderr)
        return 2
    p = Path(sys.argv[1])
    if not p.is_file():
        print(f"error: {sys.argv[1]} is not a file", file=sys.stderr)
        return 2
    print(hashlib.sha256(p.read_bytes()).hexdigest())
    return 0


if __name__ == "__main__":
    sys.exit(main())
