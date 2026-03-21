#!/usr/bin/env bash

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
NAMESPACE="${NAMESPACE:-mini-ecommerce}"
ARGOCD_NAMESPACE="${ARGOCD_NAMESPACE:-argocd}"
ARGOCD_APP_MANIFEST="${ARGOCD_APP_MANIFEST:-$ROOT_DIR/argocd/applications/mini-ecommerce-dev.yaml}"
ARGOCD_INSTALL_MANIFEST="${ARGOCD_INSTALL_MANIFEST:-$ROOT_DIR/argocd/install.yaml}"
ARGOCD_INSTALL_URL="${ARGOCD_INSTALL_URL:-https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml}"
HELM_INSTALL_URL="${HELM_INSTALL_URL:-https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3}"
LOCAL_PATH_MANIFEST_URL="${LOCAL_PATH_MANIFEST_URL:-https://raw.githubusercontent.com/rancher/local-path-provisioner/master/deploy/local-path-storage.yaml}"
LOCAL_PATH_NAMESPACE="${LOCAL_PATH_NAMESPACE:-local-path-storage}"
LOCAL_PATH_DEPLOYMENT="${LOCAL_PATH_DEPLOYMENT:-local-path-provisioner}"
TIMEOUT="${TIMEOUT:-180s}"

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
    local wrapper_dir="${TMPDIR:-/tmp}/k0s-kubectl"
    local wrapper="${wrapper_dir}/kubectl"
    mkdir -p "$wrapper_dir"
    cat > "$wrapper" <<'WRAP'
#!/usr/bin/env bash
exec sudo k0s kubectl "$@"
WRAP
    chmod +x "$wrapper"
    export PATH="$wrapper_dir:$PATH"

    if [[ -z "${KUBECONFIG:-}" ]]; then
      local kubeconfig="${wrapper_dir}/kubeconfig"
      sudo k0s kubeconfig admin > "$kubeconfig"
      export KUBECONFIG="$kubeconfig"
    fi

    KUBECTL=(kubectl)
    return
  fi

  echo "[ERROR] kubectl not found and k0s is unavailable."
  exit 1
}

install_helm() {
  if command -v helm >/dev/null 2>&1; then
    return
  fi

  require_cmd curl
  echo "[INFO] Installing Helm..."
  curl -fsSL "$HELM_INSTALL_URL" | sudo bash
}

ensure_namespace() {
  "${KUBECTL[@]}" get namespace "$NAMESPACE" >/dev/null 2>&1 \
    || "${KUBECTL[@]}" apply -f "$ROOT_DIR/namespaces/mini-ecommerce.yaml"
}

has_storage_class() {
  "${KUBECTL[@]}" get sc --no-headers 2>/dev/null | grep -q .
}

get_default_sc() {
  "${KUBECTL[@]}" get sc -o jsonpath='{range .items[*]}{.metadata.name}{" "}{.metadata.annotations.storageclass\.kubernetes\.io/is-default-class}{"\n"}{end}' 2>/dev/null \
    | awk '$2=="true" {print $1; exit}'
}

get_any_sc() {
  "${KUBECTL[@]}" get sc -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || true
}

set_default_sc() {
  local name="$1"
  "${KUBECTL[@]}" patch sc "$name" -p '{"metadata":{"annotations":{"storageclass.kubernetes.io/is-default-class":"true"}}}'
}

install_storage_class_if_missing() {
  local default_sc
  default_sc="$(get_default_sc || true)"
  if [[ -n "$default_sc" ]]; then
    return
  fi

  if ! has_storage_class; then
    require_cmd curl
    echo "[INFO] Installing local-path-provisioner..."
    "${KUBECTL[@]}" apply -f "$LOCAL_PATH_MANIFEST_URL"
  fi

  if "${KUBECTL[@]}" -n "$LOCAL_PATH_NAMESPACE" get deploy "$LOCAL_PATH_DEPLOYMENT" >/dev/null 2>&1; then
    "${KUBECTL[@]}" -n "$LOCAL_PATH_NAMESPACE" rollout status deploy/"$LOCAL_PATH_DEPLOYMENT" --timeout="$TIMEOUT" || true
  fi

  default_sc="$(get_default_sc || true)"
  if [[ -z "$default_sc" ]]; then
    local sc_name=""
    if "${KUBECTL[@]}" get sc local-path >/dev/null 2>&1; then
      sc_name="local-path"
    else
      sc_name="$(get_any_sc)"
    fi

    if [[ -n "$sc_name" ]]; then
      set_default_sc "$sc_name"
    fi
  fi
}

install_sealed_secrets_if_missing() {
  if "${KUBECTL[@]}" get crd sealedsecrets.bitnami.com >/dev/null 2>&1; then
    return
  fi

  install_helm
  echo "[INFO] Installing Sealed Secrets controller..."
  "$ROOT_DIR/scripts/platform/install-sealed-secrets.sh"
}

apply_argocd_application() {
  if [[ -f "$ARGOCD_APP_MANIFEST" ]]; then
    echo "[INFO] Applying Argo CD Application: $ARGOCD_APP_MANIFEST"
    "${KUBECTL[@]}" apply -f "$ARGOCD_APP_MANIFEST"
  else
    echo "[WARN] Argo CD application manifest not found: $ARGOCD_APP_MANIFEST"
  fi
}

print_argocd_status() {
  "${KUBECTL[@]}" -n "$ARGOCD_NAMESPACE" get applications
  "${KUBECTL[@]}" -n "$ARGOCD_NAMESPACE" get pods
}
