#!/usr/bin/env bash
set -euo pipefail

if kubectl --kubeconfig /etc/kubernetes/admin.conf get ns >/dev/null 2>&1; then
  k() { kubectl --kubeconfig /etc/kubernetes/admin.conf "$@"; }
elif sudo kubectl --kubeconfig /etc/kubernetes/admin.conf get ns >/dev/null 2>&1; then
  k() { sudo kubectl --kubeconfig /etc/kubernetes/admin.conf "$@"; }
else
  echo "unable to find a working admin kubeconfig" >&2
  exit 1
fi

k get pv | egrep 'local-nvme-r740|local-zfast-t560' || true
echo ---
k -n beagle get pvc | egrep 'local-nvme-r740|local-data' || true
echo ---
k -n beagle get pod | egrep 'local-nvme-r740-canary|local-zfast-t560-canary|beagle-workspace|sounio-workspace|beagle-core' || true
