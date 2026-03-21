#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
# shellcheck disable=SC1091
source "$ROOT_DIR/scripts/platform/platform-lib.sh"

ensure_kubectl

echo "[1/4] Ensure namespace exists: $NAMESPACE"
ensure_namespace

echo "[2/4] Ensure default StorageClass"
install_storage_class_if_missing

echo "[3/4] Install Sealed Secrets (if missing)"
install_sealed_secrets_if_missing

echo "[4/4] Install Argo CD (if missing)"
"$ROOT_DIR/scripts/platform/install-argocd.sh"

echo "Platform bootstrap completed."
