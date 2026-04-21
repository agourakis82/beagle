#!/usr/bin/env bash
set -euo pipefail

if kubectl config current-context >/dev/null 2>&1; then
  k() { kubectl "$@"; }
elif sudo kubectl config current-context >/dev/null 2>&1; then
  k() { sudo kubectl "$@"; }
else
  echo "unable to find a working kubectl context via kubectl or sudo kubectl" >&2
  exit 1
fi

nodes="$(k get nodes -o jsonpath='{range .items[*]}{.metadata.name}{" "}{.status.addresses[?(@.type=="InternalIP")].address}{"\n"}{end}')"
routing_mode="$(k -n kube-system get cm cilium-config -o jsonpath='{.data.routing-mode}')"
tunnel_protocol="$(k -n kube-system get cm cilium-config -o jsonpath='{.data.tunnel-protocol}')"
auto_direct="$(k -n kube-system get cm cilium-config -o jsonpath='{.data.auto-direct-node-routes}')"
cilium_pod="$(k -n kube-system get pods -l k8s-app=cilium -o jsonpath='{.items[0].metadata.name}')"
live_routing_line="$(k -n kube-system exec "${cilium_pod}" -- cilium-dbg status | sed -n 's/^Routing:[[:space:]]*//p' | head -n1)"

echo "=== NODE INTERNAL IPs ==="
echo "${nodes}"
echo
echo "=== CILIUM ==="
echo "routing-mode=${routing_mode}"
echo "tunnel-protocol=${tunnel_protocol}"
echo "auto-direct-node-routes=${auto_direct}"
echo "live-routing=${live_routing_line}"
echo

bad_ip=0
while read -r name ip; do
  [[ -z "${name:-}" ]] && continue
  case "${ip}" in
    10.100.100.*|10.200.0.*) ;;
    *)
      echo "FAIL: ${name} still uses management/internal IP ${ip}" >&2
      bad_ip=1
      ;;
  esac
done <<< "${nodes}"

bad_cilium=0
if [[ "${routing_mode}" != "native" ]]; then
  echo "FAIL: cilium routing-mode is ${routing_mode}, expected native" >&2
  bad_cilium=1
fi
if [[ "${live_routing_line}" != Network:\ Native* ]]; then
  echo "FAIL: live cilium datapath is not native (${live_routing_line})" >&2
  bad_cilium=1
fi
if [[ "${auto_direct}" != "true" ]]; then
  echo "WARN: auto-direct-node-routes is ${auto_direct}" >&2
fi

if [[ "${bad_ip}" -eq 0 && "${bad_cilium}" -eq 0 ]]; then
  echo "OK: cluster underlay already matches the 100Gb plan"
  exit 0
fi

echo "NOT_READY: cluster still needs the 100Gb underlay migration" >&2
exit 1
