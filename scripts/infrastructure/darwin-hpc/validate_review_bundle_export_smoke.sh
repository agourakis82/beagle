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
  review-bundle.json \
  ro-crate-metadata.json \
  beagle-health-after-restart.json \
  bootstrap-after-restart.json \
  review-bundle-after-restart.json \
  ro-crate-metadata-after-restart.json \
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
  expected-recommended-recipe-kind.txt \
  expected-provider.txt \
  expected-model.txt \
  expected-export-profile.txt \
  expected-readiness-state.txt; do
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
EXPECTED_RECOMMENDED_RECIPE_KIND="$(cat "${OUT}/expected-recommended-recipe-kind.txt")"
EXPECTED_PROVIDER="$(cat "${OUT}/expected-provider.txt")"
EXPECTED_MODEL="$(cat "${OUT}/expected-model.txt")"
EXPECTED_EXPORT_PROFILE="$(cat "${OUT}/expected-export-profile.txt")"
EXPECTED_READINESS_STATE="$(cat "${OUT}/expected-readiness-state.txt")"

jq -e \
  --arg expected_program "${EXPECTED_PROGRAM}" \
  --arg expected_campaign "${EXPECTED_CAMPAIGN}" \
  --arg expected_workstream "${EXPECTED_WORKSTREAM}" \
  --arg expected_experiment "${EXPECTED_EXPERIMENT}" \
  --arg expected_manuscript_target "${EXPECTED_MANUSCRIPT_TARGET}" \
  --arg expected_recommended_recipe_kind "${EXPECTED_RECOMMENDED_RECIPE_KIND}" \
  --arg expected_provider "${EXPECTED_PROVIDER}" \
  --arg expected_model "${EXPECTED_MODEL}" \
  --arg expected_export_profile "${EXPECTED_EXPORT_PROFILE}" \
  --arg expected_readiness_state "${EXPECTED_READINESS_STATE}" '
  .expected_program == $expected_program
  and .expected_campaign == $expected_campaign
  and .expected_workstream == $expected_workstream
  and .expected_experiment == $expected_experiment
  and .expected_manuscript_target == $expected_manuscript_target
  and .expected_recommended_recipe_kind == $expected_recommended_recipe_kind
  and .expected_provider == $expected_provider
  and .expected_model == $expected_model
  and .expected_export_profile == $expected_export_profile
  and .expected_readiness_state == $expected_readiness_state
  and (.review_bundle_source_present == true or .review_bundle_source_present == 1)
  and (.http_source_present == true or .http_source_present == 1)
  and (.doc_present == true or .doc_present == 1)
  and (.go_no_go_present == true or .go_no_go_present == 1)
  and (.known_limits_present == true or .known_limits_present == 1)
  and (.contract_present == true or .contract_present == 1)
  and (.rocrate_profile_present == true or .rocrate_profile_present == 1)
  and (.datacite_present == true or .datacite_present == 1)
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
  --arg expected_program "${EXPECTED_PROGRAM}" \
  --arg expected_campaign "${EXPECTED_CAMPAIGN}" \
  --arg expected_workstream "${EXPECTED_WORKSTREAM}" \
  --arg expected_manuscript_target "${EXPECTED_MANUSCRIPT_TARGET}" \
  --arg expected_export_profile "${EXPECTED_EXPORT_PROFILE}" \
  --arg expected_readiness_state "${EXPECTED_READINESS_STATE}" \
  --arg workspace_id "${WORKSPACE_ID}" \
  --arg session_id "${SESSION_ID}" '
  .status == "ok"
  and .phase == "B19.5"
  and .bundle.bundle_version == "beagle-review-bundle-v1"
  and .bundle.export_profile == $expected_export_profile
  and .bundle.program_id == $expected_program
  and .bundle.campaign_id == $expected_campaign
  and .bundle.active_workstream_id == $expected_workstream
  and .bundle.workspace_id == $workspace_id
  and .bundle.session_id == $session_id
  and .bundle.manuscript_target.id == $expected_manuscript_target
  and .bundle.readiness_state == $expected_readiness_state
  and (.bundle.claims | length) >= 2
  and (.bundle.claim_ids | length) == (.bundle.claims | length)
  and .bundle.evidence_pack_ref == ("campaign:" + $expected_campaign + ":evidence-pack")
  and .bundle.manuscript_pack_ref == ("campaign:" + $expected_campaign + ":manuscript-pack")
  and (.bundle.payload_manifest | length) >= 4
  and ((.bundle.payload_manifest | map(select(.logical_path == "ro-crate-metadata.json")) | length) == 1)
  and (.bundle.provenance.profile == "w3c-prov-bounded")
  and ((.bundle.provenance.activities | length) >= 1)
  and (.bundle.citation.profile == "datacite-4.7-ready")
  and ((.bundle.citation.related_identifiers | length) >= 3)
  and ((.bundle.ro_crate_metadata["@graph"] | length) >= 8)
' "${OUT}/review-bundle.json" >/dev/null

jq -e '
  ((."@graph" | length) >= 8)
  and ((."@graph" | map(select(."@id" == "./")) | length) == 1)
  and ((."@graph" | map(select(."@id" == "ro-crate-metadata.json")) | length) == 1)
' "${OUT}/ro-crate-metadata.json" >/dev/null

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
  --arg session_id "${SESSION_ID}" \
  --arg expected_readiness_state "${EXPECTED_READINESS_STATE}" '
  .status == "ok"
  and .bundle.program_id == $expected_program
  and .bundle.campaign_id == $expected_campaign
  and .bundle.workspace_id == $workspace_id
  and .bundle.session_id == $session_id
  and .bundle.readiness_state == $expected_readiness_state
' "${OUT}/review-bundle-after-restart.json" >/dev/null

jq -e \
  --arg workspace_id "${WORKSPACE_ID}" \
  --arg session_id "${SESSION_ID}" \
  --arg expected_program "${EXPECTED_PROGRAM}" \
  --arg expected_campaign "${EXPECTED_CAMPAIGN}" \
  --arg expected_workstream "${EXPECTED_WORKSTREAM}" \
  --arg expected_experiment "${EXPECTED_EXPERIMENT}" \
  --arg expected_readiness_state "${EXPECTED_READINESS_STATE}" '
  .status == "ok"
  and .workspace_id == $workspace_id
  and .session_id == $session_id
  and .expected_program == $expected_program
  and .expected_campaign == $expected_campaign
  and .expected_workstream == $expected_workstream
  and .expected_experiment == $expected_experiment
  and .claim_count >= 2
  and .payload_count >= 4
  and .readiness_state == $expected_readiness_state
  and .restart_recovered_session == true
' "${OUT}/smoke.json" >/dev/null

grep -Eq 'deployment.apps/beagle-core' "${OUT}/final-cluster-health.txt"
grep -Eq 'Slurmctld\(primary\).*UP' "${OUT}/final-cluster-health.txt"

echo "[OK] review bundle validator passed"
