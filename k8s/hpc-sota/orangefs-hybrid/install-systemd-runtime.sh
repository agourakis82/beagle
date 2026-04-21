#!/usr/bin/env bash
set -euo pipefail

BASE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PASS="${PASS:-Urso1982!}"

copy_to_host() {
  local host="$1"
  sshpass -p "$PASS" scp -o StrictHostKeyChecking=no \
    "$BASE/systemd/orangefs-client-runtime.sh" \
    "$BASE/systemd/orangefs-client-runtime.service" \
    "root@$host:/tmp/" >/dev/null
  sshpass -p "$PASS" ssh -o StrictHostKeyChecking=no "root@$host" '
    install -m 0755 /tmp/orangefs-client-runtime.sh /usr/local/sbin/orangefs-client-runtime.sh
    install -m 0644 /tmp/orangefs-client-runtime.service /etc/systemd/system/orangefs-client-runtime.service
    systemctl daemon-reload
    systemctl enable --now orangefs-client-runtime.service
    systemctl status --no-pager orangefs-client-runtime.service | sed -n "1,20p"
  '
}

copy_server_unit() {
  local host="$1"
  local service_file="$2"
  local service_name
  service_name="$(basename "$service_file")"
  sshpass -p "$PASS" scp -o StrictHostKeyChecking=no \
    "$BASE/systemd/$service_file" \
    "root@$host:/tmp/$service_name" >/dev/null
  sshpass -p "$PASS" ssh -o StrictHostKeyChecking=no "root@$host" "
    install -m 0644 /tmp/$service_name /etc/systemd/system/$service_name
    systemctl daemon-reload
    systemctl enable --now $service_name
    systemctl status --no-pager $service_name | sed -n '1,20p'
  "
}

copy_server_unit 10.100.100.2 orangefs-server01.service
copy_server_unit 10.100.100.3 orangefs-server02.service
copy_to_host 10.100.100.4
copy_to_host 10.100.100.1

