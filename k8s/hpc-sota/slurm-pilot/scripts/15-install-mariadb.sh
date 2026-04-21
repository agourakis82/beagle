#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib-kubeconfig.sh"
NAMESPACE="${NAMESPACE:-slurm-pilot}"
export KUBECONFIG="${KUBECONFIG_PATH}"

SLURM_DB_PASSWORD="${SLURM_DB_PASSWORD:-$(openssl rand -hex 16)}"
SLURM_DB_ROOT_PASSWORD="${SLURM_DB_ROOT_PASSWORD:-$(openssl rand -hex 16)}"

helm repo add bitnami https://charts.bitnami.com/bitnami >/dev/null 2>&1 || true
helm repo update >/dev/null

kubectl -n "${NAMESPACE}" create secret generic mariadb-password \
  --from-literal=password="${SLURM_DB_PASSWORD}" \
  --dry-run=client -o yaml | kubectl apply -f -

helm upgrade --install slurm-pilot-mariadb bitnami/mariadb \
  --namespace "${NAMESPACE}" \
  --create-namespace \
  -f "${REPO_ROOT}/values/mariadb-values.yaml" \
  --set auth.password="${SLURM_DB_PASSWORD}" \
  --set auth.rootPassword="${SLURM_DB_ROOT_PASSWORD}" \
  --wait --timeout 10m
