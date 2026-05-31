#!/usr/bin/env bash
# Cursor Skills Master — installer
# Installs 16 master skills (bundling 258 skills) into Cursor.
#
# Usage:
#   ./install.sh                 # install globally to ~/.cursor/skills/
#   ./install.sh --project DIR   # install into DIR/.cursor/skills/
#   ./install.sh --help
#
# One-liner (from anywhere):
#   curl -fsSL https://raw.githubusercontent.com/Bodymobarez/cursor-skills-master/main/install.sh | bash

set -euo pipefail

REPO_RAW="https://raw.githubusercontent.com/Bodymobarez/cursor-skills-master/main"
REPO_GIT="https://github.com/Bodymobarez/cursor-skills-master.git"

GREEN='\033[0;32m'; BLUE='\033[0;34m'; YELLOW='\033[1;33m'; RED='\033[0;31m'; NC='\033[0m'
info()  { printf "${BLUE}==>${NC} %s\n" "$1"; }
ok()    { printf "${GREEN}✓${NC} %s\n" "$1"; }
warn()  { printf "${YELLOW}!${NC} %s\n" "$1"; }
err()   { printf "${RED}✗${NC} %s\n" "$1" >&2; }

TARGET_BASE="$HOME/.cursor"
MODE="global"

while [ $# -gt 0 ]; do
  case "$1" in
    --project)
      MODE="project"; TARGET_BASE="${2:?--project needs a directory}/.cursor"; shift 2 ;;
    --help|-h)
      grep '^#' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) err "Unknown option: $1"; exit 1 ;;
  esac
done

SKILLS_DIR="$TARGET_BASE/skills"
info "Target: $SKILLS_DIR ($MODE)"

# --- locate skills source: local repo dir, or download ---
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" 2>/dev/null && pwd || echo "")"
SRC=""
if [ -n "$SCRIPT_DIR" ] && [ -d "$SCRIPT_DIR/skills" ]; then
  SRC="$SCRIPT_DIR/skills"
  info "Using local skills from: $SRC"
else
  info "Downloading skills from GitHub..."
  TMP="$(mktemp -d)"
  trap 'rm -rf "$TMP"' EXIT
  if command -v git >/dev/null 2>&1; then
    git clone --depth 1 "$REPO_GIT" "$TMP/repo" >/dev/null 2>&1
    SRC="$TMP/repo/skills"
  else
    err "git is required for remote install. Install git and retry."
    exit 1
  fi
fi

[ -d "$SRC" ] || { err "Skills source not found."; exit 1; }

# --- backup existing ---
mkdir -p "$SKILLS_DIR"
if [ -n "$(ls -A "$SKILLS_DIR" 2>/dev/null || true)" ]; then
  BACKUP="$SKILLS_DIR.backup.$(date +%Y%m%d_%H%M%S)"
  cp -R "$SKILLS_DIR" "$BACKUP"
  warn "Existing skills backed up to: $BACKUP"
fi

# --- install masters (overwrite same-named) ---
COUNT=0
for master in "$SRC"/*-master; do
  [ -d "$master" ] || continue
  name="$(basename "$master")"
  rm -rf "$SKILLS_DIR/$name"
  cp -R "$master" "$SKILLS_DIR/$name"
  COUNT=$((COUNT + 1))
done

ok "Installed $COUNT master skills into $SKILLS_DIR"
BUNDLED=$(find "$SKILLS_DIR" -name GUIDE.md 2>/dev/null | wc -l | tr -d ' ')
ok "Bundled sub-skills available: $BUNDLED"
echo
info "Next steps:"
echo "  1. Restart Cursor (or open a new chat)."
echo "  2. Open Settings → Skills to see the *-master skills."
echo "  3. Try: \"use ui-master and build a landing page\""
