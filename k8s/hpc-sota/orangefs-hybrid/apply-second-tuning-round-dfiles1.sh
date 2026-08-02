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
  /DefaultNumDFiles / { next }
  /EventLogging io,storage,distribution,server/ { next }
  /RootHandle / && !seen_default_num_dfiles {
    print
    print "    DefaultNumDFiles 1"
    seen_default_num_dfiles=1
    next
  }
  /Server server02/ && !in_server02 {
    in_server02=1
    print
    next
  }
  in_server02 && /LogFile / && !seen_server02_logging {
    print
    print "    EventLogging io,storage,distribution,server"
    seen_server02_logging=1
    next
  }
  in_server02 && /<\/ServerOptions>/ {
    in_server02=0
    print
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

echo "Applied Round 2: DefaultNumDFiles=1 and server02 EventLogging."
