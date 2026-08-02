#!/usr/bin/env bash
set -euo pipefail

failures=0
warnings=0

die() {
  echo "kueue-topology-doctor: $*" >&2
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

resource_count() {
  local resource="$1"
  kctl get "${resource}" --no-headers 2>/dev/null | sed '/^[[:space:]]*$/d' | wc -l | tr -d ' '
}

namespaced_resource_count() {
  local resource="$1"
  kctl get "${resource}" -A --no-headers 2>/dev/null | sed '/^[[:space:]]*$/d' | wc -l | tr -d ' '
}

echo "Darwin/Sounio Kueue topology doctor"
echo
echo "This script is read-only."
echo "It checks whether Kubernetes batch scheduling has moved beyond a flat GPU queue."

section "Kueue Core"
if kctl get crd clusterqueues.kueue.x-k8s.io >/dev/null 2>&1; then
  pass "Kueue CRDs are installed"
else
  fail "Kueue CRDs are missing"
fi

if kctl get clusterqueues.kueue.x-k8s.io sounio-hpc >/dev/null 2>&1; then
  pass "ClusterQueue/sounio-hpc exists"
else
  fail "ClusterQueue/sounio-hpc is missing"
fi

if kctl -n beagle get localqueues.kueue.x-k8s.io hpc-batch >/dev/null 2>&1; then
  pass "LocalQueue/beagle/hpc-batch exists"
else
  warn "LocalQueue/beagle/hpc-batch is missing"
fi

if kctl -n beagle get localqueues.kueue.x-k8s.io hpc-training >/dev/null 2>&1; then
  pass "LocalQueue/beagle/hpc-training exists"
else
  warn "LocalQueue/beagle/hpc-training is missing"
fi

section "Resource Flavors"
flavors="$(resource_count resourceflavors.kueue.x-k8s.io)"
if [[ "${flavors}" -ge 3 ]]; then
  pass "ResourceFlavors exist (${flavors})"
else
  fail "ResourceFlavors are incomplete (${flavors})"
fi

for flavor in gpu-l4 gpu-rtx-a5000 gpu-rtx-4000-ada; do
  if kctl get resourceflavors.kueue.x-k8s.io "${flavor}" >/dev/null 2>&1; then
    pass "ResourceFlavor/${flavor} exists"
  else
    fail "ResourceFlavor/${flavor} is missing"
  fi
done

section "Topology And Admission"
topologies="$(resource_count topologies.kueue.x-k8s.io)"
admission_checks="$(resource_count admissionchecks.kueue.x-k8s.io)"
priorities="$(resource_count workloadpriorityclasses.kueue.x-k8s.io)"
workloads="$(namespaced_resource_count workloads.kueue.x-k8s.io)"
timer_unit="darwin-fabric-storage-admission-reconcile.timer"
reconciler_script="/home/devsounio/beagle/k8s/hpc-sota/ops/scheduler-readiness/fabric-storage-admission-reconcile.sh"
attachment_manifest="/home/devsounio/beagle/k8s/hpc-sota/kueue/clusterqueue.with-admissioncheck.example.yaml"
clusterqueue_admission_checks="$(
  kctl get clusterqueues.kueue.x-k8s.io sounio-hpc \
    -o jsonpath='{range .spec.admissionChecksStrategy.admissionChecks[*]}{.name}{"\n"}{end}' \
    2>/dev/null || true
)"

if [[ "${topologies}" -gt 0 ]]; then
  pass "Kueue Topology objects exist (${topologies})"
else
  warn "No Kueue Topology objects exist; GPU locality is not modeled"
fi

for flavor in gpu-any gpu-l4 gpu-rtx-a5000 gpu-rtx-4000-ada; do
  topology_name="$(kctl get resourceflavors.kueue.x-k8s.io "${flavor}" -o jsonpath='{.spec.topologyName}' 2>/dev/null || true)"
  if [[ "${topology_name}" == "gpu-fabric-10-210" ]]; then
    pass "ResourceFlavor/${flavor} uses Topology/gpu-fabric-10-210"
  else
    warn "ResourceFlavor/${flavor} is not bound to Topology/gpu-fabric-10-210"
  fi
done

if [[ "${admission_checks}" -gt 0 ]]; then
  pass "Kueue AdmissionChecks exist (${admission_checks})"
else
  warn "No Kueue AdmissionChecks exist; fabric/storage readiness is not enforced by Kueue"
fi

if printf '%s\n' "${clusterqueue_admission_checks}" | grep -qx 'fabric-storage-readiness'; then
  pass "ClusterQueue/sounio-hpc references AdmissionCheck/fabric-storage-readiness"
else
  warn "ClusterQueue/sounio-hpc does not enforce AdmissionCheck/fabric-storage-readiness"
fi

if [[ "${priorities}" -gt 0 ]]; then
  pass "Kueue WorkloadPriorityClasses exist (${priorities})"
else
  warn "No Kueue WorkloadPriorityClasses exist; batch priority policy is still implicit"
fi

echo "Observed Kueue workloads: ${workloads}"

section "Fabric/Storage Reconciler"
if [[ -x "${reconciler_script}" ]]; then
  pass "fabric-storage AdmissionCheck reconciler script exists"
else
  fail "fabric-storage AdmissionCheck reconciler script is missing or not executable"
fi

if [[ -f "${attachment_manifest}" ]]; then
  pass "staged ClusterQueue AdmissionCheck attachment manifest exists"
else
  warn "staged ClusterQueue AdmissionCheck attachment manifest is missing"
fi

if command -v systemctl >/dev/null 2>&1 && systemctl list-unit-files "${timer_unit}" >/dev/null 2>&1; then
  timer_enabled="$(systemctl is-enabled "${timer_unit}" 2>/dev/null || true)"
  timer_active="$(systemctl is-active "${timer_unit}" 2>/dev/null || true)"
  if [[ "${timer_enabled}" == "enabled" && "${timer_active}" == "active" ]]; then
    pass "${timer_unit} is enabled and active"
  elif printf '%s\n' "${clusterqueue_admission_checks}" | grep -qx 'fabric-storage-readiness'; then
    fail "ClusterQueue enforces fabric-storage-readiness but ${timer_unit} is not active"
  else
    warn "${timer_unit} is installed but not enabled; safe until ClusterQueue attachment"
  fi
else
  warn "${timer_unit} is not installed on this host"
fi

section "Current Queue Shape"
kctl get clusterqueues.kueue.x-k8s.io sounio-hpc -o yaml 2>/dev/null |
  sed -n '/^spec:/,/^status:/p' |
  sed -n '1,120p' || true

echo
if (( failures > 0 )); then
  echo "Kueue topology verdict: FAIL (${failures} failure(s), ${warnings} warning(s))"
  exit 1
fi

if (( warnings > 0 )); then
  echo "Kueue topology verdict: FLAT BUT OPERATIONAL (${warnings} SOTA gap warning(s))"
  exit 0
fi

echo "Kueue topology verdict: SOTA SCHEDULER GATE GREEN"
