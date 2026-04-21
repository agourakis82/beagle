#!/usr/bin/env bash
set -euo pipefail

SOURCE_KUBECONFIG="${SOURCE_KUBECONFIG:-/home/devsounio/.kube/config}"
FALLBACK_KUBECONFIG="/etc/kubernetes/admin.conf"
TARGET_SERVER="${TARGET_SERVER:-https://k8s-api.darwin.lan:6443}"

if [[ $# -ne 1 ]]; then
  echo "usage: $0 <output-kubeconfig-path>" >&2
  exit 1
fi

OUTPUT_PATH="$1"

if [[ ! -f "${SOURCE_KUBECONFIG}" ]]; then
  SOURCE_KUBECONFIG="${FALLBACK_KUBECONFIG}"
fi

if [[ ! -f "${SOURCE_KUBECONFIG}" ]]; then
  echo "no source kubeconfig found at ${SOURCE_KUBECONFIG} or ${FALLBACK_KUBECONFIG}" >&2
  exit 1
fi

tmp="$(mktemp)"
trap 'rm -f "${tmp}"' EXIT

KUBECONFIG="${SOURCE_KUBECONFIG}" kubectl config view --raw --flatten > "${tmp}"
cluster_name="$(KUBECONFIG="${tmp}" kubectl config view -o jsonpath='{.clusters[0].name}')"

if [[ -z "${cluster_name}" ]]; then
  echo "unable to determine cluster name from ${SOURCE_KUBECONFIG}" >&2
  exit 1
fi

KUBECONFIG="${tmp}" kubectl config set-cluster "${cluster_name}" --server="${TARGET_SERVER}" >/dev/null

mkdir -p "$(dirname "${OUTPUT_PATH}")"
install -m 0600 "${tmp}" "${OUTPUT_PATH}"

echo "wrote Tailnet client kubeconfig: ${OUTPUT_PATH}"
echo "source kubeconfig: ${SOURCE_KUBECONFIG}"
echo "target server: ${TARGET_SERVER}"
echo
echo "client prerequisites:"
echo "  1. accept the subnet route to 10.100.100.0/24"
echo "  2. resolve k8s-api.darwin.lan -> 10.100.100.2"
echo "  3. install this file as ~/.kube/config on the trusted client"
