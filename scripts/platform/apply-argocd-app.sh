#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
# shellcheck disable=SC1091
source "$ROOT_DIR/scripts/platform/platform-lib.sh"

ensure_kubectl

echo "[1/2] Apply Argo CD Application"
apply_argocd_application

echo "[2/2] Argo CD status"
print_argocd_status

echo "Argo CD application apply completed."
