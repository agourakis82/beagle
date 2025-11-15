#!/usr/bin/env bash
set -euo pipefail

# Linux -> Windows sync (rsync over SSH)
# Required envs:
#   BEAGLE_SYNC_HOST   (e.g., 10.100.0.1 or 10.100.0.2)
#   BEAGLE_SYNC_USER   (e.g., maria or windows ssh user)
#   BEAGLE_REMOTE_PATH (e.g., /mnt/e/workspace/beagle-remote) - remote POSIX path for Windows share
# Optional:
#   BEAGLE_LOCAL_PATH  (default: /home/maria/beagle)
#   BEAGLE_RSYNC_EXCLUDES (default: sync/excludes.rsync)
#   BEAGLE_SSH_OPTS    (e.g., -p 22 -o StrictHostKeyChecking=no)

LOCAL_PATH="${BEAGLE_LOCAL_PATH:-/home/maria/beagle}"
EXCLUDES_FILE="${BEAGLE_RSYNC_EXCLUDES:-${LOCAL_PATH}/sync/excludes.rsync}"
HOST="${BEAGLE_SYNC_HOST:?BEAGLE_SYNC_HOST required}"
USER="${BEAGLE_SYNC_USER:?BEAGLE_SYNC_USER required}"
REMOTE_PATH="${BEAGLE_REMOTE_PATH:?BEAGLE_REMOTE_PATH required}"
SSH_OPTS="${BEAGLE_SSH_OPTS:-}"

rsync -az --delete --info=stats2,progress2 \
  --exclude-from="${EXCLUDES_FILE}" \
  -e "ssh ${SSH_OPTS}" \
  "${LOCAL_PATH}/" "${USER}@${HOST}:${REMOTE_PATH}/"

echo "Sync Linux -> Windows completed: ${LOCAL_PATH} -> ${USER}@${HOST}:${REMOTE_PATH}"

