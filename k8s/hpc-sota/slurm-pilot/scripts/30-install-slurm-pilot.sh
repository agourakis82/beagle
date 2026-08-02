#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib-kubeconfig.sh"
SLINKY_VERSION="${SLINKY_VERSION:-v1.1.0-rc1}"
WORKDIR="${WORKDIR:-/tmp/slurm-operator-${SLINKY_VERSION}}"
export KUBECONFIG="${KUBECONFIG_PATH}"

if [[ ! -d "${WORKDIR}/helm/slurm" ]]; then
  echo "missing ${WORKDIR}/helm/slurm; run 20-install-slurm-operator.sh first" >&2
  exit 1
fi

helm upgrade --install slurm-pilot "${WORKDIR}/helm/slurm" \
  --reset-values \
  --namespace slurm-pilot \
  --create-namespace \
  -f "${REPO_ROOT}/values/slurm-pilot-values.yaml"

KUBECTL_BIN="kubectl" NS="slurm-pilot" \
  bash "${REPO_ROOT}/scripts/31-reconcile-slurm-pilot-scheduling.sh"
