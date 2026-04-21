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
  physio-ingest-response.json \
  physio-attachment.json \
  ingest-response.json \
  query-response.json \
  context-packet.json \
  cockpit.json \
  tool-cursor.json \
  tool-claude-code.json \
  tool-codex.json \
  beagle-health-after-restart.json \
  bootstrap-after-restart.json \
  context-packet-after-restart.json \
  smoke.json \
  final-cluster-health.txt \
  workspace-id.txt \
  seed-session-id.txt \
  seed-published-result-job-id.txt \
  expected-workstream.txt \
  expected-recommended-recipe-kind.txt \
  expected-memory-source.txt \
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
EXPECTED_WORKSTREAM="$(cat "${OUT}/expected-workstream.txt")"
EXPECTED_RECOMMENDED_RECIPE_KIND="$(cat "${OUT}/expected-recommended-recipe-kind.txt")"
EXPECTED_MEMORY_SOURCE="$(cat "${OUT}/expected-memory-source.txt")"
EXPECTED_PROVIDER="$(cat "${OUT}/expected-provider.txt")"
EXPECTED_MODEL="$(cat "${OUT}/expected-model.txt")"

jq -e \
  --arg expected_workstream "${EXPECTED_WORKSTREAM}" \
  --arg expected_recommended_recipe_kind "${EXPECTED_RECOMMENDED_RECIPE_KIND}" \
  --arg expected_memory_source "${EXPECTED_MEMORY_SOURCE}" \
  --arg expected_provider "${EXPECTED_PROVIDER}" \
  --arg expected_model "${EXPECTED_MODEL}" '
  .expected_workstream == $expected_workstream
  and .expected_recommended_recipe_kind == $expected_recommended_recipe_kind
  and .expected_memory_source == $expected_memory_source
  and .expected_provider == $expected_provider
  and .expected_model == $expected_model
  and (.context_packet_source_present == true or .context_packet_source_present == 1)
  and (.cockpit_source_present == true or .cockpit_source_present == 1)
  and (.http_source_present == true or .http_source_present == 1)
  and (.memory_source_present == true or .memory_source_present == 1)
  and (.doc_present == true or .doc_present == 1)
  and (.go_no_go_present == true or .go_no_go_present == 1)
  and (.known_limits_present == true or .known_limits_present == 1)
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

jq -e '.status == "ok" and .snapshot != null and .snapshot.source != null' "${OUT}/physio-attachment.json" >/dev/null

jq -e '.status == "ok" and .memory_id != null and .physio_attached == true and .experiment_flags_attached == true' "${OUT}/ingest-response.json" >/dev/null

jq -e \
  --arg session_id "${SESSION_ID}" '
  (.highlights | length) >= 1
  and (.recent_physio != null)
  and ((.highlights | map(.conversation_id) | index($session_id)) != null)
' "${OUT}/query-response.json" >/dev/null

jq -e \
  --arg expected_workstream "${EXPECTED_WORKSTREAM}" \
  --arg workspace_id "${WORKSPACE_ID}" \
  --arg session_id "${SESSION_ID}" \
  --arg expected_recommended_recipe_kind "${EXPECTED_RECOMMENDED_RECIPE_KIND}" \
  --arg expected_memory_source "${EXPECTED_MEMORY_SOURCE}" \
  --arg expected_provider "${EXPECTED_PROVIDER}" \
  --arg expected_model "${EXPECTED_MODEL}" \
  --argjson published_result_job_id "${PUBLISHED_RESULT_JOB_ID}" '
  .status == "ok"
  and .packet.workstream_id == $expected_workstream
  and .packet.workspace_id == $workspace_id
  and .packet.session_id == $session_id
  and .packet.handoff.handoff_present == true
  and .packet.last_result.summary.job_id == $published_result_job_id
  and .packet.last_successful_task.profile_id == "cpu-batch-v1"
  and .packet.latest_physio != null
  and .packet.experiment_flags.provider == $expected_provider
  and .packet.experiment_flags.model == $expected_model
  and .packet.experiment_flags.hrv_aware == true
  and .packet.recommended_recipe.kind == $expected_recommended_recipe_kind
  and (.packet.memory_hits | length) >= 1
  and .packet.memory_hits[0].source == $expected_memory_source
' "${OUT}/context-packet.json" >/dev/null

jq -e \
  --arg workspace_id "${WORKSPACE_ID}" \
  --arg session_id "${SESSION_ID}" '
  .status == "ok"
  and .context_packet.workspace_id == $workspace_id
  and .context_packet.session_id == $session_id
  and (.tool_dock | length) == 3
' "${OUT}/cockpit.json" >/dev/null

for tool_file in tool-cursor.json tool-claude-code.json tool-codex.json; do
  jq -e \
    --arg expected_workstream "${EXPECTED_WORKSTREAM}" \
    --arg workspace_id "${WORKSPACE_ID}" \
    --arg session_id "${SESSION_ID}" '
    .status == "ok"
    and .tool.context_packet_path == ("/api/darwin/workstreams/" + $expected_workstream + "/context-packet")
    and .context_packet.workstream_id == $expected_workstream
    and .context_packet.workspace_id == $workspace_id
    and .context_packet.session_id == $session_id
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
  --arg workspace_id "${WORKSPACE_ID}" \
  --arg session_id "${SESSION_ID}" '
  .status == "ok"
  and .packet.workspace_id == $workspace_id
  and .packet.session_id == $session_id
' "${OUT}/context-packet-after-restart.json" >/dev/null

jq -e \
  --arg workspace_id "${WORKSPACE_ID}" \
  --arg session_id "${SESSION_ID}" \
  --arg expected_workstream "${EXPECTED_WORKSTREAM}" \
  --arg expected_recommended_recipe_kind "${EXPECTED_RECOMMENDED_RECIPE_KIND}" '
  .status == "ok"
  and .workspace_id == $workspace_id
  and .session_id == $session_id
  and .expected_workstream == $expected_workstream
  and .expected_recommended_recipe_kind == $expected_recommended_recipe_kind
  and .packet_memory_hit_count >= 1
  and .packet_latest_physio_source != ""
  and .restart_recovered_session == true
' "${OUT}/smoke.json" >/dev/null

grep -Eq 'deployment.apps/beagle-core' "${OUT}/final-cluster-health.txt"
grep -Eq 'Slurmctld\(primary\).*UP' "${OUT}/final-cluster-health.txt"

echo "[OK] memory-aware workstream context packet validator passed"
