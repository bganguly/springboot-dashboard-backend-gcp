#!/usr/bin/env bash
DB_URL="${DATABASE_URL:-postgresql://$(whoami):@localhost:5432/database_flyway_orm}"
DB="${DB_URL##*/}"; DB="${DB%%\?*}"

run_psql() { psql -d "$DB" -c "$1" 2>&1; }

EXPECTED_TABLES=(
  orders customers order_items products categories regions
  daily_summary order_category_facts
  daily_customer_category_summary daily_customer_token_category_summary
  daily_customer_token_order_summary daily_customer_token_category_rollup
  daily_filter_category_summary daily_status_category_summary
)

echo "=== Java ===" && java -version 2>&1 | head -1
echo "=== Postgres ===" && pg_isready 2>&1

echo "=== Table presence & row counts ==="
for t in "${EXPECTED_TABLES[@]}"; do
  result=$(psql -d "$DB" -Atqc "SELECT COUNT(*) FROM \"$t\"" 2>&1)
  printf "  %-50s %s\n" "$t" "$result"
done

echo "=== Date ranges ==="
run_psql "SELECT 'orders' AS tbl, MIN(\"placedAt\")::date AS min, MAX(\"placedAt\")::date AS max FROM orders UNION ALL SELECT 'daily_summary', MIN(date), MAX(date) FROM daily_summary;"

echo "=== Flyway history ===" && run_psql "SELECT version, description, success FROM flyway_schema_history ORDER BY installed_rank;" 2>&1

echo "=== Missing V3 tables ==="
for t in order_category_facts daily_customer_token_order_summary daily_filter_category_summary daily_status_category_summary; do
  exists=$(psql -d "$DB" -Atqc "SELECT to_regclass('public.\"$t\"')" 2>&1)
  printf "  %-50s %s\n" "$t" "${exists:-MISSING}"
done

./scripts/free-port.sh 8080
echo "=== App errors ===" && DATABASE_URL="$DB_URL" ./gradlew bootRun 2>&1 | grep -E "Caused by|APPLICATION FAILED|Started" | head -20
