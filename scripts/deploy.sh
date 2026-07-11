#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

printf '\n=== springboot-dashboard-backend-gcp ===\n'
printf '  [1] Local  — start local dev server (default)\n'
printf '  [2] Remote — deploy to GCP (Cloud Run or GKE)\n'
printf '\nChoice [1/2]: '
read -r _MODE
case "$_MODE" in
  2) _TARGET="remote" ;;
  *) _TARGET="local" ;;
esac

# ══════════════════════════════════════════════════════════════════════════════
# LOCAL
# ══════════════════════════════════════════════════════════════════════════════
if [[ "$_TARGET" == "local" ]]; then

  ORDERS="${ORDERS:-100000}"
  DB="database_flyway_orm"
  DB_URL="postgresql://$(whoami):@localhost:5432/${DB}"

  fail() { printf '\nERROR: %s\n\n' "$*" >&2; exit 1; }
  ok()   { printf '  %-18s %s\n' "$1" "$2"; }

  printf '\n=== prerequisites ===\n'

  command -v java >/dev/null 2>&1 || fail "Java 21 not found.
  Install via SDKMAN (workaround for older Macs — brew triggers a 30-60 min source build):
    curl -s https://get.sdkman.io | bash
    source ~/.sdkman/bin/sdkman-init.sh
    sdk install java 21-tem"

  JAVA_VER=$(java -version 2>&1 | head -1)
  [[ "$JAVA_VER" =~ 21 ]] || fail "Java 21 required. Found: $JAVA_VER
  Install via SDKMAN:  sdk install java 21-tem"
  ok "java" "$JAVA_VER"

  command -v gradle >/dev/null 2>&1 || fail "Gradle not found.
  Install via SDKMAN (workaround for older Macs — brew triggers a 30-60 min source build):
    sdk install gradle"
  ok "gradle" "$(gradle --version 2>/dev/null | grep '^Gradle ' | head -1)"

  command -v psql >/dev/null 2>&1 || fail "psql not found — install Postgres (brew install postgresql@15)"
  ok "psql" "$(psql --version)"

  if ! pg_isready >/dev/null 2>&1; then
    printf '  postgres: not running — starting...\n'
    if command -v brew >/dev/null 2>&1; then
      brew services start postgresql@15 2>/dev/null || brew services start postgresql 2>/dev/null || true
      sleep 2
    fi
    pg_isready >/dev/null 2>&1 || fail "Postgres did not start. Install: brew install postgresql@15"
  fi
  ok "postgres" "ready"

  if [[ ! -f "$ROOT_DIR/gradlew" ]]; then
    printf '\ngradlew not found — generating...\n'
    gradle wrapper
  fi

  DB_EXISTS=$(psql -lqt 2>/dev/null | cut -d'|' -f1 | tr -d ' ' | grep -x "$DB" || true)
  if [[ -z "$DB_EXISTS" ]]; then
    printf '\n=== first-time database setup ===\n'
    printf 'Will:\n'
    printf '  1. createdb %s\n' "$DB"
    printf '  2. apply V1/V2/V3 migrations\n'
    printf '  3. seed %s orders\n' "$ORDERS"
    printf '  4. rebuild all read model rollups\n'
    printf '\n  Set ORDERS=N to change the seed size (default 100k; production uses 4M).\n'
    printf '\nProceed? [Y/n] '
    read -r yn
    [[ -z "$yn" || "$yn" =~ ^[Yy]$ ]] || { printf 'Aborted.\n'; exit 0; }

    printf '\n[1/4] creating database...\n'
    createdb "$DB"

    printf '[2/4] applying migrations...\n'
    psql -d "$DB" -f src/main/resources/db/migration/V1__initial_schema.sql
    psql -d "$DB" -f src/main/resources/db/migration/V2__daily_summary.sql
    psql -d "$DB" -f src/main/resources/db/migration/V3__indexes_and_read_models.sql

    printf '[3/4] seeding %s orders...\n' "$ORDERS"
    psql -d "$DB" -v orders="$ORDERS" -f scripts/seed-large.sql

    printf '[4/4] rebuilding read model rollups...\n'
    psql -d "$DB" -f scripts/rebuild-dashboard-read-models.sql

    printf '\nSetup complete.\n'
  else
    ok "database" "$DB (exists — skipping setup)"
  fi

  printf '\n=== diagnostics ===\n'
  DATABASE_URL="$DB_URL" ./scripts/diagnose.sh

  printf '\n=== starting backend :8080 ===\n'
  "$ROOT_DIR/scripts/free-port.sh" 8080
  DATABASE_URL="$DB_URL" ./gradlew bootRun

  exit 0
fi

# ══════════════════════════════════════════════════════════════════════════════
# REMOTE (GCP)
# ══════════════════════════════════════════════════════════════════════════════

ENV_FILE="$ROOT_DIR/.env.gcp"

if ! command -v gcloud >/dev/null 2>&1; then
  printf '\ngcloud CLI not found.\n'
  if command -v brew >/dev/null 2>&1; then
    printf 'Installing via Homebrew...\n'
    brew install --cask google-cloud-sdk
    source "$(brew --prefix)/share/google-cloud-sdk/path.bash.inc" 2>/dev/null || true
  else
    printf 'Install it from: https://cloud.google.com/sdk/docs/install\nThen re-run this script.\n'
    exit 1
  fi
fi

ACTIVE_ACCOUNT=$(gcloud auth list --filter=status:ACTIVE --format="value(account)" 2>/dev/null | head -1 || true)
if [[ -z "$ACTIVE_ACCOUNT" ]]; then
  printf '\nNot authenticated with gcloud — logging in...\n'
  gcloud auth login
  ACTIVE_ACCOUNT=$(gcloud auth list --filter=status:ACTIVE --format="value(account)" 2>/dev/null | head -1 || true)
  [[ -n "$ACTIVE_ACCOUNT" ]] || { printf 'Login did not complete.\n' >&2; exit 1; }
fi
printf '\nAuthenticated as: %s\n' "$ACTIVE_ACCOUNT"

[[ -f "$ENV_FILE" ]] && source "$ENV_FILE"

_CONFIG_PROJECT=$(gcloud config get-value project 2>/dev/null || true)
GCP_PROJECT="${_CONFIG_PROJECT:-${GCP_PROJECT:-}}"
[[ -n "$GCP_PROJECT" ]] || {
  printf '\nNo GCP project detected.\n' >&2
  printf 'Run: gcloud config set project <id>   (or set GCP_PROJECT in %s)\n' "$ENV_FILE" >&2
  exit 1
}

_CONFIG_REGION=$(gcloud config get-value compute/region 2>/dev/null || true)
GCP_REGION="${_CONFIG_REGION:-${GCP_REGION:-us-central1}}"

_GIT_HASH=$(git -C "$ROOT_DIR" rev-parse --short HEAD 2>/dev/null || true)
_BUILD_TS=$(date +%Y%m%d%H%M%S)
TAG="${_GIT_HASH:+${_GIT_HASH}-}${_BUILD_TS}"

printf '\n=== deployment config ===\n'
printf '  Project: %s\n  Region:  %s\n' "$GCP_PROJECT" "$GCP_REGION"

AR_STATE=$(gcloud services list \
  --project="$GCP_PROJECT" \
  --filter="name:artifactregistry.googleapis.com" \
  --format="value(state)" 2>/dev/null || true)

if [[ "$AR_STATE" != "ENABLED" ]]; then
  printf '\n  Enabling Artifact Registry API for project %s...\n' "$GCP_PROJECT"
  gcloud services enable artifactregistry.googleapis.com --project="$GCP_PROJECT"
fi

_LISTED_REGISTRY=$(gcloud artifacts repositories list \
  --project="$GCP_PROJECT" \
  --location="$GCP_REGION" \
  --format="value(name)" 2>/dev/null | head -1 || true)
_LISTED_REGISTRY="${_LISTED_REGISTRY##*/}"
REGISTRY="${_LISTED_REGISTRY:-${ARTIFACT_REGISTRY:-${GCP_PROJECT}-gradle}}"

if ! gcloud artifacts repositories describe "$REGISTRY" \
      --project="$GCP_PROJECT" --location="$GCP_REGION" >/dev/null 2>&1; then
  printf '\n  No Artifact Registry repo found — creating "%s" in %s...\n' "$REGISTRY" "$GCP_REGION"
  gcloud artifacts repositories create "$REGISTRY" \
    --repository-format=docker \
    --location="$GCP_REGION" \
    --project="$GCP_PROJECT"
fi

IMAGE="${GCP_REGION}-docker.pkg.dev/${GCP_PROJECT}/${REGISTRY}/backend:${TAG}"

if [[ ! -f "$ENV_FILE" ]]; then
  printf '\n.env.gcp not found — provisioning infra first...\n'
  GCP_PROJECT="$GCP_PROJECT" GCP_REGION="$GCP_REGION" "$ROOT_DIR/scripts/infra-up.sh"
  [[ -f "$ENV_FILE" ]] && source "$ENV_FILE"
fi

printf '\nBuilding and pushing:\n  %s\n' "$IMAGE"

printf '\n=== STOPPED ===================================================\n'
printf '  Deploy to GKE (Kubernetes)?  Y = GKE  /  n = Cloud Run\n'
printf '===============================================================\n'
read -r -p "Deploy to GKE? [Y/n]: " _CHOICE
case "$_CHOICE" in
  [nN]*) DEPLOY_TARGET="cloudrun" ;;
  *)     DEPLOY_TARGET="gke" ;;
esac
printf '\n  Target: %s\n' "$DEPLOY_TARGET"

if docker info >/dev/null 2>&1; then
  printf '\n[1/3] configuring docker auth...\n'
  gcloud auth configure-docker "${GCP_REGION}-docker.pkg.dev" --quiet
  printf '[2/3] building image...\n'
  docker build --platform linux/amd64 -t "$IMAGE" "$ROOT_DIR"
  printf '[3/3] pushing image...\n'
  docker push "$IMAGE"
else
  printf '\nDocker not available — building via Cloud Build (no local Docker needed)...\n'
  gcloud services enable cloudbuild.googleapis.com --project "$GCP_PROJECT"
  gcloud builds submit \
    --tag "$IMAGE" \
    --project "$GCP_PROJECT" \
    "$ROOT_DIR"
fi

if ! gcloud auth application-default print-access-token >/dev/null 2>&1; then
  printf '\nSetting up Application Default Credentials (required by the Pulumi GCP provider)...\n'
  gcloud auth application-default login
fi

GKE_CLUSTER="${GKE_CLUSTER:-dash-gke-cluster}"
K8S_NAMESPACE="dash"

if [[ "$DEPLOY_TARGET" == "gke" ]]; then
  GKE_ZONE="${GCP_REGION}-a"
  printf '\n=== deploying to GKE via Cloud Build ===\n'
  printf '  Cluster: %s  Zone: %s\n' "$GKE_CLUSTER" "$GKE_ZONE"

  gcloud services enable cloudbuild.googleapis.com container.googleapis.com secretmanager.googleapis.com \
    --project "$GCP_PROJECT" --quiet

  _PROJECT_NUMBER=$(gcloud projects describe "$GCP_PROJECT" --format="value(projectNumber)")
  for _SA in \
    "${GCP_PROJECT}@cloudbuild.gserviceaccount.com" \
    "${_PROJECT_NUMBER}-compute@developer.gserviceaccount.com"; do
    gcloud secrets add-iam-policy-binding dash-database-url \
      --member="serviceAccount:${_SA}" \
      --role="roles/secretmanager.secretAccessor" \
      --project "$GCP_PROJECT" --quiet 2>/dev/null || true
  done

  if ! gcloud container clusters describe "$GKE_CLUSTER" \
        --zone "$GKE_ZONE" --project "$GCP_PROJECT" >/dev/null 2>&1; then
    printf '\n  Cluster not found — creating %s (this takes ~5 min)...\n' "$GKE_CLUSTER"
    gcloud container clusters create "$GKE_CLUSTER" \
      --zone "$GKE_ZONE" \
      --network "dash-vpc" \
      --subnetwork "dash-subnet" \
      --num-nodes 1 \
      --machine-type e2-small \
      --enable-autoscaling --min-nodes 1 --max-nodes 3 \
      --workload-pool "${GCP_PROJECT}.svc.id.goog" \
      --project "$GCP_PROJECT"
  fi

  gcloud builds submit "$ROOT_DIR/k8s" \
    --config "$ROOT_DIR/cloudbuild-gke.yaml" \
    --substitutions "_IMAGE=${IMAGE},_CLUSTER=${GKE_CLUSTER},_ZONE=${GKE_ZONE},_NAMESPACE=${K8S_NAMESPACE}" \
    --project "$GCP_PROJECT"

  BACKEND_URL="<check GKE ingress — kubectl get ingress dash-backend -n ${K8S_NAMESPACE}>"
  printf '\nDone. Check ingress IP:\n  kubectl get ingress dash-backend -n %s\n' "$K8S_NAMESPACE"
else
  printf '\n=== deploying via Pulumi ===\n'
  cd "$ROOT_DIR/infra"
  npm install --prefer-offline 2>/dev/null || npm install
  pulumi stack select "dev" 2>/dev/null || pulumi stack init "dev"
  pulumi config set gcp:project "$GCP_PROJECT"
  pulumi config set gcp:region  "$GCP_REGION"
  pulumi config set backendImage "$IMAGE"
  pulumi up --yes

  BACKEND_URL=$(pulumi stack output backendUrl 2>/dev/null || \
    gcloud run services describe dash-backend \
      --region "$GCP_REGION" --project "$GCP_PROJECT" \
      --format="value(status.url)" 2>/dev/null || true)

  printf '\nDone. Backend URL:\n  %s\n' "$BACKEND_URL"
fi

_CUSTOMERS=$(curl -sf "${BACKEND_URL}/api/customers" --max-time 10 2>/dev/null \
  | python3 -c "import sys,json; d=json.load(sys.stdin); print(len(d.get('data',[])))" 2>/dev/null || echo "-1")

if [[ "$_CUSTOMERS" == "0" ]]; then
  printf '\nDatabase is empty. Seed demo data now? [y/N] '
  read -r do_seed
  if [[ "$do_seed" =~ ^[Yy]$ ]]; then
    "$ROOT_DIR/scripts/seed-via-proxy.sh" "$GCP_PROJECT" "$GCP_REGION"
  fi
elif [[ "$_CUSTOMERS" == "-1" ]]; then
  printf '\n(Could not reach backend to check seed status — skipping seed prompt.)\n'
fi

printf '\nRemember to tear down when finished:\n'
printf '  ./scripts/infra-down.sh\n'
