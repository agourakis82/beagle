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

root="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

case "${1:-}" in
  apply-storage)
    k apply -f "$root/storageclass-local-zfast-t560.yaml"
    k apply -f "$root/pv-local-zfast-t560-beagle-core.yaml"
    k apply -f "$root/pv-local-zfast-t560-beagle-workspace.yaml"
    k apply -f "$root/pv-local-zfast-t560-sounio-workspace.yaml"
    k apply -f "$root/pvc-local-zfast-t560-beagle-core.yaml"
    k apply -f "$root/pvc-local-zfast-t560-beagle-workspace.yaml"
    k apply -f "$root/pvc-local-zfast-t560-sounio-workspace.yaml"
    ;;
  canary-storage)
    k -n beagle delete pod local-zfast-t560-canary --ignore-not-found
    k apply -f "$root/pod-local-zfast-t560-canary.yaml"
    k -n beagle wait --for=condition=Ready --timeout=10m pod/local-zfast-t560-canary
    k -n beagle logs local-zfast-t560-canary
    ;;
  quiesce-old)
    k -n beagle scale statefulset beagle-workspace --replicas=0
    k -n beagle scale statefulset sounio-workspace-habitat --replicas=0
    k -n beagle scale deployment beagle-core --replicas=0
    ;;
  apply-local)
    k apply -f "$root/deployment-beagle-workspace-local.yaml"
    k apply -f "$root/deployment-sounio-workspace-local.yaml"
    k -n beagle patch deployment beagle-core --type=merge --patch-file "$root/deployment-beagle-core-local-patch.yaml"
    k -n beagle rollout status deployment/beagle-core --timeout=30m
    k -n beagle rollout status deployment/beagle-workspace-local --timeout=30m
    k -n beagle rollout status deployment/sounio-workspace-local --timeout=30m
    ;;
  cleanup-ephemeral)
    k -n beagle delete pod \
      local-zfast-t560-canary \
      local-nvme-r740-canary \
      workspace-post-cutover-reconcile \
      workspace-post-cutover-verify \
      workspace-post-cutover-diff \
      --ignore-not-found=true --wait=true
    ;;
  switch-services)
    k -n beagle patch svc beagle-workspace --type=merge -p '{"spec":{"selector":{"app.kubernetes.io/name":"beagle-workspace-local"}}}'
    k -n beagle patch svc beagle-workspace-internal --type=merge -p '{"spec":{"selector":{"app.kubernetes.io/name":"beagle-workspace-local"}}}'
    k -n beagle patch svc sounio-workspace --type=merge -p '{"spec":{"selector":{"app.kubernetes.io/name":"sounio-workspace-local"}}}'
    k -n beagle patch svc sounio-workspace-habitat --type=merge -p '{"spec":{"selector":{"app.kubernetes.io/name":"sounio-workspace-local"}}}'
    k -n beagle patch svc sounio-workspace-habitat-internal --type=merge -p '{"spec":{"selector":{"app.kubernetes.io/name":"sounio-workspace-local"}}}'
    ;;
  rollback-services)
    k -n beagle patch svc beagle-workspace --type=merge -p '{"spec":{"selector":{"app.kubernetes.io/name":"beagle-workspace"}}}'
    k -n beagle patch svc beagle-workspace-internal --type=merge -p '{"spec":{"selector":{"app.kubernetes.io/name":"beagle-workspace"}}}'
    k -n beagle patch svc sounio-workspace --type=merge -p '{"spec":{"selector":{"app.kubernetes.io/name":"sounio-workspace-habitat"}}}'
    k -n beagle patch svc sounio-workspace-habitat --type=merge -p '{"spec":{"selector":{"app.kubernetes.io/name":"sounio-workspace-habitat"}}}'
    k -n beagle patch svc sounio-workspace-habitat-internal --type=merge -p '{"spec":{"selector":{"app.kubernetes.io/name":"sounio-workspace-habitat"}}}'
    ;;
  *)
    echo "usage: cutover.sh <apply-storage|canary-storage|quiesce-old|apply-local|cleanup-ephemeral|switch-services|rollback-services>" >&2
    exit 1
    ;;
esac
