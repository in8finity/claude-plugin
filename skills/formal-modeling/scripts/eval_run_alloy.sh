#!/usr/bin/env bash
# Run an Alloy model for an eval and save output.
# Usage: eval_run_alloy.sh <model.als> <output-dir>
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
MODEL="$1"
OUTDIR="$2"
mkdir -p "$OUTDIR"
"$SCRIPT_DIR/alloy_run.sh" "$MODEL" 2>&1 | tee "$OUTDIR/alloy_output.txt"
