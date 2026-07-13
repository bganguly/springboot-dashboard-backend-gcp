#!/usr/bin/env bash
set -euo pipefail

TIER="${TIER:-lite}"
PROJECT="bikram-java"
LOCATION="us-central1"
PREFIX="dash-${TIER}"
CMD="${1:-}"

usage() {
  printf 'usage: TIER=lite|full %s up|down|pause|resume\n' "$(basename "$0")" >&2
  exit 1
}

[[ -z "$CMD" ]] && usage

case "$CMD" in
  up)
    gcloud scheduler jobs run "${PREFIX}-scale-up-backend" \
      --location "$LOCATION" --project "$PROJECT"
    printf 'Scaled up: %s-backend now has min=1.\n' "$PREFIX"
    ;;
  down)
    gcloud scheduler jobs run "${PREFIX}-scale-down-backend" \
      --location "$LOCATION" --project "$PROJECT"
    printf 'Scaled down: %s-backend now has min=0.\n' "$PREFIX"
    ;;
  pause)
    gcloud scheduler jobs pause "${PREFIX}-scale-up-backend" \
      --location "$LOCATION" --project "$PROJECT"
    gcloud scheduler jobs pause "${PREFIX}-scale-down-backend" \
      --location "$LOCATION" --project "$PROJECT"
    printf 'Schedule paused for %s-backend.\n' "$PREFIX"
    ;;
  resume)
    gcloud scheduler jobs resume "${PREFIX}-scale-up-backend" \
      --location "$LOCATION" --project "$PROJECT"
    gcloud scheduler jobs resume "${PREFIX}-scale-down-backend" \
      --location "$LOCATION" --project "$PROJECT"
    printf 'Schedule resumed for %s-backend.\n' "$PREFIX"
    ;;
  *)
    usage
    ;;
esac
