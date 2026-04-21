#!/usr/bin/env bash
set -euo pipefail

OUT="${OUT:-/home/devsounio/beagle/.artifacts/darwin-hpc/study-decision-engine}"
B261_BASE_OUT="${B261_BASE_OUT:-/home/devsounio/beagle/.artifacts/darwin-hpc/study-registry-sweep}"
WORKSTREAM_ID="${WORKSTREAM_ID:-beagle-darwin-hpc-governance}"

require_file() {
  local path="$1"
  [[ -f "${path}" ]] || {
    echo "[FAIL] missing file: ${path}" >&2
    exit 1
  }
}

for file in \
  source-summary.json \
  health-before.json \
  health-after.json \
  study-registry.json \
  study-dag.json \
  study-sweep.json \
  comparative-result-summary.json \
  study-decision.json \
  study-decision-basis.json \
  next-run-proposal.json \
  study-registry-after-restart.json \
  study-sweep-after-restart.json \
  comparative-result-summary-after-restart.json \
  study-decision-after-restart.json \
  study-decision-basis-after-restart.json \
  next-run-proposal-after-restart.json \
  smoke.json \
  final-cluster-health.txt; do
  require_file "${OUT}/${file}"
done

require_file "${B261_BASE_OUT}/smoke.json"
require_file "${B261_BASE_OUT}/comparative-result-summary.json"

jq -e '
  .study_decision_source_present == 1 and
  .next_run_proposal_source_present == 1 and
  .study_registry_source_present == 1 and
  .study_dag_source_present == 1 and
  .study_sweep_source_present == 1 and
  .workbench_run_source_present == 1 and
  .workbench_result_binding_source_present == 1 and
  .lib_source_present == 1 and
  .http_source_present == 1 and
  .doc_present == 1 and
  .go_no_go_present == 1 and
  .known_limits_present == 1 and
  .study_decision_schema_present == 1 and
  .next_run_proposal_schema_present == 1 and
  .study_decision_basis_schema_present == 1 and
  .b261_base_present == 1
' "${OUT}/source-summary.json" >/dev/null

jq -e '
  .phase == "B26.1" and
  .status == "ok" and
  .same_beagle_owned_identity == true
' "${B261_BASE_OUT}/smoke.json" >/dev/null

jq -e '
  .phase == "B26.2" and
  .contract_kind == "study-decision" and
  .contract_version == "beagle-study-decision-v1" and
  .workstream_id == "'"${WORKSTREAM_ID}"'" and
  .same_beagle_owned_identity == true and
  .operator_review_required == true and
  (.recommended_action | IN("continue-sweep","stop-study","promote-variant","archive-variant","rerun-variant")) and
  (.recommended_next_variant_id | length) > 0 and
  (.recommended_next_compute_profile_id | length) > 0
' "${OUT}/study-decision.json" >/dev/null

jq -e '
  .phase == "B26.2" and
  .contract_kind == "study-decision-basis" and
  .contract_version == "beagle-study-decision-basis-v1" and
  .same_beagle_owned_identity == true and
  (.evidence_refs | length) >= 4 and
  (.best_run_id | length) > 0 and
  (.best_variant_id | length) > 0 and
  (.latest_run_diff_categories | type) == "array"
' "${OUT}/study-decision-basis.json" >/dev/null

jq -e '
  .phase == "B26.2" and
  .contract_kind == "next-run-proposal" and
  .contract_version == "beagle-next-run-proposal-v1" and
  .same_beagle_owned_identity == true and
  .operator_review_required == true and
  (.proposed_run_label | length) > 0 and
  (.proposed_variant_id | length) > 0 and
  (.proposed_compute_profile_id | length) > 0 and
  .study_decision_id == "'"$(jq -r '.decision_id' "${OUT}/study-decision.json")"'" and
  .study_decision_basis_id == "'"$(jq -r '.basis_id' "${OUT}/study-decision-basis.json")"'"
' "${OUT}/next-run-proposal.json" >/dev/null

jq -e '
  .study_id == "'"$(jq -r '.study_id' "${OUT}/study-registry.json")"'" and
  .workspace_id == "'"$(jq -r '.workspace_id' "${OUT}/study-registry.json")"'" and
  .session_id == "'"$(jq -r '.session_id' "${OUT}/study-registry.json")"'" and
  .same_beagle_owned_identity == true
' "${OUT}/study-registry-after-restart.json" >/dev/null

jq -e '
  .study_id == "'"$(jq -r '.study_id' "${OUT}/study-registry.json")"'" and
  .workspace_id == "'"$(jq -r '.workspace_id' "${OUT}/study-registry.json")"'" and
  .session_id == "'"$(jq -r '.session_id' "${OUT}/study-registry.json")"'" and
  .same_beagle_owned_identity == true
' "${OUT}/study-sweep-after-restart.json" >/dev/null

jq -e '
  .study_id == "'"$(jq -r '.study_id' "${OUT}/study-registry.json")"'" and
  .workspace_id == "'"$(jq -r '.workspace_id' "${OUT}/study-registry.json")"'" and
  .session_id == "'"$(jq -r '.session_id' "${OUT}/study-registry.json")"'" and
  .same_beagle_owned_identity == true
' "${OUT}/comparative-result-summary-after-restart.json" >/dev/null

jq -e '
  .study_id == "'"$(jq -r '.study_id' "${OUT}/study-registry.json")"'" and
  .workspace_id == "'"$(jq -r '.workspace_id' "${OUT}/study-registry.json")"'" and
  .session_id == "'"$(jq -r '.session_id' "${OUT}/study-registry.json")"'" and
  .same_beagle_owned_identity == true and
  .recommended_action == "'"$(jq -r '.recommended_action' "${OUT}/study-decision.json")"'"
' "${OUT}/study-decision-after-restart.json" >/dev/null

jq -e '
  .status == "ok" and
  .phase == "B26.2" and
  .study_decision_generated == true and
  .next_run_proposal_generated == true and
  .decision_basis_generated == true and
  .comparative_summary_generated == true and
  .same_beagle_owned_identity == true and
  .restart_recovered_session == true
' "${OUT}/smoke.json" >/dev/null

grep -Eq 'deployment.apps/beagle-core|beagle-core' "${OUT}/final-cluster-health.txt"
grep -Eq 'Slurmctld\(primary\)|slurm' "${OUT}/final-cluster-health.txt"

echo "[OK] study decision engine smoke artifacts validated"
