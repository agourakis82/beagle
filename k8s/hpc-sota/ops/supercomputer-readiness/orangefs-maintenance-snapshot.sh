#!/usr/bin/env bash
set -euo pipefail

PASS="${PASS:-Urso1982!}"
STAMP="${STAMP:-$(date -u +%Y%m%dT%H%M%SZ)}"
OUT_DIR="${OUT_DIR:-/home/devsounio/beagle/k8s/hpc-sota/ops/supercomputer-readiness/artifacts/orangefs-maintenance-${STAMP}}"

remote() {
  local host="$1"
  shift
  sshpass -p "${PASS}" ssh -o StrictHostKeyChecking=no -o ConnectTimeout=5 "root@${host}" "$@"
}

remote_copy() {
  local host="$1"
  local src="$2"
  local dest="$3"
  sshpass -p "${PASS}" scp -q -o StrictHostKeyChecking=no "root@${host}:${src}" "${dest}"
}

mkdir -p "${OUT_DIR}"/{t560-proxmox,5860-proxmox,local}

echo "Darwin/Sounio OrangeFS maintenance snapshot"
echo "out_dir=${OUT_DIR}"

{
  echo "# OrangeFS Maintenance Snapshot"
  echo
  echo "- generated_at: ${STAMP}"
  echo "- purpose: pre-maintenance evidence before any multi-TiB OrangeFS growth"
  echo "- mutation: none"
} >"${OUT_DIR}/README.md"

echo "[local] capacity doctor"
/home/devsounio/beagle/k8s/hpc-sota/ops/supercomputer-readiness/orangefs-capacity-doctor.sh \
  >"${OUT_DIR}/local/orangefs-capacity-doctor.txt"

echo "[local] growth gate"
/home/devsounio/beagle/k8s/hpc-sota/ops/supercomputer-readiness/orangefs-growth-gate.sh preflight \
  >"${OUT_DIR}/local/orangefs-growth-gate-preflight.txt"

echo "[local] mount"
findmnt -T /var/lib/orangefs-lab/client-runtime/mnt \
  >"${OUT_DIR}/local/orangefs-client-findmnt.txt" || true
df -hT /var/lib/orangefs-lab/client-runtime/mnt \
  >"${OUT_DIR}/local/orangefs-client-df.txt" || true

echo "[t560] collect server01 state"
remote t560-proxmox "systemctl status --no-pager orangefs-server01.service | sed -n '1,80p'" \
  >"${OUT_DIR}/t560-proxmox/orangefs-server01-status.txt" || true
remote t560-proxmox "df -hT /zfast/orangefs-lab /mnt/datasets /mnt/inference 2>/dev/null" \
  >"${OUT_DIR}/t560-proxmox/df-capacity.txt" || true
remote t560-proxmox "ls -la /zfast/orangefs-lab/two-node/etc /zfast/orangefs-lab/two-node/server01 2>/dev/null" \
  >"${OUT_DIR}/t560-proxmox/layout.txt" || true
remote_copy t560-proxmox /zfast/orangefs-lab/two-node/etc/orangefs_lab_2n.conf \
  "${OUT_DIR}/t560-proxmox/orangefs_lab_2n.conf" || true
remote_copy t560-proxmox /etc/systemd/system/orangefs-server01.service \
  "${OUT_DIR}/t560-proxmox/orangefs-server01.service" || true

echo "[5860] collect server02 state"
remote 5860-proxmox "systemctl status --no-pager orangefs-server02.service | sed -n '1,80p'" \
  >"${OUT_DIR}/5860-proxmox/orangefs-server02-status.txt" || true
remote 5860-proxmox "df -hT /srv/orangefs-server02-store /var/lib/orangefs-lab 2>/dev/null" \
  >"${OUT_DIR}/5860-proxmox/df-capacity.txt" || true
remote 5860-proxmox "lvs --units g --nosuffix --separator , -o lv_name,lv_size,data_percent,metadata_percent pve/data pve/orangefs_server02_store 2>/dev/null" \
  >"${OUT_DIR}/5860-proxmox/lvs-orangefs.txt" || true
remote 5860-proxmox "ls -la /srv/orangefs-server02-store /srv/orangefs-server02-store/{data,meta,log} 2>/dev/null" \
  >"${OUT_DIR}/5860-proxmox/layout.txt" || true
remote_copy 5860-proxmox /var/lib/orangefs-lab/two-node/etc/orangefs_lab_2n.conf \
  "${OUT_DIR}/5860-proxmox/orangefs_lab_2n.conf" || true
remote_copy 5860-proxmox /etc/systemd/system/orangefs-server02.service \
  "${OUT_DIR}/5860-proxmox/orangefs-server02.service" || true

echo "[local] checksums"
find "${OUT_DIR}" -type f -print0 | sort -z | xargs -0 sha256sum >"${OUT_DIR}/SHA256SUMS"

echo "snapshot complete: ${OUT_DIR}"
