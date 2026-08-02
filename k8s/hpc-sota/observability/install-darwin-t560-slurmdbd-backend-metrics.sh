#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"

sudo -n install -d -m 0755 /var/lib/node_exporter/textfile
sudo -n install -m 0755 "${SCRIPT_DIR}/t560-slurmdbd-backend-metrics.sh" /usr/local/sbin/darwin-slurmdbd-backend-metrics.sh
sudo -n install -m 0644 "${SCRIPT_DIR}/darwin-t560-slurmdbd-backend-metrics.service" /etc/systemd/system/darwin-t560-slurmdbd-backend-metrics.service
sudo -n install -m 0644 "${SCRIPT_DIR}/darwin-t560-slurmdbd-backend-metrics.timer" /etc/systemd/system/darwin-t560-slurmdbd-backend-metrics.timer

sudo -n systemctl daemon-reload
sudo -n systemctl enable --now darwin-t560-slurmdbd-backend-metrics.timer
sudo -n systemctl start darwin-t560-slurmdbd-backend-metrics.service

echo "installed darwin-t560-slurmdbd-backend-metrics timer/service"
