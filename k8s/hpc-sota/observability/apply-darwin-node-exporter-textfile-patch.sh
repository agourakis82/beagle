#!/usr/bin/env bash
set -euo pipefail

NS="${NS:-darwin-observability-system}"
NAME="${NAME:-darwin-node-exporter}"

if sudo -n kubectl -n "${NS}" get ds "${NAME}" -o jsonpath='{.spec.template.spec.containers[0].args}' | grep -q -- '--collector.textfile.directory=/host/root/var/lib/node_exporter/textfile'; then
  echo "node-exporter textfile collector already enabled"
else
  echo "enabling node-exporter textfile collector"
  sudo -n kubectl -n "${NS}" patch ds "${NAME}" --type='json' -p='[
    {"op":"add","path":"/spec/template/spec/containers/0/args/-","value":"--collector.textfile.directory=/host/root/var/lib/node_exporter/textfile"}
  ]'
fi

echo "waiting for daemonset rollout"
sudo -n kubectl -n "${NS}" rollout status ds/"${NAME}" --timeout=180s
