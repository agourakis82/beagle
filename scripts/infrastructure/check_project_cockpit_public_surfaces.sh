#!/usr/bin/env bash
set -euo pipefail

COCKPIT_VIP="${COCKPIT_VIP:-100.107.208.198}"
WORKSPACE_VIP="${WORKSPACE_VIP:-100.103.74.10}"
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

echo "[public] cockpit health"
curl_public "http://${COCKPIT_VIP}/healthz" \
  | jq -e '.ok == true and .startupWarm.status == "ready"' >/dev/null
curl_public "http://${COCKPIT_VIP}/healthz" \
  | jq '{ok, startupWarm:.startupWarm.status}'

echo
echo "[public] vision control room"
curl_public "http://${COCKPIT_VIP}/api/public/vision/control-room" \
  | jq -e '.inferenceFabric.status == "ready" and .inferenceFabric.truthMode == "observed" and .inferenceFabric.engine.status == "published-via-control-plane"' >/dev/null
curl_public "http://${COCKPIT_VIP}/api/public/vision/control-room" \
  | jq '{title, fabric:(.inferenceFabric.status // null), truthMode:(.inferenceFabric.truthMode // null), engineStatus:(.inferenceFabric.engine.status // null)}'

echo
echo "[public] vision apple brief"
curl_public "http://${COCKPIT_VIP}/api/public/vision/apple-brief" \
  | jq -e '.inferenceFabric.status == "ready" and .inferenceFabric.engine.status == "published-via-control-plane" and (.handoffChecklist | length) > 0 and (.packetGraph.nodeCount // 0) > 0' >/dev/null
curl_public "http://${COCKPIT_VIP}/api/public/vision/apple-brief" \
  | jq '{title, route, fabric:(.inferenceFabric.status // null), engineStatus:(.inferenceFabric.engine.status // null), checklistCount:(.handoffChecklist | length), nodeCount:(.packetGraph.nodeCount // 0), edgeCount:(.packetGraph.edgeCount // 0)}'

echo
echo "[public] vision apple launchpad"
curl_public "http://${COCKPIT_VIP}/api/public/vision/apple-launchpad" \
  | jq -e '.inferenceFabric.status == "ready" and .inferenceFabric.engine.status == "published-via-control-plane" and .developerAccount.status == "active" and (.launchGates | length) > 0' >/dev/null
curl_public "http://${COCKPIT_VIP}/api/public/vision/apple-launchpad" \
  | jq '{title, route, fabric:(.inferenceFabric.status // null), engineStatus:(.inferenceFabric.engine.status // null), developer:(.developerAccount.status // null), gateCount:(.launchGates | length), checklistCount:(.handoffChecklist | length)}'

echo
echo "[public] vision operator board"
curl_public "http://${COCKPIT_VIP}/api/public/vision/operator-board" \
  | jq -e '.inferenceFabric.status == "ready" and .inferenceFabric.engine.status == "published-via-control-plane" and .developerAccount.status == "active" and (.operatorTransitions | length) > 0 and (.operatorLanes | length) > 0' >/dev/null
curl_public "http://${COCKPIT_VIP}/api/public/vision/operator-board" \
  | jq '{title, route, fabric:(.inferenceFabric.status // null), engineStatus:(.inferenceFabric.engine.status // null), developer:(.developerAccount.status // null), transitionCount:(.operatorTransitions | length), laneCount:(.operatorLanes | length)}'

echo
echo "[public] vision runtime matrix"
curl_public "http://${COCKPIT_VIP}/api/public/vision/runtime-matrix" \
  | jq -e '.inferenceFabric.status == "ready" and .inferenceFabric.engine.status == "published-via-control-plane" and .developerAccount.status == "active" and (.runtimeMatrix | length) > 0 and (.matrixChecks | length) > 0' >/dev/null
curl_public "http://${COCKPIT_VIP}/api/public/vision/runtime-matrix" \
  | jq '{title, route, fabric:(.inferenceFabric.status // null), engineStatus:(.inferenceFabric.engine.status // null), developer:(.developerAccount.status // null), shellCount:(.runtimeMatrix | length), checkCount:(.matrixChecks | length)}'

echo
echo "[public] vision route atlas"
curl_public "http://${COCKPIT_VIP}/api/public/vision/route-atlas" \
  | jq -e '.inferenceFabric.status == "ready" and .inferenceFabric.engine.status == "published-via-control-plane" and .developerAccount.status == "active" and (.atlasRoutes | length) > 0 and (.atlasChecks | length) > 0' >/dev/null
curl_public "http://${COCKPIT_VIP}/api/public/vision/route-atlas" \
  | jq '{title, route, fabric:(.inferenceFabric.status // null), engineStatus:(.inferenceFabric.engine.status // null), developer:(.developerAccount.status // null), routeCount:(.atlasRoutes | length), checkCount:(.atlasChecks | length)}'

echo
echo "[public] vision mission timeline"
curl_public "http://${COCKPIT_VIP}/api/public/vision/mission-timeline" \
  | jq -e '.inferenceFabric.status == "ready" and .inferenceFabric.engine.status == "published-via-control-plane" and .developerAccount.status == "active" and (.missionTimeline | length) > 0 and (.timelineChecks | length) > 0' >/dev/null
curl_public "http://${COCKPIT_VIP}/api/public/vision/mission-timeline" \
  | jq '{title, route, fabric:(.inferenceFabric.status // null), engineStatus:(.inferenceFabric.engine.status // null), developer:(.developerAccount.status // null), phaseCount:(.missionTimeline | length), checkCount:(.timelineChecks | length)}'

echo
echo "[public] vision sovereign bridge"
curl_public "http://${COCKPIT_VIP}/api/public/vision/sovereign-bridge" \
  | jq -e '.inferenceFabric.status == "ready" and .inferenceFabric.engine.status == "published-via-control-plane" and .developerAccount.status == "active" and (.bridgeStages | length) > 0 and (.bridgeChecks | length) > 0' >/dev/null
curl_public "http://${COCKPIT_VIP}/api/public/vision/sovereign-bridge" \
  | jq '{title, route, fabric:(.inferenceFabric.status // null), engineStatus:(.inferenceFabric.engine.status // null), developer:(.developerAccount.status // null), stageCount:(.bridgeStages | length), checkCount:(.bridgeChecks | length)}'

echo
echo "[public] vision sovereign cockpit preview"
curl_public "http://${COCKPIT_VIP}/api/public/vision/sovereign-cockpit-preview" \
  | jq -e '.inferenceFabric.status == "ready" and .inferenceFabric.engine.status == "published-via-control-plane" and .developerAccount.status == "active" and (.previewPanels | length) > 0 and (.previewChecks | length) > 0' >/dev/null
curl_public "http://${COCKPIT_VIP}/api/public/vision/sovereign-cockpit-preview" \
  | jq '{title, route, fabric:(.inferenceFabric.status // null), engineStatus:(.inferenceFabric.engine.status // null), developer:(.developerAccount.status // null), panelCount:(.previewPanels | length), checkCount:(.previewChecks | length)}'

echo
echo "[public] vision packet graph"
curl_public "http://${COCKPIT_VIP}/api/public/vision/packet-graph" \
  | jq -e '.inferenceFabric.status == "ready" and .inferenceFabric.engine.status == "published-via-control-plane" and (.graphNodes | length) > 0 and (.graphEdges | length) > 0' >/dev/null
curl_public "http://${COCKPIT_VIP}/api/public/vision/packet-graph" \
  | jq '{title, route, fabric:(.inferenceFabric.status // null), engineStatus:(.inferenceFabric.engine.status // null), nodeCount:(.graphSummary.nodeCount // 0), edgeCount:(.graphSummary.edgeCount // 0)}'

echo
echo "[public] vision handoff"
curl_public "http://${COCKPIT_VIP}/api/public/vision/handoff" \
  | jq -e '.inferenceFabric.status == "ready" and .inferenceFabric.engine.status == "published-via-control-plane" and (.handoffChecklist | length) > 0' >/dev/null
curl_public "http://${COCKPIT_VIP}/api/public/vision/handoff" \
  | jq '{title, route, fabric:(.inferenceFabric.status // null), engineStatus:(.inferenceFabric.engine.status // null), checklistCount:(.handoffChecklist | length)}'

echo
echo "[public] showcase"
curl_public "http://${COCKPIT_VIP}/api/public/projects/sounio/showcase" \
  | jq -e '.inferenceFabric.status == "ready" and .inferenceFabric.truthMode == "observed" and .inferenceFabric.engine.status == "published-via-control-plane"' >/dev/null
curl_public "http://${COCKPIT_VIP}/api/public/projects/sounio/showcase" \
  | jq '{title, fabric:(.inferenceFabric.status // null), truthMode:(.inferenceFabric.truthMode // null), engineStatus:(.inferenceFabric.engine.status // null), models:(.inferenceFabric.models // [] | map({id,provider}))}'

echo
echo "[public] showcase packet graph"
curl_public "http://${COCKPIT_VIP}/api/public/projects/sounio/packet-graph" \
  | jq -e '.inferenceFabric.status == "ready" and .inferenceFabric.engine.status == "published-via-control-plane" and (.graphNodes | length) > 0 and (.graphEdges | length) > 0' >/dev/null
curl_public "http://${COCKPIT_VIP}/api/public/projects/sounio/packet-graph" \
  | jq '{title, route, fabric:(.inferenceFabric.status // null), engineStatus:(.inferenceFabric.engine.status // null), nodeCount:(.graphSummary.nodeCount // 0), edgeCount:(.graphSummary.edgeCount // 0)}'

echo
echo "[public] showcase sovereign bridge"
curl_public "http://${COCKPIT_VIP}/api/public/projects/sounio/sovereign-bridge" \
  | jq -e '.inferenceFabric.status == "ready" and .inferenceFabric.engine.status == "published-via-control-plane" and (.bridgeStages | length) > 0 and (.bridgeChecks | length) > 0' >/dev/null
curl_public "http://${COCKPIT_VIP}/api/public/projects/sounio/sovereign-bridge" \
  | jq '{title, route, fabric:(.inferenceFabric.status // null), engineStatus:(.inferenceFabric.engine.status // null), stageCount:(.bridgeStages | length), checkCount:(.bridgeChecks | length)}'

echo
echo "[public] showcase sovereign cockpit preview"
curl_public "http://${COCKPIT_VIP}/api/public/projects/sounio/sovereign-cockpit-preview" \
  | jq -e '.inferenceFabric.status == "ready" and .inferenceFabric.engine.status == "published-via-control-plane" and (.previewPanels | length) > 0 and (.previewChecks | length) > 0' >/dev/null
curl_public "http://${COCKPIT_VIP}/api/public/projects/sounio/sovereign-cockpit-preview" \
  | jq '{title, route, fabric:(.inferenceFabric.status // null), engineStatus:(.inferenceFabric.engine.status // null), panelCount:(.previewPanels | length), checkCount:(.previewChecks | length)}'

echo
echo "[public] workspace VIP on :8080"
curl_public "http://${WORKSPACE_VIP}:8080/" | head -c 200
echo
