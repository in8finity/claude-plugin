#!/usr/bin/env bash
# Set up an eval output directory and copy fixture files.
# Usage: eval_setup.sh <eval-num> <iteration-dir> [fixture-dir]
set -euo pipefail
EVAL_NUM="$1"
ITER_DIR="$2"
FIXTURE_DIR="${3:-}"
OUTDIR="$ITER_DIR/eval-$EVAL_NUM/with_skill/outputs"
mkdir -p "$OUTDIR"
if [[ -n "$FIXTURE_DIR" && -d "$FIXTURE_DIR" ]]; then
  cp "$FIXTURE_DIR"/* "$OUTDIR/" 2>/dev/null || true
fi
echo "$OUTDIR"
