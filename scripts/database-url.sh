#!/usr/bin/env bash
# Emit the DATABASE_URL from terraform output.
# Usage: DATABASE_URL=$(./scripts/database-url.sh)
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR/infra"

terraform output -raw database_url
