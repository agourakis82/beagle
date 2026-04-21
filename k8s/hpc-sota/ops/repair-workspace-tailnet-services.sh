#!/usr/bin/env bash
set -euo pipefail

ROOT="/home/devsounio/beagle/k8s"
HTTP_MANIFEST="${ROOT}/tailscale-operator/sounio-workspace-tailnet-http.yaml"
SSH_MANIFEST="${ROOT}/tailscale-operator/sounio-workspace-tailnet-ssh.yaml"
KUBECONFIG_PATH="${KUBECONFIG_PATH:-/etc/kubernetes/admin.conf}"
HTTP_SERVICE="sounio-workspace-tailnet-http"
SSH_SERVICE="sounio-workspace-tailnet-ssh"
PROXYGROUP_NS="tailscale"
PROXYGROUP_NAME="sounio-workspace-ingress"
WORKSPACE_NS="beagle"
WORKSPACE_STS="sounio-workspace-habitat"
TIMEOUT_SECONDS="${TIMEOUT_SECONDS:-60}"

pick_kubectl() {
  if kubectl --kubeconfig "${KUBECONFIG_PATH}" version --request-timeout=5s >/dev/null 2>&1; then
    KCTL=(kubectl --kubeconfig "${KUBECONFIG_PATH}")
    return
  fi

  if command -v sudo >/dev/null 2>&1 && sudo -n kubectl --kubeconfig "${KUBECONFIG_PATH}" version --request-timeout=5s >/dev/null 2>&1; then
    KCTL=(sudo kubectl --kubeconfig "${KUBECONFIG_PATH}")
    return
  fi

  echo "FAIL unable to reach Kubernetes API with kubectl or sudo kubectl" >&2
  exit 1
}

info() {
  printf 'INFO %s\n' "$1"
}

pass() {
  printf 'PASS %s\n' "$1"
}

fail() {
  printf 'FAIL %s\n' "$1" >&2
}

service_status() {
  local name="$1"
  "${KCTL[@]}" -n "${WORKSPACE_NS}" get svc "${name}" \
    -o jsonpath='{range .status.conditions[*]}{.type}={.status}({.reason}) {end}' 2>/dev/null || true
}

service_ip() {
  local name="$1"
  "${KCTL[@]}" -n "${WORKSPACE_NS}" get svc "${name}" \
    -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null || true
}

service_hostname() {
  local name="$1"
  "${KCTL[@]}" -n "${WORKSPACE_NS}" get svc "${name}" \
    -o jsonpath='{.status.loadBalancer.ingress[0].hostname}' 2>/dev/null || true
}

service_has_green_status() {
  local name="$1"
  [[ "$(service_status "${name}")" == *"TailscaleIngressSvcConfigured=True(IngressSvcConfigured)"* ]]
}

workspace_ready() {
  local ready
  ready="$("${KCTL[@]}" -n "${WORKSPACE_NS}" get statefulset "${WORKSPACE_STS}" -o jsonpath='{.status.readyReplicas}' 2>/dev/null || true)"
  [[ "${ready:-0}" -ge 1 ]]
}

proxygroup_ready() {
  local conditions
  conditions="$("${KCTL[@]}" -n "${PROXYGROUP_NS}" get proxygroup "${PROXYGROUP_NAME}" -o jsonpath='{range .status.conditions[*]}{.type}={.status}{" "}{end}' 2>/dev/null || true)"
  [[ "${conditions}" == *"ProxyGroupReady=True"* ]]
}

print_summary() {
  "${KCTL[@]}" -n "${WORKSPACE_NS}" get svc "${HTTP_SERVICE}" "${SSH_SERVICE}" \
    -o jsonpath='{range .items[*]}{.metadata.name}{"\t"}{range .status.conditions[*]}{.type}={.status}({.reason}) {end}{"\t"}{.status.loadBalancer.ingress[0].ip}{"\t"}{.status.loadBalancer.ingress[0].hostname}{"\n"}{end}'
  printf '\n'
}

main() {
  pick_kubectl

  if [[ ! -f "${HTTP_MANIFEST}" || ! -f "${SSH_MANIFEST}" ]]; then
    fail "required manifests missing under ${ROOT}/tailscale-operator"
    exit 1
  fi

  info "checking workspace habitat readiness"
  if workspace_ready; then
    pass "statefulset/${WORKSPACE_STS} is ready"
  else
    fail "statefulset/${WORKSPACE_STS} is not ready; refusing tailnet repair"
    exit 1
  fi

  info "checking ProxyGroup readiness"
  if proxygroup_ready; then
    pass "proxygroup/${PROXYGROUP_NAME} is ready"
  else
    fail "proxygroup/${PROXYGROUP_NAME} is not ready; refusing tailnet repair"
    exit 1
  fi

  info "current workspace tailnet service status"
  print_summary

  if service_has_green_status "${HTTP_SERVICE}" && service_has_green_status "${SSH_SERVICE}"; then
    pass "workspace tailnet services already configured"
    exit 0
  fi

  info "recreating workspace tailnet services from canonical manifests"
  "${KCTL[@]}" -n "${WORKSPACE_NS}" delete svc "${HTTP_SERVICE}" "${SSH_SERVICE}" --ignore-not-found=true --wait=true
  "${KCTL[@]}" apply -f "${HTTP_MANIFEST}" -f "${SSH_MANIFEST}"

  info "waiting up to ${TIMEOUT_SECONDS}s for TailscaleIngressSvcConfigured=True"
  local deadline
  deadline=$((SECONDS + TIMEOUT_SECONDS))
  while (( SECONDS < deadline )); do
    if service_has_green_status "${HTTP_SERVICE}" && service_has_green_status "${SSH_SERVICE}"; then
      pass "workspace tailnet services returned to green"
      print_summary
      exit 0
    fi
    sleep 2
  done

  fail "workspace tailnet services did not return to green in ${TIMEOUT_SECONDS}s"
  print_summary
  exit 1
}

main "$@"
