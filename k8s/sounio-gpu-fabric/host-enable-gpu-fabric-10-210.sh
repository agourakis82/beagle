#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat >&2 <<'EOF'
usage: host-enable-gpu-fabric-10-210.sh <r770-proxmox|r740-proxmox|5860-proxmox>

Creates a persistent vmbr210 + VLAN 210 uplink on the GPU hosts.
This keeps the pilot 10.200 fabric intact on gpufabricbr0 and exposes the
dedicated 10.210 fabric as altname gpufabric210.
EOF
}

if [[ $# -ne 1 ]]; then
  usage
  exit 1
fi

host="$1"
case "${host}" in
  r770-proxmox)
    raw="nic3"
    host_ip="10.210.0.1/24"
    ;;
  r740-proxmox)
    raw="nic4"
    host_ip="10.210.0.4/24"
    ;;
  5860-proxmox)
    raw="ens5f1np1"
    host_ip="10.210.0.3/24"
    ;;
  *)
    usage
    echo "unknown host: ${host}" >&2
    exit 1
    ;;
esac

cfg_path="/etc/network/interfaces.d/80-gpu-fabric-210.cfg"
vlan_if="${raw}.210"

cat >"${cfg_path}" <<EOF
auto ${vlan_if}
iface ${vlan_if} inet manual
    vlan-raw-device ${raw}
    mtu 9000

auto vmbr210
iface vmbr210 inet static
    post-up ip link property add dev vmbr210 altname gpufabric210 || true
    address ${host_ip}
    bridge-ports ${vlan_if}
    bridge-stp off
    bridge-fd 0
    mtu 9000
EOF

ifdown vmbr210 >/dev/null 2>&1 || true
ifdown "${vlan_if}" >/dev/null 2>&1 || true
ifreload -a || true
ifup "${vlan_if}"
ifup vmbr210
ip -br addr show vmbr210
ip -d link show vmbr210 | sed -n '1,80p'
