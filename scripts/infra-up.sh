#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
INFRA_DIR="$ROOT_DIR/infra"
ENV_FILE="$ROOT_DIR/.env.gcp"

: "${GCP_PROJECT:?Set GCP_PROJECT env var}"
: "${GCP_REGION:=${TF_VAR_gcp_region:-us-central1}}"

step() { printf '\n[infra-up] %s\n' "$1"; }

cd "$INFRA_DIR"

step "terraform init"
terraform init -upgrade -input=false

step "terraform apply"
terraform apply \
  -var="gcp_project=${GCP_PROJECT}" \
  -var="gcp_region=${GCP_REGION}" \
  -input=false \
  -auto-approve

step "writing .env.gcp"
INSTANCE=$(terraform output -raw cloud_sql_instance)
REGISTRY=$(terraform output -raw artifact_registry)
RUN_URL=$(terraform output -raw cloud_run_url)

cat > "$ENV_FILE" <<EOF
CLOUD_SQL_INSTANCE=${INSTANCE}
ARTIFACT_REGISTRY=${REGISTRY}
CLOUD_RUN_URL=${RUN_URL}
GCP_PROJECT=${GCP_PROJECT}
GCP_REGION=${GCP_REGION}
EOF

echo ""
echo "Infra ready."
echo "  Cloud SQL instance : ${INSTANCE}"
echo "  Artifact Registry  : ${REGISTRY}"
echo "  Cloud Run URL      : ${RUN_URL}"
echo ""
echo "Next: ./scripts/prepare-demo-data.sh"
