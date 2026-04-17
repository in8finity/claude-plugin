#!/usr/bin/env bash
# Run a Dafny model and pretty-print the verification results.
#
# Usage:
#   ./dafny_run.sh [model.dfy]
#
# Works with local Dafny (preferred) or falls back to Docker.
#
# Output is piped through dafny_format.py for structured display.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
MODEL="${1:-model.dfy}"

if [[ ! -f "$MODEL" ]]; then
  echo "Model not found: $MODEL" >&2
  exit 1
fi

need() { command -v "$1" &>/dev/null || return 1; }
need python3 || { echo "Required: python3" >&2; exit 1; }

# ── detect dafny ────────────────────────────────────────────────────────────
# Try local install first, then Docker fallback.

USE_DOCKER=false
DAFNY_CMD=""

detect_dafny() {
  local candidates=(
    dafny                                             # system PATH
    /opt/homebrew/bin/dafny                            # Homebrew Apple Silicon
    /usr/local/bin/dafny                               # Homebrew Intel Mac
    "${HOME}/.dotnet/tools/dafny"                      # dotnet tool install --global
    "${DOTNET_ROOT:-/nonexistent}/tools/dafny"         # custom DOTNET_ROOT
    "${HOME}/.dafny/dafny"                             # manual install
    /usr/bin/dafny                                     # system package (Ubuntu/Debian)
    /snap/bin/dafny                                    # snap install
  )

  for cmd in "${candidates[@]}"; do
    if [[ -x "$cmd" ]] || command -v "$cmd" &>/dev/null; then
      # Verify it actually runs (not a broken symlink)
      if "$cmd" --version &>/dev/null 2>&1; then
        DAFNY_CMD="$cmd"
        return 0
      fi
    fi
  done
  return 1
}

if detect_dafny; then
  echo "Using Dafny: $DAFNY_CMD" >&2
elif need docker; then
  USE_DOCKER=true
  echo "No local Dafny found; using Docker (ghcr.io/dafny-lang/dafny)" >&2
else
  echo "ERROR: No Dafny and no Docker found." >&2
  echo "" >&2
  echo "Install one of:" >&2
  echo "  macOS:   brew install dafny" >&2
  echo "  Ubuntu:  dotnet tool install --global dafny" >&2
  echo "  Any:     install Docker" >&2
  exit 1
fi

# ── run verification ────────────────────────────────────────────────────────

if $USE_DOCKER; then
  MODEL_DIR="$(cd "$(dirname "$MODEL")" && pwd)"
  MODEL_NAME="$(basename "$MODEL")"

  docker run --rm \
    -v "$MODEL_DIR:/work" \
    -w /work \
    ghcr.io/dafny-lang/dafny:latest \
    verify --log-format text "$MODEL_NAME" 2>&1 \
    | python3 "$SCRIPT_DIR/dafny_format.py" "$MODEL"
else
  "$DAFNY_CMD" verify --log-format text "$MODEL" 2>&1 \
    | python3 "$SCRIPT_DIR/dafny_format.py" "$MODEL"
fi
