#!/usr/bin/env bash
set -euo pipefail

if [[ -z "${KUBECONFIG:-}" && ! -f /etc/kubernetes/admin.conf ]]; then
  echo "Set KUBECONFIG or run from a control-plane host with /etc/kubernetes/admin.conf." >&2
  exit 1
fi

if [[ -z "${KUBECONFIG:-}" ]]; then
  export KUBECONFIG=/etc/kubernetes/admin.conf
fi

chart_version="$(helm -n kube-system list -o json | python3 -c 'import json,sys; data=json.load(sys.stdin); print(data[0]["chart"].split("-")[-1] if data else "")')"
if [[ -z "${chart_version}" ]]; then
  echo "Unable to discover the deployed Cilium chart version." >&2
  exit 1
fi
target_chart_version="${TARGET_CHART_VERSION:-${chart_version}}"
k8s_service_host="${K8S_SERVICE_HOST_OVERRIDE:-$(kubectl -n default get svc kubernetes -o jsonpath='{.spec.clusterIP}')}"
k8s_service_port="${K8S_SERVICE_PORT_OVERRIDE:-$(kubectl -n default get svc kubernetes -o jsonpath='{.spec.ports[0].port}')}"
if [[ -z "${k8s_service_host}" || -z "${k8s_service_port}" ]]; then
  echo "Unable to discover kubernetes service host/port for Cilium upgrade." >&2
  exit 1
fi

tmp_values="$(mktemp)"
trap 'rm -f "$tmp_values"' EXIT

helm -n kube-system get values cilium -a >"$tmp_values"

helm repo add cilium https://helm.cilium.io >/dev/null 2>&1 || true
helm repo update >/dev/null

helm upgrade cilium cilium/cilium \
  --namespace kube-system \
  --version "${target_chart_version}" \
  -f "$tmp_values" \
  --set k8sServiceHost="${k8s_service_host}" \
  --set k8sServicePort="${k8s_service_port}" \
  --set routingMode=native \
  --set autoDirectNodeRoutes=true \
  --set ipv4NativeRoutingCIDR=10.0.0.0/8 \
  --set tunnelProtocol="" \
  --set cni.exclusive=false \
  --wait

kubectl -n kube-system rollout restart ds/cilium deploy/cilium-operator
kubectl -n kube-system rollout status ds/cilium --timeout=300s
kubectl -n kube-system rollout status deploy/cilium-operator --timeout=300s

echo "=== cilium-config ==="
echo "deployed-chart=${chart_version}"
echo "target-chart=${target_chart_version}"
echo "k8sServiceHost=${k8s_service_host}"
echo "k8sServicePort=${k8s_service_port}"
kubectl -n kube-system get cm cilium-config -o jsonpath='{.data.routing-mode}{"\n"}{.data.tunnel-protocol}{"\n"}{.data.auto-direct-node-routes}{"\n"}{.data.ipv4-native-routing-cidr}{"\n"}{.data.cni-exclusive}{"\n"}'
echo "=== cilium-live-routing ==="
pod="$(kubectl -n kube-system get pods -l k8s-app=cilium -o jsonpath='{.items[0].metadata.name}')"
kubectl -n kube-system exec "${pod}" -- cilium-dbg status | sed -n 's/^Routing:[[:space:]]*//p'
