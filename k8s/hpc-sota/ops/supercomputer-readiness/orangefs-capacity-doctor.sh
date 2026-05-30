#!/usr/bin/env bash
set -euo pipefail

PASS="${PASS:-Urso1982!}"
ORANGEFS_MOUNT="${ORANGEFS_MOUNT:-/var/lib/orangefs-lab/client-runtime/mnt}"
TARGET_TB="${TARGET_TB:-2}"

hosts=(
  t560-proxmox
  5860-proxmox
  r740-proxmox
  r770-proxmox
)

section() {
  echo
  echo "== $1 =="
}

bytes_to_tib() {
  awk -v b="$1" 'BEGIN { printf "%.2f", b / 1024 / 1024 / 1024 / 1024 }'
}

remote() {
  local host="$1"
  shift
  sshpass -p "${PASS}" ssh -o StrictHostKeyChecking=no -o ConnectTimeout=5 "root@${host}" "$@"
}

echo "Darwin/Sounio OrangeFS capacity doctor"
echo
echo "This script is read-only. It distinguishes exported OrangeFS capacity from raw host storage."

section "Worker-visible OrangeFS"
if ! findmnt -T "${ORANGEFS_MOUNT}" >/dev/null 2>&1; then
  echo "FAIL: OrangeFS mount is missing at ${ORANGEFS_MOUNT}"
  exit 1
fi

read -r source fstype size avail used < <(findmnt -T "${ORANGEFS_MOUNT}" -n -b -o SOURCE,FSTYPE,SIZE,AVAIL,USED)
size_tib="$(bytes_to_tib "${size}")"
avail_tib="$(bytes_to_tib "${avail}")"
echo "mount=${ORANGEFS_MOUNT}"
echo "source=${source}"
echo "fstype=${fstype}"
echo "size_tib=${size_tib}"
echo "avail_tib=${avail_tib}"

if awk -v size="${size_tib}" -v target="${TARGET_TB}" 'BEGIN { exit !(size >= target) }'; then
  echo "PASS: OrangeFS exported capacity is at least ${TARGET_TB} TiB"
  exported_ok=1
else
  echo "WARN: OrangeFS exported capacity is below ${TARGET_TB} TiB"
  exported_ok=0
fi

section "Candidate Local Capacity"
for host in "${hosts[@]}"; do
  echo "--- ${host} ---"
  if ! remote "${host}" "true" >/dev/null 2>&1; then
    echo "WARN: unable to reach ${host}"
    continue
  fi

  remote "${host}" "
    df -B1 -T \
      /mnt/darwin-fast \
      /mnt/hpc-local-nvme \
      /mnt/inference \
      /mnt/datasets \
      /srv/orangefs-server02-store \
      /var/lib/orangefs-lab 2>/dev/null |
    awk 'NR == 1 || \$5 ~ /^[0-9]+$/ {print}'
  " || true
done

section "Verdict"
if [[ "${exported_ok}" -eq 1 ]]; then
  echo "OrangeFS capacity verdict: MULTI-TERABYTE EXPORTED"
else
  echo "OrangeFS capacity verdict: REPAIRED BUT SUB-TERABYTE EXPORTED"
  echo "Next safe promotion requires adding or migrating to real exported server storage."
fi
