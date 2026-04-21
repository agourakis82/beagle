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
  bootstrap-before.json \
  seed-pilot.json \
  physio-ingest-response.json \
  ingest-response.json \
  query-response.json \
  program-context-packet.json \
  campaign-context-packet.json \
  tool-cursor.json \
  tool-claude-code.json \
  tool-codex.json \
  beagle-health-after-restart.json \
  bootstrap-after-restart.json \
  program-context-packet-after-restart.json \
  smoke.json \
  final-cluster-health.txt \
  workspace-id.txt \
  seed-session-id.txt \
  seed-published-result-job-id.txt \
  expected-program.txt \
  expected-campaign.txt \
  expected-workstream.txt \
  expected-recommended-recipe-kind.txt \
  expected-provider.txt \
  expected-model.txt; do
  [[ -s "${OUT}/${file}" ]] || {
    echo "[FAIL] missing or empty artifact: ${OUT}/${file}" >&2
    exit 1
  }
done

WORKSPACE_ID="$(cat "${OUT}/workspace-id.txt")"
SESSION_ID="$(cat "${OUT}/seed-session-id.txt")"
PUBLISHED_RESULT_JOB_ID="$(cat "${OUT}/seed-published-result-job-id.txt")"
EXPECTED_PROGRAM="$(cat "${OUT}/expected-program.txt")"
EXPECTED_CAMPAIGN="$(cat "${OUT}/expected-campaign.txt")"
EXPECTED_WORKSTREAM="$(cat "${OUT}/expected-workstream.txt")"
EXPECTED_RECOMMENDED_RECIPE_KIND="$(cat "${OUT}/expected-recommended-recipe-kind.txt")"
EXPECTED_PROVIDER="$(cat "${OUT}/expected-provider.txt")"
EXPECTED_MODEL="$(cat "${OUT}/expected-model.txt")"

jq -e \
  --arg expected_program "${EXPECTED_PROGRAM}" \
  --arg expected_campaign "${EXPECTED_CAMPAIGN}" \
  --arg expected_workstream "${EXPECTED_WORKSTREAM}" \
  --arg expected_recommended_recipe_kind "${EXPECTED_RECOMMENDED_RECIPE_KIND}" \
  --arg expected_provider "${EXPECTED_PROVIDER}" \
  --arg expected_model "${EXPECTED_MODEL}" '
  .expected_program == $expected_program
  and .expected_campaign == $expected_campaign
  and .expected_workstream == $expected_workstream
  and .expected_recommended_recipe_kind == $expected_recommended_recipe_kind
  and .expected_provider == $expected_provider
  and .expected_model == $expected_model
  and (.program_context_source_present == true or .program_context_source_present == 1)
  and (.cockpit_source_present == true or .cockpit_source_present == 1)
  and (.http_source_present == true or .http_source_present == 1)
  and (.doc_present == true or .doc_present == 1)
  and (.go_no_go_present == true or .go_no_go_present == 1)
  and (.known_limits_present == true or .known_limits_present == 1)
  and (.contract_present == true or .contract_present == 1)
' "${OUT}/source-summary.json" >/dev/null

jq -e \
  --arg workspace_id "${WORKSPACE_ID}" \
  --arg session_id "${SESSION_ID}" \
  --argjson published_result_job_id "${PUBLISHED_RESULT_JOB_ID}" '
  .status == "ok"
  and .workspace_id == $workspace_id
  and .session_id == $session_id
  and .published_result.job_id == $published_result_job_id
' "${OUT}/seed-pilot.json" >/dev/null

jq -e '.status == "ok" and .memory_id != null and .physio_attached == true and .experiment_flags_attached == true' "${OUT}/ingest-response.json" >/dev/null

jq -e \
  --arg session_id "${SESSION_ID}" '
  (.highlights | length) >= 1
  and (.recent_physio != null)
  and ((.highlights | map(.conversation_id) | index($session_id)) != null)
' "${OUT}/query-response.json" >/dev/null

jq -e \
  --arg expected_program "${EXPECTED_PROGRAM}" \
  --arg expected_campaign "${EXPECTED_CAMPAIGN}" \
  --arg expected_workstream "${EXPECTED_WORKSTREAM}" \
  --arg workspace_id "${WORKSPACE_ID}" \
  --arg session_id "${SESSION_ID}" \
  --arg expected_recommended_recipe_kind "${EXPECTED_RECOMMENDED_RECIPE_KIND}" \
  --arg expected_provider "${EXPECTED_PROVIDER}" \
  --arg expected_model "${EXPECTED_MODEL}" \
  --argjson published_result_job_id "${PUBLISHED_RESULT_JOB_ID}" '
  .status == "ok"
  and .packet.program_id == $expected_program
  and .packet.campaign_id == $expected_campaign
  and .packet.active_workstream_id == $expected_workstream
  and .packet.workspace_id == $workspace_id
  and .packet.session_id == $session_id
  and .packet.governance_state == "canonical"
  and .packet.recommended_next_recipe.kind == $expected_recommended_recipe_kind
  and .packet.latest_physio != null
  and .packet.experiment_flags.provider == $expected_provider
  and .packet.experiment_flags.model == $expected_model
  and (.packet.latest_results | length) >= 1
  and .packet.latest_results[0].last_result.summary.job_id == $published_result_job_id
  and (.packet.latest_memory_hits | length) >= 1
  and (.packet.evidence_targets | length) >= 1
  and (.packet.manuscript_targets | length) >= 1
' "${OUT}/program-context-packet.json" >/dev/null

jq -e \
  --arg expected_program "${EXPECTED_PROGRAM}" \
  --arg expected_campaign "${EXPECTED_CAMPAIGN}" \
  --arg expected_workstream "${EXPECTED_WORKSTREAM}" '
  .status == "ok"
  and .packet.program_id == $expected_program
  and .packet.campaign_id == $expected_campaign
  and .packet.active_workstream_id == $expected_workstream
  and (.packet.workstream_ids | index($expected_workstream) != null)
' "${OUT}/campaign-context-packet.json" >/dev/null

for tool_file in tool-cursor.json tool-claude-code.json tool-codex.json; do
  jq -e \
    --arg expected_program "${EXPECTED_PROGRAM}" \
    --arg expected_campaign "${EXPECTED_CAMPAIGN}" \
    --arg expected_workstream "${EXPECTED_WORKSTREAM}" '
    .status == "ok"
    and .tool.program_context_packet_path == ("/api/darwin/programs/" + $expected_program + "/context-packet")
    and .tool.campaign_context_packet_path == ("/api/darwin/campaigns/" + $expected_campaign + "/context-packet")
    and .context_packet.workstream_id == $expected_workstream
  ' "${OUT}/${tool_file}" >/dev/null
done

jq -e \
  --arg workspace_id "${WORKSPACE_ID}" \
  --arg session_id "${SESSION_ID}" '
  .status == "ok"
  and .workspace_id == $workspace_id
  and .session_id == $session_id
  and .recovered_session == true
' "${OUT}/bootstrap-after-restart.json" >/dev/null

jq -e \
  --arg expected_program "${EXPECTED_PROGRAM}" \
  --arg expected_campaign "${EXPECTED_CAMPAIGN}" \
  --arg workspace_id "${WORKSPACE_ID}" \
  --arg session_id "${SESSION_ID}" '
  .status == "ok"
  and .packet.program_id == $expected_program
  and .packet.campaign_id == $expected_campaign
  and .packet.workspace_id == $workspace_id
  and .packet.session_id == $session_id
' "${OUT}/program-context-packet-after-restart.json" >/dev/null

jq -e \
  --arg workspace_id "${WORKSPACE_ID}" \
  --arg session_id "${SESSION_ID}" \
  --arg expected_program "${EXPECTED_PROGRAM}" \
  --arg expected_campaign "${EXPECTED_CAMPAIGN}" \
  --arg expected_workstream "${EXPECTED_WORKSTREAM}" '
  .status == "ok"
  and .workspace_id == $workspace_id
  and .session_id == $session_id
  and .expected_program == $expected_program
  and .expected_campaign == $expected_campaign
  and .expected_workstream == $expected_workstream
  and .latest_result_count >= 1
  and .latest_memory_hit_count >= 1
  and .latest_physio_source != null
  and .restart_recovered_session == true
' "${OUT}/smoke.json" >/dev/null

grep -Eq 'deployment.apps/beagle-core' "${OUT}/final-cluster-health.txt"
grep -Eq 'Slurmctld\(primary\).*UP' "${OUT}/final-cluster-health.txt"

echo "[OK] program context packet validator passed"
