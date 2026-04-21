#!/usr/bin/env bash
set -euo pipefail

OUT="${OUT:-/home/devsounio/beagle/.artifacts/darwin-hpc/baseline-adoption}"
PROOF_OUT="${PROOF_OUT:-${OUT}/container-proof}"
B265_BASE_OUT="${B265_BASE_OUT:-/home/devsounio/beagle/.artifacts/darwin-hpc/study-promotion-execution}"

require_file() {
  local path="$1"
  [[ -f "${path}" ]] || {
    echo "[FAIL] missing file: ${path}" >&2
    exit 1
  }
}

for file in \
  source-summary.json \
  promoted-variant-receipt.json \
  baseline-adoption.json \
  baseline-rollback-plan.json \
  next-study-seed.json \
  workbench-context-after-baseline.json \
  context-packet-before.json \
  smoke.json \
  final-cluster-health.txt; do
  require_file "${OUT}/${file}"
done

require_file "${B265_BASE_OUT}/smoke.json"
require_file "${PROOF_OUT}/promoted-variant-receipt-after-restart.json"
require_file "${PROOF_OUT}/baseline-adoption-after-restart.json"
require_file "${PROOF_OUT}/next-study-seed-after-restart.json"

jq -e '
  .source_baseline_adoption_present == 1 and
  .source_next_study_seed_present == 1 and
  .source_lib_present == 1 and
  .source_http_present == 1 and
  .source_context_packet_present == 1 and
  .source_intent_planner_present == 1 and
  .doc_present == 1 and
  .go_no_go_present == 1 and
  .known_limits_present == 1 and
  .schema_receipt_present == 1 and
  .schema_adoption_present == 1 and
  .schema_rollback_present == 1 and
  .schema_seed_present == 1 and
  .schema_workbench_context_present == 1 and
  .b265_base_present == 1
' "${OUT}/source-summary.json" >/dev/null

jq -e '
  .phase == "B26.6" and
  .contract_kind == "promoted-variant-receipt" and
  .same_beagle_owned_identity == true and
  (.promoted_variant_id | length) > 0 and
  (.promoted_run_id | length) > 0 and
  (.study_promotion_execution_id | length) > 0
' "${OUT}/promoted-variant-receipt.json" >/dev/null

jq -e '
  .phase == "B26.6" and
  .contract_kind == "baseline-adoption" and
  .same_beagle_owned_identity == true and
  (.adopted_variant_id | length) > 0 and
  (.adopted_run_id | length) > 0 and
  (.bounded_baseline_scope | length) > 0
' "${OUT}/baseline-adoption.json" >/dev/null

jq -e '
  .phase == "B26.6" and
  .contract_kind == "baseline-rollback-plan" and
  .same_beagle_owned_identity == true and
  (.steps | length) >= 1 and
  (.restores_archived_variant_ids | length) >= 1
' "${OUT}/baseline-rollback-plan.json" >/dev/null

jq -e '
  .phase == "B26.6" and
  .contract_kind == "next-study-seed" and
  .same_beagle_owned_identity == true and
  .auto_launch_new_study == false and
  (.seeded_baseline_variant_id | length) > 0 and
  (.suggested_next_study_id | length) > 0
' "${OUT}/next-study-seed.json" >/dev/null

jq -e '
  .phase == "B26.6" and
  .bounded_study_baseline.phase == "B26.6" and
  (.bounded_study_baseline.adoption_id | length) > 0
' "${OUT}/workbench-context-after-baseline.json" >/dev/null

jq -e '
  .packet.bounded_study_baseline != null and
  .packet.bounded_study_baseline.phase == "B26.6" and
  (.packet.bounded_study_baseline.promoted_variant_id | length) > 0
' "${OUT}/context-packet-before.json" >/dev/null

jq -e '
  .status == "ok" and
  .phase == "B26.6" and
  .same_beagle_owned_identity == true and
  .next_study_auto_launch == false and
  .bounded_study_baseline_on_context_packet == true and
  .context_baseline_phase == "B26.6" and
  .restart_recovered_identity == true and
  .restart_recovered_adoption_ids == true
' "${OUT}/smoke.json" >/dev/null

jq -e '
  .study_id == "'"$(jq -r '.study_id' "${OUT}/baseline-adoption.json")"'" and
  .workspace_id == "'"$(jq -r '.workspace_id' "${OUT}/baseline-adoption.json")"'" and
  .session_id == "'"$(jq -r '.session_id' "${OUT}/baseline-adoption.json")"'" and
  .same_beagle_owned_identity == true
' "${PROOF_OUT}/baseline-adoption-after-restart.json" >/dev/null

grep -Eq 'deployment.apps/beagle-core|beagle-core' "${OUT}/final-cluster-health.txt"
grep -Eq 'Slurmctld\(primary\)|slurm' "${OUT}/final-cluster-health.txt"

echo "[OK] baseline adoption smoke artifacts validated"
