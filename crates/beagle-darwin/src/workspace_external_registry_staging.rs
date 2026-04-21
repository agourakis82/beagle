use crate::workspace_publication_package::{
    read_workspace_publication_package, CrossrefDepositBundle, DataCiteDepositPayload,
    WorkspacePublicationPackageResponse,
};
use crate::workspace_scholarly_release::WorkspaceScholarlyReleaseResponse;
use crate::workspace_subagents::{WorkspaceSubAgentRole, WorkspaceSubAgentsPlane};
use crate::{
    CampaignClaimsResponse, EvidencePack, EvidencePackCitation, EvidencePackProvenance,
    ProgramContextPacket, ReviewBundle, ScholarlyReleasePayloadItem, WorkstreamContextPacket,
    WorkstreamContextPacketResponse,
};
use anyhow::{anyhow, Context};
use beagle_config::BeagleConfig;
use chrono::{DateTime, Utc};
use serde::{Deserialize, Serialize};
use serde_json::Value;
use std::fs;
use std::path::{Path, PathBuf};

const WORKSPACE_EXTERNAL_STAGING_PHASE: &str = "B21.5";
const WORKSPACE_EXTERNAL_STAGING_VERSION: &str = "beagle-external-registry-staging-v1";
const WORKSPACE_EXTERNAL_STAGING_KIND: &str = "workspace-external-registry-staging";
const MANUSCRIPT_SUBAGENT_ID: &str = "manuscript";
const EXTERNAL_STAGING_READINESS_PROFILE: &str = "external-registry-dry-run-readiness-v1";
const DATACITE_TEST_STAGING_PROFILE: &str = "datacite-test-api-staging-v1";
const CROSSREF_DRY_RUN_PROFILE: &str = "crossref-journal-article-dry-run-v1";
const DATACITE_TEST_API_BASE: &str = "https://api.test.datacite.org";

#[derive(Debug, Clone, Serialize, Deserialize)]
struct WorkspaceExternalRegistryStagingRecord {
    package_version: String,
    package_id: String,
    workstream_id: String,
    workspace_id: String,
    session_id: String,
    source_subagent_id: String,
    source_role_tag: String,
    requested_tool_id: Option<String>,
    staging_goal: String,
    summary: String,
    dry_run_notes: String,
    upstream_publication_package_id: String,
    upstream_release_id: String,
    upstream_assembly_id: String,
    upstream_manuscript_handoff_id: String,
    upstream_subagent_handoff_id: String,
    recorded_at: DateTime<Utc>,
    program_id: String,
    campaign_id: String,
    manuscript_pack_id: String,
    jats_pack_id: String,
    managed_attach_state: String,
    stable_attach_alias: String,
}

#[derive(Debug, Clone)]
pub struct WorkspaceExternalRegistryStagingRequest<'a> {
    pub source_subagent_id: &'a str,
    pub requested_tool_id: Option<&'a str>,
    pub staging_goal: &'a str,
    pub summary: &'a str,
    pub dry_run_notes: &'a str,
}

#[derive(Debug, Clone, Serialize)]
pub struct WorkspaceExternalRegistryStagingPlane {
    pub package_version: String,
    pub package_kind: String,
    pub package_id: String,
    pub workstream_id: String,
    pub workspace_id: String,
    pub session_id: String,
    pub package_state: String,
    pub recorded_at: DateTime<Utc>,
    pub source_subagent_id: String,
    pub source_role_tag: String,
    pub requested_tool_id: Option<String>,
    pub staging_goal: String,
    pub summary: String,
    pub dry_run_notes: String,
    pub upstream_publication_package_id: String,
    pub upstream_release_id: String,
    pub upstream_assembly_id: String,
    pub upstream_manuscript_handoff_id: String,
    pub upstream_subagent_handoff_id: String,
    pub workspace_external_staging_path: String,
    pub workspace_publication_package_ref: String,
    pub external_staging_readiness_report_ref: String,
    pub datacite_test_staging_payload_ref: String,
    pub crossref_dry_run_bundle_ref: String,
    pub external_staging_bundle_ref: String,
    pub program_id: String,
    pub campaign_id: String,
    pub manuscript_pack_id: String,
    pub jats_pack_id: String,
    pub readiness_state: String,
    pub technical_external_staging_state: String,
    pub section_profile: String,
    pub article_type: String,
    pub managed_attach_state: String,
    pub stable_attach_alias: String,
    pub note: String,
}

#[derive(Debug, Clone, Serialize)]
pub struct WorkspaceExternalRegistryStagingContinuity {
    pub handoff_present: bool,
    pub propagated_handoff: Option<String>,
    pub claim_count: usize,
    pub supported_claim_count: usize,
    pub result_ref_count: usize,
    pub memory_ref_count: usize,
    pub physio_ref_count: usize,
    pub review_payload_count: usize,
    pub ro_crate_payload_count: usize,
    pub datacite_related_identifier_count: usize,
    pub crossref_related_item_count: usize,
    pub qa_state: String,
    pub qa_warning_count: usize,
    pub qa_failure_count: usize,
    pub technical_blocker_count: usize,
    pub epistemic_blocker_count: usize,
    pub technical_ready_for_external_staging: bool,
    pub findable_publication_allowed: bool,
    pub readiness_state: String,
    pub source_env_file: String,
    pub source_workspace_folder: String,
    pub source_shell_entry_hint: String,
    pub restart_recovered_session: bool,
}

#[derive(Debug, Clone, Serialize)]
pub struct ExternalStagingReadinessCheck {
    pub check_id: String,
    pub dimension: String,
    pub description: String,
    pub status: String,
    pub detail: String,
}

#[derive(Debug, Clone, Serialize)]
pub struct ExternalStagingReadinessReport {
    pub report_profile: String,
    pub checked_at: DateTime<Utc>,
    pub technical_external_staging_state: String,
    pub epistemic_readiness_state: String,
    pub real_registry_call_performed: bool,
    pub datacite_test_staging_allowed: bool,
    pub crossref_dry_run_allowed: bool,
    pub findable_publication_allowed: bool,
    pub technical_blocker_count: usize,
    pub epistemic_blocker_count: usize,
    pub warning_count: usize,
    pub checks: Vec<ExternalStagingReadinessCheck>,
    pub note: String,
}

#[derive(Debug, Clone, Serialize)]
pub struct DataCiteTestStagingPayload {
    pub staging_profile: String,
    pub api_base_url: String,
    pub request_path: String,
    pub request_method: String,
    pub auth_mode: String,
    pub target_state: String,
    pub real_network_call_performed: bool,
    pub doi_candidate: String,
    pub payload: Value,
    pub readiness_state: String,
    pub note: String,
}

#[derive(Debug, Clone, Serialize)]
pub struct CrossrefDryRunBundle {
    pub dry_run_profile: String,
    pub bundle_id: String,
    pub submission_mode: String,
    pub request_method: String,
    pub content_type: String,
    pub transport_target: String,
    pub schema_hint: String,
    pub real_network_call_performed: bool,
    pub batch_id: String,
    pub journal_title: String,
    pub article_title: String,
    pub related_item_count: usize,
    pub readiness_state: String,
    pub xml_bundle: String,
    pub note: String,
}

#[derive(Debug, Clone, Serialize)]
pub struct ExternalRegistryStagingBundle {
    pub bundle_version: String,
    pub bundle_kind: String,
    pub bundle_id: String,
    pub program_id: String,
    pub campaign_id: String,
    pub workstream_id: String,
    pub workspace_id: String,
    pub session_id: String,
    pub manuscript_pack_id: String,
    pub jats_pack_id: String,
    pub readiness_state: String,
    pub technical_external_staging_state: String,
    pub workspace_publication_package_ref: String,
    pub external_staging_readiness_report_ref: String,
    pub datacite_test_staging_payload_ref: String,
    pub crossref_dry_run_bundle_ref: String,
    pub payload_manifest: Vec<ScholarlyReleasePayloadItem>,
    pub provenance: EvidencePackProvenance,
    pub citation: EvidencePackCitation,
    pub note: String,
}

#[derive(Debug, Clone, Serialize)]
pub struct WorkspaceExternalRegistryStagingResponse {
    pub status: String,
    pub phase: String,
    pub package: WorkspaceExternalRegistryStagingPlane,
    pub continuity: WorkspaceExternalRegistryStagingContinuity,
    pub source_role: WorkspaceSubAgentRole,
    pub subagents: WorkspaceSubAgentsPlane,
    pub context_packet: WorkstreamContextPacket,
    pub program_context: ProgramContextPacket,
    pub evidence_pack: EvidencePack,
    pub claims: CampaignClaimsResponse,
    pub review_bundle: ReviewBundle,
    pub scholarly_release: WorkspaceScholarlyReleaseResponse,
    pub publication_package: WorkspacePublicationPackageResponse,
    pub external_staging_readiness_report: ExternalStagingReadinessReport,
    pub datacite_test_staging_payload: DataCiteTestStagingPayload,
    pub crossref_dry_run_bundle: CrossrefDryRunBundle,
    pub external_staging_bundle: ExternalRegistryStagingBundle,
}

pub fn record_workspace_external_registry_staging(
    data_dir: &Path,
    cfg: &BeagleConfig,
    workstream_id: &str,
    context_packet: WorkstreamContextPacketResponse,
    request: WorkspaceExternalRegistryStagingRequest<'_>,
) -> anyhow::Result<WorkspaceExternalRegistryStagingResponse> {
    let upstream = read_workspace_publication_package(data_dir, cfg, workstream_id, context_packet)?
        .ok_or_else(|| anyhow!("a workspace publication package is required before external staging"))?;

    let source_subagent_id = normalize_selector(request.source_subagent_id);
    if source_subagent_id != MANUSCRIPT_SUBAGENT_ID {
        return Err(anyhow!(
            "external registry staging must originate from sub-agent '{}'",
            MANUSCRIPT_SUBAGENT_ID
        ));
    }
    if upstream.package.source_subagent_id != source_subagent_id {
        return Err(anyhow!(
            "latest publication package must originate from '{}' before external staging",
            source_subagent_id
        ));
    }

    let requested_tool_id = request
        .requested_tool_id
        .map(normalize_selector)
        .filter(|value| !value.is_empty())
        .or_else(|| Some("claude-code".to_string()));
    let staging_goal = normalize_sentence(request.staging_goal);
    let summary = normalize_sentence(request.summary);
    let dry_run_notes = normalize_sentence(request.dry_run_notes);
    if staging_goal.is_empty() {
        return Err(anyhow!("external staging goal must not be empty"));
    }
    if summary.is_empty() {
        return Err(anyhow!("external staging summary must not be empty"));
    }
    if dry_run_notes.is_empty() {
        return Err(anyhow!("external staging notes must not be empty"));
    }

    let record = WorkspaceExternalRegistryStagingRecord {
        package_version: WORKSPACE_EXTERNAL_STAGING_VERSION.to_string(),
        package_id: format!(
            "{}-external-staging-{}",
            sanitize_component(&upstream.package.session_id),
            Utc::now().timestamp_millis()
        ),
        workstream_id: upstream.package.workstream_id.clone(),
        workspace_id: upstream.package.workspace_id.clone(),
        session_id: upstream.package.session_id.clone(),
        source_subagent_id: upstream.package.source_subagent_id.clone(),
        source_role_tag: upstream.package.source_role_tag.clone(),
        requested_tool_id,
        staging_goal,
        summary,
        dry_run_notes,
        upstream_publication_package_id: upstream.package.package_id.clone(),
        upstream_release_id: upstream.package.upstream_release_id.clone(),
        upstream_assembly_id: upstream.package.upstream_assembly_id.clone(),
        upstream_manuscript_handoff_id: upstream.package.upstream_manuscript_handoff_id.clone(),
        upstream_subagent_handoff_id: upstream.package.upstream_subagent_handoff_id.clone(),
        recorded_at: Utc::now(),
        program_id: upstream.package.program_id.clone(),
        campaign_id: upstream.package.campaign_id.clone(),
        manuscript_pack_id: upstream.package.manuscript_pack_id.clone(),
        jats_pack_id: upstream.package.jats_pack_id.clone(),
        managed_attach_state: upstream.package.managed_attach_state.clone(),
        stable_attach_alias: upstream.package.stable_attach_alias.clone(),
    };
    write_external_staging_record(data_dir, &record.workspace_id, &record)?;

    response_from_state(&upstream, record)
}

pub fn read_workspace_external_registry_staging(
    data_dir: &Path,
    cfg: &BeagleConfig,
    workstream_id: &str,
    context_packet: WorkstreamContextPacketResponse,
) -> anyhow::Result<Option<WorkspaceExternalRegistryStagingResponse>> {
    let Some(record) = read_external_staging_record(data_dir, &context_packet.packet.workspace_id)?
    else {
        return Ok(None);
    };
    let upstream = read_workspace_publication_package(data_dir, cfg, workstream_id, context_packet)?
        .ok_or_else(|| anyhow!("workspace publication package is unavailable for external staging shaping"))?;
    response_from_state(&upstream, record).map(Some)
}

fn response_from_state(
    upstream: &WorkspacePublicationPackageResponse,
    record: WorkspaceExternalRegistryStagingRecord,
) -> anyhow::Result<WorkspaceExternalRegistryStagingResponse> {
    let payload_manifest = build_external_staging_payload_manifest(&record, upstream);
    let external_staging_readiness_report = build_external_staging_readiness_report(upstream);
    let datacite_test_staging_payload =
        build_datacite_test_staging_payload(&record, &upstream.datacite_deposit_payload);
    let crossref_dry_run_bundle =
        build_crossref_dry_run_bundle(&record, &upstream.crossref_deposit_bundle);
    let external_staging_bundle = build_external_staging_bundle(
        &record,
        upstream,
        &payload_manifest,
        &external_staging_readiness_report,
    );

    let package = WorkspaceExternalRegistryStagingPlane {
        package_version: WORKSPACE_EXTERNAL_STAGING_VERSION.to_string(),
        package_kind: WORKSPACE_EXTERNAL_STAGING_KIND.to_string(),
        package_id: record.package_id.clone(),
        workstream_id: record.workstream_id.clone(),
        workspace_id: record.workspace_id.clone(),
        session_id: record.session_id.clone(),
        package_state: "external-registry-staged".to_string(),
        recorded_at: record.recorded_at,
        source_subagent_id: record.source_subagent_id.clone(),
        source_role_tag: record.source_role_tag.clone(),
        requested_tool_id: record.requested_tool_id.clone(),
        staging_goal: record.staging_goal.clone(),
        summary: record.summary.clone(),
        dry_run_notes: record.dry_run_notes.clone(),
        upstream_publication_package_id: record.upstream_publication_package_id.clone(),
        upstream_release_id: record.upstream_release_id.clone(),
        upstream_assembly_id: record.upstream_assembly_id.clone(),
        upstream_manuscript_handoff_id: record.upstream_manuscript_handoff_id.clone(),
        upstream_subagent_handoff_id: record.upstream_subagent_handoff_id.clone(),
        workspace_external_staging_path: format!(
            "/api/darwin/workstreams/{}/workspace-external-staging",
            record.workstream_id
        ),
        workspace_publication_package_ref: format!(
            "workspace-publication-package:{}",
            record.upstream_publication_package_id
        ),
        external_staging_readiness_report_ref: format!(
            "workspace-external-staging:{}:external-staging-readiness-report",
            record.package_id
        ),
        datacite_test_staging_payload_ref: format!(
            "workspace-external-staging:{}:datacite-test-staging-payload",
            record.package_id
        ),
        crossref_dry_run_bundle_ref: format!(
            "workspace-external-staging:{}:crossref-dry-run-bundle",
            record.package_id
        ),
        external_staging_bundle_ref: format!(
            "workspace-external-staging:{}:external-staging-bundle",
            record.package_id
        ),
        program_id: record.program_id.clone(),
        campaign_id: record.campaign_id.clone(),
        manuscript_pack_id: record.manuscript_pack_id.clone(),
        jats_pack_id: record.jats_pack_id.clone(),
        readiness_state: upstream.package.readiness_state.clone(),
        technical_external_staging_state: external_staging_readiness_report
            .technical_external_staging_state
            .clone(),
        section_profile: upstream.package.section_profile.clone(),
        article_type: upstream.package.article_type.clone(),
        managed_attach_state: record.managed_attach_state.clone(),
        stable_attach_alias: record.stable_attach_alias.clone(),
        note: "The external registry staging layer prepares DataCite/Crossref-facing dry-run artifacts without performing real registry calls or hiding epistemic readiness gaps.".to_string(),
    };
    let continuity = WorkspaceExternalRegistryStagingContinuity {
        handoff_present: upstream.continuity.handoff_present,
        propagated_handoff: upstream.continuity.propagated_handoff.clone(),
        claim_count: upstream.continuity.claim_count,
        supported_claim_count: upstream.continuity.supported_claim_count,
        result_ref_count: upstream.continuity.result_ref_count,
        memory_ref_count: upstream.continuity.memory_ref_count,
        physio_ref_count: upstream.continuity.physio_ref_count,
        review_payload_count: upstream.continuity.review_payload_count,
        ro_crate_payload_count: upstream.continuity.ro_crate_payload_count,
        datacite_related_identifier_count: upstream.continuity.datacite_related_identifier_count,
        crossref_related_item_count: upstream.continuity.crossref_related_item_count,
        qa_state: upstream.continuity.qa_state.clone(),
        qa_warning_count: upstream.continuity.qa_warning_count,
        qa_failure_count: upstream.continuity.qa_failure_count,
        technical_blocker_count: external_staging_readiness_report.technical_blocker_count,
        epistemic_blocker_count: external_staging_readiness_report.epistemic_blocker_count,
        technical_ready_for_external_staging: external_staging_readiness_report
            .datacite_test_staging_allowed
            && external_staging_readiness_report.crossref_dry_run_allowed,
        findable_publication_allowed: external_staging_readiness_report.findable_publication_allowed,
        readiness_state: upstream.package.readiness_state.clone(),
        source_env_file: upstream.continuity.source_env_file.clone(),
        source_workspace_folder: upstream.continuity.source_workspace_folder.clone(),
        source_shell_entry_hint: upstream.continuity.source_shell_entry_hint.clone(),
        restart_recovered_session: true,
    };

    Ok(WorkspaceExternalRegistryStagingResponse {
        status: "ok".to_string(),
        phase: WORKSPACE_EXTERNAL_STAGING_PHASE.to_string(),
        package,
        continuity,
        source_role: upstream.source_role.clone(),
        subagents: upstream.subagents.clone(),
        context_packet: upstream.context_packet.clone(),
        program_context: upstream.program_context.clone(),
        evidence_pack: upstream.evidence_pack.clone(),
        claims: upstream.claims.clone(),
        review_bundle: upstream.review_bundle.clone(),
        scholarly_release: upstream.scholarly_release.clone(),
        publication_package: upstream.clone(),
        external_staging_readiness_report,
        datacite_test_staging_payload,
        crossref_dry_run_bundle,
        external_staging_bundle,
    })
}

fn build_external_staging_payload_manifest(
    record: &WorkspaceExternalRegistryStagingRecord,
    upstream: &WorkspacePublicationPackageResponse,
) -> Vec<ScholarlyReleasePayloadItem> {
    let mut payloads = upstream.publication_package_bundle.payload_manifest.clone();
    payloads.push(ScholarlyReleasePayloadItem {
        logical_path: "reports/external-staging-readiness-report.json".to_string(),
        payload_kind: "external-staging-readiness-report".to_string(),
        media_type: "application/json".to_string(),
        reference: format!(
            "workspace-external-staging:{}:external-staging-readiness-report",
            record.package_id
        ),
    });
    payloads.push(ScholarlyReleasePayloadItem {
        logical_path: "exports/datacite-test-staging-payload.json".to_string(),
        payload_kind: "datacite-test-staging-payload".to_string(),
        media_type: "application/json".to_string(),
        reference: format!(
            "workspace-external-staging:{}:datacite-test-staging-payload",
            record.package_id
        ),
    });
    payloads.push(ScholarlyReleasePayloadItem {
        logical_path: "exports/crossref-dry-run-bundle.json".to_string(),
        payload_kind: "crossref-dry-run-bundle".to_string(),
        media_type: "application/json".to_string(),
        reference: format!(
            "workspace-external-staging:{}:crossref-dry-run-bundle",
            record.package_id
        ),
    });
    payloads.push(ScholarlyReleasePayloadItem {
        logical_path: "release/external-registry-staging-bundle.json".to_string(),
        payload_kind: "external-registry-staging-bundle".to_string(),
        media_type: "application/json".to_string(),
        reference: format!(
            "workspace-external-staging:{}:external-staging-bundle",
            record.package_id
        ),
    });
    payloads.push(ScholarlyReleasePayloadItem {
        logical_path: "contracts/datacite-test-staging-payload-schema.yaml".to_string(),
        payload_kind: "datacite-test-staging-contract".to_string(),
        media_type: "text/yaml".to_string(),
        reference: "docs/darwin/hpc/contracts/datacite-test-staging-payload-schema.yaml"
            .to_string(),
    });
    payloads.push(ScholarlyReleasePayloadItem {
        logical_path: "contracts/crossref-dry-run-bundle-schema.yaml".to_string(),
        payload_kind: "crossref-dry-run-contract".to_string(),
        media_type: "text/yaml".to_string(),
        reference: "docs/darwin/hpc/contracts/crossref-dry-run-bundle-schema.yaml".to_string(),
    });
    payloads.push(ScholarlyReleasePayloadItem {
        logical_path: "contracts/external-staging-readiness-report-schema.yaml".to_string(),
        payload_kind: "external-staging-readiness-contract".to_string(),
        media_type: "text/yaml".to_string(),
        reference:
            "docs/darwin/hpc/contracts/external-staging-readiness-report-schema.yaml"
                .to_string(),
    });
    payloads
}

fn build_external_staging_readiness_report(
    upstream: &WorkspacePublicationPackageResponse,
) -> ExternalStagingReadinessReport {
    let jats_qa_ok = upstream.continuity.qa_failure_count == 0
        && matches!(upstream.continuity.qa_state.as_str(), "pass" | "pass-with-warnings");
    let publication_package_present = !upstream.publication_package_bundle.payload_manifest.is_empty();
    let datacite_draft_ready = upstream.datacite_deposit_payload.target_state == "draft"
        && !upstream.datacite_deposit_payload.doi_candidate.is_empty();
    let crossref_xml_ready = upstream.crossref_deposit_bundle.xml_bundle.contains("<doi_batch")
        && upstream
            .crossref_deposit_bundle
            .xml_bundle
            .contains("<journal_article");
    let readiness_pending = upstream.package.readiness_state.contains("pending");

    let mut checks = vec![
        readiness_check(
            "jats-qa-still-passing",
            "technical",
            "JATS QA remains acceptable for external staging.",
            jats_qa_ok,
            "expected pass or pass-with-warnings with zero failures",
        ),
        readiness_check(
            "publication-package-present",
            "technical",
            "The deposit-ready publication package exists before external staging.",
            publication_package_present,
            "expected an upstream publication package payload manifest",
        ),
        readiness_check(
            "datacite-draft-ready",
            "technical",
            "The DataCite deposit payload is ready to be pointed at the test API in draft mode.",
            datacite_draft_ready,
            "expected DataCite draft staging metadata with a DOI candidate",
        ),
        readiness_check(
            "crossref-dry-run-ready",
            "technical",
            "The Crossref journal/article XML is dry-run ready.",
            crossref_xml_ready,
            "expected Crossref XML with doi_batch and journal_article",
        ),
        ExternalStagingReadinessCheck {
            check_id: "registry-boundary-still-closed".to_string(),
            dimension: "technical".to_string(),
            description:
                "Real registry network calls remain intentionally disabled in this phase."
                    .to_string(),
            status: "warning".to_string(),
            detail:
                "the package is staged for external dry-run workflows only; no DataCite or Crossref submission is executed"
                    .to_string(),
        },
    ];

    checks.push(if readiness_pending {
        ExternalStagingReadinessCheck {
            check_id: "human-eval-pending-explicit".to_string(),
            dimension: "epistemic".to_string(),
            description:
                "Human evaluation pending remains explicit at external staging time."
                    .to_string(),
            status: "blocked".to_string(),
            detail: format!(
                "findable publication remains blocked by readiness_state={}",
                upstream.package.readiness_state
            ),
        }
    } else {
        ExternalStagingReadinessCheck {
            check_id: "human-eval-pending-explicit".to_string(),
            dimension: "epistemic".to_string(),
            description:
                "Human evaluation pending remains explicit at external staging time."
                    .to_string(),
            status: "pass".to_string(),
            detail: "no epistemic pending state is attached to this staging package".to_string(),
        }
    });

    let technical_blocker_count = checks
        .iter()
        .filter(|check| check.dimension == "technical" && check.status == "blocked")
        .count();
    let epistemic_blocker_count = checks
        .iter()
        .filter(|check| check.dimension == "epistemic" && check.status == "blocked")
        .count();
    let warning_count = checks.iter().filter(|check| check.status == "warning").count();

    ExternalStagingReadinessReport {
        report_profile: EXTERNAL_STAGING_READINESS_PROFILE.to_string(),
        checked_at: Utc::now(),
        technical_external_staging_state: if technical_blocker_count == 0 {
            "ready-for-external-test-staging".to_string()
        } else {
            "blocked".to_string()
        },
        epistemic_readiness_state: upstream.package.readiness_state.clone(),
        real_registry_call_performed: false,
        datacite_test_staging_allowed: technical_blocker_count == 0,
        crossref_dry_run_allowed: technical_blocker_count == 0,
        findable_publication_allowed: !readiness_pending && technical_blocker_count == 0,
        technical_blocker_count,
        epistemic_blocker_count,
        warning_count,
        checks,
        note: "The external staging readiness report makes the registry-facing boundary explicit: technical dry-run staging may be ready even while epistemic publication maturity is still pending.".to_string(),
    }
}

fn readiness_check(
    check_id: &str,
    dimension: &str,
    description: &str,
    passed: bool,
    failure_detail: &str,
) -> ExternalStagingReadinessCheck {
    ExternalStagingReadinessCheck {
        check_id: check_id.to_string(),
        dimension: dimension.to_string(),
        description: description.to_string(),
        status: if passed { "pass" } else { "blocked" }.to_string(),
        detail: if passed {
            "check passed".to_string()
        } else {
            failure_detail.to_string()
        },
    }
}

fn build_datacite_test_staging_payload(
    record: &WorkspaceExternalRegistryStagingRecord,
    upstream: &DataCiteDepositPayload,
) -> DataCiteTestStagingPayload {
    let mut payload = upstream.payload.clone();
    if let Some(meta) = payload.get_mut("meta").and_then(Value::as_object_mut) {
        meta.insert(
            "externalStagingPackageId".to_string(),
            Value::String(record.package_id.clone()),
        );
        meta.insert(
            "realNetworkCallPerformed".to_string(),
            Value::Bool(false),
        );
        meta.insert(
            "testApiBaseUrl".to_string(),
            Value::String(DATACITE_TEST_API_BASE.to_string()),
        );
    }

    DataCiteTestStagingPayload {
        staging_profile: DATACITE_TEST_STAGING_PROFILE.to_string(),
        api_base_url: DATACITE_TEST_API_BASE.to_string(),
        request_path: "/dois".to_string(),
        request_method: "POST".to_string(),
        auth_mode: "repository-account-basic-auth".to_string(),
        target_state: upstream.target_state.clone(),
        real_network_call_performed: false,
        doi_candidate: upstream.doi_candidate.clone(),
        payload,
        readiness_state: upstream.readiness_state.clone(),
        note: "The DataCite test staging payload is pointed at the official test API shape and remains dry-run only in this phase.".to_string(),
    }
}

fn build_crossref_dry_run_bundle(
    record: &WorkspaceExternalRegistryStagingRecord,
    upstream: &CrossrefDepositBundle,
) -> CrossrefDryRunBundle {
    CrossrefDryRunBundle {
        dry_run_profile: CROSSREF_DRY_RUN_PROFILE.to_string(),
        bundle_id: format!("{}-crossref-dry-run", record.package_id),
        submission_mode: "dry-run-no-submit".to_string(),
        request_method: "POST".to_string(),
        content_type: "application/xml".to_string(),
        transport_target: "crossref-member-deposit-compatible".to_string(),
        schema_hint: "crossref-journal-article-xml".to_string(),
        real_network_call_performed: false,
        batch_id: upstream.batch_id.clone(),
        journal_title: upstream.journal_title.clone(),
        article_title: upstream.article_title.clone(),
        related_item_count: upstream.related_item_count,
        readiness_state: upstream.readiness_state.clone(),
        xml_bundle: upstream.xml_bundle.clone(),
        note: "The Crossref dry-run bundle keeps deposit-compatible XML intact while freezing the transport boundary as no-submit.".to_string(),
    }
}

fn build_external_staging_bundle(
    record: &WorkspaceExternalRegistryStagingRecord,
    upstream: &WorkspacePublicationPackageResponse,
    payload_manifest: &[ScholarlyReleasePayloadItem],
    readiness_report: &ExternalStagingReadinessReport,
) -> ExternalRegistryStagingBundle {
    ExternalRegistryStagingBundle {
        bundle_version: WORKSPACE_EXTERNAL_STAGING_VERSION.to_string(),
        bundle_kind: "external-registry-staging-bundle".to_string(),
        bundle_id: format!("{}-external-staging-bundle", record.package_id),
        program_id: record.program_id.clone(),
        campaign_id: record.campaign_id.clone(),
        workstream_id: record.workstream_id.clone(),
        workspace_id: record.workspace_id.clone(),
        session_id: record.session_id.clone(),
        manuscript_pack_id: record.manuscript_pack_id.clone(),
        jats_pack_id: record.jats_pack_id.clone(),
        readiness_state: upstream.package.readiness_state.clone(),
        technical_external_staging_state: readiness_report
            .technical_external_staging_state
            .clone(),
        workspace_publication_package_ref: format!(
            "workspace-publication-package:{}",
            record.upstream_publication_package_id
        ),
        external_staging_readiness_report_ref: format!(
            "workspace-external-staging:{}:external-staging-readiness-report",
            record.package_id
        ),
        datacite_test_staging_payload_ref: format!(
            "workspace-external-staging:{}:datacite-test-staging-payload",
            record.package_id
        ),
        crossref_dry_run_bundle_ref: format!(
            "workspace-external-staging:{}:crossref-dry-run-bundle",
            record.package_id
        ),
        payload_manifest: payload_manifest.to_vec(),
        provenance: upstream.publication_package_bundle.provenance.clone(),
        citation: upstream.publication_package_bundle.citation.clone(),
        note: "The external registry staging bundle externalizes the publication package into registry-facing dry-run artifacts while keeping the real submission boundary closed.".to_string(),
    }
}

fn write_external_staging_record(
    data_dir: &Path,
    workspace_id: &str,
    record: &WorkspaceExternalRegistryStagingRecord,
) -> anyhow::Result<()> {
    let path = external_staging_record_path(data_dir, workspace_id);
    if let Some(parent) = path.parent() {
        fs::create_dir_all(parent)
            .with_context(|| format!("create external staging directory {}", parent.display()))?;
    }
    let payload = serde_json::to_vec_pretty(record)
        .context("serialize workspace external staging record")?;
    fs::write(&path, payload)
        .with_context(|| format!("write external staging record {}", path.display()))?;
    Ok(())
}

fn read_external_staging_record(
    data_dir: &Path,
    workspace_id: &str,
) -> anyhow::Result<Option<WorkspaceExternalRegistryStagingRecord>> {
    let path = external_staging_record_path(data_dir, workspace_id);
    if !path.exists() {
        return Ok(None);
    }
    let bytes = fs::read(&path)
        .with_context(|| format!("read external staging record {}", path.display()))?;
    let record = serde_json::from_slice(&bytes)
        .with_context(|| format!("parse external staging record {}", path.display()))?;
    Ok(Some(record))
}

fn external_staging_record_path(data_dir: &Path, workspace_id: &str) -> PathBuf {
    workspace_external_staging_dir(data_dir).join(format!(
        "{}.json",
        sanitize_component(workspace_id)
    ))
}

fn workspace_external_staging_dir(data_dir: &Path) -> PathBuf {
    crate::workspace_plane::workspace_plane_dir(data_dir).join("external-registry-staging")
}

fn normalize_selector(value: &str) -> String {
    value.trim().to_ascii_lowercase()
}

fn normalize_sentence(value: &str) -> String {
    value.split_whitespace().collect::<Vec<_>>().join(" ")
}

fn sanitize_component(value: &str) -> String {
    value
        .chars()
        .map(|ch| if ch.is_ascii_alphanumeric() { ch } else { '-' })
        .collect::<String>()
        .trim_matches('-')
        .to_string()
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::workspace_manuscript_assembly::{
        record_workspace_manuscript_assembly, WorkspaceManuscriptAssemblyRequest,
    };
    use crate::workspace_manuscript_handoff::{
        record_workspace_manuscript_handoff, WorkspaceManuscriptHandoffRequest,
    };
    use crate::workspace_plane::{write_workspace_session, WorkspaceSessionState};
    use crate::workspace_publication_package::{
        record_workspace_publication_package, WorkspacePublicationPackageRequest,
    };
    use crate::workspace_scholarly_release::{
        record_workspace_scholarly_release, WorkspaceScholarlyReleaseRequest,
    };
    use crate::workspace_subagent_handoff::{
        record_workspace_subagent_handoff, WorkspaceSubAgentHandoffRequest,
    };
    use crate::{
        WorkstreamContextPacketExperimentFlags, WorkstreamContextPacketHandoff,
        WorkstreamContextPacketLastResult, WorkstreamContextPacketMemoryHit,
        WorkstreamContextPacketPhysioSnapshot, WorkstreamContextPacketRecipe,
        WorkstreamContextPacketResultSummary,
    };
    use beagle_config::{
        AdvancedModulesConfig, ConsumerAccessConfig, GraphConfig, HermesConfig, LlmConfig,
        ObserverThresholds, StorageConfig, ToolBridgeConfig, WorkspaceHabitatConfig,
        WorkspacePlaneConfig,
    };
    use std::env;

    fn packet() -> WorkstreamContextPacketResponse {
        WorkstreamContextPacketResponse {
            status: "ok".to_string(),
            phase: "B18.1".to_string(),
            packet: WorkstreamContextPacket {
                packet_version: "beagle-memory-aware-context-packet-v1".to_string(),
                workstream_id: "beagle-darwin-hpc-governance".to_string(),
                workspace_id: "beagle-cluster-pilot".to_string(),
                session_id: "ws-cluster-workspace-habitat".to_string(),
                repo: "agourakis82/beagle".to_string(),
                branch: "feat/darwin-hpc-governance".to_string(),
                governance_state: "canonical".to_string(),
                handoff: WorkstreamContextPacketHandoff {
                    handoff_required: true,
                    recovery_required: true,
                    handoff_present: true,
                    last_handoff: Some("resume from canonical Beagle workspace state".to_string()),
                },
                last_result: WorkstreamContextPacketLastResult {
                    available: true,
                    reference: None,
                    summary: Some(WorkstreamContextPacketResultSummary {
                        job_id: 31,
                        state: "published".to_string(),
                        run_label: "darwin-hpc-governance".to_string(),
                        profile_id: "cpu-short-v1".to_string(),
                        node_list: "t560-proxmox".to_string(),
                        manifest_key: "results/darwin-hpc-governance/result-31.json".to_string(),
                        source_phase: Some("B21.3".to_string()),
                        source_run_id: Some("b213-scholarly-release".to_string()),
                    }),
                    manifest: None,
                    error: None,
                },
                last_successful_task: None,
                latest_physio: Some(WorkstreamContextPacketPhysioSnapshot {
                    hr: Some(61.0),
                    hrv_level: Some("bounded".to_string()),
                    spo2: Some(98.0),
                    timestamp: None,
                    source: Some("observer-smoke".to_string()),
                }),
                experiment_flags: Some(WorkstreamContextPacketExperimentFlags {
                    hrv_aware: Some(true),
                    observer_enabled: Some(true),
                    serendipity_enabled: Some(false),
                    triad_enabled: Some(false),
                    provider: Some("xai".to_string()),
                    model: Some("grok-4-1-fast-reasoning".to_string()),
                    experiment_id: Some("expedition-002".to_string()),
                    condition: Some("hrv_aware".to_string()),
                }),
                memory_hits: vec![WorkstreamContextPacketMemoryHit {
                    memory_id: Some("memory-1".to_string()),
                    source: "bridge".to_string(),
                    conversation_id: None,
                    turn_index: Some(0),
                    role: Some("assistant".to_string()),
                    snippet: "Stage the canonical campaign package for external dry-run workflows without performing real registry calls.".to_string(),
                    timestamp: None,
                    relevance: 0.91,
                    tags: vec!["handoff".to_string()],
                    domain: Some("darwin-hpc".to_string()),
                    physio_snapshot: None,
                }],
                retrieval_context: None,
                recommended_recipe: Some(WorkstreamContextPacketRecipe {
                    id: "operator_cpu_loop".to_string(),
                    kind: "operator-loop".to_string(),
                    summary: "Continue in bounded operator loop".to_string(),
                }),
                bounded_study_baseline: None,
            },
        }
    }

    fn test_config(data_dir: &Path) -> BeagleConfig {
        let mut cfg = BeagleConfig {
            profile: "cluster".to_string(),
            safe_mode: true,
            api_token: Some("test-token".to_string()),
            llm: LlmConfig::default(),
            storage: StorageConfig {
                data_dir: data_dir.display().to_string(),
            },
            hermes: HermesConfig::default(),
            graph: GraphConfig::default(),
            tool_bridge: ToolBridgeConfig::default(),
            workspace: WorkspacePlaneConfig {
                canonical_workspace_id: "beagle-cluster-pilot".to_string(),
                canonical_repo: "agourakis82/beagle".to_string(),
                canonical_branch: "feat/darwin-hpc-governance".to_string(),
                canonical_track: "darwin-hpc".to_string(),
                operator_name: Some("test-operator".to_string()),
                default_dev_plane: "beagle-cluster".to_string(),
                vm_fallback_role: "fallback-only".to_string(),
                promotion_scope: "beagle-darwin-hpc-general-noninfra".to_string(),
                cutover_workstream: "beagle-darwin-hpc-governance".to_string(),
                cutover_state: "canonical".to_string(),
                cutover_last_transition: "resume".to_string(),
                cutover_branch_lineage: "feat/darwin-hpc-governance".to_string(),
                cutover_default_profile: "cpu-short-v1".to_string(),
                cutover_batch_profile: "cpu-batch-v1".to_string(),
                cutover_advanced_profile: "gpu-single-v1".to_string(),
                cutover_result_publication: "object-backed".to_string(),
                cutover_result_retrieval: "object-backed".to_string(),
                cutover_result_retention_policy: "active".to_string(),
                cutover_operator_consumer_policy: "full".to_string(),
                cutover_research_consumer_policy: "bounded".to_string(),
                cutover_recovery_required: true,
                cutover_handoff_required: true,
                bootstrap_enabled: true,
                habitat: WorkspaceHabitatConfig::default(),
            },
            consumers: ConsumerAccessConfig::default(),
            advanced: AdvancedModulesConfig::default(),
            observer: ObserverThresholds::default(),
        };
        cfg.workspace.habitat.ssh_enabled = true;
        cfg.workspace.habitat.ssh_service_port = 2222;
        cfg.workspace.habitat.ssh_user = "openvscode-server".to_string();
        cfg
    }

    fn seed_workspace(data_dir: &Path) {
        let cfg = test_config(data_dir);
        let mut state = WorkspaceSessionState::new(
            &cfg,
            "beagle-cluster-pilot".to_string(),
            Some("ws-cluster-workspace-habitat".to_string()),
        );
        state.last_handoff = Some("resume from canonical Beagle workspace state".to_string());
        write_workspace_session(data_dir, &state).expect("seed workspace session");
    }

    fn seed_upstream(
        data_dir: &Path,
        cfg: &BeagleConfig,
    ) -> (WorkstreamContextPacketResponse, WorkspacePublicationPackageResponse) {
        seed_workspace(data_dir);
        let context_packet = packet();
        let _subagent_handoff = record_workspace_subagent_handoff(
            data_dir,
            cfg,
            "beagle-darwin-hpc-governance",
            context_packet.clone(),
            WorkspaceSubAgentHandoffRequest {
                source_subagent_id: "core",
                target_subagent_id: "experiments",
                requested_tool_id: Some("codex"),
                requested_work_mode: Some("implementation"),
                intent: "Prepare the experiments workspace",
                summary: "Shift implementation results into experiments analysis.",
            },
        )
        .expect("record subagent handoff");
        let _manuscript_handoff = record_workspace_manuscript_handoff(
            data_dir,
            cfg,
            "beagle-darwin-hpc-governance",
            context_packet.clone(),
            WorkspaceManuscriptHandoffRequest {
                source_subagent_id: "experiments",
                requested_tool_id: Some("claude-code"),
                requested_work_mode: Some("manuscript"),
                intent: "Move experiments output into manuscript drafting",
                summary: "Shift the experiments interpretation into manuscript drafting.",
                manuscript_goal: "Create the canonical manuscript surface.",
            },
        )
        .expect("record manuscript handoff");
        let _assembly = record_workspace_manuscript_assembly(
            data_dir,
            cfg,
            "beagle-darwin-hpc-governance",
            context_packet.clone(),
            WorkspaceManuscriptAssemblyRequest {
                source_subagent_id: "manuscript",
                requested_tool_id: Some("claude-code"),
                intent: "Assemble the canonical editorial artifact",
                summary: "Freeze the bounded editorial assembly for Expedition 002.",
                assembly_goal: "Produce a JATS-ready manuscript package.",
                section_profile: Some("jats-1.4-ready"),
            },
        )
        .expect("record manuscript assembly");
        let _release = record_workspace_scholarly_release(
            data_dir,
            cfg,
            "beagle-darwin-hpc-governance",
            context_packet.clone(),
            WorkspaceScholarlyReleaseRequest {
                source_subagent_id: "manuscript",
                requested_tool_id: Some("claude-code"),
                summary: "Freeze the canonical scholarly release bundle.",
                release_goal: "Produce the release-grade scholarly package.",
                release_notes:
                    "Keep JATS QA, RO-Crate, DataCite metadata, and Crossref article XML explicit.",
            },
        )
        .expect("record scholarly release");
        let publication = record_workspace_publication_package(
            data_dir,
            cfg,
            "beagle-darwin-hpc-governance",
            context_packet.clone(),
            WorkspacePublicationPackageRequest {
                source_subagent_id: "manuscript",
                requested_tool_id: Some("claude-code"),
                publication_goal:
                    "Stage the scholarly release as a deposit-ready publication package without performing real DOI or Crossref submission.",
                summary:
                    "Freeze the canonical campaign as a deposit-ready publication package.",
                staging_notes:
                    "Prepare DataCite draft staging payloads, Crossref deposit-ready XML, and a publication readiness report without opening the real deposit boundary.",
            },
        )
        .expect("record publication package");
        (context_packet, publication)
    }

    #[test]
    fn workspace_external_registry_staging_records_test_ready_artifacts_with_same_identity() {
        let temp_root = env::temp_dir().join(format!(
            "beagle-b215-test-{}",
            Utc::now()
                .timestamp_nanos_opt()
                .unwrap_or_else(|| Utc::now().timestamp_micros() * 1000)
        ));
        fs::create_dir_all(&temp_root).expect("create temp dir");
        let cfg = test_config(&temp_root);
        let (context_packet, publication) = seed_upstream(&temp_root, &cfg);

        let response = record_workspace_external_registry_staging(
            &temp_root,
            &cfg,
            "beagle-darwin-hpc-governance",
            context_packet,
            WorkspaceExternalRegistryStagingRequest {
                source_subagent_id: "manuscript",
                requested_tool_id: Some("claude-code"),
                staging_goal:
                    "Prepare the canonical campaign package for external test staging without performing real registry calls.",
                summary:
                    "Freeze a dry-run external staging package for DataCite/Crossref-facing workflows.",
                dry_run_notes:
                    "Keep registry calls disabled while making the transport boundary explicit.",
            },
        )
        .expect("record external staging");

        assert_eq!(response.package.workstream_id, publication.package.workstream_id);
        assert_eq!(response.package.workspace_id, publication.package.workspace_id);
        assert_eq!(response.package.session_id, publication.package.session_id);
        assert_eq!(response.package.source_subagent_id, "manuscript");
        assert_eq!(
            response.external_staging_readiness_report.report_profile,
            "external-registry-dry-run-readiness-v1"
        );
        assert_eq!(
            response.datacite_test_staging_payload.api_base_url,
            DATACITE_TEST_API_BASE
        );
        assert_eq!(
            response.crossref_dry_run_bundle.submission_mode,
            "dry-run-no-submit"
        );
        assert_eq!(
            response.package.technical_external_staging_state,
            "ready-for-external-test-staging"
        );
        assert_eq!(
            response.package.readiness_state,
            "claim-linked-human-eval-pending"
        );
    }

    #[test]
    fn workspace_external_registry_staging_latest_survives_restart_shaping() {
        let temp_root = env::temp_dir().join(format!(
            "beagle-b215-restart-{}",
            Utc::now()
                .timestamp_nanos_opt()
                .unwrap_or_else(|| Utc::now().timestamp_micros() * 1000)
        ));
        fs::create_dir_all(&temp_root).expect("create temp dir");
        let cfg = test_config(&temp_root);
        let (context_packet, _publication) = seed_upstream(&temp_root, &cfg);

        let recorded = record_workspace_external_registry_staging(
            &temp_root,
            &cfg,
            "beagle-darwin-hpc-governance",
            context_packet.clone(),
            WorkspaceExternalRegistryStagingRequest {
                source_subagent_id: "manuscript",
                requested_tool_id: Some("claude-code"),
                staging_goal:
                    "Prepare the canonical campaign package for external test staging without performing real registry calls.",
                summary:
                    "Freeze a dry-run external staging package for DataCite/Crossref-facing workflows.",
                dry_run_notes:
                    "Keep registry calls disabled while making the transport boundary explicit.",
            },
        )
        .expect("record external staging");

        let shaped = read_workspace_external_registry_staging(
            &temp_root,
            &cfg,
            "beagle-darwin-hpc-governance",
            context_packet,
        )
        .expect("shape external staging")
        .expect("external staging present");

        assert_eq!(shaped.package.package_id, recorded.package.package_id);
        assert_eq!(
            shaped.package.upstream_publication_package_id,
            recorded.package.upstream_publication_package_id
        );
        assert_eq!(
            shaped.datacite_test_staging_payload.doi_candidate,
            recorded.datacite_test_staging_payload.doi_candidate
        );
        assert_eq!(
            shaped.crossref_dry_run_bundle.bundle_id,
            recorded.crossref_dry_run_bundle.bundle_id
        );
        assert!(shaped.continuity.restart_recovered_session);
    }
}
