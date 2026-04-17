#!/usr/bin/env bash
# Write a model file to an eval output directory.
# Usage: eval_write_model.sh <output-dir> <filename> < model-content
# Reads model content from stdin.
set -euo pipefail
OUTDIR="$1"
FILENAME="$2"
mkdir -p "$OUTDIR"
cat > "$OUTDIR/$FILENAME"
echo "$OUTDIR/$FILENAME"
