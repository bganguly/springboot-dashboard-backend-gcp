#!/usr/bin/env bash
# Dump the current database to GCS as a pg_dump custom-format snapshot.
# For fastest transfer, run from GCP Cloud Shell in the same region as Cloud SQL.
#
# Usage:
#   DEMO_SNAPSHOT_GCS_URI=gs://bucket/dash/demo.dump ./scripts/bake-demo-snapshot.sh
set -euo pipefail

: "${DEMO_SNAPSHOT_GCS_URI:?Set DEMO_SNAPSHOT_GCS_URI=gs://bucket/path/demo.dump}"
: "${DATABASE_URL:?Set DATABASE_URL}"

command -v pg_dump >/dev/null 2>&1 || { echo "pg_dump not found." >&2; exit 1; }
command -v gsutil  >/dev/null 2>&1 || { echo "gsutil not found." >&2; exit 1; }

echo "Streaming pg_dump directly to ${DEMO_SNAPSHOT_GCS_URI}..."
pg_dump --format=custom --no-owner --no-privileges "$DATABASE_URL" \
  | gsutil cp - "$DEMO_SNAPSHOT_GCS_URI"

echo "Done: $DEMO_SNAPSHOT_GCS_URI"
