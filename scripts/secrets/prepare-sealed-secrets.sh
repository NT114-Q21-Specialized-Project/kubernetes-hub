#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
NAMESPACE="${NAMESPACE:-mini-ecommerce}"
SEALED_SECRETS_MODE="${SEALED_SECRETS_MODE:-auto}"
KEY_BACKUP_PATH="${KEY_BACKUP_PATH:-$ROOT_DIR/overlays/dev/sealed-secrets-key.yaml}"
CONTROLLER_NAMESPACE="${CONTROLLER_NAMESPACE:-kube-system}"
CONTROLLER_NAME="${CONTROLLER_NAME:-sealed-secrets-controller}"
KUBESEAL_BIN="${KUBESEAL_BIN:-kubeseal}"
TIMEOUT="${TIMEOUT:-180s}"
DB_SECRET_DIRS=(user-db product-db order-db inventory-db payment-db)

log() {
  echo "[INFO] $*"
}

die() {
  echo "[ERROR] $*" >&2
  exit 1
}

have_plain_db_secrets() {
  local db
  for db in "${DB_SECRET_DIRS[@]}"; do
    [[ -f "$ROOT_DIR/base/databases/$db/secret.yaml" ]] || return 1
  done
}

restore_sealed_secrets_key() {
  [[ -f "$KEY_BACKUP_PATH" ]] || die "Missing Sealed Secrets key backup: $KEY_BACKUP_PATH"

  KEY_BACKUP_PATH="$KEY_BACKUP_PATH" \
  CONTROLLER_NAMESPACE="$CONTROLLER_NAMESPACE" \
  CONTROLLER_NAME="$CONTROLLER_NAME" \
  TIMEOUT="$TIMEOUT" \
  "$ROOT_DIR/scripts/secrets/restore-sealed-secrets-key.sh"
}

generate_sealed_secrets() {
  have_plain_db_secrets || die "Missing base/databases/*/secret.yaml. Create the plaintext secret files locally before resealing."
  command -v "$KUBESEAL_BIN" >/dev/null 2>&1 || die "Missing required command: $KUBESEAL_BIN"

  NAMESPACE="$NAMESPACE" \
  CONTROLLER_NAMESPACE="$CONTROLLER_NAMESPACE" \
  CONTROLLER_NAME="$CONTROLLER_NAME" \
  KUBESEAL_BIN="$KUBESEAL_BIN" \
  "$ROOT_DIR/scripts/secrets/generate-sealed-secrets.sh"

  die "Generated sealedsecret.yaml locally. Commit and push the updated files, then rerun apply-staging.sh so Argo CD can sync them."
}

mode="$SEALED_SECRETS_MODE"
if [[ "$mode" == "auto" ]]; then
  if [[ -f "$KEY_BACKUP_PATH" ]]; then
    mode="restore"
  else
    mode="generate"
  fi
fi

case "$mode" in
  restore)
    log 'Restoring the Sealed Secrets controller key for reusable GitOps ciphertext'
    restore_sealed_secrets_key
    ;;
  generate)
    log 'Generating sealed secrets from local secret.yaml files'
    generate_sealed_secrets
    ;;
  skip)
    log 'Skipping Sealed Secrets preparation because the cluster already has the expected key'
    ;;
  *)
    die "Unsupported SEALED_SECRETS_MODE: $SEALED_SECRETS_MODE (expected: auto, restore, generate, skip)"
    ;;
esac
