#!/usr/bin/env bash
set -euo pipefail

NAMESPACE="${NAMESPACE:-kube-system}"
RELEASE_NAME="${RELEASE_NAME:-sealed-secrets}"
CHART_NAME="${CHART_NAME:-sealed-secrets/sealed-secrets}"
CONTROLLER_NAME="${CONTROLLER_NAME:-sealed-secrets-controller}"
TIMEOUT="${TIMEOUT:-180s}"

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || {
    echo "[ERROR] Missing required command: $1"
    exit 1
  }
}

require_cmd helm
require_cmd kubectl

echo "[1/3] Add/update Helm repo"
helm repo add sealed-secrets https://bitnami-labs.github.io/sealed-secrets >/dev/null 2>&1 || true
helm repo update >/dev/null

echo "[2/3] Install/upgrade Sealed Secrets controller"
helm upgrade --install "$RELEASE_NAME" "$CHART_NAME" \
  -n "$NAMESPACE" \
  --create-namespace \
  --set-string fullnameOverride="$CONTROLLER_NAME"

echo "[3/3] Wait rollout"
kubectl -n "$NAMESPACE" rollout status deploy/"$CONTROLLER_NAME" --timeout="$TIMEOUT"

echo "Done. Controller is ready: $NAMESPACE/$CONTROLLER_NAME"
