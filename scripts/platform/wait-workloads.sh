#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
NAMESPACE="${NAMESPACE:-mini-ecommerce}"
ARGOCD_NAMESPACE="${ARGOCD_NAMESPACE:-argocd}"
ARGOCD_APP_NAME="${ARGOCD_APP_NAME:-}"
TIMEOUT="${TIMEOUT:-300s}"
WAIT_INTERVAL_SECONDS="${WAIT_INTERVAL_SECONDS:-5}"
WAIT_ATTEMPTS="${WAIT_ATTEMPTS:-60}"
WAIT_DEPLOYMENTS="${WAIT_DEPLOYMENTS:-api-gateway frontend user-service product-service order-service inventory-service payment-service redis}"
WAIT_STATEFULSETS="${WAIT_STATEFULSETS:-user-db product-db order-db inventory-db payment-db}"

# shellcheck disable=SC1091
source "$ROOT_DIR/scripts/platform/platform-lib.sh"

log() {
  echo "[INFO] $*"
}

die() {
  echo "[ERROR] $*" >&2
  exit 1
}

wait_for_resource() {
  local kind="$1"
  local name="$2"
  local attempt=1

  until "${KUBECTL[@]}" -n "$NAMESPACE" get "$kind/$name" >/dev/null 2>&1; do
    if (( attempt >= WAIT_ATTEMPTS )); then
      die "Timed out waiting for $kind/$name in namespace $NAMESPACE"
    fi

    sleep "$WAIT_INTERVAL_SECONDS"
    ((attempt++))
  done
}

ensure_kubectl

local_deployment_list=( $WAIT_DEPLOYMENTS )
local_statefulset_list=( $WAIT_STATEFULSETS )

for deployment in "${local_deployment_list[@]}"; do
  wait_for_resource deployment "$deployment"
  "${KUBECTL[@]}" -n "$NAMESPACE" rollout status deployment/"$deployment" --timeout="$TIMEOUT"
done

for statefulset in "${local_statefulset_list[@]}"; do
  wait_for_resource statefulset "$statefulset"
  "${KUBECTL[@]}" -n "$NAMESPACE" rollout status statefulset/"$statefulset" --timeout="$TIMEOUT"
done

if [[ -n "$ARGOCD_APP_NAME" ]]; then
  log "Argo CD application status: $ARGOCD_APP_NAME"
  "${KUBECTL[@]}" -n "$ARGOCD_NAMESPACE" get application "$ARGOCD_APP_NAME"
fi

log "Current resources in namespace: $NAMESPACE"
"${KUBECTL[@]}" get pods,svc,ingress -n "$NAMESPACE"
