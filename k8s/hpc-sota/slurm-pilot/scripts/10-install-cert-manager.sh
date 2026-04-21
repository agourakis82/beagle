#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib-kubeconfig.sh"
CERT_MANAGER_VERSION="${CERT_MANAGER_VERSION:-v1.20.1}"
export KUBECONFIG="${KUBECONFIG_PATH}"

helm repo add jetstack https://charts.jetstack.io >/dev/null 2>&1 || true
helm repo update >/dev/null 2>&1

helm upgrade --install cert-manager jetstack/cert-manager \
  --namespace cert-manager \
  --create-namespace \
  --reset-values \
  --version "${CERT_MANAGER_VERSION}" \
  --set crds.enabled=true \
  -f "${REPO_ROOT}/values/cert-manager-values.yaml"

KUBECONFIG="${KUBECONFIG_PATH}" kubectl -n cert-manager rollout status deploy/cert-manager --timeout=180s
KUBECONFIG="${KUBECONFIG_PATH}" kubectl -n cert-manager rollout status deploy/cert-manager-cainjector --timeout=180s
KUBECONFIG="${KUBECONFIG_PATH}" kubectl -n cert-manager rollout status deploy/cert-manager-webhook --timeout=180s
