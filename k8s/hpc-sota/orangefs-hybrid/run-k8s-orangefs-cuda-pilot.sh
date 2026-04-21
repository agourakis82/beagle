#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
KUBECONFIG_PATH="${KUBECONFIG_PATH:-/etc/kubernetes/admin.conf}"
NAMESPACE="${NAMESPACE:-beagle}"
JOB_NAME="${JOB_NAME:-orangefs-cuda-pilot}"
MANIFEST="${MANIFEST:-$ROOT/k8s/job-orangefs-cuda-pilot.yaml}"
WAIT_TIMEOUT="${WAIT_TIMEOUT:-240s}"

export KUBECONFIG="$KUBECONFIG_PATH"

kubectl -n "$NAMESPACE" delete job "$JOB_NAME" --ignore-not-found=true >/dev/null 2>&1 || true
kubectl -n "$NAMESPACE" apply -f "$MANIFEST" >/dev/null
kubectl -n "$NAMESPACE" wait --for=condition=complete --timeout="$WAIT_TIMEOUT" "job/$JOB_NAME"

pod="$(kubectl -n "$NAMESPACE" get pod -l app.kubernetes.io/name="$JOB_NAME" -o jsonpath='{.items[0].metadata.name}')"
echo "job=$JOB_NAME"
echo "pod=$pod"
kubectl -n "$NAMESPACE" logs "$pod" --tail=200
