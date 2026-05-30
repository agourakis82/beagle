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
sglang_args=()

if [[ -n "${SGLANG_MEM_FRACTION_STATIC:-}" ]]; then
  sglang_args+=(--mem-fraction-static "${SGLANG_MEM_FRACTION_STATIC}")
fi
if [[ -n "${SGLANG_MAX_TOTAL_TOKENS:-}" ]]; then
  sglang_args+=(--max-total-tokens "${SGLANG_MAX_TOTAL_TOKENS}")
fi
if [[ -n "${SGLANG_ATTENTION_BACKEND:-}" ]]; then
  sglang_args+=(--attention-backend "${SGLANG_ATTENTION_BACKEND}")
fi
if [[ "${SGLANG_DISABLE_CUDA_GRAPH:-}" == "1" ]]; then
  sglang_args+=(--disable-cuda-graph)
fi

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
  --port "${engine_port}" \
  "${sglang_args[@]}"
