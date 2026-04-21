#!/usr/bin/env bash
set -euo pipefail

NAMESPACE="${1:-${DYNAMO_PLATFORM_NAMESPACE:-dynamo-system}}"
VERSION="${DYNAMO_PLATFORM_VERSION:-1.0.1}"
RELEASE_NAME="${DYNAMO_PLATFORM_RELEASE_NAME:-dynamo-platform}"
TMP_DIR="${DYNAMO_PLATFORM_TMP_DIR:-$(mktemp -d)}"
CHART_URL="https://helm.ngc.nvidia.com/nvidia/ai-dynamo/charts/dynamo-platform-${VERSION}.tgz"
CHART_PATH="${TMP_DIR}/dynamo-platform-${VERSION}.tgz"

cleanup() {
  if [[ -n "${TMP_DIR:-}" && -d "${TMP_DIR:-}" ]]; then
    rm -rf "${TMP_DIR}"
  fi
}

trap cleanup EXIT

if ! command -v helm >/dev/null 2>&1; then
  echo "helm is required to install Dynamo Platform" >&2
  exit 1
fi

if ! command -v kubectl >/dev/null 2>&1; then
  echo "kubectl is required to install Dynamo Platform" >&2
  exit 1
fi

echo "Fetching Dynamo Platform chart ${VERSION} from ${CHART_URL}"
curl -fsSL -o "${CHART_PATH}" "${CHART_URL}"

echo "Installing/upgrading ${RELEASE_NAME} into namespace ${NAMESPACE}"
helm upgrade --install "${RELEASE_NAME}" "${CHART_PATH}" \
  --namespace "${NAMESPACE}" \
  --create-namespace

echo "Waiting for Dynamo platform namespace ${NAMESPACE} to exist"
kubectl get namespace "${NAMESPACE}" >/dev/null

echo "Dynamo Platform bootstrap submitted."
