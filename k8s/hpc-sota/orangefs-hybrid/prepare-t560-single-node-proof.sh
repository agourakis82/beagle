#!/usr/bin/env bash
set -euo pipefail

TARGET_HOST="${TARGET_HOST:-root@10.100.100.2}"
SRC_ROOT="${SRC_ROOT:-/zfast/orangefs-lab}"
BUILD_DIR="${BUILD_DIR:-/zfast/orangefs-lab/orangefs-build}"

SSH_BASE=(ssh -o StrictHostKeyChecking=no)
if [[ -n "${SSHPASS:-}" ]]; then
  SSH_BASE=(sshpass -p "${SSHPASS}" ssh -o StrictHostKeyChecking=no)
fi

echo "==> Preparing single-node OrangeFS proof workspace on ${TARGET_HOST}"

"${SSH_BASE[@]}" "${TARGET_HOST}" "bash -s" <<REMOTE
set -euo pipefail

install -d -m 0755 "${BUILD_DIR}"
install -d -m 0755 "${SRC_ROOT}/server-store"
install -d -m 0755 "${SRC_ROOT}/server-meta"
install -d -m 0755 "${SRC_ROOT}/mnt"

echo "== source head =="
cat "${SRC_ROOT}/orangefs-src/.current-head"

echo "== planned directories =="
ls -ld "${BUILD_DIR}" "${SRC_ROOT}/server-store" "${SRC_ROOT}/server-meta" "${SRC_ROOT}/mnt"
REMOTE
