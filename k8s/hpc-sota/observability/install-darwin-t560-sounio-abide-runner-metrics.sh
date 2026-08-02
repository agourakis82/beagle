#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

install -m 0755 "${ROOT_DIR}/t560-sounio-abide-runner-metrics.sh" /usr/local/bin/t560-sounio-abide-runner-metrics.sh

sed 's|/home/devsounio/beagle/k8s/hpc-sota/observability/t560-sounio-abide-runner-metrics.sh|/usr/local/bin/t560-sounio-abide-runner-metrics.sh|g' \
  "${ROOT_DIR}/darwin-t560-sounio-abide-runner-metrics.service" \
  | install -m 0644 /dev/stdin /etc/systemd/system/darwin-t560-sounio-abide-runner-metrics.service

install -m 0644 "${ROOT_DIR}/darwin-t560-sounio-abide-runner-metrics.timer" /etc/systemd/system/darwin-t560-sounio-abide-runner-metrics.timer

systemctl daemon-reload
systemctl enable --now darwin-t560-sounio-abide-runner-metrics.timer
systemctl start darwin-t560-sounio-abide-runner-metrics.service
