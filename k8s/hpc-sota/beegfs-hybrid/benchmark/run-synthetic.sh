#!/usr/bin/env bash
set -euo pipefail

MOUNT="${1:-/beegfs}"
OUTDIR="${2:-${MOUNT}/benchmarks/$(hostname)-$(date +%Y%m%d-%H%M%S)}"

mkdir -p "${OUTDIR}"

echo "==> BeeGFS synthetic benchmark harness"
echo "mount=${MOUNT}"
echo "outdir=${OUTDIR}"

if ! mountpoint -q "${MOUNT}"; then
  echo "BeeGFS mount ${MOUNT} is not active" >&2
  exit 1
fi

{
  echo "host=$(hostname)"
  uname -a
  date -Is
} > "${OUTDIR}/context.txt"

if command -v beegfs >/dev/null 2>&1; then
  beegfs node list --mgmtd-addr=10.100.100.2:8010 > "${OUTDIR}/beegfs-node-list.txt" || true
fi

if command -v beegfs-net >/dev/null 2>&1; then
  beegfs-net > "${OUTDIR}/beegfs-net.txt" || true
fi

if command -v mdtest >/dev/null 2>&1; then
  mdtest -d "${OUTDIR}/mdtest" -n 10000 -i 1 -u > "${OUTDIR}/mdtest.txt" 2>&1 || true
fi

if command -v ior >/dev/null 2>&1; then
  ior -a POSIX -b 16g -t 2m -F -w -r -o "${OUTDIR}/ior" > "${OUTDIR}/ior.txt" 2>&1 || true
fi

echo "==> Synthetic benchmark artifacts in ${OUTDIR}"
