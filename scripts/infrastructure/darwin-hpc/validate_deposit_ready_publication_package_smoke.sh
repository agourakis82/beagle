#!/usr/bin/env bash
set -euo pipefail

ROOT="${ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)}"
OUT="${OUT:-${ROOT}/.artifacts/darwin-hpc/deposit-ready-publication-package}"

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
  "${OUT}/workspace-publication-package.json" \
  "${OUT}/campaign-review-bundle.json" \
  "${OUT}/campaign-jats-manuscript-pack.json" \
  "${OUT}/publication-readiness-report.json" \
  "${OUT}/datacite-deposit-payload.json" \
  "${OUT}/crossref-deposit-bundle.json" \
  "${OUT}/publication-package-bundle.json" \
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
  "${OUT}/workspace-publication-package-after-restart.json" \
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
  .publication_source_present == 1 and
  .release_source_present == 1 and
  .assembly_source_present == 1 and
  .http_source_present == 1 and
  .datacite_deposit_contract_present == 1 and
  .crossref_deposit_contract_present == 1 and
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
  .route.selection.selected_subagent_id == "manuscript" and
  .route.selection.selected_role_tag == "manuscript-authoring"
' "${OUT}/route-manuscript.json" >/dev/null

jq -e '
  .phase == "B20.9" and
  .handoff.source_subagent_id == "core" and
  .handoff.target_subagent_id == "experiments"
' "${OUT}/handoff-core-to-experiments.json" >/dev/null

jq -e '
  .phase == "B21.1" and
  .manuscript_handoff.target_subagent_id == "manuscript"
' "${OUT}/workspace-manuscript-handoff-post.json" >/dev/null

jq -e '
  .phase == "B21.2" and
  .assembly.source_subagent_id == "manuscript" and
  .assembly.section_profile == "jats-1.4-ready"
' "${OUT}/workspace-manuscript-assembly-post.json" >/dev/null

jq -e '
  .phase == "B21.3" and
  .release.source_subagent_id == "manuscript" and
  .release.readiness_state == "claim-linked-human-eval-pending"
' "${OUT}/workspace-scholarly-release-post.json" >/dev/null

jq -e --slurpfile release "${OUT}/workspace-scholarly-release-post.json" '
  .phase == "B21.4" and
  .package.workstream_id == "beagle-darwin-hpc-governance" and
  .package.workspace_id == "beagle-cluster-pilot" and
  .package.session_id == "ws-cluster-workspace-habitat" and
  .package.source_subagent_id == "manuscript" and
  .package.source_role_tag == "manuscript-authoring" and
  .package.upstream_release_id == $release[0].release.release_id and
  .package.publication_readiness_report_ref == ("workspace-publication-package:" + .package.package_id + ":publication-readiness-report") and
  .package.datacite_deposit_payload_ref == ("workspace-publication-package:" + .package.package_id + ":datacite-deposit-payload") and
  .package.crossref_deposit_bundle_ref == ("workspace-publication-package:" + .package.package_id + ":crossref-deposit-bundle") and
  .package.publication_package_bundle_ref == ("workspace-publication-package:" + .package.package_id + ":publication-package-bundle") and
  .package.readiness_state == "claim-linked-human-eval-pending" and
  .package.section_profile == "jats-1.4-ready" and
  .package.article_type == "research-article" and
  .package.technical_deposit_state == "ready-for-draft-deposit" and
  .package.managed_attach_state == "coder-compatible-ready" and
  .package.stable_attach_alias == "beagle-cluster-pilot.coder" and
  .continuity.qa_state == .scholarly_release.jats_qa_report.qa_state and
  .continuity.qa_warning_count == .scholarly_release.jats_qa_report.warning_count and
  .continuity.qa_failure_count == .scholarly_release.jats_qa_report.failure_count and
  .continuity.ro_crate_payload_count == (.scholarly_release.ro_crate_export.payload_manifest | length) and
  .continuity.datacite_related_identifier_count == (.scholarly_release.datacite_metadata.related_identifiers | length) and
  .continuity.crossref_related_item_count == .crossref_deposit_bundle.related_item_count and
  .continuity.technical_blocker_count == .publication_readiness_report.technical_blocker_count and
  .continuity.epistemic_blocker_count == .publication_readiness_report.epistemic_blocker_count and
  .continuity.technical_ready_for_staging == true and
  .continuity.findable_publication_allowed == false
' "${OUT}/workspace-publication-package-post.json" >/dev/null

jq -e --slurpfile post "${OUT}/workspace-publication-package-post.json" '
  .package.package_id == $post[0].package.package_id and
  .package.upstream_release_id == $post[0].package.upstream_release_id and
  .publication_package_bundle.bundle_id == $post[0].publication_package_bundle.bundle_id and
  .publication_readiness_report.technical_deposit_state == $post[0].publication_readiness_report.technical_deposit_state
' "${OUT}/workspace-publication-package.json" >/dev/null

jq -e '
  .report_profile == "deposit-ready-publication-readiness-v1" and
  .technical_deposit_state == "ready-for-draft-deposit" and
  .epistemic_readiness_state == "claim-linked-human-eval-pending" and
  .real_deposit_performed == false and
  .doi_staging_allowed == true and
  .crossref_staging_allowed == true and
  .findable_publication_allowed == false and
  .technical_blocker_count == 0 and
  .epistemic_blocker_count >= 1 and
  .warning_count >= 1 and
  any(.checks[]; .check_id == "human-eval-pending-explicit" and .status == "blocked") and
  any(.checks[]; .check_id == "doi-prefix-still-placeholder" and .status == "warning")
' "${OUT}/publication-readiness-report.json" >/dev/null

jq -e '
  .deposit_profile == "datacite-rest-api-draft-staging-v1" and
  .api_shape_version == "datacite-rest-api-doi-draft" and
  .target_state == "draft" and
  .real_deposit_performed == false and
  .prefix_placeholder == "10.00000" and
  (.doi_candidate | startswith("10.00000/")) and
  .payload.data.type == "dois" and
  .payload.data.attributes.event == "draft" and
  .readiness_state == "claim-linked-human-eval-pending"
' "${OUT}/datacite-deposit-payload.json" >/dev/null

jq -e '
  .export_profile == "crossref-journal-article-deposit-bundle-v1" and
  .submission_mode == "deposit-ready-no-submit" and
  .real_deposit_performed == false and
  .related_item_count >= 1 and
  .readiness_state == "claim-linked-human-eval-pending" and
  (.xml_bundle | contains("<doi_batch")) and
  (.xml_bundle | contains("<journal_article"))
' "${OUT}/crossref-deposit-bundle.json" >/dev/null

jq -e '
  .bundle_kind == "deposit-ready-publication-package" and
  .technical_deposit_state == "ready-for-draft-deposit" and
  .readiness_state == "claim-linked-human-eval-pending" and
  (.payload_manifest | length) >= 12 and
  (.provenance.activities | length) >= 1 and
  (.citation.related_identifiers | length) >= 1
' "${OUT}/publication-package-bundle.json" >/dev/null

jq -e '
  .qa_profile == "jats-1.4-bounded-qa-v1" and
  (.qa_state == "pass-with-warnings" or .qa_state == "pass") and
  .failure_count == 0 and
  any(.checks[]; .check_id == "human-eval-pending-explicit")
' "${OUT}/jats-qa-report.json" >/dev/null

jq -e '
  ."@context" == "https://w3id.org/ro/crate/1.1/context" and
  (."@graph" | length) >= 5
' "${OUT}/ro-crate-metadata.json" >/dev/null

jq -e '
  .metadata_profile == "datacite-4.7-ready" and
  (.identifiers | length) >= 1 and
  (.creators | length) >= 1 and
  .readiness_state == "claim-linked-human-eval-pending"
' "${OUT}/datacite-metadata.json" >/dev/null

jq -e '
  .bundle.campaign_id == "expedition-002-hrv-aware"
' "${OUT}/campaign-review-bundle.json" >/dev/null

jq -e '
  .pack.campaign_id == "expedition-002-hrv-aware" and
  .pack.jats_profile == "jats-1.4-ready"
' "${OUT}/campaign-jats-manuscript-pack.json" >/dev/null

grep -q "<article " "${OUT}/jats-article.xml"
grep -q "<ref-list>" "${OUT}/jats-article.xml"
grep -q "<doi_batch" "${OUT}/crossref-article.xml"
grep -q "<journal_article" "${OUT}/crossref-article.xml"
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

jq -e --slurpfile post "${OUT}/workspace-publication-package-post.json" '
  .package.package_id == $post[0].package.package_id and
  .package.session_id == $post[0].package.session_id and
  .package.upstream_release_id == $post[0].package.upstream_release_id and
  .publication_readiness_report.technical_deposit_state == $post[0].publication_readiness_report.technical_deposit_state and
  .context_packet.handoff.last_handoff == $post[0].context_packet.handoff.last_handoff
' "${OUT}/workspace-publication-package-after-restart.json" >/dev/null

jq -e '
  .phase == "B21.4" and
  .workstream_id == "beagle-darwin-hpc-governance" and
  .workspace_id == "beagle-cluster-pilot" and
  .session_id == "ws-cluster-workspace-habitat" and
  .source_subagent_id == "manuscript" and
  (.qa_state == "pass-with-warnings" or .qa_state == "pass") and
  .technical_deposit_state == "ready-for-draft-deposit" and
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

printf '[OK] deposit-ready publication package smoke artifacts validated\n'
