#!/usr/bin/env bash
set -euo pipefail

version="${JOBSET_VERSION:-v0.11.1}"
manifest_url="https://github.com/kubernetes-sigs/jobset/releases/download/${version}/manifests.yaml"

if kubectl config current-context >/dev/null 2>&1; then
  k() { kubectl "$@"; }
elif sudo kubectl config current-context >/dev/null 2>&1; then
  k() { sudo kubectl "$@"; }
else
  echo "unable to find a working kubectl context via kubectl or sudo kubectl" >&2
  exit 1
fi

echo "== installing JobSet ${version} =="
k apply --server-side -f "${manifest_url}"
k -n jobset-system rollout status deploy/jobset-controller-manager --timeout=180s
k get pods -n jobset-system -o wide

