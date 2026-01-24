#!/usr/bin/env bash
set -e

NAMESPACE=mini-ecommerce
OVERLAY=overlays/dev

echo "▶️ Apply Kubernetes manifests (dev)..."

# Tạo namespace nếu chưa có
kubectl get ns $NAMESPACE >/dev/null 2>&1 || kubectl apply -f namespaces/mini-ecommerce.yaml

# Apply kustomize dev overlay
kubectl apply -k $OVERLAY

echo "⏳ Waiting for pods to be ready..."
kubectl rollout status deploy/api-gateway -n $NAMESPACE
kubectl rollout status deploy/frontend -n $NAMESPACE
kubectl rollout status deploy/user-service -n $NAMESPACE
kubectl rollout status deploy/product-service -n $NAMESPACE
kubectl rollout status deploy/order-service -n $NAMESPACE

echo "✅ Dev environment is up!"
kubectl get pods -n $NAMESPACE
kubectl get svc -n $NAMESPACE
kubectl get ingress -n $NAMESPACE
