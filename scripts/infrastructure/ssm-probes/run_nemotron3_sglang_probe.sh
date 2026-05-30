#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
namespace="${KUBE_NAMESPACE:-beagle}"
baseline_deploy="${SSM_BASELINE_DEPLOYMENT:-ssm-probe-serving}"
probe_name="${SSM_NEMOTRON3_PROBE_NAME:-ssm-nemotron3-sglang-probe}"
probe_manifest="${SSM_NEMOTRON3_PROBE_MANIFEST:-${repo_root}/k8s/project-cockpit/profiles/ssm-nemotron3-sglang-probe.yaml}"
probe_endpoint="${SSM_NEMOTRON3_PROBE_ENDPOINT:-http://ssm-nemotron3-sglang-probe.beagle.svc.cluster.local:8006}"
run_id="${SSM_PROBE_RUN_ID:-nemotron3-sglang-$(date -u +%Y%m%dT%H%M%SZ)}"
served_model="${SSM_NEMOTRON3_SERVED_MODEL:-nemotron3-nano-4b-fp8-sglang}"
keep_probe="${KEEP_SSM_NEMOTRON3_PROBE:-0}"
restore_baseline="${RESTORE_SSM_BASELINE:-1}"

wait_probe_models() {
  local i
  for i in $(seq 1 60); do
    if kubectl -n "${namespace}" exec deploy/project-cockpit -- \
      curl -fsS "${probe_endpoint}/v1/models" >/tmp/sounio-nemotron3-models.json 2>/dev/null; then
      cat /tmp/sounio-nemotron3-models.json
      return 0
    fi
    sleep 2
  done
  kubectl -n "${namespace}" get endpoints "${probe_name}" -o wide || true
  return 1
}

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

echo "[nemotron3-sglang] baseline -> scale down ${baseline_deploy}"
kubectl -n "${namespace}" scale deploy/"${baseline_deploy}" --replicas=0
kubectl -n "${namespace}" rollout status deploy/"${baseline_deploy}" --timeout=300s

echo "[nemotron3-sglang] apply probe ${probe_name}"
kubectl apply -f "${probe_manifest}"
kubectl -n "${namespace}" rollout status deploy/"${probe_name}" --timeout=2400s

echo "[nemotron3-sglang] gpu"
kubectl -n "${namespace}" exec deploy/"${probe_name}" -- \
  sh -lc 'nvidia-smi --query-gpu=name,memory.used,memory.free,memory.total,utilization.gpu --format=csv,noheader'

echo "[nemotron3-sglang] models"
wait_probe_models
echo

echo "[nemotron3-sglang] matrix run_id=${run_id}"
SSM_PROBE_ENDPOINT="${probe_endpoint}" \
SSM_PROBE_RUN_ID="${run_id}" \
SSM_PROBE_MODEL="${served_model}" \
  "${repo_root}/scripts/infrastructure/run_ssm_probe_matrix.sh"

echo "[nemotron3-sglang] completed"
