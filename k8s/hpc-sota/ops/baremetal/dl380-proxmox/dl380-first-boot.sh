#!/usr/bin/env bash
set -Eeuo pipefail

exec > >(tee -a /var/log/dl380-first-boot.log) 2>&1

echo "dl380 first boot: starting"

hostnamectl set-hostname dl380-proxmox

for entry in \
  "192.168.3.228 r770-proxmox r770-proxmox.local r770-proxmox.darwin.local" \
  "192.168.3.169 t560-proxmox t560-proxmox.local t560-proxmox.darwin.local" \
  "192.168.3.207 5860-proxmox 5860-proxmox.local 5860-proxmox.darwin.local" \
  "192.168.3.168 r740-proxmox r740-proxmox.local r740-proxmox.darwin.local" \
  "192.168.3.155 dl380-proxmox dl380-proxmox.local dl380-proxmox.darwin.local"
do
  address=${entry%% *}
  if ! grep -qE "^${address}[[:space:]]" /etc/hosts; then
    printf '%s\n' "$entry" >> /etc/hosts
  fi
done

# The installer enables subscription-only repositories by default. This lab
# follows the same no-subscription channels already used by the PVE cluster.
sed -i \
  -e 's#https://enterprise.proxmox.com/debian/pve#http://download.proxmox.com/debian/pve#' \
  -e 's#Components: pve-enterprise#Components: pve-no-subscription#' \
  /etc/apt/sources.list.d/pve-enterprise.sources

sed -i \
  -e 's#https://enterprise.proxmox.com/debian/ceph-squid#http://download.proxmox.com/debian/ceph-squid#' \
  -e 's#Components: enterprise#Components: no-subscription#' \
  /etc/apt/sources.list.d/ceph.sources

export DEBIAN_FRONTEND=noninteractive
apt-get update
apt-get install -y \
  ca-certificates \
  curl \
  ethtool \
  git \
  hwloc \
  infiniband-diags \
  jq \
  numactl \
  openssh-server \
  pciutils \
  rdma-core

systemctl enable --now ssh

install -d -m 0755 /var/lib/darwin
touch /var/lib/darwin/dl380-base-ready

echo "dl380 first boot: complete"
