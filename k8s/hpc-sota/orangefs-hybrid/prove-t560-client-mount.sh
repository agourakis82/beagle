#!/usr/bin/env bash
set -euo pipefail

BASE=/zfast/orangefs-lab
BUILD="$BASE/orangefs-build-serveronly-dyn"
LIB="$BUILD/lib"
BIN="$BUILD/src/apps/kernel/linux"
SERVER="$BUILD/src/server/pvfs2-server"
CONF="$BASE/single-node-dyn/etc/orangefs_lab.conf"
MNT="$BASE/single-node-dyn/mnt"
RUNDIR="$BASE/single-node-dyn/run"
SERVER_LOG="$RUNDIR/server.log"
CLIENT_LOG="$RUNDIR/client.log"
CANARY="$MNT/orangefs-canary.txt"
ETCDIR="$(dirname "$CONF")"

cleanup() {
    set +e
    sync
    umount "$MNT" >/dev/null 2>&1 || true
    if [[ -f "$RUNDIR/client.pid" ]]; then
        kill "$(cat "$RUNDIR/client.pid")" >/dev/null 2>&1 || true
    fi
    if [[ -f "$RUNDIR/server.pid" ]]; then
        kill "$(cat "$RUNDIR/server.pid")" >/dev/null 2>&1 || true
    fi
    wait >/dev/null 2>&1 || true
}

mkdir -p "$RUNDIR" "$MNT" "$ETCDIR"
trap cleanup EXIT

modprobe orangefs
rm -f "$SERVER_LOG" "$CLIENT_LOG" "$CANARY"
rm -rf "$BASE/single-node-dyn/data" "$BASE/single-node-dyn/meta" "$BASE/single-node-dyn/log"
mkdir -p "$BASE/single-node-dyn/data" "$BASE/single-node-dyn/meta" "$BASE/single-node-dyn/log"

cat >"$CONF" <<'EOF'
<Defaults>
    UnexpectedRequests 50
    EventLogging none
    EnableTracing no
    LogStamp datetime
    BMIModules bmi_tcp
    FlowModules flowproto_multiqueue
    PerfUpdateInterval 1000
    ServerJobBMITimeoutSecs 30
    ServerJobFlowTimeoutSecs 30
    ClientJobBMITimeoutSecs 300
    ClientJobFlowTimeoutSecs 300
    ClientRetryLimit 5
    ClientRetryDelayMilliSecs 2000
    PrecreateBatchSize 0,32,512,32,32,32,0
    PrecreateLowThreshold 0,16,256,16,16,16,0

    DataStorageSpace /zfast/orangefs-lab/single-node-dyn/data
    MetadataStorageSpace /zfast/orangefs-lab/single-node-dyn/meta
    LogFile /zfast/orangefs-lab/single-node-dyn/log/pvfs2-server.log
</Defaults>

<Aliases>
    Alias t560-proxmox tcp://10.100.100.2:3334
</Aliases>

<Filesystem>
    Name orangefs_lab
    ID 353983656
    RootHandle 1048576
    FileStuffing yes
    DistrDirServersInitial 1
    DistrDirServersMax 1
    DistrDirSplitSize 100
    <MetaHandleRanges>
        Range t560-proxmox 3-4611686018427387904
    </MetaHandleRanges>
    <DataHandleRanges>
        Range t560-proxmox 4611686018427387905-9223372036854775806
    </DataHandleRanges>
    <StorageHints>
        TroveSyncMeta yes
        TroveSyncData no
        TroveMethod alt-aio
    </StorageHints>
</Filesystem>
EOF

env LD_LIBRARY_PATH="$LIB" "$SERVER" -f -a t560-proxmox "$CONF" >/dev/null
env LD_LIBRARY_PATH="$LIB" "$SERVER" -d -a t560-proxmox "$CONF" >"$SERVER_LOG" 2>&1 &
echo $! > "$RUNDIR/server.pid"
sleep 3
grep -q "PVFS2 Server ready" "$SERVER_LOG"

env LD_LIBRARY_PATH="$LIB" "$BIN/pvfs2-client" \
    -f \
    -L "$CLIENT_LOG" \
    -p "$BIN/pvfs2-client-core" \
    >/dev/null 2>&1 &
echo $! > "$RUNDIR/client.pid"
sleep 4

timeout 12s python3 - "$MNT" <<'EOF'
import ctypes
import os
import sys

mnt = sys.argv[1]
libc = ctypes.CDLL("libc.so.6", use_errno=True)
source = b"tcp://10.100.100.2:3334/orangefs_lab"
fstype = b"pvfs2"
target = mnt.encode()
if libc.mount(source, target, fstype, 0, None) != 0:
    err = ctypes.get_errno()
    raise OSError(err, os.strerror(err))
EOF

mount | grep -F "$MNT"
printf "orangefs-moonshot-%s\n" "$(date -Iseconds)" > "$CANARY"
cat "$CANARY"
ls -la "$MNT"
