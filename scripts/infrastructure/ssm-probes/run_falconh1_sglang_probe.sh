#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
namespace="${KUBE_NAMESPACE:-beagle}"
baseline_deploy="${SSM_BASELINE_DEPLOYMENT:-ssm-probe-serving}"
probe_name="${SSM_FALCONH1_PROBE_NAME:-ssm-falconh1-sglang-probe}"
probe_manifest="${SSM_FALCONH1_PROBE_MANIFEST:-${repo_root}/k8s/project-cockpit/profiles/ssm-falconh1-sglang-probe.yaml}"
probe_endpoint="${SSM_FALCONH1_PROBE_ENDPOINT:-http://ssm-falconh1-sglang-probe.beagle.svc.cluster.local:8004}"
run_id="${SSM_PROBE_RUN_ID:-falconh1-sglang-$(date -u +%Y%m%dT%H%M%SZ)}"
keep_probe="${KEEP_SSM_FALCONH1_PROBE:-0}"
restore_baseline="${RESTORE_SSM_BASELINE:-1}"

restore() {
  local rc=$?
  if [[ "${keep_probe}" != "1" ]]; then
    kubectl -n "${namespace}" delete -f "${probe_manifest}" --ignore-not-found=true >/dev/null 2>&1 || true
  fi
  if [[ "${restore_baseline}" == "1" ]]; then
    kubectl -n "${namespace}" scale deploy/"${baseline_deploy}" --replicas=1 >/dev/null 2>&1 || true
    kubectl -n "${namespace}" rollout status deploy/"${baseline_deploy}" --timeout=900s >/dev/null 2>&1 || true
  fi
  return "${rc}"
}
trap restore EXIT

echo "[falconh1-sglang] baseline -> scale down ${baseline_deploy}"
kubectl -n "${namespace}" scale deploy/"${baseline_deploy}" --replicas=0
kubectl -n "${namespace}" rollout status deploy/"${baseline_deploy}" --timeout=300s

echo "[falconh1-sglang] apply probe ${probe_name}"
kubectl apply -f "${probe_manifest}"
kubectl -n "${namespace}" rollout status deploy/"${probe_name}" --timeout=1800s

echo "[falconh1-sglang] gpu"
kubectl -n "${namespace}" exec deploy/"${probe_name}" -- \
  sh -lc 'nvidia-smi --query-gpu=name,memory.used,memory.free,memory.total,utilization.gpu --format=csv,noheader'

echo "[falconh1-sglang] models"
kubectl -n "${namespace}" exec deploy/project-cockpit -- \
  curl -fsS "${probe_endpoint}/v1/models"
echo

echo "[falconh1-sglang] matrix run_id=${run_id}"
SSM_PROBE_ENDPOINT="${probe_endpoint}" \
SSM_PROBE_RUN_ID="${run_id}" \
SSM_PROBE_MODEL="falcon-h1-7b-instruct-sglang" \
  "${repo_root}/scripts/infrastructure/run_ssm_probe_matrix.sh"

echo "[falconh1-sglang] completed"
