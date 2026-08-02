#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
VERSION="${KUEUE_VERSION:-v0.16.2}"
KUBECTL_BIN="${KUBECTL_BIN:-sudo kubectl}"
PATCH_FILE="${PATCH_FILE:-${SCRIPT_DIR}/controller-manager-scheduling-patch.yaml}"

$KUBECTL_BIN apply --server-side --force-conflicts --validate=false -f "https://github.com/kubernetes-sigs/kueue/releases/download/${VERSION}/manifests.yaml"
if [[ -f "${PATCH_FILE}" ]]; then
  $KUBECTL_BIN -n kueue-system patch deployment kueue-controller-manager --type merge --patch-file "${PATCH_FILE}"
fi
$KUBECTL_BIN rollout status deployment/kueue-controller-manager -n kueue-system --timeout=180s

echo "[OK] kueue installed: ${VERSION}"
