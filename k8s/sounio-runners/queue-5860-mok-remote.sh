#!/usr/bin/env bash
set -euo pipefail

host="${PROXMOX_5860_HOST:-5860-proxmox}"
user="${PROXMOX_5860_USER:-root}"

if [[ -z "${PROXMOX_ROOT_PASSWORD:-}" ]]; then
  echo "Set PROXMOX_ROOT_PASSWORD in the environment before running this script." >&2
  exit 1
fi

if [[ -z "${MOK_ENROLL_PASSWORD:-}" ]]; then
  echo "Set MOK_ENROLL_PASSWORD in the environment before running this script." >&2
  exit 1
fi

export SSHPASS="${PROXMOX_ROOT_PASSWORD}"

sshpass -e ssh \
  -o StrictHostKeyChecking=no \
  -o PreferredAuthentications=password \
  -o PubkeyAuthentication=no \
  "${user}@${host}" \
  "MOK_ENROLL_PASSWORD='${MOK_ENROLL_PASSWORD}' python3 - <<'PY'
import os, pty, select

cmd = [
    'mokutil',
    '--import',
    '/var/lib/shim-signed/mok/MOK.der',
    '/var/lib/dkms/mok.pub',
]

password = os.environ['MOK_ENROLL_PASSWORD']
pid, fd = pty.fork()
if pid == 0:
    os.execvp(cmd[0], cmd)

buffer = ''
while True:
    ready, _, _ = select.select([fd], [], [], 5)
    if fd not in ready:
        continue
    try:
        data = os.read(fd, 4096)
    except OSError:
        break
    if not data:
        break
    text = data.decode(errors='ignore')
    print(text, end='')
    buffer += text.lower()
    if 'input password:' in buffer:
        os.write(fd, (password + '\\n').encode())
        buffer = ''
    elif 'input password again:' in buffer:
        os.write(fd, (password + '\\n').encode())
        buffer = ''

_, status = os.waitpid(pid, 0)
raise SystemExit(os.waitstatus_to_exitcode(status))
PY"
