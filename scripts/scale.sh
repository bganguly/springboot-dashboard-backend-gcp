#!/usr/bin/env bash
set -euo pipefail

TIER="${TIER:-lite}"
PROJECT="bikram-java"
LOCATION="us-central1"
ZONE="${LOCATION}-a"
PREFIX="dash-${TIER}"
CLUSTER="${PREFIX}-cluster"
CMD="${1:-}"

_is_gke() {
  gcloud container clusters describe "$CLUSTER" \
    --zone "$ZONE" --project "$PROJECT" >/dev/null 2>&1
}

_gke_nodes() {
  gcloud container clusters describe "$CLUSTER" \
    --zone "$ZONE" --project "$PROJECT" \
    --format="value(currentNodeCount)" 2>/dev/null || echo "0"
}

_cr_min() {
  gcloud run services describe "${PREFIX}-backend" \
    --region "$LOCATION" --project "$PROJECT" \
    --format="value(spec.template.metadata.annotations['autoscaling.knative.dev/minScale'])" \
    2>/dev/null || echo "?"
}

_do_scale() {
  local cmd="$1"
  case "$cmd" in
    up)
      if _is_gke; then
        printf 'GKE — scaling node pool to 1...\n'
        gcloud container clusters resize "$CLUSTER" \
          --node-pool default-pool --num-nodes 1 \
          --zone "$ZONE" --project "$PROJECT" --quiet
        printf 'Node coming up; Spring Boot will be ready in ~2-3 min.\n'
      else
        gcloud scheduler jobs run "${PREFIX}-scale-up-backend" \
          --location "$LOCATION" --project "$PROJECT"
        printf 'Cloud Run min-instances set to 1.\n'
      fi
      ;;
    down)
      if _is_gke; then
        printf 'GKE — scaling node pool to 0...\n'
        gcloud container clusters resize "$CLUSTER" \
          --node-pool default-pool --num-nodes 0 \
          --zone "$ZONE" --project "$PROJECT" --quiet
        printf 'Node pool at 0. No node charges until next scale-up.\n'
      else
        gcloud scheduler jobs run "${PREFIX}-scale-down-backend" \
          --location "$LOCATION" --project "$PROJECT"
        printf 'Cloud Run min-instances set to 0.\n'
      fi
      ;;
    pause)
      if _is_gke; then
        gcloud scheduler jobs pause "${PREFIX}-gke-scale-up"   --location "$LOCATION" --project "$PROJECT"
        gcloud scheduler jobs pause "${PREFIX}-gke-scale-down" --location "$LOCATION" --project "$PROJECT"
      else
        gcloud scheduler jobs pause "${PREFIX}-scale-up-backend"   --location "$LOCATION" --project "$PROJECT"
        gcloud scheduler jobs pause "${PREFIX}-scale-down-backend" --location "$LOCATION" --project "$PROJECT"
      fi
      printf 'Auto-schedule paused.\n'
      ;;
    resume)
      if _is_gke; then
        gcloud scheduler jobs resume "${PREFIX}-gke-scale-up"   --location "$LOCATION" --project "$PROJECT"
        gcloud scheduler jobs resume "${PREFIX}-gke-scale-down" --location "$LOCATION" --project "$PROJECT"
      else
        gcloud scheduler jobs resume "${PREFIX}-scale-up-backend"   --location "$LOCATION" --project "$PROJECT"
        gcloud scheduler jobs resume "${PREFIX}-scale-down-backend" --location "$LOCATION" --project "$PROJECT"
      fi
      printf 'Auto-schedule resumed.\n'
      ;;
  esac
}

_menu() {
  printf '\n=== scale.sh — %s (%s) ===\n' "$PREFIX" "$(if _is_gke; then printf 'GKE · nodes=%s' "$(_gke_nodes)"; else printf 'Cloud Run · min=%s' "$(_cr_min)"; fi)"
  printf '  Auto-schedule: starts 8am · stops 5pm · weekdays Pacific.\n\n'
  printf '  [1] Start now        — bring backend online immediately\n'
  printf '  [2] Stop now         — take backend offline (no charges)\n'
  printf '  [3] Suspend schedule — disable the 8am/5pm auto-schedule\n'
  printf '  [4] Resume schedule  — re-enable the 8am/5pm auto-schedule\n'
  printf '  [enter] Do nothing\n'
  printf '\nChoice [1/2/3/4]: '
  read -r _CHOICE
  case "${_CHOICE:-}" in
    1) _do_scale up     ;;
    2) _do_scale down   ;;
    3) _do_scale pause  ;;
    4) _do_scale resume ;;
    *) printf 'No change.\n' ;;
  esac
}

if [[ -z "$CMD" ]]; then
  _menu
else
  _do_scale "$CMD"
fi
