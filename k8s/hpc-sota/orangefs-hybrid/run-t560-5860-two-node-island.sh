#!/usr/bin/env bash
set -euo pipefail

REMOTE_HOST=10.100.100.3
REMOTE_PASS='Urso1982!'
SSH=(sshpass -p "$REMOTE_PASS" ssh -o StrictHostKeyChecking=no "root@$REMOTE_HOST")
SCP=(sshpass -p "$REMOTE_PASS" scp -o StrictHostKeyChecking=no)

T560_BASE=/zfast/orangefs-lab/two-node-persistent
T560_BUILD=/zfast/orangefs-lab/orangefs-build-serveronly-dyn
T560_LIB="$T560_BUILD/lib"
T560_SERVER="$T560_BUILD/src/server/pvfs2-server"

R5860_BASE=/var/lib/orangefs-lab/two-node-persistent
R5860_BUILD=/var/lib/orangefs-lab/orangefs-build-serveronly-dyn
R5860_SERVER="$R5860_BUILD/src/server/pvfs2-server"

CONF_LOCAL="$T560_BASE/etc/orangefs_lab_2n.conf"
CONF_REMOTE="$R5860_BASE/etc/orangefs_lab_2n.conf"
RUN_LOCAL="$T560_BASE/run"
RUN_REMOTE="$R5860_BASE/run"
SERVER_LOG_LOCAL="$RUN_LOCAL/server01.log"
SERVER_LOG_REMOTE="$RUN_REMOTE/server02.log"

cleanup() {
    set +e
    if [[ -f "$RUN_LOCAL/server01.pid" ]]; then
        kill "$(cat "$RUN_LOCAL/server01.pid")" >/dev/null 2>&1 || true
    fi
    "${SSH[@]}" 'if [[ -f '"$RUN_REMOTE"'/server02.pid ]]; then kill "$(cat '"$RUN_REMOTE"'/server02.pid)" >/dev/null 2>&1 || true; fi' >/dev/null 2>&1 || true
    wait >/dev/null 2>&1 || true
}

mkdir -p "$T560_BASE/server01/data" "$T560_BASE/server01/meta" "$T560_BASE/server01/log" \
         "$T560_BASE/etc" "$RUN_LOCAL"
trap cleanup EXIT

modprobe orangefs

pkill -f "/zfast/orangefs-lab/orangefs-build-serveronly-dyn/src/server/pvfs2-server -d -a server01" >/dev/null 2>&1 || true

rm -f "$SERVER_LOG_LOCAL"

"${SSH[@]}" "modprobe orangefs && pkill -f '/var/lib/orangefs-lab/orangefs-build-serveronly-dyn/src/server/pvfs2-server -d -a server02' >/dev/null 2>&1 || true; mkdir -p '$R5860_BASE/server02/data' '$R5860_BASE/server02/meta' '$R5860_BASE/server02/log' '$R5860_BASE/etc' '$RUN_REMOTE'"

cat >"$CONF_LOCAL" <<'EOF'
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
</Defaults>

<Aliases>
    Alias server01 tcp://10.100.100.2:3334
    Alias server02 tcp://10.100.100.3:3334
</Aliases>

<ServerOptions>
    Server server01
    DataStorageSpace /zfast/orangefs-lab/two-node-persistent/server01/data
    MetadataStorageSpace /zfast/orangefs-lab/two-node-persistent/server01/meta
    LogFile /zfast/orangefs-lab/two-node-persistent/server01/log/pvfs2-server.log
</ServerOptions>

<ServerOptions>
    Server server02
    DataStorageSpace /var/lib/orangefs-lab/two-node-persistent/server02/data
    MetadataStorageSpace /var/lib/orangefs-lab/two-node-persistent/server02/meta
    LogFile /var/lib/orangefs-lab/two-node-persistent/server02/log/pvfs2-server.log
</ServerOptions>

<Filesystem>
    Name orangefs_lab_2n
    ID 353983657
    RootHandle 1048576
    FileStuffing yes
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
        TroveSyncMeta yes
        TroveSyncData no
        TroveMethod alt-aio
    </StorageHints>
</Filesystem>
EOF

"${SCP[@]}" "$CONF_LOCAL" "root@$REMOTE_HOST:$CONF_REMOTE" >/dev/null

if [[ ! -f "$T560_BASE/server01/data/collections.db" ]]; then
    env LD_LIBRARY_PATH="$T560_LIB" "$T560_SERVER" -f -a server01 "$CONF_LOCAL" >/dev/null
fi
"${SSH[@]}" "if [[ ! -f '$R5860_BASE/server02/data/collections.db' ]]; then '$R5860_SERVER' -f -a server02 '$CONF_REMOTE' >/dev/null; fi"

env LD_LIBRARY_PATH="$T560_LIB" "$T560_SERVER" -d -a server01 "$CONF_LOCAL" >"$SERVER_LOG_LOCAL" 2>&1 &
echo $! > "$RUN_LOCAL/server01.pid"

"${SSH[@]}" "nohup '$R5860_SERVER' -d -a server02 '$CONF_REMOTE' >'$SERVER_LOG_REMOTE' 2>&1 & echo \$! > '$RUN_REMOTE/server02.pid'"

sleep 4
grep -q "PVFS2 Server ready" "$SERVER_LOG_LOCAL"
"${SSH[@]}" "grep -q 'PVFS2 Server ready' '$SERVER_LOG_REMOTE'"

echo "OrangeFS two-node island is live."
echo "server01 log: $SERVER_LOG_LOCAL"
echo "server02 log: $SERVER_LOG_REMOTE"
echo "Press Ctrl-C to stop both proof servers."

while true; do
    sleep 30
done
