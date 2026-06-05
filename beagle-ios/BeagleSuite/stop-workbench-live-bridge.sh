#!/usr/bin/env bash
set -euo pipefail

systemctl --user stop beagle-workbench-cockpit-tunnel.service 2>/dev/null || true
systemctl --user stop project-cockpit-api.service 2>/dev/null || true
systemctl --user reset-failed beagle-workbench-cockpit-tunnel.service project-cockpit-api.service 2>/dev/null || true

echo "Beagle Workbench live bridge is stopped."
