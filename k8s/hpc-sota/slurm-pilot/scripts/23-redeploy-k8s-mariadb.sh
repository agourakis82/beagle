#!/usr/bin/env bash
set -euo pipefail

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib-kubeconfig.sh"
NS="${NS:-slurm-pilot}"
VALUES_PATH="${VALUES_PATH:-/tmp/mariadb-values.yaml}"

export KUBECONFIG="${KUBECONFIG_PATH}"

DB_PASS="$(kubectl -n "${NS}" get secret mariadb-password -o jsonpath='{.data.password}' | base64 -d)"
ROOT_PASS="$(kubectl -n "${NS}" get secret slurm-pilot-mariadb -o jsonpath='{.data.mariadb-root-password}' | base64 -d)"

helm repo add bitnami https://charts.bitnami.com/bitnami >/dev/null 2>&1 || true
helm repo update >/dev/null

helm upgrade --install slurm-pilot-mariadb bitnami/mariadb \
  -n "${NS}" \
  -f "${VALUES_PATH}" \
  --set auth.password="${DB_PASS}" \
  --set auth.rootPassword="${ROOT_PASS}" \
  --wait --timeout 12m

kubectl -n "${NS}" rollout status statefulset/slurm-pilot-mariadb --timeout=6m
kubectl -n "${NS}" get pod slurm-pilot-mariadb-0 -o wide
