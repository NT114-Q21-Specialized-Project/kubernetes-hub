#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
KEY="$(cd "$ROOT_DIR/../jenkins-kvm-hub" && pwd)/key_pair/lab-key"
HOST="192.168.201.10"
USER="ubuntu"
REPO_URL="https://github.com/NT114-Q21-Specialized-Project/kubernetes-hub.git"
REMOTE_DIR="/home/ubuntu/kubernetes-hub"
REMOTE_PLATFORM_BOOTSTRAP_PATH="$REMOTE_DIR/scripts/platform/bootstrap-platform.sh"
REMOTE_APP_APPLY_PATH="$REMOTE_DIR/scripts/platform/apply-argocd-app.sh"

log() {
  printf '[%s] %s\n' "$(date +'%F %T')" "$*"
}

if [[ ! -f "$KEY" ]]; then
  echo "[ERROR] SSH key not found: $KEY"
  exit 1
fi

log "SSH to ${USER}@${HOST} and reset GitOps repo"

ssh -i "$KEY" "${USER}@${HOST}" \
  "REMOTE_DIR='$REMOTE_DIR' REPO_URL='$REPO_URL' REMOTE_PLATFORM_BOOTSTRAP_PATH='$REMOTE_PLATFORM_BOOTSTRAP_PATH' REMOTE_APP_APPLY_PATH='$REMOTE_APP_APPLY_PATH' bash -s" <<'REMOTE'
set -euo pipefail
log() { printf '[%s] %s\n' "$(date +'%F %T')" "$*"; }

log '1) Remove old repo (if any)'
sudo rm -rf "$REMOTE_DIR"

log '2) Clone repository'
git clone "$REPO_URL" "$REMOTE_DIR" || { log 'Clone failed'; exit 1; }

log '3) Run platform bootstrap'
cd "$REMOTE_DIR"
"$REMOTE_PLATFORM_BOOTSTRAP_PATH"

log '4) Apply Argo CD application'
"$REMOTE_APP_APPLY_PATH"

log '5) Print Argo CD and app status'
sudo k0s kubectl -n argocd get applications
sudo k0s kubectl -n argocd get pods
sudo k0s kubectl get pods -n mini-ecommerce
REMOTE

log 'Done.'
