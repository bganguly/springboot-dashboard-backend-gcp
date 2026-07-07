#!/usr/bin/env bash
set -euo pipefail

# Single entry point: build the backend image, push it, and deploy via
# Pulumi. One-shot by default — every value below is auto-detected/derived
# with no confirmation prompt, matching the nextjs repos' deploy.sh scripts.
# The only interactive stops left are genuine forks in the road: gcloud/ADC
# login (no headless alternative exists) and the demo-scale reseed (a
# long-running, deliberate decision, not a safe default).

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

ENV_FILE="$ROOT_DIR/.env.gcp"

# ── gcloud install ────────────────────────────────────────────────────────────
if ! command -v gcloud >/dev/null 2>&1; then
  printf '\ngcloud CLI not found.\n'
  if command -v brew >/dev/null 2>&1; then
    printf 'Installing via Homebrew...\n'
    brew install --cask google-cloud-sdk
    # shellcheck source=/dev/null
    source "$(brew --prefix)/share/google-cloud-sdk/path.bash.inc" 2>/dev/null || true
  else
    printf 'Install it from: https://cloud.google.com/sdk/docs/install\nThen re-run this script.\n'
    exit 1
  fi
fi

# ── gcloud auth ───────────────────────────────────────────────────────────────
# No local-mode fallback for a GCP deploy (unlike nextjs's AWS scripts) — the
# login itself needs browser interaction either way, so trigger it directly
# instead of asking permission to ask.
ACTIVE_ACCOUNT=$(gcloud auth list --filter=status:ACTIVE --format="value(account)" 2>/dev/null | head -1 || true)
if [[ -z "$ACTIVE_ACCOUNT" ]]; then
  printf '\nNot authenticated with gcloud — logging in...\n'
  gcloud auth login
  ACTIVE_ACCOUNT=$(gcloud auth list --filter=status:ACTIVE --format="value(account)" 2>/dev/null | head -1 || true)
  [[ -n "$ACTIVE_ACCOUNT" ]] || { printf 'Login did not complete.\n' >&2; exit 1; }
fi
printf '\nAuthenticated as: %s\n' "$ACTIVE_ACCOUNT"

# ── seed known values ─────────────────────────────────────────────────────────
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

# ── Artifact Registry API + repo ──────────────────────────────────────────────
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

# ── check infra ───────────────────────────────────────────────────────────────
if [[ ! -f "$ENV_FILE" ]]; then
  printf '\n.env.gcp not found — provisioning infra first...\n'
  GCP_PROJECT="$GCP_PROJECT" GCP_REGION="$GCP_REGION" "$ROOT_DIR/scripts/infra-up.sh"
  [[ -f "$ENV_FILE" ]] && source "$ENV_FILE"
fi

printf '\nBuilding and pushing:\n  %s\n' "$IMAGE"
printf 'Then deploying to Cloud Run in %s.\n' "$GCP_REGION"

# ── build & push ──────────────────────────────────────────────────────────────
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

# ── application default credentials (required by Pulumi GCP provider) ─────────
if ! gcloud auth application-default print-access-token >/dev/null 2>&1; then
  printf '\nSetting up Application Default Credentials (required by the Pulumi GCP provider)...\n'
  gcloud auth application-default login
fi

# ── deploy via pulumi ─────────────────────────────────────────────────────────
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

# ── optional seed ─────────────────────────────────────────────────────────────
# Genuine fork in the road (long-running, not a safe default) — kept
# interactive, same as nextjs's demo-scale reseed prompt.
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
printf '  GCP_PROJECT=%s ./scripts/infra-down.sh\n' "$GCP_PROJECT"
