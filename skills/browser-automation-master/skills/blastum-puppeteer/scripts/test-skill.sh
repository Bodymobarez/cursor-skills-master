#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SKILL_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

cd "$SKILL_DIR"

if ! command -v node >/dev/null 2>&1; then
  echo "Node.js is required (v18+)." >&2
  exit 1
fi

if ! command -v npm >/dev/null 2>&1; then
  echo "npm is required." >&2
  exit 1
fi

if [ ! -d node_modules ]; then
  echo "Installing skill test dependencies..."
  if [ -f package-lock.json ]; then
    npm ci
  else
    npm install
  fi
fi

echo "Running puppeteer skill tests..."
npm run test:skill

if [ "${SKIP_AUDIT:-0}" != "1" ]; then
  echo "Running npm audit (non-blocking)..."
  npm audit --omit=dev || true
fi
