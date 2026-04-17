#!/usr/bin/env bash
# Unified verification runner — routes .als to Alloy, .dfy to Dafny.
#
# Usage:
#   ./verify.sh model.als          # runs Alloy pipeline
#   ./verify.sh model.dfy          # runs Dafny pipeline
#   ./verify.sh --self             # self-verifies the skill (all models)
#   ./verify.sh --self --dafny     # self-verifies using Dafny only (fast)
#   ./verify.sh --self --alloy     # self-verifies using Alloy only
#   ./verify.sh --self --both      # self-verifies using both (cross-check)
#
# Exit code: 0 if all pass, 1 if any failures.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SKILL_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

# ── self-verification mode ──────────────────────────────────────────────────

if [[ "${1:-}" == "--self" ]]; then
  MODE="${2:---both}"
  FAIL=0

  echo "╔══════════════════════════════════════════════════════════╗"
  echo "║  Formal-Modeling Skill — Self-Verification              ║"
  echo "╚══════════════════════════════════════════════════════════╝"
  echo ""

  if [[ "$MODE" == "--dafny" || "$MODE" == "--both" ]]; then
    echo "┌─ Dafny verification (unbounded proofs) ─────────────────┐"
    DAFNY_DIR="$SKILL_DIR/self-models"
    if [[ -d "$DAFNY_DIR" ]]; then
      DAFNY_TOTAL=0
      DAFNY_PASS=0
      for dfy in "$DAFNY_DIR"/*.dfy; do
        NAME="$(basename "$dfy" .dfy)"
        DAFNY_TOTAL=$((DAFNY_TOTAL + 1))
        if OUTPUT=$(dafny verify "$dfy" 2>&1); then
          VERIFIED=$(echo "$OUTPUT" | grep 'verified' | sed 's/[^0-9]*\([0-9]*\) verified.*/\1/')
          echo "  ✓  $NAME ($VERIFIED verified)"
          DAFNY_PASS=$((DAFNY_PASS + 1))
        else
          ERRORS=$(echo "$OUTPUT" | grep 'error' | sed 's/.*[^0-9]\([0-9]*\) error.*/\1/')
          echo "  ✗  $NAME ($ERRORS errors)"
          FAIL=1
        fi
      done
      echo "│"
      echo "│  Dafny: $DAFNY_PASS/$DAFNY_TOTAL models pass"
      echo "└───────────────────────────────────────────────────────────┘"
      echo ""
    else
      echo "  (no self-models/ directory found — skipping)"
      echo "└───────────────────────────────────────────────────────────┘"
      echo ""
    fi
  fi

  if [[ "$MODE" == "--alloy" || "$MODE" == "--both" ]]; then
    echo "┌─ Alloy verification (bounded model checking) ───────────┐"
    ALLOY_MODELS=(
      "$SKILL_DIR/self-models/skill_pipeline.als"
      "$SKILL_DIR/self-models/skill_pipeline_boundary.als"
      "$SKILL_DIR/self-models/skill_pipeline_quality.als"
      "$SKILL_DIR/self-models/skill_pipeline_decisions.als"
    )
    ALLOY_TOTAL=0
    ALLOY_PASS=0
    for als in "${ALLOY_MODELS[@]}"; do
      if [[ -f "$als" ]]; then
        NAME="$(basename "$als" .als)"
        ALLOY_TOTAL=$((ALLOY_TOTAL + 1))
        OUTPUT=$("$SCRIPT_DIR/alloy_run.sh" "$als" 2>/dev/null)
        CHECKS=$(echo "$OUTPUT" | grep -c '✓' || true)
        FAILURES=$(echo "$OUTPUT" | grep -c 'COUNTEREXAMPLE' || true)
        if [[ "$FAILURES" -eq 0 ]]; then
          echo "  ✓  $NAME ($CHECKS checks pass)"
          ALLOY_PASS=$((ALLOY_PASS + 1))
        else
          echo "  ✗  $NAME ($FAILURES counterexamples)"
          FAIL=1
        fi
      fi
    done
    echo "│"
    echo "│  Alloy: $ALLOY_PASS/$ALLOY_TOTAL models pass"
    echo "└───────────────────────────────────────────────────────────┘"
    echo ""
  fi

  if [[ "$FAIL" -eq 0 ]]; then
    echo "═══ ALL PASS ═══"
  else
    echo "═══ FAILURES DETECTED ═══"
  fi
  exit "$FAIL"
fi

# ── single-file mode ────────────────────────────────────────────────────────

MODEL="${1:-}"
if [[ -z "$MODEL" ]]; then
  echo "Usage: verify.sh <model.als|model.dfy>" >&2
  echo "       verify.sh --self [--dafny|--alloy|--both]" >&2
  exit 1
fi

if [[ ! -f "$MODEL" ]]; then
  echo "File not found: $MODEL" >&2
  exit 1
fi

EXT="${MODEL##*.}"
case "$EXT" in
  als)
    exec "$SCRIPT_DIR/alloy_run.sh" "$MODEL"
    ;;
  dfy)
    exec "$SCRIPT_DIR/dafny_run.sh" "$MODEL"
    ;;
  *)
    echo "Unknown file type: .$EXT (expected .als or .dfy)" >&2
    exit 1
    ;;
esac
