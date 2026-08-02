#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib-kubeconfig.sh"
NAMESPACE="${NAMESPACE:-slurm-pilot}"
export KUBECONFIG="${KUBECONFIG_PATH}"

SLURM_DB_PASSWORD="${SLURM_DB_PASSWORD:-$(openssl rand -hex 16)}"
SLURM_DB_ROOT_PASSWORD="${SLURM_DB_ROOT_PASSWORD:-$(openssl rand -hex 16)}"

kubectl -n "${NAMESPACE}" create secret generic mariadb-password \
  --from-literal=password="${SLURM_DB_PASSWORD}" \
  --dry-run=client -o yaml | kubectl apply -f -

kubectl -n "${NAMESPACE}" create secret generic mariadb-root-password \
  --from-literal=password="${SLURM_DB_ROOT_PASSWORD}" \
  --dry-run=client -o yaml | kubectl apply -f -

tmp_manifest="$(mktemp)"
trap 'rm -f "${tmp_manifest}"' EXIT

sed "s/CHANGE_ME/${SLURM_DB_ROOT_PASSWORD}/g" "${REPO_ROOT}/k8s/mariadb.yaml" > "${tmp_manifest}"
kubectl apply -f "${tmp_manifest}"
kubectl -n "${NAMESPACE}" rollout status statefulset/slurm-pilot-mariadb --timeout=10m
