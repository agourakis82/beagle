#!/usr/bin/env bash
set -euo pipefail

TARGET_ROOT="${TARGET_ROOT:-/mnt/datasets/orangefs-lab/two-node}"
SERVER01_ALIAS="${SERVER01_ALIAS:-tcp://10.100.100.2:3334}"
SERVER02_ALIAS="${SERVER02_ALIAS:-tcp://10.100.100.3:3334}"
SERVER02_ROOT="${SERVER02_ROOT:-/srv/orangefs-server02-store}"
OUT_DIR="${OUT_DIR:-/home/devsounio/beagle/k8s/hpc-sota/ops/supercomputer-readiness/artifacts/orangefs-multitb-plan}"

mkdir -p "${OUT_DIR}"

CONF="${OUT_DIR}/orangefs_lab_2n.multitb-target.conf"
SERVER01_UNIT="${OUT_DIR}/orangefs-server01.multitb-target.service"

cat >"${CONF}" <<EOF
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
    Alias server01 ${SERVER01_ALIAS}
    Alias server02 ${SERVER02_ALIAS}
</Aliases>

<ServerOptions>
    Server server01
    DataStorageSpace ${TARGET_ROOT}/server01/data
    MetadataStorageSpace ${TARGET_ROOT}/server01/meta
    LogFile ${TARGET_ROOT}/server01/log/pvfs2-server.log
</ServerOptions>

<ServerOptions>
    Server server02
    DataStorageSpace ${SERVER02_ROOT}/data
    MetadataStorageSpace ${SERVER02_ROOT}/meta
    LogFile ${SERVER02_ROOT}/log/pvfs2-server.log
    EventLogging io,storage,distribution,server
</ServerOptions>

<Filesystem>
    Name orangefs_lab_2n
    ID 353983657
    RootHandle 1048576
    DefaultNumDFiles 1
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

cat >"${SERVER01_UNIT}" <<EOF
[Unit]
Description=OrangeFS server01 multi-TiB target on t560
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
Environment=LD_LIBRARY_PATH=/zfast/orangefs-lab/orangefs-build-serveronly-dyn/lib
ExecStartPre=/bin/bash -lc 'fuser -k 3334/tcp >/dev/null 2>&1 || true; sleep 1'
ExecStart=/zfast/orangefs-lab/orangefs-build-serveronly-dyn/src/server/pvfs2-server -d -a server01 ${TARGET_ROOT}/etc/orangefs_lab_2n.conf
Restart=on-failure
RestartSec=3

[Install]
WantedBy=multi-user.target
EOF

echo "generated=${CONF}"
echo "generated=${SERVER01_UNIT}"
echo
echo "Review only. Do not apply outside a maintenance window."
