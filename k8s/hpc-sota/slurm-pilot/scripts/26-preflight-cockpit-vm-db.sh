#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib-kubeconfig.sh"

export KUBECONFIG="${KUBECONFIG_PATH}"

EXTERNAL_DB_HOST="${EXTERNAL_DB_HOST:-10.100.100.166}"
EXTERNAL_DB_PORT="${EXTERNAL_DB_PORT:-3306}"

echo "preflighting cockpit VM MariaDB candidate at ${EXTERNAL_DB_HOST}:${EXTERNAL_DB_PORT}"
echo "overlay: ${REPO_ROOT}/values/slurm-pilot-values.cockpit-vm-db.yaml"

EXTERNAL_DB_HOST="${EXTERNAL_DB_HOST}" \
EXTERNAL_DB_PORT="${EXTERNAL_DB_PORT}" \
  bash "${REPO_ROOT}/scripts/25-preflight-external-slurmdbd-db.sh"
