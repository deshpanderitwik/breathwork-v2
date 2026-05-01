#!/usr/bin/env bash
# Build @breathe/core and copy build artifacts into the Swift package tree:
#   1. core.iife.js → BreathRuntime/Sources/BreathRuntime/Resources (loaded
#      by JSContext at runtime).
#   2. test/fixtures/*.json → BreathRuntime/Tests/.../Fixtures (consumed by
#      the contract-parity tests).
#
# Fixture *generation* (which writes packages/core/test/fixtures/*.json) is
# in scripts/gen-fixtures.sh — that's a deliberate dev action committed via
# git. This script only copies what's already on disk.
#
# Run automatically by apps/macos/Makefile and apps/ios/Makefile before any
# Swift build. Safe to invoke from anywhere.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SRC="$REPO_ROOT/packages/core/dist/core.iife.js"
DST_DIR="$REPO_ROOT/swift/BreathRuntime/Sources/BreathRuntime/Resources"
DST="$DST_DIR/core.iife.js"
FIXTURES_SRC="$REPO_ROOT/packages/core/test/fixtures"
FIXTURES_DST="$REPO_ROOT/swift/BreathRuntime/Tests/BreathRuntimeTests/Fixtures"

cd "$REPO_ROOT"

echo "[sync-core] building @breathe/core…"
pnpm --filter @breathe/core build

if [[ ! -f "$SRC" ]]; then
  echo "[sync-core] error: expected $SRC after build, not found." >&2
  exit 1
fi

mkdir -p "$DST_DIR"
cp "$SRC" "$DST"
echo "[sync-core] core.iife.js → swift/BreathRuntime/Sources/BreathRuntime/Resources/"

shopt -s nullglob
fixtures=("$FIXTURES_SRC"/*.json)
mkdir -p "$FIXTURES_DST"
if [[ ${#fixtures[@]} -gt 0 ]]; then
  cp "${fixtures[@]}" "$FIXTURES_DST/"
  echo "[sync-core] fixtures (${#fixtures[@]}) → swift/BreathRuntime/Tests/BreathRuntimeTests/Fixtures/"
else
  echo "[sync-core] note: no fixtures found in $FIXTURES_SRC — run scripts/gen-fixtures.sh"
fi
