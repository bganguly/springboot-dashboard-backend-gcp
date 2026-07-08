#!/usr/bin/env bash
# Run a read-only SQL query against prod Cloud SQL without --private-ip.
# Usage: ./scripts/query-prod.sh "SELECT id, search_text FROM orders WHERE id = 1973252"
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SQL="${1:?usage: $0 \"SELECT ...\"}"
PORT=9471

cd "$ROOT_DIR/infra"
OUT="$(pulumi stack output databaseUrl --show-secrets 2>/dev/null)"
REST="${OUT#*://}"
USERINFO="${REST%%@*}"
HOSTDB="${REST#*@}"
DB_USER="${USERINFO%%:*}"
DB_PASS="${USERINFO#*:}"
DB_NAME="${HOSTDB##*/}"; DB_NAME="${DB_NAME%%\?*}"
SQL_CONN="$(pulumi stack output cloudSqlInstance 2>/dev/null)"

INSTANCE="${SQL_CONN##*:}"
PROJECT="${SQL_CONN%%:*}"

echo "Enabling public IP on $INSTANCE..."
gcloud sql instances patch "$INSTANCE" --project="$PROJECT" --assign-ip --quiet
echo "Waiting 10s for public IP to become reachable..."
sleep 10

trap '
  echo "Removing public IP from $INSTANCE..."
  gcloud sql instances patch "'"$INSTANCE"'" --project="'"$PROJECT"'" --no-assign-ip --quiet
  kill "$PROXY_PID" 2>/dev/null; wait "$PROXY_PID" 2>/dev/null
  unset DB_PASS
' EXIT

cloud-sql-proxy "$SQL_CONN" --port "$PORT" >/tmp/csp-query.log 2>&1 &
PROXY_PID=$!

READY=0
for _ in $(seq 1 20); do
  (echo > /dev/tcp/127.0.0.1/$PORT) 2>/dev/null && { READY=1; break; }
  sleep 1
done

if [[ "$READY" -eq 0 ]]; then
  echo "Proxy did not become ready. Log:" >&2
  cat /tmp/csp-query.log >&2
  exit 1
fi

PGPASSWORD="$DB_PASS" psql \
  "host=127.0.0.1 port=$PORT user=$DB_USER dbname=$DB_NAME sslmode=disable" \
  -c "$SQL" || {
  echo "psql failed. Proxy log:" >&2
  cat /tmp/csp-query.log >&2
  exit 1
}
