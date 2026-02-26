#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
NAMESPACE="${NAMESPACE:-mini-ecommerce}"
CONTROLLER_NAMESPACE="${CONTROLLER_NAMESPACE:-kube-system}"
CONTROLLER_NAME="${CONTROLLER_NAME:-sealed-secrets-controller}"
KUBESEAL_BIN="${KUBESEAL_BIN:-kubeseal}"
KUBECTL=()

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || {
    echo "[ERROR] Missing required command: $1"
    exit 1
  }
}

ensure_kubectl() {
  if command -v kubectl >/dev/null 2>&1; then
    KUBECTL=(kubectl)
    return
  fi

  if command -v k0s >/dev/null 2>&1; then
    KUBECTL=(sudo k0s kubectl)

    if [[ -z "${KUBECONFIG:-}" ]]; then
      local kubeconfig="${TMPDIR:-/tmp}/k0s-kubeconfig"
      sudo k0s kubeconfig admin > "$kubeconfig"
      sudo chmod 0644 "$kubeconfig"
      export KUBECONFIG="$kubeconfig"
    fi
    return
  fi

  echo "[ERROR] kubectl not found and k0s is unavailable."
  exit 1
}

ensure_kubectl
require_cmd "$KUBESEAL_BIN"

if ! "${KUBECTL[@]}" get crd sealedsecrets.bitnami.com >/dev/null 2>&1; then
  echo "[ERROR] CRD sealedsecrets.bitnami.com not found. Install Sealed Secrets controller first."
  exit 1
fi

generate_one() {
  local db_dir="$1"
  local plain_secret="$ROOT_DIR/base/databases/$db_dir/secret.yaml"
  local sealed_secret="$ROOT_DIR/base/databases/$db_dir/sealedsecret.yaml"

  if [[ ! -f "$plain_secret" ]]; then
    echo "[ERROR] Missing input file: $plain_secret"
    exit 1
  fi

  "${KUBECTL[@]}" create --dry-run=client -f "$plain_secret" -o yaml -n "$NAMESPACE" \
    | "$KUBESEAL_BIN" \
      --controller-name "$CONTROLLER_NAME" \
      --controller-namespace "$CONTROLLER_NAMESPACE" \
      --format yaml \
    > "$sealed_secret"

  echo "[OK] Generated $sealed_secret"
}

generate_one user-db
generate_one product-db
generate_one order-db

echo "Done. Commit sealedsecret.yaml files and keep secret.yaml ignored."
