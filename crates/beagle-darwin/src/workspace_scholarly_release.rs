use crate::workspace_manuscript_assembly::{
    read_workspace_manuscript_assembly, WorkspaceManuscriptAssemblyResponse,
};
use crate::workspace_subagents::{WorkspaceSubAgentRole, WorkspaceSubAgentsPlane};
use crate::{
    CampaignClaimsResponse, EvidencePack, EvidencePackCitation, EvidencePackProvenance,
    EvidencePackRelatedIdentifier, JatsManuscriptPack, ProgramContextPacket, ReviewBundle,
    WorkstreamContextPacket, WorkstreamContextPacketResponse,
};
use anyhow::{anyhow, Context};
use beagle_config::BeagleConfig;
use chrono::{DateTime, Utc};
use serde::{Deserialize, Serialize};
use serde_json::{json, Value};
use std::fs;
use std::path::{Path, PathBuf};

const WORKSPACE_SCHOLARLY_RELEASE_PHASE: &str = "B21.3";
const WORKSPACE_SCHOLARLY_RELEASE_VERSION: &str = "beagle-scholarly-release-pipeline-v1";
const WORKSPACE_SCHOLARLY_RELEASE_KIND: &str = "workspace-scholarly-release";
const MANUSCRIPT_SUBAGENT_ID: &str = "manuscript";
const JATS_QA_PROFILE: &str = "jats-1.4-bounded-qa-v1";
const RO_CRATE_EXPORT_PROFILE: &str = "ro-crate-1.2-release-bounded";
const RO_CRATE_CONTEXT: &str = "https://w3id.org/ro/crate/1.1/context";
const DATACITE_PROFILE: &str = "datacite-4.7-ready";
const CROSSREF_PROFILE: &str = "crossref-journal-article-stub-v1";
const SECTION_MAP_CONTRACT_REF: &str =
    "docs/darwin/hpc/contracts/manuscript-section-map.yaml";

#[derive(Debug, Clone, Serialize, Deserialize)]
struct WorkspaceScholarlyReleaseRecord {
    release_version: String,
    release_id: String,
    workstream_id: String,
    workspace_id: String,
    session_id: String,
    source_subagent_id: String,
    source_role_tag: String,
    requested_tool_id: Option<String>,
    release_goal: String,
    summary: String,
    release_notes: String,
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
pub struct WorkspaceScholarlyReleaseRequest<'a> {
    pub source_subagent_id: &'a str,
    pub requested_tool_id: Option<&'a str>,
    pub release_goal: &'a str,
    pub summary: &'a str,
    pub release_notes: &'a str,
}

#[derive(Debug, Clone, Serialize)]
pub struct WorkspaceScholarlyReleasePlane {
    pub release_version: String,
    pub release_kind: String,
    pub release_id: String,
    pub workstream_id: String,
    pub workspace_id: String,
    pub session_id: String,
    pub release_state: String,
    pub recorded_at: DateTime<Utc>,
    pub source_subagent_id: String,
    pub source_role_tag: String,
    pub requested_tool_id: Option<String>,
    pub release_goal: String,
    pub summary: String,
    pub release_notes: String,
    pub upstream_assembly_id: String,
    pub upstream_manuscript_handoff_id: String,
    pub upstream_subagent_handoff_id: String,
    pub workspace_scholarly_release_path: String,
    pub workspace_manuscript_assembly_ref: String,
    pub workspace_manuscript_handoff_ref: String,
    pub jats_qa_report_ref: String,
    pub ro_crate_export_ref: String,
    pub datacite_metadata_ref: String,
    pub crossref_article_stub_ref: String,
    pub release_bundle_ref: String,
    pub program_id: String,
    pub campaign_id: String,
    pub manuscript_pack_id: String,
    pub jats_pack_id: String,
    pub readiness_state: String,
    pub section_profile: String,
    pub article_type: String,
    pub managed_attach_state: String,
    pub stable_attach_alias: String,
    pub note: String,
}

#[derive(Debug, Clone, Serialize)]
pub struct WorkspaceScholarlyReleaseContinuity {
    pub handoff_present: bool,
    pub propagated_handoff: Option<String>,
    pub claim_count: usize,
    pub supported_claim_count: usize,
    pub result_ref_count: usize,
    pub memory_ref_count: usize,
    pub physio_ref_count: usize,
    pub review_payload_count: usize,
    pub jats_section_count: usize,
    pub jats_profile: String,
    pub jats_qa_status: String,
    pub qa_warning_count: usize,
    pub qa_failure_count: usize,
    pub ro_crate_payload_count: usize,
    pub datacite_related_identifier_count: usize,
    pub crossref_related_item_count: usize,
    pub crossref_has_abstract: bool,
    pub provenance_activity_count: usize,
    pub readiness_state: String,
    pub source_env_file: String,
    pub source_workspace_folder: String,
    pub source_shell_entry_hint: String,
}

#[derive(Debug, Clone, Serialize)]
pub struct JatsQaCheck {
    pub check_id: String,
    pub description: String,
    pub status: String,
    pub detail: String,
}

#[derive(Debug, Clone, Serialize)]
pub struct JatsQaReport {
    pub qa_profile: String,
    pub qa_state: String,
    pub checked_at: DateTime<Utc>,
    pub readiness_state: String,
    pub warning_count: usize,
    pub failure_count: usize,
    pub checks: Vec<JatsQaCheck>,
    pub note: String,
}

#[derive(Debug, Clone, Serialize)]
pub struct ScholarlyReleasePayloadItem {
    pub logical_path: String,
    pub payload_kind: String,
    pub media_type: String,
    pub reference: String,
}

#[derive(Debug, Clone, Serialize)]
pub struct ScholarlyRoCrateExport {
    pub export_profile: String,
    pub crate_file_name: String,
    pub root_entity_id: String,
    pub main_entity_id: String,
    pub upstream_review_bundle_ref: String,
    pub payload_manifest: Vec<ScholarlyReleasePayloadItem>,
    pub metadata: Value,
}

#[derive(Debug, Clone, Serialize)]
pub struct DataCiteCreator {
    pub name: String,
}

#[derive(Debug, Clone, Serialize)]
pub struct DataCiteIdentifier {
    pub identifier: String,
    pub identifier_type: String,
}

#[derive(Debug, Clone, Serialize)]
pub struct DataCiteTitle {
    pub title: String,
}

#[derive(Debug, Clone, Serialize)]
pub struct DataCiteType {
    pub resource_type_general: String,
    pub resource_type: String,
}

#[derive(Debug, Clone, Serialize)]
pub struct DataCiteDescription {
    pub description: String,
    pub description_type: String,
}

#[derive(Debug, Clone, Serialize)]
pub struct DataCiteSubject {
    pub subject: String,
}

#[derive(Debug, Clone, Serialize)]
pub struct DataCiteReadyMetadata {
    pub metadata_profile: String,
    pub identifiers: Vec<DataCiteIdentifier>,
    pub creators: Vec<DataCiteCreator>,
    pub titles: Vec<DataCiteTitle>,
    pub publisher: String,
    pub publication_year: i32,
    pub types: DataCiteType,
    pub version: String,
    pub subjects: Vec<DataCiteSubject>,
    pub descriptions: Vec<DataCiteDescription>,
    pub related_identifiers: Vec<EvidencePackRelatedIdentifier>,
    pub language: String,
    pub readiness_state: String,
    pub evidence_pack_ref: String,
    pub review_bundle_ref: String,
    pub jats_pack_ref: String,
}

#[derive(Debug, Clone, Serialize)]
pub struct CrossrefContributor {
    pub full_name: String,
    pub given_name: Option<String>,
    pub surname: String,
}

#[derive(Debug, Clone, Serialize)]
pub struct CrossrefArticleStub {
    pub export_profile: String,
    pub stub_id: String,
    pub journal_title: String,
    pub publisher_name: String,
    pub article_title: String,
    pub article_type: String,
    pub abstract_text: String,
    pub contributors: Vec<CrossrefContributor>,
    pub publication_year: i32,
    pub language: String,
    pub readiness_state: String,
    pub related_items: Vec<EvidencePackRelatedIdentifier>,
    pub xml_stub: String,
}

#[derive(Debug, Clone, Serialize)]
pub struct ScholarlyReleaseBundle {
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
    pub qa_report_ref: String,
    pub ro_crate_export_ref: String,
    pub datacite_metadata_ref: String,
    pub crossref_article_stub_ref: String,
    pub payload_manifest: Vec<ScholarlyReleasePayloadItem>,
    pub provenance: EvidencePackProvenance,
    pub citation: EvidencePackCitation,
    pub note: String,
}

#[derive(Debug, Clone, Serialize)]
pub struct WorkspaceScholarlyReleaseResponse {
    pub status: String,
    pub phase: String,
    pub release: WorkspaceScholarlyReleasePlane,
    pub continuity: WorkspaceScholarlyReleaseContinuity,
    pub source_role: WorkspaceSubAgentRole,
    pub subagents: WorkspaceSubAgentsPlane,
    pub context_packet: WorkstreamContextPacket,
    pub program_context: ProgramContextPacket,
    pub evidence_pack: EvidencePack,
    pub claims: CampaignClaimsResponse,
    pub review_bundle: ReviewBundle,
    pub jats_pack: JatsManuscriptPack,
    pub jats_qa_report: JatsQaReport,
    pub ro_crate_export: ScholarlyRoCrateExport,
    pub datacite_metadata: DataCiteReadyMetadata,
    pub crossref_article_stub: CrossrefArticleStub,
    pub release_bundle: ScholarlyReleaseBundle,
}

pub fn record_workspace_scholarly_release(
    data_dir: &Path,
    cfg: &BeagleConfig,
    workstream_id: &str,
    context_packet: WorkstreamContextPacketResponse,
    request: WorkspaceScholarlyReleaseRequest<'_>,
) -> anyhow::Result<WorkspaceScholarlyReleaseResponse> {
    let upstream =
        read_workspace_manuscript_assembly(data_dir, cfg, workstream_id, context_packet)?
            .ok_or_else(|| {
                anyhow!("a workspace manuscript assembly is required before scholarly release")
            })?;

    let source_subagent_id = normalize_selector(request.source_subagent_id);
    if source_subagent_id != MANUSCRIPT_SUBAGENT_ID {
        return Err(anyhow!(
            "scholarly release must originate from sub-agent '{}'",
            MANUSCRIPT_SUBAGENT_ID
        ));
    }
    if upstream.assembly.source_subagent_id != source_subagent_id {
        return Err(anyhow!(
            "latest manuscript assembly must originate from '{}' before scholarly release",
            source_subagent_id
        ));
    }

    let requested_tool_id = request
        .requested_tool_id
        .map(normalize_selector)
        .filter(|value| !value.is_empty())
        .or_else(|| Some("claude-code".to_string()));
    let release_goal = normalize_sentence(request.release_goal);
    let summary = normalize_sentence(request.summary);
    let release_notes = normalize_sentence(request.release_notes);
    if release_goal.is_empty() {
        return Err(anyhow!("scholarly release goal must not be empty"));
    }
    if summary.is_empty() {
        return Err(anyhow!("scholarly release summary must not be empty"));
    }
    if release_notes.is_empty() {
        return Err(anyhow!("scholarly release notes must not be empty"));
    }

    let record = WorkspaceScholarlyReleaseRecord {
        release_version: WORKSPACE_SCHOLARLY_RELEASE_VERSION.to_string(),
        release_id: format!(
            "{}-scholarly-release-{}",
            sanitize_component(&upstream.assembly.session_id),
            Utc::now().timestamp_millis()
        ),
        workstream_id: upstream.assembly.workstream_id.clone(),
        workspace_id: upstream.assembly.workspace_id.clone(),
        session_id: upstream.assembly.session_id.clone(),
        source_subagent_id: upstream.assembly.source_subagent_id.clone(),
        source_role_tag: upstream.assembly.source_role_tag.clone(),
        requested_tool_id,
        release_goal,
        summary,
        release_notes,
        upstream_assembly_id: upstream.assembly.assembly_id.clone(),
        upstream_manuscript_handoff_id: upstream
            .assembly
            .upstream_manuscript_handoff_id
            .clone(),
        upstream_subagent_handoff_id: upstream.assembly.upstream_subagent_handoff_id.clone(),
        recorded_at: Utc::now(),
        program_id: upstream.assembly.program_id.clone(),
        campaign_id: upstream.assembly.campaign_id.clone(),
        manuscript_pack_id: upstream.manuscript_pack.pack_id.clone(),
        jats_pack_id: upstream.jats_pack.pack_id.clone(),
        managed_attach_state: upstream.assembly.managed_attach_state.clone(),
        stable_attach_alias: upstream.assembly.stable_attach_alias.clone(),
    };
    write_release_record(data_dir, &record.workspace_id, &record)?;

    response_from_state(&upstream, record)
}

pub fn read_workspace_scholarly_release(
    data_dir: &Path,
    cfg: &BeagleConfig,
    workstream_id: &str,
    context_packet: WorkstreamContextPacketResponse,
) -> anyhow::Result<Option<WorkspaceScholarlyReleaseResponse>> {
    let Some(record) = read_release_record(data_dir, &context_packet.packet.workspace_id)? else {
        return Ok(None);
    };
    let upstream = read_workspace_manuscript_assembly(data_dir, cfg, workstream_id, context_packet)?
        .ok_or_else(|| anyhow!("workspace manuscript assembly is unavailable for scholarly release shaping"))?;

    response_from_state(&upstream, record).map(Some)
}

fn response_from_state(
    upstream: &WorkspaceManuscriptAssemblyResponse,
    record: WorkspaceScholarlyReleaseRecord,
) -> anyhow::Result<WorkspaceScholarlyReleaseResponse> {
    let payload_manifest = build_release_payload_manifest(
        &record,
        &upstream.evidence_pack,
        &upstream.review_bundle,
        &upstream.jats_pack,
    );
    let jats_qa_report = build_jats_qa_report(&upstream.jats_pack, &upstream.review_bundle);
    let datacite_metadata = build_datacite_ready_metadata(&record, upstream);
    let crossref_article_stub =
        build_crossref_article_stub(&record, upstream, &datacite_metadata);
    let ro_crate_export = build_ro_crate_export(
        &record,
        upstream,
        &payload_manifest,
        &jats_qa_report,
        &datacite_metadata,
        &crossref_article_stub,
    );
    let release_bundle = build_release_bundle(
        &record,
        upstream,
        &payload_manifest,
        &jats_qa_report,
        &ro_crate_export,
        &datacite_metadata,
        &crossref_article_stub,
    );

    let release = WorkspaceScholarlyReleasePlane {
        release_version: WORKSPACE_SCHOLARLY_RELEASE_VERSION.to_string(),
        release_kind: WORKSPACE_SCHOLARLY_RELEASE_KIND.to_string(),
        release_id: record.release_id.clone(),
        workstream_id: record.workstream_id.clone(),
        workspace_id: record.workspace_id.clone(),
        session_id: record.session_id.clone(),
        release_state: "release-bundle-assembled".to_string(),
        recorded_at: record.recorded_at,
        source_subagent_id: record.source_subagent_id.clone(),
        source_role_tag: record.source_role_tag.clone(),
        requested_tool_id: record.requested_tool_id.clone(),
        release_goal: record.release_goal.clone(),
        summary: record.summary.clone(),
        release_notes: record.release_notes.clone(),
        upstream_assembly_id: record.upstream_assembly_id.clone(),
        upstream_manuscript_handoff_id: record.upstream_manuscript_handoff_id.clone(),
        upstream_subagent_handoff_id: record.upstream_subagent_handoff_id.clone(),
        workspace_scholarly_release_path: format!(
            "/api/darwin/workstreams/{}/workspace-scholarly-release",
            record.workstream_id
        ),
        workspace_manuscript_assembly_ref: format!(
            "workspace-manuscript-assembly:{}",
            record.upstream_assembly_id
        ),
        workspace_manuscript_handoff_ref: format!(
            "workspace-manuscript-handoff:{}",
            record.upstream_manuscript_handoff_id
        ),
        jats_qa_report_ref: format!("workspace-scholarly-release:{}:jats-qa-report", record.release_id),
        ro_crate_export_ref: format!("workspace-scholarly-release:{}:ro-crate-export", record.release_id),
        datacite_metadata_ref: format!("workspace-scholarly-release:{}:datacite-ready", record.release_id),
        crossref_article_stub_ref: format!(
            "workspace-scholarly-release:{}:crossref-article-stub",
            record.release_id
        ),
        release_bundle_ref: format!("workspace-scholarly-release:{}:release-bundle", record.release_id),
        program_id: record.program_id.clone(),
        campaign_id: record.campaign_id.clone(),
        manuscript_pack_id: record.manuscript_pack_id.clone(),
        jats_pack_id: record.jats_pack_id.clone(),
        readiness_state: upstream.jats_pack.readiness_state.clone(),
        section_profile: upstream.jats_pack.jats_profile.clone(),
        article_type: upstream.jats_pack.article_type.clone(),
        managed_attach_state: record.managed_attach_state.clone(),
        stable_attach_alias: record.stable_attach_alias.clone(),
        note: "The scholarly release keeps one Beagle-owned workspace/session identity while assembling a release-grade editorial bundle with QA and standards crosswalks.".to_string(),
    };
    let continuity = WorkspaceScholarlyReleaseContinuity {
        handoff_present: upstream.continuity.handoff_present,
        propagated_handoff: upstream.continuity.propagated_handoff.clone(),
        claim_count: upstream.continuity.claim_count,
        supported_claim_count: upstream.continuity.supported_claim_count,
        result_ref_count: upstream.continuity.result_ref_count,
        memory_ref_count: upstream.continuity.memory_ref_count,
        physio_ref_count: upstream.continuity.physio_ref_count,
        review_payload_count: upstream.review_bundle.payload_manifest.len(),
        jats_section_count: upstream.jats_pack.section_map.len(),
        jats_profile: upstream.jats_pack.jats_profile.clone(),
        jats_qa_status: jats_qa_report.qa_state.clone(),
        qa_warning_count: jats_qa_report.warning_count,
        qa_failure_count: jats_qa_report.failure_count,
        ro_crate_payload_count: ro_crate_export.payload_manifest.len(),
        datacite_related_identifier_count: datacite_metadata.related_identifiers.len(),
        crossref_related_item_count: crossref_article_stub.related_items.len(),
        crossref_has_abstract: !crossref_article_stub.abstract_text.is_empty(),
        provenance_activity_count: upstream.review_bundle.provenance.activities.len(),
        readiness_state: upstream.jats_pack.readiness_state.clone(),
        source_env_file: upstream.source_role.env_file.clone(),
        source_workspace_folder: upstream.source_role.workspace_folder.clone(),
        source_shell_entry_hint: upstream.source_role.shell_entry_hint.clone(),
    };

    Ok(WorkspaceScholarlyReleaseResponse {
        status: "ok".to_string(),
        phase: WORKSPACE_SCHOLARLY_RELEASE_PHASE.to_string(),
        release,
        continuity,
        source_role: upstream.source_role.clone(),
        subagents: upstream.subagents.clone(),
        context_packet: upstream.context_packet.clone(),
        program_context: upstream.program_context.clone(),
        evidence_pack: upstream.evidence_pack.clone(),
        claims: upstream.claims.clone(),
        review_bundle: upstream.review_bundle.clone(),
        jats_pack: upstream.jats_pack.clone(),
        jats_qa_report,
        ro_crate_export,
        datacite_metadata,
        crossref_article_stub,
        release_bundle,
    })
}

fn build_release_payload_manifest(
    record: &WorkspaceScholarlyReleaseRecord,
    evidence_pack: &EvidencePack,
    review_bundle: &ReviewBundle,
    jats_pack: &JatsManuscriptPack,
) -> Vec<ScholarlyReleasePayloadItem> {
    vec![
        ScholarlyReleasePayloadItem {
            logical_path: "qa/jats-qa-report.json".to_string(),
            payload_kind: "jats-qa-report".to_string(),
            media_type: "application/json".to_string(),
            reference: format!("workspace-scholarly-release:{}:jats-qa-report", record.release_id),
        },
        ScholarlyReleasePayloadItem {
            logical_path: "exports/ro-crate-metadata.json".to_string(),
            payload_kind: "ro-crate-export".to_string(),
            media_type: "application/ld+json".to_string(),
            reference: format!("workspace-scholarly-release:{}:ro-crate-export", record.release_id),
        },
        ScholarlyReleasePayloadItem {
            logical_path: "exports/datacite-metadata.json".to_string(),
            payload_kind: "datacite-ready-metadata".to_string(),
            media_type: "application/json".to_string(),
            reference: format!("workspace-scholarly-release:{}:datacite-ready", record.release_id),
        },
        ScholarlyReleasePayloadItem {
            logical_path: "exports/crossref-article.xml".to_string(),
            payload_kind: "crossref-article-stub".to_string(),
            media_type: "application/xml".to_string(),
            reference: format!(
                "workspace-scholarly-release:{}:crossref-article-stub",
                record.release_id
            ),
        },
        ScholarlyReleasePayloadItem {
            logical_path: "manuscript/jats-article.xml".to_string(),
            payload_kind: "jats-article".to_string(),
            media_type: "application/xml".to_string(),
            reference: format!("campaign:{}:jats-manuscript-pack", record.campaign_id),
        },
        ScholarlyReleasePayloadItem {
            logical_path: "review/review-bundle.json".to_string(),
            payload_kind: "review-bundle".to_string(),
            media_type: "application/json".to_string(),
            reference: review_bundle.bundle_id.clone(),
        },
        ScholarlyReleasePayloadItem {
            logical_path: "evidence/evidence-pack.json".to_string(),
            payload_kind: "evidence-pack".to_string(),
            media_type: "application/json".to_string(),
            reference: evidence_pack.pack_id.clone(),
        },
        ScholarlyReleasePayloadItem {
            logical_path: "claims/claims.json".to_string(),
            payload_kind: "claim-layer".to_string(),
            media_type: "application/json".to_string(),
            reference: format!("campaign:{}:claims", record.campaign_id),
        },
        ScholarlyReleasePayloadItem {
            logical_path: "manuscript/manuscript-pack.json".to_string(),
            payload_kind: "manuscript-pack".to_string(),
            media_type: "application/json".to_string(),
            reference: record.manuscript_pack_id.clone(),
        },
        ScholarlyReleasePayloadItem {
            logical_path: "contracts/manuscript-section-map.yaml".to_string(),
            payload_kind: "section-map-contract".to_string(),
            media_type: "text/yaml".to_string(),
            reference: SECTION_MAP_CONTRACT_REF.to_string(),
        },
        ScholarlyReleasePayloadItem {
            logical_path: "contracts/workspace-scholarly-release-schema.yaml".to_string(),
            payload_kind: "release-contract".to_string(),
            media_type: "text/yaml".to_string(),
            reference: "docs/darwin/hpc/contracts/workspace-scholarly-release-schema.yaml"
                .to_string(),
        },
        ScholarlyReleasePayloadItem {
            logical_path: "contracts/jats-qa-report-schema.yaml".to_string(),
            payload_kind: "qa-contract".to_string(),
            media_type: "text/yaml".to_string(),
            reference: "docs/darwin/hpc/contracts/jats-qa-report-schema.yaml".to_string(),
        },
        ScholarlyReleasePayloadItem {
            logical_path: "contracts/datacite-ready-metadata-schema.yaml".to_string(),
            payload_kind: "datacite-contract".to_string(),
            media_type: "text/yaml".to_string(),
            reference:
                "docs/darwin/hpc/contracts/datacite-ready-metadata-schema.yaml".to_string(),
        },
        ScholarlyReleasePayloadItem {
            logical_path: "contracts/crossref-article-stub-schema.yaml".to_string(),
            payload_kind: "crossref-contract".to_string(),
            media_type: "text/yaml".to_string(),
            reference: "docs/darwin/hpc/contracts/crossref-article-stub-schema.yaml".to_string(),
        },
        ScholarlyReleasePayloadItem {
            logical_path: "release/release-bundle.json".to_string(),
            payload_kind: "scholarly-release-bundle".to_string(),
            media_type: "application/json".to_string(),
            reference: format!("workspace-scholarly-release:{}:release-bundle", record.release_id),
        },
    ]
    .into_iter()
    .chain(
        jats_pack
            .citation
            .related_identifiers
            .iter()
            .map(|identifier| ScholarlyReleasePayloadItem {
                logical_path: format!(
                    "references/{}.txt",
                    sanitize_component(&identifier.value)
                ),
                payload_kind: "related-identifier".to_string(),
                media_type: "text/plain".to_string(),
                reference: identifier.value.clone(),
            }),
    )
    .collect()
}

fn build_jats_qa_report(
    jats_pack: &JatsManuscriptPack,
    review_bundle: &ReviewBundle,
) -> JatsQaReport {
    let xml = &jats_pack.jats_xml;
    let mut checks = vec![
        qa_check(
            "article-root",
            "JATS output contains an article root element.",
            xml.contains("<article "),
            "expected <article root element in JATS XML",
        ),
        qa_check(
            "front-present",
            "JATS output contains a front matter section.",
            xml.contains("<front>"),
            "expected <front> in JATS XML",
        ),
        qa_check(
            "body-present",
            "JATS output contains a body section.",
            xml.contains("<body>"),
            "expected <body> in JATS XML",
        ),
        qa_check(
            "ref-list-present",
            "JATS output contains a reference list.",
            xml.contains("<ref-list>"),
            "expected <ref-list> in JATS XML",
        ),
        qa_check(
            "minimum-sections",
            "JATS section map contains at least six editorial sections.",
            jats_pack.section_map.len() >= 6,
            "expected abstract/introduction/methods/results/discussion/references",
        ),
        qa_check(
            "required-sections",
            "JATS section map includes the canonical editorial sections.",
            has_required_sections(jats_pack),
            "required section types are abstract, introduction, methods, results, discussion, references",
        ),
        qa_check(
            "claim-links-explicit",
            "Claims remain explicitly linked in the manuscript package.",
            !jats_pack.claim_ids.is_empty()
                && jats_pack
                    .section_map
                    .iter()
                    .any(|section| !section.claim_refs.is_empty()),
            "expected claim ids and claim refs in section map",
        ),
        qa_check(
            "provenance-explicit",
            "Provenance remains explicit in the scholarly release.",
            !jats_pack.provenance.activities.is_empty(),
            "expected provenance activities in JATS pack",
        ),
        qa_check(
            "citation-explicit",
            "Citation identifiers remain explicit in the scholarly release.",
            !jats_pack.citation.related_identifiers.is_empty(),
            "expected related identifiers in citation metadata",
        ),
        qa_check(
            "review-bundle-aligned",
            "The JATS pack remains aligned with the upstream review bundle.",
            review_bundle.claim_ids == jats_pack.claim_ids,
            "expected matching claim ids between review bundle and JATS pack",
        ),
        qa_check(
            "readiness-explicit",
            "Readiness state remains explicit in the release artifact.",
            !jats_pack.readiness_state.trim().is_empty(),
            "expected readiness_state to be present",
        ),
    ];

    if jats_pack.readiness_state.contains("pending") {
        checks.push(JatsQaCheck {
            check_id: "human-eval-pending-explicit".to_string(),
            description:
                "Human-eval pending is preserved explicitly instead of being hidden.".to_string(),
            status: "warning".to_string(),
            detail: format!(
                "release remains bounded and honest with readiness_state={}",
                jats_pack.readiness_state
            ),
        });
    } else {
        checks.push(JatsQaCheck {
            check_id: "human-eval-pending-explicit".to_string(),
            description:
                "Human-eval pending is preserved explicitly instead of being hidden.".to_string(),
            status: "pass".to_string(),
            detail: "no pending human-eval state was attached to this JATS pack".to_string(),
        });
    }

    let warning_count = checks.iter().filter(|check| check.status == "warning").count();
    let failure_count = checks.iter().filter(|check| check.status == "fail").count();
    let qa_state = if failure_count > 0 {
        "fail"
    } else if warning_count > 0 {
        "pass-with-warnings"
    } else {
        "pass"
    };

    JatsQaReport {
        qa_profile: JATS_QA_PROFILE.to_string(),
        qa_state: qa_state.to_string(),
        checked_at: Utc::now(),
        readiness_state: jats_pack.readiness_state.clone(),
        warning_count,
        failure_count,
        checks,
        note: "The bounded QA report checks structural JATS readiness while keeping human-eval pending explicit when it still applies.".to_string(),
    }
}

fn qa_check(check_id: &str, description: &str, passed: bool, failure_detail: &str) -> JatsQaCheck {
    JatsQaCheck {
        check_id: check_id.to_string(),
        description: description.to_string(),
        status: if passed { "pass" } else { "fail" }.to_string(),
        detail: if passed {
            "check passed".to_string()
        } else {
            failure_detail.to_string()
        },
    }
}

fn has_required_sections(jats_pack: &JatsManuscriptPack) -> bool {
    let section_types = jats_pack
        .section_map
        .iter()
        .map(|section| section.section_type.as_str())
        .collect::<Vec<_>>();
    ["abstract", "introduction", "methods", "results", "discussion", "references"]
        .iter()
        .all(|required| section_types.contains(required))
}

fn build_ro_crate_export(
    record: &WorkspaceScholarlyReleaseRecord,
    upstream: &WorkspaceManuscriptAssemblyResponse,
    payload_manifest: &[ScholarlyReleasePayloadItem],
    qa_report: &JatsQaReport,
    datacite_metadata: &DataCiteReadyMetadata,
    crossref_article_stub: &CrossrefArticleStub,
) -> ScholarlyRoCrateExport {
    let payload_entities = payload_manifest
        .iter()
        .map(|item| {
            json!({
                "@id": item.logical_path,
                "@type": "File",
                "encodingFormat": item.media_type,
                "name": item.payload_kind,
            })
        })
        .collect::<Vec<_>>();
    let mut graph = vec![
        json!({
            "@id": "ro-crate-metadata.json",
            "@type": "CreativeWork",
            "about": { "@id": "./" },
            "conformsTo": { "@id": "https://w3id.org/ro/crate/1.1" }
        }),
        json!({
            "@id": "./",
            "@type": ["Dataset", "ScholarlyArticle"],
            "name": upstream.jats_pack.title,
            "identifier": record.release_id,
            "description": record.release_notes,
            "mainEntity": { "@id": "manuscript/jats-article.xml" },
            "hasPart": payload_manifest
                .iter()
                .map(|item| json!({ "@id": item.logical_path }))
                .collect::<Vec<_>>(),
            "isBasedOn": { "@id": upstream.review_bundle.bundle_id },
            "subjectOf": [
                { "@id": "exports/datacite-metadata.json" },
                { "@id": "exports/crossref-article.xml" }
            ]
        }),
        json!({
            "@id": upstream.review_bundle.bundle_id,
            "@type": "CreativeWork",
            "name": "Upstream Review Bundle",
            "identifier": upstream.review_bundle.bundle_id,
            "version": upstream.review_bundle.bundle_version
        }),
        json!({
            "@id": "qa/jats-qa-report.json",
            "@type": "File",
            "encodingFormat": "application/json",
            "name": "JATS QA Report",
            "description": qa_report.note
        }),
        json!({
            "@id": "exports/datacite-metadata.json",
            "@type": "File",
            "encodingFormat": "application/json",
            "name": "DataCite-ready Metadata",
            "description": format!(
                "DataCite-ready export with {} related identifiers.",
                datacite_metadata.related_identifiers.len()
            )
        }),
        json!({
            "@id": "exports/crossref-article.xml",
            "@type": "File",
            "encodingFormat": "application/xml",
            "name": "Crossref-compatible Article Stub",
            "description": format!(
                "Crossref-compatible stub for {}.",
                crossref_article_stub.article_title
            )
        }),
        json!({
            "@id": "manuscript/jats-article.xml",
            "@type": "File",
            "encodingFormat": "application/xml",
            "name": upstream.jats_pack.title
        }),
    ];
    graph.extend(payload_entities);

    let metadata = json!({
        "@context": RO_CRATE_CONTEXT,
        "@graph": graph
    });

    ScholarlyRoCrateExport {
        export_profile: RO_CRATE_EXPORT_PROFILE.to_string(),
        crate_file_name: "ro-crate-metadata.json".to_string(),
        root_entity_id: "./".to_string(),
        main_entity_id: "manuscript/jats-article.xml".to_string(),
        upstream_review_bundle_ref: upstream.review_bundle.bundle_id.clone(),
        payload_manifest: payload_manifest.to_vec(),
        metadata,
    }
}

fn build_datacite_ready_metadata(
    record: &WorkspaceScholarlyReleaseRecord,
    upstream: &WorkspaceManuscriptAssemblyResponse,
) -> DataCiteReadyMetadata {
    DataCiteReadyMetadata {
        metadata_profile: DATACITE_PROFILE.to_string(),
        identifiers: vec![DataCiteIdentifier {
            identifier: record.release_id.clone(),
            identifier_type: "InternalReleaseID".to_string(),
        }],
        creators: upstream
            .review_bundle
            .citation
            .creators
            .iter()
            .cloned()
            .map(|name| DataCiteCreator { name })
            .collect(),
        titles: vec![DataCiteTitle {
            title: upstream.jats_pack.title.clone(),
        }],
        publisher: upstream.review_bundle.citation.publisher.clone(),
        publication_year: upstream.review_bundle.citation.publication_year,
        types: DataCiteType {
            resource_type_general: upstream
                .review_bundle
                .citation
                .resource_type_general
                .clone(),
            resource_type: "JournalArticle".to_string(),
        },
        version: WORKSPACE_SCHOLARLY_RELEASE_VERSION.to_string(),
        subjects: upstream
            .review_bundle
            .citation
            .subjects
            .iter()
            .cloned()
            .map(|subject| DataCiteSubject { subject })
            .collect(),
        descriptions: vec![
            DataCiteDescription {
                description: record.summary.clone(),
                description_type: "Abstract".to_string(),
            },
            DataCiteDescription {
                description: record.release_notes.clone(),
                description_type: "TechnicalInfo".to_string(),
            },
        ],
        related_identifiers: upstream.review_bundle.citation.related_identifiers.clone(),
        language: "en".to_string(),
        readiness_state: upstream.jats_pack.readiness_state.clone(),
        evidence_pack_ref: upstream.evidence_pack.pack_id.clone(),
        review_bundle_ref: upstream.review_bundle.bundle_id.clone(),
        jats_pack_ref: upstream.jats_pack.pack_id.clone(),
    }
}

fn build_crossref_article_stub(
    record: &WorkspaceScholarlyReleaseRecord,
    upstream: &WorkspaceManuscriptAssemblyResponse,
    datacite_metadata: &DataCiteReadyMetadata,
) -> CrossrefArticleStub {
    let contributors = datacite_metadata
        .creators
        .iter()
        .map(|creator| crossref_contributor(&creator.name))
        .collect::<Vec<_>>();
    let contributor_xml = contributors
        .iter()
        .map(|contributor| {
            let given = contributor
                .given_name
                .as_ref()
                .map(|value| format!("<given_name>{}</given_name>", xml_escape(value)))
                .unwrap_or_default();
            format!(
                "<person_name contributor_role=\"author\" sequence=\"additional\">{}{}</person_name>",
                given,
                format!("<surname>{}</surname>", xml_escape(&contributor.surname))
            )
        })
        .collect::<Vec<_>>()
        .join("");
    let citation_xml = datacite_metadata
        .related_identifiers
        .iter()
        .enumerate()
        .map(|(index, identifier)| {
            format!(
                "<citation key=\"R{}\"><unstructured_citation>{} [{}] {}</unstructured_citation></citation>",
                index + 1,
                xml_escape(&identifier.relation_type),
                xml_escape(&identifier.identifier_type),
                xml_escape(&identifier.value)
            )
        })
        .collect::<Vec<_>>()
        .join("");
    let xml_stub = format!(
        "<doi_batch xmlns=\"http://www.crossref.org/schema/5.3.1\"><head><doi_batch_id>{}</doi_batch_id><timestamp>{}</timestamp><depositor><depositor_name>{}</depositor_name><email_address>{}</email_address></depositor><registrant>{}</registrant></head><body><journal><journal_metadata><full_title>{}</full_title></journal_metadata><journal_issue><publication_date media_type=\"online\"><year>{}</year></publication_date></journal_issue><journal_article publication_type=\"full_text\"><titles><title>{}</title></titles><contributors>{}</contributors><jats:abstract xmlns:jats=\"http://www.ncbi.nlm.nih.gov/JATS1\"><jats:p>{}</jats:p></jats:abstract><citation_list>{}</citation_list></journal_article></journal></body></doi_batch>",
        xml_escape(&record.release_id),
        record.recorded_at.timestamp(),
        xml_escape(&upstream.review_bundle.citation.publisher),
        "noreply@beagle.invalid",
        xml_escape(&upstream.review_bundle.citation.publisher),
        "Beagle Internal Research Objects",
        upstream.review_bundle.citation.publication_year,
        xml_escape(&upstream.jats_pack.title),
        contributor_xml,
        xml_escape(&upstream.jats_pack.abstract_text),
        citation_xml,
    );

    CrossrefArticleStub {
        export_profile: CROSSREF_PROFILE.to_string(),
        stub_id: format!("{}-crossref-article-stub", record.release_id),
        journal_title: "Beagle Internal Research Objects".to_string(),
        publisher_name: upstream.review_bundle.citation.publisher.clone(),
        article_title: upstream.jats_pack.title.clone(),
        article_type: upstream.jats_pack.article_type.clone(),
        abstract_text: upstream.jats_pack.abstract_text.clone(),
        contributors,
        publication_year: upstream.review_bundle.citation.publication_year,
        language: "en".to_string(),
        readiness_state: upstream.jats_pack.readiness_state.clone(),
        related_items: datacite_metadata.related_identifiers.clone(),
        xml_stub,
    }
}

fn crossref_contributor(name: &str) -> CrossrefContributor {
    let tokens = name
        .split_whitespace()
        .map(|token| token.to_string())
        .collect::<Vec<_>>();
    let (given_name, surname) = match tokens.split_last() {
        Some((last, [])) => (None, last.clone()),
        Some((last, rest)) => (Some(rest.join(" ")), last.clone()),
        None => (None, name.to_string()),
    };
    CrossrefContributor {
        full_name: name.to_string(),
        given_name,
        surname,
    }
}

fn build_release_bundle(
    record: &WorkspaceScholarlyReleaseRecord,
    upstream: &WorkspaceManuscriptAssemblyResponse,
    payload_manifest: &[ScholarlyReleasePayloadItem],
    _qa_report: &JatsQaReport,
    _ro_crate_export: &ScholarlyRoCrateExport,
    _datacite_metadata: &DataCiteReadyMetadata,
    _crossref_article_stub: &CrossrefArticleStub,
) -> ScholarlyReleaseBundle {
    ScholarlyReleaseBundle {
        bundle_version: WORKSPACE_SCHOLARLY_RELEASE_VERSION.to_string(),
        bundle_kind: "scholarly-release-bundle".to_string(),
        bundle_id: format!("{}-release-bundle", record.release_id),
        program_id: record.program_id.clone(),
        campaign_id: record.campaign_id.clone(),
        workstream_id: record.workstream_id.clone(),
        workspace_id: record.workspace_id.clone(),
        session_id: record.session_id.clone(),
        manuscript_pack_id: record.manuscript_pack_id.clone(),
        jats_pack_id: record.jats_pack_id.clone(),
        readiness_state: upstream.jats_pack.readiness_state.clone(),
        qa_report_ref: format!("workspace-scholarly-release:{}:jats-qa-report", record.release_id),
        ro_crate_export_ref: format!("workspace-scholarly-release:{}:ro-crate-export", record.release_id),
        datacite_metadata_ref: format!("workspace-scholarly-release:{}:datacite-ready", record.release_id),
        crossref_article_stub_ref: format!(
            "workspace-scholarly-release:{}:crossref-article-stub",
            record.release_id
        ),
        payload_manifest: payload_manifest.to_vec(),
        provenance: upstream.review_bundle.provenance.clone(),
        citation: upstream.review_bundle.citation.clone(),
        note: "The scholarly release bundle is release-grade and externalizable, but it intentionally stops before DOI deposit or external submission.".to_string(),
    }
}

fn write_release_record(
    data_dir: &Path,
    workspace_id: &str,
    record: &WorkspaceScholarlyReleaseRecord,
) -> anyhow::Result<()> {
    let path = scholarly_release_record_path(data_dir, workspace_id);
    if let Some(parent) = path.parent() {
        fs::create_dir_all(parent).with_context(|| {
            format!(
                "create scholarly release directory {}",
                parent.display()
            )
        })?;
    }
    let payload = serde_json::to_vec_pretty(record)
        .context("serialize workspace scholarly release record")?;
    fs::write(&path, payload).with_context(|| {
        format!("write scholarly release record {}", path.display())
    })?;
    Ok(())
}

fn read_release_record(
    data_dir: &Path,
    workspace_id: &str,
) -> anyhow::Result<Option<WorkspaceScholarlyReleaseRecord>> {
    let path = scholarly_release_record_path(data_dir, workspace_id);
    if !path.exists() {
        return Ok(None);
    }
    let bytes =
        fs::read(&path).with_context(|| format!("read scholarly release record {}", path.display()))?;
    let record = serde_json::from_slice(&bytes)
        .with_context(|| format!("parse scholarly release record {}", path.display()))?;
    Ok(Some(record))
}

fn scholarly_release_record_path(data_dir: &Path, workspace_id: &str) -> PathBuf {
    workspace_scholarly_release_dir(data_dir).join(format!(
        "{}.json",
        sanitize_component(workspace_id)
    ))
}

fn workspace_scholarly_release_dir(data_dir: &Path) -> PathBuf {
    crate::workspace_plane::workspace_plane_dir(data_dir).join("scholarly-releases")
}

fn xml_escape(value: &str) -> String {
    value
        .replace('&', "&amp;")
        .replace('<', "&lt;")
        .replace('>', "&gt;")
        .replace('"', "&quot;")
        .replace('\'', "&apos;")
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
                    snippet: "Turn the same bounded evidence and claims into a release-grade package.".to_string(),
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

    fn seed_manuscript_assembly(
        data_dir: &Path,
        cfg: &BeagleConfig,
    ) -> WorkspaceManuscriptAssemblyResponse {
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

        record_workspace_manuscript_assembly(
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
        .expect("manuscript assembly")
    }

    #[test]
    fn workspace_scholarly_release_records_qa_and_crosswalks_with_same_identity() {
        let data_dir = temp_data_dir("workspace-scholarly-release");
        let cfg = test_config(&data_dir);
        seed_workspace_session(&data_dir, &cfg);
        let upstream = seed_manuscript_assembly(&data_dir, &cfg);

        let response = record_workspace_scholarly_release(
            &data_dir,
            &cfg,
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
        .expect("scholarly release");

        assert_eq!(response.phase, "B21.3");
        assert_eq!(response.release.workstream_id, "beagle-darwin-hpc-governance");
        assert_eq!(response.release.workspace_id, "beagle-cluster-pilot");
        assert_eq!(response.release.session_id, "ws-cluster-workspace-habitat");
        assert_eq!(response.release.source_subagent_id, "manuscript");
        assert_eq!(
            response.release.upstream_assembly_id,
            upstream.assembly.assembly_id
        );
        assert_eq!(response.jats_qa_report.qa_profile, "jats-1.4-bounded-qa-v1");
        assert_eq!(response.ro_crate_export.export_profile, "ro-crate-1.2-release-bounded");
        assert_eq!(response.datacite_metadata.metadata_profile, "datacite-4.7-ready");
        assert_eq!(response.crossref_article_stub.export_profile, "crossref-journal-article-stub-v1");
        assert_eq!(response.release_bundle.readiness_state, response.jats_pack.readiness_state);
        assert!(response.jats_qa_report.warning_count >= 1);
        assert_eq!(response.jats_qa_report.failure_count, 0);
        assert!(response.crossref_article_stub.xml_stub.contains("<doi_batch"));
        assert!(response.crossref_article_stub.xml_stub.contains("<journal_article"));
        assert!(response.ro_crate_export.metadata.to_string().contains("ro-crate-metadata.json"));
        assert_eq!(response.review_bundle.campaign_id, response.evidence_pack.campaign_id);
    }

    #[test]
    fn workspace_scholarly_release_latest_survives_restart_shaping() {
        let data_dir = temp_data_dir("workspace-scholarly-release-restart");
        let cfg = test_config(&data_dir);
        seed_workspace_session(&data_dir, &cfg);
        let upstream = seed_manuscript_assembly(&data_dir, &cfg);

        let recorded = record_workspace_scholarly_release(
            &data_dir,
            &cfg,
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
        .expect("record scholarly release");

        let shaped = read_workspace_scholarly_release(
            &data_dir,
            &cfg,
            "beagle-darwin-hpc-governance",
            packet(),
        )
        .expect("read scholarly release")
        .expect("scholarly release present");

        assert_eq!(shaped.release.release_id, recorded.release.release_id);
        assert_eq!(shaped.release.upstream_assembly_id, upstream.assembly.assembly_id);
        assert_eq!(shaped.release.session_id, "ws-cluster-workspace-habitat");
        assert_eq!(shaped.source_role.subagent_id, "manuscript");
        assert_eq!(
            shaped.release_bundle.bundle_id,
            recorded.release_bundle.bundle_id
        );
        assert_eq!(
            shaped.context_packet.handoff.last_handoff,
            recorded.context_packet.handoff.last_handoff
        );
        assert_eq!(shaped.jats_qa_report.qa_state, recorded.jats_qa_report.qa_state);
    }
}
