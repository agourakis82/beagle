#!/usr/bin/env bash
set -euo pipefail

if [[ -z "${PROXMOX_ROOT_PASSWORD:-}" ]]; then
  echo "set PROXMOX_ROOT_PASSWORD before running this script" >&2
  exit 1
fi

if ! command -v sshpass >/dev/null 2>&1; then
  echo "sshpass is required" >&2
  exit 1
fi

declare -A BRIDGE_BY_HOST=(
  [r770-proxmox]=vmbr1
  [r740-proxmox]=vmbr200
  [5860-proxmox]=vmbr200
)

for host in "${!BRIDGE_BY_HOST[@]}"; do
  bridge="${BRIDGE_BY_HOST[$host]}"
  echo "== ${host} (${bridge}) =="
  sshpass -p "${PROXMOX_ROOT_PASSWORD}" ssh -o StrictHostKeyChecking=no "root@${host}" "
set -euo pipefail
cp /etc/network/interfaces /etc/network/interfaces.bak.\$(date +%Y%m%d%H%M%S)
python3 - <<'PY'
from pathlib import Path
path = Path('/etc/network/interfaces')
text = path.read_text()
needle = 'iface ${bridge} inet static\\n'
if needle not in text:
    raise SystemExit(f'missing stanza for ${bridge}')
addition = needle + '\tpost-up ip link property add dev ${bridge} altname gpufabricbr0 || true\\n'
if 'post-up ip link property add dev ${bridge} altname gpufabricbr0 || true' not in text:
    text = text.replace(needle, addition, 1)
path.write_text(text)
PY
ip link property add dev ${bridge} altname gpufabricbr0 || true
ip -d link show dev ${bridge} | sed -n '1,3p'
"
  echo
done
