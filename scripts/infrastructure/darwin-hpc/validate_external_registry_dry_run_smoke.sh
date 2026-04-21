#!/usr/bin/env bash
set -euo pipefail

ROOT="${ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)}"
OUT="${OUT:-${ROOT}/.artifacts/darwin-hpc/external-registry-dry-run}"

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
  "${OUT}/campaign-review-bundle.json" \
  "${OUT}/campaign-jats-manuscript-pack.json" \
  "${OUT}/external-staging-readiness-report.json" \
  "${OUT}/datacite-test-staging-payload.json" \
  "${OUT}/crossref-dry-run-bundle.json" \
  "${OUT}/external-registry-staging-bundle.json" \
  "${OUT}/publication-readiness-report.json" \
  "${OUT}/jats-qa-report.json" \
  "${OUT}/ro-crate-metadata.json" \
  "${OUT}/datacite-metadata.json" \
  "${OUT}/crossref-article.xml" \
  "${OUT}/jats-article.xml" \
  "${OUT}/workspace-context.json" \
  "${OUT}/workspace-context-after-restart.json" \
  "${OUT}/workspace-context.env" \
  "${OUT}/manuscript.env" \
  "${OUT}/manuscript-identity.txt" \
  "${OUT}/manuscript-identity-after-restart.txt" \
  "${OUT}/workspace-external-staging-after-restart.json" \
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
  .expected_campaign == "expedition-002-hrv-aware" and
  .expected_workstream == "beagle-darwin-hpc-governance" and
  .expected_subagent == "manuscript" and
  .expected_jats_profile == "jats-1.4-ready" and
  .external_source_present == 1 and
  .publication_source_present == 1 and
  .http_source_present == 1 and
  .datacite_test_contract_present == 1 and
  .crossref_dry_run_contract_present == 1 and
  .readiness_contract_present == 1 and
  .doc_present == 1 and
  .go_no_go_present == 1 and
  .known_limits_present == 1
' "${OUT}/source-summary.json" >/dev/null

jq -e '
  .phase == "B20.8" and
  any(.subagents.roles[]; .subagent_id == "manuscript" and .role_tag == "manuscript-authoring")
' "${OUT}/workspace-subagent-list.json" >/dev/null

jq -e '
  .phase == "B20.8" and
  .route.selection.selected_subagent_id == "manuscript"
' "${OUT}/route-manuscript.json" >/dev/null

jq -e '.phase == "B20.9"' "${OUT}/handoff-core-to-experiments.json" >/dev/null
jq -e '.phase == "B21.1"' "${OUT}/workspace-manuscript-handoff-post.json" >/dev/null
jq -e '.phase == "B21.2"' "${OUT}/workspace-manuscript-assembly-post.json" >/dev/null
jq -e '.phase == "B21.3"' "${OUT}/workspace-scholarly-release-post.json" >/dev/null
jq -e '.phase == "B21.4"' "${OUT}/workspace-publication-package-post.json" >/dev/null

jq -e --slurpfile publication "${OUT}/workspace-publication-package-post.json" '
  .phase == "B21.5" and
  .package.workstream_id == "beagle-darwin-hpc-governance" and
  .package.workspace_id == "beagle-cluster-pilot" and
  .package.session_id == "ws-cluster-workspace-habitat" and
  .package.source_subagent_id == "manuscript" and
  .package.source_role_tag == "manuscript-authoring" and
  .package.upstream_publication_package_id == $publication[0].package.package_id and
  .package.workspace_publication_package_ref == ("workspace-publication-package:" + .package.upstream_publication_package_id) and
  .package.external_staging_readiness_report_ref == ("workspace-external-staging:" + .package.package_id + ":external-staging-readiness-report") and
  .package.datacite_test_staging_payload_ref == ("workspace-external-staging:" + .package.package_id + ":datacite-test-staging-payload") and
  .package.crossref_dry_run_bundle_ref == ("workspace-external-staging:" + .package.package_id + ":crossref-dry-run-bundle") and
  .package.external_staging_bundle_ref == ("workspace-external-staging:" + .package.package_id + ":external-staging-bundle") and
  .package.readiness_state == "claim-linked-human-eval-pending" and
  .package.technical_external_staging_state == "ready-for-external-test-staging" and
  .package.managed_attach_state == "coder-compatible-ready" and
  .package.stable_attach_alias == "beagle-cluster-pilot.coder" and
  .continuity.handoff_present == true and
  .continuity.claim_count >= 1 and
  .continuity.technical_blocker_count == .external_staging_readiness_report.technical_blocker_count and
  .continuity.epistemic_blocker_count == .external_staging_readiness_report.epistemic_blocker_count and
  .continuity.technical_ready_for_external_staging == true and
  .continuity.findable_publication_allowed == false and
  .continuity.restart_recovered_session == true
' "${OUT}/workspace-external-staging-post.json" >/dev/null

jq -e --slurpfile post "${OUT}/workspace-external-staging-post.json" '
  .package.package_id == $post[0].package.package_id and
  .package.upstream_publication_package_id == $post[0].package.upstream_publication_package_id and
  .external_staging_bundle.bundle_id == $post[0].external_staging_bundle.bundle_id and
  .external_staging_readiness_report.technical_external_staging_state == $post[0].external_staging_readiness_report.technical_external_staging_state
' "${OUT}/workspace-external-staging.json" >/dev/null

jq -e '
  .report_profile == "external-registry-dry-run-readiness-v1" and
  .technical_external_staging_state == "ready-for-external-test-staging" and
  .epistemic_readiness_state == "claim-linked-human-eval-pending" and
  .real_registry_call_performed == false and
  .datacite_test_staging_allowed == true and
  .crossref_dry_run_allowed == true and
  .findable_publication_allowed == false and
  .technical_blocker_count == 0 and
  .epistemic_blocker_count >= 1 and
  .warning_count >= 1 and
  any(.checks[]; .check_id == "human-eval-pending-explicit" and .status == "blocked") and
  any(.checks[]; .check_id == "registry-boundary-still-closed" and .status == "warning")
' "${OUT}/external-staging-readiness-report.json" >/dev/null

jq -e '
  .staging_profile == "datacite-test-api-staging-v1" and
  .api_base_url == "https://api.test.datacite.org" and
  .request_path == "/dois" and
  .request_method == "POST" and
  .auth_mode == "repository-account-basic-auth" and
  .target_state == "draft" and
  .real_network_call_performed == false and
  (.doi_candidate | startswith("10.00000/")) and
  .payload.data.type == "dois" and
  .payload.data.attributes.event == "draft" and
  .readiness_state == "claim-linked-human-eval-pending"
' "${OUT}/datacite-test-staging-payload.json" >/dev/null

jq -e '
  .dry_run_profile == "crossref-journal-article-dry-run-v1" and
  .submission_mode == "dry-run-no-submit" and
  .request_method == "POST" and
  .content_type == "application/xml" and
  .transport_target == "crossref-member-deposit-compatible" and
  .schema_hint == "crossref-journal-article-xml" and
  .real_network_call_performed == false and
  .related_item_count >= 1 and
  .readiness_state == "claim-linked-human-eval-pending" and
  (.xml_bundle | contains("<doi_batch")) and
  (.xml_bundle | contains("<journal_article"))
' "${OUT}/crossref-dry-run-bundle.json" >/dev/null

jq -e '
  .bundle_kind == "external-registry-staging-bundle" and
  .technical_external_staging_state == "ready-for-external-test-staging" and
  .readiness_state == "claim-linked-human-eval-pending" and
  (.payload_manifest | length) >= 16 and
  (.provenance.activities | length) >= 1 and
  (.citation.related_identifiers | length) >= 1
' "${OUT}/external-registry-staging-bundle.json" >/dev/null

jq -e '.bundle.campaign_id == "expedition-002-hrv-aware"' "${OUT}/campaign-review-bundle.json" >/dev/null
jq -e '.pack.campaign_id == "expedition-002-hrv-aware" and .pack.jats_profile == "jats-1.4-ready"' "${OUT}/campaign-jats-manuscript-pack.json" >/dev/null

grep -Eq '<article([[:space:]>])' "${OUT}/jats-article.xml"
grep -q "<doi_batch" "${OUT}/crossref-article.xml"
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

jq -e --slurpfile post "${OUT}/workspace-external-staging-post.json" '
  .package.package_id == $post[0].package.package_id and
  .package.session_id == $post[0].package.session_id and
  .package.upstream_publication_package_id == $post[0].package.upstream_publication_package_id and
  .external_staging_readiness_report.technical_external_staging_state == $post[0].external_staging_readiness_report.technical_external_staging_state and
  .context_packet.handoff.last_handoff == $post[0].context_packet.handoff.last_handoff
' "${OUT}/workspace-external-staging-after-restart.json" >/dev/null

jq -e '
  .phase == "B21.5" and
  .workstream_id == "beagle-darwin-hpc-governance" and
  .workspace_id == "beagle-cluster-pilot" and
  .session_id == "ws-cluster-workspace-habitat" and
  .source_subagent_id == "manuscript" and
  (.qa_state == "pass-with-warnings" or .qa_state == "pass") and
  .technical_external_staging_state == "ready-for-external-test-staging" and
  .readiness_state == "claim-linked-human-eval-pending" and
  .managed_attach_state == "coder-compatible-ready" and
  .stable_attach_alias == "beagle-cluster-pilot.coder" and
  .claim_count >= 1 and
  .technical_blocker_count == 0 and
  .ro_crate_payload_count >= 8 and
  .restart_recovered_session == true
' "${OUT}/smoke.json" >/dev/null

grep -q "deployment.apps/beagle-core" "${OUT}/final-cluster-health.txt"
grep -q "deployment.apps/beagle-workspace" "${OUT}/final-cluster-health.txt"
grep -Eq 'Slurmctld\(primary\).*UP' "${OUT}/final-cluster-health.txt"

printf '[OK] external registry dry-run smoke artifacts validated\n'
