#!/usr/bin/env bash
set -euo pipefail

CACHE_HOST="${CACHE_HOST:-10.100.100.3}"
TARGET_NODE="${TARGET_NODE:-10.100.100.4}"
SSH_PASS="${SSHPASS:-Urso1982!}"

pull_on_node() {
  local image="$1"
  sshpass -p "$SSH_PASS" ssh -o StrictHostKeyChecking=no root@"$TARGET_NODE" \
    "crictl pull $image" >/dev/null
}

show_logs() {
  local container="$1"
  sshpass -p "$SSH_PASS" ssh -o StrictHostKeyChecking=no root@"$CACHE_HOST" \
    "docker logs --since 2m $container 2>&1 | tail -n 20"
}

echo "[INFO] verifying docker.io mirror via $CACHE_HOST:5000 from $TARGET_NODE"
pull_on_node docker.io/library/httpd:2.4.62-alpine3.20
show_logs registry-cache-dockerhub

echo "[INFO] verifying registry.k8s.io mirror via $CACHE_HOST:5002 from $TARGET_NODE"
pull_on_node registry.k8s.io/e2e-test-images/agnhost:2.53
show_logs registry-cache-k8s

echo "[INFO] verifying ghcr.io mirror via $CACHE_HOST:5001 from $TARGET_NODE"
sshpass -p "$SSH_PASS" ssh -o StrictHostKeyChecking=no root@"$TARGET_NODE" \
  "crictl rmi ghcr.io/mellanox/k8s-rdma-shared-dev-plugin:v1.5.3 >/dev/null 2>&1 || true"
pull_on_node ghcr.io/mellanox/k8s-rdma-shared-dev-plugin:v1.5.3
show_logs registry-cache-ghcr

echo "[OK] mirror verification completed"
