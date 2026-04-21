#!/usr/bin/env bash
set -euo pipefail

BASE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PASS="${PASS:-Urso1982!}"
RUN_ID="${RUN_ID:-$(date +%s)}"
SIZE_MB="${SIZE_MB:-256}"
MODE="${MODE:-fanout}"
T560_HOST=root@10.100.100.2
KUBECONFIG_REMOTE=/etc/kubernetes/admin.conf
TEMPLATE="$BASE/k8s/pod-orangefs-dataset-repro-template.yaml"

render_apply() {
  local name="$1"
  local node="$2"
  local mode="$3"
  local expected_digest="${4:-}"
  perl -0pe \
    "s/__NAME__/$name/g; s/__NODE__/$node/g; s/__RUN_ID__/$RUN_ID/g; s/__SIZE_MB__/$SIZE_MB/g; s/__MODE__/$mode/g; s/__EXPECTED_DIGEST__/$expected_digest/g" \
    "$TEMPLATE" \
  | sshpass -p "$PASS" ssh -o StrictHostKeyChecking=no "$T560_HOST" "KUBECONFIG=$KUBECONFIG_REMOTE kubectl apply -f - >/dev/null"
}

delete_pod() {
  local name="$1"
  sshpass -p "$PASS" ssh -o StrictHostKeyChecking=no "$T560_HOST" \
    "KUBECONFIG=$KUBECONFIG_REMOTE kubectl -n beagle delete pod $name --ignore-not-found --force --grace-period=0 >/dev/null 2>&1 || true"
}

wait_pod() {
  local name="$1"
  local phase
  for _ in $(seq 1 180); do
    phase="$(sshpass -p "$PASS" ssh -o StrictHostKeyChecking=no "$T560_HOST" "KUBECONFIG=$KUBECONFIG_REMOTE kubectl -n beagle get pod $name -o jsonpath='{.status.phase}'" 2>/dev/null || true)"
    if [[ "$phase" == "Succeeded" || "$phase" == "Failed" ]]; then
      echo "$phase"
      return 0
    fi
    sleep 2
  done
  echo "Timeout"
}

logs_pod() {
  local name="$1"
  echo "---logs:$name---"
  sshpass -p "$PASS" ssh -o StrictHostKeyChecking=no "$T560_HOST" \
    "KUBECONFIG=$KUBECONFIG_REMOTE kubectl -n beagle logs $name --tail=200 2>/dev/null || true"
}

fetch_logs() {
  local name="$1"
  sshpass -p "$PASS" ssh -o StrictHostKeyChecking=no "$T560_HOST" \
    "KUBECONFIG=$KUBECONFIG_REMOTE kubectl -n beagle logs $name --tail=200 2>/dev/null || true"
}

extract_digest() {
  local name="$1"
  fetch_logs "$name" | awk -F'sha256=' '/sha256=/{print $2}' | tail -n1 | tr -d '\r'
}

restart_client_mounts() {
  local host
  for host in root@10.100.100.4 root@10.100.100.1; do
    sshpass -p "$PASS" ssh -o StrictHostKeyChecking=no "$host" \
      "systemctl restart orangefs-client-runtime.service >/dev/null && systemctl is-active orangefs-client-runtime.service" >/dev/null
  done
}

writer="orangefs-dataset-repro-writer-r740"
reader1="orangefs-dataset-repro-reader-r740"
reader2="orangefs-dataset-repro-reader-r770"

for pod in "$writer" "$reader1" "$reader2"; do
  delete_pod "$pod"
done
sleep 3

restart_client_mounts

case "$MODE" in
  writer-r740)
    render_apply "$writer" "r740-proxmox" writer ""
    phase="$(wait_pod "$writer")"
    echo "$writer phase=$phase"
    logs_pod "$writer"
    ;;
  reader-r740)
    render_apply "$reader1" "r740-proxmox" reader "${EXPECTED_DIGEST:-}"
    phase="$(wait_pod "$reader1")"
    echo "$reader1 phase=$phase"
    logs_pod "$reader1"
    ;;
  reader-r770)
    render_apply "$reader2" "r770-proxmox" reader "${EXPECTED_DIGEST:-}"
    phase="$(wait_pod "$reader2")"
    echo "$reader2 phase=$phase"
    logs_pod "$reader2"
    ;;
  fanout)
    render_apply "$writer" "r740-proxmox" writer ""
    phase="$(wait_pod "$writer")"
    echo "$writer phase=$phase"
    logs_pod "$writer"
    [[ "$phase" == "Succeeded" ]]

    expected_digest="$(extract_digest "$writer")"
    if [[ -z "$expected_digest" ]]; then
      echo "failed to extract dataset digest from $writer logs" >&2
      exit 1
    fi
    echo "dataset digest=$expected_digest"

    restart_client_mounts

    render_apply "$reader1" "r740-proxmox" reader "$expected_digest"
    render_apply "$reader2" "r770-proxmox" reader "$expected_digest"
    phase1="$(wait_pod "$reader1")"
    phase2="$(wait_pod "$reader2")"
    echo "$reader1 phase=$phase1"
    echo "$reader2 phase=$phase2"
    logs_pod "$reader1"
    logs_pod "$reader2"
    ;;
  *)
    echo "unsupported MODE=$MODE" >&2
    exit 2
    ;;
esac
