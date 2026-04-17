#!/usr/bin/env python3
"""
dafny_format.py — Pretty-print Dafny verification results.

Reads Dafny's --log-format text output from stdin, parses per-function
results, and produces a structured summary matching the Alloy formatter style.

Usage:
  dafny verify --log-format text model.dfy | python3 dafny_format.py model.dfy
"""

import sys
import re
import os

def main():
    model_path = sys.argv[1] if len(sys.argv) > 1 else None
    src_lines = None
    if model_path:
        try:
            with open(model_path) as f:
                src_lines = f.readlines()
        except Exception:
            pass

    raw = sys.stdin.read()

    # Extract the summary line
    summary_match = re.search(
        r"Dafny program verifier finished with (\d+) verified, (\d+) errors?",
        raw
    )
    verified = int(summary_match.group(1)) if summary_match else 0
    errors = int(summary_match.group(2)) if summary_match else 0

    # Parse per-function results blocks
    # Pattern: "Results for <name> (<kind>)"
    blocks = re.split(r"^Results for (.+?) \((.+?)\)$", raw, flags=re.MULTILINE)
    # blocks: [preamble, name, kind, body, name, kind, body, ...]

    results = []
    it = iter(blocks[1:])
    for name, kind, body in zip(it, it, it):
        name = name.strip()
        kind = kind.strip()

        outcome_match = re.search(r"Overall outcome:\s*(\w+)", body)
        outcome = outcome_match.group(1) if outcome_match else "Unknown"

        time_match = re.search(r"Overall time:\s*([\d:.]+)", body)
        time_str = time_match.group(1) if time_match else "?"

        resource_match = re.search(r"Overall resource count:\s*(\d+)", body)
        resources = int(resource_match.group(1)) if resource_match else 0

        # Count assertion batches
        batch_count = len(re.findall(r"Assertion batch \d+:", body))

        # Check for errors in assertions
        error_lines = []
        for m in re.finditer(r"(\S+\.dfy)\((\d+),(\d+)\):\s*(.+)", body):
            fname, line, col, msg = m.group(1), m.group(2), m.group(3), m.group(4)
            if "error" in msg.lower() or "might not" in msg.lower():
                error_lines.append((fname, int(line), int(col), msg))

        results.append({
            "name": name,
            "kind": kind,
            "outcome": outcome,
            "time": time_str,
            "resources": resources,
            "batches": batch_count,
            "errors": error_lines,
        })

    # ── Print formatted output ──────────────────────────────────────

    print("=" * 62)
    if errors == 0:
        print(f"  ✓  Dafny: {verified} verified, {errors} errors")
    else:
        print(f"  ✗  Dafny: {verified} verified, {errors} errors")
    print("=" * 62)
    print()

    # Separate lemmas from helper functions
    lemmas = [r for r in results if r["kind"] == "correctness"]
    helpers = [r for r in results if r["kind"] != "correctness"]

    if lemmas:
        print("─" * 62)
        print("  LEMMAS (property proofs)")
        print("─" * 62)
        for r in lemmas:
            icon = "✓" if r["outcome"] == "Correct" else "✗"
            print(f"  {icon}  {r['name']:<45s} {r['time']}")
            if r["errors"]:
                for fname, line, col, msg in r["errors"]:
                    src = ""
                    if src_lines and 0 < line <= len(src_lines):
                        src = src_lines[line - 1].strip()
                        if len(src) > 60:
                            src = src[:57] + "..."
                    print(f"     ✗ {fname}:{line}  {msg}")
                    if src:
                        print(f"       {src}")
        print()

    if helpers:
        print("─" * 62)
        print("  FUNCTIONS (well-formedness checks)")
        print("─" * 62)
        for r in helpers:
            icon = "✓" if r["outcome"] == "Correct" else "✗"
            print(f"  {icon}  {r['name']:<45s} {r['time']}")
        print()

    # Summary table
    total_resources = sum(r["resources"] for r in results)
    total_lemmas = len(lemmas)
    passed_lemmas = sum(1 for r in lemmas if r["outcome"] == "Correct")
    failed_lemmas = total_lemmas - passed_lemmas

    print("─" * 62)
    print("  SUMMARY")
    print("─" * 62)
    print(f"  Lemmas:    {passed_lemmas}/{total_lemmas} proved", end="")
    if failed_lemmas > 0:
        print(f"  ({failed_lemmas} FAILED)")
    else:
        print()
    print(f"  Functions: {len(helpers)} well-formed")
    print(f"  Resources: {total_resources:,} (Z3 rlimit units)")
    print()

    # Exit with error if any failures
    if errors > 0:
        sys.exit(1)


if __name__ == "__main__":
    main()
