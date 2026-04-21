#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SLINKY_VERSION="${SLINKY_VERSION:-v1.1.0-rc1}"
WORKDIR="${WORKDIR:-/tmp/slurm-operator-build-${SLINKY_VERSION}}"
PATCH_DIR="${PATCH_DIR:-${REPO_ROOT}/patches}"
PATCH_FILE="${PATCH_FILE:-}"
CONTAINER_TOOL="${CONTAINER_TOOL:-buildah}"
IMAGE_REF="${IMAGE_REF:-ttl.sh/sounio-slurm-operator-stepmgr-$(date -u +%Y%m%d%H%M%S):24h}"

if ! command -v "${CONTAINER_TOOL}" >/dev/null 2>&1; then
  echo "missing container tool: ${CONTAINER_TOOL}" >&2
  exit 1
fi

rm -rf "${WORKDIR}"
git clone --depth=1 --branch "${SLINKY_VERSION}" https://github.com/SlinkyProject/slurm-operator.git "${WORKDIR}"

if [[ -n "${PATCH_FILE}" && -f "${PATCH_FILE}" ]]; then
  git -C "${WORKDIR}" apply "${PATCH_FILE}"
fi

if [[ -d "${PATCH_DIR}" ]]; then
  while IFS= read -r patch_file; do
    if [[ -n "${PATCH_FILE}" && "${patch_file}" == "${PATCH_FILE}" ]]; then
      continue
    fi
    git -C "${WORKDIR}" apply "${patch_file}"
  done < <(find "${PATCH_DIR}" -maxdepth 1 -type f -name 'slurm-operator-*.patch' | sort)
fi

if [[ "${CONTAINER_TOOL}" == "buildah" ]]; then
  "${CONTAINER_TOOL}" bud --isolation "${BUILDAH_ISOLATION:-chroot}" --target manager -t "${IMAGE_REF}" "${WORKDIR}"
  "${CONTAINER_TOOL}" push "${IMAGE_REF}"
else
  "${CONTAINER_TOOL}" build --target manager -t "${IMAGE_REF}" "${WORKDIR}"
  "${CONTAINER_TOOL}" push "${IMAGE_REF}"
fi

IMAGE_REPOSITORY="${IMAGE_REF%:*}"
IMAGE_TAG="${IMAGE_REF##*:}"

cat <<EOF
Built and pushed patched slurm-operator image:
  ${IMAGE_REF}

Use it with:
  export SLURM_OPERATOR_IMAGE_REPOSITORY=${IMAGE_REPOSITORY}
  export SLURM_OPERATOR_IMAGE_TAG=${IMAGE_TAG}
  /home/devsounio/beagle/k8s/hpc-sota/slurm-pilot/scripts/20-install-slurm-operator.sh
EOF
