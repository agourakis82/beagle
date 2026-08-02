#!/usr/bin/env bash
set -euo pipefail

KUBECONFIG_PATH="${KUBECONFIG_PATH:-/etc/kubernetes/admin.conf}"
DCGM_MIN_TARGETS="${DCGM_MIN_TARGETS:-3}"
FAILURES=0
WARNINGS=0

pick_kubectl() {
  if kubectl --kubeconfig "$KUBECONFIG_PATH" version --request-timeout=5s >/dev/null 2>&1; then
    KCTL=(kubectl --kubeconfig "$KUBECONFIG_PATH")
    return
  fi

  if command -v sudo >/dev/null 2>&1 && sudo -n kubectl --kubeconfig "$KUBECONFIG_PATH" version --request-timeout=5s >/dev/null 2>&1; then
    KCTL=(sudo kubectl --kubeconfig "$KUBECONFIG_PATH")
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

require_binary() {
  local bin="$1"
  if command -v "$bin" >/dev/null 2>&1; then
    pass "binary present: $bin"
  else
    fail "required binary missing: $bin"
  fi
}

check_object() {
  local kind="$1"
  local namespace="$2"
  local name="$3"

  if "${KCTL[@]}" -n "$namespace" get "$kind" "$name" >/dev/null 2>&1; then
    pass "$kind/$name present in $namespace"
  else
    fail "$kind/$name missing in $namespace"
  fi
}

check_namespace() {
  local namespace="$1"
  if "${KCTL[@]}" get namespace "$namespace" >/dev/null 2>&1; then
    pass "namespace/$namespace present"
  else
    fail "namespace/$namespace missing"
  fi
}

check_deployment_ready() {
  local namespace="$1"
  local name="$2"
  local desired available

  desired="$("${KCTL[@]}" -n "$namespace" get deploy "$name" -o jsonpath='{.status.replicas}' 2>/dev/null || true)"
  available="$("${KCTL[@]}" -n "$namespace" get deploy "$name" -o jsonpath='{.status.availableReplicas}' 2>/dev/null || true)"

  if [[ -z "$desired" ]]; then
    fail "deployment/$name missing in $namespace"
    return
  fi

  if [[ "${available:-0}" -ge 1 ]]; then
    pass "deployment/$name available replicas=${available:-0}"
  else
    fail "deployment/$name has no available replicas"
  fi
}

check_statefulset_ready() {
  local namespace="$1"
  local name="$2"
  local ready

  ready="$("${KCTL[@]}" -n "$namespace" get statefulset "$name" -o jsonpath='{.status.readyReplicas}' 2>/dev/null || true)"
  if [[ "${ready:-0}" -ge 1 ]]; then
    pass "statefulset/$name ready replicas=${ready:-0}"
  else
    fail "statefulset/$name has no ready replicas"
  fi
}

check_dashboard_configmap() {
  local name="$1"
  local label

  label="$("${KCTL[@]}" -n darwin-platform get cm "$name" -o jsonpath='{.metadata.labels.grafana_dashboard}' 2>/dev/null || true)"
  if [[ "$label" == "1" ]]; then
    pass "dashboard configmap/$name labeled for Grafana"
  else
    fail "dashboard configmap/$name missing grafana_dashboard=1"
  fi
}

query_prometheus_targets() {
  local prom_ip
  prom_ip="$("${KCTL[@]}" -n darwin-platform get svc darwin-observability-prometheus -o jsonpath='{.spec.clusterIP}' 2>/dev/null || true)"
  if [[ -z "$prom_ip" ]]; then
    fail "service/darwin-observability-prometheus missing in darwin-platform"
    return 1
  fi

  PROM_TARGETS_JSON="$(curl -fsS "http://${prom_ip}:9090/api/v1/targets")" || {
    fail "unable to query Prometheus targets API at http://${prom_ip}:9090"
    return 1
  }

  pass "Prometheus targets API reachable at http://${prom_ip}:9090"
  return 0
}

check_job_target_health() {
  local job="$1"
  local minimum="$2"
  local total healthy

  total="$(jq --arg job "$job" '[.data.activeTargets[] | select(.labels.job == $job)] | length' <<<"$PROM_TARGETS_JSON")"
  healthy="$(jq --arg job "$job" '[.data.activeTargets[] | select(.labels.job == $job and .health == "up")] | length' <<<"$PROM_TARGETS_JSON")"

  if [[ "$total" -eq 0 ]]; then
    fail "Prometheus has zero active targets for job=$job"
    return
  fi

  if [[ "$healthy" -ge "$minimum" ]]; then
    pass "job=$job healthy targets ${healthy}/${total} (expected >= ${minimum})"
  else
    warn "job=$job healthy targets ${healthy}/${total} (expected >= ${minimum})"
  fi
}

print_firing_alerts() {
  local prom_ip alerts_json firing_count
  prom_ip="$("${KCTL[@]}" -n darwin-platform get svc darwin-observability-prometheus -o jsonpath='{.spec.clusterIP}' 2>/dev/null || true)"
  alerts_json="$(curl -fsS "http://${prom_ip}:9090/api/v1/query?query=ALERTS%7Balertstate%3D%22firing%22%7D" 2>/dev/null || true)"
  if [[ -z "$alerts_json" ]]; then
    warn "could not query currently firing ALERTS metric"
    return
  fi

  firing_count="$(jq '[.data.result[] | select(.metric.alertname | startswith("Darwin") or startswith("Ceph"))] | length' <<<"$alerts_json")"
  pass "firing alert samples from this layer: ${firing_count}"
}

main() {
  require_binary curl
  require_binary jq
  require_binary kubectl
  pick_kubectl

  echo "== Namespaces =="
  check_namespace darwin-platform
  check_namespace darwin-observability-system
  check_namespace beagle

  echo
  echo "== Rule bundles and alert routing =="
  check_object prometheusrule darwin-platform darwin-gpu-ceph-storage-rules
  check_object prometheusrule darwin-platform darwin-hpc-control-room-rules
  check_object prometheusrule darwin-platform darwin-sounio-slurm-ops-rules
  check_object prometheusrule darwin-platform darwin-tailscale-route-rules
  check_object prometheusrule darwin-platform darwin-slurmdbd-backend-rules
  check_object alertmanagerconfig darwin-platform darwin-alert-routing
  check_deployment_ready darwin-platform darwin-alert-sink

  echo
  echo "== Dashboards =="
  check_dashboard_configmap darwin-dashboard-gpu-ceph-storage
  check_dashboard_configmap darwin-dashboard-hpc-control-room
  check_dashboard_configmap darwin-dashboard-sounio-dev-loop
  check_dashboard_configmap darwin-dashboard-slurm-ops
  check_dashboard_configmap darwin-dashboard-sounio-compiler-pipeline

  echo
  echo "== ServiceMonitors and workloads =="
  check_object servicemonitor darwin-observability-system darwin-dcgm-exporter
  check_object servicemonitor darwin-observability-system ceph-mgr-prometheus
  check_statefulset_ready beagle sounio-workspace-control

  echo
  echo "== Prometheus target health =="
  if query_prometheus_targets; then
    check_job_target_health darwin-dcgm-exporter "$DCGM_MIN_TARGETS"
    check_job_target_health ceph-mgr-prometheus 1
    if jq -e '.data.result | type=="array"' <<<"$(curl -fsS "http://$("${KCTL[@]}" -n darwin-platform get svc darwin-observability-prometheus -o jsonpath='{.spec.clusterIP}'):9090/api/v1/query?query=darwin_slurmdbd_current_backend_healthy")" >/dev/null 2>&1; then
      pass "Prometheus query for darwin_slurmdbd_current_backend_healthy is reachable"
    else
      warn "could not query darwin_slurmdbd_current_backend_healthy from Prometheus"
    fi
    print_firing_alerts
  fi

  echo
  if [[ "$FAILURES" -gt 0 ]]; then
    echo "Observability verification finished with ${FAILURES} failure(s) and ${WARNINGS} warning(s)."
    exit 1
  fi

  if [[ "$WARNINGS" -gt 0 ]]; then
    echo "Observability verification finished with ${WARNINGS} warning(s)."
  else
    echo "Observability verification passed cleanly."
  fi
}

main "$@"
