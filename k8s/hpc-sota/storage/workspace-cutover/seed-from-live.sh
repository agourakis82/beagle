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

backup_root="/zfast/workspaces/live"

mkdir -p \
  "$backup_root/beagle-core" \
  "$backup_root/beagle-workspace" \
  "$backup_root/sounio-workspace"

tmpdir="$(mktemp -d)"
trap 'rm -rf "$tmpdir"' EXIT

echo "syncing beagle-core -> $backup_root/beagle-core"
k -n beagle exec deploy/beagle-core -- tar cf - -C /var/lib/beagle . | tar xf - -C "$backup_root/beagle-core"

echo "syncing beagle-workspace -> $backup_root/beagle-workspace"
k -n beagle exec beagle-workspace-0 -- tar cf - -C /workspace . | tar xf - -C "$backup_root/beagle-workspace"

echo "syncing sounio-workspace -> $backup_root/sounio-workspace"
k -n beagle exec sounio-workspace-habitat-0 -- tar cf - -C /workspace . | tar xf - -C "$backup_root/sounio-workspace"

chown -R 1000:1000 \
  "$backup_root/beagle-workspace" \
  "$backup_root/sounio-workspace"

du -sh \
  "$backup_root/beagle-core" \
  "$backup_root/beagle-workspace" \
  "$backup_root/sounio-workspace"
