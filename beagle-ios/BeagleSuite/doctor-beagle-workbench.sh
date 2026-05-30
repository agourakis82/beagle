#!/usr/bin/env bash
# Gate for Beagle Workbench Phase 1: Cockpit reachable on t560 and Mac (via tunnel).
set -euo pipefail

COCKPIT_PORT="${COCKPIT_PORT:-4370}"
COCKPIT_HOST="${COCKPIT_HOST:-127.0.0.1}"
PROJECT_SLUG="${PROJECT_SLUG:-sounio}"
MAC_SSH="${MAC_SSH:-demetriosagourakis@macbook-pro-de-demetrios-2.tail21cbc4.ts.net}"
TIMEOUT="${TIMEOUT:-20}"
CHECK_MAC="${CHECK_MAC:-1}"

BASE="http://${COCKPIT_HOST}:${COCKPIT_PORT}"
PASS=0
FAIL=0
SKIP=0

pass() { echo "PASS  $*"; PASS=$((PASS + 1)); }
fail() { echo "FAIL  $*"; FAIL=$((FAIL + 1)); }
skip() { echo "SKIP  $*"; SKIP=$((SKIP + 1)); }

check_endpoint_post() {
  local label="$1"
  local url="$2"
  local body="$3"
  local jq_filter="${4:-.}"

  local response
  if response="$(curl -fsS --max-time "${TIMEOUT}" -X POST -H 'Content-Type: application/json' -d "${body}" "${url}" 2>&1)"; then
    if echo "${response}" | jq -e "${jq_filter}" >/dev/null 2>&1; then
      pass "${label} ${url}"
      echo "${response}" | jq -c "${jq_filter}" 2>/dev/null | head -c 400
      echo
    else
      fail "${label}: JSON filter mismatch (${url})"
    fi
  else
    fail "${label}: unreachable (${url}) — ${response}"
  fi
}

check_endpoint() {
  local label="$1"
  local url="$2"
  local jq_filter="${3:-.}"

  if ! command -v curl >/dev/null; then
    fail "${label}: curl missing"
    return
  fi
  if ! command -v jq >/dev/null; then
    fail "${label}: jq missing"
    return
  fi

  local body
  if body="$(curl -fsS --max-time "${TIMEOUT}" "${url}" 2>&1)"; then
  if echo "${body}" | jq -e "${jq_filter}" >/dev/null 2>&1; then
      pass "${label} ${url}"
      echo "${body}" | jq -c "${jq_filter}" 2>/dev/null | head -c 400
      echo
    else
      fail "${label}: JSON filter mismatch (${url})"
    fi
  else
    fail "${label}: unreachable (${url}) — ${body}"
  fi
}

check_mac_endpoint() {
  local label="$1"
  local url="$2"
  local jq_filter="${3:-.}"

  if [[ "${CHECK_MAC}" != "1" ]]; then
    skip "${label} (CHECK_MAC=0)"
    return
  fi

  if ! ssh -o BatchMode=yes -o ConnectTimeout=8 "${MAC_SSH}" true 2>/dev/null; then
    skip "${label}: Mac SSH unreachable (${MAC_SSH})"
    return
  fi

  local remote_cmd
  remote_cmd="set -e; body=\$(curl -fsS --max-time ${TIMEOUT} '${url}'); echo \"\${body}\" | jq -c '${jq_filter}'"
  if out="$(ssh -o BatchMode=yes -o ConnectTimeout=8 "${MAC_SSH}" bash -lc "${remote_cmd}" 2>&1)"; then
    if [[ "${out}" == curl:* ]] || [[ "${out}" == *"Failed to connect"* ]]; then
      fail "${label} (Mac): ${url} — ${out}"
      return
    fi
    pass "${label} (Mac) ${url}"
    echo "${out}" | head -c 400
    echo
  else
    fail "${label} (Mac): ${url} — ${out}"
  fi
}

echo "== Beagle Workbench doctor =="
echo "t560 endpoint: ${BASE}"
echo "project:       ${PROJECT_SLUG}"
echo

echo "-- systemd (t560) --"
if systemctl --user --no-pager --plain is-active project-cockpit-api.service 2>/dev/null; then
  pass "project-cockpit-api.service active"
elif curl -fsS --max-time 3 "${BASE}/api/catalog/executive" >/dev/null 2>&1; then
  pass "cockpit API reachable (systemd unit name may differ)"
else
  fail "project-cockpit-api not active and catalog unreachable"
fi
if [[ "${CHECK_MAC}" == "1" ]]; then
  systemctl --user --no-pager --plain is-active beagle-workbench-cockpit-tunnel.service 2>/dev/null && pass "beagle-workbench-cockpit-tunnel.service active" || fail "beagle-workbench-cockpit-tunnel.service not active (run ./start-workbench-live-bridge.sh)"
fi
echo

echo "-- t560 readbacks --"
check_endpoint "catalog" "${BASE}/api/catalog/executive" '{projects: (.projects | length)}'
check_endpoint "workspace" "${BASE}/api/projects/${PROJECT_SLUG}/go-work-now?depth=deep" '{slug: (.projectSlug // .project.projectSlug // "unknown"), status: (.goWorkNow.workspaceState.status // "unknown")}'
check_endpoint "cluster" "${BASE}/api/cluster/ops/summary" '{status, generatedAt}'
check_endpoint_post "graphrag" "${BASE}/api/workbench/${PROJECT_SLUG}/context/graphrag/query" '{"query":"doctor gate","query_mode":"local","limit":4}' '{node_count, projectSlug}'
check_endpoint "agent-sessions" "${BASE}/api/projects/${PROJECT_SLUG}/agent/sessions" '{sessions: (.sessions | type)}'
check_endpoint "zellij-status" "${BASE}/api/projects/${PROJECT_SLUG}/workspace/zellij/status" '{projectSlug, transport, sessionName}'
HANDOFF_SLUG="${HANDOFF_SLUG:-darwin-mfc}"
handoff_id="$(curl -fsS --max-time "${TIMEOUT}" "${BASE}/api/workbench/${HANDOFF_SLUG}/context/messages/board?limit=8" 2>/dev/null | jq -r '.next_actions[0].message_id // empty' 2>/dev/null || true)"
if [[ -n "${handoff_id}" ]]; then
  encoded_id="$(jq -rn --arg s "${handoff_id}" '$s|@uri')"
  check_endpoint "handoff-compile" "${BASE}/api/workbench/${HANDOFF_SLUG}/context/messages/${encoded_id}/compile" '{schema, handoff: {message_id: .handoff.message_id}}'
else
  skip "handoff-compile (no open handoffs on ${HANDOFF_SLUG})"
fi
zellij_body="$(curl -fsS --max-time "${TIMEOUT}" -X POST -H 'Content-Type: application/json' \
  -d '{"tab":"repo","text":"workbench doctor ping","confirmed":true}' \
  "${BASE}/api/projects/${PROJECT_SLUG}/workspace/zellij/send" 2>&1)" \
  && echo "${zellij_body}" | jq -e '{ok, tab, sessionName}' >/dev/null 2>&1 \
  && pass "zellij-send ${BASE}/api/projects/${PROJECT_SLUG}/workspace/zellij/send" \
  || skip "zellij-send (route present; habitat transport may be offline from t560)"
echo

if [[ "${CHECK_MAC}" == "1" ]]; then
  echo "-- Mac readbacks (127.0.0.1:${COCKPIT_PORT} via tunnel) --"
  MAC_BASE="http://127.0.0.1:${COCKPIT_PORT}"
  check_mac_endpoint "catalog" "${MAC_BASE}/api/catalog/executive" '{projects: (.projects | length)}'
  check_mac_endpoint "workspace" "${MAC_BASE}/api/projects/${PROJECT_SLUG}/go-work-now?depth=deep" '{slug: (.projectSlug // .project.projectSlug // "unknown"), status: (.goWorkNow.workspaceState.status // "unknown")}'
  check_mac_endpoint "cluster" "${MAC_BASE}/api/cluster/ops/summary" '{status, generatedAt}'
  echo
fi

echo "== summary =="
echo "pass=${PASS} fail=${FAIL} skip=${SKIP}"
if [[ "${FAIL}" -gt 0 ]]; then
  echo
  echo "Hints:"
  echo "  t560: cd beagle/beagle-ios/BeagleSuite && ./start-workbench-live-bridge.sh"
  echo "  Mac:  export BEAGLE_COCKPIT_URL=http://127.0.0.1:${COCKPIT_PORT}"
  exit 1
fi
echo "Beagle Workbench Phase 1 gate: PASS"
exit 0
