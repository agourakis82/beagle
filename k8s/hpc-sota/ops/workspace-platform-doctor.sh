#!/usr/bin/env bash
set -euo pipefail

ROOT="/home/devsounio/beagle/k8s"
CATALOG_DIR="${ROOT}/workspace-platform/catalog"
CATALOG_VALIDATE="${ROOT}/workspace-platform/scripts/validate-project-catalog.sh"
KUBECONFIG_PATH="${KUBECONFIG_PATH:-/etc/kubernetes/admin.conf}"
FAILURES=0
WARNINGS=0
REGISTRY_DEFAULTS_FILE="${ROOT}/workspace-platform/image-defaults.env"

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

check_binary() {
  local bin="$1"
  if command -v "$bin" >/dev/null 2>&1; then
    pass "binary present: ${bin}"
  else
    fail "required binary missing: ${bin}"
  fi
}

check_object() {
  local namespace="$1"
  local kind="$2"
  local name="$3"

  if "${KCTL[@]}" -n "${namespace}" get "${kind}" "${name}" >/dev/null 2>&1; then
    pass "${kind}/${name} present in ${namespace}"
  else
    fail "${kind}/${name} missing in ${namespace}"
  fi
}

check_statefulset_ready() {
  local namespace="$1"
  local name="$2"
  local ready

  ready="$("${KCTL[@]}" -n "${namespace}" get statefulset "${name}" -o jsonpath='{.status.readyReplicas}' 2>/dev/null || true)"
  if [[ "${ready:-0}" -ge 1 ]]; then
    pass "statefulset/${name} ready replicas=${ready:-0}"
  else
    fail "statefulset/${name} has no ready replicas"
  fi
}

check_service_external_ip() {
  local namespace="$1"
  local name="$2"
  local ip

  ip="$("${KCTL[@]}" -n "${namespace}" get svc "${name}" -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null || true)"
  if [[ -n "${ip}" ]]; then
    pass "service/${name} has external ip ${ip}"
  else
    fail "service/${name} has no external ip"
  fi
}

check_proxygroup_ready() {
  local namespace="$1"
  local name="$2"
  local ready

  ready="$("${KCTL[@]}" -n "${namespace}" get proxygroup "${name}" -o jsonpath='{range .status.conditions[*]}{.type}={.status}{" "}{end}' 2>/dev/null || true)"
  if [[ "${ready}" == *"ProxyGroupReady=True"* ]]; then
    pass "proxygroup/${name} is ready"
  else
    fail "proxygroup/${name} is not ready"
  fi
}

check_catalog_counts() {
  local mode count
  for mode in always-on warm cold; do
    count="$(find "${CATALOG_DIR}/${mode}" -maxdepth 1 -type f -name '*.env' 2>/dev/null | wc -l | tr -d ' ')"
    pass "catalog/${mode} env files=${count}"
  done
}

check_catalog_validation() {
  if [[ ! -x "${CATALOG_VALIDATE}" ]]; then
    fail "catalog validator missing: ${CATALOG_VALIDATE}"
    return
  fi

  if bash "${CATALOG_VALIDATE}" "${CATALOG_DIR}" >/tmp/workspace-platform-doctor.catalog.out 2>&1; then
    pass "workspace catalog validates against the live cluster"
  else
    warn "workspace catalog validation reported issues"
    sed -n '1,80p' /tmp/workspace-platform-doctor.catalog.out
  fi
}

check_no_localhost_refs() {
  local label="$1"
  shift
  local hits
  hits="$(rg -n "localhost/" "$@" 2>/dev/null || true)"
  if [[ -z "${hits}" ]]; then
    pass "${label} has no localhost image refs"
  else
    warn "${label} still contains localhost image refs"
    printf '%s\n' "${hits}" | sed -n '1,40p'
  fi
}

check_live_image_ref() {
  local namespace="$1"
  local kind="$2"
  local name="$3"
  local refs
  refs="$("${KCTL[@]}" -n "${namespace}" get "${kind}" "${name}" -o jsonpath='{range .spec.template.spec.containers[*]}{.image}{"\n"}{end}' 2>/dev/null || true)"
  if [[ -z "${refs}" ]]; then
    fail "${kind}/${name} images could not be read"
    return
  fi
  if grep -q 'localhost/' <<<"${refs}"; then
    warn "${kind}/${name} is still localhost-backed"
    printf '%s\n' "${refs}" | sed -n '1,20p'
  else
    pass "${kind}/${name} is registry-backed"
  fi
}

main() {
  check_binary kubectl
  pick_kubectl

  echo "== Workspace platform common layer =="
  pass "catalog root: ${CATALOG_DIR}"

  echo
  echo "== Catalog shape =="
  check_catalog_counts
  check_catalog_validation

  echo
  echo "== Shared workspace inputs =="
  check_object beagle configmap sounio-workspace-config
  check_object beagle secret sounio-workspace-ssh-authorized-keys
  check_object beagle secret beagle-workspace-ssh-authorized-keys
  if [[ -f "${REGISTRY_DEFAULTS_FILE}" ]]; then
    pass "registry defaults file present: ${REGISTRY_DEFAULTS_FILE}"
  else
    warn "registry defaults file missing: ${REGISTRY_DEFAULTS_FILE}"
  fi

  echo
  echo "== Registry backing =="
  check_no_localhost_refs "workspace catalog envs" "${CATALOG_DIR}"
  check_live_image_ref beagle deployment project-cockpit
  check_live_image_ref beagle statefulset sounio-workspace-control

  echo
  echo "== Promoted Sounio surfaces =="
  check_object beagle service sounio-workspace
  check_service_external_ip beagle sounio-workspace-tailnet-http
  check_service_external_ip beagle sounio-workspace-tailnet-ssh
  check_proxygroup_ready tailscale sounio-workspace-ingress
  if bash "${ROOT}/hpc-sota/ops/sounio-workspace-contract-doctor.sh"; then
    pass "Sounio workspace contract is current"
  else
    fail "Sounio workspace contract doctor reported attention"
  fi

  echo
  echo "== Decision reminder =="
  cat <<'EOF'
- If this doctor is already yellow, do not onboard another project yet.
- New projects should enter through workspace-platform catalog files, not ad hoc manifests.
- Promote one project at a time.
EOF

  echo
  if [[ "${FAILURES}" -gt 0 ]]; then
    echo "Workspace platform doctor finished with ${FAILURES} failure(s) and ${WARNINGS} warning(s)."
    exit 1
  fi

  if [[ "${WARNINGS}" -gt 0 ]]; then
    echo "Workspace platform doctor finished with ${WARNINGS} warning(s)."
  else
    echo "Workspace platform doctor passed cleanly."
  fi
}

main "$@"
