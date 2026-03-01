# Kubernetes Hub

This repository contains Kubernetes manifests and GitOps configuration for the [Mini E-commerce system](https://github.com/NT114-Q21-Specialized-Project/mini-ecommerce-microservices).

## 1. ArgoCD Manifests Overview

Contains manifests for setting up ArgoCD in the Kubernetes cluster.

### Dev Environment

All manifests in this repository are validated on local Minikube and k0s dev clusters.

### Application Overview

![Application Overview](images/application.png)

### Deployment and Namespace

![Deployment and Namespace](images/deployment.png)

### Services

![Services](images/svc.png)

### Network

![Network](images/network.png)

## 2. GitOps Bootstrap (Argo CD)

### 2.1 Prerequisites

- A running Kubernetes cluster (Minikube or k0s)
- `kubectl`, `helm`, `argocd` CLI (optional but recommended)
- NGINX Ingress Controller installed in the cluster

### 2.2 Bootstrap Infra + Argo CD (Recommended)

Use the bootstrap script to prepare the cluster and enable GitOps.
This script does NOT deploy the app directly. It only installs infra and creates the Argo CD Application.

```bash
# From the repo root
./scripts/bootstrap-infra.sh
```

What it does:
- ensure namespace exists
- ensure default StorageClass (installs local-path-provisioner if missing)
- install Sealed Secrets controller if missing
- install Argo CD if missing (server-side apply)
- apply Argo CD Application manifest
- print Argo CD status

### 2.3 Reset GitOps on k0s Master (Clean Re-clone)

If you want a clean reset on k0s master, use the reset script.
It removes `/home/ubuntu/kubernetes-hub`, clones fresh, and re-runs bootstrap.

```bash
# This script expects the SSH key at ../jenkins-kvm-hub/key_pair/lab-key
cd /home/tienphatng237/Desktop/NT114-AIOPs-DevOps/kubernetes-hub
./scripts/reset-gitops.sh
```

Adjust `HOST` or `KEY` inside `scripts/reset-gitops.sh` if your environment differs.

Manual SSH run (k0s) without the reset script:

```bash
scp -i key_pair/lab-key ../kubernetes-hub/scripts/bootstrap-infra.sh \
  ubuntu@192.168.201.10:/home/ubuntu/kubernetes-hub/scripts/bootstrap-infra.sh

ssh -i key_pair/lab-key ubuntu@192.168.201.10 \
  'chmod +x ~/kubernetes-hub/scripts/bootstrap-infra.sh && cd ~/kubernetes-hub && ./scripts/bootstrap-infra.sh'

sudo k0s kubectl -n argocd get applications
sudo k0s kubectl -n argocd get pods
sudo k0s kubectl -n mini-ecommerce get pods
```

### 2.4 Manual Argo CD Install (Optional)

```bash
# 1) Create namespace
kubectl create namespace argocd

# 2) Install Argo CD from repository manifest (server-side apply)
kubectl apply --server-side --force-conflicts -n argocd -f argocd/install.yaml

# 3) Wait core components
kubectl -n argocd rollout status statefulset/argocd-application-controller --timeout=300s
kubectl -n argocd rollout status deploy/argocd-server --timeout=300s
kubectl -n argocd rollout status deploy/argocd-repo-server --timeout=300s
kubectl -n argocd rollout status deploy/argocd-applicationset-controller --timeout=300s
```

### 2.5 Access Argo CD

```bash
# 1) Port-forward Argo CD UI/API
kubectl -n argocd port-forward svc/argocd-server 8088:443

# 2) Get initial admin password
kubectl -n argocd get secret argocd-initial-admin-secret \
  -o jsonpath="{.data.password}" | base64 --decode && echo

# 3) (Optional) Login with CLI
argocd login localhost:8088 --username admin --password '<INITIAL_PASSWORD>' --insecure
```

### 2.5.1 Access Argo CD on k0s Master (No kubectl)

On k0s, use `sudo k0s kubectl` instead of `kubectl`.

Port-forward on the k0s master:

```bash
sudo k0s kubectl -n argocd port-forward svc/argocd-server 8088:443
```

If you want to access from your local machine, open an SSH tunnel:

```bash
ssh -i key_pair/lab-key -L 8088:127.0.0.1:8088 ubuntu@192.168.201.10
```

Then open `https://localhost:8088` in your browser.

### 2.6 Deploy Mini E-commerce Application with Argo CD

```bash
# 1) Create/update Argo CD Application
kubectl apply -f argocd/applications/mini-ecommerce-dev.yaml

# 2) Trigger refresh/sync from CLI (optional)
argocd app get mini-ecommerce-dev
argocd app sync mini-ecommerce-dev
argocd app wait mini-ecommerce-dev --health --sync --timeout 300
```

### 2.7 Verify Deployment

```bash
# Argo CD application status
kubectl -n argocd get applications
kubectl -n argocd get application mini-ecommerce-dev

# Runtime status in target namespace
kubectl get pods,svc,ingress -n mini-ecommerce

# Quick ingress smoke check
LB_IP=$(kubectl -n ingress-nginx get svc ingress-nginx-controller -o jsonpath='{.status.loadBalancer.ingress[0].ip}')
curl --resolve mini-ecommerce.tienphatng237.com:80:$LB_IP http://mini-ecommerce.tienphatng237.com/api/users/health
```

## 3. Sealed Secrets (Cluster-Specific)

Sealed Secrets are cluster-specific. When you change clusters (e.g., k0s),
you must reseal the secrets using that cluster's public key.

```bash
# 1) Install/upgrade Sealed Secrets controller
./scripts/install-sealed-secrets.sh

# 2) Create secret.yaml locally (ignored by git) from example, then edit values
cp base/databases/user-db/secret.yaml.example base/databases/user-db/secret.yaml
cp base/databases/product-db/secret.yaml.example base/databases/product-db/secret.yaml
cp base/databases/order-db/secret.yaml.example base/databases/order-db/secret.yaml

# 3) Ensure kubeseal is installed on the target cluster host (example)
curl -fsSL -o /tmp/kubeseal.tar.gz https://github.com/bitnami-labs/sealed-secrets/releases/download/v0.36.0/kubeseal-0.36.0-linux-amd64.tar.gz
tar -C /tmp -xzf /tmp/kubeseal.tar.gz
sudo install -m 755 /tmp/kubeseal /usr/local/bin/kubeseal

# 4) Generate sealedsecret.yaml files using the target cluster key
./scripts/generate-sealed-secrets.sh

# 5) Commit sealedsecret.yaml and push so Argo CD can reconcile
```

## 4. Ingress Access (Argo CD + Mini E-commerce)

This requires an NGINX Ingress Controller in the cluster.

### 4.1 Apply Ingress Manifests on k0s

Run from the repo root on k0s master:

```bash
cd ~/kubernetes-hub

# Apply Argo CD ingress
sudo k0s kubectl apply -f argocd/ingress.yaml

# Apply mini-ecommerce ingress from dev overlay
sudo k0s kubectl apply -k overlays/dev
```

### 4.2 Add Hosts on Your Local Machine

```bash
LB_IP=$(ssh -i key_pair/lab-key ubuntu@192.168.201.10 \
  "sudo k0s kubectl -n ingress-nginx get svc ingress-nginx-controller -o jsonpath='{.status.loadBalancer.ingress[0].ip}'")

sudo sed -i '/argocd\.tienphatng237\.com/d;/mini-ecommerce\.tienphatng237\.com/d' /etc/hosts
echo "$LB_IP argocd.tienphatng237.com mini-ecommerce.tienphatng237.com" | sudo tee -a /etc/hosts
```

Open:
- `https://argocd.tienphatng237.com`
- `http://mini-ecommerce.tienphatng237.com`

If using ingress locally (Minikube), map hosts to Minikube IP:

```bash
IP=$(minikube ip)
sudo sed -i '/argocd\.tienphatng237\.com/d;/mini-ecommerce\.tienphatng237\.com/d' /etc/hosts
echo "$IP argocd.tienphatng237.com mini-ecommerce.tienphatng237.com" | sudo tee -a /etc/hosts
```

### 4.3 Quick Ingress Smoke Check

```bash
LB_IP=$(kubectl -n ingress-nginx get svc ingress-nginx-controller -o jsonpath='{.status.loadBalancer.ingress[0].ip}')
curl --resolve mini-ecommerce.tienphatng237.com:80:$LB_IP http://mini-ecommerce.tienphatng237.com/api/users/health
```

## 5. Sync Conflict Note (When Jenkins Updates Image Tags)

If Jenkins pushes a new `gitops(dev): update image tags ...` commit before your push:

```bash
git fetch origin
git rebase origin/main
git push origin main
```
