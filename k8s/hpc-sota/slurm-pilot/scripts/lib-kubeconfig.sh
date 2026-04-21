#!/usr/bin/env bash
set -euo pipefail

resolve_default_kubeconfig() {
  if [[ -n "${KUBECONFIG:-}" ]]; then
    printf '%s\n' "${KUBECONFIG}"
    return 0
  fi

  if [[ -r "/etc/kubernetes/admin.conf" ]]; then
    printf '%s\n' "/etc/kubernetes/admin.conf"
    return 0
  fi

  if [[ -r "${HOME}/.kube/config" ]]; then
    printf '%s\n' "${HOME}/.kube/config"
    return 0
  fi

  printf '%s\n' "/etc/kubernetes/admin.conf"
}

KUBECONFIG_PATH="${KUBECONFIG_PATH:-$(resolve_default_kubeconfig)}"
export KUBECONFIG="${KUBECONFIG_PATH}"
