#!/usr/bin/env bash
# Run a Dafny model for an eval and save output.
# Usage: eval_run_dafny.sh <model.dfy> <output-dir>
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
MODEL="$1"
OUTDIR="$2"
mkdir -p "$OUTDIR"
"$SCRIPT_DIR/dafny_run.sh" "$MODEL" 2>&1 | tee "$OUTDIR/dafny_output.txt"
