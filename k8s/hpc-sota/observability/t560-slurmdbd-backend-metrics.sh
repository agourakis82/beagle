#!/usr/bin/env bash
set -euo pipefail

OUT_DIR="${OUT_DIR:-/var/lib/node_exporter/textfile}"
OUT_FILE="${OUT_DIR}/slurmdbd_hostlocal_backend.prom"
KUBECONFIG_PATH="${KUBECONFIG_PATH:-/etc/kubernetes/admin.conf}"
NS="${NS:-slurm-pilot}"
EXTERNAL_HOST_ALIAS="${EXTERNAL_HOST_ALIAS:-slurmdbd-mariadb-ext.darwin.lan}"

mkdir -p "${OUT_DIR}"

metric_bool() {
  if "$@"; then
    echo 1
  else
    echo 0
  fi
}

age_hours() {
  local path="$1"
  local now
  local then
  now="$(date +%s)"
  then="$(stat -c %Y "$path" 2>/dev/null || echo 0)"
  if [[ "$then" -le 0 ]]; then
    echo -1
    return 0
  fi
  echo $(((now - then) / 3600))
}

if [[ "$(systemctl is-active mariadb 2>/dev/null || true)" == "active" ]]; then
  mariadb_active=1
else
  mariadb_active=0
fi

if [[ "$(systemctl is-enabled mariadb 2>/dev/null || true)" == "enabled" ]]; then
  mariadb_enabled=1
else
  mariadb_enabled=0
fi

if [[ "$(systemctl is-active slurm-pilot-mariadb-backup.timer 2>/dev/null || true)" == "active" ]]; then
  backup_timer_active=1
else
  backup_timer_active=0
fi

if [[ "$(systemctl is-enabled slurm-pilot-mariadb-backup.timer 2>/dev/null || true)" == "enabled" ]]; then
  backup_timer_enabled=1
else
  backup_timer_enabled=0
fi

latest_dump="$(find /var/backups/slurm-pilot-mariadb -maxdepth 1 -type f -name 'slurm_acct_db-*.sql.gz' 2>/dev/null | sort | tail -n1 || true)"
if [[ -n "${latest_dump}" && -f "${latest_dump}" ]]; then
  latest_dump_age_hours="$(age_hours "${latest_dump}")"
else
  latest_dump_age_hours=-1
fi

latest_snapshot_dir="$(find /var/backups/slurm-pilot-mariadb/snapshots -maxdepth 1 -mindepth 1 -type d 2>/dev/null | sort | tail -n1 || true)"
if [[ -n "${latest_snapshot_dir}" && -d "${latest_snapshot_dir}" ]]; then
  latest_snapshot_age_hours="$(age_hours "${latest_snapshot_dir}")"
  if [[ -f "${latest_snapshot_dir}/slurm_acct_db.sql.gz" && -f "${latest_snapshot_dir}/metadata.json" && -f "${latest_snapshot_dir}/table_rows.tsv" ]]; then
    snapshot_complete=1
  else
    snapshot_complete=0
  fi
else
  latest_snapshot_age_hours=-1
  snapshot_complete=0
fi

login_pod="$(kubectl --kubeconfig "${KUBECONFIG_PATH}" -n "${NS}" get pod -o name 2>/dev/null | grep 'pod/slurm-pilot-login' | head -n1 | cut -d/ -f2 || true)"
storage_host="$(
  kubectl --kubeconfig "${KUBECONFIG_PATH}" -n "${NS}" exec slurm-pilot-accounting-0 -- \
    bash -lc 'grep -m1 "^StorageHost=" /etc/slurm/slurmdbd.conf | cut -d= -f2' 2>/dev/null || true
)"

if [[ -n "${storage_host}" && "${storage_host}" == "${EXTERNAL_HOST_ALIAS}" ]]; then
  current_backend_external=1
else
  current_backend_external=0
fi

if [[ -n "${login_pod}" ]]; then
  if kubectl --kubeconfig "${KUBECONFIG_PATH}" -n "${NS}" exec "${login_pod}" -- \
      bash -lc 'sacctmgr -nP list cluster >/dev/null 2>&1 && sacct -n -P -a -S 2026-04-04T00:00:00 >/dev/null 2>&1'; then
    accounting_read_ok=1
  else
    accounting_read_ok=0
  fi
else
  accounting_read_ok=0
fi

hostlocal_rollback_ready=1
if [[ "${mariadb_active}" -ne 1 || "${backup_timer_active}" -ne 1 || "${snapshot_complete}" -ne 1 ]]; then
  hostlocal_rollback_ready=0
fi

ext_pod_ready=0
if [[ "$(kubectl --kubeconfig "${KUBECONFIG_PATH}" -n "${NS}" get pod slurm-pilot-mariadb-ext-0 -o jsonpath='{.status.containerStatuses[0].ready}' 2>/dev/null || true)" == "true" ]]; then
  ext_pod_ready=1
fi

current_backend_healthy=0
if [[ "${current_backend_external}" -eq 1 ]]; then
  if [[ "${ext_pod_ready}" -eq 1 && "${accounting_read_ok}" -eq 1 ]]; then
    current_backend_healthy=1
  fi
else
  if [[ "${hostlocal_rollback_ready}" -eq 1 && "${accounting_read_ok}" -eq 1 ]]; then
    current_backend_healthy=1
  fi
fi

tmp="$(mktemp "${OUT_FILE}.XXXXXX")"
cat > "${tmp}" <<EOF
# HELP darwin_slurmdbd_hostlocal_mariadb_active Whether the host-local MariaDB backing slurmdbd is active.
# TYPE darwin_slurmdbd_hostlocal_mariadb_active gauge
darwin_slurmdbd_hostlocal_mariadb_active ${mariadb_active}
# HELP darwin_slurmdbd_hostlocal_mariadb_enabled Whether the host-local MariaDB backing slurmdbd is enabled on boot.
# TYPE darwin_slurmdbd_hostlocal_mariadb_enabled gauge
darwin_slurmdbd_hostlocal_mariadb_enabled ${mariadb_enabled}
# HELP darwin_slurmdbd_backup_timer_active Whether the host-local slurmdbd backup timer is active.
# TYPE darwin_slurmdbd_backup_timer_active gauge
darwin_slurmdbd_backup_timer_active ${backup_timer_active}
# HELP darwin_slurmdbd_backup_timer_enabled Whether the host-local slurmdbd backup timer is enabled on boot.
# TYPE darwin_slurmdbd_backup_timer_enabled gauge
darwin_slurmdbd_backup_timer_enabled ${backup_timer_enabled}
# HELP darwin_slurmdbd_latest_dump_age_hours Age in hours of the latest top-level logical Slurm accounting dump.
# TYPE darwin_slurmdbd_latest_dump_age_hours gauge
darwin_slurmdbd_latest_dump_age_hours ${latest_dump_age_hours}
# HELP darwin_slurmdbd_latest_snapshot_age_hours Age in hours of the latest migration-grade snapshot directory.
# TYPE darwin_slurmdbd_latest_snapshot_age_hours gauge
darwin_slurmdbd_latest_snapshot_age_hours ${latest_snapshot_age_hours}
# HELP darwin_slurmdbd_latest_snapshot_complete Whether the latest migration-grade snapshot is complete.
# TYPE darwin_slurmdbd_latest_snapshot_complete gauge
darwin_slurmdbd_latest_snapshot_complete ${snapshot_complete}
# HELP darwin_slurmdbd_current_storage_host_info Current StorageHost configured in slurmdbd.conf.
# TYPE darwin_slurmdbd_current_storage_host_info gauge
darwin_slurmdbd_current_storage_host_info{storage_host="${storage_host:-unknown}"} 1
# HELP darwin_slurmdbd_current_backend_external Whether the current live slurmdbd backend is the externalized K8s MariaDB candidate.
# TYPE darwin_slurmdbd_current_backend_external gauge
darwin_slurmdbd_current_backend_external ${current_backend_external}
# HELP darwin_slurmdbd_external_candidate_ready Whether the external MariaDB candidate pod is Running and Ready.
# TYPE darwin_slurmdbd_external_candidate_ready gauge
darwin_slurmdbd_external_candidate_ready ${ext_pod_ready}
# HELP darwin_slurmdbd_hostlocal_rollback_ready Whether the host-local MariaDB path remains ready as a rollback target.
# TYPE darwin_slurmdbd_hostlocal_rollback_ready gauge
darwin_slurmdbd_hostlocal_rollback_ready ${hostlocal_rollback_ready}
# HELP darwin_slurmdbd_current_backend_healthy Aggregate health for the current live slurmdbd backend path.
# TYPE darwin_slurmdbd_current_backend_healthy gauge
darwin_slurmdbd_current_backend_healthy ${current_backend_healthy}
# HELP darwin_slurmdbd_accounting_read_ok Whether sacctmgr and sacct can still read accounting data from the Slurm login pod.
# TYPE darwin_slurmdbd_accounting_read_ok gauge
darwin_slurmdbd_accounting_read_ok ${accounting_read_ok}
EOF

mv "${tmp}" "${OUT_FILE}"
chmod 0644 "${OUT_FILE}"
