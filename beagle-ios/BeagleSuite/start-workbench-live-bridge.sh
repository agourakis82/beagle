#!/usr/bin/env bash
set -euo pipefail

COCKPIT_ROOT="${COCKPIT_ROOT:-/home/devsounio/beagle/apps/project-cockpit}"
COCKPIT_PORT="${COCKPIT_PORT:-4370}"
COCKPIT_HOST="${COCKPIT_HOST:-127.0.0.1}"
BEAGLE_DATA_DIR="${BEAGLE_DATA_DIR:-/home/devsounio/.beagle-data}"
MAC_SSH="${MAC_SSH:-demetriosagourakis@macbook-pro-de-demetrios-2.tail21cbc4.ts.net}"

if [[ ! -d "${COCKPIT_ROOT}" ]]; then
  echo "missing cockpit root: ${COCKPIT_ROOT}" >&2
  exit 1
fi

systemctl --user stop project-cockpit-api.service 2>/dev/null || true
systemctl --user reset-failed project-cockpit-api.service 2>/dev/null || true
systemd-run --user \
  --unit=project-cockpit-api \
  --property="WorkingDirectory=${COCKPIT_ROOT}" \
  --setenv="PROJECT_COCKPIT_HOST=${COCKPIT_HOST}" \
  --setenv="PROJECT_COCKPIT_PORT=${COCKPIT_PORT}" \
  --setenv="BEAGLE_DATA_DIR=${BEAGLE_DATA_DIR}" \
  /usr/bin/node "${COCKPIT_ROOT}/server/index.mjs" >/dev/null

sleep 1
curl -fsS --max-time 20 "http://${COCKPIT_HOST}:${COCKPIT_PORT}/api/cluster/ops/summary" >/dev/null

systemctl --user stop beagle-workbench-cockpit-tunnel.service 2>/dev/null || true
systemctl --user reset-failed beagle-workbench-cockpit-tunnel.service 2>/dev/null || true
systemd-run --user \
  --unit=beagle-workbench-cockpit-tunnel \
  /usr/bin/ssh \
    -o ExitOnForwardFailure=yes \
    -o ServerAliveInterval=30 \
    -o ServerAliveCountMax=3 \
    -o BatchMode=yes \
    -N \
    -R "127.0.0.1:${COCKPIT_PORT}:${COCKPIT_HOST}:${COCKPIT_PORT}" \
    "${MAC_SSH}" >/dev/null

sleep 1
ssh -o BatchMode=yes -o ConnectTimeout=8 "${MAC_SSH}" \
  "curl -fsS --max-time 20 http://127.0.0.1:${COCKPIT_PORT}/api/cluster/ops/summary >/dev/null"

echo "Beagle Workbench live bridge is up."
echo "Mac endpoint: http://127.0.0.1:${COCKPIT_PORT}/api/cluster/ops/summary"
echo "Services:"
systemctl --user --no-pager --plain status project-cockpit-api.service beagle-workbench-cockpit-tunnel.service | sed -n '1,80p'
