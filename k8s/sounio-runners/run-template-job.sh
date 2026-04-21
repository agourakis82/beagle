#!/usr/bin/env bash
set -euo pipefail

if [[ $# -lt 1 || $# -gt 2 ]]; then
  echo "usage: $0 <cpu|cpu-standard|gpu> [job-name]" >&2
  exit 1
fi

kind="$1"
namespace="${NAMESPACE:-beagle}"
root="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if kubectl config current-context >/dev/null 2>&1; then
  k() { kubectl "$@"; }
elif sudo kubectl config current-context >/dev/null 2>&1; then
  k() { sudo kubectl "$@"; }
else
  echo "unable to find a working kubectl context via kubectl or sudo kubectl" >&2
  exit 1
fi

case "$kind" in
  cpu)
    template="$root/cpu-batch-job.yaml"
    default_prefix="sounio-cpu-batch"
    ;;
  cpu-standard)
    template="$root/cpu-standard-job.yaml"
    default_prefix="sounio-cpu-standard"
    ;;
  gpu)
    template="$root/gpu-batch-job.yaml"
    default_prefix="sounio-gpu-batch"
    ;;
  *)
    echo "unknown job kind: $kind" >&2
    exit 1
    ;;
esac

job_name="${2:-${default_prefix}-$(date +%Y%m%d%H%M%S)}"

sed \
  -e "s/name: ${default_prefix}-template/name: ${job_name}/" \
  -e "s/suspend: true/suspend: false/" \
  "$template" \
  | k -n "$namespace" apply -f - >/dev/null

echo "$job_name"
