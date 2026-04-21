#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib-kubeconfig.sh"
SLINKY_VERSION="${SLINKY_VERSION:-v1.1.0-rc1}"
WORKDIR="${WORKDIR:-/tmp/slurm-operator-${SLINKY_VERSION}}"
PATCH_DIR="${PATCH_DIR:-${REPO_ROOT}/patches}"
PATCH_FILE="${PATCH_FILE:-}"
VALUES_FILE="${VALUES_FILE:-${REPO_ROOT}/values/slurm-operator-values.yaml}"
ENABLE_STEPMGR="${ENABLE_STEPMGR:-false}"
SLURM_OPERATOR_IMAGE_REPOSITORY="${SLURM_OPERATOR_IMAGE_REPOSITORY:-}"
SLURM_OPERATOR_IMAGE_TAG="${SLURM_OPERATOR_IMAGE_TAG:-}"
export KUBECONFIG="${KUBECONFIG_PATH}"

rm -rf "${WORKDIR}"
git clone --depth=1 --branch "${SLINKY_VERSION}" https://github.com/SlinkyProject/slurm-operator.git "${WORKDIR}"
if [[ -n "${PATCH_FILE}" && -f "${PATCH_FILE}" ]]; then
  git -C "${WORKDIR}" apply "${PATCH_FILE}"
fi
if [[ -d "${PATCH_DIR}" ]]; then
  while IFS= read -r patch_path; do
    if [[ -n "${PATCH_FILE}" && "${patch_path}" == "${PATCH_FILE}" ]]; then
      continue
    fi
    git -C "${WORKDIR}" apply "${patch_path}"
  done < <(find "${PATCH_DIR}" -maxdepth 1 -type f -name 'slurm-operator-*.patch' | sort)
fi
helm dependency build "${WORKDIR}/helm/slurm-operator" >/dev/null

HELM_SET_ARGS=()
HELM_SET_ARGS+=(--set-string "operator.enableStepmgr=${ENABLE_STEPMGR}")
if [[ -n "${SLURM_OPERATOR_IMAGE_REPOSITORY}" ]]; then
  HELM_SET_ARGS+=(--set "operator.image.repository=${SLURM_OPERATOR_IMAGE_REPOSITORY}")
fi
if [[ -n "${SLURM_OPERATOR_IMAGE_TAG}" ]]; then
  HELM_SET_ARGS+=(--set "operator.image.tag=${SLURM_OPERATOR_IMAGE_TAG}")
fi

helm upgrade --install slurm-operator "${WORKDIR}/helm/slurm-operator" \
  --namespace slurm-pilot \
  --create-namespace \
  -f "${VALUES_FILE}" \
  "${HELM_SET_ARGS[@]}"

KUBECONFIG="${KUBECONFIG_PATH}" kubectl -n slurm-pilot rollout status deploy/slurm-operator --timeout=180s
KUBECONFIG="${KUBECONFIG_PATH}" kubectl -n slurm-pilot rollout status deploy/slurm-operator-webhook --timeout=180s
