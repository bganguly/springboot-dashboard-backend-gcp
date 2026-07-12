#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

_pulumi_stack_count() {
  local stack="$1"
  ( cd "$ROOT_DIR/infra" 2>/dev/null && \
    pulumi stack ls --json 2>/dev/null | python3 -c "
import json,sys
try:
    data=json.load(sys.stdin)
    for s in data:
        if s.get('name')=='$stack':
            print(s.get('resourceCount',0))
            sys.exit(0)
    print(0)
except Exception:
    print(0)
" 2>/dev/null ) || printf '0'
}
_local_running=0
_lite_count=0
_full_count=0
lsof -ti:8080 >/dev/null 2>&1 && _local_running=1 || true
if command -v pulumi >/dev/null 2>&1 && pulumi whoami >/dev/null 2>&1; then
  _lite_count=$(_pulumi_stack_count lite)
  _full_count=$(_pulumi_stack_count full)
fi

printf '\n=== springboot-dashboard-backend-gcp ===\n\n'
printf '  [1] Local  — Spring Boot on localhost + local Postgres (no GCP cost)'
(( _local_running )) && printf ' [running]' || printf ' [not detected]'
printf '\n'
printf '  [2] Lite   — GCP: Cloud Run + db-g1-small (scales to zero, cold starts OK)'
(( _lite_count > 0 )) && printf ' [%s resources active]' "$_lite_count" || printf ' [not deployed]'
printf '\n'
printf '  [3] Full   — GCP: Cloud Run + db-custom-4-16384 (min 1 instance, always warm)'
(( _full_count > 0 )) && printf ' [%s resources active]' "$_full_count" || printf ' [not deployed]'
printf '\n'
printf '               Full also unlocks GKE deployment.\n'
printf '\nChoice [1/2/3]: '
read -r _MODE
case "$_MODE" in
  2) _TARGET="remote"; DEPLOY_MODE="lite" ;;
  3) _TARGET="remote"; DEPLOY_MODE="full" ;;
  *) _TARGET="local";  DEPLOY_MODE=""    ;;
esac

if [[ "$_TARGET" == "remote" ]]; then
  if [[ "$DEPLOY_MODE" == "lite" ]]; then
    printf '\n--- Lite GCP summary ---\n'
    printf '  DB:         db-g1-small (1 vCPU, 1.7 GB), 10 GB disk\n'
    printf '  Cloud Run:  min=0 instances (cold starts ~5s), max=1, 1 CPU / 512 Mi\n'
    printf '  GKE:        skipped\n'
    printf '  Cost est:   ~$30-50/mo if left running\n'
  else
    printf '\n--- Full GCP summary ---\n'
    printf '  DB:         db-custom-4-16384 (4 vCPU, 16 GB), 35 GB disk\n'
    printf '  Cloud Run:  min=1 instance (always warm), max=5, 2 CPU / 1 Gi\n'
    printf '  GKE:        available (you will be prompted)\n'
    printf '  Cost est:   ~$200-300/mo if left running — TEAR DOWN when done\n'
  fi
  printf '\nProceed? [Y/n] '
  read -r _CONFIRM
  [[ -z "$_CONFIRM" || "$_CONFIRM" =~ ^[Yy]$ ]] || { printf 'Aborted.\n'; exit 0; }
fi

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

ENV_FILE="$ROOT_DIR/.env.gcp.${DEPLOY_MODE}"

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

_shasum() { shasum -a 256 "$@" 2>/dev/null || sha256sum "$@" 2>/dev/null; }
TAG=$(find "$ROOT_DIR/src" "$ROOT_DIR/Dockerfile" \
    "$ROOT_DIR/build.gradle.kts" "$ROOT_DIR/settings.gradle.kts" \
    -type f 2>/dev/null | sort | xargs cat 2>/dev/null \
  | _shasum | cut -c1-16 || true)
TAG="${TAG:-$(date +%Y%m%d%H%M%S)}"

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

_IMG_EXISTS=$(gcloud artifacts docker tags list \
  "${GCP_REGION}-docker.pkg.dev/${GCP_PROJECT}/${REGISTRY}/backend" \
  --filter="tag=${TAG}" \
  --format="value(tag)" \
  --project "$GCP_PROJECT" 2>/dev/null | head -1 || true)

if [[ -n "$_IMG_EXISTS" ]]; then
  printf '\n  Image %s already exists — skipping build.\n' "$IMAGE"
else
  printf '\nBuilding and pushing:\n  %s\n' "$IMAGE"

if [[ "$DEPLOY_MODE" == "lite" ]]; then
  DEPLOY_TARGET="cloudrun"
  printf '\n  [lite] Skipping GKE — deploying to Cloud Run.\n'
else
  _GKE_EXISTS=$(gcloud container clusters describe "${GKE_CLUSTER:-dash-gke-cluster}" \
    --zone "${GCP_REGION}-a" --project "$GCP_PROJECT" --format="value(name)" 2>/dev/null || true)
  _CR_EXISTS=$(gcloud run services describe dash-backend \
    --region "$GCP_REGION" --project "$GCP_PROJECT" --format="value(name)" 2>/dev/null || true)
  if [[ -n "$_GKE_EXISTS" ]]; then
    DEPLOY_TARGET="gke"
    printf '\n  GKE cluster detected — redeploying to GKE.\n'
  elif [[ -n "$_CR_EXISTS" ]]; then
    DEPLOY_TARGET="cloudrun"
    printf '\n  Cloud Run service detected — redeploying to Cloud Run.\n'
  else
    printf '\n=== STOPPED ===================================================\n'
    printf '  Deploy to GKE (Kubernetes)?  Y = GKE  /  n = Cloud Run\n'
    printf '===============================================================\n'
    read -r -p "Deploy to GKE? [Y/n]: " _CHOICE
    case "$_CHOICE" in
      [nN]*) DEPLOY_TARGET="cloudrun" ;;
      *)     DEPLOY_TARGET="gke" ;;
    esac
    printf '\n  Target: %s\n' "$DEPLOY_TARGET"
  fi
fi

_cloudbuild_submit() {
  local tag="$1" project="$2" srcdir="$3"
  gcloud services enable cloudbuild.googleapis.com --project "$project"

  _CB_ROLE=$(gcloud projects get-iam-policy "$project" \
    --flatten="bindings[].members" \
    --filter="bindings.members:user:${ACTIVE_ACCOUNT} AND (bindings.role:roles/cloudbuild OR bindings.role:roles/owner OR bindings.role:roles/editor)" \
    --format="value(bindings.role)" 2>/dev/null | head -1 || true)
  if [[ -z "$_CB_ROLE" ]]; then
    printf '  Granting Cloud Build Editor to %s...\n' "$ACTIVE_ACCOUNT"
    gcloud projects add-iam-policy-binding "$project" \
      --member="user:${ACTIVE_ACCOUNT}" \
      --role="roles/cloudbuild.builds.editor" --quiet
  fi

  local attempt=0
  while (( attempt < 3 )); do
    attempt=$(( attempt + 1 ))
    set +e
    gcloud builds submit --tag "$tag" --project "$project" "$srcdir"
    local rc=$?
    set -e
    [[ "$rc" == "0" ]] && return 0
    [[ "$rc" == "130" ]] && { printf '\n[deploy] Build cancelled.\n'; exit 130; }
    if (( attempt < 3 )); then
      printf '  Cloud Build submit failed (attempt %d/3) — waiting 20s for IAM propagation...\n' "$attempt"
      sleep 20
    fi
  done
  printf '[deploy] Cloud Build failed after 3 attempts.\n' >&2
  return 1
}

if docker info >/dev/null 2>&1; then
  printf '\n[1/3] configuring docker auth...\n'
  gcloud auth configure-docker "${GCP_REGION}-docker.pkg.dev" --quiet
  printf '[2/3] building image...\n'
  docker build --platform linux/amd64 -t "$IMAGE" "$ROOT_DIR"
  printf '[3/3] pushing image...\n'
  docker push "$IMAGE"
else
  printf '\nDocker not available — building via Cloud Build...\n'
  _cloudbuild_submit "$IMAGE" "$GCP_PROJECT" "$ROOT_DIR"
fi
fi

if ! gcloud auth application-default print-access-token >/dev/null 2>&1; then
  printf '\nSetting up Application Default Credentials (required by the Pulumi GCP provider)...\n'
  gcloud auth application-default login
fi

GKE_CLUSTER="${GKE_CLUSTER:-dash-gke-cluster}"
K8S_NAMESPACE="dash"

_pulumi_up_robust() {
  local log_file
  log_file="$(mktemp)"
  local attempt=0 rc

  while (( attempt < 5 )); do
    attempt=$(( attempt + 1 ))
    set +e
    pulumi up --yes 2>&1 | tee "$log_file"
    rc="${PIPESTATUS[0]}"
    set -e

    [[ "$rc" == "0" ]] && { rm -f "$log_file"; return 0; }

    local conflicts
    conflicts=$(python3 - "${log_file}" <<'PYEOF'
import re, sys
content = open(sys.argv[1]).read()
lines = content.split('\n')
seen = set()
for i, line in enumerate(lines):
    m = re.match(r'\s+(gcp:[^(]+)\(([^)]+)\):', line)
    if m:
        type_display = m.group(1).strip()
        logical_name = m.group(2).strip()
        for j in range(i, min(i+8, len(lines))):
            id_m = re.search(r"'([^']+)' already exists", lines[j])
            if id_m:
                key = f'{type_display}|{logical_name}|{id_m.group(1)}'
                if key not in seen:
                    seen.add(key)
                    print(key)
                break
PYEOF
    2>/dev/null || true)

    if [[ -z "$conflicts" ]]; then
      local protected_urns
      protected_urns=$(grep -oE "urn:pulumi:[^ \"']+" "$log_file" \
        | tr -d '"' | grep -v '^$' | sort -u || true)
      if grep -q 'cannot be deleted' "$log_file" 2>/dev/null && [[ -n "$protected_urns" ]]; then
        printf '[deploy] Unprotecting and removing stale protected resources...\n'
        while IFS= read -r urn; do
          [[ -z "$urn" ]] && continue
          printf '  unprotect: %s\n' "$urn"
          pulumi state unprotect "$urn" --yes 2>/dev/null || true
          printf '  delete:    %s\n' "$urn"
          pulumi state delete "$urn" --yes 2>/dev/null || true
        done <<< "$protected_urns"
        continue
      fi
      printf '\n[deploy] pulumi up failed — actual errors:\n' >&2
      grep -E 'error:|Error|failed|FAIL' "$log_file" | head -20 >&2 || true
      rm -f "$log_file"
      return 1
    fi

    printf '[deploy] Auto-importing conflicting resources (attempt %d)...\n' "$attempt"
    while IFS='|' read -r type_display logical_name gcp_id; do
      [[ -z "$type_display" ]] && continue
      local module type_name import_type
      module=$(printf '%s' "$type_display" | cut -d: -f2)
      type_name=$(printf '%s' "$type_display" | cut -d: -f3)
      import_type="gcp:${module}/${type_name,}:${type_name}"
      printf '  importing: %s %s = %s\n' "$import_type" "$logical_name" "$gcp_id"
      pulumi import "$import_type" "$logical_name" "$gcp_id" --yes 2>/dev/null || true
    done <<< "$conflicts"
  done

  rm -f "$log_file"
  printf '[deploy] pulumi up failed after %d attempts.\n' "$attempt" >&2
  return 1
}

if [[ "$DEPLOY_TARGET" == "gke" ]]; then
  GKE_ZONE="${GCP_REGION}-a"
  DEPLOY_MODE_PREFIX=$([[ "$DEPLOY_MODE" == "lite" ]] && printf 'dash-lite' || printf 'dash')

  _SECRET_EXISTS=$(gcloud secrets versions access latest \
    --secret="${DEPLOY_MODE_PREFIX:-dash}-database-url" \
    --project "$GCP_PROJECT" >/dev/null 2>&1 && echo "yes" || echo "")
  if [[ -z "$_SECRET_EXISTS" ]]; then
    printf '\n=== provisioning Cloud SQL + networking + secrets via Pulumi (required by GKE) ===\n'
    cd "$ROOT_DIR/infra"
    [[ -d node_modules ]] || npm install --prefer-offline 2>/dev/null || npm install
    pulumi stack select "$DEPLOY_MODE" 2>/dev/null || pulumi stack init "$DEPLOY_MODE"
    if [[ "$DEPLOY_MODE" == "lite" ]]; then
      DEPLOY_MODE_PREFIX="dash-lite"
      cat > "Pulumi.${DEPLOY_MODE}.yaml" <<PYAML
config:
  gcp:project: ${GCP_PROJECT}
  gcp:region: ${GCP_REGION}
  dashboard:namePrefix: dash-lite
  dashboard:dbTier: db-g1-small
  dashboard:dbDiskGb: "10"
  dashboard:minInstanceCount: "0"
  dashboard:maxInstanceCount: "1"
  dashboard:cpu: "1"
  dashboard:memory: 512Mi
  dashboard:backendImage: ${IMAGE}
PYAML
    else
      DEPLOY_MODE_PREFIX="dash"
      cat > "Pulumi.${DEPLOY_MODE}.yaml" <<PYAML
config:
  gcp:project: ${GCP_PROJECT}
  gcp:region: ${GCP_REGION}
  dashboard:namePrefix: dash
  dashboard:dbTier: db-custom-4-16384
  dashboard:dbDiskGb: "35"
  dashboard:minInstanceCount: "1"
  dashboard:maxInstanceCount: "5"
  dashboard:cpu: "2"
  dashboard:memory: 1Gi
  dashboard:backendImage: ${IMAGE}
PYAML
    fi
    _pulumi_up_robust
    cd "$ROOT_DIR"

    printf '  Verifying secret version is accessible before GKE deploy...\n'
    _SECRET_READY=0
    for _i in 1 2 3 4 5 6; do
      if gcloud secrets versions access latest \
          --secret="${DEPLOY_MODE_PREFIX:-dash}-database-url" \
          --project "$GCP_PROJECT" >/dev/null 2>&1; then
        _SECRET_READY=1
        break
      fi
      printf '  Not yet accessible — waiting 10s (attempt %d/6)...\n' "$_i"
      sleep 10
    done
    if (( ! _SECRET_READY )); then
      printf '[deploy] Secret %s-database-url has no version after Pulumi up — aborting GKE deploy.\n' \
        "${DEPLOY_MODE_PREFIX:-dash}" >&2
      exit 1
    fi
  fi

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

  _gke_target_network=$(gcloud compute networks list \
    --project "$GCP_PROJECT" \
    --filter="name=dash-vpc" \
    --format="value(selfLink)" 2>/dev/null | head -1 || true)
  [[ -z "$_gke_target_network" ]] && _gke_target_network="default"

  _create_gke_cluster() {
    _GKE_NET_ARGS=()
    if [[ "$_gke_target_network" != "default" ]]; then
      _GKE_NET_ARGS=(--network "dash-vpc" --subnetwork "dash-subnet")
    fi
    gcloud container clusters create "$GKE_CLUSTER" \
      --zone "$GKE_ZONE" \
      "${_GKE_NET_ARGS[@]}" \
      --num-nodes 1 \
      --machine-type e2-medium \
      --enable-autoscaling --min-nodes 1 --max-nodes 3 \
      --workload-pool "${GCP_PROJECT}.svc.id.goog" \
      --project "$GCP_PROJECT"
  }

  if gcloud container clusters describe "$GKE_CLUSTER" \
        --zone "$GKE_ZONE" --project "$GCP_PROJECT" >/dev/null 2>&1; then
    _CLUSTER_NET=$(gcloud container clusters describe "$GKE_CLUSTER" \
      --zone "$GKE_ZONE" --project "$GCP_PROJECT" \
      --format="value(networkConfig.network)" 2>/dev/null || true)
    if [[ "$_gke_target_network" != "default" && "$_CLUSTER_NET" != *"dash-vpc"* ]]; then
      printf '\n  Cluster network mismatch detected — recreating %s (~5 min)...\n' "$GKE_CLUSTER"
      gcloud container clusters delete "$GKE_CLUSTER" \
        --zone "$GKE_ZONE" --project "$GCP_PROJECT" --quiet
      _create_gke_cluster
    fi
  else
    printf '\n  Cluster not found — creating %s on dash-vpc (this takes ~5 min)...\n' "$GKE_CLUSTER"
    _create_gke_cluster
  fi

  printf '\n  Tail Cloud Build logs? [Y/n] '
  read -r _GKE_TAIL
  _GKE_BUILD_ID=$(gcloud builds submit "$ROOT_DIR/k8s" \
    --config "$ROOT_DIR/cloudbuild-gke.yaml" \
    --substitutions "_IMAGE=${IMAGE},_CLUSTER=${GKE_CLUSTER},_ZONE=${GKE_ZONE},_NAMESPACE=${K8S_NAMESPACE}" \
    --project "$GCP_PROJECT" \
    --async --format="value(id)" 2>/dev/null)
  printf '  Build ID: %s\n' "$_GKE_BUILD_ID"
  if [[ -z "$_GKE_TAIL" || "$_GKE_TAIL" =~ ^[Yy]$ ]]; then
    gcloud builds log --stream "$_GKE_BUILD_ID" --project "$GCP_PROJECT"
  else
    printf '  To tail later:\n    gcloud builds log --stream %s --project %s\n' "$_GKE_BUILD_ID" "$GCP_PROJECT"
  fi
  _GKE_BUILD_STATUS=$(gcloud builds describe "$_GKE_BUILD_ID" \
    --project "$GCP_PROJECT" --format="value(status)" 2>/dev/null || true)
  [[ "$_GKE_BUILD_STATUS" == "SUCCESS" ]] || {
    printf '[deploy] GKE build %s — status: %s\n' "$_GKE_BUILD_ID" "$_GKE_BUILD_STATUS" >&2
    exit 1
  }

  BACKEND_URL="<check GKE ingress — kubectl get ingress dash-backend -n ${K8S_NAMESPACE}>"
  printf '\nDone. Check ingress IP:\n  kubectl get ingress dash-backend -n %s\n' "$K8S_NAMESPACE"
else
  printf '\n=== deploying via Pulumi ===\n'
  cd "$ROOT_DIR/infra"
  [[ -d node_modules ]] || npm install --prefer-offline 2>/dev/null || npm install
  pulumi stack select "$DEPLOY_MODE" 2>/dev/null || pulumi stack init "$DEPLOY_MODE"
  if [[ "$DEPLOY_MODE" == "lite" ]]; then
    cat > "Pulumi.${DEPLOY_MODE}.yaml" <<PYAML
config:
  gcp:project: ${GCP_PROJECT}
  gcp:region: ${GCP_REGION}
  dashboard:namePrefix: dash-lite
  dashboard:dbTier: db-g1-small
  dashboard:dbDiskGb: "10"
  dashboard:minInstanceCount: "0"
  dashboard:maxInstanceCount: "1"
  dashboard:cpu: "1"
  dashboard:memory: 512Mi
  dashboard:backendImage: ${IMAGE}
PYAML
  else
    cat > "Pulumi.${DEPLOY_MODE}.yaml" <<PYAML
config:
  gcp:project: ${GCP_PROJECT}
  gcp:region: ${GCP_REGION}
  dashboard:namePrefix: dash
  dashboard:dbTier: db-custom-4-16384
  dashboard:dbDiskGb: "35"
  dashboard:minInstanceCount: "1"
  dashboard:maxInstanceCount: "5"
  dashboard:cpu: "2"
  dashboard:memory: 1Gi
  dashboard:backendImage: ${IMAGE}
PYAML
  fi
  _pulumi_up_robust

  BACKEND_URL=$(pulumi stack output backendUrl 2>/dev/null || \
    gcloud run services describe dash-backend \
      --region "$GCP_REGION" --project "$GCP_PROJECT" \
      --format="value(status.url)" 2>/dev/null || true)

  cat > "$ENV_FILE" <<EOF
CLOUD_SQL_INSTANCE=$(pulumi stack output cloudSqlInstance 2>/dev/null || true)
ARTIFACT_REGISTRY=$(pulumi stack output artifactRegistry 2>/dev/null || true)
CLOUD_RUN_URL=${BACKEND_URL}
GCP_PROJECT=${GCP_PROJECT}
GCP_REGION=${GCP_REGION}
EOF

  printf '\nDone. Backend URL:\n  %s\n' "$BACKEND_URL"
fi

_DB_URL="$("$ROOT_DIR/scripts/database-url.sh" 2>/dev/null || true)"
if [[ -n "$_DB_URL" ]]; then
  _TOKEN_ROWS=$(psql "$_DB_URL" -Atqc "SELECT count(*) FROM daily_customer_token_category_summary" 2>/dev/null || echo "0")
  if [[ "$_TOKEN_ROWS" == "0" ]]; then
    printf '\nDatabase needs seeding — running prepare-demo-data.sh (snapshot restore or full seed)...\n'
    DEMO_SNAPSHOT_GCS_URI="gs://bikram-java-dash-snapshots/dash/demo.dump" \
      DATABASE_URL="$_DB_URL" \
      "$ROOT_DIR/scripts/prepare-demo-data.sh"

    printf '\nRe-baking snapshot to GCS...\n'
    DEMO_SNAPSHOT_GCS_URI="gs://bikram-java-dash-snapshots/dash/demo.dump" \
      DATABASE_URL="$_DB_URL" \
      "$ROOT_DIR/scripts/bake-demo-snapshot.sh"
  else
    printf '\nDatabase already seeded (%s token rows) — skipping seed.\n' "$_TOKEN_ROWS"
  fi
else
  printf '\n(Could not resolve DATABASE_URL — skipping seed check.)\n'
fi

printf '\nRemember to tear down when finished:\n'
printf '  ./scripts/infra-down.sh\n'
