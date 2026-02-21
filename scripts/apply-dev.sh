#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
NAMESPACE="${NAMESPACE:-mini-ecommerce}"
OVERLAY="${OVERLAY:-overlays/dev}"
TIMEOUT="${TIMEOUT:-180s}"
INGRESS_HOST="${INGRESS_HOST:-mini-ecommerce.local}"
HEALTH_RETRIES="${HEALTH_RETRIES:-20}"
HEALTH_SLEEP_SECONDS="${HEALTH_SLEEP_SECONDS:-2}"
BOOTSTRAP_USER_DB="${BOOTSTRAP_USER_DB:-true}"

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || {
    echo "[ERROR] Missing required command: $1"
    exit 1
  }
}

rollout_wait() {
  local kind="$1"
  local name="$2"
  kubectl rollout status "${kind}/${name}" -n "$NAMESPACE" --timeout="$TIMEOUT"
}

wait_for_secret() {
  local name="$1"
  local retries="${2:-30}"
  local sleep_seconds="${3:-2}"

  for attempt in $(seq 1 "$retries"); do
    if kubectl get secret "$name" -n "$NAMESPACE" >/dev/null 2>&1; then
      return 0
    fi
    echo "waiting secret/$name (${attempt}/${retries})"
    sleep "$sleep_seconds"
  done

  echo "[ERROR] Secret $name not found in namespace $NAMESPACE."
  kubectl get sealedsecrets.bitnami.com -n "$NAMESPACE" || true
  return 1
}

ensure_secret_managed_by_sealedsecret() {
  local name="$1"
  local owner_kind

  if ! kubectl get secret "$name" -n "$NAMESPACE" >/dev/null 2>&1; then
    return 0
  fi

  owner_kind="$(kubectl get secret "$name" -n "$NAMESPACE" -o jsonpath='{.metadata.ownerReferences[0].kind}' 2>/dev/null || true)"
  if [[ "$owner_kind" != "SealedSecret" ]]; then
    echo "secret/$name exists but unmanaged; deleting for SealedSecret takeover"
    kubectl delete secret "$name" -n "$NAMESPACE" --ignore-not-found
  fi
}

require_cmd kubectl

echo "[1/8] Ensure namespace exists: $NAMESPACE"
kubectl get namespace "$NAMESPACE" >/dev/null 2>&1 || kubectl apply -f "$ROOT_DIR/namespaces/mini-ecommerce.yaml"

echo "[2/8] Apply overlay: $OVERLAY"
kubectl apply -k "$ROOT_DIR/$OVERLAY"

echo "[3/8] Wait generated Secrets from SealedSecrets"
if ! kubectl get crd sealedsecrets.bitnami.com >/dev/null 2>&1; then
  echo "[ERROR] sealedsecrets.bitnami.com CRD not found. Install Sealed Secrets controller first."
  exit 1
fi
ensure_secret_managed_by_sealedsecret user-db-secret
ensure_secret_managed_by_sealedsecret product-db-secret
ensure_secret_managed_by_sealedsecret order-db-secret
wait_for_secret user-db-secret
wait_for_secret product-db-secret
wait_for_secret order-db-secret

echo "[4/8] Wait database StatefulSets"
rollout_wait statefulset user-db
rollout_wait statefulset product-db
rollout_wait statefulset order-db

if [[ "$BOOTSTRAP_USER_DB" == "true" ]]; then
  echo "[5/8] Bootstrap databases schema/password (idempotent)"
  PRODUCT_DB_PASSWORD="$(kubectl get secret product-db-secret -n "$NAMESPACE" -o jsonpath='{.data.POSTGRES_PASSWORD}' | base64 --decode)"
  ORDER_DB_PASSWORD="$(kubectl get secret order-db-secret -n "$NAMESPACE" -o jsonpath='{.data.POSTGRES_PASSWORD}' | base64 --decode)"

  kubectl exec -n "$NAMESPACE" user-db-0 -- sh -lc \
    "psql -U user -d postgres -tAc \"SELECT 1 FROM pg_database WHERE datname='user_db'\" | grep -q 1 || psql -U user -d postgres -c \"CREATE DATABASE user_db\""
  kubectl exec -n "$NAMESPACE" user-db-0 -- sh -lc \
    "psql -U user -d user_db -f /docker-entrypoint-initdb.d/init-users.sql"
  kubectl exec -n "$NAMESPACE" product-db-0 -- sh -lc \
    "psql -U product -d postgres -tAc \"SELECT 1 FROM pg_database WHERE datname='productdb'\" | grep -q 1 || psql -U product -d postgres -c \"CREATE DATABASE productdb\""
  kubectl exec -n "$NAMESPACE" product-db-0 -- sh -lc \
    "psql -U product -d postgres -c \"ALTER USER product WITH PASSWORD '$PRODUCT_DB_PASSWORD'\""
  kubectl exec -n "$NAMESPACE" order-db-0 -- sh -lc \
    "psql -U order -d postgres -tAc \"SELECT 1 FROM pg_database WHERE datname='orderdb'\" | grep -q 1 || psql -U order -d postgres -c \"CREATE DATABASE orderdb\""
  kubectl exec -n "$NAMESPACE" order-db-0 -- sh -lc \
    "psql -U order -d postgres -c \"ALTER USER \\\"order\\\" WITH PASSWORD '$ORDER_DB_PASSWORD'\""
fi

echo "[6/8] Restart app Deployments to pick updated Secret/env"
kubectl rollout restart deploy/user-service -n "$NAMESPACE"
kubectl rollout restart deploy/product-service -n "$NAMESPACE"
kubectl rollout restart deploy/order-service -n "$NAMESPACE"
kubectl rollout restart deploy/api-gateway -n "$NAMESPACE"
kubectl rollout restart deploy/frontend -n "$NAMESPACE"

echo "[7/8] Wait app Deployments"
rollout_wait deployment user-service
rollout_wait deployment product-service
rollout_wait deployment order-service
rollout_wait deployment api-gateway
rollout_wait deployment frontend

echo "[8/8] Snapshot status"
kubectl get pods,svc,ingress -n "$NAMESPACE"

if command -v minikube >/dev/null 2>&1 && command -v curl >/dev/null 2>&1; then
  MINIKUBE_IP="$(minikube ip 2>/dev/null || true)"
  if [[ -n "$MINIKUBE_IP" ]]; then
    echo "[SMOKE] GET /api/users/health via ingress"
    CODE="000"
    for attempt in $(seq 1 "$HEALTH_RETRIES"); do
      CODE="$(curl -sS -o /tmp/mini_ecommerce_health.json -w "%{http_code}" \
        --resolve "${INGRESS_HOST}:80:${MINIKUBE_IP}" \
        "http://${INGRESS_HOST}/api/users/health" || true)"
      if [[ "$CODE" == "200" ]]; then
        break
      fi
      echo "users_health_http=$CODE (attempt ${attempt}/${HEALTH_RETRIES})"
      sleep "$HEALTH_SLEEP_SECONDS"
    done

    echo "users_health_http=$CODE"
    if [[ "$CODE" != "200" ]]; then
      echo "--- response body ---"
      cat /tmp/mini_ecommerce_health.json || true
      echo "--- user-service logs (tail) ---"
      kubectl logs deploy/user-service -n "$NAMESPACE" --tail=120 || true
      echo "--- api-gateway logs (tail) ---"
      kubectl logs deploy/api-gateway -n "$NAMESPACE" --tail=120 || true
      echo "[ERROR] Smoke health check failed."
      exit 1
    fi
  fi
fi

echo "Done."
