#!/usr/bin/env bash
# setup.sh — wire sefer's shared docs into Claude Code.
#
# Writes the parent CLAUDE.md import stub. Claude Code reads CLAUDE.md up the
# directory tree, so a single stub at gly.fish/ is inherited by every sibling
# repo (meida, yada, alef, navi). Idempotent; run once per machine after cloning
# gly.fish + sefer as siblings.
set -euo pipefail

SEFER_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PARENT_DIR="$(dirname "$SEFER_DIR")"
parent_claude="$PARENT_DIR/CLAUDE.md"

if [ -f "$parent_claude" ]; then
  echo "exists (left as-is): $parent_claude"
else
  printf '@sefer/overview.md\n' > "$parent_claude"
  echo "wrote $parent_claude  ->  imports sefer/overview.md into every repo below it"
fi

# Optional: give a single repo its own stub so it self-documents the shared dep
# (redundant with the parent auto-load above):
#   echo '@../sefer/overview.md' > ../meida/CLAUDE.md
