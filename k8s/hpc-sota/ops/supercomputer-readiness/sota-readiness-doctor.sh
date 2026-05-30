#!/usr/bin/env bash
set -euo pipefail

SCRIPT_PATH="${BASH_SOURCE[0]}"
if command -v readlink >/dev/null 2>&1; then
  SCRIPT_PATH="$(readlink -f "${SCRIPT_PATH}")"
fi
SCRIPT_DIR="$(cd -- "$(dirname -- "${SCRIPT_PATH}")" && pwd)"
OPS_DIR="$(cd -- "${SCRIPT_DIR}/.." && pwd)"
ROOT_DIR="$(cd -- "${OPS_DIR}/.." && pwd)"

# shellcheck source=../lab-ops.sh
source "${OPS_DIR}/lab-ops.sh"

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

have_local_control_plane() {
  command -v kubectl >/dev/null 2>&1 &&
    command -v sudo >/dev/null 2>&1 &&
    sudo -n env KUBECONFIG=/etc/kubernetes/admin.conf kubectl get nodes >/dev/null 2>&1
}

kctl() {
  if have_local_control_plane; then
    sudo -n env KUBECONFIG=/etc/kubernetes/admin.conf kubectl "$@"
  else
    lab_kctl "$@"
  fi
}

login_pod() {
  kctl -n slurm-pilot get pod -o jsonpath='{range .items[*]}{.metadata.name}{"\n"}{end}' |
    awk '/^slurm-pilot-login-/{print; exit}'
}

slurm_exec() {
  local pod
  pod="$(login_pod)"
  if [[ -z "${pod}" ]]; then
    return 1
  fi
  kctl -n slurm-pilot exec "${pod}" -- "$@"
}

resource_count() {
  local resource="$1"
  kctl get "${resource}" -A --no-headers 2>/dev/null | sed '/^[[:space:]]*$/d' | wc -l | tr -d ' '
}

cluster_resource_count() {
  local resource="$1"
  kctl get "${resource}" --no-headers 2>/dev/null | sed '/^[[:space:]]*$/d' | wc -l | tr -d ' '
}

echo "Darwin/Sounio supercomputer readiness doctor"
echo
echo "This script is read-only."
echo "It distinguishes live operational health from SOTA gaps."

section "Control Plane"
if kctl version --client >/dev/null 2>&1 && kctl get nodes >/dev/null 2>&1; then
  pass "Kubernetes API is reachable"
else
  fail "Kubernetes API is not reachable"
fi

ready_nodes="$(kctl get nodes --no-headers 2>/dev/null | awk '$2 == "Ready" {count++} END {print count + 0}')"
total_nodes="$(kctl get nodes --no-headers 2>/dev/null | awk 'END {print NR + 0}')"
if [[ "${total_nodes}" -gt 0 && "${ready_nodes}" -eq "${total_nodes}" ]]; then
  pass "Kubernetes nodes Ready (${ready_nodes}/${total_nodes})"
else
  fail "Kubernetes nodes are not all Ready (${ready_nodes}/${total_nodes})"
fi

section "Scheduler Lanes"
if slurm_exec scontrol ping >/dev/null 2>&1; then
  pass "Slurm controller responds"
else
  fail "Slurm controller does not respond"
fi

if slurm_exec sinfo -h -p gpu-orangefs >/dev/null 2>&1; then
  pass "Slurm gpu-orangefs partition is visible"
else
  fail "Slurm gpu-orangefs partition is not visible"
fi

if kctl get clusterqueue.kueue.x-k8s.io sounio-hpc >/dev/null 2>&1; then
  pass "Kueue ClusterQueue/sounio-hpc exists"
else
  warn "Kueue ClusterQueue/sounio-hpc is missing"
fi

section "GPU Authority"
if "${OPS_DIR}/gpu-lease" status >/dev/null 2>&1; then
  pass "gpu-lease status succeeds"
else
  fail "gpu-lease status failed"
fi

gpu_workers="$(kctl get nodes -l sounio.dev/slurm-worker-gpuorangefs=true --no-headers 2>/dev/null | wc -l | tr -d ' ')"
if [[ "${gpu_workers}" -ge 1 ]]; then
  pass "Slurm gpuorangefs admitted workers exist (${gpu_workers})"
else
  warn "No nodes are admitted as Slurm gpuorangefs workers"
fi

gpu_flavors="$(cluster_resource_count resourceflavors.kueue.x-k8s.io)"
if [[ "${gpu_flavors}" -ge 3 ]]; then
  pass "Kueue ResourceFlavors are present (${gpu_flavors})"
else
  warn "Kueue ResourceFlavors look incomplete (${gpu_flavors})"
fi

section "DRA And Topology"
deviceclasses="$(cluster_resource_count deviceclasses.resource.k8s.io)"
resourceslices="$(cluster_resource_count resourceslices.resource.k8s.io)"
resourceclaims="$(resource_count resourceclaims.resource.k8s.io)"
if [[ "${deviceclasses}" -gt 0 || "${resourceslices}" -gt 0 || "${resourceclaims}" -gt 0 ]]; then
  pass "Kubernetes DRA objects exist (DeviceClass=${deviceclasses}, ResourceSlice=${resourceslices}, ResourceClaim=${resourceclaims})"
else
  warn "Kubernetes DRA API exists but no DRA objects are currently in use"
fi

if "${ROOT_DIR}/ops/scheduler-readiness/dra-canary-doctor.sh" >/dev/null 2>&1; then
  pass "DRA canary lane is staged and schema-valid"
else
  warn "DRA canary lane is missing or invalid"
fi

kueue_topologies="$(cluster_resource_count topologies.kueue.x-k8s.io)"
admission_checks="$(cluster_resource_count admissionchecks.kueue.x-k8s.io)"
priority_classes="$(cluster_resource_count workloadpriorityclasses.kueue.x-k8s.io)"
if [[ "${kueue_topologies}" -gt 0 || "${admission_checks}" -gt 0 || "${priority_classes}" -gt 0 ]]; then
  pass "Kueue advanced admission objects exist (Topology=${kueue_topologies}, AdmissionCheck=${admission_checks}, WorkloadPriorityClass=${priority_classes})"
else
  warn "Kueue is installed but topology/admission/priority objects are not active"
fi

if "${ROOT_DIR}/ops/scheduler-readiness/kueue-topology-doctor.sh" >/dev/null 2>&1; then
  pass "Kueue topology doctor passes"
else
  warn "Kueue topology doctor reports flat scheduling gaps"
fi

section "Fabric And Storage"
rdma_pods="$(kctl get pods -A --no-headers 2>/dev/null | awk 'tolower($2) ~ /rdma|network-operator|multus/ && $4 == "Running" {count++} END {print count + 0}')"
if [[ "${rdma_pods}" -gt 0 ]]; then
  pass "RDMA/Multus/NVIDIA network substrate pods are running (${rdma_pods})"
else
  warn "RDMA/Multus/NVIDIA network substrate pods were not observed"
fi

if "${SCRIPT_DIR}/gpu-fabric-gate.sh" phase3-preflight >/dev/null 2>&1; then
  pass "GPU fabric 10.210 Kubernetes-side preflight passes"
else
  warn "GPU fabric 10.210 Kubernetes-side preflight does not pass"
fi

external_preflight_output="$("${SCRIPT_DIR}/gpu-fabric-gate.sh" phase3-external-preflight 2>&1 || true)"
if grep -q '^10\.210 external preflight: PASS$' <<<"${external_preflight_output}"; then
  pass "GPU fabric 10.210 external host-to-host jumbo preflight passes"
  pass "GPU fabric 10.210 gateway/SVI 10.210.0.254 is proven"
elif grep -q '^10\.210 external preflight: PASS WITH WARNINGS' <<<"${external_preflight_output}"; then
  pass "GPU fabric 10.210 external host-to-host jumbo preflight passes"
  warn "GPU fabric 10.210 gateway/SVI 10.210.0.254 is not yet proven"
else
  warn "GPU fabric 10.210 external host-to-host jumbo preflight does not pass"
fi

orangefs_mount="/var/lib/orangefs-lab/client-runtime/mnt"
if findmnt -T "${orangefs_mount}" -n -o FSTYPE 2>/dev/null | grep -qx 'pvfs2'; then
  pass "OrangeFS client mount exists on ${orangefs_mount}"
  orangefs_size_gb="$(df -BG --output=size "${orangefs_mount}" 2>/dev/null | tail -n1 | tr -dc '0-9')"
  if [[ -n "${orangefs_size_gb}" && "${orangefs_size_gb}" -ge 2000 ]]; then
    pass "OrangeFS visible capacity is multi-terabyte (${orangefs_size_gb}G)"
  else
    warn "OrangeFS visible capacity is below multi-terabyte SOTA target (${orangefs_size_gb:-unknown}G)"
    if [[ -x "${SCRIPT_DIR}/orangefs-growth-gate.sh" ]]; then
      pass "OrangeFS growth gate exists for safe multi-terabyte promotion"
    else
      warn "OrangeFS growth gate is missing"
    fi
  fi
else
  warn "OrangeFS client mount was not found on this machine"
fi

section "Expansion Readiness"
if [[ -f "${ROOT_DIR}/DL380_ONBOARDING.md" ]]; then
  pass "DL380 onboarding runbook exists"
else
  warn "DL380 onboarding runbook is missing"
fi

if rg -q 'dl380-proxmox|DL380' /home/devsounio/beagle/k8s/sounio-networking/service-fabric-10g/netbox/seed-lab-devices-orm.py 2>/dev/null; then
  pass "DL380 appears in NetBox seed"
else
  warn "DL380 is not yet represented in NetBox seed"
fi

echo
if (( failures > 0 )); then
  echo "Doctor verdict: ATTENTION (${failures} failure(s), ${warnings} SOTA gap warning(s))"
  exit 1
fi

if (( warnings > 0 )); then
  echo "Doctor verdict: OPERATIONAL WITH SOTA GAPS (${warnings})"
  exit 0
fi

echo "Doctor verdict: SOTA READINESS GREEN"
