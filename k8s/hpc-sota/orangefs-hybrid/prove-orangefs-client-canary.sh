#!/usr/bin/env bash
set -euo pipefail

TARGET_HOST="${TARGET_HOST:?set TARGET_HOST like root@10.100.100.4}"
TARGET_PASS="${TARGET_PASS:-Urso1982!}"
TARGET_NAME="${TARGET_NAME:-$(echo "$TARGET_HOST" | sed 's/.*@//; s/[^A-Za-z0-9._-]/_/g')}"
SOURCE_HOST="${SOURCE_HOST:-root@10.100.100.2}"
SOURCE_PASS="${SOURCE_PASS:-Urso1982!}"
FS_URI="${FS_URI:-tcp://10.100.100.2:3334/orangefs_lab_2n}"

SSH_TARGET=(sshpass -p "$TARGET_PASS" ssh -o StrictHostKeyChecking=no "$TARGET_HOST")
SSH_SOURCE=(sshpass -p "$SOURCE_PASS" ssh -o StrictHostKeyChecking=no "$SOURCE_HOST")
SCP_TARGET=(sshpass -p "$TARGET_PASS" scp -o StrictHostKeyChecking=no)

REMOTE_BASE=/var/lib/orangefs-lab/client-canary
REMOTE_BIN="$REMOTE_BASE/bin"
REMOTE_LIB="$REMOTE_BASE/lib"
REMOTE_RUN="$REMOTE_BASE/run"
REMOTE_MNT="$REMOTE_BASE/mnt"
REMOTE_LOG="$REMOTE_RUN/pvfs2-client.log"
REMOTE_CANARY="$REMOTE_MNT/orangefs-client-canary.txt"
STAGE_DIR="$(mktemp -d)"

cleanup_local() {
    rm -rf "$STAGE_DIR"
}
trap cleanup_local EXIT

cleanup_remote='
set +e
python3 - "'"$REMOTE_MNT"'" <<'"'"'EOF'"'"' >/dev/null 2>&1
import ctypes
import sys
mnt = sys.argv[1].encode()
libc = ctypes.CDLL("libc.so.6", use_errno=True)
libc.umount2(mnt, 0)
EOF
if [[ -f "'"$REMOTE_RUN"'/client.pid" ]]; then
  kill "$(cat "'"$REMOTE_RUN"'/client.pid")" >/dev/null 2>&1 || true
fi
'

"${SSH_TARGET[@]}" "bash -s" <<'REMOTE'
set -euo pipefail
modprobe orangefs
mkdir -p /var/lib/orangefs-lab/client-canary/bin \
         /var/lib/orangefs-lab/client-canary/lib \
         /var/lib/orangefs-lab/client-canary/run \
         /var/lib/orangefs-lab/client-canary/mnt
REMOTE

"${SSH_SOURCE[@]}" "cat /zfast/orangefs-lab/orangefs-build-serveronly-dyn/src/apps/kernel/linux/pvfs2-client" > "$STAGE_DIR/pvfs2-client"
"${SSH_SOURCE[@]}" "cat /zfast/orangefs-lab/orangefs-build-serveronly-dyn/src/apps/kernel/linux/pvfs2-client-core" > "$STAGE_DIR/pvfs2-client-core"
"${SSH_SOURCE[@]}" "cat /zfast/orangefs-lab/orangefs-build-serveronly-dyn/lib/libpvfs2.so" > "$STAGE_DIR/libpvfs2.so"
"${SSH_SOURCE[@]}" "cat /zfast/orangefs-lab/orangefs-build-serveronly-dyn/lib/libpvfs2.so.2" > "$STAGE_DIR/libpvfs2.so.2"
"${SSH_SOURCE[@]}" "cat /zfast/orangefs-lab/orangefs-build-serveronly-dyn/lib/libpvfs2.so.2.10.0" > "$STAGE_DIR/libpvfs2.so.2.10.0"

"${SCP_TARGET[@]}" "$STAGE_DIR/pvfs2-client" "${TARGET_HOST}:${REMOTE_BIN}/pvfs2-client" >/dev/null
"${SCP_TARGET[@]}" "$STAGE_DIR/pvfs2-client-core" "${TARGET_HOST}:${REMOTE_BIN}/pvfs2-client-core" >/dev/null
"${SCP_TARGET[@]}" "$STAGE_DIR/libpvfs2.so" "${TARGET_HOST}:${REMOTE_LIB}/libpvfs2.so" >/dev/null
"${SCP_TARGET[@]}" "$STAGE_DIR/libpvfs2.so.2" "${TARGET_HOST}:${REMOTE_LIB}/libpvfs2.so.2" >/dev/null
"${SCP_TARGET[@]}" "$STAGE_DIR/libpvfs2.so.2.10.0" "${TARGET_HOST}:${REMOTE_LIB}/libpvfs2.so.2.10.0" >/dev/null

"${SSH_TARGET[@]}" "bash -s" <<REMOTE
set -euo pipefail
trap '$cleanup_remote' EXIT
chmod 0755 "$REMOTE_BIN/pvfs2-client" "$REMOTE_BIN/pvfs2-client-core"
rm -f "$REMOTE_LOG" "$REMOTE_CANARY"
LD_LIBRARY_PATH="$REMOTE_LIB" "$REMOTE_BIN/pvfs2-client" -f -L "$REMOTE_LOG" -p "$REMOTE_BIN/pvfs2-client-core" >/dev/null 2>&1 &
echo \$! > "$REMOTE_RUN/client.pid"
sleep 4
python3 - "$REMOTE_MNT" <<'EOF'
import ctypes
import os
import sys
mnt = sys.argv[1]
libc = ctypes.CDLL("libc.so.6", use_errno=True)
source = ${FS_URI@Q}.encode()
fstype = b"pvfs2"
target = mnt.encode()
if libc.mount(source, target, fstype, 0, None) != 0:
    err = ctypes.get_errno()
    raise OSError(err, os.strerror(err))
EOF
mount | grep -F "$REMOTE_MNT"
printf "orangefs-client-canary-%s-%s\n" "$TARGET_NAME" "\$(date -Iseconds)" > "$REMOTE_CANARY"
cat "$REMOTE_CANARY"
ls -la "$REMOTE_MNT"
REMOTE
