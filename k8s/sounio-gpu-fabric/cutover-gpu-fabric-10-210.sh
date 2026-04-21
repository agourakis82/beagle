#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat >&2 <<'EOF'
usage: cutover-gpu-fabric-10-210.sh [--apply] [--run-smoke]

  --apply      apply the 10.210 NetworkAttachmentDefinition after preflight
  --run-smoke  run the RDMA smoke on gpu-fabric-10-210 after apply
EOF
}

apply_manifest=false
run_smoke=false

while [[ $# -gt 0 ]]; do
  case "$1" in
    --apply)
      apply_manifest=true
      shift
      ;;
    --run-smoke)
      run_smoke=true
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      usage
      echo "unknown arg: $1" >&2
      exit 1
      ;;
  esac
done

root="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
preflight="${root}/preflight-gpu-fabric-10-210.sh"
nad="${root}/networkattachmentdefinition-gpu-fabric-10-210.example.yaml"
smoke="${root}/run-jobset-rdma-smoke.sh"

if kubectl config current-context >/dev/null 2>&1; then
  k() { kubectl "$@"; }
elif sudo kubectl --kubeconfig=/etc/kubernetes/admin.conf config current-context >/dev/null 2>&1; then
  k() { sudo kubectl --kubeconfig=/etc/kubernetes/admin.conf "$@"; }
else
  echo "unable to find a working kubectl context via kubectl or sudo kubectl --kubeconfig=/etc/kubernetes/admin.conf" >&2
  exit 1
fi

"${preflight}"

cat <<'EOF'

external prerequisites still required outside Kubernetes:
- Arista VLAN for 10.210.0.0/24 created and trunked to the GPU hosts
- SVI/gateway for 10.210.0.254 configured
- host bridge/master path normalized to gpufabric210 with MTU 9000
- PFC/ECN only on the dedicated GPU VLAN
EOF

if ! $apply_manifest; then
  echo
  echo "preflight passed; rerun with --apply when the external network side is ready"
  exit 0
fi

echo
echo "== applying gpu-fabric-10-210 =="
k apply -f "${nad}"
k -n beagle get network-attachment-definition gpu-fabric-10-210

if ! $run_smoke; then
  echo
  echo "10.210 attachment applied; rerun with --run-smoke to execute the RDMA smoke"
  exit 0
fi

echo
echo "== running RDMA smoke on 10.210 =="
"${smoke}" \
  --network gpu-fabric-10-210 \
  --jobset-name sounio-rdma-ddp-smoke-10-210
