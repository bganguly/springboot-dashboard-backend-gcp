#!/usr/bin/env bash
# Read-only production diagnostics via Cloud SQL Auth Proxy (no public IP
# exposure, unlike seed-via-proxy.sh). Fetches credentials from Pulumi
# internally and never prints them — only the query output below is emitted.
# Runs ONLY read-only statements (pg_stat_user_tables, EXPLAIN ANALYZE); never
# writes, never VACUUM (which would need to lock/scan the table itself).
#
# Usage: ./scripts/db-readonly-diagnose.sh [FROM_DATE] [TO_DATE]
#   FROM_DATE/TO_DATE: date range for the sample EXPLAIN ANALYZE count query.
#   Defaults to a narrow, arbitrary recent-looking window if omitted.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
FROM_DATE="${1:-2026-06-10}"
TO_DATE="${2:-2026-06-13}"
PROXY_PORT="${PROXY_PORT:-5433}"

cd "$ROOT_DIR/infra"

OUT_JSON="$(pulumi stack output --show-secrets --json)"

# Everything below stays inside this script's own process — nothing is
# echoed, exported to the caller's shell, or written to disk.
eval "$(python3 - "$OUT_JSON" <<'PYEOF'
import json, sys
d = json.loads(sys.argv[1])
url = d["databaseUrl"]
rest = url.split("://", 1)[1]
userinfo, hostdb = rest.split("@", 1)
user, pw = userinfo.split(":", 1)
_, db = hostdb.split("/", 1)
db = db.split("?")[0]
print(f"DB_USER={user!r}")
print(f"DB_PASS={pw!r}")
print(f"DB_NAME={db!r}")
print(f"SQL_CONN={d['cloudSqlInstance']!r}")
PYEOF
)"
unset OUT_JSON

cloud-sql-proxy "$SQL_CONN" --private-ip --port "$PROXY_PORT" >/tmp/cloud-sql-proxy-diag.log 2>&1 &
PROXY_PID=$!
cleanup() {
  kill "$PROXY_PID" 2>/dev/null || true
  wait "$PROXY_PID" 2>/dev/null || true
  unset DB_USER DB_PASS DB_NAME SQL_CONN
}
trap cleanup EXIT

for _ in $(seq 1 20); do
  (echo > "/dev/tcp/127.0.0.1/$PROXY_PORT") >/dev/null 2>&1 && break
  sleep 1
done

echo "=== pg_stat_user_tables: orders ==="
PGPASSWORD="$DB_PASS" psql -h 127.0.0.1 -p "$PROXY_PORT" -U "$DB_USER" -d "$DB_NAME" -c \
  "SELECT relname, n_live_tup, n_dead_tup, last_autovacuum, last_vacuum, last_analyze, autovacuum_count, vacuum_count
   FROM pg_stat_user_tables WHERE relname = 'orders';"

echo
echo "=== EXPLAIN ANALYZE: exact count over ${FROM_DATE}..${TO_DATE} ==="
PGPASSWORD="$DB_PASS" psql -h 127.0.0.1 -p "$PROXY_PORT" -U "$DB_USER" -d "$DB_NAME" -c \
  "EXPLAIN (ANALYZE, BUFFERS) SELECT COUNT(*) FROM orders o
   WHERE o.\"placedAt\" >= '${FROM_DATE}'::timestamptz
     AND o.\"placedAt\" <= ('${TO_DATE}'::date + interval '1 day' - interval '1 second');"
