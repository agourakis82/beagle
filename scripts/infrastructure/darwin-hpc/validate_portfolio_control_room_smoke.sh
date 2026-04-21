#!/usr/bin/env bash
set -euo pipefail

OUT="${OUT:?OUT is required}"

require() {
  command -v "$1" >/dev/null 2>&1 || {
    echo "[FAIL] missing command: $1" >&2
    exit 1
  }
}

require jq

for file in \
  source-summary.json \
  build.log \
  image-load.log \
  deploy-apply.log \
  deploy-rollout.log \
  beagle-health-before.json \
  workstreams-list.json \
  portfolio.json \
  governance-status.json \
  governance-handoff.json \
  governance-last-result.json \
  governance-timeline.json \
  wave1-status.json \
  wave1-handoff.json \
  wave1-last-result.json \
  wave1-timeline.json \
  beagle-health-after-restart.json \
  portfolio-after-restart.json \
  smoke.json \
  final-cluster-health.txt \
  run-id.txt \
  governance-workstream-id.txt \
  wave1-workstream-id.txt \
  expected-default-dev-plane.txt \
  expected-vm-fallback-role.txt \
  expected-governance-state.txt \
  expected-governance-last-transition.txt \
  governance-workspace-id.txt \
  governance-session-id.txt \
  wave1-workspace-id.txt \
  wave1-session-id.txt; do
  [[ -s "${OUT}/${file}" ]] || {
    echo "[FAIL] missing or empty artifact: ${OUT}/${file}" >&2
    exit 1
  }
done

RUN_ID="$(cat "${OUT}/run-id.txt")"
GOVERNANCE_WORKSTREAM="$(cat "${OUT}/governance-workstream-id.txt")"
WAVE1_WORKSTREAM="$(cat "${OUT}/wave1-workstream-id.txt")"
EXPECTED_DEFAULT_DEV_PLANE="$(cat "${OUT}/expected-default-dev-plane.txt")"
EXPECTED_VM_FALLBACK_ROLE="$(cat "${OUT}/expected-vm-fallback-role.txt")"
EXPECTED_GOVERNANCE_STATE="$(cat "${OUT}/expected-governance-state.txt")"
EXPECTED_GOVERNANCE_LAST_TRANSITION="$(cat "${OUT}/expected-governance-last-transition.txt")"
GOVERNANCE_WORKSPACE_ID="$(cat "${OUT}/governance-workspace-id.txt")"
GOVERNANCE_SESSION_ID="$(cat "${OUT}/governance-session-id.txt")"
WAVE1_WORKSPACE_ID="$(cat "${OUT}/wave1-workspace-id.txt")"
WAVE1_SESSION_ID="$(cat "${OUT}/wave1-session-id.txt")"

jq -e \
  --arg run_id "${RUN_ID}" \
  --arg governance_workstream "${GOVERNANCE_WORKSTREAM}" \
  --arg wave1_workstream "${WAVE1_WORKSTREAM}" '
  .run_id == $run_id
  and .governance_workstream == $governance_workstream
  and .wave1_workstream == $wave1_workstream
  and (.control_room_source_present == true or .control_room_source_present == 1)
  and (.timeline_source_present == true or .timeline_source_present == 1)
  and (.http_source_present == true or .http_source_present == 1)
  and (.doc_present == true or .doc_present == 1)
  and (.go_no_go_present == true or .go_no_go_present == 1)
  and (.known_limits_present == true or .known_limits_present == 1)
  and (.registry_present == true or .registry_present == 1)
' "${OUT}/source-summary.json" >/dev/null

jq -e \
  --arg governance_workstream "${GOVERNANCE_WORKSTREAM}" \
  --arg wave1_workstream "${WAVE1_WORKSTREAM}" '
  .status == "ok"
  and (.workstreams | map(.id) | index($governance_workstream) != null)
  and (.workstreams | map(.id) | index($wave1_workstream) != null)
' "${OUT}/workstreams-list.json" >/dev/null

jq -e \
  --arg governance_workstream "${GOVERNANCE_WORKSTREAM}" \
  --arg wave1_workstream "${WAVE1_WORKSTREAM}" \
  --arg expected_default_dev_plane "${EXPECTED_DEFAULT_DEV_PLANE}" \
  --arg expected_vm_fallback_role "${EXPECTED_VM_FALLBACK_ROLE}" \
  --arg expected_governance_state "${EXPECTED_GOVERNANCE_STATE}" \
  --arg expected_governance_last_transition "${EXPECTED_GOVERNANCE_LAST_TRANSITION}" \
  --arg governance_workspace_id "${GOVERNANCE_WORKSPACE_ID}" \
  --arg governance_session_id "${GOVERNANCE_SESSION_ID}" \
  --arg wave1_workspace_id "${WAVE1_WORKSPACE_ID}" \
  --arg wave1_session_id "${WAVE1_SESSION_ID}" '
  .status == "ok"
  and (.canonical_workstream_ids | index($governance_workstream) != null)
  and (.canonical_workstream_ids | index($wave1_workstream) != null)
  and .summary.total_workstreams >= 2
  and .summary.canonical_workstreams >= 2
  and .summary.live_sessions >= 2
  and .summary.fallback_active_workstreams == 0
  and ((.workstreams[] | select(.id == $governance_workstream) | .live_session.workspace_id) == $governance_workspace_id)
  and ((.workstreams[] | select(.id == $governance_workstream) | .live_session.session_id) == $governance_session_id)
  and ((.workstreams[] | select(.id == $governance_workstream) | .default_dev_plane) == $expected_default_dev_plane)
  and ((.workstreams[] | select(.id == $governance_workstream) | .vm_fallback_role) == $expected_vm_fallback_role)
  and ((.workstreams[] | select(.id == $governance_workstream) | .governance_state) == $expected_governance_state)
  and ((.workstreams[] | select(.id == $governance_workstream) | .governance_last_transition) == $expected_governance_last_transition)
  and ((.workstreams[] | select(.id == $wave1_workstream) | .live_session.workspace_id) == $wave1_workspace_id)
  and ((.workstreams[] | select(.id == $wave1_workstream) | .live_session.session_id) == $wave1_session_id)
  and ((.workstreams[] | select(.id == $wave1_workstream) | .default_dev_plane) == $expected_default_dev_plane)
  and ((.workstreams[] | select(.id == $wave1_workstream) | .vm_fallback_role) == $expected_vm_fallback_role)
  and ((.workstreams[] | select(.id == $wave1_workstream) | .governance_state) == $expected_governance_state)
  and ((.workstreams[] | select(.id == $wave1_workstream) | .governance_last_transition) == $expected_governance_last_transition)
' "${OUT}/portfolio.json" >/dev/null

jq -e \
  --arg governance_workstream "${GOVERNANCE_WORKSTREAM}" \
  --arg governance_workspace_id "${GOVERNANCE_WORKSPACE_ID}" \
  --arg governance_session_id "${GOVERNANCE_SESSION_ID}" \
  --arg expected_default_dev_plane "${EXPECTED_DEFAULT_DEV_PLANE}" \
  --arg expected_governance_state "${EXPECTED_GOVERNANCE_STATE}" \
  --arg expected_governance_last_transition "${EXPECTED_GOVERNANCE_LAST_TRANSITION}" '
  .status == "ok"
  and .workstream_id == $governance_workstream
  and .governance_state == $expected_governance_state
  and .governance_last_transition == $expected_governance_last_transition
  and .live_session.workspace_id == $governance_workspace_id
  and .live_session.session_id == $governance_session_id
  and .live_session.active_dev_plane == $expected_default_dev_plane
  and .live_session.fallback_active == false
' "${OUT}/governance-status.json" >/dev/null

jq -e \
  --arg wave1_workstream "${WAVE1_WORKSTREAM}" \
  --arg wave1_workspace_id "${WAVE1_WORKSPACE_ID}" \
  --arg wave1_session_id "${WAVE1_SESSION_ID}" \
  --arg expected_default_dev_plane "${EXPECTED_DEFAULT_DEV_PLANE}" \
  --arg expected_governance_state "${EXPECTED_GOVERNANCE_STATE}" \
  --arg expected_governance_last_transition "${EXPECTED_GOVERNANCE_LAST_TRANSITION}" '
  .status == "ok"
  and .workstream_id == $wave1_workstream
  and .governance_state == $expected_governance_state
  and .governance_last_transition == $expected_governance_last_transition
  and .live_session.workspace_id == $wave1_workspace_id
  and .live_session.session_id == $wave1_session_id
  and .live_session.active_dev_plane == $expected_default_dev_plane
  and .live_session.fallback_active == false
' "${OUT}/wave1-status.json" >/dev/null

jq -e \
  --arg governance_workstream "${GOVERNANCE_WORKSTREAM}" \
  --arg governance_session_id "${GOVERNANCE_SESSION_ID}" '
  .status == "ok"
  and .workstream_id == $governance_workstream
  and .identity.session_id == $governance_session_id
  and .returned_events == 1
  and (.events | length) == 1
' "${OUT}/governance-timeline.json" >/dev/null

jq -e \
  --arg wave1_workstream "${WAVE1_WORKSTREAM}" \
  --arg wave1_session_id "${WAVE1_SESSION_ID}" '
  .status == "ok"
  and .workstream_id == $wave1_workstream
  and .identity.session_id == $wave1_session_id
  and .returned_events == 1
  and (.events | length) == 1
' "${OUT}/wave1-timeline.json" >/dev/null

jq -e \
  --arg governance_workstream "${GOVERNANCE_WORKSTREAM}" \
  --arg wave1_workstream "${WAVE1_WORKSTREAM}" \
  --arg governance_workspace_id "${GOVERNANCE_WORKSPACE_ID}" \
  --arg governance_session_id "${GOVERNANCE_SESSION_ID}" \
  --arg wave1_workspace_id "${WAVE1_WORKSPACE_ID}" \
  --arg wave1_session_id "${WAVE1_SESSION_ID}" '
  .status == "ok"
  and ((.workstreams[] | select(.id == $governance_workstream) | .live_session.workspace_id) == $governance_workspace_id)
  and ((.workstreams[] | select(.id == $governance_workstream) | .live_session.session_id) == $governance_session_id)
  and ((.workstreams[] | select(.id == $wave1_workstream) | .live_session.workspace_id) == $wave1_workspace_id)
  and ((.workstreams[] | select(.id == $wave1_workstream) | .live_session.session_id) == $wave1_session_id)
' "${OUT}/portfolio-after-restart.json" >/dev/null

jq -e \
  --arg run_id "${RUN_ID}" \
  --arg governance_workstream "${GOVERNANCE_WORKSTREAM}" \
  --arg wave1_workstream "${WAVE1_WORKSTREAM}" \
  --arg governance_workspace_id "${GOVERNANCE_WORKSPACE_ID}" \
  --arg governance_session_id "${GOVERNANCE_SESSION_ID}" \
  --arg wave1_workspace_id "${WAVE1_WORKSPACE_ID}" \
  --arg wave1_session_id "${WAVE1_SESSION_ID}" '
  .status == "ok"
  and .run_id == $run_id
  and .governance_workstream == $governance_workstream
  and .wave1_workstream == $wave1_workstream
  and .portfolio_workstream_count >= 2
  and .canonical_workstream_count >= 2
  and .live_session_count >= 2
  and .governance_workspace_id == $governance_workspace_id
  and .governance_session_id == $governance_session_id
  and .wave1_workspace_id == $wave1_workspace_id
  and .wave1_session_id == $wave1_session_id
  and .after_restart_governance_session_id == $governance_session_id
  and .after_restart_wave1_session_id == $wave1_session_id
' "${OUT}/smoke.json" >/dev/null

grep -Eq 'deployment.apps/beagle-core' "${OUT}/final-cluster-health.txt"
grep -Eq 'Slurmctld\(primary\).*UP' "${OUT}/final-cluster-health.txt"

echo "[OK] portfolio control room smoke validation passed"
