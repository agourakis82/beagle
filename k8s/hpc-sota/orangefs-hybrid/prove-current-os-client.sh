#!/usr/bin/env bash
set -euo pipefail

TARGET_HOST="${TARGET_HOST:-root@10.100.100.2}"

SSH_BASE=(ssh -o StrictHostKeyChecking=no)
if [[ -n "${SSHPASS:-}" ]]; then
  SSH_BASE=(sshpass -p "${SSHPASS}" ssh -o StrictHostKeyChecking=no)
fi

echo "==> Proving OrangeFS kernel client path on ${TARGET_HOST}"

"${SSH_BASE[@]}" "${TARGET_HOST}" "bash -s" <<'REMOTE'
set -euo pipefail

echo "== kernel version =="
uname -r

echo "== modinfo orangefs =="
modinfo orangefs | sed -n '1,40p'

echo "== load module =="
modprobe orangefs

echo "== lsmod =="
lsmod | grep -i orangefs || true

echo "== filesystems =="
grep -i orangefs /proc/filesystems || true

echo "== unload module =="
modprobe -r orangefs
lsmod | grep -i orangefs || true
REMOTE
