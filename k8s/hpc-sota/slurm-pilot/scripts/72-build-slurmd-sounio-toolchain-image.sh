#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
IMAGE_CONTEXT="${IMAGE_CONTEXT:-${REPO_ROOT}/images/slurmd-sounio-toolchain}"
CONTAINER_TOOL="${CONTAINER_TOOL:-buildah}"
REGISTRY_HOST="${REGISTRY_HOST:-192.168.3.207:5003}"
IMAGE_NAME="${IMAGE_NAME:-slurmd-sounio-toolchain}"
IMAGE_TAG="${IMAGE_TAG:-25.11-ubuntu24.04-gcc-$(date -u +%Y%m%dT%H%M%SZ)}"
IMAGE_REF="${IMAGE_REF:-${REGISTRY_HOST}/${IMAGE_NAME}:${IMAGE_TAG}}"

if ! command -v "${CONTAINER_TOOL}" >/dev/null 2>&1; then
  echo "missing container tool: ${CONTAINER_TOOL}" >&2
  exit 1
fi

if [[ ! -f "${IMAGE_CONTEXT}/Dockerfile" ]]; then
  echo "missing Dockerfile: ${IMAGE_CONTEXT}/Dockerfile" >&2
  exit 1
fi

if [[ "${CONTAINER_TOOL}" == "buildah" ]]; then
  "${CONTAINER_TOOL}" bud --isolation "${BUILDAH_ISOLATION:-chroot}" -t "${IMAGE_REF}" "${IMAGE_CONTEXT}"
  "${CONTAINER_TOOL}" push --tls-verify=false "${IMAGE_REF}" "docker://${IMAGE_REF}"
else
  "${CONTAINER_TOOL}" build -t "${IMAGE_REF}" "${IMAGE_CONTEXT}"
  "${CONTAINER_TOOL}" push "${IMAGE_REF}"
fi

cat <<EOF
Built and pushed Sounio Slurm CPU worker image:
  ${IMAGE_REF}

Use it in values/slurm-pilot-values.yaml:

nodesets:
  cpuops:
    slurmd:
      image:
        repository: ${IMAGE_REF%:*}
        tag: ${IMAGE_REF##*:}
EOF

