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
  deploy-apply.log \
  deploy-rollout.log \
  beagle-health-before.json \
  bootstrap-before.json \
  seed-pilot.json \
  cockpit.json \
  cockpit.html \
  tool-cursor.json \
  tool-claude-code.json \
  tool-codex.json \
  beagle-health-after-restart.json \
  bootstrap-after-restart.json \
  cockpit-after-restart.json \
  smoke.json \
  final-cluster-health.txt \
  workspace-id.txt \
  seed-session-id.txt \
  seed-published-result-job-id.txt \
  expected-workstream.txt \
  expected-repo.txt \
  expected-branch.txt \
  expected-default-dev-plane.txt \
  expected-vm-fallback-role.txt \
  expected-promotion-scope.txt \
  expected-governance-state.txt \
  expected-last-transition.txt; do
  [[ -s "${OUT}/${file}" ]] || {
    echo "[FAIL] missing or empty artifact: ${OUT}/${file}" >&2
    exit 1
  }
done

WORKSPACE_ID="$(cat "${OUT}/workspace-id.txt")"
SESSION_ID="$(cat "${OUT}/seed-session-id.txt")"
PUBLISHED_RESULT_JOB_ID="$(cat "${OUT}/seed-published-result-job-id.txt")"
EXPECTED_WORKSTREAM="$(cat "${OUT}/expected-workstream.txt")"
EXPECTED_REPO="$(cat "${OUT}/expected-repo.txt")"
EXPECTED_BRANCH="$(cat "${OUT}/expected-branch.txt")"
EXPECTED_DEFAULT_DEV_PLANE="$(cat "${OUT}/expected-default-dev-plane.txt")"
EXPECTED_VM_FALLBACK_ROLE="$(cat "${OUT}/expected-vm-fallback-role.txt")"
EXPECTED_PROMOTION_SCOPE="$(cat "${OUT}/expected-promotion-scope.txt")"
EXPECTED_GOVERNANCE_STATE="$(cat "${OUT}/expected-governance-state.txt")"
EXPECTED_LAST_TRANSITION="$(cat "${OUT}/expected-last-transition.txt")"

jq -e \
  --arg expected_workstream "${EXPECTED_WORKSTREAM}" \
  --arg expected_governance_state "${EXPECTED_GOVERNANCE_STATE}" \
  --arg expected_last_transition "${EXPECTED_LAST_TRANSITION}" '
  .expected_workstream == $expected_workstream
  and .expected_governance_state == $expected_governance_state
  and .expected_last_transition == $expected_last_transition
  and (.cockpit_source_present == true or .cockpit_source_present == 1)
  and (.http_source_present == true or .http_source_present == 1)
  and (.doc_present == true or .doc_present == 1)
  and (.go_no_go_present == true or .go_no_go_present == 1)
  and (.known_limits_present == true or .known_limits_present == 1)
' "${OUT}/source-summary.json" >/dev/null

jq -e \
  --arg workspace_id "${WORKSPACE_ID}" \
  --arg session_id "${SESSION_ID}" '
  .status == "ok"
  and .workspace_id == $workspace_id
  and .session_id == $session_id
  and .published_result.job_id != null
  and .last_successful_task.published_result_job_id != null
' "${OUT}/seed-pilot.json" >/dev/null

jq -e \
  --arg expected_workstream "${EXPECTED_WORKSTREAM}" \
  --arg workspace_id "${WORKSPACE_ID}" \
  --arg session_id "${SESSION_ID}" \
  --arg expected_repo "${EXPECTED_REPO}" \
  --arg expected_branch "${EXPECTED_BRANCH}" \
  --arg expected_default_dev_plane "${EXPECTED_DEFAULT_DEV_PLANE}" \
  --arg expected_vm_fallback_role "${EXPECTED_VM_FALLBACK_ROLE}" \
  --arg expected_promotion_scope "${EXPECTED_PROMOTION_SCOPE}" \
  --arg expected_governance_state "${EXPECTED_GOVERNANCE_STATE}" \
  --arg expected_last_transition "${EXPECTED_LAST_TRANSITION}" \
  --argjson published_result_job_id "${PUBLISHED_RESULT_JOB_ID}" '
  .status == "ok"
  and .workstream_id == $expected_workstream
  and .envelope.workspace_id == $workspace_id
  and .envelope.session_id == $session_id
  and .envelope.repo == $expected_repo
  and .envelope.branch == $expected_branch
  and .envelope.default_dev_plane == $expected_default_dev_plane
  and .envelope.vm_fallback_role == $expected_vm_fallback_role
  and .envelope.promotion_scope == $expected_promotion_scope
  and .envelope.governance_state == $expected_governance_state
  and .envelope.governance_last_transition == $expected_last_transition
  and .envelope.fallback_active == false
  and .handoff.handoff_present == true
  and .last_result.available == true
  and .last_result.summary.job_id == $published_result_job_id
  and (.recipes | length) >= 4
  and (.tool_dock | length) == 3
  and (.tool_dock | map(.tool_id) | index("cursor") != null)
  and (.tool_dock | map(.tool_id) | index("claude-code") != null)
  and (.tool_dock | map(.tool_id) | index("codex") != null)
' "${OUT}/cockpit.json" >/dev/null

for tool_file in tool-cursor.json tool-claude-code.json tool-codex.json; do
  jq -e \
    --arg workspace_id "${WORKSPACE_ID}" \
    --arg session_id "${SESSION_ID}" '
    .status == "ok"
    and .tool.launch_surface_kind == "beagle-session-envelope"
    and .envelope.workspace_id == $workspace_id
    and .envelope.session_id == $session_id
    and .handoff.handoff_present == true
    and (.recipe_ids | length) >= 4
  ' "${OUT}/${tool_file}" >/dev/null
done

grep -q 'Beagle Premium Tool Dock MVP' "${OUT}/cockpit.html"
grep -q 'Open in Cursor' "${OUT}/cockpit.html"
grep -q 'Open Claude Code' "${OUT}/cockpit.html"
grep -q 'Open Codex' "${OUT}/cockpit.html"
grep -q "${SESSION_ID}" "${OUT}/cockpit.html"

jq -e \
  --arg workspace_id "${WORKSPACE_ID}" \
  --arg session_id "${SESSION_ID}" '
  .status == "ok"
  and .workspace_id == $workspace_id
  and .session_id == $session_id
  and .recovered_session == true
' "${OUT}/bootstrap-after-restart.json" >/dev/null

jq -e \
  --arg workspace_id "${WORKSPACE_ID}" \
  --arg session_id "${SESSION_ID}" '
  .status == "ok"
  and .envelope.workspace_id == $workspace_id
  and .envelope.session_id == $session_id
  and .handoff.handoff_present == true
' "${OUT}/cockpit-after-restart.json" >/dev/null

jq -e \
  --arg workspace_id "${WORKSPACE_ID}" \
  --arg session_id "${SESSION_ID}" \
  --arg expected_workstream "${EXPECTED_WORKSTREAM}" \
  --arg expected_repo "${EXPECTED_REPO}" \
  --arg expected_branch "${EXPECTED_BRANCH}" \
  --arg expected_default_dev_plane "${EXPECTED_DEFAULT_DEV_PLANE}" \
  --arg expected_vm_fallback_role "${EXPECTED_VM_FALLBACK_ROLE}" \
  --arg expected_promotion_scope "${EXPECTED_PROMOTION_SCOPE}" \
  --arg expected_governance_state "${EXPECTED_GOVERNANCE_STATE}" \
  --arg expected_last_transition "${EXPECTED_LAST_TRANSITION}" '
  .status == "ok"
  and .workspace_id == $workspace_id
  and .session_id == $session_id
  and .expected_workstream == $expected_workstream
  and .expected_repo == $expected_repo
  and .expected_branch == $expected_branch
  and .expected_default_dev_plane == $expected_default_dev_plane
  and .expected_vm_fallback_role == $expected_vm_fallback_role
  and .expected_promotion_scope == $expected_promotion_scope
  and .expected_governance_state == $expected_governance_state
  and .expected_last_transition == $expected_last_transition
  and .cockpit_recipe_count >= 4
  and .cockpit_handoff_present == true
  and .cursor_tool_id == "cursor"
  and .claude_tool_id == "claude-code"
  and .codex_tool_id == "codex"
  and .restart_recovered_session == true
' "${OUT}/smoke.json" >/dev/null

grep -Eq 'deployment.apps/beagle-core' "${OUT}/final-cluster-health.txt"
grep -Eq 'Slurmctld\(primary\).*UP' "${OUT}/final-cluster-health.txt"

echo "[OK] premium tool dock MVP smoke validation passed"
