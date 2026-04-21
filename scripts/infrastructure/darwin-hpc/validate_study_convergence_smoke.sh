#!/usr/bin/env bash
set -euo pipefail

OUT="${OUT:-/home/devsounio/beagle/.artifacts/darwin-hpc/study-convergence}"
PROOF_OUT="${PROOF_OUT:-${OUT}/container-proof}"
B263_BASE_OUT="${B263_BASE_OUT:-/home/devsounio/beagle/.artifacts/darwin-hpc/study-proposal-dispatch}"
B262_BASE_OUT="${B262_BASE_OUT:-/home/devsounio/beagle/.artifacts/darwin-hpc/study-decision-engine}"
B261_BASE_OUT="${B261_BASE_OUT:-/home/devsounio/beagle/.artifacts/darwin-hpc/study-registry-sweep}"

require_file() {
  local path="$1"
  [[ -f "${path}" ]] || {
    echo "[FAIL] missing file: ${path}" >&2
    exit 1
  }
}

for file in \
  source-summary.json \
  study-convergence.json \
  variant-promotion-decision.json \
  study-closeout-summary.json \
  smoke.json \
  final-cluster-health.txt; do
  require_file "${OUT}/${file}"
done

require_file "${B263_BASE_OUT}/smoke.json"
require_file "${B262_BASE_OUT}/smoke.json"
require_file "${B261_BASE_OUT}/smoke.json"
require_file "${PROOF_OUT}/study-convergence-after-restart.json"
require_file "${PROOF_OUT}/variant-promotion-decision-after-restart.json"
require_file "${PROOF_OUT}/study-closeout-summary-after-restart.json"

jq -e '
  .source_convergence_present == 1 and
  .source_decision_present == 1 and
  .source_continuation_present == 1 and
  .source_dispatch_present == 1 and
  .source_next_run_present == 1 and
  .source_registry_present == 1 and
  .source_dag_present == 1 and
  .source_sweep_present == 1 and
  .source_lib_present == 1 and
  .source_http_present == 1 and
  .doc_present == 1 and
  .go_no_go_present == 1 and
  .known_limits_present == 1 and
  .schema_convergence_present == 1 and
  .schema_promotion_present == 1 and
  .schema_closeout_present == 1 and
  .b263_base_present == 1 and
  .b262_base_present == 1 and
  .b261_base_present == 1
' "${OUT}/source-summary.json" >/dev/null

jq -e '
  .phase == "B26.4" and
  .contract_kind == "study-convergence" and
  .contract_version == "beagle-study-convergence-v1" and
  .same_beagle_owned_identity == true and
  .convergence_state == "converged" and
  .enough_evidence_to_stop == true and
  .recommended_action == "stop-study" and
  (.best_variant_id | length) > 0 and
  (.best_run_id | length) > 0 and
  (.best_run_score >= 140) and
  (.updated_run_count >= 11) and
  (.updated_variant_count >= 11) and
  (.updated_compared_run_count >= 11)
' "${OUT}/study-convergence.json" >/dev/null

jq -e '
  .phase == "B26.4" and
  .contract_kind == "variant-promotion-decision" and
  .contract_version == "beagle-variant-promotion-decision-v1" and
  .same_beagle_owned_identity == true and
  .decision_action == "promote-variant" and
  (.promoted_variant_id | length) > 0 and
  (.promoted_run_id | length) > 0 and
  .archived_variant_count >= 1 and
  .operator_review_required == true
' "${OUT}/variant-promotion-decision.json" >/dev/null

jq -e '
  .phase == "B26.4" and
  .contract_kind == "study-closeout-summary" and
  .contract_version == "beagle-study-closeout-summary-v1" and
  .same_beagle_owned_identity == true and
  .final_study_state == "converged" and
  .final_comparative_decision == "stop-study" and
  .final_variant_promotion_state == "promote-variant" and
  (.promoted_variant_id | length) > 0 and
  (.promoted_run_id | length) > 0
' "${OUT}/study-closeout-summary.json" >/dev/null

jq -e '
  .phase == "B26.4" and
  .study_id == "'"$(jq -r '.study_id' "${OUT}/study-convergence.json")"'" and
  .workstream_id == "'"$(jq -r '.workstream_id' "${OUT}/study-convergence.json")"'" and
  .workspace_id == "'"$(jq -r '.workspace_id' "${OUT}/study-convergence.json")"'" and
  .session_id == "'"$(jq -r '.session_id' "${OUT}/study-convergence.json")"'" and
  .same_beagle_owned_identity == true and
  .restart_recovered_identity == true and
  .restart_recovered_summary == true and
  .convergence_state == "converged" and
  .recommended_action == "stop-study" and
  .final_comparative_decision == "stop-study" and
  .final_variant_promotion_state == "promote-variant"
' "${OUT}/smoke.json" >/dev/null

jq -e '
  .study_id == "'"$(jq -r '.study_id' "${OUT}/study-convergence.json")"'" and
  .workspace_id == "'"$(jq -r '.workspace_id' "${OUT}/study-convergence.json")"'" and
  .session_id == "'"$(jq -r '.session_id' "${OUT}/study-convergence.json")"'" and
  .same_beagle_owned_identity == true
' "${PROOF_OUT}/study-convergence-after-restart.json" >/dev/null

jq -e '
  .study_id == "'"$(jq -r '.study_id' "${OUT}/study-convergence.json")"'" and
  .workspace_id == "'"$(jq -r '.workspace_id' "${OUT}/study-convergence.json")"'" and
  .session_id == "'"$(jq -r '.session_id' "${OUT}/study-convergence.json")"'" and
  .same_beagle_owned_identity == true
' "${PROOF_OUT}/variant-promotion-decision-after-restart.json" >/dev/null

jq -e '
  .study_id == "'"$(jq -r '.study_id' "${OUT}/study-convergence.json")"'" and
  .workspace_id == "'"$(jq -r '.workspace_id' "${OUT}/study-convergence.json")"'" and
  .session_id == "'"$(jq -r '.session_id' "${OUT}/study-convergence.json")"'" and
  .same_beagle_owned_identity == true
' "${PROOF_OUT}/study-closeout-summary-after-restart.json" >/dev/null

grep -Eq 'deployment.apps/beagle-core|beagle-core' "${OUT}/final-cluster-health.txt"
grep -Eq 'Slurmctld\(primary\)|slurm' "${OUT}/final-cluster-health.txt"

echo "[OK] study convergence smoke artifacts validated"
