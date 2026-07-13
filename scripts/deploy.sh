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
printf '  [2] Lite   — GCP: e2-medium backend VM + e2-standard-2 Postgres VM'
(( _lite_count > 0 )) && printf ' [%s resources active]' "$_lite_count" || printf ' [not deployed]'
printf '\n'
printf '  [3] Full   — GCP: e2-standard-2 backend VM + n2-standard-4 Postgres VM'
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
    printf '  Backend:    e2-medium GCE VM running Spring Boot in Docker\n'
    printf '  DB:         e2-standard-2 Postgres 16 VM (2 vCPU, 8 GB), 20 GB SSD\n'
    printf '  GKE:        skipped\n'
    printf '  Cost est:   ~$50-70/mo if left running\n'
  else
    printf '\n--- Full GCP summary ---\n'
    printf '  Backend:    e2-standard-2 GCE VM running Spring Boot in Docker\n'
    printf '  DB:         n2-standard-4 Postgres 16 VM (4 vCPU, 16 GB), 35 GB SSD\n'
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

  command -v psql >/dev/null 2>&1 || fail "psql not found — install Postgres (brew install postgresql@16)"
  ok "psql" "$(psql --version)"

  if ! pg_isready >/dev/null 2>&1; then
    printf '  postgres: not running — starting...\n'
    if command -v brew >/dev/null 2>&1; then
      brew services start postgresql@16 2>/dev/null || brew services start postgresql 2>/dev/null || true
      sleep 2
    fi
    pg_isready >/dev/null 2>&1 || fail "Postgres did not start. Install: brew install postgresql@16"
  fi
  ok "postgres" "ready"

  if ! psql -Atqc \
      "SELECT 1 FROM pg_available_extensions WHERE name='pg_bigm'" \
      2>/dev/null | grep -q 1; then
    printf '  pg_bigm not found — building from source...\n'
    _pg_cfg=$(brew --prefix postgresql@16)/bin/pg_config
    _tmp=$(mktemp -d)
    git clone --depth 1 https://github.com/pgbigm/pg_bigm.git "$_tmp/pg_bigm"
    make -C "$_tmp/pg_bigm" USE_PGXS=1 PG_CONFIG="$_pg_cfg"
    make -C "$_tmp/pg_bigm" USE_PGXS=1 PG_CONFIG="$_pg_cfg" install
    rm -rf "$_tmp"
    printf '  pg_bigm installed — restarting postgresql@16...\n'
    brew services restart postgresql@16
    for _i in $(seq 1 10); do pg_isready -q 2>/dev/null && break; sleep 1; done
  fi

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
    psql -d "$DB" -f src/main/resources/db/migration/V4__search_text.sql
    psql -d "$DB" -f src/main/resources/db/migration/V5__customer_sort_index.sql
    psql -d "$DB" -f src/main/resources/db/migration/V6__count_cache.sql
    psql -d "$DB" -f src/main/resources/db/migration/V7__daily_order_count.sql

    printf '[3/4] seeding %s orders...\n' "$ORDERS"
    psql -d "$DB" -v orders="$ORDERS" -f scripts/seed-large.sql

    printf '[4/4] rebuilding read model rollups...\n'
    psql -d "$DB" -f scripts/rebuild-dashboard-read-models.sql

    printf '\nSetup complete.\n'
  else
    ok "database" "$DB (exists — skipping setup)"
  fi

  if psql -d "$DB" -Atqc "SELECT 1 FROM pg_available_extensions WHERE name='pg_bigm'" 2>/dev/null | grep -q 1; then
    _missing_bigm=$(psql -d "$DB" -Atqc \
      "SELECT COUNT(*) FROM pg_indexes WHERE indexname IN ('idx_orders_search_text_bigm','idx_orders_notes_bigm','idx_customers_bigm')" \
      2>/dev/null || echo 0)
    _build_bigm_index() {
      local label="$1" sql="$2"
      printf '  [bigm] %s ... ' "$label"
      psql -d "$DB" -c "$sql" &
      local bg=$!
      local dots=0
      while kill -0 "$bg" 2>/dev/null; do
        sleep 3
        _pct=$(psql -d "$DB" -Atqc \
          "SELECT COALESCE(ROUND(100*blocks_done::numeric/NULLIF(blocks_total,0)),0) FROM pg_stat_progress_create_index WHERE relid=(SELECT oid FROM pg_class WHERE relname IN ('orders','customers') LIMIT 1) LIMIT 1" \
          2>/dev/null)
        if [[ -n "$_pct" && "$_pct" != "0" ]]; then
          printf '\r  [bigm] %s ... %s%%   ' "$label" "$_pct"
        else
          dots=$(( (dots+1) % 4 ))
          printf '\r  [bigm] %s ... %s   ' "$label" "$(printf '%0.s.' $(seq 1 $((dots+1))))"
        fi
      done
      wait "$bg" && printf '\r  [bigm] %s ... done        \n' "$label" || { printf '\r  [bigm] %s ... FAILED (rc=%d)\n' "$label" "$?"; return 1; }
    }

    if [[ "$_missing_bigm" -lt 3 ]]; then
      printf '\n=== building pg_bigm search indexes (one-time) ===\n'
      psql -d "$DB" -c "CREATE EXTENSION IF NOT EXISTS pg_bigm;" 2>/dev/null
      _build_bigm_index "idx_orders_search_text_bigm" \
        "CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_orders_search_text_bigm ON orders USING gin (search_text gin_bigm_ops);"
      _build_bigm_index "idx_orders_notes_bigm" \
        "CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_orders_notes_bigm ON orders USING gin (notes gin_bigm_ops);"
      _build_bigm_index "idx_customers_bigm" \
        "CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_customers_bigm ON customers USING gin ((\"firstName\"||' '||\"lastName\"||' '||email) gin_bigm_ops);"
      psql -d "$DB" -c "DROP INDEX IF EXISTS idx_orders_search_text_trgm;" 2>/dev/null
      psql -d "$DB" -c "DROP INDEX IF EXISTS idx_orders_notes_trgm;" 2>/dev/null
      psql -d "$DB" -c "DROP INDEX IF EXISTS idx_customers_trgm;" 2>/dev/null
      printf '  pg_bigm indexes ready.\n'
    else
      ok "pg_bigm indexes" "already in place"
    fi
  fi

  printf '\n=== diagnostics ===\n'
  DATABASE_URL="$DB_URL" ./scripts/diagnose.sh

  BACKEND_LOG="$ROOT_DIR/backend.log"
  printf '\n=== starting backend :8080 ===\n'
  "$ROOT_DIR/scripts/free-port.sh" 8080
  DATABASE_URL="$DB_URL" ./gradlew bootRun > "$BACKEND_LOG" 2>&1 &
  BACKEND_PID=$!
  printf '  backend PID %s — tailing %s\n' "$BACKEND_PID" "$BACKEND_LOG"
  printf '  waiting for :8080...\n'
  for _i in $(seq 1 60); do
    sleep 2
    if lsof -ti:8080 >/dev/null 2>&1; then break; fi
    if ! kill -0 "$BACKEND_PID" 2>/dev/null; then
      printf '\n  backend exited — check %s\n' "$BACKEND_LOG"
      tail -30 "$BACKEND_LOG"
      exit 1
    fi
  done
  printf '  backend ready\n'

  FRONTEND_DIR="$ROOT_DIR/../dashboard-frontend-gcp"
  if [[ -d "$FRONTEND_DIR" ]]; then
    printf '\n=== starting frontend :3006 ===\n'
    cd "$FRONTEND_DIR"
    npm install --prefer-offline 2>/dev/null || npm install
    "$FRONTEND_DIR/scripts/free-port.sh" 3006
    printf '  API explorer → http://localhost:3006\n'
    printf '  Static explorer → http://localhost:8080/explorer.html\n'
    printf '  Backend logs → tail -f %s\n\n' "$BACKEND_LOG"
    BACKEND_URL="http://localhost:8080" npm run dev
  else
    printf '\n  dashboard-frontend-gcp not found — backend only\n'
    wait "$BACKEND_PID"
  fi

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
  DEPLOY_TARGET="vm"
  printf '\n  [lite] Skipping GKE — deploying to GCE VM.\n'
else
  _GKE_EXISTS=$(gcloud container clusters describe "${GKE_CLUSTER:-dash-gke-cluster}" \
    --zone "${GCP_REGION}-a" --project "$GCP_PROJECT" --format="value(name)" 2>/dev/null || true)
  if [[ -n "$_GKE_EXISTS" ]]; then
    DEPLOY_TARGET="gke"
    printf '\n  GKE cluster detected — redeploying to GKE.\n'
  else
    printf '\n=== STOPPED ===================================================\n'
    printf '  Deploy to GKE (Kubernetes)?  Y = GKE  /  n = GCE VM\n'
    printf '===============================================================\n'
    read -r -p "Deploy to GKE? [Y/n]: " _CHOICE
    case "$_CHOICE" in
      [nN]*) DEPLOY_TARGET="vm" ;;
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
            if not id_m:
                # "failed to create instance <name>: ... already exists"
                cm = re.search(r'failed to create \w+ ([^:\s]+):', lines[j])
                if cm and re.search(r'already exists|instanceAlreadyExists', lines[j]):
                    id_m = cm
            if id_m:
                key = f'{type_display}|{logical_name}|{id_m.group(1)}'
                if key not in seen:
                    seen.add(key)
                    print(key)
                break
PYEOF
    2>/dev/null || true)

    if [[ -z "$conflicts" ]]; then
      local deletion_fail_urns
      deletion_fail_urns=$(grep -oE 'error: deleting urn:pulumi:[^ ]+' "$log_file" \
        | sed 's/^error: deleting //; s/:$//' | sort -u || true)
      if [[ -n "$deletion_fail_urns" ]]; then
        printf '[deploy] Auto-purging stale state entries that GCP refused to delete...\n'
        while IFS= read -r urn; do
          [[ -z "$urn" ]] && continue
          printf '  purging: %s\n' "$urn"
          pulumi state delete "$urn" --yes 2>/dev/null || true
        done <<< "$deletion_fail_urns"
        continue
      fi
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
      if grep -qE 'Error waiting for Create Instance' "$log_file" 2>/dev/null; then
        local _pending _wait_i=0
        _pending=$(gcloud sql instances list \
          --project "$GCP_PROJECT" \
          --filter="state=PENDING_CREATE" \
          --format="value(name)" 2>/dev/null || true)
        if [[ -n "$_pending" ]]; then
          printf '[deploy] GCE instance still creating (%s) — waiting for RUNNABLE (up to 15 min)...\n' "$_pending"
          while (( _wait_i < 30 )); do
            _wait_i=$(( _wait_i + 1 ))
            sleep 30
            _pending=$(gcloud sql instances list \
              --project "$GCP_PROJECT" \
              --filter="state=PENDING_CREATE" \
              --format="value(name)" 2>/dev/null || true)
            [[ -z "$_pending" ]] && break
            printf '  still creating... (%d/30)\n' "$_wait_i"
          done
          printf '[deploy] GCE instance ready — retrying pulumi up...\n'
          continue
        fi
      fi
      printf '\n[deploy] pulumi up failed — actual errors:\n' >&2
      grep -E 'error:|Error|failed|FAIL' "$log_file" | head -20 >&2 || true
      rm -f "$log_file"
      return 1
    fi

    printf '[deploy] Auto-importing conflicting resources (attempt %d)...\n' "$attempt"
    while IFS='|' read -r type_display logical_name gcp_id; do
      [[ -z "$type_display" ]] && continue
      local module type_name import_type import_id
      module=$(printf '%s' "$type_display" | cut -d: -f2)
      type_name=$(printf '%s' "$type_display" | cut -d: -f3)
      import_type="gcp:${module}/${type_name,}:${type_name}"
      import_id="$gcp_id"
      if [[ "$module" == "cloudrunv2" && "${type_name,,}" == "service" && "$import_id" != projects/* ]]; then
        import_id="projects/${GCP_PROJECT}/locations/${GCP_REGION}/services/${import_id}"
      fi
      printf '  importing: %s %s = %s\n' "$import_type" "$logical_name" "$import_id"
      pulumi import "$import_type" "$logical_name" "$import_id" --yes 2>/dev/null || true
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
    printf '\n=== provisioning Postgres VM + networking + secrets via Pulumi (required by GKE) ===\n'
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
  dashboard:dbVmType: e2-standard-2
  dashboard:dbDiskGb: "20"
  dashboard:backendVmType: e2-medium
  dashboard:backendImage: ${IMAGE}
PYAML
    else
      DEPLOY_MODE_PREFIX="dash"
      cat > "Pulumi.${DEPLOY_MODE}.yaml" <<PYAML
config:
  gcp:project: ${GCP_PROJECT}
  gcp:region: ${GCP_REGION}
  dashboard:namePrefix: dash
  dashboard:dbVmType: n2-standard-4
  dashboard:dbDiskGb: "35"
  dashboard:backendVmType: e2-standard-2
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
  DEPLOY_MODE_PREFIX=$([[ "$DEPLOY_MODE" == "lite" ]] && printf 'dash-lite' || printf 'dash')

  _LEGACY_CR="${DEPLOY_MODE_PREFIX}-backend"
  _CR_EXISTS=$(gcloud run services describe "$_LEGACY_CR" \
    --region "$GCP_REGION" --project "$GCP_PROJECT" \
    --format="value(name)" 2>/dev/null || true)
  if [[ -n "$_CR_EXISTS" ]]; then
    printf '  Deleting legacy Cloud Run service %s...\n' "$_LEGACY_CR"
    gcloud run services delete "$_LEGACY_CR" \
      --region "$GCP_REGION" --project "$GCP_PROJECT" --quiet
  fi

  if [[ "$DEPLOY_MODE" == "lite" ]]; then
    cat > "Pulumi.${DEPLOY_MODE}.yaml" <<PYAML
config:
  gcp:project: ${GCP_PROJECT}
  gcp:region: ${GCP_REGION}
  dashboard:namePrefix: dash-lite
  dashboard:dbVmType: e2-standard-2
  dashboard:dbDiskGb: "20"
  dashboard:backendVmType: e2-medium
  dashboard:backendImage: ${IMAGE}
PYAML
  else
    cat > "Pulumi.${DEPLOY_MODE}.yaml" <<PYAML
config:
  gcp:project: ${GCP_PROJECT}
  gcp:region: ${GCP_REGION}
  dashboard:namePrefix: dash
  dashboard:dbVmType: n2-standard-4
  dashboard:dbDiskGb: "35"
  dashboard:backendVmType: e2-standard-2
  dashboard:backendImage: ${IMAGE}
PYAML
  fi
  _pulumi_up_robust

  printf '\n  Resetting DB VM (sentinel guards against re-init if already done)...\n'
  gcloud compute instances reset "${DEPLOY_MODE_PREFIX}-pg" \
    --zone "${GCP_REGION}-a" --project "$GCP_PROJECT" --quiet || true
  printf '  DB VM reset — Postgres init takes ~3-5 min on first boot.\n'

  printf '\n  Resetting backend VM to apply new image...\n'
  gcloud compute instances reset "${DEPLOY_MODE_PREFIX}-backend" \
    --zone "${GCP_REGION}-a" --project "$GCP_PROJECT" --quiet || true
  printf '  VM reset — startup script will pull the image and start Spring Boot (~3-5 min).\n'

  BACKEND_URL=$(pulumi stack output backendUrl 2>/dev/null || \
    gcloud compute instances describe "${DEPLOY_MODE_PREFIX}-backend" \
      --zone "${GCP_REGION}-a" --project "$GCP_PROJECT" \
      --format="value(networkInterfaces[0].accessConfigs[0].natIP)" 2>/dev/null \
      | awk '{print "http://" $1 ":8080"}' || true)

  cat > "$ENV_FILE" <<EOF
DB_VM_IP=$(pulumi stack output dbVmInternalIp 2>/dev/null || true)
ARTIFACT_REGISTRY=$(pulumi stack output artifactRegistry 2>/dev/null || true)
CLOUD_RUN_URL=${BACKEND_URL}
GCP_PROJECT=${GCP_PROJECT}
GCP_REGION=${GCP_REGION}
EOF

  printf '\nDone. Backend URL:\n  %s\n' "$BACKEND_URL"
fi

if [[ "$DEPLOY_MODE" == "lite" ]]; then
  DEMO_SNAPSHOT_GCS_URI="gs://bikram-java-dash-snapshots/dash/demo-lite.dump"
  BAKE_VM_NAME="dash-bake-vm"
  BAKE_VM_NETWORK="dash-lite-vpc"
  BAKE_VM_SUBNET="dash-lite-subnet"
  BAKE_SECRET_NAME="dash-lite-database-url"
  S3_SOURCE_URI="s3://bikram-nextjs-subsecond-fetch-with-websockets/nextjs-dash/demo-lite.dump"
else
  DEMO_SNAPSHOT_GCS_URI="gs://bikram-java-dash-snapshots/dash/demo.dump"
  BAKE_VM_NAME="dash-bake-vm"
  BAKE_VM_NETWORK="dash-vpc"
  BAKE_VM_SUBNET="dash-subnet"
  BAKE_SECRET_NAME="dash-database-url"
  S3_SOURCE_URI="s3://bikram-nextjs-subsecond-fetch-with-websockets/nextjs-dash/demo.dump"
fi

printf '\nChecking database...\n'
_API_ORDERS=""
for _i in 1 2 3 4 5; do
  _API_ORDERS=$(curl -sf "${BACKEND_URL}/api/orders?page=0&size=1" 2>/dev/null \
    | python3 -c "import sys,json;d=json.load(sys.stdin);print(d.get('total',0))" \
    2>/dev/null || true)
  [[ -n "$_API_ORDERS" ]] && break
  printf '  waiting for backend (%d/5)...\n' "$_i"; sleep 10
done

if [[ -z "$_API_ORDERS" ]]; then
  printf '(Backend unreachable — skipping seed check)\n'
elif [[ "$_API_ORDERS" != "0" ]]; then
  printf 'Database has %s orders — skipping seed.\n' "$_API_ORDERS"
else
  printf 'Database empty — starting VM bake...\n'

  _AWS_SECRET_OK=$(gcloud secrets versions access latest \
    --secret="dash-aws-credentials" --project="$GCP_PROJECT" >/dev/null 2>&1 && printf 'yes' || printf '')
  if [[ -z "$_AWS_SECRET_OK" ]]; then
    printf '\nERROR: Secret "dash-aws-credentials" not found in project %s.\n' "$GCP_PROJECT"
    printf 'Create it once with:\n'
    printf '  printf "AWS_ACCESS_KEY_ID=...\\nAWS_SECRET_ACCESS_KEY=...\\nAWS_DEFAULT_REGION=us-east-1" \\\n'
    printf '    | gcloud secrets create dash-aws-credentials --data-file=- --project=%s\n' "$GCP_PROJECT"
    printf 'Then re-run this script.\n'
    exit 1
  fi

  gcloud compute firewall-rules describe "${BAKE_VM_NETWORK}-allow-iap-ssh" \
    --project="$GCP_PROJECT" >/dev/null 2>&1 || \
  gcloud compute firewall-rules create "${BAKE_VM_NETWORK}-allow-iap-ssh" \
    --project="$GCP_PROJECT" --network="$BAKE_VM_NETWORK" \
    --direction=INGRESS --source-ranges=35.235.240.0/20 \
    --allow=tcp:22 --quiet

  gcloud compute networks subnets update "$BAKE_VM_SUBNET" \
    --project="$GCP_PROJECT" --region="$GCP_REGION" \
    --enable-private-ip-google-access --quiet 2>/dev/null || true

  if ! gcloud compute instances describe "$BAKE_VM_NAME" \
      --zone="${GCP_REGION}-a" --project="$GCP_PROJECT" \
      --format="value(name)" >/dev/null 2>&1; then
    printf '  Creating bake VM...\n'
    gcloud compute instances create "$BAKE_VM_NAME" \
      --project="$GCP_PROJECT" --zone="${GCP_REGION}-a" \
      --machine-type=n2-standard-8 \
      --image-family=debian-12 --image-project=debian-cloud \
      --boot-disk-size=50GB \
      --network="$BAKE_VM_NETWORK" --subnet="$BAKE_VM_SUBNET" \
      --no-address --scopes=cloud-platform --quiet
    printf '  Waiting for VM startup...\n'; sleep 30
  fi

  gcloud compute ssh "$BAKE_VM_NAME" \
    --project="$GCP_PROJECT" --zone="${GCP_REGION}-a" \
    --tunnel-through-iap --ssh-flag="-o ConnectTimeout=30" \
    --command='command -v pg_restore >/dev/null 2>&1 || (
      echo "deb http://apt.postgresql.org/pub/repos/apt bookworm-pgdg main" \
        | sudo tee /etc/apt/sources.list.d/pgdg.list &&
      curl -fsSL https://www.postgresql.org/media/keys/ACCC4CF8.asc \
        | sudo gpg --dearmor -o /etc/apt/trusted.gpg.d/postgresql.gpg &&
      sudo apt-get update -qq &&
      sudo apt-get install -y postgresql-client-16 awscli
    )' 2>/dev/null

  _BAKE_SCRIPT=$(mktemp)
  _GCS_BASENAME=$(basename "$DEMO_SNAPSHOT_GCS_URI")
  cat > "$_BAKE_SCRIPT" << BAKE_EOF
#!/bin/bash
set -euo pipefail
PROJECT="${GCP_PROJECT}"
SECRET="${BAKE_SECRET_NAME}"
GCS_BASENAME="${_GCS_BASENAME}"
S3_URI="${S3_SOURCE_URI}"

echo "=== fetching DB URL ==="
TOKEN=\$(curl -sf http://metadata.google.internal/computeMetadata/v1/instance/service-accounts/default/token \
  -H Metadata-Flavor:Google | python3 -c "import sys,json;print(json.load(sys.stdin)['access_token'])")
DB_URL=\$(curl -sf \
  "https://secretmanager.googleapis.com/v1/projects/\${PROJECT}/secrets/\${SECRET}/versions/latest:access" \
  -H "Authorization: Bearer \${TOKEN}" \
  | python3 -c "import sys,json,base64;print(base64.b64decode(json.load(sys.stdin)['payload']['data']).decode())")
echo "DB URL resolved."

echo "=== checking GCS snapshot ==="
GCS_EXISTS=\$(curl -sf \
  "https://storage.googleapis.com/storage/v1/b/bikram-java-dash-snapshots/o/dash%2F\${GCS_BASENAME}" \
  -H "Authorization: Bearer \${TOKEN}" 2>/dev/null | python3 -c "import sys,json;print('yes')" 2>/dev/null || echo "no")

if [[ "\$GCS_EXISTS" == "yes" ]]; then
  echo "=== restoring from GCS ==="
  curl -fL \
    "https://storage.googleapis.com/storage/v1/b/bikram-java-dash-snapshots/o/dash%2F\${GCS_BASENAME}?alt=media" \
    -H "Authorization: Bearer \${TOKEN}" -o /tmp/bake.dump
else
  echo "=== GCS snapshot missing — fetching AWS creds ==="
  AWS_SECRET_NAME="dash-aws-credentials"
  AWS_CREDS=\$(curl -sf \
    "https://secretmanager.googleapis.com/v1/projects/\${PROJECT}/secrets/\${AWS_SECRET_NAME}/versions/latest:access" \
    -H "Authorization: Bearer \${TOKEN}" \
    | python3 -c "import sys,json,base64;print(base64.b64decode(json.load(sys.stdin)['payload']['data']).decode())")
  export \$(echo "\$AWS_CREDS" | grep -E '^AWS_' | xargs)

  echo "=== downloading from S3 ==="
  aws s3 cp "\$S3_URI" /tmp/bake.dump

  echo "=== will save to GCS after restore ==="
  SAVE_TO_GCS="yes"
fi

echo "=== running pg_restore ==="
pg_restore --no-owner --no-privileges --clean --if-exists \
  -d "\$DB_URL" /tmp/bake.dump || true

if [[ "\${SAVE_TO_GCS:-no}" == "yes" ]]; then
  echo "=== saving snapshot to GCS for future deploys ==="
  curl -sf \
    "https://storage.googleapis.com/upload/storage/v1/b/bikram-java-dash-snapshots/o?uploadType=media&name=dash%2F\${GCS_BASENAME}" \
    -H "Authorization: Bearer \${TOKEN}" \
    -H "Content-Type: application/octet-stream" \
    --data-binary @/tmp/bake.dump
fi

rm -f /tmp/bake.dump
echo "=== done ==="
BAKE_EOF

  gcloud compute scp "$_BAKE_SCRIPT" \
    "${BAKE_VM_NAME}:/tmp/bake.sh" \
    --project="$GCP_PROJECT" --zone="${GCP_REGION}-a" \
    --tunnel-through-iap --quiet 2>/dev/null
  rm -f "$_BAKE_SCRIPT"

  printf '  Running restore on VM...\n'
  gcloud compute ssh "$BAKE_VM_NAME" \
    --project="$GCP_PROJECT" --zone="${GCP_REGION}-a" \
    --tunnel-through-iap --ssh-flag="-o ConnectTimeout=30" \
    --command='bash /tmp/bake.sh' 2>/dev/null

  printf '  Deleting bake VM...\n'
  gcloud compute instances delete "$BAKE_VM_NAME" \
    --zone="${GCP_REGION}-a" --project="$GCP_PROJECT" --quiet

  printf 'Seeding complete.\n'
fi

printf '\nRemember to tear down when finished:\n'
printf '  ./scripts/infra-down.sh\n'

if [[ "$_TARGET" == "remote" && -n "$DEPLOY_MODE" ]]; then
  _SET_LIVE="$(cd "$ROOT_DIR/../../portfolio/scripts" 2>/dev/null && pwd || true)/set-live-url.sh"
  if [[ -f "$_SET_LIVE" ]]; then
    printf '\nMarking dashboard backend live in portfolio...\n'
    bash "$_SET_LIVE" --backend-only --tier "$DEPLOY_MODE" dashboard
  fi
fi

FRONTEND_DEPLOY="$(cd "$ROOT_DIR/../dashboard-frontend-gcp/scripts" 2>/dev/null && pwd || true)/deploy.sh"
if [[ -f "$FRONTEND_DEPLOY" ]]; then
  printf '\n  Deploying frontend inline...\n'
  DEPLOY_MODE="$DEPLOY_MODE" bash "$FRONTEND_DEPLOY"
fi
