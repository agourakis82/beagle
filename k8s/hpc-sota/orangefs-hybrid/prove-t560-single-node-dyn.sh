#!/usr/bin/env bash
set -euo pipefail

host="${ORANGEFS_HOST:-root@10.100.100.2}"
pass="${ORANGEFS_PASS:-Urso1982!}"

ssh_cmd=(
  sshpass -p "$pass"
  ssh
  -o StrictHostKeyChecking=no
  "$host"
)

"${ssh_cmd[@]}" '
set -euo pipefail

base=/zfast/orangefs-lab/single-node-dyn
server=/zfast/orangefs-lab/orangefs-build-serveronly-dyn/src/server/pvfs2-server
conf=$base/etc/pvfs2-fs.conf

mkdir -p "$base"/{data,meta,log,mnt,etc}
cp -f /home/devsounio/beagle/k8s/hpc-sota/orangefs-hybrid/single-node-fs.conf.example "$conf"

"$server" -f -a t560-proxmox "$conf"

set +e
timeout 8s "$server" -d -a t560-proxmox "$conf" > "$base/log/foreground.out" 2>&1
rc=$?
set -e

printf "server_rc=%s\n" "$rc"
ls -lah "$base/data" "$base/meta" "$base/log"
printf "\n--- foreground.out ---\n"
sed -n "1,120p" "$base/log/foreground.out"
printf "\n--- pvfs2-server.log ---\n"
sed -n "1,120p" "$base/log/pvfs2-server.log" 2>/dev/null || true
'
