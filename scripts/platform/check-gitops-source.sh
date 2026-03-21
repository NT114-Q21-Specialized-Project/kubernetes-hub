#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
ENV_NAME="${ENV_NAME:-staging}"
APP_NAME="${APP_NAME:-mini-ecommerce-staging}"
OVERLAY_REL="${OVERLAY_REL:-overlays/$ENV_NAME}"
OVERLAY_DIR="${OVERLAY_DIR:-$ROOT_DIR/$OVERLAY_REL}"
APP_MANIFEST_REL="${APP_MANIFEST_REL:-argocd/applications/$APP_NAME.yaml}"
APP_MANIFEST="${APP_MANIFEST:-$ROOT_DIR/$APP_MANIFEST_REL}"

warn() {
  echo "[WARN] $*" >&2
}

die() {
  echo "[ERROR] $*" >&2
  exit 1
}

kustomization="$OVERLAY_DIR/kustomization.yaml"
[[ -f "$kustomization" ]] || die "Missing overlay file: $kustomization"
[[ -s "$kustomization" ]] || die "Overlay '$ENV_NAME' is not ready: $kustomization is empty."
[[ -f "$APP_MANIFEST" ]] || die "Missing Argo CD application manifest: $APP_MANIFEST"
[[ -s "$APP_MANIFEST" ]] || die "Argo CD application manifest is empty: $APP_MANIFEST"

if ! command -v git >/dev/null 2>&1; then
  exit 0
fi

if ! git -C "$ROOT_DIR" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  exit 0
fi

if ! git -C "$ROOT_DIR" ls-files --error-unmatch "$APP_MANIFEST_REL" >/dev/null 2>&1; then
  warn "$APP_MANIFEST_REL is not tracked by git yet. Argo CD will not be able to sync staging from the remote repo until you commit and push it."
  exit 0
fi

if [[ -n "$(git -C "$ROOT_DIR" status --short -- "$APP_MANIFEST_REL" "$OVERLAY_REL")" ]]; then
  warn "Staging GitOps files have local-only changes. Commit and push them before relying on Argo CD sync from GitHub."
fi
