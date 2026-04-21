#!/usr/bin/env bash
set -euo pipefail

failures=0

section() {
  echo
  echo "== $1 =="
}

pass() {
  echo "PASS: $1"
}

warn() {
  echo "WARN: $1"
  failures=$((failures + 1))
}

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || {
    echo "Missing required command: $1" >&2
    exit 2
  }
}

require_cmd ip
require_cmd tailscale

echo "HPC route doctor"
echo

section "Tailscale overlap guard"
route_all="$(tailscale debug prefs 2>/dev/null | sed -n 's/.*"RouteAll": \(true\|false\).*/\1/p' | head -n1)"
if [[ "${route_all}" == "false" ]]; then
  pass "t560 Tailscale RouteAll/accept-routes is disabled"
else
  warn "t560 Tailscale RouteAll/accept-routes is enabled; overlapping subnet routes can hijack vmbr0 replies"
fi

if ip route show table 52 2>/dev/null | grep -q '^192\.168\.3\.0/24 '; then
  warn "table 52 still imports 192.168.3.0/24 via tailscale0"
else
  pass "table 52 no longer imports 192.168.3.0/24"
fi

section "Management LAN routing"
route_probe="$(ip route get 192.168.3.228 2>/dev/null | tr -s ' ')"
if [[ "${route_probe}" == *" dev vmbr0 "* && "${route_probe}" == *" src 192.168.3.169 "* ]]; then
  pass "management LAN replies route through vmbr0 (${route_probe})"
else
  warn "management LAN route probe is unexpected: ${route_probe:-<no output>}"
fi

section "API endpoint resolution"
if command -v getent >/dev/null 2>&1; then
  api_hosts="$(getent ahostsv4 k8s-api.darwin.lan 2>/dev/null | awk '{print $1}' | sort -u | xargs || true)"
  if [[ "${api_hosts}" == *"10.100.100.2"* ]]; then
    pass "k8s-api.darwin.lan resolves to 10.100.100.2 (${api_hosts})"
  else
    warn "k8s-api.darwin.lan resolution is unexpected (${api_hosts:-<no output>})"
  fi
else
  warn "getent is not available; skipping DNS resolution check"
fi

api_route_probe="$(ip route get 10.100.100.2 2>/dev/null | tr -s ' ')"
if [[ -n "${api_route_probe}" ]]; then
  pass "route to 10.100.100.2 is present (${api_route_probe})"
else
  warn "route to 10.100.100.2 is missing"
fi

check_server_line() {
  local file="$1"
  local label="$2"
  local line
  line="$(sudo -n grep -m1 'server:' "$file" 2>/dev/null || true)"
  if [[ "${line}" == *"https://k8s-api.darwin.lan:6443"* ]]; then
    pass "${label} uses k8s-api.darwin.lan:6443"
  else
    warn "${label} is not using k8s-api.darwin.lan:6443 (${line:-missing})"
  fi
}

section "Kubeconfig controlPlaneEndpoint alignment"
check_server_line /etc/kubernetes/admin.conf "/etc/kubernetes/admin.conf"
check_server_line /etc/kubernetes/super-admin.conf "/etc/kubernetes/super-admin.conf"
check_server_line /root/.kube/config "/root/.kube/config"

if [[ -f /home/devsounio/.kube/config ]]; then
  line="$(grep -m1 'server:' /home/devsounio/.kube/config 2>/dev/null || true)"
  if [[ "${line}" == *"https://k8s-api.darwin.lan:6443"* ]]; then
    pass "/home/devsounio/.kube/config uses k8s-api.darwin.lan:6443"
  else
    warn "/home/devsounio/.kube/config is not using k8s-api.darwin.lan:6443 (${line:-missing})"
  fi
else
  warn "/home/devsounio/.kube/config is missing"
fi

cp_endpoint="$(sudo -n kubectl -n kube-system get configmap kubeadm-config -o go-template='{{index .data "ClusterConfiguration"}}' 2>/dev/null | sed -n 's/^controlPlaneEndpoint: //p' | head -n1)"
if [[ "${cp_endpoint}" == "k8s-api.darwin.lan:6443" ]]; then
  pass "kubeadm-config controlPlaneEndpoint is k8s-api.darwin.lan:6443"
else
  warn "kubeadm-config controlPlaneEndpoint is unexpected (${cp_endpoint:-missing})"
fi

section "Kubernetes reachability"
if sudo -n kubectl --request-timeout=5s get --raw=/readyz >/dev/null 2>&1; then
  pass "Kubernetes API /readyz responds via current admin path"
else
  warn "Kubernetes API /readyz did not respond via current admin path"
fi

not_ready_nodes="$(sudo -n kubectl get nodes --no-headers 2>/dev/null | awk '$2 != "Ready" {print $1}' | xargs || true)"
if [[ -z "${not_ready_nodes}" ]]; then
  pass "all Kubernetes nodes are Ready"
else
  warn "non-Ready Kubernetes nodes: ${not_ready_nodes}"
fi

echo
if (( failures == 0 )); then
  echo "Doctor verdict: HEALTHY"
  exit 0
fi

echo "Doctor verdict: ATTENTION (${failures} issue(s))"
echo "Suggested first remediation:"
echo "  sudo tailscale set --accept-routes=false"
exit 1
