#!/usr/bin/env bash
set -euo pipefail

BASE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PASS="${PASS:?defina PASS no ambiente (nunca no script); prefira chave SSH}"
T560=root@10.100.100.2
R5860=root@10.100.100.3
R740=root@10.100.100.4
R770=root@10.100.100.1

T560_CONF=/zfast/orangefs-lab/two-node/etc/orangefs_lab_2n.conf
R5860_CONF=/var/lib/orangefs-lab/two-node/etc/orangefs_lab_2n.conf

TMP_CONF="$(mktemp)"
trap 'rm -f "$TMP_CONF"' EXIT

awk '
  /TroveMaxConcurrentIO 32/ { next }
  /FlowBufferSizeBytes 1048576/ { next }
  /FlowBuffersPerFlow 16/ { next }
  /AttrCacheKeywords dh,md,de,st/ { next }
  /AttrCacheSize 4093/ { next }
  /AttrCacheMaxNumElems 32768/ { next }
  /DBMaxSize 1073741824/ { next }
  /FlowModules flowproto_multiqueue/ && !seen_trove_max {
    print
    print "    TroveMaxConcurrentIO 32"
    seen_trove_max=1
    next
  }
  /FileStuffing yes/ && !seen_flow_buffers {
    print
    print "    FlowBufferSizeBytes 1048576"
    print "    FlowBuffersPerFlow 16"
    seen_flow_buffers=1
    next
  }
  /<StorageHints>/ && !seen_storage_hints {
    print
    print "        AttrCacheKeywords dh,md,de,st"
    print "        AttrCacheSize 4093"
    print "        AttrCacheMaxNumElems 32768"
    print "        DBMaxSize 1073741824"
    seen_storage_hints=1
    next
  }
  { print }
' "$T560_CONF" > "$TMP_CONF"

scp_copy() {
  local src="$1"
  local host="$2"
  local dest="$3"
  sshpass -p "$PASS" scp -o StrictHostKeyChecking=no "$src" "$host:$dest" >/dev/null
}

ssh_run() {
  local host="$1"
  shift
  sshpass -p "$PASS" ssh -o StrictHostKeyChecking=no "$host" "$@"
}

scp_copy "$TMP_CONF" "$T560" "$T560_CONF"
scp_copy "$TMP_CONF" "$R5860" "$R5860_CONF"

scp_copy "$BASE/systemd/orangefs-server01.service" "$T560" /etc/systemd/system/orangefs-server01.service
scp_copy "$BASE/systemd/orangefs-server02.service" "$R5860" /etc/systemd/system/orangefs-server02.service

ssh_run "$T560" "systemctl daemon-reload && systemctl stop orangefs-server01.service || true && fuser -k 3334/tcp >/dev/null 2>&1 || true && systemctl reset-failed orangefs-server01.service && systemctl start orangefs-server01.service && systemctl --no-pager status orangefs-server01.service | sed -n '1,18p'"
ssh_run "$R5860" "systemctl daemon-reload && systemctl stop orangefs-server02.service || true && fuser -k 3334/tcp >/dev/null 2>&1 || true && systemctl reset-failed orangefs-server02.service && systemctl start orangefs-server02.service && systemctl --no-pager status orangefs-server02.service | sed -n '1,18p'"

sleep 4

ssh_run "$R740" "systemctl restart orangefs-client-runtime.service && systemctl --no-pager status orangefs-client-runtime.service | sed -n '1,18p'"
ssh_run "$R770" "systemctl restart orangefs-client-runtime.service && systemctl --no-pager status orangefs-client-runtime.service | sed -n '1,18p'"
