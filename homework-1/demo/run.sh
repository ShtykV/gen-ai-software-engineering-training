#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."

export PORT="${PORT:-3000}"
export SEED_DATA="${SEED_DATA:-true}"

echo "Starting Banking Transactions API (Gleam + Wisp) on http://localhost:${PORT} (SEED_DATA=${SEED_DATA})..."
exec gleam run
