#!/usr/bin/env bash
set -euo pipefail

ACTION="${1:-start}"

BASE="${BASE:-/var/lib/orangefs-lab/client-runtime}"
BIN="${BIN:-$BASE/bin}"
LIB="${LIB:-$BASE/lib}"
RUN="${RUN:-$BASE/run}"
MNT="${MNT:-$BASE/mnt}"
LOG="${LOG:-$RUN/pvfs2-client.log}"
PIDFILE="${PIDFILE:-$RUN/client.pid}"
FS_URI="${FS_URI:-tcp://10.100.100.2:3334/orangefs_lab_2n}"

mount_fs() {
  python3 - "$MNT" "$FS_URI" <<'PY'
import ctypes, os, sys
mnt = sys.argv[1].encode()
src = sys.argv[2].encode()
libc = ctypes.CDLL("libc.so.6", use_errno=True)
if libc.mount(src, mnt, b"pvfs2", 0, None) != 0:
    err = ctypes.get_errno()
    if err != 16:  # EBUSY
        raise OSError(err, os.strerror(err))
PY
}

umount_fs() {
  python3 - "$MNT" <<'PY'
import ctypes, sys
mnt = sys.argv[1].encode()
libc = ctypes.CDLL("libc.so.6", use_errno=True)
libc.umount2(mnt, 0)
PY
}

is_mounted() {
  mountpoint -q "$MNT"
}

start_client() {
  modprobe orangefs
  mkdir -p "$BIN" "$LIB" "$RUN" "$MNT"

  if [[ -f "$PIDFILE" ]] && kill -0 "$(cat "$PIDFILE")" 2>/dev/null; then
    :
  else
    pkill -f "$BIN/pvfs2-client -f -L $LOG" >/dev/null 2>&1 || true
    nohup env LD_LIBRARY_PATH="$LIB" \
      "$BIN/pvfs2-client" -f -L "$LOG" -p "$BIN/pvfs2-client-core" \
      >/dev/null 2>&1 &
    echo $! >"$PIDFILE"
    sleep 4
  fi

  if ! is_mounted; then
    mount_fs
  fi
}

stop_client() {
  if is_mounted; then
    umount_fs || true
  fi
  if [[ -f "$PIDFILE" ]]; then
    kill "$(cat "$PIDFILE")" >/dev/null 2>&1 || true
    rm -f "$PIDFILE"
  fi
  pkill -f "$BIN/pvfs2-client -f -L $LOG" >/dev/null 2>&1 || true
}

status_client() {
  if is_mounted; then
    mount | grep -F " on $MNT "
  else
    echo "not-mounted:$MNT"
  fi
  if [[ -f "$PIDFILE" ]] && kill -0 "$(cat "$PIDFILE")" 2>/dev/null; then
    echo "client-pid=$(cat "$PIDFILE")"
  else
    echo "client-pid=not-running"
  fi
}

case "$ACTION" in
  start)
    start_client
    status_client
    ;;
  stop)
    stop_client
    ;;
  restart)
    stop_client
    start_client
    status_client
    ;;
  status)
    status_client
    ;;
  *)
    echo "usage: $0 {start|stop|restart|status}" >&2
    exit 2
    ;;
esac

