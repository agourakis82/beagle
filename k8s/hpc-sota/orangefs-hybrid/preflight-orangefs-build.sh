#!/usr/bin/env bash
set -euo pipefail

TARGET_HOST="${TARGET_HOST:-root@10.100.100.2}"

SSH_BASE=(ssh -o StrictHostKeyChecking=no)
if [[ -n "${SSHPASS:-}" ]]; then
  SSH_BASE=(sshpass -p "${SSHPASS}" ssh -o StrictHostKeyChecking=no)
fi

echo "==> OrangeFS build preflight on ${TARGET_HOST}"

"${SSH_BASE[@]}" "${TARGET_HOST}" "bash -s" <<'REMOTE'
set -euo pipefail

echo "== system =="
uname -r
. /etc/os-release
echo "${PRETTY_NAME}"

echo "== orangefs kernel client =="
modinfo orangefs | sed -n '1,20p'

echo "== build tools =="
for bin in git gcc make autoconf automake libtool pkg-config; do
  if command -v "${bin}" >/dev/null 2>&1; then
    echo "present ${bin}"
  else
    echo "missing ${bin}"
  fi
done

echo "== likely libs =="
dpkg -l | egrep 'libssl|libxml2|dbus|zlib|bison|flex' | sed -n '1,80p' || true

echo "== workspace =="
df -h / /zfast 2>/dev/null || true
REMOTE
