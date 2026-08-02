#!/usr/bin/env bash
set -euo pipefail

SCRIPT_PATH="${BASH_SOURCE[0]}"
if command -v readlink >/dev/null 2>&1; then
  SCRIPT_PATH="$(readlink -f "${SCRIPT_PATH}")"
fi
SCRIPT_DIR="$(cd -- "$(dirname -- "${SCRIPT_PATH}")" && pwd)"
SYSTEMD_DIR="${SCRIPT_DIR}/systemd"
WATCH_SERVICE="darwin-gpu-fabric-smoke-watch.service"
WATCH_TIMER="darwin-gpu-fabric-smoke-watch.timer"
RUN_ON_READY_SERVICE="darwin-gpu-fabric-smoke-run-on-ready.service"
ENABLE=0
RUN_ONCE=0

usage() {
  cat <<'EOF'
usage: install-gpu-fabric-smoke-watch-timer.sh [--enable] [--run-once]

Install the Darwin GPU fabric smoke watcher systemd units.

Default behavior installs the service/timer files and reloads systemd, but does
not enable the timer. The installed timer only runs the safe watch mode; it
never creates smoke jobs. Use the run-on-ready service manually during an
explicit GPU test window.
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --enable)
      ENABLE=1
      shift
      ;;
    --run-once)
      RUN_ONCE=1
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      usage >&2
      echo "unknown argument: $1" >&2
      exit 2
      ;;
  esac
done

chmod +x "${SCRIPT_DIR}/gpu-fabric-smoke-watch.sh"
sudo -n install -m 0644 "${SYSTEMD_DIR}/${WATCH_SERVICE}" "/etc/systemd/system/${WATCH_SERVICE}"
sudo -n install -m 0644 "${SYSTEMD_DIR}/${WATCH_TIMER}" "/etc/systemd/system/${WATCH_TIMER}"
sudo -n install -m 0644 "${SYSTEMD_DIR}/${RUN_ON_READY_SERVICE}" "/etc/systemd/system/${RUN_ON_READY_SERVICE}"
sudo -n systemctl daemon-reload

if [[ "${ENABLE}" -eq 1 ]]; then
  sudo -n systemctl enable --now "${WATCH_TIMER}"
  echo "enabled ${WATCH_TIMER}"
else
  echo "installed ${WATCH_SERVICE}, ${WATCH_TIMER}, and ${RUN_ON_READY_SERVICE}; timer not enabled"
fi

if [[ "${RUN_ONCE}" -eq 1 ]]; then
  sudo -n systemctl start "${WATCH_SERVICE}" || true
  sudo -n systemctl status --no-pager "${WATCH_SERVICE}" | sed -n '1,28p'
fi
