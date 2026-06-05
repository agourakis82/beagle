#!/usr/bin/env bash
set -euo pipefail

NS="${NS:-beagle}"
SERVICE_URL="${SERVICE_URL:-http://ssm-probe-serving.beagle.svc.cluster.local:8002}"
EXEC_POD="${EXEC_POD:-deploy/project-cockpit}"
PROMPT="${PROMPT:-Reply with exactly: sounio-ssm-ready}"

curl_in_cluster() {
  kubectl -n "${NS}" exec "${EXEC_POD}" -- curl -fsS "$@"
}

echo "[ssm-probe] models"
curl_in_cluster "${SERVICE_URL}/v1/models"
echo

echo "[ssm-probe] health-before"
curl_in_cluster "${SERVICE_URL}/health"
echo

echo "[ssm-probe] chat smoke"
start_ns="$(date +%s%N)"
curl_in_cluster "${SERVICE_URL}/v1/chat/completions" \
  -H "content-type: application/json" \
  -d "{\"model\":\"mamba-130m-hf\",\"messages\":[{\"role\":\"user\",\"content\":\"${PROMPT}\"}],\"max_tokens\":24,\"temperature\":0}"
echo
end_ns="$(date +%s%N)"
elapsed_ms="$(( (end_ns - start_ns) / 1000000 ))"

echo "[ssm-probe] metrics-after elapsed_ms=${elapsed_ms}"
curl_in_cluster "${SERVICE_URL}/metrics"
echo
