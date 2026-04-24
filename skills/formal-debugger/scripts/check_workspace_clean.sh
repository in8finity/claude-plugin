#!/usr/bin/env bash
#
# check_workspace_clean.sh — F11/TC33 enforcement: workspace contamination check.
#
# Fails if the working tree has untracked or gitignored files under the
# investigated path(s). The motivating failure: a locally-untracked source
# file makes code appear healthy while a clean CI checkout crashes on the
# same code path.
#
# Exit 0 = clean, 1 = contamination found, 2 = usage/git error.
#
# Usage:
#   check_workspace_clean.sh                    # whole repo
#   check_workspace_clean.sh src/ bot/          # specific paths
#   check_workspace_clean.sh --source-only src/ # only flag common source extensions
#
# Note: "ignored" files are only flagged when they match tracked directories
# (via --directory). A global .gitignore match on a top-level build dir is
# usually fine; a .gitignore match on a file inside src/ is usually not.

set -euo pipefail

# Normalize a path to cwd-relative for echo (keeps output free of absolute
# home/user paths when the caller passes a resolvable absolute path).
rel() {
  if command -v python3 >/dev/null 2>&1; then
    python3 -c 'import os,sys; print(os.path.relpath(sys.argv[1]))' "$1" 2>/dev/null || echo "$1"
  else
    echo "$1"
  fi
}

SOURCE_ONLY=false
PATHS=()

while [[ $# -gt 0 ]]; do
  case "$1" in
    --source-only) SOURCE_ONLY=true; shift ;;
    --help|-h)
      sed -n '2,20p' "$0" | sed 's/^# \{0,1\}//'
      exit 0
      ;;
    --) shift; PATHS+=("$@"); break ;;
    -*) echo "unknown flag: $1" >&2; exit 2 ;;
    *) PATHS+=("$1"); shift ;;
  esac
done

if ! git rev-parse --git-dir >/dev/null 2>&1; then
  echo "error: not inside a git repository" >&2
  exit 2
fi

# Default to the whole working tree if no paths supplied.
if [[ ${#PATHS[@]} -eq 0 ]]; then
  PATHS=(".")
fi

SOURCE_REGEX='\.(py|ts|tsx|js|jsx|go|rs|rb|java|kt|swift|c|h|cpp|cc|cs|php|ex|exs|clj|scala|lua|sh|bash|zsh|fish)$'

untracked=$(git ls-files --others --exclude-standard -- "${PATHS[@]}" 2>/dev/null || true)
ignored=$(git ls-files --others --ignored --exclude-standard -- "${PATHS[@]}" 2>/dev/null || true)

if $SOURCE_ONLY; then
  untracked=$(echo "$untracked" | grep -E "$SOURCE_REGEX" || true)
  ignored=$(echo "$ignored" | grep -E "$SOURCE_REGEX" || true)
fi

untracked_count=0
ignored_count=0
[[ -n "$untracked" ]] && untracked_count=$(echo "$untracked" | wc -l | tr -d ' ')
[[ -n "$ignored" ]]   && ignored_count=$(echo "$ignored" | wc -l | tr -d ' ')

# Build a cwd-relative display of the passed paths for the header line.
REL_PATHS=()
for p in "${PATHS[@]}"; do
  REL_PATHS+=("$(rel "$p")")
done

if [[ $untracked_count -eq 0 && $ignored_count -eq 0 ]]; then
  echo "TC33 PASS: workspace clean under ${REL_PATHS[*]}"
  exit 0
fi

echo "TC33 FAIL: workspace contamination under ${REL_PATHS[*]}"
if [[ $untracked_count -gt 0 ]]; then
  echo
  echo "  Untracked files ($untracked_count):"
  echo "$untracked" | sed 's/^/    /'
fi
if [[ $ignored_count -gt 0 ]]; then
  echo
  echo "  Gitignored files ($ignored_count):"
  echo "$ignored" | sed 's/^/    /'
fi
echo
echo "F11 requires recording 'Workspace clean: yes/no' on evidence derived"
echo "from local state. If the listed files cannot run in a clean CI"
echo "checkout (e.g., untracked source files, local stubs), the code-based"
echo "evidence is \`unreliable-source\` — the investigation must re-verify"
echo "against a clean checkout before acceptance."
exit 1
