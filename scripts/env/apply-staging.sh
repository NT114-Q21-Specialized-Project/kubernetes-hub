#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
ENV_NAME="staging"
APP_NAME="${APP_NAME:-mini-ecommerce-staging}"
NAMESPACE="${NAMESPACE:-mini-ecommerce}"
ARGOCD_NAMESPACE="${ARGOCD_NAMESPACE:-argocd}"
OVERLAY_REL="${OVERLAY_REL:-overlays/$ENV_NAME}"
APP_MANIFEST_REL="${APP_MANIFEST_REL:-argocd/applications/$APP_NAME.yaml}"
APP_MANIFEST="${APP_MANIFEST:-$ROOT_DIR/$APP_MANIFEST_REL}"
KEY_BACKUP_PATH="${KEY_BACKUP_PATH:-$ROOT_DIR/overlays/dev/sealed-secrets-key.yaml}"
SEALED_SECRETS_MODE="${SEALED_SECRETS_MODE:-auto}"
CONTROLLER_NAMESPACE="${CONTROLLER_NAMESPACE:-kube-system}"
CONTROLLER_NAME="${CONTROLLER_NAME:-sealed-secrets-controller}"
KUBESEAL_BIN="${KUBESEAL_BIN:-kubeseal}"
TIMEOUT="${TIMEOUT:-300s}"
WAIT_INTERVAL_SECONDS="${WAIT_INTERVAL_SECONDS:-5}"
WAIT_ATTEMPTS="${WAIT_ATTEMPTS:-60}"
WAIT_DEPLOYMENTS="${WAIT_DEPLOYMENTS:-api-gateway frontend user-service product-service order-service inventory-service payment-service redis}"
WAIT_STATEFULSETS="${WAIT_STATEFULSETS:-user-db product-db order-db inventory-db payment-db}"

log() {
  echo "[INFO] $*"
}

log '[1/5] Validate local GitOps source'
ENV_NAME="$ENV_NAME" \
APP_NAME="$APP_NAME" \
OVERLAY_REL="$OVERLAY_REL" \
APP_MANIFEST_REL="$APP_MANIFEST_REL" \
APP_MANIFEST="$APP_MANIFEST" \
"$ROOT_DIR/scripts/platform/check-gitops-source.sh"

log '[2/5] Bootstrap platform prerequisites'
NAMESPACE="$NAMESPACE" \
ARGOCD_NAMESPACE="$ARGOCD_NAMESPACE" \
TIMEOUT="$TIMEOUT" \
"$ROOT_DIR/scripts/platform/bootstrap-platform.sh"

log '[3/5] Prepare Sealed Secrets'
NAMESPACE="$NAMESPACE" \
SEALED_SECRETS_MODE="$SEALED_SECRETS_MODE" \
KEY_BACKUP_PATH="$KEY_BACKUP_PATH" \
CONTROLLER_NAMESPACE="$CONTROLLER_NAMESPACE" \
CONTROLLER_NAME="$CONTROLLER_NAME" \
KUBESEAL_BIN="$KUBESEAL_BIN" \
TIMEOUT="$TIMEOUT" \
"$ROOT_DIR/scripts/secrets/prepare-sealed-secrets.sh"

log '[4/5] Apply staging Argo CD application'
NAMESPACE="$NAMESPACE" \
ARGOCD_NAMESPACE="$ARGOCD_NAMESPACE" \
ARGOCD_APP_MANIFEST="$APP_MANIFEST" \
TIMEOUT="$TIMEOUT" \
"$ROOT_DIR/scripts/platform/apply-argocd-app.sh"

log '[5/5] Wait for staging workloads'
NAMESPACE="$NAMESPACE" \
ARGOCD_NAMESPACE="$ARGOCD_NAMESPACE" \
ARGOCD_APP_NAME="$APP_NAME" \
TIMEOUT="$TIMEOUT" \
WAIT_INTERVAL_SECONDS="$WAIT_INTERVAL_SECONDS" \
WAIT_ATTEMPTS="$WAIT_ATTEMPTS" \
WAIT_DEPLOYMENTS="$WAIT_DEPLOYMENTS" \
WAIT_STATEFULSETS="$WAIT_STATEFULSETS" \
"$ROOT_DIR/scripts/platform/wait-workloads.sh"
