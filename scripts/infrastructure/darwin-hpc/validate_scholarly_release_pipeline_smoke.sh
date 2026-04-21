#!/usr/bin/env bash
set -euo pipefail

ROOT="${ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)}"
OUT="${OUT:-${ROOT}/.artifacts/darwin-hpc/scholarly-release-pipeline}"

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
  "${OUT}/workspace-scholarly-release.json" \
  "${OUT}/campaign-review-bundle.json" \
  "${OUT}/campaign-jats-manuscript-pack.json" \
  "${OUT}/jats-qa-report.json" \
  "${OUT}/ro-crate-metadata.json" \
  "${OUT}/datacite-metadata.json" \
  "${OUT}/crossref-article-stub.json" \
  "${OUT}/crossref-article.xml" \
  "${OUT}/release-bundle.json" \
  "${OUT}/jats-article.xml" \
  "${OUT}/workspace-context.json" \
  "${OUT}/workspace-context-after-restart.json" \
  "${OUT}/workspace-context.env" \
  "${OUT}/manuscript.env" \
  "${OUT}/manuscript-identity.txt" \
  "${OUT}/manuscript-identity-after-restart.txt" \
  "${OUT}/workspace-scholarly-release-after-restart.json" \
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
  .release_source_present == 1 and
  .assembly_source_present == 1 and
  .review_bundle_source_present == 1 and
  .http_source_present == 1 and
  .release_contract_present == 1 and
  .jats_qa_contract_present == 1 and
  .datacite_contract_present == 1 and
  .crossref_contract_present == 1 and
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

jq -e --slurpfile assembly "${OUT}/workspace-manuscript-assembly-post.json" '
  .phase == "B21.3" and
  .release.workstream_id == "beagle-darwin-hpc-governance" and
  .release.workspace_id == "beagle-cluster-pilot" and
  .release.session_id == "ws-cluster-workspace-habitat" and
  .release.source_subagent_id == "manuscript" and
  .release.source_role_tag == "manuscript-authoring" and
  .release.upstream_assembly_id == $assembly[0].assembly.assembly_id and
  .release.jats_qa_report_ref == ("workspace-scholarly-release:" + .release.release_id + ":jats-qa-report") and
  .release.ro_crate_export_ref == ("workspace-scholarly-release:" + .release.release_id + ":ro-crate-export") and
  .release.datacite_metadata_ref == ("workspace-scholarly-release:" + .release.release_id + ":datacite-ready") and
  .release.crossref_article_stub_ref == ("workspace-scholarly-release:" + .release.release_id + ":crossref-article-stub") and
  .release.release_bundle_ref == ("workspace-scholarly-release:" + .release.release_id + ":release-bundle") and
  .release.section_profile == "jats-1.4-ready" and
  .release.article_type == "research-article" and
  .release.readiness_state == "claim-linked-human-eval-pending" and
  .release.managed_attach_state == "coder-compatible-ready" and
  .release.stable_attach_alias == "beagle-cluster-pilot.coder" and
  .continuity.jats_qa_status == .jats_qa_report.qa_state and
  .continuity.qa_warning_count == .jats_qa_report.warning_count and
  .continuity.qa_failure_count == .jats_qa_report.failure_count and
  .continuity.ro_crate_payload_count == (.ro_crate_export.payload_manifest | length) and
  .continuity.datacite_related_identifier_count == (.datacite_metadata.related_identifiers | length) and
  .continuity.crossref_related_item_count == (.crossref_article_stub.related_items | length) and
  .jats_qa_report.qa_profile == "jats-1.4-bounded-qa-v1" and
  (.jats_qa_report.qa_state == "pass-with-warnings" or .jats_qa_report.qa_state == "pass") and
  .jats_qa_report.failure_count == 0 and
  (.jats_qa_report.checks | length) >= 6 and
  .ro_crate_export.export_profile == "ro-crate-1.2-release-bounded" and
  .datacite_metadata.metadata_profile == "datacite-4.7-ready" and
  .crossref_article_stub.export_profile == "crossref-journal-article-stub-v1" and
  (.crossref_article_stub.xml_stub | contains("<doi_batch")) and
  (.crossref_article_stub.xml_stub | contains("<journal_article")) and
  .release_bundle.readiness_state == .release.readiness_state and
  (.release_bundle.payload_manifest | length) >= 8 and
  .release_bundle.provenance.profile == .review_bundle.provenance.profile and
  .context_packet.handoff.last_handoff == $assembly[0].context_packet.handoff.last_handoff
' "${OUT}/workspace-scholarly-release-post.json" >/dev/null

jq -e --slurpfile post "${OUT}/workspace-scholarly-release-post.json" '
  .release.release_id == $post[0].release.release_id and
  .release.upstream_assembly_id == $post[0].release.upstream_assembly_id and
  .release_bundle.bundle_id == $post[0].release_bundle.bundle_id and
  .jats_qa_report.qa_state == $post[0].jats_qa_report.qa_state
' "${OUT}/workspace-scholarly-release.json" >/dev/null

jq -e '
  .qa_profile == "jats-1.4-bounded-qa-v1" and
  (.qa_state == "pass-with-warnings" or .qa_state == "pass") and
  .failure_count == 0 and
  (.checks | length) >= 6 and
  any(.checks[]; .check_id == "article-root" and .status == "pass") and
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
  (.titles | length) >= 1 and
  (.related_identifiers | length) >= 1 and
  .readiness_state == "claim-linked-human-eval-pending"
' "${OUT}/datacite-metadata.json" >/dev/null

jq -e '
  .export_profile == "crossref-journal-article-stub-v1" and
  (.contributors | length) >= 1 and
  (.related_items | length) >= 1 and
  (.xml_stub | contains("<doi_batch")) and
  (.xml_stub | contains("<journal_article")) and
  .readiness_state == "claim-linked-human-eval-pending"
' "${OUT}/crossref-article-stub.json" >/dev/null

jq -e '
  .bundle_kind == "scholarly-release-bundle" and
  (.payload_manifest | length) >= 8 and
  .readiness_state == "claim-linked-human-eval-pending" and
  (.provenance.activities | length) >= 1 and
  (.citation.related_identifiers | length) >= 1
' "${OUT}/release-bundle.json" >/dev/null

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

jq -e --slurpfile post "${OUT}/workspace-scholarly-release-post.json" '
  .release.release_id == $post[0].release.release_id and
  .release.session_id == $post[0].release.session_id and
  .release.upstream_assembly_id == $post[0].release.upstream_assembly_id and
  .jats_qa_report.qa_state == $post[0].jats_qa_report.qa_state and
  .context_packet.handoff.last_handoff == $post[0].context_packet.handoff.last_handoff
' "${OUT}/workspace-scholarly-release-after-restart.json" >/dev/null

jq -e '
  .phase == "B21.3" and
  .workstream_id == "beagle-darwin-hpc-governance" and
  .workspace_id == "beagle-cluster-pilot" and
  .session_id == "ws-cluster-workspace-habitat" and
  .source_subagent_id == "manuscript" and
  (.qa_state == "pass-with-warnings" or .qa_state == "pass") and
  .jats_profile == "jats-1.4-ready" and
  .readiness_state == "claim-linked-human-eval-pending" and
  .managed_attach_state == "coder-compatible-ready" and
  .stable_attach_alias == "beagle-cluster-pilot.coder" and
  .claim_count >= 1 and
  .ro_crate_payload_count >= 8 and
  .restart_recovered_session == true
' "${OUT}/smoke.json" >/dev/null

grep -q "deployment.apps/beagle-core" "${OUT}/final-cluster-health.txt"
grep -q "deployment.apps/beagle-workspace" "${OUT}/final-cluster-health.txt"
grep -Eq 'Slurmctld\(primary\).*UP' "${OUT}/final-cluster-health.txt"

printf '[OK] scholarly release pipeline smoke artifacts validated\n'
