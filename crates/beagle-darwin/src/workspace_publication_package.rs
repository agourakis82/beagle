use crate::workspace_scholarly_release::{
    read_workspace_scholarly_release, CrossrefArticleStub, DataCiteReadyMetadata,
    ScholarlyReleasePayloadItem, WorkspaceScholarlyReleaseResponse,
};
use crate::workspace_subagents::{WorkspaceSubAgentRole, WorkspaceSubAgentsPlane};
use crate::{
    CampaignClaimsResponse, EvidencePack, EvidencePackCitation, EvidencePackProvenance,
    ProgramContextPacket, ReviewBundle, WorkstreamContextPacket, WorkstreamContextPacketResponse,
};
use anyhow::{anyhow, Context};
use beagle_config::BeagleConfig;
use chrono::{DateTime, Utc};
use serde::{Deserialize, Serialize};
use serde_json::{json, Value};
use std::fs;
use std::path::{Path, PathBuf};

const WORKSPACE_PUBLICATION_PACKAGE_PHASE: &str = "B21.4";
const WORKSPACE_PUBLICATION_PACKAGE_VERSION: &str =
    "beagle-deposit-ready-publication-package-v1";
const WORKSPACE_PUBLICATION_PACKAGE_KIND: &str = "workspace-publication-package";
const MANUSCRIPT_SUBAGENT_ID: &str = "manuscript";
const PUBLICATION_READINESS_PROFILE: &str = "deposit-ready-publication-readiness-v1";
const DATACITE_DEPOSIT_PROFILE: &str = "datacite-rest-api-draft-staging-v1";
const CROSSREF_DEPOSIT_PROFILE: &str = "crossref-journal-article-deposit-bundle-v1";
const DOI_PREFIX_PLACEHOLDER: &str = "10.00000";

#[derive(Debug, Clone, Serialize, Deserialize)]
struct WorkspacePublicationPackageRecord {
    package_version: String,
    package_id: String,
    workstream_id: String,
    workspace_id: String,
    session_id: String,
    source_subagent_id: String,
    source_role_tag: String,
    requested_tool_id: Option<String>,
    publication_goal: String,
    summary: String,
    staging_notes: String,
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
pub struct WorkspacePublicationPackageRequest<'a> {
    pub source_subagent_id: &'a str,
    pub requested_tool_id: Option<&'a str>,
    pub publication_goal: &'a str,
    pub summary: &'a str,
    pub staging_notes: &'a str,
}

#[derive(Debug, Clone, Serialize)]
pub struct WorkspacePublicationPackagePlane {
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
    pub publication_goal: String,
    pub summary: String,
    pub staging_notes: String,
    pub upstream_release_id: String,
    pub upstream_assembly_id: String,
    pub upstream_manuscript_handoff_id: String,
    pub upstream_subagent_handoff_id: String,
    pub workspace_publication_package_path: String,
    pub workspace_scholarly_release_ref: String,
    pub publication_readiness_report_ref: String,
    pub datacite_deposit_payload_ref: String,
    pub crossref_deposit_bundle_ref: String,
    pub publication_package_bundle_ref: String,
    pub program_id: String,
    pub campaign_id: String,
    pub manuscript_pack_id: String,
    pub jats_pack_id: String,
    pub readiness_state: String,
    pub section_profile: String,
    pub article_type: String,
    pub technical_deposit_state: String,
    pub managed_attach_state: String,
    pub stable_attach_alias: String,
    pub note: String,
}

#[derive(Debug, Clone, Serialize)]
pub struct WorkspacePublicationPackageContinuity {
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
    pub technical_ready_for_staging: bool,
    pub findable_publication_allowed: bool,
    pub readiness_state: String,
    pub source_env_file: String,
    pub source_workspace_folder: String,
    pub source_shell_entry_hint: String,
}

#[derive(Debug, Clone, Serialize)]
pub struct PublicationReadinessCheck {
    pub check_id: String,
    pub dimension: String,
    pub description: String,
    pub status: String,
    pub detail: String,
}

#[derive(Debug, Clone, Serialize)]
pub struct PublicationReadinessReport {
    pub report_profile: String,
    pub checked_at: DateTime<Utc>,
    pub technical_deposit_state: String,
    pub epistemic_readiness_state: String,
    pub real_deposit_performed: bool,
    pub doi_staging_allowed: bool,
    pub crossref_staging_allowed: bool,
    pub findable_publication_allowed: bool,
    pub technical_blocker_count: usize,
    pub epistemic_blocker_count: usize,
    pub warning_count: usize,
    pub checks: Vec<PublicationReadinessCheck>,
    pub note: String,
}

#[derive(Debug, Clone, Serialize)]
pub struct DataCiteDepositPayload {
    pub deposit_profile: String,
    pub api_shape_version: String,
    pub target_state: String,
    pub real_deposit_performed: bool,
    pub prefix_placeholder: String,
    pub doi_candidate: String,
    pub payload: Value,
    pub readiness_state: String,
    pub note: String,
}

#[derive(Debug, Clone, Serialize)]
pub struct CrossrefDepositBundle {
    pub export_profile: String,
    pub bundle_id: String,
    pub submission_mode: String,
    pub real_deposit_performed: bool,
    pub batch_id: String,
    pub journal_title: String,
    pub article_title: String,
    pub related_item_count: usize,
    pub readiness_state: String,
    pub xml_bundle: String,
    pub note: String,
}

#[derive(Debug, Clone, Serialize)]
pub struct PublicationPackageBundle {
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
    pub technical_deposit_state: String,
    pub publication_readiness_report_ref: String,
    pub scholarly_release_ref: String,
    pub jats_qa_report_ref: String,
    pub ro_crate_export_ref: String,
    pub datacite_metadata_ref: String,
    pub datacite_deposit_payload_ref: String,
    pub crossref_article_stub_ref: String,
    pub crossref_deposit_bundle_ref: String,
    pub payload_manifest: Vec<ScholarlyReleasePayloadItem>,
    pub provenance: EvidencePackProvenance,
    pub citation: EvidencePackCitation,
    pub note: String,
}

#[derive(Debug, Clone, Serialize)]
pub struct WorkspacePublicationPackageResponse {
    pub status: String,
    pub phase: String,
    pub package: WorkspacePublicationPackagePlane,
    pub continuity: WorkspacePublicationPackageContinuity,
    pub source_role: WorkspaceSubAgentRole,
    pub subagents: WorkspaceSubAgentsPlane,
    pub context_packet: WorkstreamContextPacket,
    pub program_context: ProgramContextPacket,
    pub evidence_pack: EvidencePack,
    pub claims: CampaignClaimsResponse,
    pub review_bundle: ReviewBundle,
    pub scholarly_release: WorkspaceScholarlyReleaseResponse,
    pub publication_readiness_report: PublicationReadinessReport,
    pub datacite_deposit_payload: DataCiteDepositPayload,
    pub crossref_deposit_bundle: CrossrefDepositBundle,
    pub publication_package_bundle: PublicationPackageBundle,
}

pub fn record_workspace_publication_package(
    data_dir: &Path,
    cfg: &BeagleConfig,
    workstream_id: &str,
    context_packet: WorkstreamContextPacketResponse,
    request: WorkspacePublicationPackageRequest<'_>,
) -> anyhow::Result<WorkspacePublicationPackageResponse> {
    let upstream =
        read_workspace_scholarly_release(data_dir, cfg, workstream_id, context_packet)?.ok_or_else(
            || anyhow!("a workspace scholarly release is required before publication packaging"),
        )?;

    let source_subagent_id = normalize_selector(request.source_subagent_id);
    if source_subagent_id != MANUSCRIPT_SUBAGENT_ID {
        return Err(anyhow!(
            "publication packaging must originate from sub-agent '{}'",
            MANUSCRIPT_SUBAGENT_ID
        ));
    }
    if upstream.release.source_subagent_id != source_subagent_id {
        return Err(anyhow!(
            "latest scholarly release must originate from '{}' before publication packaging",
            source_subagent_id
        ));
    }

    let requested_tool_id = request
        .requested_tool_id
        .map(normalize_selector)
        .filter(|value| !value.is_empty())
        .or_else(|| Some("claude-code".to_string()));
    let publication_goal = normalize_sentence(request.publication_goal);
    let summary = normalize_sentence(request.summary);
    let staging_notes = normalize_sentence(request.staging_notes);
    if publication_goal.is_empty() {
        return Err(anyhow!("publication package goal must not be empty"));
    }
    if summary.is_empty() {
        return Err(anyhow!("publication package summary must not be empty"));
    }
    if staging_notes.is_empty() {
        return Err(anyhow!("publication package staging notes must not be empty"));
    }

    let record = WorkspacePublicationPackageRecord {
        package_version: WORKSPACE_PUBLICATION_PACKAGE_VERSION.to_string(),
        package_id: format!(
            "{}-publication-package-{}",
            sanitize_component(&upstream.release.session_id),
            Utc::now().timestamp_millis()
        ),
        workstream_id: upstream.release.workstream_id.clone(),
        workspace_id: upstream.release.workspace_id.clone(),
        session_id: upstream.release.session_id.clone(),
        source_subagent_id: upstream.release.source_subagent_id.clone(),
        source_role_tag: upstream.release.source_role_tag.clone(),
        requested_tool_id,
        publication_goal,
        summary,
        staging_notes,
        upstream_release_id: upstream.release.release_id.clone(),
        upstream_assembly_id: upstream.release.upstream_assembly_id.clone(),
        upstream_manuscript_handoff_id: upstream.release.upstream_manuscript_handoff_id.clone(),
        upstream_subagent_handoff_id: upstream.release.upstream_subagent_handoff_id.clone(),
        recorded_at: Utc::now(),
        program_id: upstream.release.program_id.clone(),
        campaign_id: upstream.release.campaign_id.clone(),
        manuscript_pack_id: upstream.release.manuscript_pack_id.clone(),
        jats_pack_id: upstream.release.jats_pack_id.clone(),
        managed_attach_state: upstream.release.managed_attach_state.clone(),
        stable_attach_alias: upstream.release.stable_attach_alias.clone(),
    };
    write_publication_package_record(data_dir, &record.workspace_id, &record)?;

    response_from_state(&upstream, record)
}

pub fn read_workspace_publication_package(
    data_dir: &Path,
    cfg: &BeagleConfig,
    workstream_id: &str,
    context_packet: WorkstreamContextPacketResponse,
) -> anyhow::Result<Option<WorkspacePublicationPackageResponse>> {
    let Some(record) = read_publication_package_record(data_dir, &context_packet.packet.workspace_id)?
    else {
        return Ok(None);
    };
    let upstream = read_workspace_scholarly_release(data_dir, cfg, workstream_id, context_packet)?
        .ok_or_else(|| {
            anyhow!("workspace scholarly release is unavailable for publication package shaping")
        })?;
    response_from_state(&upstream, record).map(Some)
}

fn response_from_state(
    upstream: &WorkspaceScholarlyReleaseResponse,
    record: WorkspacePublicationPackageRecord,
) -> anyhow::Result<WorkspacePublicationPackageResponse> {
    let payload_manifest = build_publication_payload_manifest(&record, upstream);
    let publication_readiness_report = build_publication_readiness_report(upstream);
    let datacite_deposit_payload =
        build_datacite_deposit_payload(&record, &upstream.datacite_metadata, upstream);
    let crossref_deposit_bundle =
        build_crossref_deposit_bundle(&record, &upstream.crossref_article_stub);
    let publication_package_bundle = build_publication_package_bundle(
        &record,
        upstream,
        &payload_manifest,
        &publication_readiness_report,
    );

    let package = WorkspacePublicationPackagePlane {
        package_version: WORKSPACE_PUBLICATION_PACKAGE_VERSION.to_string(),
        package_kind: WORKSPACE_PUBLICATION_PACKAGE_KIND.to_string(),
        package_id: record.package_id.clone(),
        workstream_id: record.workstream_id.clone(),
        workspace_id: record.workspace_id.clone(),
        session_id: record.session_id.clone(),
        package_state: "deposit-ready-staged".to_string(),
        recorded_at: record.recorded_at,
        source_subagent_id: record.source_subagent_id.clone(),
        source_role_tag: record.source_role_tag.clone(),
        requested_tool_id: record.requested_tool_id.clone(),
        publication_goal: record.publication_goal.clone(),
        summary: record.summary.clone(),
        staging_notes: record.staging_notes.clone(),
        upstream_release_id: record.upstream_release_id.clone(),
        upstream_assembly_id: record.upstream_assembly_id.clone(),
        upstream_manuscript_handoff_id: record.upstream_manuscript_handoff_id.clone(),
        upstream_subagent_handoff_id: record.upstream_subagent_handoff_id.clone(),
        workspace_publication_package_path: format!(
            "/api/darwin/workstreams/{}/workspace-publication-package",
            record.workstream_id
        ),
        workspace_scholarly_release_ref: format!(
            "workspace-scholarly-release:{}",
            record.upstream_release_id
        ),
        publication_readiness_report_ref: format!(
            "workspace-publication-package:{}:publication-readiness-report",
            record.package_id
        ),
        datacite_deposit_payload_ref: format!(
            "workspace-publication-package:{}:datacite-deposit-payload",
            record.package_id
        ),
        crossref_deposit_bundle_ref: format!(
            "workspace-publication-package:{}:crossref-deposit-bundle",
            record.package_id
        ),
        publication_package_bundle_ref: format!(
            "workspace-publication-package:{}:publication-package-bundle",
            record.package_id
        ),
        program_id: record.program_id.clone(),
        campaign_id: record.campaign_id.clone(),
        manuscript_pack_id: record.manuscript_pack_id.clone(),
        jats_pack_id: record.jats_pack_id.clone(),
        readiness_state: upstream.release.readiness_state.clone(),
        section_profile: upstream.release.section_profile.clone(),
        article_type: upstream.release.article_type.clone(),
        technical_deposit_state: publication_readiness_report.technical_deposit_state.clone(),
        managed_attach_state: record.managed_attach_state.clone(),
        stable_attach_alias: record.stable_attach_alias.clone(),
        note: "The publication package stages a standards-grade scholarly release for future DataCite/Crossref deposit without performing a real deposit or hiding epistemic readiness gaps.".to_string(),
    };
    let continuity = WorkspacePublicationPackageContinuity {
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
        qa_state: upstream.jats_qa_report.qa_state.clone(),
        qa_warning_count: upstream.jats_qa_report.warning_count,
        qa_failure_count: upstream.jats_qa_report.failure_count,
        technical_blocker_count: publication_readiness_report.technical_blocker_count,
        epistemic_blocker_count: publication_readiness_report.epistemic_blocker_count,
        technical_ready_for_staging: publication_readiness_report.doi_staging_allowed
            && publication_readiness_report.crossref_staging_allowed,
        findable_publication_allowed: publication_readiness_report.findable_publication_allowed,
        readiness_state: upstream.release.readiness_state.clone(),
        source_env_file: upstream.source_role.env_file.clone(),
        source_workspace_folder: upstream.source_role.workspace_folder.clone(),
        source_shell_entry_hint: upstream.source_role.shell_entry_hint.clone(),
    };

    Ok(WorkspacePublicationPackageResponse {
        status: "ok".to_string(),
        phase: WORKSPACE_PUBLICATION_PACKAGE_PHASE.to_string(),
        package,
        continuity,
        source_role: upstream.source_role.clone(),
        subagents: upstream.subagents.clone(),
        context_packet: upstream.context_packet.clone(),
        program_context: upstream.program_context.clone(),
        evidence_pack: upstream.evidence_pack.clone(),
        claims: upstream.claims.clone(),
        review_bundle: upstream.review_bundle.clone(),
        scholarly_release: upstream.clone(),
        publication_readiness_report,
        datacite_deposit_payload,
        crossref_deposit_bundle,
        publication_package_bundle,
    })
}

fn build_publication_payload_manifest(
    record: &WorkspacePublicationPackageRecord,
    upstream: &WorkspaceScholarlyReleaseResponse,
) -> Vec<ScholarlyReleasePayloadItem> {
    let mut payloads = upstream.release_bundle.payload_manifest.clone();
    payloads.push(ScholarlyReleasePayloadItem {
        logical_path: "reports/publication-readiness-report.json".to_string(),
        payload_kind: "publication-readiness-report".to_string(),
        media_type: "application/json".to_string(),
        reference: format!(
            "workspace-publication-package:{}:publication-readiness-report",
            record.package_id
        ),
    });
    payloads.push(ScholarlyReleasePayloadItem {
        logical_path: "exports/datacite-deposit-payload.json".to_string(),
        payload_kind: "datacite-deposit-payload".to_string(),
        media_type: "application/json".to_string(),
        reference: format!(
            "workspace-publication-package:{}:datacite-deposit-payload",
            record.package_id
        ),
    });
    payloads.push(ScholarlyReleasePayloadItem {
        logical_path: "exports/crossref-deposit-bundle.json".to_string(),
        payload_kind: "crossref-deposit-bundle".to_string(),
        media_type: "application/json".to_string(),
        reference: format!(
            "workspace-publication-package:{}:crossref-deposit-bundle",
            record.package_id
        ),
    });
    payloads.push(ScholarlyReleasePayloadItem {
        logical_path: "release/deposit-ready-publication-package.json".to_string(),
        payload_kind: "deposit-ready-publication-package".to_string(),
        media_type: "application/json".to_string(),
        reference: format!(
            "workspace-publication-package:{}:publication-package-bundle",
            record.package_id
        ),
    });
    payloads.push(ScholarlyReleasePayloadItem {
        logical_path: "contracts/datacite-deposit-payload-schema.yaml".to_string(),
        payload_kind: "datacite-deposit-contract".to_string(),
        media_type: "text/yaml".to_string(),
        reference: "docs/darwin/hpc/contracts/datacite-deposit-payload-schema.yaml"
            .to_string(),
    });
    payloads.push(ScholarlyReleasePayloadItem {
        logical_path: "contracts/crossref-deposit-bundle-schema.yaml".to_string(),
        payload_kind: "crossref-deposit-contract".to_string(),
        media_type: "text/yaml".to_string(),
        reference: "docs/darwin/hpc/contracts/crossref-deposit-bundle-schema.yaml"
            .to_string(),
    });
    payloads.push(ScholarlyReleasePayloadItem {
        logical_path: "contracts/publication-readiness-report-schema.yaml".to_string(),
        payload_kind: "publication-readiness-contract".to_string(),
        media_type: "text/yaml".to_string(),
        reference: "docs/darwin/hpc/contracts/publication-readiness-report-schema.yaml"
            .to_string(),
    });
    payloads
}

fn build_publication_readiness_report(
    upstream: &WorkspaceScholarlyReleaseResponse,
) -> PublicationReadinessReport {
    let qa_pass = upstream.jats_qa_report.failure_count == 0
        && matches!(
            upstream.jats_qa_report.qa_state.as_str(),
            "pass" | "pass-with-warnings"
        );
    let ro_crate_present = !upstream.ro_crate_export.payload_manifest.is_empty();
    let datacite_present = !upstream.datacite_metadata.identifiers.is_empty()
        && !upstream.datacite_metadata.creators.is_empty()
        && !upstream.datacite_metadata.titles.is_empty();
    let crossref_present = upstream.crossref_article_stub.xml_stub.contains("<doi_batch")
        && upstream.crossref_article_stub.xml_stub.contains("<journal_article");
    let readiness_pending = upstream.release.readiness_state.contains("pending");

    let mut checks = vec![
        readiness_check(
            "jats-qa-passed",
            "technical",
            "JATS QA remains in a passing state for staging.",
            qa_pass,
            "expected pass or pass-with-warnings with zero failures",
        ),
        readiness_check(
            "ro-crate-present",
            "technical",
            "RO-Crate export is present for release packaging.",
            ro_crate_present,
            "expected RO-Crate payload manifest entries",
        ),
        readiness_check(
            "datacite-export-present",
            "technical",
            "DataCite-ready metadata is present for staging.",
            datacite_present,
            "expected identifiers, creators, and titles in DataCite metadata",
        ),
        readiness_check(
            "crossref-export-present",
            "technical",
            "Crossref-compatible article XML is present for staging.",
            crossref_present,
            "expected Crossref XML bundle with doi_batch and journal_article",
        ),
        PublicationReadinessCheck {
            check_id: "doi-prefix-still-placeholder".to_string(),
            dimension: "technical".to_string(),
            description:
                "The package still uses a placeholder DOI prefix because no real DOI deposit is performed in this phase.".to_string(),
            status: "warning".to_string(),
            detail: format!(
                "technical staging remains valid with prefix placeholder {}",
                DOI_PREFIX_PLACEHOLDER
            ),
        },
    ];

    checks.push(if readiness_pending {
        PublicationReadinessCheck {
            check_id: "human-eval-pending-explicit".to_string(),
            dimension: "epistemic".to_string(),
            description:
                "Human-eval pending remains explicit instead of being hidden at deposit staging time."
                    .to_string(),
            status: "blocked".to_string(),
            detail: format!(
                "findable publication is still blocked by readiness_state={}",
                upstream.release.readiness_state
            ),
        }
    } else {
        PublicationReadinessCheck {
            check_id: "human-eval-pending-explicit".to_string(),
            dimension: "epistemic".to_string(),
            description:
                "Human-eval pending remains explicit instead of being hidden at deposit staging time."
                    .to_string(),
            status: "pass".to_string(),
            detail: "no epistemic pending state is attached to this package".to_string(),
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
    let warning_count = checks
        .iter()
        .filter(|check| check.status == "warning")
        .count();
    let doi_staging_allowed = technical_blocker_count == 0;
    let crossref_staging_allowed = technical_blocker_count == 0;
    let technical_deposit_state = if technical_blocker_count == 0 {
        "ready-for-draft-deposit"
    } else {
        "blocked"
    };

    PublicationReadinessReport {
        report_profile: PUBLICATION_READINESS_PROFILE.to_string(),
        checked_at: Utc::now(),
        technical_deposit_state: technical_deposit_state.to_string(),
        epistemic_readiness_state: upstream.release.readiness_state.clone(),
        real_deposit_performed: false,
        doi_staging_allowed,
        crossref_staging_allowed,
        findable_publication_allowed: !readiness_pending && technical_blocker_count == 0,
        technical_blocker_count,
        epistemic_blocker_count,
        warning_count,
        checks,
        note: "The publication readiness report separates technical deposit staging from epistemic publication maturity so draft-ready packaging never hides human-eval gaps.".to_string(),
    }
}

fn readiness_check(
    check_id: &str,
    dimension: &str,
    description: &str,
    passed: bool,
    failure_detail: &str,
) -> PublicationReadinessCheck {
    PublicationReadinessCheck {
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

fn build_datacite_deposit_payload(
    record: &WorkspacePublicationPackageRecord,
    datacite_metadata: &DataCiteReadyMetadata,
    upstream: &WorkspaceScholarlyReleaseResponse,
) -> DataCiteDepositPayload {
    let doi_candidate = format!(
        "{}/{}",
        DOI_PREFIX_PLACEHOLDER,
        sanitize_component(&record.package_id)
    );
    let payload = json!({
        "data": {
            "type": "dois",
            "attributes": {
                "event": "draft",
                "doi": doi_candidate,
                "prefix": DOI_PREFIX_PLACEHOLDER,
                "titles": datacite_metadata
                    .titles
                    .iter()
                    .map(|title| json!({ "title": title.title }))
                    .collect::<Vec<_>>(),
                "creators": datacite_metadata
                    .creators
                    .iter()
                    .map(|creator| json!({ "name": creator.name }))
                    .collect::<Vec<_>>(),
                "publisher": datacite_metadata.publisher,
                "publicationYear": datacite_metadata.publication_year,
                "types": {
                    "resourceTypeGeneral": datacite_metadata.types.resource_type_general,
                    "resourceType": datacite_metadata.types.resource_type,
                },
                "subjects": datacite_metadata
                    .subjects
                    .iter()
                    .map(|subject| json!({ "subject": subject.subject }))
                    .collect::<Vec<_>>(),
                "descriptions": datacite_metadata
                    .descriptions
                    .iter()
                    .map(|description| {
                        json!({
                            "description": description.description,
                            "descriptionType": description.description_type,
                        })
                    })
                    .collect::<Vec<_>>(),
                "language": datacite_metadata.language,
                "schemaVersion": "http://datacite.org/schema/kernel-4",
                "url": format!(
                    "https://beagle.invalid/{}/{}",
                    sanitize_component(&record.campaign_id),
                    sanitize_component(&record.package_id)
                ),
                "relatedIdentifiers": datacite_metadata
                    .related_identifiers
                    .iter()
                    .map(|identifier| {
                        json!({
                            "relationType": identifier.relation_type,
                            "relatedIdentifierType": identifier.identifier_type,
                            "relatedIdentifier": identifier.value,
                        })
                    })
                    .collect::<Vec<_>>(),
            },
        },
        "meta": {
            "packageId": record.package_id,
            "upstreamReleaseId": record.upstream_release_id,
            "realDepositPerformed": false,
            "epistemicReadinessState": upstream.release.readiness_state,
        }
    });

    DataCiteDepositPayload {
        deposit_profile: DATACITE_DEPOSIT_PROFILE.to_string(),
        api_shape_version: "datacite-rest-api-doi-draft".to_string(),
        target_state: "draft".to_string(),
        real_deposit_performed: false,
        prefix_placeholder: DOI_PREFIX_PLACEHOLDER.to_string(),
        doi_candidate,
        payload,
        readiness_state: upstream.release.readiness_state.clone(),
        note: "The DataCite deposit payload is technically ready for draft staging, but it intentionally keeps a placeholder DOI prefix until a real deposit boundary is opened.".to_string(),
    }
}

fn build_crossref_deposit_bundle(
    record: &WorkspacePublicationPackageRecord,
    crossref_stub: &CrossrefArticleStub,
) -> CrossrefDepositBundle {
    CrossrefDepositBundle {
        export_profile: CROSSREF_DEPOSIT_PROFILE.to_string(),
        bundle_id: format!("{}-crossref-deposit-bundle", record.package_id),
        submission_mode: "deposit-ready-no-submit".to_string(),
        real_deposit_performed: false,
        batch_id: format!("{}-crossref-batch", record.package_id),
        journal_title: crossref_stub.journal_title.clone(),
        article_title: crossref_stub.article_title.clone(),
        related_item_count: crossref_stub.related_items.len(),
        readiness_state: crossref_stub.readiness_state.clone(),
        xml_bundle: crossref_stub.xml_stub.clone(),
        note: "The Crossref bundle is deposit-ready XML for a journal/article deposit flow, but no submission is performed in this phase.".to_string(),
    }
}

fn build_publication_package_bundle(
    record: &WorkspacePublicationPackageRecord,
    upstream: &WorkspaceScholarlyReleaseResponse,
    payload_manifest: &[ScholarlyReleasePayloadItem],
    readiness_report: &PublicationReadinessReport,
) -> PublicationPackageBundle {
    PublicationPackageBundle {
        bundle_version: WORKSPACE_PUBLICATION_PACKAGE_VERSION.to_string(),
        bundle_kind: "deposit-ready-publication-package".to_string(),
        bundle_id: format!("{}-publication-package-bundle", record.package_id),
        program_id: record.program_id.clone(),
        campaign_id: record.campaign_id.clone(),
        workstream_id: record.workstream_id.clone(),
        workspace_id: record.workspace_id.clone(),
        session_id: record.session_id.clone(),
        manuscript_pack_id: record.manuscript_pack_id.clone(),
        jats_pack_id: record.jats_pack_id.clone(),
        readiness_state: upstream.release.readiness_state.clone(),
        technical_deposit_state: readiness_report.technical_deposit_state.clone(),
        publication_readiness_report_ref: format!(
            "workspace-publication-package:{}:publication-readiness-report",
            record.package_id
        ),
        scholarly_release_ref: format!("workspace-scholarly-release:{}", record.upstream_release_id),
        jats_qa_report_ref: upstream.release.jats_qa_report_ref.clone(),
        ro_crate_export_ref: upstream.release.ro_crate_export_ref.clone(),
        datacite_metadata_ref: upstream.release.datacite_metadata_ref.clone(),
        datacite_deposit_payload_ref: format!(
            "workspace-publication-package:{}:datacite-deposit-payload",
            record.package_id
        ),
        crossref_article_stub_ref: upstream.release.crossref_article_stub_ref.clone(),
        crossref_deposit_bundle_ref: format!(
            "workspace-publication-package:{}:crossref-deposit-bundle",
            record.package_id
        ),
        payload_manifest: payload_manifest.to_vec(),
        provenance: upstream.release_bundle.provenance.clone(),
        citation: upstream.release_bundle.citation.clone(),
        note: "The deposit-ready publication package keeps the release bundle intact while adding staged deposit artifacts and an explicit readiness report.".to_string(),
    }
}

fn write_publication_package_record(
    data_dir: &Path,
    workspace_id: &str,
    record: &WorkspacePublicationPackageRecord,
) -> anyhow::Result<()> {
    let path = publication_package_record_path(data_dir, workspace_id);
    if let Some(parent) = path.parent() {
        fs::create_dir_all(parent).with_context(|| {
            format!("create publication package directory {}", parent.display())
        })?;
    }
    let payload = serde_json::to_vec_pretty(record)
        .context("serialize workspace publication package record")?;
    fs::write(&path, payload)
        .with_context(|| format!("write publication package record {}", path.display()))?;
    Ok(())
}

fn read_publication_package_record(
    data_dir: &Path,
    workspace_id: &str,
) -> anyhow::Result<Option<WorkspacePublicationPackageRecord>> {
    let path = publication_package_record_path(data_dir, workspace_id);
    if !path.exists() {
        return Ok(None);
    }
    let bytes = fs::read(&path)
        .with_context(|| format!("read publication package record {}", path.display()))?;
    let record = serde_json::from_slice(&bytes)
        .with_context(|| format!("parse publication package record {}", path.display()))?;
    Ok(Some(record))
}

fn publication_package_record_path(data_dir: &Path, workspace_id: &str) -> PathBuf {
    workspace_publication_package_dir(data_dir).join(format!(
        "{}.json",
        sanitize_component(workspace_id)
    ))
}

fn workspace_publication_package_dir(data_dir: &Path) -> PathBuf {
    crate::workspace_plane::workspace_plane_dir(data_dir).join("publication-packages")
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
    use crate::workspace_scholarly_release::{
        record_workspace_scholarly_release, WorkspaceScholarlyReleaseRequest,
    };
    use crate::workspace_subagent_handoff::{
        record_workspace_subagent_handoff, WorkspaceSubAgentHandoffRequest,
        WorkspaceSubAgentHandoffResponse,
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
                    last_handoff: Some(
                        "resume from canonical Beagle workspace state".to_string(),
                    ),
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
                        source_phase: Some("B21.1".to_string()),
                        source_run_id: Some("b211-manuscript-loop".to_string()),
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
                    snippet: "Stage the same scholarly release for future deposit without performing a real DOI or Crossref submission.".to_string(),
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

    fn temp_data_dir(name: &str) -> PathBuf {
        let path = env::temp_dir().join(format!(
            "beagle-{}-{}",
            name,
            Utc::now()
                .timestamp_nanos_opt()
                .unwrap_or_else(|| Utc::now().timestamp_micros() * 1000)
        ));
        fs::create_dir_all(&path).expect("create temp data dir");
        path
    }

    fn seed_workspace_session(data_dir: &Path, cfg: &BeagleConfig) {
        let mut state = WorkspaceSessionState::new(
            cfg,
            "beagle-cluster-pilot".to_string(),
            Some("ws-cluster-workspace-habitat".to_string()),
        );
        state.last_handoff = Some("resume from canonical Beagle workspace state".to_string());
        write_workspace_session(data_dir, &state).expect("seed workspace session");
    }

    fn seed_scholarly_release(
        data_dir: &Path,
        cfg: &BeagleConfig,
    ) -> WorkspaceScholarlyReleaseResponse {
        let _upstream: WorkspaceSubAgentHandoffResponse = record_workspace_subagent_handoff(
            data_dir,
            cfg,
            "beagle-darwin-hpc-governance",
            packet(),
            WorkspaceSubAgentHandoffRequest {
                source_subagent_id: "core",
                target_subagent_id: "experiments",
                requested_work_mode: Some("analysis"),
                requested_tool_id: Some("claude-code"),
                intent: "analysis",
                summary: "Carry the canonical session into bounded experiments review.",
            },
        )
        .expect("upstream handoff");

        let _handoff = record_workspace_manuscript_handoff(
            data_dir,
            cfg,
            "beagle-darwin-hpc-governance",
            packet(),
            WorkspaceManuscriptHandoffRequest {
                source_subagent_id: "experiments",
                requested_work_mode: Some("manuscript"),
                requested_tool_id: Some("claude-code"),
                intent: "manuscript",
                summary: "Shift the experiments interpretation into manuscript drafting.",
                manuscript_goal:
                    "Freeze a bounded manuscript-oriented packet for the active campaign.",
            },
        )
        .expect("manuscript handoff");

        let _assembly = record_workspace_manuscript_assembly(
            data_dir,
            cfg,
            "beagle-darwin-hpc-governance",
            packet(),
            WorkspaceManuscriptAssemblyRequest {
                source_subagent_id: "manuscript",
                requested_tool_id: Some("claude-code"),
                section_profile: Some("jats-1.4-ready"),
                intent: "editorial-assembly",
                summary: "Freeze a JATS-ready manuscript artifact inside the manuscript subagent.",
                assembly_goal:
                    "Keep claims, evidence, provenance, and editorial sections explicitly linked.",
            },
        )
        .expect("manuscript assembly");

        record_workspace_scholarly_release(
            data_dir,
            cfg,
            "beagle-darwin-hpc-governance",
            packet(),
            WorkspaceScholarlyReleaseRequest {
                source_subagent_id: "manuscript",
                requested_tool_id: Some("claude-code"),
                release_goal: "Freeze a release-grade manuscript package with bounded standards crosswalks.",
                summary: "Turn the manuscript assembly into an externalizable release bundle without minting a new workspace session.",
                release_notes: "Keep JATS QA, RO-Crate, DataCite-ready metadata, and a Crossref-compatible stub explicit and restart-safe.",
            },
        )
        .expect("scholarly release")
    }

    #[test]
    fn workspace_publication_package_records_deposit_ready_artifacts_with_same_identity() {
        let data_dir = temp_data_dir("workspace-publication-package");
        let cfg = test_config(&data_dir);
        seed_workspace_session(&data_dir, &cfg);
        let upstream = seed_scholarly_release(&data_dir, &cfg);

        let response = record_workspace_publication_package(
            &data_dir,
            &cfg,
            "beagle-darwin-hpc-governance",
            packet(),
            WorkspacePublicationPackageRequest {
                source_subagent_id: "manuscript",
                requested_tool_id: Some("claude-code"),
                publication_goal: "Stage the scholarly release as a deposit-ready publication package without performing real DOI or Crossref submission.",
                summary: "Freeze technical deposit artifacts while keeping human-eval pending explicit.",
                staging_notes: "Prepare DataCite/Crossref staging artifacts and a publication readiness report, but keep deposit execution out of scope.",
            },
        )
        .expect("publication package");

        assert_eq!(response.phase, "B21.4");
        assert_eq!(response.package.workstream_id, "beagle-darwin-hpc-governance");
        assert_eq!(response.package.workspace_id, "beagle-cluster-pilot");
        assert_eq!(response.package.session_id, "ws-cluster-workspace-habitat");
        assert_eq!(response.package.source_subagent_id, "manuscript");
        assert_eq!(
            response.package.upstream_release_id,
            upstream.release.release_id
        );
        assert_eq!(
            response.publication_readiness_report.report_profile,
            "deposit-ready-publication-readiness-v1"
        );
        assert_eq!(
            response.datacite_deposit_payload.deposit_profile,
            "datacite-rest-api-draft-staging-v1"
        );
        assert_eq!(
            response.crossref_deposit_bundle.export_profile,
            "crossref-journal-article-deposit-bundle-v1"
        );
        assert_eq!(
            response.package.technical_deposit_state,
            "ready-for-draft-deposit"
        );
        assert!(response.datacite_deposit_payload.doi_candidate.starts_with("10.00000/"));
        assert!(response.crossref_deposit_bundle.xml_bundle.contains("<doi_batch"));
        assert!(!response.publication_readiness_report.findable_publication_allowed);
        assert_eq!(
            response.publication_package_bundle.readiness_state,
            response.package.readiness_state
        );
    }

    #[test]
    fn workspace_publication_package_latest_survives_restart_shaping() {
        let data_dir = temp_data_dir("workspace-publication-package-restart");
        let cfg = test_config(&data_dir);
        seed_workspace_session(&data_dir, &cfg);
        let upstream = seed_scholarly_release(&data_dir, &cfg);

        let recorded = record_workspace_publication_package(
            &data_dir,
            &cfg,
            "beagle-darwin-hpc-governance",
            packet(),
            WorkspacePublicationPackageRequest {
                source_subagent_id: "manuscript",
                requested_tool_id: Some("claude-code"),
                publication_goal: "Stage the scholarly release as a deposit-ready publication package without performing real DOI or Crossref submission.",
                summary: "Freeze technical deposit artifacts while keeping human-eval pending explicit.",
                staging_notes: "Prepare DataCite/Crossref staging artifacts and a publication readiness report, but keep deposit execution out of scope.",
            },
        )
        .expect("record publication package");

        let shaped = read_workspace_publication_package(
            &data_dir,
            &cfg,
            "beagle-darwin-hpc-governance",
            packet(),
        )
        .expect("read publication package")
        .expect("publication package present");

        assert_eq!(shaped.package.package_id, recorded.package.package_id);
        assert_eq!(shaped.package.upstream_release_id, upstream.release.release_id);
        assert_eq!(shaped.package.session_id, "ws-cluster-workspace-habitat");
        assert_eq!(shaped.source_role.subagent_id, "manuscript");
        assert_eq!(
            shaped.publication_package_bundle.bundle_id,
            recorded.publication_package_bundle.bundle_id
        );
        assert_eq!(
            shaped.context_packet.handoff.last_handoff,
            recorded.context_packet.handoff.last_handoff
        );
        assert_eq!(
            shaped.publication_readiness_report.technical_deposit_state,
            recorded.publication_readiness_report.technical_deposit_state
        );
    }
}
