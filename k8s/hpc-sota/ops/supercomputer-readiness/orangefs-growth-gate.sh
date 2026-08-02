#!/usr/bin/env bash
set -euo pipefail

PASS="${PASS:?defina PASS no ambiente (nunca no script); prefira chave SSH}"
MIN_TIB="${MIN_TIB:-1.25}"
MODE="${1:-status}"

candidate_specs=(
  "t560-proxmox:/mnt/datasets:zfast datasets tier; service anchor"
  "r740-proxmox:/mnt/hpc-local-nvme:near-GPU NVMe; current OrangeFS client"
  "r770-proxmox:/mnt/darwin-fast:near-GPU fast local disk; current OrangeFS client"
  "5860-proxmox:/srv/orangefs-server02-store:current server02 backend; thin-pool constrained"
)

usage() {
  cat <<'EOF'
usage: orangefs-growth-gate.sh [status|preflight]

Read-only gate for promoting OrangeFS from repaired sub-TiB export to a real
multi-TiB shared data plane.

status    Summarize exported OrangeFS capacity and candidate backing paths.
preflight Enforce conservative readiness checks for a future growth window.

This script does not format disks, stop services, edit OrangeFS config, or move
data. It exists to prevent accidental "capacity expansion" onto the wrong
storage tier.
EOF
}

remote() {
  local host="$1"
  shift
  sshpass -p "${PASS}" ssh -o StrictHostKeyChecking=no -o ConnectTimeout=5 "root@${host}" "$@"
}

bytes_to_tib() {
  awk -v b="$1" 'BEGIN { printf "%.2f", b / 1024 / 1024 / 1024 / 1024 }'
}

section() {
  echo
  echo "== $1 =="
}

candidate_table() {
  local failures=0
  printf '%-14s %-24s %-8s %-8s %-8s %s\n' "HOST" "PATH" "SIZE_TIB" "AVAIL" "USE%" "NOTES"
  for spec in "${candidate_specs[@]}"; do
    IFS=: read -r host path notes <<<"${spec}"
    if ! out="$(remote "${host}" "df -B1 -T '${path}' 2>/dev/null | awk 'NR==2 {print \$2,\$3,\$4,\$5,\$6,\$7}'" 2>/dev/null)"; then
      printf '%-14s %-24s %-8s %-8s %-8s %s\n' "${host}" "${path}" "n/a" "n/a" "n/a" "unreachable or missing"
      failures=$((failures + 1))
      continue
    fi
    if [[ -z "${out}" ]]; then
      printf '%-14s %-24s %-8s %-8s %-8s %s\n' "${host}" "${path}" "n/a" "n/a" "n/a" "missing"
      failures=$((failures + 1))
      continue
    fi
    read -r fstype size used avail use mount <<<"${out}"
    printf '%-14s %-24s %-8s %-8s %-8s %s\n' \
      "${host}" "${path}" "$(bytes_to_tib "${size}")" "$(bytes_to_tib "${avail}")" "${use}" "${notes}"
  done
  return "${failures}"
}

orangefs_exported_tib() {
  local mount="${ORANGEFS_MOUNT:-/var/lib/orangefs-lab/client-runtime/mnt}"
  findmnt -T "${mount}" -n -b -o SIZE 2>/dev/null | awk '{ printf "%.2f", $1 / 1024 / 1024 / 1024 / 1024 }'
}

case "${MODE}" in
  -h|--help)
    usage
    exit 0
    ;;
  status)
    echo "Darwin/Sounio OrangeFS growth gate"
    echo
    echo "mode=status (read-only)"
    section "Exported Capacity"
    exported="$(orangefs_exported_tib || true)"
    echo "orangefs_exported_tib=${exported:-unknown}"
    section "Candidate Backing Paths"
    candidate_table || true
    ;;
  preflight)
    echo "Darwin/Sounio OrangeFS growth gate"
    echo
    echo "mode=preflight (read-only)"
    failures=0

    section "Current Export"
    exported="$(orangefs_exported_tib || true)"
    echo "orangefs_exported_tib=${exported:-unknown}"
    if [[ -n "${exported}" ]] && awk -v value="${exported}" 'BEGIN { exit !(value < 2.0) }'; then
      echo "PASS: current export is still below the multi-TiB target; growth gate is relevant"
    else
      echo "WARN: current export already appears multi-TiB or unreadable"
    fi

    section "Candidate Backing Paths"
    candidate_table || failures=$((failures + 1))

    section "Promotion Hold Points"
    echo "REQUIRED: explicit maintenance window"
    echo "REQUIRED: OrangeFS config/snapshot backup"
    echo "REQUIRED: selected target path with >= ${MIN_TIB} TiB available"
    echo "REQUIRED: target path is not a nearly-full thin pool"
    echo "REQUIRED: client canary plan after remount"
    echo "REQUIRED: rollback path to current two-node export"

    if [[ "${failures}" -gt 0 ]]; then
      echo
      echo "OrangeFS growth preflight: FAIL (${failures} failure(s))"
      exit 1
    fi

    echo
    echo "OrangeFS growth preflight: HOLD FOR MAINTENANCE WINDOW"
    echo "No live storage mutation was performed."
    ;;
  *)
    usage >&2
    echo "unknown mode: ${MODE}" >&2
    exit 2
    ;;
esac
