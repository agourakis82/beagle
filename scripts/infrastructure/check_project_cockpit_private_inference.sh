#!/usr/bin/env bash
set -euo pipefail

COCKPIT_VIP="${COCKPIT_VIP:-100.107.208.198}"
PROJECT_SLUG="${PROJECT_SLUG:-sounio}"
CURL_MAX_TIME="${CURL_MAX_TIME:-15}"

runtime_url="http://${COCKPIT_VIP}/api/projects/${PROJECT_SLUG}/inference/runtime"
workload_url="http://${COCKPIT_VIP}/api/projects/${PROJECT_SLUG}/inference/workload"
bootstrap_url="http://${COCKPIT_VIP}/api/projects/${PROJECT_SLUG}/inference/bootstrap"

curl_private() {
  curl --noproxy '*' --max-time "$CURL_MAX_TIME" -fsS "$@"
}

echo "[private] inference runtime"
curl_private "${runtime_url}" \
  | jq -e '.runtime.status == "ready"
    and .runtime.truthMode == "observed"
    and .runtime.engine.status == "published-via-control-plane"
    and .runtime.engine.accessMode == "published-via-control-plane"
    and (.runtime.models | length) > 0' >/dev/null
curl_private "${runtime_url}" \
  | jq '{status:.runtime.status, truthMode:.runtime.truthMode, engineStatus:.runtime.engine.status, engineAccessMode:.runtime.engine.accessMode, models:(.runtime.models|map({id,provider}))}'

echo
echo "[private] inference workload"
curl_private "${workload_url}" \
  | jq -e '.workload.status == "ready"
    and .workload.engine.status == "ready"
    and .workload.controlPlane.status == "ready"
    and .endpoint != null' >/dev/null
curl_private "${workload_url}" \
  | jq '{status:.workload.status, endpoint, engine:(.workload.engine|{status,internalUrl,service:(.service.clusterIP // null)}), controlPlane:(.workload.controlPlane|{status,internalUrl,service:(.service.clusterIP // null)})}'

echo
echo "[private] inference bootstrap"
curl_private "${bootstrap_url}" \
  | jq -e '.provider == "inference-fabric"
    and .primaryFabric == "sglang+dynamo"
    and (.bootstrapCommand | contains("deploy_sglang_dynamo_fabric.sh"))
    and (.testCommand | contains("/v1/models"))' >/dev/null
curl_private "${bootstrap_url}" \
  | jq '{provider, primaryFabric, bootstrapCommand, rolloutCommand, testCommand}'
