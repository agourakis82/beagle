#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib-kubeconfig.sh"
NS="${NS:-slurm-pilot}"
export KUBECONFIG="${KUBECONFIG_PATH}"

SNAPSHOT_SQL_GZ="${SNAPSHOT_SQL_GZ:-$(find /var/backups/slurm-pilot-mariadb/snapshots -type f -name 'slurm_acct_db.sql.gz' | sort | tail -n1)}"
POD_NAME="${POD_NAME:-slurm-pilot-mariadb-ext-0}"
DB_NAME="${DB_NAME:-slurm_acct_db}"
DB_USER="${DB_USER:-slurm}"
DB_PASSWORD_SECRET_NAME="${DB_PASSWORD_SECRET_NAME:-mariadb-password}"
DB_PASSWORD_SECRET_KEY="${DB_PASSWORD_SECRET_KEY:-password}"

if [[ -z "${SNAPSHOT_SQL_GZ}" || ! -f "${SNAPSHOT_SQL_GZ}" ]]; then
  echo "snapshot not found" >&2
  exit 1
fi

DB_PASSWORD="$(kubectl -n "${NS}" get secret "${DB_PASSWORD_SECRET_NAME}" -o jsonpath="{.data.${DB_PASSWORD_SECRET_KEY}}" | base64 -d)"

kubectl -n "${NS}" rollout status statefulset/slurm-pilot-mariadb-ext --timeout=10m

echo "preparing ${POD_NAME} for restore"
kubectl -n "${NS}" exec "${POD_NAME}" -- bash -lc "
  mariadb -uroot <<'SQL'
DROP DATABASE IF EXISTS \`${DB_NAME}\`;
CREATE DATABASE \`${DB_NAME}\`;
CREATE USER IF NOT EXISTS '${DB_USER}'@'%' IDENTIFIED BY '${DB_PASSWORD}';
ALTER USER '${DB_USER}'@'%' IDENTIFIED BY '${DB_PASSWORD}';
GRANT ALL PRIVILEGES ON \`${DB_NAME}\`.* TO '${DB_USER}'@'%';
FLUSH PRIVILEGES;
SQL
"

echo "restoring ${SNAPSHOT_SQL_GZ} into ${POD_NAME}"
gunzip -c "${SNAPSHOT_SQL_GZ}" | kubectl -n "${NS}" exec -i "${POD_NAME}" -- bash -lc "mariadb -uroot ${DB_NAME}"

echo "validating restore"
kubectl -n "${NS}" exec "${POD_NAME}" -- bash -lc "
  mariadb -uroot -N -B -e 'SHOW DATABASES LIKE \"${DB_NAME}\"; USE \`${DB_NAME}\`; SHOW TABLES;' | sed -n '1,40p'
"
kubectl -n "${NS}" exec "${POD_NAME}" -- bash -lc "
  mariadb -h 127.0.0.1 -u'${DB_USER}' -p'${DB_PASSWORD}' -N -B -e 'SHOW DATABASES LIKE \"${DB_NAME}\";'
"

echo "restore finished"
