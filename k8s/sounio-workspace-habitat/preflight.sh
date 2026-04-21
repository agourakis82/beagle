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

echo "== habitat preflight =="
echo "context: $(k config current-context)"
echo

echo "== stable service =="
k -n beagle get svc sounio-workspace
echo

echo "== current workspace pvc and habitat pvc =="
k -n beagle get pvc sounio-workspace-data
k -n beagle get pvc workspace-data-sounio-workspace-habitat-0 2>/dev/null || \
  echo "habitat pvc workspace-data-sounio-workspace-habitat-0 not created yet"
echo

echo "== habitat resources =="
k get storageclass ceph-rbd-ssd-rwop 2>/dev/null || echo "storageclass ceph-rbd-ssd-rwop not created yet"
k -n beagle get svc sounio-workspace-habitat sounio-workspace-habitat-internal 2>/dev/null || \
  echo "habitat services not created yet"
k -n beagle get statefulset sounio-workspace-habitat 2>/dev/null || \
  echo "habitat statefulset not created yet"
echo

echo "== live workspace pods =="
k -n beagle get pods -l app.kubernetes.io/name=sounio-workspace-habitat -o wide
echo

echo "== legacy deployment (optional) =="
k -n beagle get deploy sounio-workspace 2>/dev/null || \
  echo "legacy deployment sounio-workspace not present"
echo

echo "preflight complete"
