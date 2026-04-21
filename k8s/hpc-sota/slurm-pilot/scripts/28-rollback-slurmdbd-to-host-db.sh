#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib-kubeconfig.sh"
NS="${NS:-slurm-pilot}"
SLINKY_VERSION="${SLINKY_VERSION:-v1.1.0-rc1}"
WORKDIR="${WORKDIR:-/tmp/slurm-operator-${SLINKY_VERSION}}"
export KUBECONFIG="${KUBECONFIG_PATH}"

if [[ ! -d "${WORKDIR}/helm/slurm" ]]; then
  echo "missing ${WORKDIR}/helm/slurm; run 20-install-slurm-operator.sh first" >&2
  exit 1
fi

helm upgrade slurm-pilot "${WORKDIR}/helm/slurm" \
  --reset-values \
  --namespace "${NS}" \
  -f "${REPO_ROOT}/values/slurm-pilot-values.yaml" \
  -f "${REPO_ROOT}/values/slurm-pilot-values.host-db.yaml" \
  --wait --timeout 20m

kubectl -n "${NS}" rollout status statefulset/slurm-pilot-accounting --timeout=10m
KUBECONFIG_PATH="${KUBECONFIG_PATH}" TIMEOUT_SECONDS=120 INTERVAL_SECONDS=5 \
  bash "${REPO_ROOT}/scripts/29-wait-slurm-accounting-ready.sh"
kubectl -n "${NS}" exec sts/slurm-pilot-accounting -- bash -lc "grep -nE 'Storage(Type|Host|Port|User|Loc)' /etc/slurm/slurmdbd.conf"
kubectl -n "${NS}" exec deploy/slurm-pilot-login-slinky -- bash -lc 'sacctmgr list cluster && echo --- && sacct -n -X -S now-2hours -o JobID,Partition,State,Elapsed | tail -n 20'

echo "rollback complete"
