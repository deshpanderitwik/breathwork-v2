#!/usr/bin/env bash
# Build @breathe/core and regenerate the contract-test fixtures under
# packages/core/test/fixtures/. Commit the resulting diff when scheduler
# behavior changes intentionally.
#
# Run from anywhere — paths resolve from the script's location.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT"

echo "[gen-fixtures] building @breathe/core…"
pnpm --filter @breathe/core build

echo "[gen-fixtures] generating fixtures…"
node packages/core/test/fixtures/generate.mjs
