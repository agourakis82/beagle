#!/usr/bin/env bash
set -euo pipefail

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib-kubeconfig.sh"
NS="${NS:-slurm-pilot}"
RELEASE_NAME="${RELEASE_NAME:-slurm-pilot-mariadb-ext}"
VALUES_PATH="${VALUES_PATH:-/tmp/mariadb-values.yaml}"

export KUBECONFIG="${KUBECONFIG_PATH}"

DB_PASS="$(kubectl -n "${NS}" get secret mariadb-password -o jsonpath='{.data.password}' | base64 -d)"
ROOT_PASS="$(openssl rand -hex 16)"

helm repo add bitnami https://charts.bitnami.com/bitnami >/dev/null 2>&1 || true
helm repo update >/dev/null

helm upgrade --install "${RELEASE_NAME}" bitnami/mariadb \
  -n "${NS}" \
  -f "${VALUES_PATH}" \
  --set auth.password="${DB_PASS}" \
  --set auth.rootPassword="${ROOT_PASS}" \
  --wait --timeout 12m

kubectl -n "${NS}" rollout status statefulset/"${RELEASE_NAME}" --timeout=6m
kubectl -n "${NS}" get pod "${RELEASE_NAME}-0" -o wide
