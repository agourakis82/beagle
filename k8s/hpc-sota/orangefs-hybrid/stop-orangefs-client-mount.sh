#!/usr/bin/env bash
set -euo pipefail

TARGET_HOST="${TARGET_HOST:?set TARGET_HOST like root@10.100.100.4}"
TARGET_PASS="${TARGET_PASS:?defina TARGET_PASS no ambiente (nunca no script); prefira chave SSH}"

SSH_TARGET=(sshpass -p "$TARGET_PASS" ssh -o StrictHostKeyChecking=no "$TARGET_HOST")
REMOTE_BASE=/var/lib/orangefs-lab/client-runtime
REMOTE_BIN="$REMOTE_BASE/bin"
REMOTE_RUN="$REMOTE_BASE/run"
REMOTE_LOG="$REMOTE_RUN/pvfs2-client.log"
REMOTE_MNT="$REMOTE_BASE/mnt"

"${SSH_TARGET[@]}" "bash -s" <<REMOTE
set -euo pipefail
python3 - <<'EOF' >/dev/null 2>&1 || true
import ctypes
mnt=b"$REMOTE_MNT"
libc=ctypes.CDLL("libc.so.6", use_errno=True)
libc.umount2(mnt,0)
EOF
pkill -f "$REMOTE_BIN/pvfs2-client -f -L $REMOTE_LOG" >/dev/null 2>&1 || true
ps -ef | grep pvfs2-client | grep -v grep || true
REMOTE
