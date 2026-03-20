#!/usr/bin/env bash
set -euo pipefail

ROOT="${ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)}"
NAMESPACE="${NAMESPACE:-beagle}"
APP_NAME="${APP_NAME:-beagle-core}"
SERVICE_NAME="${SERVICE_NAME:-beagle-core}"
LOCAL_PORT="${LOCAL_PORT:-18080}"
APPLY_MANIFESTS="${APPLY_MANIFESTS:-0}"
KUSTOMIZE_DIR="${KUSTOMIZE_DIR:-${ROOT}/k8s/beagle}"

require() {
  command -v "$1" >/dev/null 2>&1 || {
    echo "[FAIL] missing command: $1" >&2
    exit 1
  }
}

require kubectl
require curl
require date

if [[ "${APPLY_MANIFESTS}" == "1" ]]; then
  kubectl apply -k "${KUSTOMIZE_DIR}"
fi

kubectl -n "${NAMESPACE}" rollout status deployment/"${APP_NAME}" --timeout=180s

PF_LOG="$(mktemp)"
kubectl -n "${NAMESPACE}" port-forward service/"${SERVICE_NAME}" "${LOCAL_PORT}:8080" >"${PF_LOG}" 2>&1 &
PF_PID=$!

cleanup() {
  kill "${PF_PID}" >/dev/null 2>&1 || true
  rm -f "${PF_LOG}"
}
trap cleanup EXIT

sleep 3

echo "[INFO] checking /health on ${SERVICE_NAME}"
curl -fsS "http://127.0.0.1:${LOCAL_PORT}/health"
echo

POD="$(
  kubectl -n "${NAMESPACE}" get pod \
    -l app.kubernetes.io/name="${APP_NAME}" \
    -o jsonpath='{.items[0].metadata.name}'
)"

SENTINEL="cluster-mvp-$(date +%s)"
echo "[INFO] writing persistence sentinel into \$BEAGLE_DATA_DIR"
kubectl -n "${NAMESPACE}" exec "${POD}" -- sh -lc \
  'mkdir -p "${BEAGLE_DATA_DIR}/smoke" && printf "%s" "'"${SENTINEL}"'" > "${BEAGLE_DATA_DIR}/smoke/persistence.txt"'

echo "[INFO] restarting deployment/${APP_NAME}"
kubectl -n "${NAMESPACE}" rollout restart deployment/"${APP_NAME}"
kubectl -n "${NAMESPACE}" rollout status deployment/"${APP_NAME}" --timeout=180s

NEW_POD="$(
  kubectl -n "${NAMESPACE}" get pod \
    -l app.kubernetes.io/name="${APP_NAME}" \
    -o jsonpath='{.items[0].metadata.name}'
)"

VALUE="$(
  kubectl -n "${NAMESPACE}" exec "${NEW_POD}" -- sh -lc \
    'cat "${BEAGLE_DATA_DIR}/smoke/persistence.txt"'
)"

if [[ "${VALUE}" != "${SENTINEL}" ]]; then
  echo "[FAIL] persistence check failed: expected ${SENTINEL}, got ${VALUE}" >&2
  exit 1
fi

echo "[INFO] re-checking /health after restart"
curl -fsS "http://127.0.0.1:${LOCAL_PORT}/health"
echo

echo "[INFO] recent logs"
kubectl -n "${NAMESPACE}" logs deployment/"${APP_NAME}" --tail=40

echo "[OK] cluster MVP smoke passed"
