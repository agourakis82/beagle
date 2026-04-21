#!/usr/bin/env bash
set -euo pipefail

REMOTE_HOST=10.100.100.3
REMOTE_PASS='Urso1982!'
SSH="sshpass -p $REMOTE_PASS ssh -o StrictHostKeyChecking=no root@$REMOTE_HOST"
SCP="sshpass -p $REMOTE_PASS scp -o StrictHostKeyChecking=no"

T560_BASE=/zfast/orangefs-lab/two-node
T560_BUILD=/zfast/orangefs-lab/orangefs-build-serveronly-dyn
T560_LIB="$T560_BUILD/lib"
T560_SERVER="$T560_BUILD/src/server/pvfs2-server"
T560_BIN="$T560_BUILD/src/apps/kernel/linux"

R5860_BASE=/var/lib/orangefs-lab/two-node
R5860_BUILD=/var/lib/orangefs-lab/orangefs-build-serveronly-dyn
R5860_SERVER="$R5860_BUILD/src/server/pvfs2-server"

CONF_LOCAL="$T560_BASE/etc/orangefs_lab_2n.conf"
CONF_REMOTE="$R5860_BASE/etc/orangefs_lab_2n.conf"
MNT="$T560_BASE/mnt"
RUN_LOCAL="$T560_BASE/run"
RUN_REMOTE="$R5860_BASE/run"
SERVER_LOG_LOCAL="$RUN_LOCAL/server01.log"
SERVER_LOG_REMOTE="$RUN_REMOTE/server02.log"
CLIENT_LOG="$RUN_LOCAL/client.log"
CANARY="$MNT/orangefs-canary-2n.txt"
HOLD_SECONDS="${HOLD_SECONDS:-0}"

cleanup() {
    set +e
    sync
    python3 - "$MNT" <<'EOF' >/dev/null 2>&1
import ctypes
import sys
mnt = sys.argv[1].encode()
libc = ctypes.CDLL("libc.so.6", use_errno=True)
libc.umount2(mnt, 0)
EOF
    if [[ -f "$RUN_LOCAL/client.pid" ]]; then
        kill "$(cat "$RUN_LOCAL/client.pid")" >/dev/null 2>&1 || true
    fi
    if [[ -f "$RUN_LOCAL/server01.pid" ]]; then
        kill "$(cat "$RUN_LOCAL/server01.pid")" >/dev/null 2>&1 || true
    fi
    $SSH 'if [[ -f '"$RUN_REMOTE"'/server02.pid ]]; then kill "$(cat '"$RUN_REMOTE"'/server02.pid)" >/dev/null 2>&1 || true; fi' >/dev/null 2>&1 || true
    wait >/dev/null 2>&1 || true
}

mkdir -p "$T560_BASE/server01/data" "$T560_BASE/server01/meta" "$T560_BASE/server01/log" \
         "$T560_BASE/etc" "$RUN_LOCAL" "$MNT"
trap cleanup EXIT

modprobe orangefs

rm -f "$SERVER_LOG_LOCAL" "$CLIENT_LOG" "$CANARY"
rm -rf "$T560_BASE/server01/data" "$T560_BASE/server01/meta" "$T560_BASE/server01/log"
mkdir -p "$T560_BASE/server01/data" "$T560_BASE/server01/meta" "$T560_BASE/server01/log"

$SSH "modprobe orangefs && rm -rf '$R5860_BASE/server02/data' '$R5860_BASE/server02/meta' '$R5860_BASE/server02/log' '$R5860_BASE/etc' '$RUN_REMOTE' && mkdir -p '$R5860_BASE/server02/data' '$R5860_BASE/server02/meta' '$R5860_BASE/server02/log' '$R5860_BASE/etc' '$RUN_REMOTE'"

cat >"$CONF_LOCAL" <<'EOF'
<Defaults>
    UnexpectedRequests 50
    EventLogging none
    EnableTracing no
    LogStamp datetime
    BMIModules bmi_tcp
    FlowModules flowproto_multiqueue
    TroveMaxConcurrentIO 32
    PerfUpdateInterval 1000
    ServerJobBMITimeoutSecs 30
    ServerJobFlowTimeoutSecs 30
    ClientJobBMITimeoutSecs 300
    ClientJobFlowTimeoutSecs 300
    ClientRetryLimit 5
    ClientRetryDelayMilliSecs 2000
    PrecreateBatchSize 0,32,512,32,32,32,0
    PrecreateLowThreshold 0,16,256,16,16,16,0
</Defaults>

<Aliases>
    Alias server01 tcp://10.100.100.2:3334
    Alias server02 tcp://10.100.100.3:3334
</Aliases>

<ServerOptions>
    Server server01
    DataStorageSpace /zfast/orangefs-lab/two-node/server01/data
    MetadataStorageSpace /zfast/orangefs-lab/two-node/server01/meta
    LogFile /zfast/orangefs-lab/two-node/server01/log/pvfs2-server.log
</ServerOptions>

<ServerOptions>
    Server server02
    DataStorageSpace /var/lib/orangefs-lab/two-node/server02/data
    MetadataStorageSpace /var/lib/orangefs-lab/two-node/server02/meta
    LogFile /var/lib/orangefs-lab/two-node/server02/log/pvfs2-server.log
</ServerOptions>

<Filesystem>
    Name orangefs_lab_2n
    ID 353983657
    RootHandle 1048576
    FileStuffing yes
    FlowBufferSizeBytes 1048576
    FlowBuffersPerFlow 16
    DistrDirServersInitial 1
    DistrDirServersMax 1
    DistrDirSplitSize 100
    <MetaHandleRanges>
        Range server01 3-2305843009213693952
        Range server02 2305843009213693953-4611686018427387903
    </MetaHandleRanges>
    <DataHandleRanges>
        Range server01 4611686018427387905-6917529027641081855
        Range server02 6917529027641081856-9223372036854775806
    </DataHandleRanges>
    <StorageHints>
        AttrCacheKeywords dh,md,de,st
        AttrCacheSize 4093
        AttrCacheMaxNumElems 32768
        DBMaxSize 1073741824
        TroveSyncMeta yes
        TroveSyncData no
        TroveMethod alt-aio
    </StorageHints>
</Filesystem>
EOF

$SCP "$CONF_LOCAL" "root@$REMOTE_HOST:$CONF_REMOTE" >/dev/null

env LD_LIBRARY_PATH="$T560_LIB" "$T560_SERVER" -f -a server01 "$CONF_LOCAL" >/dev/null
$SSH "$R5860_SERVER -f -a server02 '$CONF_REMOTE' >/dev/null"

env LD_LIBRARY_PATH="$T560_LIB" "$T560_SERVER" -d -a server01 "$CONF_LOCAL" >"$SERVER_LOG_LOCAL" 2>&1 &
echo $! > "$RUN_LOCAL/server01.pid"

$SSH "nohup '$R5860_SERVER' -d -a server02 '$CONF_REMOTE' >'$SERVER_LOG_REMOTE' 2>&1 & echo \$! > '$RUN_REMOTE/server02.pid'"

sleep 4
grep -q "PVFS2 Server ready" "$SERVER_LOG_LOCAL"
$SSH "grep -q 'PVFS2 Server ready' '$SERVER_LOG_REMOTE'"

env LD_LIBRARY_PATH="$T560_LIB" "$T560_BIN/pvfs2-client" \
    -f \
    -L "$CLIENT_LOG" \
    -p "$T560_BIN/pvfs2-client-core" \
    >/dev/null 2>&1 &
echo $! > "$RUN_LOCAL/client.pid"
sleep 4

python3 - "$MNT" <<'EOF'
import ctypes
import os
import sys

mnt = sys.argv[1]
libc = ctypes.CDLL("libc.so.6", use_errno=True)
source = b"tcp://10.100.100.2:3334/orangefs_lab_2n"
fstype = b"pvfs2"
target = mnt.encode()
if libc.mount(source, target, fstype, 0, None) != 0:
    err = ctypes.get_errno()
    raise OSError(err, os.strerror(err))
EOF

mount | grep -F "$MNT"
printf "orangefs-two-node-%s\n" "$(date -Iseconds)" > "$CANARY"
cat "$CANARY"
ls -la "$MNT"

if [[ "$HOLD_SECONDS" -gt 0 ]]; then
    echo "Holding two-node proof open for ${HOLD_SECONDS}s"
    sleep "$HOLD_SECONDS"
fi
