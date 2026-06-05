#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
namespace="${KUBE_NAMESPACE:-beagle}"
probe_name="${KIMI_LINEAR_Q3_PROBE_NAME:-kimi-linear-q3-llamacpp-probe}"
probe_manifest="${KIMI_LINEAR_Q3_PROBE_MANIFEST:-${repo_root}/k8s/project-cockpit/profiles/kimi-linear-q3-llamacpp-probe.yaml}"
probe_endpoint="${KIMI_LINEAR_Q3_ENDPOINT:-http://kimi-linear-q3-llamacpp-probe.beagle.svc.cluster.local:8007}"
run_id="${SSM_PROBE_RUN_ID:-kimi-linear-q3-llamacpp-$(date -u +%Y%m%dT%H%M%SZ)}"
served_model="${KIMI_LINEAR_Q3_SERVED_MODEL:-kimi-linear-q3-k-s-gguf}"
keep_probe="${KEEP_KIMI_LINEAR_Q3_PROBE:-0}"

cleanup() {
  local rc=$?
  if [[ "${keep_probe}" != "1" ]]; then
    kubectl -n "${namespace}" delete -f "${probe_manifest}" --ignore-not-found=true >/dev/null 2>&1 || true
  fi
  return "${rc}"
}
trap cleanup EXIT

wait_probe_models() {
  local i
  for i in $(seq 1 90); do
    if kubectl -n "${namespace}" exec deploy/project-cockpit -- \
      curl -fsS "${probe_endpoint}/v1/models" >/tmp/sounio-kimi-linear-q3-models.json 2>/dev/null; then
      cat /tmp/sounio-kimi-linear-q3-models.json
      return 0
    fi
    sleep 2
  done
  kubectl -n "${namespace}" get endpoints "${probe_name}" -o wide || true
  return 1
}

echo "[kimi-linear-q3] apply probe ${probe_name}"
kubectl apply -f "${probe_manifest}"
kubectl -n "${namespace}" rollout status deploy/"${probe_name}" --timeout=5400s

echo "[kimi-linear-q3] gpu"
kubectl -n "${namespace}" exec deploy/"${probe_name}" -- \
  sh -lc 'nvidia-smi --query-gpu=name,memory.used,memory.free,memory.total,utilization.gpu --format=csv,noheader'

echo "[kimi-linear-q3] models"
wait_probe_models
echo

echo "[kimi-linear-q3] matrix run_id=${run_id}"
SSM_PROBE_ENDPOINT="${probe_endpoint}" \
SSM_PROBE_RUN_ID="${run_id}" \
SSM_PROBE_MODEL="${served_model}" \
  "${repo_root}/scripts/infrastructure/run_ssm_probe_matrix.sh"

echo "[kimi-linear-q3] completed"
