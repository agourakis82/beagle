#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
SYSTEMD_DIR="${SCRIPT_DIR%/scripts}/systemd"

sudo -n install -m 0644 \
  "${SYSTEMD_DIR}/slurm-pilot-gpuorangefs-autoheal.service" \
  /etc/systemd/system/slurm-pilot-gpuorangefs-autoheal.service
sudo -n install -m 0644 \
  "${SYSTEMD_DIR}/slurm-pilot-gpuorangefs-autoheal.timer" \
  /etc/systemd/system/slurm-pilot-gpuorangefs-autoheal.timer

sudo -n systemctl daemon-reload
sudo -n systemctl enable --now slurm-pilot-gpuorangefs-autoheal.timer
sudo -n systemctl start slurm-pilot-gpuorangefs-autoheal.service

echo "installed slurm-pilot-gpuorangefs-autoheal timer/service"
