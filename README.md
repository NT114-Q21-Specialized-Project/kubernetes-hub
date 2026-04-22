# Kubernetes Hub

This repository contains Kubernetes manifests and GitOps configuration for the [Mini E-commerce system](https://github.com/NT114-Q21-Specialized-Project/mini-ecommerce-microservices).

## Table of Contents

- [Repository Overview](#1-repository-overview)
- [Deploy Application](#2-deploy-mini-e-commerce-to-the-cluster)

## 1. Repository Overview

This section summarizes the target deployment topology and the main environments used by this repository.

### Validated Environments

All manifests in this repository are validated on local Minikube and k0s dev clusters.

### Application Overview

![Application Overview](images/application.png)

### Deployment and Namespace

![Deployment and Namespace](images/deployment.png)

### Services

![Services](images/svc.png)

### Network

![Network](images/network.png)

## 2. Deploy Mini E-commerce to the Cluster

### 2.1 Prerequisites

- A running Kubernetes cluster
- `kubectl`
- NGINX Ingress Controller installed in the cluster

### 2.2 Prepare Static Secrets

This fork deploys directly with `kubectl apply -k`, so create the plain Kubernetes Secret files locally before applying the overlay.

Copy the secret templates:

```bash
cp base/api-gateway/auth-jwt-secret.yaml.example base/api-gateway/auth-jwt-secret.yaml

for db in user-db product-db order-db inventory-db payment-db; do
  cp "base/databases/$db/secret.yaml.example" "base/databases/$db/secret.yaml"
done
```

Then edit the copied files with the values for your target cluster:

- `base/api-gateway/auth-jwt-secret.yaml`
- `base/databases/user-db/secret.yaml`
- `base/databases/product-db/secret.yaml`
- `base/databases/order-db/secret.yaml`
- `base/databases/inventory-db/secret.yaml`
- `base/databases/payment-db/secret.yaml`

For `base/api-gateway/auth-jwt-secret.yaml`, generate strong random values instead of using placeholder text:

```bash
openssl rand -base64 32
openssl rand -base64 32
```

Use the generated values for:

- `JWT_SECRET`
- `INTERNAL_SERVICE_TOKEN`

### 2.3 Apply Staging Overlay

Run from the repo root:

```bash
kubectl apply -k overlays/staging
```

Note:

- The `staging` overlay now reads static secrets from `base/`

### 2.4 Verify Deployment

```bash
kubectl get pods,svc,ingress -n mini-ecommerce
```

Quick smoke check through ingress:

```bash
LB_IP=$(kubectl -n ingress-nginx get svc ingress-nginx-controller -o jsonpath='{.status.loadBalancer.ingress[0].ip}')
curl --resolve mini-ecommerce.tienphatng237.com:80:$LB_IP http://mini-ecommerce.tienphatng237.com/api/users/health
```

### 2.5 Re-Apply After Changes

Whenever you update images, replicas, resources, or static secrets, apply the overlay again:

```bash
kubectl apply -k overlays/staging
```
