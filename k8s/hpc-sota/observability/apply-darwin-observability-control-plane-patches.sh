#!/usr/bin/env bash
set -euo pipefail

KUBECONFIG_PATH="${KUBECONFIG_PATH:-/etc/kubernetes/admin.conf}"
NS="${NS:-darwin-platform}"

kc() {
  sudo kubectl --kubeconfig="${KUBECONFIG_PATH}" "$@"
}

control_plane_patch='{
  "spec": {
    "template": {
      "spec": {
        "nodeSelector": {
          "node-role.kubernetes.io/control-plane": ""
        },
        "tolerations": [
          {
            "key": "node-role.kubernetes.io/control-plane",
            "operator": "Exists",
            "effect": "NoSchedule"
          }
        ]
      }
    }
  }
}'

control_plane_cr_patch='{
  "spec": {
    "nodeSelector": {
      "node-role.kubernetes.io/control-plane": ""
    },
    "tolerations": [
      {
        "key": "node-role.kubernetes.io/control-plane",
        "operator": "Exists",
        "effect": "NoSchedule"
      }
    ]
  }
}'

echo "== patch deployments onto control-plane =="
kc -n "${NS}" patch deployment darwin-observability-grafana --type merge -p "${control_plane_patch}"
kc -n "${NS}" patch deployment darwin-observability-kube-state-metrics --type merge -p "${control_plane_patch}"
kc -n "${NS}" patch deployment darwin-observability-operator --type merge -p "${control_plane_patch}"

echo "== patch Prometheus and Alertmanager CRs onto control-plane =="
kc -n "${NS}" patch prometheus darwin-observability-prometheus --type merge -p "${control_plane_cr_patch}"
kc -n "${NS}" patch alertmanager darwin-observability-alertmanager --type merge -p "${control_plane_cr_patch}"

echo "== recycle deployment-backed pods from not-ready nodes =="
kc -n "${NS}" delete pod -l app.kubernetes.io/name=grafana --ignore-not-found --grace-period=0 --force || true
kc -n "${NS}" delete pod -l app.kubernetes.io/name=kube-state-metrics --ignore-not-found --grace-period=0 --force || true
kc -n "${NS}" delete pod -l app=kube-prometheus-stack-operator --ignore-not-found --grace-period=0 --force || true

echo "== wait for deployments =="
kc -n "${NS}" rollout status deploy/darwin-observability-operator --timeout=180s
kc -n "${NS}" rollout status deploy/darwin-observability-kube-state-metrics --timeout=180s
kc -n "${NS}" rollout status deploy/darwin-observability-grafana --timeout=180s

echo "== recycle statefulset-backed pods after operator reconciliation =="
kc -n "${NS}" delete pod alertmanager-darwin-observability-alertmanager-0 --ignore-not-found --grace-period=0 --force || true
kc -n "${NS}" delete pod prometheus-darwin-observability-prometheus-0 --ignore-not-found --grace-period=0 --force || true

echo "== wait for statefulsets =="
kc -n "${NS}" rollout status statefulset/alertmanager-darwin-observability-alertmanager --timeout=180s
kc -n "${NS}" rollout status statefulset/prometheus-darwin-observability-prometheus --timeout=180s

echo "== final pod summary =="
kc -n "${NS}" get pods -o wide
