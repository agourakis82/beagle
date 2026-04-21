#!/usr/bin/env bash
set -euo pipefail

BACKUP_DIR="${BACKUP_DIR:-/var/backups/slurm-pilot-mariadb}"
DB_NAME="${DB_NAME:-slurm_acct_db}"
STAMP="$(date +%Y%m%d-%H%M%S)"

mkdir -p "${BACKUP_DIR}"
mysqldump --single-transaction --quick --databases "${DB_NAME}" | gzip -9 > "${BACKUP_DIR}/${DB_NAME}-${STAMP}.sql.gz"
find "${BACKUP_DIR}" -type f -name "${DB_NAME}-*.sql.gz" -mtime +14 -delete
ls -lh "${BACKUP_DIR}"
