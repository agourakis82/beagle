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

if ! helm -n "${NS}" status slurm-pilot-mariadb >/dev/null 2>&1; then
  if kubectl -n "${NS}" get statefulset/slurm-pilot-mariadb >/dev/null 2>&1; then
    kubectl -n "${NS}" delete statefulset/slurm-pilot-mariadb --ignore-not-found
    kubectl -n "${NS}" delete service/slurm-pilot-mariadb --ignore-not-found
    kubectl -n "${NS}" delete pvc/slurm-pilot-mariadb-data --ignore-not-found
  fi
  CURRENT_PASSWORD="$(kubectl -n "${NS}" get secret mariadb-password -o jsonpath='{.data.password}' | base64 -d)"
  ROOT_PASSWORD="$(openssl rand -hex 16)"
  SLURM_DB_PASSWORD="${CURRENT_PASSWORD}" SLURM_DB_ROOT_PASSWORD="${ROOT_PASSWORD}" bash "${REPO_ROOT}/scripts/15-install-mariadb.sh"
fi

bash "${REPO_ROOT}/scripts/21-restore-slurmdbd-snapshot-to-k8s-mariadb.sh"

OVERLAY="$(mktemp)"
trap 'rm -f "${OVERLAY}"' EXIT
cat > "${OVERLAY}" <<EOF
accounting:
  storageConfig:
    host: slurm-pilot-mariadb.slurm-pilot.svc.cluster.local
    port: 3306
    database: slurm_acct_db
    username: slurm
    passwordKeyRef:
      name: mariadb-password
      key: password
EOF

helm upgrade slurm-pilot "${WORKDIR}/helm/slurm" \
  --reset-values \
  --namespace "${NS}" \
  -f "${REPO_ROOT}/values/slurm-pilot-values.yaml" \
  -f "${OVERLAY}" \
  --wait --timeout 20m

kubectl -n "${NS}" rollout status statefulset/slurm-pilot-accounting --timeout=10m
kubectl -n "${NS}" exec deploy/slurm-pilot-login-slinky -- bash -lc 'sacctmgr list cluster && echo "---" && sacct -j 2,4,7,16,17,18,19 --format=JobID,JobName,State -P'
