#!/usr/bin/env bash
set -euo pipefail

EDGE_HOST="${EDGE_HOST:-root@5860-proxmox}"
EDGE_PASSWORD="${EDGE_PASSWORD:-}"
ROOT_DIR="/srv/service-fabric"
LOCAL_DIR="/home/devsounio/beagle/k8s/sounio-networking/service-fabric-10g"

if [[ -z "${EDGE_PASSWORD}" ]]; then
  echo "set EDGE_PASSWORD" >&2
  exit 1
fi

ssh_cmd=(sshpass -p "${EDGE_PASSWORD}" ssh -o StrictHostKeyChecking=no "${EDGE_HOST}")
scp_cmd=(sshpass -p "${EDGE_PASSWORD}" scp -o StrictHostKeyChecking=no -r)

"${ssh_cmd[@]}" "apt-get update && apt-get install -y docker.io docker-compose git jq curl && systemctl enable --now docker"
"${ssh_cmd[@]}" "mkdir -p ${ROOT_DIR}/registry/data ${ROOT_DIR}/technitium/config ${ROOT_DIR}/netbox/{postgres,redis,redis-cache,media,reports,scripts,secrets}"

"${scp_cmd[@]}" "${LOCAL_DIR}/registry-cache/" "${EDGE_HOST}:${ROOT_DIR}/registry/"
"${scp_cmd[@]}" "${LOCAL_DIR}/dns-control-plane/" "${EDGE_HOST}:${ROOT_DIR}/technitium/"
"${scp_cmd[@]}" "${LOCAL_DIR}/netbox/" "${EDGE_HOST}:${ROOT_DIR}/netbox-manifests/"

echo "edge service plane artifacts synced to ${EDGE_HOST}"
