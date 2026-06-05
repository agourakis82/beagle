#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
namespace="${KUBE_NAMESPACE:-beagle}"
runner="${RUNNER_DEPLOYMENT:-deploy/project-cockpit}"

probe_name="${GGUF_PROBE_NAME:-cluster-gguf-probe}"
model_repo="${GGUF_MODEL_REPO:?GGUF_MODEL_REPO is required, e.g. HuggingFaceTB/SmolLM2-1.7B-Instruct-GGUF}"
model_file="${GGUF_MODEL_FILE:?GGUF_MODEL_FILE is required, e.g. smollm2-1.7b-instruct-q4_k_m.gguf}"
served_model="${GGUF_SERVED_MODEL:-${probe_name}}"
run_id="${SSM_PROBE_RUN_ID:-${probe_name}-$(date -u +%Y%m%dT%H%M%SZ)}"

node_name="${GGUF_NODE_NAME:-r770-proxmox}"
accelerator="${GGUF_ACCELERATOR:-nvidia-l4}"
service_port="${GGUF_SERVICE_PORT:-8007}"
ctx_size="${GGUF_CTX_SIZE:-4096}"
gpu_layers="${GGUF_GPU_LAYERS:-999}"
threads="${GGUF_THREADS:-8}"
parallel="${GGUF_PARALLEL:-1}"
model_cache_size="${GGUF_MODEL_CACHE_SIZE:-16Gi}"
memory_request="${GGUF_MEMORY_REQUEST:-8Gi}"
memory_limit="${GGUF_MEMORY_LIMIT:-32Gi}"
cpu_request="${GGUF_CPU_REQUEST:-2}"
cpu_limit="${GGUF_CPU_LIMIT:-8}"
image="${LLAMACPP_IMAGE:-ghcr.io/ggml-org/llama.cpp:server-cuda}"
keep_probe="${KEEP_GGUF_PROBE:-0}"
run_operator_safe="${RUN_OPERATOR_SAFE:-1}"

if ! [[ "${probe_name}" =~ ^[a-z0-9]([-a-z0-9]*[a-z0-9])?$ ]]; then
  echo "GGUF_PROBE_NAME must be a DNS-1123 name: ${probe_name}" >&2
  exit 2
fi

tmp_manifest="$(mktemp -t "${probe_name}.XXXXXX.yaml")"
model_url="https://huggingface.co/${model_repo}/resolve/main/${model_file}"
endpoint="http://${probe_name}.${namespace}.svc.cluster.local:${service_port}"

cleanup() {
  local rc=$?
  if [[ "${keep_probe}" != "1" ]]; then
    kubectl -n "${namespace}" delete -f "${tmp_manifest}" --ignore-not-found=true >/dev/null 2>&1 || true
  else
    echo "[gguf-probe] keeping ${probe_name}; endpoint=${endpoint}"
  fi
  rm -f "${tmp_manifest}"
  return "${rc}"
}
trap cleanup EXIT

cat >"${tmp_manifest}" <<YAML
apiVersion: v1
kind: Service
metadata:
  name: ${probe_name}
  namespace: ${namespace}
  labels:
    app.kubernetes.io/name: ${probe_name}
    app.kubernetes.io/part-of: beagle
    sounio.dev/lane: cluster-model-probe
    sounio.dev/probe-runtime: llamacpp
spec:
  selector:
    app.kubernetes.io/name: ${probe_name}
  ports:
    - name: http
      port: ${service_port}
      targetPort: http
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: ${probe_name}
  namespace: ${namespace}
  labels:
    app.kubernetes.io/name: ${probe_name}
    app.kubernetes.io/part-of: beagle
    sounio.dev/lane: cluster-model-probe
    sounio.dev/probe-runtime: llamacpp
spec:
  replicas: 1
  revisionHistoryLimit: 1
  strategy:
    type: Recreate
  selector:
    matchLabels:
      app.kubernetes.io/name: ${probe_name}
  template:
    metadata:
      labels:
        app.kubernetes.io/name: ${probe_name}
        app.kubernetes.io/part-of: beagle
        sounio.dev/lane: cluster-model-probe
        sounio.dev/probe-runtime: llamacpp
    spec:
      runtimeClassName: nvidia
      nodeSelector:
        kubernetes.io/hostname: ${node_name}
        sounio.dev/accelerator-class: gpu
        sounio.dev/accelerator: ${accelerator}
      tolerations:
        - key: sounio.dev/compute
          operator: Equal
          value: heavy
          effect: NoSchedule
        - key: sounio.dev/pool
          operator: Equal
          value: gpu-batch
          effect: NoSchedule
      initContainers:
        - name: fetch-gguf
          image: curlimages/curl:8.17.0
          imagePullPolicy: IfNotPresent
          command:
            - sh
            - -lc
            - |
              set -eu
              file="/models/model.gguf"
              if [ -s "\${file}" ]; then
                echo "GGUF already present: \${file}"
                exit 0
              fi
              curl -L --fail --retry 8 --retry-delay 10 --connect-timeout 30 \
                -o "\${file}.part" \
                "${model_url}"
              mv "\${file}.part" "\${file}"
              ls -lh "\${file}"
          resources:
            requests:
              cpu: "1"
              memory: 512Mi
            limits:
              cpu: "2"
              memory: 2Gi
          volumeMounts:
            - name: model-cache
              mountPath: /models
      containers:
        - name: llama-server
          image: ${image}
          imagePullPolicy: IfNotPresent
          command:
            - /bin/sh
            - -lc
          args:
            - |
              set -eu
              export LD_LIBRARY_PATH=/app:\${LD_LIBRARY_PATH:-}
              exec /app/llama-server \
                --model /models/model.gguf \
                --alias "${served_model}" \
                --host 0.0.0.0 \
                --port 8000 \
                --ctx-size ${ctx_size} \
                --n-gpu-layers ${gpu_layers} \
                --threads ${threads} \
                --parallel ${parallel} \
                --cont-batching \
                --jinja
          env:
            - name: CUDA_VISIBLE_DEVICES
              value: "0"
          ports:
            - name: http
              containerPort: 8000
          startupProbe:
            httpGet:
              path: /health
              port: http
            periodSeconds: 10
            timeoutSeconds: 10
            failureThreshold: 360
          readinessProbe:
            httpGet:
              path: /health
              port: http
            periodSeconds: 10
            timeoutSeconds: 10
            failureThreshold: 8
          livenessProbe:
            httpGet:
              path: /health
              port: http
            initialDelaySeconds: 120
            periodSeconds: 30
            timeoutSeconds: 10
            failureThreshold: 6
          resources:
            requests:
              cpu: "${cpu_request}"
              memory: ${memory_request}
              nvidia.com/gpu: "1"
            limits:
              cpu: "${cpu_limit}"
              memory: ${memory_limit}
              nvidia.com/gpu: "1"
          volumeMounts:
            - name: model-cache
              mountPath: /models
            - name: dshm
              mountPath: /dev/shm
      volumes:
        - name: model-cache
          emptyDir:
            sizeLimit: ${model_cache_size}
        - name: dshm
          emptyDir:
            medium: Memory
            sizeLimit: 4Gi
YAML

wait_probe_models() {
  local i
  for i in $(seq 1 120); do
    if kubectl -n "${namespace}" exec "${runner}" -- \
      curl -fsS "${endpoint}/v1/models" >/tmp/sounio-${probe_name}-models.json 2>/dev/null; then
      cat /tmp/sounio-${probe_name}-models.json
      return 0
    fi
    sleep 2
  done
  kubectl -n "${namespace}" get endpoints "${probe_name}" -o wide || true
  kubectl -n "${namespace}" logs deploy/"${probe_name}" --tail=120 || true
  return 1
}

echo "[gguf-probe] model=${model_repo}/${model_file}"
echo "[gguf-probe] apply ${probe_name} on ${node_name}/${accelerator}"
kubectl apply -f "${tmp_manifest}"
kubectl -n "${namespace}" rollout status deploy/"${probe_name}" --timeout=7200s

echo "[gguf-probe] gpu"
kubectl -n "${namespace}" exec deploy/"${probe_name}" -- \
  sh -lc 'nvidia-smi --query-gpu=name,memory.used,memory.free,memory.total,utilization.gpu --format=csv,noheader'

echo "[gguf-probe] models"
wait_probe_models
echo

echo "[gguf-probe] matrix run_id=${run_id}"
SSM_PROBE_ENDPOINT="${endpoint}" \
SSM_PROBE_RUN_ID="${run_id}" \
SSM_PROBE_MODEL="${served_model}" \
  "${repo_root}/scripts/infrastructure/run_ssm_probe_matrix.sh"

if [[ "${run_operator_safe}" == "1" ]]; then
  echo "[gguf-probe] operator-safe matrix"
  SSM_PROBE_ENDPOINT="${endpoint}" \
  SSM_PROBE_RUN_ID="${run_id}-operator-safe" \
  SSM_PROBE_MODEL="${served_model}" \
    "${repo_root}/scripts/infrastructure/run_operator_safe_probe_matrix.sh"
fi

echo "[gguf-probe] completed run_id=${run_id}"
