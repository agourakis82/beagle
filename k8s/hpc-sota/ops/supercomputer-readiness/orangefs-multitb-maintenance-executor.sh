#!/usr/bin/env bash
set -euo pipefail

MODE="dry-run"
CONFIRM="${ORANGEFS_MULTITB_CONFIRM:-}"
PASS="${PASS:-Urso1982!}"
SNAPSHOT_DIR="${SNAPSHOT_DIR:-}"
PLAN_DIR="${PLAN_DIR:-/home/devsounio/beagle/k8s/hpc-sota/ops/supercomputer-readiness/artifacts/orangefs-multitb-plan}"
TARGET_BACKING_PATH="${TARGET_BACKING_PATH:-/mnt/datasets}"
TARGET_ROOT="${TARGET_ROOT:-/mnt/datasets/orangefs-lab/two-node}"
SERVER02_CONF_PATH="${SERVER02_CONF_PATH:-/var/lib/orangefs-lab/two-node/etc/orangefs_lab_2n.conf}"
OLD_SERVER01_ROOT="${OLD_SERVER01_ROOT:-/zfast/orangefs-lab/two-node/server01}"
TARGET_CONF="${TARGET_CONF:-${PLAN_DIR}/orangefs_lab_2n.multitb-target.conf}"
TARGET_UNIT="${TARGET_UNIT:-${PLAN_DIR}/orangefs-server01.multitb-target.service}"
MIN_TARGET_AVAIL_TIB="${MIN_TARGET_AVAIL_TIB:-1.25}"
SNAPSHOT_MAX_AGE_HOURS="${SNAPSHOT_MAX_AGE_HOURS:-6}"
ARTIFACT_ROOT="${ARTIFACT_ROOT:-/home/devsounio/beagle/k8s/hpc-sota/ops/supercomputer-readiness/artifacts/orangefs-multitb-runs}"
LOCK_FILE="${LOCK_FILE:-/tmp/darwin-orangefs-multitb-maintenance.lock}"
RUN_ID="$(date -u +%Y%m%dT%H%M%SZ)-$$"
REPORT_DIR="${REPORT_DIR:-${ARTIFACT_ROOT}/${RUN_ID}}"
REPORT_FILE="${REPORT_FILE:-${REPORT_DIR}/report.env}"

usage() {
  cat <<'EOF'
usage: orangefs-multitb-maintenance-executor.sh [--dry-run|--apply|--rollback] --snapshot-dir PATH

Default mode is --dry-run. The script is intentionally conservative:

  --dry-run  prints the exact maintenance sequence and validates local inputs
  --apply    executes the sequence only when ORANGEFS_MULTITB_CONFIRM=APPLY is set
  --rollback restores config/unit files from the snapshot when ORANGEFS_MULTITB_CONFIRM=ROLLBACK is set

Required before --apply:

  1. explicit maintenance window
  2. fresh orangefs-maintenance-snapshot.sh artifact
  3. generated plan from orangefs-generate-multitb-plan.sh
  4. ORANGEFS_MULTITB_CONFIRM=APPLY

No live storage mutation is performed in --dry-run mode.
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --dry-run)
      MODE="dry-run"
      shift
      ;;
    --apply)
      MODE="apply"
      shift
      ;;
    --rollback)
      MODE="rollback"
      shift
      ;;
    --snapshot-dir)
      SNAPSHOT_DIR="${2:-}"
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "unknown argument: $1" >&2
      usage >&2
      exit 2
      ;;
  esac
done

repo_root="/home/devsounio/beagle/k8s/hpc-sota"
growth_gate="${repo_root}/ops/supercomputer-readiness/orangefs-growth-gate.sh"
generator="${repo_root}/ops/supercomputer-readiness/orangefs-generate-multitb-plan.sh"
capacity_doctor="${repo_root}/ops/supercomputer-readiness/orangefs-capacity-doctor.sh"
sota_doctor="${repo_root}/ops/supercomputer-readiness/sota-readiness-doctor.sh"
canary_runner="${repo_root}/orangefs-hybrid/run-k8s-multinode-orangefs-benchmark.sh"

remote() {
  local host="$1"
  shift
  local attempt
  for attempt in 1 2 3; do
    if sshpass -p "${PASS}" ssh \
      -o StrictHostKeyChecking=no \
      -o ConnectTimeout=8 \
      -o ConnectionAttempts=1 \
      "root@${host}" "$@"; then
      return 0
    fi
    sleep "${attempt}"
  done
  return 1
}

print_cmd() {
  printf '  %s\n' "$*"
}

require_file() {
  local path="$1"
  if [[ ! -f "${path}" ]]; then
    echo "missing required file: ${path}" >&2
    exit 1
  fi
}

require_dir() {
  local path="$1"
  if [[ ! -d "${path}" ]]; then
    echo "missing required directory: ${path}" >&2
    exit 1
  fi
}

report_kv() {
  printf '%s=%q\n' "$1" "$2" >>"${REPORT_FILE}"
}

record_command_output() {
  local name="$1"
  shift
  "$@" >"${REPORT_DIR}/${name}.txt" 2>&1
}

snapshot_age_hours() {
  python3 - "$1" <<'PY'
import os
import sys
import time

path = sys.argv[1]
age = (time.time() - os.stat(path).st_mtime) / 3600
print(f"{age:.2f}")
PY
}

verify_snapshot_fresh_enough() {
  local age
  age="$(snapshot_age_hours "${SNAPSHOT_DIR}/README.md")"
  echo "snapshot_age_hours=${age}"
  if ! awk -v age="${age}" -v max="${SNAPSHOT_MAX_AGE_HOURS}" 'BEGIN { exit !(age <= max) }'; then
    echo "snapshot is older than ${SNAPSHOT_MAX_AGE_HOURS}h; create a fresh maintenance snapshot before apply" >&2
    return 1
  fi
}

target_avail_tib() {
  remote t560-proxmox "df -B1 --output=avail '${TARGET_BACKING_PATH}' | awk 'NR==2 { printf \"%.2f\", \$1 / 1024 / 1024 / 1024 / 1024 }'"
}

strict_apply_preflight() {
  echo
  echo "== Strict Apply Preflight =="
  verify_snapshot_fresh_enough

  echo "checking t560 target backing path: ${TARGET_BACKING_PATH}"
  remote t560-proxmox "test -d '${TARGET_BACKING_PATH}'"

  local avail
  avail="$(target_avail_tib)"
  echo "target_avail_tib=${avail}"
  if ! awk -v avail="${avail}" -v min="${MIN_TARGET_AVAIL_TIB}" 'BEGIN { exit !(avail >= min) }'; then
    echo "target root has less than ${MIN_TARGET_AVAIL_TIB} TiB available" >&2
    return 1
  fi

  echo "checking current server01 source directories"
  remote t560-proxmox "test -d '${OLD_SERVER01_ROOT}/data' && test -d '${OLD_SERVER01_ROOT}/meta' && test -d '${OLD_SERVER01_ROOT}/log'"

  echo "checking target paths are not existing mountpoints"
  remote t560-proxmox "if mountpoint -q '${TARGET_ROOT}/server01/data'; then exit 1; else exit 0; fi"
  remote t560-proxmox "if mountpoint -q '${TARGET_ROOT}/server01/meta'; then exit 1; else exit 0; fi"
  remote t560-proxmox "if mountpoint -q '${TARGET_ROOT}/server01/log'; then exit 1; else exit 0; fi"

  echo "checking OrangeFS services are currently known"
  remote t560-proxmox "systemctl cat orangefs-server01.service >/dev/null"
  remote 5860-proxmox "systemctl cat orangefs-server02.service >/dev/null"
  remote r740-proxmox "systemctl cat orangefs-client-runtime.service >/dev/null"
  remote r770-proxmox "systemctl cat orangefs-client-runtime.service >/dev/null"

  echo "checking generated target config references expected paths"
  grep -q "DataStorageSpace ${TARGET_ROOT}/server01/data" "${TARGET_CONF}"
  grep -q "MetadataStorageSpace ${TARGET_ROOT}/server01/meta" "${TARGET_CONF}"
  grep -q "DataStorageSpace /srv/orangefs-server02-store/data" "${TARGET_CONF}"

  echo "strict apply preflight: PASS"
}

echo "Darwin/Sounio OrangeFS multi-TiB maintenance executor"
echo
echo "mode=${MODE}"

mkdir -p "${REPORT_DIR}"
: >"${REPORT_FILE}"
report_kv "run_id" "${RUN_ID}"
report_kv "mode" "${MODE}"
report_kv "started_at_utc" "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
report_kv "snapshot_dir" "${SNAPSHOT_DIR}"
report_kv "target_root" "${TARGET_ROOT}"
report_kv "target_backing_path" "${TARGET_BACKING_PATH}"
report_kv "report_dir" "${REPORT_DIR}"

exec 9>"${LOCK_FILE}"
if ! flock -n 9; then
  echo "another OrangeFS multi-TiB maintenance executor is running; lock=${LOCK_FILE}" >&2
  report_kv "result" "lock_busy"
  exit 4
fi
report_kv "lock_file" "${LOCK_FILE}"

if [[ -z "${SNAPSHOT_DIR}" ]]; then
  echo "missing --snapshot-dir PATH" >&2
  echo "Create one immediately before the window with:" >&2
  echo "  /home/devsounio/beagle/k8s/hpc-sota/ops/supercomputer-readiness/orangefs-maintenance-snapshot.sh" >&2
  exit 2
fi

require_dir "${SNAPSHOT_DIR}"
require_file "${SNAPSHOT_DIR}/SHA256SUMS"
require_file "${SNAPSHOT_DIR}/t560-proxmox/orangefs_lab_2n.conf"
require_file "${SNAPSHOT_DIR}/t560-proxmox/orangefs-server01.service"
require_file "${SNAPSHOT_DIR}/5860-proxmox/orangefs_lab_2n.conf"
require_file "${SNAPSHOT_DIR}/5860-proxmox/orangefs-server02.service"

if [[ "${MODE}" == "rollback" ]]; then
  echo
  echo "== Rollback Sequence =="
  print_cmd "ssh r740-proxmox 'systemctl stop orangefs-client-runtime.service || true'"
  print_cmd "ssh r770-proxmox 'systemctl stop orangefs-client-runtime.service || true'"
  print_cmd "ssh t560-proxmox 'systemctl stop orangefs-client-runtime.service || true'"
  print_cmd "scp ${SNAPSHOT_DIR}/t560-proxmox/orangefs_lab_2n.conf t560-proxmox:/zfast/orangefs-lab/two-node/etc/orangefs_lab_2n.conf"
  print_cmd "scp ${SNAPSHOT_DIR}/t560-proxmox/orangefs-server01.service t560-proxmox:/etc/systemd/system/orangefs-server01.service"
  print_cmd "scp ${SNAPSHOT_DIR}/5860-proxmox/orangefs_lab_2n.conf 5860-proxmox:${SERVER02_CONF_PATH}"
  print_cmd "scp ${SNAPSHOT_DIR}/5860-proxmox/orangefs-server02.service 5860-proxmox:/etc/systemd/system/orangefs-server02.service"
  print_cmd "ssh t560-proxmox 'systemctl daemon-reload && systemctl restart orangefs-server01.service'"
  print_cmd "ssh 5860-proxmox 'systemctl daemon-reload && systemctl restart orangefs-server02.service'"
  print_cmd "ssh t560-proxmox 'systemctl restart orangefs-client-runtime.service'"
  print_cmd "ssh r740-proxmox 'systemctl restart orangefs-client-runtime.service'"
  print_cmd "ssh r770-proxmox 'systemctl restart orangefs-client-runtime.service'"
  print_cmd "${capacity_doctor}"
  print_cmd "${sota_doctor}"

  if [[ "${CONFIRM}" != "ROLLBACK" ]]; then
    echo
    report_kv "result" "rollback_dry_run_pass"
    report_kv "finished_at_utc" "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
    echo "Rollback dry run complete. Set ORANGEFS_MULTITB_CONFIRM=ROLLBACK to execute."
    echo "report=${REPORT_FILE}"
    exit 0
  fi

  echo
  echo "== Applying Rollback =="
  remote r740-proxmox "systemctl stop orangefs-client-runtime.service || true"
  remote r770-proxmox "systemctl stop orangefs-client-runtime.service || true"
  remote t560-proxmox "systemctl stop orangefs-client-runtime.service || true"
  scp "${SNAPSHOT_DIR}/t560-proxmox/orangefs_lab_2n.conf" "t560-proxmox:/zfast/orangefs-lab/two-node/etc/orangefs_lab_2n.conf" >/dev/null
  scp "${SNAPSHOT_DIR}/t560-proxmox/orangefs-server01.service" "t560-proxmox:/etc/systemd/system/orangefs-server01.service" >/dev/null
  scp "${SNAPSHOT_DIR}/5860-proxmox/orangefs_lab_2n.conf" "5860-proxmox:${SERVER02_CONF_PATH}" >/dev/null
  scp "${SNAPSHOT_DIR}/5860-proxmox/orangefs-server02.service" "5860-proxmox:/etc/systemd/system/orangefs-server02.service" >/dev/null
  remote t560-proxmox "systemctl daemon-reload && systemctl restart orangefs-server01.service"
  remote 5860-proxmox "systemctl daemon-reload && systemctl restart orangefs-server02.service"
  remote t560-proxmox "systemctl restart orangefs-client-runtime.service"
  remote r740-proxmox "systemctl restart orangefs-client-runtime.service"
  remote r770-proxmox "systemctl restart orangefs-client-runtime.service"
  "${capacity_doctor}"
  "${sota_doctor}"
  record_command_output "orangefs-capacity-doctor-rollback-post" "${capacity_doctor}"
  record_command_output "sota-readiness-doctor-rollback-post" "${sota_doctor}"
  report_kv "result" "rollback_complete"
  report_kv "finished_at_utc" "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  echo "report=${REPORT_FILE}"
  exit 0
fi

if [[ ! -f "${TARGET_CONF}" || ! -f "${TARGET_UNIT}" ]]; then
  echo "generated plan missing; generating review artifacts"
  "${generator}"
fi

require_file "${TARGET_CONF}"
require_file "${TARGET_UNIT}"
require_file "${growth_gate}"

echo
echo "== Snapshot =="
echo "snapshot_dir=${SNAPSHOT_DIR}"
echo "snapshot_sha256=${SNAPSHOT_DIR}/SHA256SUMS"

echo
echo "== Plan Artifacts =="
echo "target_conf=${TARGET_CONF}"
echo "target_unit=${TARGET_UNIT}"
sha256sum "${TARGET_CONF}" "${TARGET_UNIT}"
sha256sum "${TARGET_CONF}" "${TARGET_UNIT}" >"${REPORT_DIR}/target-artifact-sha256.txt"

echo
echo "== Read-only Preflight =="
"${growth_gate}" preflight
strict_apply_preflight
record_command_output "strict-preflight-snapshot" snapshot_age_hours "${SNAPSHOT_DIR}/README.md"

echo
echo "== Maintenance Sequence =="
print_cmd "ssh t560-proxmox 'mkdir -p ${TARGET_ROOT}/server01/{data,meta,log} ${TARGET_ROOT}/etc'"
print_cmd "ssh t560-proxmox 'rsync -aHAX --numeric-ids ${OLD_SERVER01_ROOT}/data/ ${TARGET_ROOT}/server01/data/'"
print_cmd "ssh t560-proxmox 'rsync -aHAX --numeric-ids ${OLD_SERVER01_ROOT}/meta/ ${TARGET_ROOT}/server01/meta/'"
print_cmd "ssh t560-proxmox 'rsync -aHAX --numeric-ids ${OLD_SERVER01_ROOT}/log/ ${TARGET_ROOT}/server01/log/'"
print_cmd "scp ${TARGET_CONF} t560-proxmox:${TARGET_ROOT}/etc/orangefs_lab_2n.conf"
print_cmd "scp ${TARGET_CONF} 5860-proxmox:${SERVER02_CONF_PATH}"
print_cmd "scp ${TARGET_UNIT} t560-proxmox:/etc/systemd/system/orangefs-server01.service"
print_cmd "ssh t560-proxmox 'systemctl daemon-reload'"
print_cmd "ssh r740-proxmox 'systemctl stop orangefs-client-runtime.service || true'"
print_cmd "ssh r770-proxmox 'systemctl stop orangefs-client-runtime.service || true'"
print_cmd "ssh t560-proxmox 'systemctl stop orangefs-client-runtime.service || true'"
print_cmd "ssh t560-proxmox 'systemctl restart orangefs-server01.service'"
print_cmd "ssh 5860-proxmox 'systemctl restart orangefs-server02.service'"
print_cmd "ssh t560-proxmox 'systemctl restart orangefs-client-runtime.service'"
print_cmd "ssh r740-proxmox 'systemctl restart orangefs-client-runtime.service'"
print_cmd "ssh r770-proxmox 'systemctl restart orangefs-client-runtime.service'"
print_cmd "${capacity_doctor}"
print_cmd "${canary_runner}"
print_cmd "${sota_doctor}"

if [[ "${MODE}" == "dry-run" ]]; then
  echo
  report_kv "result" "dry_run_pass"
  report_kv "finished_at_utc" "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  echo "Dry run complete. No live storage mutation was performed."
  echo "report=${REPORT_FILE}"
  exit 0
fi

if [[ "${CONFIRM}" != "APPLY" ]]; then
  echo "refusing --apply without ORANGEFS_MULTITB_CONFIRM=APPLY" >&2
  report_kv "result" "apply_refused_missing_confirm"
  report_kv "finished_at_utc" "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  exit 3
fi

echo
echo "== Applying Maintenance Sequence =="
remote t560-proxmox "mkdir -p '${TARGET_ROOT}/server01/data' '${TARGET_ROOT}/server01/meta' '${TARGET_ROOT}/server01/log' '${TARGET_ROOT}/etc'"
remote t560-proxmox "rsync -aHAX --numeric-ids '${OLD_SERVER01_ROOT}/data/' '${TARGET_ROOT}/server01/data/'"
remote t560-proxmox "rsync -aHAX --numeric-ids '${OLD_SERVER01_ROOT}/meta/' '${TARGET_ROOT}/server01/meta/'"
remote t560-proxmox "rsync -aHAX --numeric-ids '${OLD_SERVER01_ROOT}/log/' '${TARGET_ROOT}/server01/log/'"
scp "${TARGET_CONF}" "t560-proxmox:${TARGET_ROOT}/etc/orangefs_lab_2n.conf" >/dev/null
scp "${TARGET_CONF}" "5860-proxmox:${SERVER02_CONF_PATH}" >/dev/null
scp "${TARGET_UNIT}" "t560-proxmox:/etc/systemd/system/orangefs-server01.service" >/dev/null
remote t560-proxmox "systemctl daemon-reload"
remote r740-proxmox "systemctl stop orangefs-client-runtime.service || true"
remote r770-proxmox "systemctl stop orangefs-client-runtime.service || true"
remote t560-proxmox "systemctl stop orangefs-client-runtime.service || true"
remote t560-proxmox "systemctl restart orangefs-server01.service"
remote 5860-proxmox "systemctl restart orangefs-server02.service"
remote t560-proxmox "systemctl restart orangefs-client-runtime.service"
remote r740-proxmox "systemctl restart orangefs-client-runtime.service"
remote r770-proxmox "systemctl restart orangefs-client-runtime.service"
"${capacity_doctor}"
"${canary_runner}"
"${sota_doctor}"
record_command_output "orangefs-capacity-doctor-post" "${capacity_doctor}"
record_command_output "sota-readiness-doctor-post" "${sota_doctor}"
report_kv "result" "apply_complete"
report_kv "finished_at_utc" "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
echo "report=${REPORT_FILE}"
