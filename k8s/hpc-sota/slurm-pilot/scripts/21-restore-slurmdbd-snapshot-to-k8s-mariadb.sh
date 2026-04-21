#!/usr/bin/env bash
set -euo pipefail

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib-kubeconfig.sh"
NS="${NS:-slurm-pilot}"
export KUBECONFIG="${KUBECONFIG_PATH}"

SNAPSHOT_SQL_GZ="${SNAPSHOT_SQL_GZ:-$(find /var/backups/slurm-pilot-mariadb/snapshots -type f -name 'slurm_acct_db.sql.gz' | sort | tail -n1)}"
POD_NAME="${POD_NAME:-slurm-pilot-mariadb-0}"
ROOT_SECRET_NAME="${ROOT_SECRET_NAME:-slurm-pilot-mariadb}"
ROOT_SECRET_KEY="${ROOT_SECRET_KEY:-mariadb-root-password}"

if [[ -z "${SNAPSHOT_SQL_GZ}" || ! -f "${SNAPSHOT_SQL_GZ}" ]]; then
  echo "snapshot not found" >&2
  exit 1
fi

if ! ROOT_PASSWORD="$(sudo KUBECONFIG="${KUBECONFIG_PATH}" kubectl -n "${NS}" get secret "${ROOT_SECRET_NAME}" -o jsonpath="{.data.${ROOT_SECRET_KEY}}" 2>/dev/null | base64 -d 2>/dev/null)"; then
  ROOT_SECRET_NAME="mariadb-root-password"
  ROOT_SECRET_KEY="password"
  ROOT_PASSWORD="$(sudo KUBECONFIG="${KUBECONFIG_PATH}" kubectl -n "${NS}" get secret "${ROOT_SECRET_NAME}" -o jsonpath="{.data.${ROOT_SECRET_KEY}}" | base64 -d)"
fi

sudo KUBECONFIG="${KUBECONFIG_PATH}" kubectl -n "${NS}" rollout status statefulset/slurm-pilot-mariadb --timeout=10m

echo "restoring ${SNAPSHOT_SQL_GZ} into ${POD_NAME}"
gunzip -c "${SNAPSHOT_SQL_GZ}" | sudo KUBECONFIG="${KUBECONFIG_PATH}" kubectl -n "${NS}" exec -i "${POD_NAME}" -- bash -lc "mysql -uroot -p\"${ROOT_PASSWORD}\""

echo "restore finished"
sudo KUBECONFIG="${KUBECONFIG_PATH}" kubectl -n "${NS}" exec "${POD_NAME}" -- bash -lc "mysql -uroot -p\"${ROOT_PASSWORD}\" -N -B -e 'SHOW DATABASES LIKE \"slurm_acct_db\"; USE slurm_acct_db; SHOW TABLES;' | sed -n '1,40p'"
