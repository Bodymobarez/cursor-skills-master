#!/usr/bin/env bash
# Verify ACLI and md-to-adf are installed. Exit 0 if both present.

set -e

errors=0

if ! command -v acli &>/dev/null; then
  echo "ERROR: acli not found. Install: brew tap atlassian/homebrew-acli && brew install acli"
  errors=1
else
  acli --version 2>/dev/null || true
fi

if ! command -v md-to-adf &>/dev/null; then
  echo "ERROR: md-to-adf not found. Install: brew tap imzak31/md-to-adf && brew install md-to-adf"
  errors=1
else
  md-to-adf convert --help &>/dev/null || md-to-adf --help &>/dev/null || true
fi

[[ $errors -eq 0 ]]
