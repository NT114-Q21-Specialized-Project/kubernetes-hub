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

require_cmd kubectl

echo "[1/7] Ensure namespace exists: $NAMESPACE"
kubectl get namespace "$NAMESPACE" >/dev/null 2>&1 || kubectl apply -f "$ROOT_DIR/namespaces/mini-ecommerce.yaml"

echo "[2/7] Apply overlay: $OVERLAY"
kubectl apply -k "$ROOT_DIR/$OVERLAY"

echo "[3/7] Wait database StatefulSets"
rollout_wait statefulset user-db
rollout_wait statefulset product-db
rollout_wait statefulset order-db

if [[ "$BOOTSTRAP_USER_DB" == "true" ]]; then
  echo "[4/7] Bootstrap user database schema (idempotent)"
  kubectl exec -n "$NAMESPACE" user-db-0 -- sh -lc \
    "psql -U user -d postgres -tAc \"SELECT 1 FROM pg_database WHERE datname='user_db'\" | grep -q 1 || psql -U user -d postgres -c \"CREATE DATABASE user_db\""
  kubectl exec -n "$NAMESPACE" user-db-0 -- sh -lc \
    "psql -U user -d user_db -f /docker-entrypoint-initdb.d/init-users.sql"
fi

echo "[5/7] Restart app Deployments to pick updated Secret/env"
kubectl rollout restart deploy/user-service -n "$NAMESPACE"
kubectl rollout restart deploy/product-service -n "$NAMESPACE"
kubectl rollout restart deploy/order-service -n "$NAMESPACE"
kubectl rollout restart deploy/api-gateway -n "$NAMESPACE"
kubectl rollout restart deploy/frontend -n "$NAMESPACE"

echo "[6/7] Wait app Deployments"
rollout_wait deployment user-service
rollout_wait deployment product-service
rollout_wait deployment order-service
rollout_wait deployment api-gateway
rollout_wait deployment frontend

echo "[7/7] Snapshot status"
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
