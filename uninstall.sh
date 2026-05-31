#!/usr/bin/env bash
# Cursor Skills Master — uninstaller
# Removes the 16 master skills installed by this repo.
#
# Usage:
#   ./uninstall.sh                 # remove from ~/.cursor/skills/
#   ./uninstall.sh --project DIR   # remove from DIR/.cursor/skills/

set -euo pipefail
GREEN='\033[0;32m'; BLUE='\033[0;34m'; YELLOW='\033[1;33m'; NC='\033[0m'
info() { printf "${BLUE}==>${NC} %s\n" "$1"; }
ok()   { printf "${GREEN}✓${NC} %s\n" "$1"; }
warn() { printf "${YELLOW}!${NC} %s\n" "$1"; }

TARGET_BASE="$HOME/.cursor"
while [ $# -gt 0 ]; do
  case "$1" in
    --project) TARGET_BASE="${2:?}/.cursor"; shift 2 ;;
    --help|-h) grep '^#' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) shift ;;
  esac
done

SKILLS_DIR="$TARGET_BASE/skills"
MASTERS="ai-mcp analytics backend-api browser-automation code-quality content-seo \
debugging devops documents git-workflow mobile planning productivity skills-meta testing ui"

REMOVED=0
for m in $MASTERS; do
  d="$SKILLS_DIR/${m}-master"
  if [ -d "$d" ]; then rm -rf "$d"; REMOVED=$((REMOVED + 1)); fi
done
ok "Removed $REMOVED master skills from $SKILLS_DIR"
warn "Restart Cursor to refresh the skills list."
