#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
INFRA_DIR="$ROOT_DIR/infra"

: "${GCP_PROJECT:?Set GCP_PROJECT env var}"
: "${GCP_REGION:=${TF_VAR_gcp_region:-us-central1}}"

cd "$INFRA_DIR"

echo "[infra-down] terraform destroy"
terraform destroy \
  -var="gcp_project=${GCP_PROJECT}" \
  -var="gcp_region=${GCP_REGION}" \
  -input=false \
  -auto-approve

rm -f "$ROOT_DIR/.env.gcp"
echo "[infra-down] done — all GCP resources destroyed"
