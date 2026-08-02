#!/usr/bin/env bash
set -euo pipefail

KUBECONFIG_PATH="${KUBECONFIG_PATH:-/etc/kubernetes/admin.conf}"
NAMESPACE="${SOUNIO_WORKSPACE_NAMESPACE:-beagle}"
CONTROL_APP="sounio-workspace-control"
CONTROL_STS="sounio-workspace-control"
CONTROL_POD="sounio-workspace-control-0"
CONTROL_SELECTOR="app.kubernetes.io/name=${CONTROL_APP}"
STABLE_SERVICES=(sounio-workspace sounio-workspace-tailnet-http sounio-workspace-tailnet-ssh)
LEGACY_APPS=(sounio-workspace-local sounio-workspace-habitat sounio-workspace-ha sounio-zellij-recovery)
FAILURES=0
WARNINGS=0

pick_kubectl() {
  if command -v kubectl >/dev/null 2>&1 && kubectl --kubeconfig "${KUBECONFIG_PATH}" version --request-timeout=5s >/dev/null 2>&1; then
    KCTL=(kubectl --kubeconfig "${KUBECONFIG_PATH}")
    return
  fi

  if command -v sudo >/dev/null 2>&1 && sudo -n kubectl --kubeconfig "${KUBECONFIG_PATH}" version --request-timeout=5s >/dev/null 2>&1; then
    KCTL=(sudo -n kubectl --kubeconfig "${KUBECONFIG_PATH}")
    return
  fi

  if command -v kubectl >/dev/null 2>&1 && kubectl version --request-timeout=5s >/dev/null 2>&1; then
    KCTL=(kubectl)
    return
  fi

  echo "FAIL unable to reach Kubernetes API with kubectl" >&2
  exit 1
}

section() {
  echo
  echo "== $1 =="
}

pass() {
  printf 'PASS %s\n' "$1"
}

warn() {
  WARNINGS=$((WARNINGS + 1))
  printf 'WARN %s\n' "$1"
}

fail() {
  FAILURES=$((FAILURES + 1))
  printf 'FAIL %s\n' "$1"
}

jsonpath() {
  "${KCTL[@]}" -n "${NAMESPACE}" get "$1" "$2" -o "jsonpath=$3" 2>/dev/null || true
}

check_control_workload() {
  local ready desired pod_ready pod_node pvc
  desired="$(jsonpath statefulset "${CONTROL_STS}" '{.spec.replicas}')"
  ready="$(jsonpath statefulset "${CONTROL_STS}" '{.status.readyReplicas}')"
  if [[ "${desired}" == "1" && "${ready:-0}" -ge 1 ]]; then
    pass "statefulset/${CONTROL_STS} desired=1 ready=${ready}"
  else
    fail "statefulset/${CONTROL_STS} expected desired=1 ready>=1, got desired=${desired:-<none>} ready=${ready:-0}"
  fi

  pod_ready="$(jsonpath pod "${CONTROL_POD}" '{range .status.conditions[?(@.type=="Ready")]}{.status}{end}')"
  pod_node="$(jsonpath pod "${CONTROL_POD}" '{.spec.nodeName}')"
  pvc="$(jsonpath pod "${CONTROL_POD}" '{.spec.volumes[?(@.name=="workspace-data")].persistentVolumeClaim.claimName}')"
  if [[ "${pod_ready}" == "True" ]]; then
    pass "pod/${CONTROL_POD} Ready on ${pod_node:-<unknown>}"
  else
    fail "pod/${CONTROL_POD} is not Ready"
  fi
  if [[ "${pvc}" == "workspace-data-sounio-workspace-habitat-0" ]]; then
    pass "pod/${CONTROL_POD} mounts retained habitat PVC ${pvc}"
  else
    fail "pod/${CONTROL_POD} mounts unexpected workspace PVC ${pvc:-<none>}"
  fi
}

check_stable_services() {
  local service selector external endpoint_pods endpoint_names
  for service in "${STABLE_SERVICES[@]}"; do
    selector="$(jsonpath service "${service}" '{.spec.selector.app\.kubernetes\.io/name}')"
    if [[ "${selector}" == "${CONTROL_APP}" ]]; then
      pass "service/${service} selector=${selector}"
    else
      fail "service/${service} selector must be ${CONTROL_APP}, got ${selector:-<none>}"
    fi

    endpoint_names="$("${KCTL[@]}" -n "${NAMESPACE}" get endpointslice \
      -l "kubernetes.io/service-name=${service}" \
      -o jsonpath='{range .items[*].endpoints[*]}{.targetRef.name}{" "}{end}' 2>/dev/null || true)"
    if grep -qw "${CONTROL_POD}" <<<"${endpoint_names}"; then
      pass "service/${service} endpoints include ${CONTROL_POD}"
    else
      fail "service/${service} endpoints do not include ${CONTROL_POD} (${endpoint_names:-<none>})"
    fi

    if [[ "${service}" == sounio-workspace-tailnet-* ]]; then
      external="$(jsonpath service "${service}" '{.status.loadBalancer.ingress[0].ip}')"
      if [[ -n "${external}" ]]; then
        pass "service/${service} has tailnet VIP ${external}"
      else
        fail "service/${service} has no tailnet VIP"
      fi
    fi
  done
}

check_legacy_not_live() {
  local app live_pods replicas kind name
  for app in "${LEGACY_APPS[@]}"; do
    live_pods="$("${KCTL[@]}" -n "${NAMESPACE}" get pods \
      -l "app.kubernetes.io/name=${app}" \
      --field-selector=status.phase!=Succeeded,status.phase!=Failed \
      -o jsonpath='{range .items[*]}{.metadata.name}{" "}{.status.phase}{"\n"}{end}' 2>/dev/null || true)"
    if [[ -z "${live_pods}" ]]; then
      pass "no live legacy pod for app=${app}"
    else
      fail "legacy app=${app} has live pod(s): ${live_pods//$'\n'/; }"
    fi
  done

  for item in deployment/sounio-workspace deployment/sounio-workspace-local statefulset/sounio-workspace-habitat statefulset/sounio-workspace-ha; do
    kind="${item%%/*}"
    name="${item##*/}"
    replicas="$(jsonpath "${kind}" "${name}" '{.spec.replicas}')"
    if [[ -z "${replicas}" ]]; then
      warn "${item} not found"
    elif [[ "${replicas}" == "0" ]]; then
      pass "${item} replicas=0"
    else
      fail "${item} should remain replicas=0, got ${replicas}"
    fi
  done
}

check_zellij_session() {
  local tabs
  tabs="$("${KCTL[@]}" -n "${NAMESPACE}" exec "${CONTROL_POD}" -c workspace-ssh -- \
    su -s /bin/bash openvscode-server -c '
      export HOME=/workspace/.home/openvscode-server
      export XDG_CONFIG_HOME="$HOME/.config"
      export XDG_DATA_HOME="$HOME/.local/share"
      export ZELLIJ_SESSION_NAME=sounio-dev
      zellij action list-tabs 2>/dev/null
    ' 2>/dev/null | sed -E 's/\x1B\[[0-9;]*[A-Za-z]//g' || true)"

  if [[ -z "${tabs}" ]]; then
    warn "could not read sounio-dev Zellij tabs from ${CONTROL_POD}"
    return
  fi

  local expected=(repo claude-1 claude-2 claude-3 codex-1 codex-2 codex-3 kimi-cli1 kimi-cli2 grok-cli1 grok-cli2)
  local index name pos
  for index in "${!expected[@]}"; do
    name="${expected[$index]}"
    pos="$(awk -v n="${name}" '$3 == n {print $2; exit}' <<<"${tabs}")"
    if [[ "${pos}" == "${index}" ]]; then
      pass "zellij tab ${name} position=${pos}"
    else
      fail "zellij tab ${name} expected position=${index}, got ${pos:-<missing>}"
    fi
  done
}

main() {
  pick_kubectl

  section "Sounio Workspace Contract"
  echo "expected_control=${CONTROL_APP}"
  echo "namespace=${NAMESPACE}"

  section "Control Workload"
  check_control_workload

  section "Stable Services"
  check_stable_services

  section "Legacy Surfaces"
  check_legacy_not_live

  section "Zellij"
  check_zellij_session

  echo
  if [[ "${FAILURES}" -gt 0 ]]; then
    echo "Sounio workspace contract doctor FAILED: ${FAILURES} failure(s), ${WARNINGS} warning(s)."
    exit 1
  fi

  if [[ "${WARNINGS}" -gt 0 ]]; then
    echo "Sounio workspace contract doctor passed with ${WARNINGS} warning(s)."
  else
    echo "Sounio workspace contract doctor passed cleanly."
  fi
}

main "$@"
