#!/usr/bin/env bash
set -euo pipefail

SCRIPT_PATH="${BASH_SOURCE[0]}"
if command -v readlink >/dev/null 2>&1; then
  SCRIPT_PATH="$(readlink -f "${SCRIPT_PATH}")"
fi
SCRIPT_DIR="$(cd -- "$(dirname -- "${SCRIPT_PATH}")" && pwd)"
SYSTEMD_DIR="${SCRIPT_DIR}/systemd"
SERVICE="darwin-fabric-storage-admission-reconcile.service"
TIMER="darwin-fabric-storage-admission-reconcile.timer"
ENABLE=0
RUN_ONCE=0

usage() {
  cat <<'EOF'
usage: install-fabric-storage-admission-timer.sh [--enable] [--run-once]

Install the Darwin Kueue fabric/storage AdmissionCheck reconciler systemd unit.

Default behavior installs the service/timer files and reloads systemd, but does
not enable the timer. Use --enable only after deciding that
ClusterQueue/sounio-hpc may enforce AdmissionCheck/fabric-storage-readiness.
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

sudo -n install -m 0644 "${SYSTEMD_DIR}/${SERVICE}" "/etc/systemd/system/${SERVICE}"
sudo -n install -m 0644 "${SYSTEMD_DIR}/${TIMER}" "/etc/systemd/system/${TIMER}"
sudo -n systemctl daemon-reload

if [[ "${ENABLE}" -eq 1 ]]; then
  sudo -n systemctl enable --now "${TIMER}"
  echo "enabled ${TIMER}"
else
  echo "installed ${SERVICE} and ${TIMER}; timer not enabled"
fi

if [[ "${RUN_ONCE}" -eq 1 ]]; then
  sudo -n systemctl start "${SERVICE}"
  sudo -n systemctl status --no-pager "${SERVICE}" | sed -n '1,24p'
fi
