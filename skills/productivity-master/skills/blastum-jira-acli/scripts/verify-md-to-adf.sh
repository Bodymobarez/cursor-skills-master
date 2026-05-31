#!/usr/bin/env bash
# Verify md-to-adf converts sample markdown to valid ADF. Exit 0 if output contains doc structure.

set -e

tmp=$(mktemp)
trap 'rm -f "$tmp"' EXIT

printf '# Hello\n\nWorld\n' > "$tmp"
out=$(md-to-adf convert "$tmp" 2>/dev/null)

if echo "$out" | grep -q '"type": "doc"'; then
  echo "OK: md-to-adf produces valid ADF (contains doc structure)"
else
  echo "ERROR: md-to-adf output did not contain doc structure"
  exit 1
fi
