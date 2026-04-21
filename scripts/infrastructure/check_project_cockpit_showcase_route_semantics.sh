#!/usr/bin/env bash
set -euo pipefail

COCKPIT_VIP="${COCKPIT_VIP:-100.107.208.198}"
CURL_MAX_TIME="${CURL_MAX_TIME:-15}"
CURL_RETRIES="${CURL_RETRIES:-3}"

curl_public() {
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

echo "[showcase-semantics] sovereign bridge"
curl_public "http://${COCKPIT_VIP}/api/public/projects/sounio/sovereign-bridge" \
  | jq -e '
    .inferenceFabric.status == "ready"
    and .inferenceFabric.engine.status == "published-via-control-plane"
    and (.bridgeStages | length) >= 6
    and (.bridgeStages[0].route == "/public")
    and (.bridgeStages[1].route == "/public/projects/sounio")
    and (.bridgeStages[-1].route == "/projects/sounio/viewer")
    and (.bridgeChecks | length) >= 4
  ' >/dev/null
curl_public "http://${COCKPIT_VIP}/api/public/projects/sounio/sovereign-bridge" \
  | jq '{title, route, engineStatus:(.inferenceFabric.engine.status // null), stageCount:(.bridgeStages | length), firstStage:(.bridgeStages[0].route // null), secondStage:(.bridgeStages[1].route // null), lastStage:(.bridgeStages[-1].route // null)}'

echo
echo "[showcase-semantics] sovereign cockpit preview"
curl_public "http://${COCKPIT_VIP}/api/public/projects/sounio/sovereign-cockpit-preview" \
  | jq -e '
    .inferenceFabric.status == "ready"
    and .inferenceFabric.engine.status == "published-via-control-plane"
    and (.previewPanels | length) >= 4
    and (.previewPanels[0].route == "/projects/sounio")
    and (.previewPanels[1].route == "/projects/sounio/viewer")
    and (.previewChecks | length) >= 4
  ' >/dev/null
curl_public "http://${COCKPIT_VIP}/api/public/projects/sounio/sovereign-cockpit-preview" \
  | jq '{title, route, engineStatus:(.inferenceFabric.engine.status // null), panelCount:(.previewPanels | length), firstPanel:(.previewPanels[0].route // null), secondPanel:(.previewPanels[1].route // null)}'
