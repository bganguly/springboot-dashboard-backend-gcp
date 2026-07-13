#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
INFRA_DIR="$ROOT_DIR/infra"

# ── Detect independent Pulumi stack state ────────────────────────────────────
_local_running=0
_lite_count=0
_full_count=0

lsof -ti:8080 >/dev/null 2>&1 && _local_running=1 || true

_pulumi_stack_count() {
  local stack="$1"
  ( cd "$INFRA_DIR" 2>/dev/null && \
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

if command -v pulumi >/dev/null 2>&1 && pulumi whoami >/dev/null 2>&1; then
  _lite_count=$(_pulumi_stack_count lite)
  _full_count=$(_pulumi_stack_count full)
fi

# ── Show menu with detected state ────────────────────────────────────────────
printf '\n=== springboot-dashboard-backend-gcp teardown ===\n\n'
printf '  [1] Local  — stop local backend (port 8080)'
(( _local_running )) && printf ' [running]' || printf ' [not detected]'
printf '\n'
printf '  [2] Lite   — destroy GCP lite (e2-medium backend VM + e2-standard-2 Postgres VM, dash-lite-*)'
(( _lite_count > 0 )) && printf ' [%s resources active]' "$_lite_count" || printf ' [not deployed]'
printf '\n'
printf '  [3] Full   — destroy GCP full (e2-standard-2 backend VM + n2-standard-4 Postgres VM, dash-*)'
(( _full_count > 0 )) && printf ' [%s resources active]' "$_full_count" || printf ' [not deployed]'
printf '\n'
printf '\nChoice [1/2/3]: '
read -r _MODE
case "$_MODE" in
  2) _TARGET="remote"; DEPLOY_MODE="lite" ;;
  3) _TARGET="remote"; DEPLOY_MODE="full" ;;
  *)  _TARGET="local";  DEPLOY_MODE=""    ;;
esac

# ══════════════════════════════════════════════════════════════════════════════
# LOCAL
# ══════════════════════════════════════════════════════════════════════════════
if [[ "$_TARGET" == "local" ]]; then
  printf '\nStopping local backend (port 8080)...\n'
  "$ROOT_DIR/scripts/free-port.sh" 8080

  printf '\nDrop local database (database_flyway_orm)? [y/N] '
  read -r drop_db
  if [[ "$drop_db" =~ ^[Yy]$ ]]; then
    dropdb database_flyway_orm 2>/dev/null && printf 'Database dropped.\n' || printf 'Database not found — skipping.\n'
  fi

  printf 'Local infrastructure torn down.\n'
  exit 0
fi

# ══════════════════════════════════════════════════════════════════════════════
# REMOTE (GCP)
# ══════════════════════════════════════════════════════════════════════════════

ENV_FILE="$ROOT_DIR/.env.gcp.${DEPLOY_MODE}"

PULUMI_USER=$(pulumi whoami 2>/dev/null || true)
[[ -n "$PULUMI_USER" ]] || { printf 'Not logged in to Pulumi. Run: pulumi login\n' >&2; exit 1; }

[[ -f "$ENV_FILE" ]] && source "$ENV_FILE"

GCP_PROJECT="${GCP_PROJECT:-$(gcloud config get-value project 2>/dev/null || true)}"
GCP_PROJECT="${GCP_PROJECT:-bikram-java}"
GCP_REGION="${GCP_REGION:-$(gcloud config get-value compute/region 2>/dev/null || true)}"
GCP_REGION="${GCP_REGION:-us-central1}"

[[ -n "$GCP_PROJECT" ]] || { printf 'GCP project could not be detected. Set GCP_PROJECT or run: gcloud config set project <id>\n' >&2; exit 1; }

printf '\n[infra-down] project: %s  region: %s\n' "$GCP_PROJECT" "$GCP_REGION"
printf '[infra-down] Destroying Cloud Run, Postgres VM, VPC, Secret Manager, Artifact Registry...\n'

cd "$INFRA_DIR"
npm install --prefer-offline 2>/dev/null || npm install

pulumi stack select "$DEPLOY_MODE"
pulumi config set gcp:project "$GCP_PROJECT"
pulumi config set gcp:region  "$GCP_REGION"

_EXPECTED_PREFIX=$([[ "$DEPLOY_MODE" == "lite" ]] && printf 'dash-lite' || printf 'dash')
_STACK_PREFIX=$(pulumi config get namePrefix 2>/dev/null || true)
if [[ -n "$_STACK_PREFIX" && "$_STACK_PREFIX" != "$_EXPECTED_PREFIX" ]]; then
  printf '\n[infra-down] WARNING: %s stack has namePrefix=%s but expected %s.\n' "$DEPLOY_MODE" "$_STACK_PREFIX" "$_EXPECTED_PREFIX" >&2
  printf '  This stack may contain resources from a different mode — destroying may affect other environments.\n' >&2
  printf 'Proceed anyway? [y/N] '
  read -r _SAFEGUARD
  [[ "$_SAFEGUARD" =~ ^[Yy]$ ]] || { printf 'Aborted.\n'; exit 0; }
fi
printf '\n[infra-down] Targeting namePrefix=%s (only %s-* GCP resources will be deleted).\n' "$_EXPECTED_PREFIX" "$_EXPECTED_PREFIX"

_pulumi_destroy_robust() {
  local log_file
  log_file="$(mktemp)"
  local attempt=0 rc stale_urns

  while true; do
    attempt=$(( attempt + 1 ))
    set +e
    pulumi destroy --yes 2>&1 | tee "$log_file"
    rc="${PIPESTATUS[0]}"
    set -e

    if [[ "$rc" == "0" ]]; then
      rm -f "$log_file"
      return 0
    fi

    stale_urns=$(grep -oE 'error: deleting urn:pulumi:[^ ]+' "$log_file" \
      | sed 's/^error: deleting //; s/:$//' | sort -u || true)

    if [[ -z "$stale_urns" ]]; then
      rm -f "$log_file"
      printf '[infra-down] pulumi destroy failed with no extractable URNs — cannot auto-recover.\n' >&2
      return 1
    fi

    printf '[infra-down] Auto-purging stale state entries (attempt %d)...\n' "$attempt"
    while IFS= read -r urn; do
      [[ -z "$urn" ]] && continue
      printf '  purging: %s\n' "$urn"
      pulumi state delete "$urn" --yes 2>/dev/null || true
    done <<< "$stale_urns"
  done
}

_pulumi_destroy_robust

rm -f "$ENV_FILE"
printf '\n[infra-down] done — GCP %s resources destroyed, project %s preserved.\n' "$DEPLOY_MODE" "$GCP_PROJECT"
printf '[infra-down] NOTE: gs://bikram-java-dash-snapshots/ is intentionally preserved (not managed by Pulumi).\n'

FRONTEND_DOWN="$(cd "$ROOT_DIR/../dashboard-frontend-gcp/scripts" 2>/dev/null && pwd || true)/infra-down.sh"
if [[ -f "$FRONTEND_DOWN" ]]; then
  printf '\n  Chaining frontend (%s) teardown...\n' "$DEPLOY_MODE"
  DEPLOY_MODE="$DEPLOY_MODE" bash "$FRONTEND_DOWN"
fi
