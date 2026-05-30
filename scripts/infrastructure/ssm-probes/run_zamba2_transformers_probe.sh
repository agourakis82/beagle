#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
namespace="${KUBE_NAMESPACE:-beagle}"
baseline_deploy="${SSM_BASELINE_DEPLOYMENT:-ssm-probe-serving}"
probe_name="${SSM_ZAMBA2_PROBE_NAME:-ssm-zamba2-transformers-probe}"
probe_manifest="${SSM_ZAMBA2_PROBE_MANIFEST:-${repo_root}/k8s/project-cockpit/profiles/ssm-zamba2-transformers-probe.yaml}"
probe_endpoint="${SSM_ZAMBA2_PROBE_ENDPOINT:-http://ssm-zamba2-transformers-probe.beagle.svc.cluster.local:8005}"
run_id="${SSM_PROBE_RUN_ID:-zamba2-transformers-$(date -u +%Y%m%dT%H%M%SZ)}"
served_model="${SSM_ZAMBA2_SERVED_MODEL:-zamba2-2.7b-instruct-v2}"
keep_probe="${KEEP_SSM_ZAMBA2_PROBE:-0}"
restore_baseline="${RESTORE_SSM_BASELINE:-1}"

wait_probe_http() {
  local i
  for i in $(seq 1 60); do
    if kubectl -n "${namespace}" exec deploy/project-cockpit -- \
      curl -fsS "${probe_endpoint}/health" >/tmp/sounio-zamba2-health.json 2>/dev/null; then
      cat /tmp/sounio-zamba2-health.json
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

echo "[zamba2-transformers] baseline -> scale down ${baseline_deploy}"
kubectl -n "${namespace}" scale deploy/"${baseline_deploy}" --replicas=0
kubectl -n "${namespace}" rollout status deploy/"${baseline_deploy}" --timeout=300s

echo "[zamba2-transformers] apply probe ${probe_name}"
kubectl apply -f "${probe_manifest}"
kubectl -n "${namespace}" rollout status deploy/"${probe_name}" --timeout=1800s

echo "[zamba2-transformers] gpu"
kubectl -n "${namespace}" exec deploy/"${probe_name}" -- \
  sh -lc 'nvidia-smi --query-gpu=name,memory.used,memory.free,memory.total,utilization.gpu --format=csv,noheader'

echo "[zamba2-transformers] health"
wait_probe_http
echo

echo "[zamba2-transformers] models"
kubectl -n "${namespace}" exec deploy/project-cockpit -- \
  curl -fsS "${probe_endpoint}/v1/models"
echo

echo "[zamba2-transformers] matrix run_id=${run_id}"
SSM_PROBE_ENDPOINT="${probe_endpoint}" \
SSM_PROBE_RUN_ID="${run_id}" \
SSM_PROBE_MODEL="${served_model}" \
  "${repo_root}/scripts/infrastructure/run_ssm_probe_matrix.sh"

echo "[zamba2-transformers] completed"
