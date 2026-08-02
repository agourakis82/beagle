#!/usr/bin/env bash
set -euo pipefail

failures=0
warnings=0

SCRIPT_PATH="${BASH_SOURCE[0]}"
if command -v readlink >/dev/null 2>&1; then
  SCRIPT_PATH="$(readlink -f "${SCRIPT_PATH}")"
fi
SCRIPT_DIR="$(cd -- "$(dirname -- "${SCRIPT_PATH}")" && pwd)"
ROOT_DIR="$(cd -- "${SCRIPT_DIR}/../.." && pwd)"
DRA_DIR="${ROOT_DIR}/dra"

die() {
  echo "dra-canary-doctor: $*" >&2
  exit 1
}

kctl() {
  if kubectl config current-context >/dev/null 2>&1; then
    kubectl "$@"
  elif sudo -n kubectl --kubeconfig=/etc/kubernetes/admin.conf config current-context >/dev/null 2>&1; then
    sudo -n kubectl --kubeconfig=/etc/kubernetes/admin.conf "$@"
  else
    die "unable to find a working kubectl context"
  fi
}

section() {
  echo
  echo "== $1 =="
}

pass() {
  echo "PASS: $1"
}

warn() {
  echo "WARN: $1"
  warnings=$((warnings + 1))
}

fail() {
  echo "FAIL: $1"
  failures=$((failures + 1))
}

count_resource() {
  local resource="$1"
  kctl get "${resource}" -A --no-headers 2>/dev/null | sed '/^[[:space:]]*$/d' | wc -l | tr -d ' '
}

count_cluster_resource() {
  local resource="$1"
  kctl get "${resource}" --no-headers 2>/dev/null | sed '/^[[:space:]]*$/d' | wc -l | tr -d ' '
}

echo "Darwin/Sounio DRA canary doctor"
echo
echo "This script is read-only. It checks DRA readiness without allocating GPUs."

section "API"
for resource in deviceclasses.resource.k8s.io resourceclaims.resource.k8s.io resourceclaimtemplates.resource.k8s.io resourceslices.resource.k8s.io; do
  if kctl api-resources --api-group="${resource#*.}" 2>/dev/null | awk '{print $1}' | grep -qx "${resource%%.*}"; then
    pass "${resource} API exists"
  elif kctl get "${resource}" --ignore-not-found >/dev/null 2>&1; then
    pass "${resource} API exists"
  else
    fail "${resource} API is missing"
  fi
done

section "Canary Manifests"
for manifest in deviceclasses.example.yaml resourceclaimtemplates.example.yaml pod-dra-gpu-canary.example.yaml; do
  path="${DRA_DIR}/${manifest}"
  if [[ ! -f "${path}" ]]; then
    fail "${manifest} is missing"
    continue
  fi
  if kctl apply --dry-run=server -f "${path}" >/dev/null 2>&1; then
    pass "${manifest} passes server dry-run"
  else
    fail "${manifest} fails server dry-run"
  fi
done

section "Live DRA State"
deviceclasses="$(count_cluster_resource deviceclasses.resource.k8s.io)"
resourceslices="$(count_cluster_resource resourceslices.resource.k8s.io)"
resourceclaims="$(count_resource resourceclaims.resource.k8s.io)"
claimtemplates="$(count_resource resourceclaimtemplates.resource.k8s.io)"

if kctl get deviceclasses.resource.k8s.io sounio-gpu >/dev/null 2>&1; then
  pass "DeviceClass/sounio-gpu exists"
else
  warn "DeviceClass/sounio-gpu is staged but not applied"
fi

if [[ "${resourceslices}" -gt 0 ]]; then
  pass "DRA ResourceSlice objects exist (${resourceslices})"
else
  warn "No DRA ResourceSlice objects exist; no DRA driver is publishing allocatable devices"
fi

echo "Observed DRA objects: DeviceClass=${deviceclasses}, ResourceSlice=${resourceslices}, ResourceClaimTemplate=${claimtemplates}, ResourceClaim=${resourceclaims}"

echo
if (( failures > 0 )); then
  echo "DRA canary verdict: FAIL (${failures} failure(s), ${warnings} warning(s))"
  exit 1
fi

if (( warnings > 0 )); then
  echo "DRA canary verdict: STAGED (${warnings} warning(s))"
  exit 0
fi

echo "DRA canary verdict: LIVE"
