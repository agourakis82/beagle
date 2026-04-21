#!/usr/bin/env bash
set -euo pipefail

OUT_DIR="${OUT_DIR:-/var/backups/slurm-pilot-mariadb/snapshots}"
STAMP="$(date +%Y%m%d-%H%M%S)"
SNAP_DIR="${OUT_DIR}/${STAMP}"
mkdir -p "${SNAP_DIR}"

DB_NAME="${DB_NAME:-slurm_acct_db}"
MYSQL_BIN="${MYSQL_BIN:-mysql}"
MYSQLDUMP_BIN="${MYSQLDUMP_BIN:-mysqldump}"

echo "creating Slurm accounting snapshot under ${SNAP_DIR}"

sudo "${MYSQLDUMP_BIN}" \
  --single-transaction \
  --quick \
  --routines \
  --triggers \
  --events \
  "${DB_NAME}" | gzip -9 > "${SNAP_DIR}/${DB_NAME}.sql.gz"

sudo "${MYSQL_BIN}" \
  -N -B \
  -e "SELECT table_name, table_rows FROM information_schema.tables WHERE table_schema='${DB_NAME}' ORDER BY table_name;" \
  > "${SNAP_DIR}/table_rows.tsv"

cat > "${SNAP_DIR}/metadata.json" <<EOF
{
  "timestamp": "${STAMP}",
  "database": "${DB_NAME}",
  "host": "local-socket-root",
  "cluster": "beagle-slurm-pilot",
  "notes": "Logical accounting snapshot for slurmdbd backend migration."
}
EOF

sha256sum "${SNAP_DIR}/${DB_NAME}.sql.gz" > "${SNAP_DIR}/${DB_NAME}.sql.gz.sha256"

echo "snapshot complete:"
ls -lh "${SNAP_DIR}"
