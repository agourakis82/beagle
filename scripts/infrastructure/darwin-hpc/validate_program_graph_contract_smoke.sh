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
  program-summary.json \
  campaign-summary.json \
  relation-summary.json \
  consistency-summary.json; do
  [[ -s "${OUT}/${file}" ]] || {
    echo "[FAIL] missing or empty artifact: ${OUT}/${file}" >&2
    exit 1
  }
done

jq -e '
  .status == "ok"
  and (.files.doc.present == true and .files.doc.non_empty == true)
  and (.files.go_no_go.present == true and .files.go_no_go.non_empty == true)
  and (.files.known_limits.present == true and .files.known_limits.non_empty == true)
  and (.files.schema.present == true and .files.schema.non_empty == true)
  and (.files.programs_readme.present == true and .files.programs_readme.non_empty == true)
  and (.files.campaigns_readme.present == true and .files.campaigns_readme.non_empty == true)
  and (.files.program.present == true and .files.program.non_empty == true)
  and (.files.campaign_governance.present == true and .files.campaign_governance.non_empty == true)
  and (.files.campaign_expedition_002.present == true and .files.campaign_expedition_002.non_empty == true)
  and (.files.workstream_registry.present == true and .files.workstream_registry.non_empty == true)
' "${OUT}/source-summary.json" >/dev/null

jq -e '
  .status == "ok"
  and .program_id == "beagle-physio-symbolic-exocortex"
  and .status_value == "canonical"
  and .program_kind == "research-engineering-program"
  and .source_phase == "B19.1"
  and .north_star_present == true
  and .campaign_count == 2
  and .workstream_count == 2
  and .experiment_count == 1
  and (.campaign_ids | index("darwin-hpc-governance") != null)
  and (.campaign_ids | index("expedition-002-hrv-aware") != null)
  and (.workstream_ids | index("beagle-darwin-hpc-governance") != null)
  and (.workstream_ids | index("beagle-darwin-hpc-wave1") != null)
  and (.experiment_ids | index("beagle_exp_002_hrv_aware_vs_blind") != null)
  and (.missing_required_fields | length == 0)
' "${OUT}/program-summary.json" >/dev/null

jq -e '
  .status == "ok"
  and .campaign_count == 2
  and (.campaigns | map(.id) | index("darwin-hpc-governance") != null)
  and (.campaigns | map(.id) | index("expedition-002-hrv-aware") != null)
  and (
    .campaigns
    | all(
        (.missing_required_fields | length) == 0
        and (.missing_experiment_fields | length) == 0
        and (.missing_evidence_fields | length) == 0
      )
  )
' "${OUT}/campaign-summary.json" >/dev/null

jq -e '
  .status == "ok"
  and (.program_contains_campaign.missing_campaigns | length == 0)
  and (.program_contains_campaign.campaign_file_resolution["darwin-hpc-governance"] == true)
  and (.program_contains_campaign.campaign_file_resolution["expedition-002-hrv-aware"] == true)
  and (.campaign_uses_workstream.missing_workstreams | length == 0)
  and (.campaign_uses_workstream.referenced_workstream_ids | index("beagle-darwin-hpc-governance") != null)
  and (.campaign_uses_workstream.referenced_workstream_ids | index("beagle-darwin-hpc-wave1") != null)
  and (
    .campaign_runs_experiment.program_experiment_docs
    | any(
        .experiment_id == "beagle_exp_002_hrv_aware_vs_blind"
        and .campaign_id == "expedition-002-hrv-aware"
        and .spec_doc_exists == true
        and .results_doc_exists == true
      )
  )
  and (
    .result_informs_manuscript.evidence_targets
    | all(.path_exists == true)
  )
  and (
    .result_informs_manuscript.artifact_roots
    | all(.artifact_root_exists == true)
  )
  and .cross_links.invalid_campaign_program_links == {}
  and .cross_links.observer_contract_exists == true
  and .cross_links.memory_contract_exists == true
' "${OUT}/relation-summary.json" >/dev/null

jq -e '
  .status == "ok"
  and .phase == "B19.1"
  and .schema_phase == "B19.1"
  and .schema_status == "canonical-contract"
  and .program_id == "beagle-physio-symbolic-exocortex"
  and .program_status == "canonical"
  and (.campaign_ids | index("darwin-hpc-governance") != null)
  and (.campaign_ids | index("expedition-002-hrv-aware") != null)
  and .matched_schema_phase == true
  and .matched_program_source_phase == true
  and .matched_campaign_source_phases == true
  and .canonical_program_present == true
  and .canonical_campaigns_present == true
  and .mapped_existing_workstreams == true
  and .mapped_expedition_002 == true
  and .program_relations_ok == true
  and .required_relation_types_present == true
' "${OUT}/consistency-summary.json" >/dev/null

echo "[OK] program graph contract validation passed"
