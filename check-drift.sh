#!/usr/bin/env bash
# check-drift.sh — guard against the example's embedded machinery rotting.
#
# examples/user-manager.ps1 embeds a full copy of the cli.ps1 machinery by
# design (the framework is "paste machinery at the bottom of one file"). When
# cli.ps1's machinery changes, the example must be regenerated from it, or the
# two silently diverge. This script extracts the machinery section (from the
# "CLI machinery" marker to EOF) from both files and diffs them.
#
#   ./check-drift.sh            # exits non-zero on drift
# Regenerate after a cli.ps1 change:
#   awk '/# ── CLI machinery/{f=1} f' cli.ps1 >> <fresh example payload>

set -euo pipefail
cd "$(dirname "$(realpath "$0")")"

tmpcli="$(mktemp)"
tmpexp="$(mktemp)"
trap 'rm -f "$tmpcli" "$tmpexp"' EXIT

awk '/CLI machinery/{f=1} f' cli.ps1 > "$tmpcli"
awk '/CLI machinery/{f=1} f' examples/user-manager.ps1 > "$tmpexp"

if diff -q "$tmpcli" "$tmpexp" >/dev/null; then
  echo "OK: examples/user-manager.ps1 machinery is in sync with cli.ps1"
  exit 0
else
  echo "DRIFT: examples/user-manager.ps1 machinery differs from cli.ps1:" >&2
  diff "$tmpcli" "$tmpexp" >&2 || true
  exit 1
fi
