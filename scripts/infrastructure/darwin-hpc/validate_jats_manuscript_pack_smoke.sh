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
  jats-manuscript-pack.json \
  jats-article.xml \
  beagle-health-after-restart.json \
  bootstrap-after-restart.json \
  jats-manuscript-pack-after-restart.json \
  jats-article-after-restart.xml \
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
  expected-jats-profile.txt \
  expected-article-type.txt \
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
EXPECTED_JATS_PROFILE="$(cat "${OUT}/expected-jats-profile.txt")"
EXPECTED_ARTICLE_TYPE="$(cat "${OUT}/expected-article-type.txt")"
EXPECTED_READINESS_STATE="$(cat "${OUT}/expected-readiness-state.txt")"

jq -e \
  --arg expected_program "${EXPECTED_PROGRAM}" \
  --arg expected_campaign "${EXPECTED_CAMPAIGN}" \
  --arg expected_workstream "${EXPECTED_WORKSTREAM}" \
  --arg expected_experiment "${EXPECTED_EXPERIMENT}" \
  --arg expected_manuscript_target "${EXPECTED_MANUSCRIPT_TARGET}" \
  --arg expected_jats_profile "${EXPECTED_JATS_PROFILE}" \
  --arg expected_article_type "${EXPECTED_ARTICLE_TYPE}" \
  --arg expected_readiness_state "${EXPECTED_READINESS_STATE}" '
  .expected_program == $expected_program
  and .expected_campaign == $expected_campaign
  and .expected_workstream == $expected_workstream
  and .expected_experiment == $expected_experiment
  and .expected_manuscript_target == $expected_manuscript_target
  and .expected_jats_profile == $expected_jats_profile
  and .expected_article_type == $expected_article_type
  and .expected_readiness_state == $expected_readiness_state
  and (.manuscript_pack_source_present == true or .manuscript_pack_source_present == 1)
  and (.http_source_present == true or .http_source_present == 1)
  and (.doc_present == true or .doc_present == 1)
  and (.go_no_go_present == true or .go_no_go_present == 1)
  and (.known_limits_present == true or .known_limits_present == 1)
  and (.contract_present == true or .contract_present == 1)
  and (.section_map_present == true or .section_map_present == 1)
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

jq -e '.status == "ok" and .memory_id != null and .physio_attached == true' "${OUT}/ingest-response.json" >/dev/null

jq -e \
  --arg expected_program "${EXPECTED_PROGRAM}" \
  --arg expected_campaign "${EXPECTED_CAMPAIGN}" \
  --arg expected_workstream "${EXPECTED_WORKSTREAM}" \
  --arg expected_manuscript_target "${EXPECTED_MANUSCRIPT_TARGET}" \
  --arg expected_jats_profile "${EXPECTED_JATS_PROFILE}" \
  --arg expected_article_type "${EXPECTED_ARTICLE_TYPE}" \
  --arg expected_readiness_state "${EXPECTED_READINESS_STATE}" \
  --arg workspace_id "${WORKSPACE_ID}" \
  --arg session_id "${SESSION_ID}" '
  .status == "ok"
  and .phase == "B20.1"
  and .pack.pack_version == "beagle-jats-manuscript-pack-v1"
  and .pack.jats_profile == $expected_jats_profile
  and .pack.article_type == $expected_article_type
  and .pack.program_id == $expected_program
  and .pack.campaign_id == $expected_campaign
  and .pack.active_workstream_id == $expected_workstream
  and .pack.workspace_id == $workspace_id
  and .pack.session_id == $session_id
  and .pack.manuscript_target.id == $expected_manuscript_target
  and .pack.readiness_state == $expected_readiness_state
  and (.pack.claim_ids | length) >= 2
  and (.pack.section_map | length) >= 6
  and ((.pack.section_map | map(.section_type) | index("abstract")) != null)
  and ((.pack.section_map | map(.section_type) | index("methods")) != null)
  and ((.pack.section_map | map(.section_type) | index("results")) != null)
  and ((.pack.section_map | map(.section_type) | index("discussion")) != null)
  and (.pack.evidence_pack_ref == ("campaign:" + $expected_campaign + ":evidence-pack"))
  and (.pack.review_bundle_ref == ("campaign:" + $expected_campaign + ":review-bundle"))
  and (.pack.provenance.profile == "w3c-prov-bounded")
  and (.pack.citation.profile == "datacite-4.7-ready")
  and ((.pack.jats_xml | contains("<article ")) == true)
  and ((.pack.jats_xml | contains("<front>")) == true)
  and ((.pack.jats_xml | contains("<body>")) == true)
  and ((.pack.jats_xml | contains("<ref-list>")) == true)
' "${OUT}/jats-manuscript-pack.json" >/dev/null

grep -Eq '<article ' "${OUT}/jats-article.xml"
grep -Eq '<front>' "${OUT}/jats-article.xml"
grep -Eq '<body>' "${OUT}/jats-article.xml"
grep -Eq '<ref-list>' "${OUT}/jats-article.xml"

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
  --arg expected_readiness_state "${EXPECTED_READINESS_STATE}" \
  --arg expected_jats_profile "${EXPECTED_JATS_PROFILE}" '
  .status == "ok"
  and .pack.program_id == $expected_program
  and .pack.campaign_id == $expected_campaign
  and .pack.workspace_id == $workspace_id
  and .pack.session_id == $session_id
  and .pack.readiness_state == $expected_readiness_state
  and .pack.jats_profile == $expected_jats_profile
' "${OUT}/jats-manuscript-pack-after-restart.json" >/dev/null

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
  and .section_count >= 6
  and .readiness_state == $expected_readiness_state
  and .restart_recovered_session == true
' "${OUT}/smoke.json" >/dev/null

grep -Eq 'deployment.apps/beagle-core' "${OUT}/final-cluster-health.txt"
grep -Eq 'Slurmctld\(primary\).*UP' "${OUT}/final-cluster-health.txt"

echo "[OK] jats manuscript pack validator passed"
