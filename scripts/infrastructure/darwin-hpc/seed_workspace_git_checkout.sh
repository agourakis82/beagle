#!/usr/bin/env bash
set -euo pipefail

ROOT="${ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)}"
KUBECTL="${KUBECTL:-}"
NAMESPACE="${NAMESPACE:-beagle}"
DEPLOYMENT="${DEPLOYMENT:-sounio-workspace}"
CONTAINER="${CONTAINER:-workspace-ide}"
WORKSPACE_ROOT="${WORKSPACE_ROOT:-/workspace/sounio}"
REPO_URL="${REPO_URL:-}"
BRANCH="${BRANCH:-main}"

usage() {
  cat <<'EOF'
Usage:
  seed_workspace_git_checkout.sh --repo-url URL [--branch main]
      [--namespace beagle] [--deployment sounio-workspace]
      [--container workspace-ide] [--workspace-root /workspace/sounio]
EOF
}

require() {
  command -v "$1" >/dev/null 2>&1 || {
    echo "[FAIL] missing command: $1" >&2
    exit 1
  }
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --repo-url)
      REPO_URL="$2"
      shift 2
      ;;
    --branch)
      BRANCH="$2"
      shift 2
      ;;
    --namespace)
      NAMESPACE="$2"
      shift 2
      ;;
    --deployment)
      DEPLOYMENT="$2"
      shift 2
      ;;
    --container)
      CONTAINER="$2"
      shift 2
      ;;
    --workspace-root)
      WORKSPACE_ROOT="$2"
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "[FAIL] unknown argument: $1" >&2
      usage >&2
      exit 1
      ;;
  esac
done

if [[ -z "${REPO_URL}" ]]; then
  echo "[FAIL] --repo-url is required" >&2
  exit 1
fi

resolve_kubectl() {
  if [[ -n "${KUBECTL}" ]]; then
    printf '%s\n' "${KUBECTL}"
    return 0
  fi
  if [[ -r /etc/kubernetes/admin.conf ]]; then
    export KUBECONFIG=/etc/kubernetes/admin.conf
    printf '%s\n' kubectl
    return 0
  fi
  printf '%s\n' "sudo kubectl --kubeconfig=/etc/kubernetes/admin.conf"
}

require git
require tar
require mktemp

KUBECTL="$(resolve_kubectl)"
require "${KUBECTL%% *}"

TMPDIR="$(mktemp -d)"
cleanup() {
  rm -rf "${TMPDIR}"
}
trap cleanup EXIT

echo "[INFO] cloning ${REPO_URL}#${BRANCH} on host"
git clone --branch "${BRANCH}" --single-branch "${REPO_URL}" "${TMPDIR}/repo" >/dev/null 2>&1

echo "[INFO] seeding ${WORKSPACE_ROOT} in deployment/${DEPLOYMENT}"
# shellcheck disable=SC2086
${KUBECTL} -n "${NAMESPACE}" exec deployment/"${DEPLOYMENT}" -c "${CONTAINER}" -- sh -lc \
  "mkdir -p '${WORKSPACE_ROOT}' && find '${WORKSPACE_ROOT}' -mindepth 1 -maxdepth 1 ! -name '.beagle' ! -name '.devcontainer' -exec rm -rf {} +"

tar -C "${TMPDIR}/repo" -cf - . \
  | ${KUBECTL} -n "${NAMESPACE}" exec -i deployment/"${DEPLOYMENT}" -c "${CONTAINER}" -- sh -lc \
      "tar -C '${WORKSPACE_ROOT}' -xf - && chown -R openvscode-server:openvscode-server '${WORKSPACE_ROOT}'"

COMMIT_SHA="$(git -C "${TMPDIR}/repo" rev-parse HEAD)"
echo "[OK] seeded ${REPO_URL}#${BRANCH} at ${COMMIT_SHA} into ${WORKSPACE_ROOT}"
