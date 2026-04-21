#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=./lab-ops.sh
source "${SCRIPT_DIR}/lab-ops.sh"

failures=0
warnings=0

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

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || {
    echo "Missing required command: $1" >&2
    exit 2
  }
}

have_local_control_plane() {
  command -v kubectl >/dev/null 2>&1 &&
    command -v sudo >/dev/null 2>&1 &&
    sudo -n env KUBECONFIG=/etc/kubernetes/admin.conf kubectl get nodes >/dev/null 2>&1
}

surface_kctl() {
  if have_local_control_plane; then
    sudo -n env KUBECONFIG=/etc/kubernetes/admin.conf kubectl "$@"
  else
    lab_kctl "$@"
  fi
}

service_endpoints() {
  local namespace="$1"
  local service="$2"
  surface_kctl -n "$namespace" get endpoints "$service" -o jsonpath='{range .subsets[*].addresses[*]}{.ip}{" "}{end}' 2>/dev/null || true
}

check_http_code() {
  local label="$1"
  local url="$2"
  local expected_regex="$3"
  local code

  code="$(curl -kfsS -o /dev/null -w '%{http_code}' --max-time 8 "$url" 2>/dev/null || true)"
  if [[ -n "$code" && "$code" =~ $expected_regex ]]; then
    pass "${label} responds with HTTP ${code}"
  elif [[ -n "$code" ]]; then
    warn "${label} returned unexpected HTTP ${code}"
  else
    warn "${label} did not respond"
  fi
}

require_cmd curl
require_cmd getent

echo "HPC shared surface doctor"
echo
echo "This script is read-only."
echo "It verifies the client-visible and cluster-backed Darwin/Sounio control surfaces."

section "Client-visible surfaces"
api_hosts="$(getent ahostsv4 k8s-api.darwin.lan 2>/dev/null | awk '{print $1}' | sort -u | xargs || true)"
if [[ "${api_hosts}" == *"10.100.100.2"* ]]; then
  pass "k8s-api.darwin.lan resolves to 10.100.100.2 (${api_hosts})"
else
  warn "k8s-api.darwin.lan resolution is unexpected (${api_hosts:-<no output>})"
fi
check_http_code "Kubernetes API readyz" "https://k8s-api.darwin.lan:6443/readyz" '^(200)$'
check_http_code "Grafana tailnet surface" "http://darwin-grafana.tail21cbc4.ts.net" '^(200|302)$'

slurmdbd_hosts="$(getent ahostsv4 slurmdbd-mariadb-ext.darwin.lan 2>/dev/null | awk '{print $1}' | sort -u | xargs || true)"
if [[ -n "${slurmdbd_hosts}" ]]; then
  pass "slurmdbd-mariadb-ext.darwin.lan resolves (${slurmdbd_hosts})"
else
  warn "slurmdbd-mariadb-ext.darwin.lan does not resolve on this machine"
fi

section "Cluster-backed surfaces"
workspace_ready="$(surface_kctl -n beagle get statefulset sounio-workspace-habitat -o jsonpath='{.status.readyReplicas}' 2>/dev/null || true)"
if [[ "${workspace_ready:-0}" -ge 1 ]]; then
  pass "sounio-workspace-habitat has ${workspace_ready} ready replica(s)"
else
  fail "sounio-workspace-habitat has no ready replicas"
fi

workspace_service_endpoints="$(service_endpoints beagle sounio-workspace)"
if [[ -n "${workspace_service_endpoints}" ]]; then
  pass "service/sounio-workspace has endpoints (${workspace_service_endpoints})"
else
  fail "service/sounio-workspace has no endpoints"
fi

grafana_service_endpoints="$(service_endpoints darwin-platform darwin-observability-grafana)"
if [[ -n "${grafana_service_endpoints}" ]]; then
  pass "service/darwin-observability-grafana has endpoints (${grafana_service_endpoints})"
else
  fail "service/darwin-observability-grafana has no endpoints"
fi

slurmdbd_pod_phase="$(surface_kctl -n slurm-pilot get pod slurm-pilot-mariadb-ext-0 -o jsonpath='{.status.phase}' 2>/dev/null || true)"
slurmdbd_pod_ready="$(surface_kctl -n slurm-pilot get pod slurm-pilot-mariadb-ext-0 -o jsonpath='{.status.containerStatuses[0].ready}' 2>/dev/null || true)"
if [[ "${slurmdbd_pod_phase}" == "Running" && "${slurmdbd_pod_ready}" == "true" ]]; then
  pass "slurm-pilot-mariadb-ext-0 is Running and Ready"
else
  warn "slurm-pilot-mariadb-ext-0 is not Running+Ready"
fi

section "Remote ops lane"
if have_local_control_plane; then
  pass "local control-plane access is available; remote ops lane is optional here"
elif lab_preflight >/dev/null 2>&1; then
  pass "remote ops lane to $(lab_ops_host) is healthy"
else
  warn "remote ops lane to $(lab_ops_host) is not healthy"
fi

echo
if (( failures > 0 )); then
  echo "Doctor verdict: ATTENTION (${failures} failure(s), ${warnings} warning(s))"
  exit 1
fi

if (( warnings > 0 )); then
  echo "Doctor verdict: HEALTHY WITH WARNINGS (${warnings})"
  exit 0
fi

echo "Doctor verdict: HEALTHY"
