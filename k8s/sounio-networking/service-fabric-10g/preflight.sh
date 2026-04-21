#!/usr/bin/env bash
set -euo pipefail

echo "== 5860 vmbr30 =="
sshpass -p 'Urso1982!' ssh -o StrictHostKeyChecking=no -o PreferredAuthentications=password -o PubkeyAuthentication=no root@5860-proxmox \
  "ip -br addr show vmbr30 2>/dev/null || true; brctl show vmbr30 2>/dev/null || true; \
   ss -lntup '( sport = :53 )' 2>/dev/null || true; \
   iptables -t nat -S 2>/dev/null | grep 10.30.0.0/24 || true; \
   systemctl is-active service-fabric-dnsmasq.service 2>/dev/null || true"

echo
echo "== Arista Vlan130 / Et33 =="
sshpass -p 'Arista123' ssh -o StrictHostKeyChecking=no -o PreferredAuthentications=password -o PubkeyAuthentication=no admin@192.168.3.229 $'enable\nshow vlan id 130\nshow ip interface brief | include Vlan130\nshow running-config interface Ethernet33\nping 10.30.0.1 source 10.30.0.254 repeat 2\n'
