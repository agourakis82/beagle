#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
NS="${NS:-slurm-pilot}"
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib-kubeconfig.sh"
EXTERNAL_DB_HOST="${EXTERNAL_DB_HOST:-}"
EXTERNAL_DB_PORT="${EXTERNAL_DB_PORT:-3306}"

if [[ -z "${EXTERNAL_DB_HOST}" ]]; then
  echo "missing EXTERNAL_DB_HOST" >&2
  echo "example: EXTERNAL_DB_HOST=slurmdbd-mariadb-ext.darwin.lan bash scripts/25-preflight-external-slurmdbd-db.sh" >&2
  exit 2
fi

export KUBECONFIG="${KUBECONFIG_PATH}"

echo "SlurmDBD external backend preflight"
echo
echo "This script is read-only."
echo "It does not change the live accounting backend."

echo
echo "== Current live path =="
sudo -n kubectl -n "${NS}" exec slurm-pilot-accounting-0 -- \
  bash -lc 'grep -n "StorageType\\|StorageHost\\|StoragePort\\|StorageLoc\\|StorageUser" /etc/slurm/slurmdbd.conf'

echo
echo "== Current accounting reads =="
LOGIN_POD="$(sudo -n kubectl -n "${NS}" get pod -o name | grep 'pod/slurm-pilot-login' | head -n1 | cut -d/ -f2)"
sudo -n kubectl -n "${NS}" exec "${LOGIN_POD}" -- bash -lc 'sacctmgr -nP list cluster | head -n1; echo ---; sacct -n -P -a -S 2026-04-04T00:00:00 | tail -n 3'

echo
echo "== Snapshot inventory =="
find /var/backups/slurm-pilot-mariadb/snapshots -maxdepth 1 -mindepth 1 -type d | sort | tail -n 5
LATEST_SNAPSHOT="$(find /var/backups/slurm-pilot-mariadb/snapshots -maxdepth 1 -mindepth 1 -type d | sort | tail -n1)"
if [[ -z "${LATEST_SNAPSHOT}" ]]; then
  echo "missing snapshot directory under /var/backups/slurm-pilot-mariadb/snapshots" >&2
  exit 1
fi
test -f "${LATEST_SNAPSHOT}/slurm_acct_db.sql.gz"
test -f "${LATEST_SNAPSHOT}/metadata.json"
test -f "${LATEST_SNAPSHOT}/table_rows.tsv"
echo "latest snapshot complete: ${LATEST_SNAPSHOT}"

echo
echo "== Secret inventory =="
sudo -n kubectl -n "${NS}" get secret mariadb-password -o name

echo
echo "== Target resolution from t560 =="
getent ahostsv4 "${EXTERNAL_DB_HOST}" || true
timeout 5 bash -lc "</dev/tcp/${EXTERNAL_DB_HOST}/${EXTERNAL_DB_PORT}" && echo "t560 tcp reachability: ok" || {
  echo "t560 tcp reachability: failed" >&2
  exit 1
}

echo
echo "== Target resolution from Slurm login pod =="
sudo -n kubectl -n "${NS}" exec "${LOGIN_POD}" -- bash -lc "getent ahostsv4 '${EXTERNAL_DB_HOST}' || true"
sudo -n kubectl -n "${NS}" exec "${LOGIN_POD}" -- \
  bash -lc "timeout 5 bash -lc '</dev/tcp/${EXTERNAL_DB_HOST}/${EXTERNAL_DB_PORT}'" && \
  echo "login-pod tcp reachability: ok" || {
    echo "login-pod tcp reachability: failed" >&2
    exit 1
  }

echo
echo "== Recommended next file =="
echo "${REPO_ROOT}/values/slurm-pilot-values.external-db.example.yaml"
echo
echo "Preflight verdict: READY FOR A PLANNED CUTOVER WINDOW"
