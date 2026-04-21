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
  evidence-pack.json \
  beagle-health-after-restart.json \
  bootstrap-after-restart.json \
  evidence-pack-after-restart.json \
  smoke.json \
  final-cluster-health.txt \
  workspace-id.txt \
  seed-session-id.txt \
  seed-published-result-job-id.txt \
  expected-program.txt \
  expected-campaign.txt \
  expected-workstream.txt \
  expected-experiment.txt \
  expected-manuscript-target.txt \
  expected-dataset-root.txt \
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
EXPECTED_EXPERIMENT="$(cat "${OUT}/expected-experiment.txt")"
EXPECTED_MANUSCRIPT_TARGET="$(cat "${OUT}/expected-manuscript-target.txt")"
EXPECTED_DATASET_ROOT="$(cat "${OUT}/expected-dataset-root.txt")"
EXPECTED_RECOMMENDED_RECIPE_KIND="$(cat "${OUT}/expected-recommended-recipe-kind.txt")"
EXPECTED_PROVIDER="$(cat "${OUT}/expected-provider.txt")"
EXPECTED_MODEL="$(cat "${OUT}/expected-model.txt")"

jq -e \
  --arg expected_program "${EXPECTED_PROGRAM}" \
  --arg expected_campaign "${EXPECTED_CAMPAIGN}" \
  --arg expected_workstream "${EXPECTED_WORKSTREAM}" \
  --arg expected_experiment "${EXPECTED_EXPERIMENT}" \
  --arg expected_manuscript_target "${EXPECTED_MANUSCRIPT_TARGET}" \
  --arg expected_dataset_root "${EXPECTED_DATASET_ROOT}" \
  --arg expected_recommended_recipe_kind "${EXPECTED_RECOMMENDED_RECIPE_KIND}" \
  --arg expected_provider "${EXPECTED_PROVIDER}" \
  --arg expected_model "${EXPECTED_MODEL}" '
  .expected_program == $expected_program
  and .expected_campaign == $expected_campaign
  and .expected_workstream == $expected_workstream
  and .expected_experiment == $expected_experiment
  and .expected_manuscript_target == $expected_manuscript_target
  and .expected_dataset_root == $expected_dataset_root
  and .expected_recommended_recipe_kind == $expected_recommended_recipe_kind
  and .expected_provider == $expected_provider
  and .expected_model == $expected_model
  and (.evidence_pack_source_present == true or .evidence_pack_source_present == 1)
  and (.http_source_present == true or .http_source_present == 1)
  and (.doc_present == true or .doc_present == 1)
  and (.go_no_go_present == true or .go_no_go_present == 1)
  and (.known_limits_present == true or .known_limits_present == 1)
  and (.contract_present == true or .contract_present == 1)
  and (.manuscript_contract_present == true or .manuscript_contract_present == 1)
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
  --arg expected_experiment "${EXPECTED_EXPERIMENT}" \
  --arg expected_manuscript_target "${EXPECTED_MANUSCRIPT_TARGET}" \
  --arg expected_dataset_root "${EXPECTED_DATASET_ROOT}" \
  --arg expected_recommended_recipe_kind "${EXPECTED_RECOMMENDED_RECIPE_KIND}" \
  --arg workspace_id "${WORKSPACE_ID}" \
  --arg session_id "${SESSION_ID}" \
  --argjson published_result_job_id "${PUBLISHED_RESULT_JOB_ID}" '
  .status == "ok"
  and .pack.program_id == $expected_program
  and .pack.campaign_id == $expected_campaign
  and .pack.active_workstream_id == $expected_workstream
  and .pack.workspace_id == $workspace_id
  and .pack.session_id == $session_id
  and .pack.governance_state == "canonical"
  and ((.pack.experiment_refs | map(.experiment_id) | index($expected_experiment)) != null)
  and ((.pack.dataset_refs | map(.artifact_root) | index($expected_dataset_root)) != null)
  and ((.pack.result_refs | length) >= 1)
  and (.pack.result_refs[0].job_id == $published_result_job_id)
  and ((.pack.memory_refs | length) >= 1)
  and ((.pack.physio_refs | length) >= 1)
  and ((.pack.recipe_refs | length) >= 1)
  and (.pack.recipe_refs[0].kind == $expected_recommended_recipe_kind)
  and (.pack.manuscript_target.id == $expected_manuscript_target)
  and ((.pack.evidence_targets | length) >= 1)
  and .pack.provenance.profile == "w3c-prov-bounded"
  and ((.pack.provenance.activities | length) >= 1)
  and ((.pack.provenance.entities | length) >= 1)
  and .pack.citation.profile == "datacite-4.7-ready"
  and ((.pack.citation.related_identifiers | length) >= 1)
' "${OUT}/evidence-pack.json" >/dev/null

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
  and .pack.program_id == $expected_program
  and .pack.campaign_id == $expected_campaign
  and .pack.workspace_id == $workspace_id
  and .pack.session_id == $session_id
' "${OUT}/evidence-pack-after-restart.json" >/dev/null

jq -e \
  --arg workspace_id "${WORKSPACE_ID}" \
  --arg session_id "${SESSION_ID}" \
  --arg expected_program "${EXPECTED_PROGRAM}" \
  --arg expected_campaign "${EXPECTED_CAMPAIGN}" \
  --arg expected_workstream "${EXPECTED_WORKSTREAM}" \
  --arg expected_experiment "${EXPECTED_EXPERIMENT}" '
  .status == "ok"
  and .workspace_id == $workspace_id
  and .session_id == $session_id
  and .expected_program == $expected_program
  and .expected_campaign == $expected_campaign
  and .expected_workstream == $expected_workstream
  and .expected_experiment == $expected_experiment
  and .result_ref_count >= 1
  and .memory_ref_count >= 1
  and .physio_ref_count >= 1
  and .recipe_ref_count >= 1
  and .restart_recovered_session == true
' "${OUT}/smoke.json" >/dev/null

grep -Eq 'deployment.apps/beagle-core' "${OUT}/final-cluster-health.txt"
grep -Eq 'Slurmctld\(primary\).*UP' "${OUT}/final-cluster-health.txt"

echo "[OK] evidence pack validator passed"
