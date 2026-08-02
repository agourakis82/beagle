#!/usr/bin/env bash
set -euo pipefail

KUBECTL_BIN="${KUBECTL_BIN:-sudo kubectl}"

echo "[INFO] cluster version"
$KUBECTL_BIN version --short || true

echo "[INFO] gpu nodes"
$KUBECTL_BIN get nodes -L sounio.dev/accelerator,sounio.dev/pool

echo "[INFO] existing GPU/RDMA substrate"
$KUBECTL_BIN get pods -A | egrep 'nvidia-device-plugin|rdma-shared|multus|whereabouts' || true

echo "[INFO] namespaces reserved for operator staging"
$KUBECTL_BIN get ns gpu-operator nvidia-network-operator --show-labels

echo "[INFO] warning"
echo "This cluster is on Kubernetes 1.35.2."
echo "The community-supported NVIDIA Network Operator matrix confirmed during research did not clearly include 1.35 at the time of writing."
echo "Treat any install here as unsupported staging with rollback ready."

