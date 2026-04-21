#!/usr/bin/env bash
set -euo pipefail

COCKPIT_VIP="${COCKPIT_VIP:-100.107.208.198}"
WORKSPACE_VIP="${WORKSPACE_VIP:-100.103.74.10}"
CURL_MAX_TIME="${CURL_MAX_TIME:-15}"
CURL_RETRIES="${CURL_RETRIES:-3}"

curl_vip() {
  local attempt output status
  for attempt in $(seq 1 "$CURL_RETRIES"); do
    if output=$(curl --noproxy '*' --max-time "$CURL_MAX_TIME" -fsS "$@" 2>&1); then
      printf '%s\n' "$output"
      return 0
    fi
    status=$?
    if [ "$attempt" -lt "$CURL_RETRIES" ]; then
      sleep 1
    fi
  done
  printf '%s\n' "$output" >&2
  return "${status:-1}"
}

echo "[tailnet] cockpit health via VIP"
curl_vip "http://${COCKPIT_VIP}/healthz" | jq '{ok, startupWarm:.startupWarm.status}'

echo
echo "[tailnet] vision handoff via cockpit VIP"
curl_vip "http://${COCKPIT_VIP}/api/public/vision/handoff" \
  | jq '{title, route, fabric:(.inferenceFabric.status // null), truthMode:(.inferenceFabric.truthMode // null)}'

echo
echo "[tailnet] workspace HTTP root via VIP:8080"
curl_vip "http://${WORKSPACE_VIP}:8080/" | head -c 200
echo
