#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
ARGOCD_NAMESPACE="${ARGOCD_NAMESPACE:-argocd}"
ARGOCD_INSTALL_MANIFEST="${ARGOCD_INSTALL_MANIFEST:-$ROOT_DIR/argocd/install.yaml}"
ARGOCD_INSTALL_URL="${ARGOCD_INSTALL_URL:-https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml}"

# shellcheck disable=SC1091
source "$ROOT_DIR/scripts/platform/platform-lib.sh"

ensure_kubectl

need_install="false"

if ! "${KUBECTL[@]}" get ns "$ARGOCD_NAMESPACE" >/dev/null 2>&1; then
  "${KUBECTL[@]}" create namespace "$ARGOCD_NAMESPACE"
fi

if ! "${KUBECTL[@]}" get crd applications.argoproj.io >/dev/null 2>&1; then
  need_install="true"
fi

if ! "${KUBECTL[@]}" -n "$ARGOCD_NAMESPACE" get deploy argocd-server >/dev/null 2>&1; then
  need_install="true"
fi

if [[ "$need_install" != "true" ]]; then
  echo "[INFO] Argo CD is already installed."
  exit 0
fi

manifest="$ARGOCD_INSTALL_MANIFEST"
if [[ ! -f "$manifest" ]]; then
  require_cmd curl
  manifest="/tmp/argocd-install.yaml"
  echo "[INFO] Downloading Argo CD manifest..."
  curl -fsSL "$ARGOCD_INSTALL_URL" -o "$manifest"
fi

echo "[INFO] Installing Argo CD..."
"${KUBECTL[@]}" -n "$ARGOCD_NAMESPACE" apply --server-side --force-conflicts -f "$manifest"
