#!/usr/bin/env bash
set -euo pipefail

NAMESPACE="${NAMESPACE:-beagle}"
DEPLOYMENT="${DEPLOYMENT:-project-cockpit}"

fetch_html() {
  local route="$1"
  kubectl -n "$NAMESPACE" exec "deployment/${DEPLOYMENT}" -- \
    curl -fsS "http://127.0.0.1:4370${route}"
}

check_route() {
  local route="$1"
  local html js_asset css_asset

  html="$(fetch_html "$route")"

  [[ "$html" == *'<!doctype html>'* ]]
  [[ "$html" == *'<div id="root"></div>'* ]]
  [[ "$html" == *'/assets/index-'* ]]

  js_asset="$(printf '%s' "$html" | grep -oE '/assets/index-[^"]+\.js' | head -n 1)"
  css_asset="$(printf '%s' "$html" | grep -oE '/assets/index-[^"]+\.css' | head -n 1)"

  [[ -n "$js_asset" ]]
  [[ -n "$css_asset" ]]

  printf '%s\n' "$(jq -n --arg route "$route" --arg js "$js_asset" --arg css "$css_asset" '{route:$route, jsAsset:$js, cssAsset:$css}')"
}

echo "[assets] public portal"
check_route "/public"

echo
echo "[assets] vision control room"
check_route "/public/vision"

echo
echo "[assets] vision apple brief"
check_route "/public/vision/apple-brief"

echo
echo "[assets] vision apple launchpad"
check_route "/public/vision/apple-launchpad"

echo
echo "[assets] vision operator board"
check_route "/public/vision/operator-board"

echo
echo "[assets] vision runtime matrix"
check_route "/public/vision/runtime-matrix"

echo
echo "[assets] vision route atlas"
check_route "/public/vision/route-atlas"

echo
echo "[assets] vision mission timeline"
check_route "/public/vision/mission-timeline"

echo
echo "[assets] vision sovereign bridge"
check_route "/public/vision/sovereign-bridge"

echo
echo "[assets] vision sovereign cockpit preview"
check_route "/public/vision/sovereign-cockpit-preview"

echo
echo "[assets] vision packet graph"
check_route "/public/vision/packet-graph"

echo
echo "[assets] vision handoff"
check_route "/public/vision/handoff"

echo
echo "[assets] showcase"
check_route "/public/projects/sounio"

echo
echo "[assets] showcase packet graph"
check_route "/public/projects/sounio/packet-graph"

echo
echo "[assets] showcase sovereign bridge"
check_route "/public/projects/sounio/sovereign-bridge"

echo
echo "[assets] showcase sovereign cockpit preview"
check_route "/public/projects/sounio/sovereign-cockpit-preview"
