#!/usr/bin/env bash
# Start dashboard against local docker-compose Postgres — no cloud dependencies.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

echo "[local-dev] Starting local Postgres via docker-compose..."
docker compose up -d db
sleep 2

export DATABASE_URL="${DATABASE_URL:-postgresql://appuser:password@localhost:5432/app}"

echo "[local-dev] Applying schema..."
npx prisma db push

echo "[local-dev] Starting dashboard on :3004"
npm run dev
