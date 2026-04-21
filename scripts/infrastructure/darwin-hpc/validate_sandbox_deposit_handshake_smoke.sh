#!/usr/bin/env bash
set -euo pipefail

ROOT="${ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)}"
OUT="${OUT:-${ROOT}/.artifacts/darwin-hpc/sandbox-deposit-handshake}"

require() {
  command -v "$1" >/dev/null 2>&1 || {
    echo "[FAIL] missing command: $1" >&2
    exit 1
  }
}

require bash
require jq
require grep

for path in \
  "${OUT}/external-staging-source-summary.json" \
  "${OUT}/external-staging-smoke.json" \
  "${OUT}/source-summary.json" \
  "${OUT}/workspace-subagent-list.json" \
  "${OUT}/route-manuscript.json" \
  "${OUT}/handoff-core-to-experiments.json" \
  "${OUT}/workspace-manuscript-handoff-post.json" \
  "${OUT}/workspace-manuscript-assembly-post.json" \
  "${OUT}/workspace-scholarly-release-post.json" \
  "${OUT}/workspace-publication-package-post.json" \
  "${OUT}/workspace-external-staging-post.json" \
  "${OUT}/workspace-external-staging.json" \
  "${OUT}/workspace-sandbox-deposit-post.json" \
  "${OUT}/workspace-sandbox-deposit.json" \
  "${OUT}/workspace-sandbox-deposit-after-restart.json" \
  "${OUT}/datacite-test-receipt.json" \
  "${OUT}/crossref-test-receipt.json" \
  "${OUT}/registry-submission-ledger.json" \
  "${OUT}/sandbox-deposit-bundle.json" \
  "${OUT}/workspace-context.json" \
  "${OUT}/workspace-context-after-restart.json" \
  "${OUT}/workspace-context.env" \
  "${OUT}/manuscript.env" \
  "${OUT}/manuscript-identity.txt" \
  "${OUT}/manuscript-identity-after-restart.txt" \
  "${OUT}/workspace-health.txt" \
  "${OUT}/workspace-health-after-restart.txt" \
  "${OUT}/smoke.json" \
  "${OUT}/final-cluster-health.txt"; do
  [[ -f "${path}" ]] || {
    echo "[FAIL] missing artifact: ${path}" >&2
    exit 1
  }
done

jq -e '
  .phase == "B21.5" and
  .workstream_id == "beagle-darwin-hpc-governance" and
  .workspace_id == "beagle-cluster-pilot" and
  .session_id == "ws-cluster-workspace-habitat" and
  .source_subagent_id == "manuscript" and
  .technical_external_staging_state == "ready-for-external-test-staging" and
  .readiness_state == "claim-linked-human-eval-pending" and
  .restart_recovered_session == true
' "${OUT}/external-staging-smoke.json" >/dev/null

jq -e '
  .expected_workstream == "beagle-darwin-hpc-governance" and
  .expected_campaign == "expedition-002-hrv-aware" and
  .expected_subagent == "manuscript" and
  .expected_jats_profile == "jats-1.4-ready" and
  .sandbox_source_present == 1 and
  .external_source_present == 1 and
  .http_source_present == 1 and
  .datacite_receipt_contract_present == 1 and
  .crossref_receipt_contract_present == 1 and
  .ledger_contract_present == 1 and
  .doc_present == 1 and
  .go_no_go_present == 1 and
  .known_limits_present == 1 and
  .secret_example_present == 1 and
  .secret_example_has_test_keys == 1
' "${OUT}/source-summary.json" >/dev/null

jq -e --slurpfile staging "${OUT}/workspace-external-staging-post.json" '
  .phase == "B21.6" and
  .package.workstream_id == "beagle-darwin-hpc-governance" and
  .package.workspace_id == "beagle-cluster-pilot" and
  .package.session_id == "ws-cluster-workspace-habitat" and
  .package.source_subagent_id == "manuscript" and
  .package.source_role_tag == "manuscript-authoring" and
  .package.upstream_external_staging_id == $staging[0].package.package_id and
  .package.workspace_external_staging_ref == ("workspace-external-staging:" + .package.upstream_external_staging_id) and
  .package.datacite_test_receipt_ref == ("workspace-sandbox-deposit:" + .package.package_id + ":datacite-test-receipt") and
  .package.crossref_test_receipt_ref == ("workspace-sandbox-deposit:" + .package.package_id + ":crossref-test-receipt") and
  .package.registry_submission_ledger_ref == ("workspace-sandbox-deposit:" + .package.package_id + ":registry-submission-ledger") and
  .package.sandbox_deposit_bundle_ref == ("workspace-sandbox-deposit:" + .package.package_id + ":sandbox-deposit-bundle") and
  .package.readiness_state == "claim-linked-human-eval-pending" and
  .package.technical_external_staging_state == "ready-for-external-test-staging" and
  (
    .package.registry_handshake_state == "live-accepted" or
    .package.registry_handshake_state == "live-auth-blocked" or
    .package.registry_handshake_state == "live-with-nonaccepting-receipts"
  ) and
  .package.managed_attach_state == "coder-compatible-ready" and
  .package.stable_attach_alias == "beagle-cluster-pilot.coder" and
  .continuity.handoff_present == true and
  .continuity.external_registry_live_boundary_proven == true and
  .continuity.live_registry_response_count == 2 and
  .continuity.claim_count >= 1 and
  .continuity.technical_ready_for_external_staging == true and
  .continuity.restart_recovered_session == true
' "${OUT}/workspace-sandbox-deposit-post.json" >/dev/null

jq -e --slurpfile post "${OUT}/workspace-sandbox-deposit-post.json" '
  .package.package_id == $post[0].package.package_id and
  .package.registry_handshake_state == $post[0].package.registry_handshake_state and
  .datacite_test_receipt.receipt_id == $post[0].datacite_test_receipt.receipt_id and
  .crossref_test_receipt.receipt_id == $post[0].crossref_test_receipt.receipt_id and
  .registry_submission_ledger.ledger_id == $post[0].registry_submission_ledger.ledger_id
' "${OUT}/workspace-sandbox-deposit.json" >/dev/null

jq -e '
  .receipt_profile == "datacite-test-receipt-v1" and
  .registry == "datacite-test" and
  .target_url == "https://api.test.datacite.org/dois" and
  .request_method == "POST" and
  .real_network_call_attempted == true and
  .transport_ok == true and
  (.http_status | type) == "number" and
  .registry_state != "network-disabled" and
  .registry_state != "transport-failed" and
  .readiness_state == "claim-linked-human-eval-pending" and
  (.response_summary | length) >= 1
' "${OUT}/datacite-test-receipt.json" >/dev/null

jq -e '
  if (.http_status == 401 or .http_status == 403)
  then .registry_state == "auth-blocked"
  else true
  end
' "${OUT}/datacite-test-receipt.json" >/dev/null

jq -e '
  .receipt_profile == "crossref-test-receipt-v1" and
  .registry == "crossref-test" and
  .target_url == "https://test.crossref.org/servlet/deposit" and
  .request_method == "POST" and
  .real_network_call_attempted == true and
  .transport_ok == true and
  (.http_status | type) == "number" and
  .registry_state != "network-disabled" and
  .registry_state != "transport-failed" and
  .readiness_state == "claim-linked-human-eval-pending" and
  (.response_summary | length) >= 1
' "${OUT}/crossref-test-receipt.json" >/dev/null

jq -e '
  if (.http_status == 401 or .http_status == 403)
  then .registry_state == "auth-blocked"
  else true
  end
' "${OUT}/crossref-test-receipt.json" >/dev/null

jq -e --slurpfile post "${OUT}/workspace-sandbox-deposit-post.json" '
  .ledger_profile == "registry-submission-ledger-v1" and
  .workstream_id == "beagle-darwin-hpc-governance" and
  .workspace_id == "beagle-cluster-pilot" and
  .session_id == "ws-cluster-workspace-habitat" and
  .campaign_id == "expedition-002-hrv-aware" and
  .package_id == $post[0].package.package_id and
  .readiness_state == "claim-linked-human-eval-pending" and
  .registry_handshake_state == $post[0].package.registry_handshake_state and
  .submission_count == 2 and
  .live_network_attempt_count == 2 and
  .live_registry_response_count == 2 and
  .accepted_submission_count == ([.entries[] | select(.accepted == true)] | length) and
  .auth_blocked_submission_count == ([.entries[] | select(.registry_state == "auth-blocked")] | length) and
  (.entries | length) == 2 and
  any(.entries[]; .registry == "datacite-test" and .target_url == "https://api.test.datacite.org/dois") and
  any(.entries[]; .registry == "crossref-test" and .target_url == "https://test.crossref.org/servlet/deposit")
' "${OUT}/registry-submission-ledger.json" >/dev/null

jq -e --slurpfile post "${OUT}/workspace-sandbox-deposit-post.json" '
  .bundle_kind == "sandbox-deposit-bundle" and
  .campaign_id == "expedition-002-hrv-aware" and
  .workstream_id == "beagle-darwin-hpc-governance" and
  .workspace_id == "beagle-cluster-pilot" and
  .session_id == "ws-cluster-workspace-habitat" and
  .readiness_state == "claim-linked-human-eval-pending" and
  .technical_external_staging_state == "ready-for-external-test-staging" and
  .registry_handshake_state == $post[0].package.registry_handshake_state and
  (.payload_manifest | length) >= 20 and
  (.provenance.activities | length) >= 1 and
  (.citation.related_identifiers | length) >= 1
' "${OUT}/sandbox-deposit-bundle.json" >/dev/null

grep -q "BEAGLE_SUBAGENT_ROLE_TAG='manuscript-authoring'" "${OUT}/manuscript.env"

IFS=$'\t' read -r man_workstream man_workspace man_session man_subagent man_role_tag man_pwd < "${OUT}/manuscript-identity.txt"
[[ "${man_workstream}" == "beagle-darwin-hpc-governance" ]]
[[ "${man_workspace}" == "beagle-cluster-pilot" ]]
[[ "${man_session}" == "ws-cluster-workspace-habitat" ]]
[[ "${man_subagent}" == "manuscript" ]]
[[ "${man_role_tag}" == "manuscript-authoring" ]]
[[ "${man_pwd}" == "/workspace/beagle/docs/darwin/hpc" ]]

IFS=$'\t' read -r _ _ man_restart_session man_restart_subagent man_restart_role_tag man_restart_pwd < "${OUT}/manuscript-identity-after-restart.txt"
[[ "${man_restart_session}" == "ws-cluster-workspace-habitat" ]]
[[ "${man_restart_subagent}" == "manuscript" ]]
[[ "${man_restart_role_tag}" == "manuscript-authoring" ]]
[[ "${man_restart_pwd}" == "/workspace/beagle/docs/darwin/hpc" ]]

jq -e --slurpfile post "${OUT}/workspace-sandbox-deposit-post.json" '
  .package.package_id == $post[0].package.package_id and
  .package.session_id == $post[0].package.session_id and
  .package.registry_handshake_state == $post[0].package.registry_handshake_state and
  .registry_submission_ledger.ledger_id == $post[0].registry_submission_ledger.ledger_id and
  .context_packet.handoff.last_handoff == $post[0].context_packet.handoff.last_handoff
' "${OUT}/workspace-sandbox-deposit-after-restart.json" >/dev/null

jq -e '
  .phase == "B21.6" and
  .workstream_id == "beagle-darwin-hpc-governance" and
  .workspace_id == "beagle-cluster-pilot" and
  .session_id == "ws-cluster-workspace-habitat" and
  .source_subagent_id == "manuscript" and
  (
    .registry_handshake_state == "live-accepted" or
    .registry_handshake_state == "live-auth-blocked" or
    .registry_handshake_state == "live-with-nonaccepting-receipts"
  ) and
  .technical_external_staging_state == "ready-for-external-test-staging" and
  .readiness_state == "claim-linked-human-eval-pending" and
  .managed_attach_state == "coder-compatible-ready" and
  .stable_attach_alias == "beagle-cluster-pilot.coder" and
  .live_registry_response_count == 2 and
  (.datacite_http_status | type) == "number" and
  (.crossref_http_status | type) == "number" and
  .restart_recovered_session == true
' "${OUT}/smoke.json" >/dev/null

grep -q "deployment.apps/beagle-core" "${OUT}/final-cluster-health.txt"
grep -q "deployment.apps/beagle-workspace" "${OUT}/final-cluster-health.txt"
grep -Eq 'Slurmctld\(primary\).*UP' "${OUT}/final-cluster-health.txt"

printf '[OK] sandbox deposit handshake smoke artifacts validated\n'
