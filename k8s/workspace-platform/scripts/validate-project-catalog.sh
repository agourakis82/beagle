#!/usr/bin/env bash
set -euo pipefail

usage() {
  echo "usage: $0 <catalog-dir>" >&2
}

if [[ $# -ne 1 ]]; then
  usage
  exit 1
fi

catalog_dir="$1"
root="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
render_catalog="${root}/render-project-catalog.sh"
tmp_dir="$(mktemp -d)"
trap 'rm -rf "${tmp_dir}"' EXIT

"${render_catalog}" --validate-live "${catalog_dir}" "${tmp_dir}"

if kubectl config current-context >/dev/null 2>&1; then
  kubectl apply --dry-run=server -f "${tmp_dir}" >/dev/null
elif sudo kubectl --kubeconfig=/etc/kubernetes/admin.conf config current-context >/dev/null 2>&1; then
  sudo kubectl --kubeconfig=/etc/kubernetes/admin.conf apply --dry-run=server -f "${tmp_dir}" >/dev/null
else
  echo "unable to find a working kubectl context via kubectl or sudo kubectl --kubeconfig=/etc/kubernetes/admin.conf" >&2
  exit 1
fi

echo "catalog validation ok: ${catalog_dir}"
