#!/usr/bin/env python3
"""
evidence_hash.py — compute the EvidenceHash for a state-change record.

EvidenceHash is defined as:
    sha256(sorted_concat(sha256(evidence_file_1_bytes),
                         sha256(evidence_file_2_bytes),
                         ...))

- Each input file is hashed individually first.
- The individual hex hashes are sorted lexicographically.
- The sorted hashes are concatenated as one ASCII string (no separator).
- The final SHA-256 of that concatenated string is the EvidenceHash.

Sort-order independence means that the order you pass the files doesn't
affect the result — only the SET of cited evidence matters. This matches
check_pw0_live.py's validator.

Usage:
    evidence_hash.py <evidence-file-1> [<evidence-file-2> ...]

Prints only the 64-character hex digest (newline-terminated).

Example (state-change citing E1, E2, E3):
    python3 scripts/evidence_hash.py \\
        investigations/foo/evidence/E1_*.md \\
        investigations/foo/evidence/E2_*.md \\
        investigations/foo/evidence/E3_*.md
"""
import hashlib
import sys
from pathlib import Path


def main() -> int:
    if len(sys.argv) < 2:
        print("usage: evidence_hash.py <file> [<file> ...]", file=sys.stderr)
        return 2
    individual_hashes: list[str] = []
    for arg in sys.argv[1:]:
        p = Path(arg)
        if not p.is_file():
            print(f"error: {arg} is not a file", file=sys.stderr)
            return 2
        individual_hashes.append(hashlib.sha256(p.read_bytes()).hexdigest())
    individual_hashes.sort()
    combined = hashlib.sha256("".join(individual_hashes).encode("ascii")).hexdigest()
    print(combined)
    return 0


if __name__ == "__main__":
    sys.exit(main())
