#!/usr/bin/env bash
set -euo pipefail

role="${DYNAMO_ROLE:-worker}"
namespace="${DYNAMO_NAMESPACE:-sounio-inference}"
discovery_backend="${DYNAMO_DISCOVERY_BACKEND:-kubernetes}"
model_path="${MODEL_PATH:-Qwen/Qwen2.5-0.5B-Instruct}"
served_model_name="${SERVED_MODEL_NAME:-qwen2.5-0.5B-Instruct}"
http_host="${DYNAMO_HTTP_HOST:-0.0.0.0}"
http_port="${DYNAMO_HTTP_PORT:-8000}"
engine_host="${SGLANG_HOST:-0.0.0.0}"
engine_port="${SGLANG_PORT:-30000}"

if [[ "${role}" == "frontend" ]]; then
  exec python3 -m dynamo.frontend \
    --namespace "${namespace}" \
    --discovery-backend "${discovery_backend}" \
    --http-host "${http_host}" \
    --http-port "${http_port}"
fi

exec python3 -m dynamo.sglang \
  --namespace "${namespace}" \
  --discovery-backend "${discovery_backend}" \
  --model-path "${model_path}" \
  --served-model-name "${served_model_name}" \
  --host "${engine_host}" \
  --port "${engine_port}"
