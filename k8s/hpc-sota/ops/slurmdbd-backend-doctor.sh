#!/usr/bin/env bash
set -euo pipefail

failures=0

section() {
  echo
  echo "== $1 =="
}

pass() {
  echo "PASS: $1"
}

warn() {
  echo "WARN: $1"
  failures=$((failures + 1))
}

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || {
    echo "Missing required command: $1" >&2
    exit 2
  }
}

age_hours() {
  local path="$1"
  local now
  local then
  now="$(date +%s)"
  then="$(stat -c %Y "$path" 2>/dev/null || echo 0)"
  if [[ "$then" -le 0 ]]; then
    echo ""
    return 0
  fi
  echo $(((now - then) / 3600))
}

login_pod() {
  sudo -n kubectl -n slurm-pilot get pod -o name |
    grep 'pod/slurm-pilot-login' | head -n1 | cut -d/ -f2
}

require_cmd sudo
require_cmd systemctl
require_cmd kubectl
require_cmd grep
require_cmd find
require_cmd stat
require_cmd date

echo "SlurmDBD backend doctor"
echo
echo "This script is read-only."
echo "It validates the current live SlurmDBD backend path and the host-local rollback guard-rail."

section "Host-local rollback backend"
if [[ "$(systemctl is-active mariadb 2>/dev/null || true)" == "active" ]]; then
  pass "host-local MariaDB service is active"
else
  warn "host-local MariaDB service is not active"
fi

if [[ "$(systemctl is-enabled mariadb 2>/dev/null || true)" == "enabled" ]]; then
  pass "host-local MariaDB service is enabled"
else
  warn "host-local MariaDB service is not enabled"
fi

section "Backup guardrails"
if [[ "$(systemctl is-active slurm-pilot-mariadb-backup.timer 2>/dev/null || true)" == "active" ]]; then
  pass "backup timer is active"
else
  warn "backup timer is not active"
fi

if [[ "$(systemctl is-enabled slurm-pilot-mariadb-backup.timer 2>/dev/null || true)" == "enabled" ]]; then
  pass "backup timer is enabled"
else
  warn "backup timer is not enabled"
fi

latest_dump="$(find /var/backups/slurm-pilot-mariadb -maxdepth 1 -type f -name 'slurm_acct_db-*.sql.gz' 2>/dev/null | sort | tail -n1 || true)"
if [[ -n "${latest_dump}" && -f "${latest_dump}" ]]; then
  dump_age="$(age_hours "${latest_dump}")"
  if [[ -n "${dump_age}" && "${dump_age}" -le 36 ]]; then
    pass "latest logical dump is recent (${latest_dump}, ${dump_age}h old)"
  else
    warn "latest logical dump is stale (${latest_dump}, ${dump_age:-unknown}h old)"
  fi
else
  warn "no top-level logical dump found under /var/backups/slurm-pilot-mariadb"
fi

latest_snapshot_dir="$(find /var/backups/slurm-pilot-mariadb/snapshots -maxdepth 1 -mindepth 1 -type d 2>/dev/null | sort | tail -n1 || true)"
if [[ -n "${latest_snapshot_dir}" && -d "${latest_snapshot_dir}" ]]; then
  snapshot_age="$(age_hours "${latest_snapshot_dir}")"
  if [[ -f "${latest_snapshot_dir}/slurm_acct_db.sql.gz" && -f "${latest_snapshot_dir}/metadata.json" && -f "${latest_snapshot_dir}/table_rows.tsv" ]]; then
    pass "latest migration snapshot is complete (${latest_snapshot_dir}, ${snapshot_age:-unknown}h old)"
  else
    warn "latest migration snapshot is incomplete (${latest_snapshot_dir})"
  fi
else
  warn "no migration-grade snapshot directory found under /var/backups/slurm-pilot-mariadb/snapshots"
fi

section "SlurmDBD live config"
storage_lines="$(sudo -n kubectl -n slurm-pilot exec slurm-pilot-accounting-0 -- bash -lc 'grep -n "StorageType\\|StorageHost\\|StoragePort\\|StorageLoc\\|StorageUser" /etc/slurm/slurmdbd.conf' 2>/dev/null || true)"
echo "${storage_lines:-<no output>}"
if [[ "${storage_lines}" == *"StorageType=accounting_storage/mysql"* && "${storage_lines}" == *"StorageHost=slurmdbd-mariadb-ext.darwin.lan"* ]]; then
  pass "slurmdbd is pointed at the externalized MariaDB candidate via slurmdbd-mariadb-ext.darwin.lan:3306"
elif [[ "${storage_lines}" == *"StorageType=accounting_storage/mysql"* && "${storage_lines}" == *"StorageHost=10.100.100.2"* ]]; then
  pass "slurmdbd is pointed at the host-local MariaDB endpoint 10.100.100.2:3306"
else
  warn "slurmdbd.conf does not match a known-good backend endpoint"
fi

section "External candidate state"
ext_status="$(sudo -n kubectl -n slurm-pilot get pod slurm-pilot-mariadb-ext-0 -o jsonpath='{.status.phase}' 2>/dev/null || true)"
ext_ready="$(sudo -n kubectl -n slurm-pilot get pod slurm-pilot-mariadb-ext-0 -o jsonpath='{.status.containerStatuses[0].ready}' 2>/dev/null || true)"
if [[ "${ext_status}" == "Running" && "${ext_ready}" == "true" ]]; then
  pass "external MariaDB candidate pod is Running and Ready"
else
  warn "external MariaDB candidate pod is not Running+Ready"
fi

section "Accounting path from login pod"
login="$(login_pod)"
if [[ -z "${login}" ]]; then
  warn "could not resolve the slurm login pod"
else
  pass "using login pod ${login} for end-to-end accounting checks"

  cluster_output="$(sudo -n kubectl -n slurm-pilot exec "${login}" -- bash -lc 'sacctmgr -nP list cluster 2>/dev/null | head -n1' || true)"
  if [[ -n "${cluster_output}" ]]; then
    pass "sacctmgr can read cluster accounting (${cluster_output})"
  else
    warn "sacctmgr did not return cluster accounting data"
  fi

  recent_sacct="$(sudo -n kubectl -n slurm-pilot exec "${login}" -- bash -lc 'sacct -n -P -a -S 2026-04-04T00:00:00 2>/dev/null | tail -n 3' || true)"
  if [[ -n "${recent_sacct}" ]]; then
    pass "sacct can read recent accounting records"
    echo "${recent_sacct}"
  else
    warn "sacct did not return recent accounting records"
  fi
fi

section "Operational note"
echo "INFO: the live SlurmDBD path now points at the externalized K8s MariaDB candidate."
echo "INFO: the host-local MariaDB on t560 remains the rollback target and backup source."

echo
if (( failures == 0 )); then
  echo "Doctor verdict: HEALTHY (external candidate live, host-local rollback guard-rail intact)"
  exit 0
fi

echo "Doctor verdict: ATTENTION (${failures} issue(s))"
echo "Suggested first checks:"
echo "  systemctl status mariadb slurm-pilot-mariadb-backup.timer"
echo "  ls -lah /var/backups/slurm-pilot-mariadb"
echo "  sudo -n kubectl -n slurm-pilot exec ${login:-<login-pod>} -- bash -lc 'sacctmgr -nP list cluster && sacct -n -P -a -S 2026-04-04T00:00:00 | tail'"
exit 1
