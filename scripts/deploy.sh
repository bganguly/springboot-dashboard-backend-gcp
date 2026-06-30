#!/usr/bin/env bash
# Build and deploy backend (Spring Boot) to Cloud Run.
# Run deploy.sh in dashboard-frontend to deploy the frontend separately.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
[[ -f "$ROOT_DIR/.env.gcp" ]] || { echo ".env.gcp not found — run infra-up.sh first." >&2; exit 1; }
source "$ROOT_DIR/.env.gcp"

: "${GCP_PROJECT:?}" "${GCP_REGION:?}" "${ARTIFACT_REGISTRY:?}"

TAG="${IMAGE_TAG:-$(git -C "$ROOT_DIR" rev-parse --short HEAD 2>/dev/null || date +%s)}"
IMAGE="${ARTIFACT_REGISTRY}/backend:${TAG}"

gcloud auth configure-docker "${GCP_REGION}-docker.pkg.dev" --quiet

echo "[deploy-backend] Building $IMAGE"
docker build --platform linux/amd64 -t "$IMAGE" "$ROOT_DIR"
docker push "$IMAGE"

cd "$ROOT_DIR/infra"
terraform apply \
  -var="gcp_project=${GCP_PROJECT}" \
  -var="gcp_region=${GCP_REGION}" \
  -var="backend_image=${IMAGE}" \
  -input=false -auto-approve

echo "Backend: $(terraform output -raw backend_url)"
