#!/usr/bin/env bash
set -euo pipefail

if kubectl config current-context >/dev/null 2>&1; then
  k() { kubectl "$@"; }
elif sudo kubectl config current-context >/dev/null 2>&1; then
  k() { sudo kubectl "$@"; }
else
  echo "unable to find a working kubectl context via kubectl or sudo kubectl" >&2
  exit 1
fi

k get crd network-attachment-definitions.k8s.cni.cncf.io
echo "---"
k -n kube-system get ds kube-multus-ds whereabouts rdma-shared-dp-ds -o wide
echo "---"
k get node -o jsonpath='{range .items[*]}{.metadata.name}{": allocatable rdma/sounio_gpu_fabric="}{.status.allocatable.rdma\.sounio_gpu_fabric}{"\n"}{end}'
