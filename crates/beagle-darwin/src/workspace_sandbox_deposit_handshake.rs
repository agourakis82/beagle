use crate::workspace_external_registry_staging::{
    read_workspace_external_registry_staging, CrossrefDryRunBundle, DataCiteTestStagingPayload,
    ExternalRegistryStagingBundle, ExternalStagingReadinessReport,
    WorkspaceExternalRegistryStagingResponse,
};
use crate::workspace_publication_package::WorkspacePublicationPackageResponse;
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
use reqwest::blocking::{multipart, Client};
use reqwest::header::{ACCEPT, CONTENT_TYPE};
use serde::{Deserialize, Serialize};
use std::env;
use std::fs;
use std::path::{Path, PathBuf};
use std::time::Duration;

const WORKSPACE_SANDBOX_DEPOSIT_PHASE: &str = "B21.6";
const WORKSPACE_SANDBOX_DEPOSIT_VERSION: &str = "beagle-sandbox-deposit-handshake-v1";
const WORKSPACE_SANDBOX_DEPOSIT_KIND: &str = "workspace-sandbox-deposit-handshake";
const MANUSCRIPT_SUBAGENT_ID: &str = "manuscript";
const DATACITE_TEST_RECEIPT_PROFILE: &str = "datacite-test-receipt-v1";
const CROSSREF_TEST_RECEIPT_PROFILE: &str = "crossref-test-receipt-v1";
const REGISTRY_SUBMISSION_LEDGER_PROFILE: &str = "registry-submission-ledger-v1";
const DEFAULT_DATACITE_TEST_API_BASE_URL: &str = "https://api.test.datacite.org";
const DEFAULT_CROSSREF_TEST_DEPOSIT_URL: &str = "https://test.crossref.org/servlet/deposit";
const SANDBOX_NETWORK_ENV: &str = "BEAGLE_SANDBOX_DEPOSIT_NETWORK";
const DATACITE_TEST_API_BASE_ENV: &str = "BEAGLE_DATACITE_TEST_API_BASE_URL";
const DATACITE_TEST_USERNAME_ENV: &str = "BEAGLE_DATACITE_TEST_USERNAME";
const DATACITE_TEST_PASSWORD_ENV: &str = "BEAGLE_DATACITE_TEST_PASSWORD";
const CROSSREF_TEST_DEPOSIT_URL_ENV: &str = "BEAGLE_CROSSREF_TEST_DEPOSIT_URL";
const CROSSREF_TEST_USERNAME_ENV: &str = "BEAGLE_CROSSREF_TEST_USERNAME";
const CROSSREF_TEST_PASSWORD_ENV: &str = "BEAGLE_CROSSREF_TEST_PASSWORD";
const PLACEHOLDER_REGISTRY_USER: &str = "beagle-placeholder";
const PLACEHOLDER_REGISTRY_PASSWORD: &str = "beagle-placeholder";

#[derive(Debug, Clone, Serialize, Deserialize)]
struct WorkspaceSandboxDepositHandshakeRecord {
    package_version: String,
    package_id: String,
    workstream_id: String,
    workspace_id: String,
    session_id: String,
    source_subagent_id: String,
    source_role_tag: String,
    requested_tool_id: Option<String>,
    handshake_goal: String,
    summary: String,
    handshake_notes: String,
    upstream_external_staging_id: String,
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
    datacite_test_receipt: DataCiteTestReceipt,
    crossref_test_receipt: CrossrefTestReceipt,
    registry_submission_ledger: RegistrySubmissionLedger,
}

#[derive(Debug, Clone)]
pub struct WorkspaceSandboxDepositHandshakeRequest<'a> {
    pub source_subagent_id: &'a str,
    pub requested_tool_id: Option<&'a str>,
    pub handshake_goal: &'a str,
    pub summary: &'a str,
    pub handshake_notes: &'a str,
}

#[derive(Debug, Clone, Serialize)]
pub struct WorkspaceSandboxDepositHandshakePlane {
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
    pub handshake_goal: String,
    pub summary: String,
    pub handshake_notes: String,
    pub upstream_external_staging_id: String,
    pub upstream_publication_package_id: String,
    pub upstream_release_id: String,
    pub upstream_assembly_id: String,
    pub upstream_manuscript_handoff_id: String,
    pub upstream_subagent_handoff_id: String,
    pub workspace_sandbox_deposit_path: String,
    pub workspace_external_staging_ref: String,
    pub datacite_test_receipt_ref: String,
    pub crossref_test_receipt_ref: String,
    pub registry_submission_ledger_ref: String,
    pub sandbox_deposit_bundle_ref: String,
    pub program_id: String,
    pub campaign_id: String,
    pub manuscript_pack_id: String,
    pub jats_pack_id: String,
    pub readiness_state: String,
    pub technical_external_staging_state: String,
    pub registry_handshake_state: String,
    pub section_profile: String,
    pub article_type: String,
    pub managed_attach_state: String,
    pub stable_attach_alias: String,
    pub note: String,
}

#[derive(Debug, Clone, Serialize)]
pub struct WorkspaceSandboxDepositHandshakeContinuity {
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
    pub external_registry_live_boundary_proven: bool,
    pub live_registry_response_count: usize,
    pub accepted_registry_count: usize,
    pub auth_blocked_registry_count: usize,
    pub findable_publication_allowed: bool,
    pub readiness_state: String,
    pub source_env_file: String,
    pub source_workspace_folder: String,
    pub source_shell_entry_hint: String,
    pub restart_recovered_session: bool,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct DataCiteTestReceipt {
    pub receipt_profile: String,
    pub registry: String,
    pub receipt_id: String,
    pub target_url: String,
    pub request_method: String,
    pub performed_at: DateTime<Utc>,
    pub credential_state: String,
    pub real_network_call_attempted: bool,
    pub transport_ok: bool,
    pub accepted: bool,
    pub http_status: Option<u16>,
    pub registry_state: String,
    pub response_content_type: Option<String>,
    pub response_identifier: Option<String>,
    pub response_summary: String,
    pub response_body_excerpt: String,
    pub readiness_state: String,
    pub note: String,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct CrossrefTestReceipt {
    pub receipt_profile: String,
    pub registry: String,
    pub receipt_id: String,
    pub target_url: String,
    pub request_method: String,
    pub performed_at: DateTime<Utc>,
    pub credential_state: String,
    pub real_network_call_attempted: bool,
    pub transport_ok: bool,
    pub accepted: bool,
    pub http_status: Option<u16>,
    pub registry_state: String,
    pub response_content_type: Option<String>,
    pub response_identifier: Option<String>,
    pub response_summary: String,
    pub response_body_excerpt: String,
    pub readiness_state: String,
    pub note: String,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct RegistrySubmissionLedgerEntry {
    pub registry: String,
    pub receipt_ref: String,
    pub performed_at: DateTime<Utc>,
    pub target_url: String,
    pub credential_state: String,
    pub real_network_call_attempted: bool,
    pub transport_ok: bool,
    pub accepted: bool,
    pub http_status: Option<u16>,
    pub registry_state: String,
    pub response_identifier: Option<String>,
    pub response_summary: String,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct RegistrySubmissionLedger {
    pub ledger_profile: String,
    pub ledger_id: String,
    pub workstream_id: String,
    pub workspace_id: String,
    pub session_id: String,
    pub campaign_id: String,
    pub package_id: String,
    pub readiness_state: String,
    pub registry_handshake_state: String,
    pub submission_count: usize,
    pub live_network_attempt_count: usize,
    pub live_registry_response_count: usize,
    pub accepted_submission_count: usize,
    pub auth_blocked_submission_count: usize,
    pub entries: Vec<RegistrySubmissionLedgerEntry>,
    pub note: String,
}

#[derive(Debug, Clone, Serialize)]
pub struct SandboxDepositBundle {
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
    pub registry_handshake_state: String,
    pub workspace_external_staging_ref: String,
    pub datacite_test_receipt_ref: String,
    pub crossref_test_receipt_ref: String,
    pub registry_submission_ledger_ref: String,
    pub payload_manifest: Vec<ScholarlyReleasePayloadItem>,
    pub provenance: EvidencePackProvenance,
    pub citation: EvidencePackCitation,
    pub note: String,
}

#[derive(Debug, Clone, Serialize)]
pub struct WorkspaceSandboxDepositHandshakeResponse {
    pub status: String,
    pub phase: String,
    pub package: WorkspaceSandboxDepositHandshakePlane,
    pub continuity: WorkspaceSandboxDepositHandshakeContinuity,
    pub source_role: WorkspaceSubAgentRole,
    pub subagents: WorkspaceSubAgentsPlane,
    pub context_packet: WorkstreamContextPacket,
    pub program_context: ProgramContextPacket,
    pub evidence_pack: EvidencePack,
    pub claims: CampaignClaimsResponse,
    pub review_bundle: ReviewBundle,
    pub scholarly_release: WorkspaceScholarlyReleaseResponse,
    pub publication_package: WorkspacePublicationPackageResponse,
    pub external_staging: WorkspaceExternalRegistryStagingResponse,
    pub external_staging_readiness_report: ExternalStagingReadinessReport,
    pub external_staging_bundle: ExternalRegistryStagingBundle,
    pub datacite_test_receipt: DataCiteTestReceipt,
    pub crossref_test_receipt: CrossrefTestReceipt,
    pub registry_submission_ledger: RegistrySubmissionLedger,
    pub sandbox_deposit_bundle: SandboxDepositBundle,
}

pub fn record_workspace_sandbox_deposit_handshake(
    data_dir: &Path,
    cfg: &BeagleConfig,
    workstream_id: &str,
    context_packet: WorkstreamContextPacketResponse,
    request: WorkspaceSandboxDepositHandshakeRequest<'_>,
) -> anyhow::Result<WorkspaceSandboxDepositHandshakeResponse> {
    let upstream = read_workspace_external_registry_staging(data_dir, cfg, workstream_id, context_packet)?
        .ok_or_else(|| anyhow!("workspace external staging is required before sandbox deposit handshake"))?;

    let source_subagent_id = normalize_selector(request.source_subagent_id);
    if source_subagent_id != MANUSCRIPT_SUBAGENT_ID {
        return Err(anyhow!(
            "sandbox deposit handshake must originate from sub-agent '{}'",
            MANUSCRIPT_SUBAGENT_ID
        ));
    }
    if upstream.package.source_subagent_id != source_subagent_id {
        return Err(anyhow!(
            "latest external staging package must originate from '{}' before sandbox handshake",
            source_subagent_id
        ));
    }

    let requested_tool_id = request
        .requested_tool_id
        .map(normalize_selector)
        .filter(|value| !value.is_empty())
        .or_else(|| Some("claude-code".to_string()));
    let handshake_goal = normalize_sentence(request.handshake_goal);
    let summary = normalize_sentence(request.summary);
    let handshake_notes = normalize_sentence(request.handshake_notes);
    if handshake_goal.is_empty() {
        return Err(anyhow!("sandbox deposit handshake goal must not be empty"));
    }
    if summary.is_empty() {
        return Err(anyhow!("sandbox deposit handshake summary must not be empty"));
    }
    if handshake_notes.is_empty() {
        return Err(anyhow!("sandbox deposit handshake notes must not be empty"));
    }

    let package_id = format!(
        "{}-sandbox-deposit-{}",
        sanitize_component(&upstream.package.session_id),
        Utc::now().timestamp_millis()
    );
    let datacite_test_receipt = perform_datacite_test_handshake(
        &upstream.datacite_test_staging_payload,
        &upstream.package.readiness_state,
    );
    let crossref_test_receipt = perform_crossref_test_handshake(
        &upstream.crossref_dry_run_bundle,
        &upstream.package.readiness_state,
    );
    let registry_submission_ledger = build_registry_submission_ledger(
        &package_id,
        &upstream,
        &datacite_test_receipt,
        &crossref_test_receipt,
    );

    let record = WorkspaceSandboxDepositHandshakeRecord {
        package_version: WORKSPACE_SANDBOX_DEPOSIT_VERSION.to_string(),
        package_id,
        workstream_id: upstream.package.workstream_id.clone(),
        workspace_id: upstream.package.workspace_id.clone(),
        session_id: upstream.package.session_id.clone(),
        source_subagent_id: upstream.package.source_subagent_id.clone(),
        source_role_tag: upstream.package.source_role_tag.clone(),
        requested_tool_id,
        handshake_goal,
        summary,
        handshake_notes,
        upstream_external_staging_id: upstream.package.package_id.clone(),
        upstream_publication_package_id: upstream.package.upstream_publication_package_id.clone(),
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
        datacite_test_receipt,
        crossref_test_receipt,
        registry_submission_ledger,
    };
    write_sandbox_deposit_record(data_dir, &record.workspace_id, &record)?;

    response_from_state(&upstream, record)
}

pub fn read_workspace_sandbox_deposit_handshake(
    data_dir: &Path,
    cfg: &BeagleConfig,
    workstream_id: &str,
    context_packet: WorkstreamContextPacketResponse,
) -> anyhow::Result<Option<WorkspaceSandboxDepositHandshakeResponse>> {
    let Some(record) = read_sandbox_deposit_record(data_dir, &context_packet.packet.workspace_id)?
    else {
        return Ok(None);
    };
    let upstream = read_workspace_external_registry_staging(data_dir, cfg, workstream_id, context_packet)?
        .ok_or_else(|| anyhow!("workspace external staging is unavailable for sandbox deposit shaping"))?;
    response_from_state(&upstream, record).map(Some)
}

fn response_from_state(
    upstream: &WorkspaceExternalRegistryStagingResponse,
    record: WorkspaceSandboxDepositHandshakeRecord,
) -> anyhow::Result<WorkspaceSandboxDepositHandshakeResponse> {
    let payload_manifest = build_sandbox_deposit_payload_manifest(&record, upstream);
    let registry_handshake_state =
        derive_registry_handshake_state(&record.datacite_test_receipt, &record.crossref_test_receipt);
    let sandbox_deposit_bundle =
        build_sandbox_deposit_bundle(&record, upstream, &payload_manifest, &registry_handshake_state);

    let package = WorkspaceSandboxDepositHandshakePlane {
        package_version: WORKSPACE_SANDBOX_DEPOSIT_VERSION.to_string(),
        package_kind: WORKSPACE_SANDBOX_DEPOSIT_KIND.to_string(),
        package_id: record.package_id.clone(),
        workstream_id: record.workstream_id.clone(),
        workspace_id: record.workspace_id.clone(),
        session_id: record.session_id.clone(),
        package_state: "sandbox-deposit-handshaked".to_string(),
        recorded_at: record.recorded_at,
        source_subagent_id: record.source_subagent_id.clone(),
        source_role_tag: record.source_role_tag.clone(),
        requested_tool_id: record.requested_tool_id.clone(),
        handshake_goal: record.handshake_goal.clone(),
        summary: record.summary.clone(),
        handshake_notes: record.handshake_notes.clone(),
        upstream_external_staging_id: record.upstream_external_staging_id.clone(),
        upstream_publication_package_id: record.upstream_publication_package_id.clone(),
        upstream_release_id: record.upstream_release_id.clone(),
        upstream_assembly_id: record.upstream_assembly_id.clone(),
        upstream_manuscript_handoff_id: record.upstream_manuscript_handoff_id.clone(),
        upstream_subagent_handoff_id: record.upstream_subagent_handoff_id.clone(),
        workspace_sandbox_deposit_path: format!(
            "/api/darwin/workstreams/{}/workspace-sandbox-deposit",
            record.workstream_id
        ),
        workspace_external_staging_ref: format!(
            "workspace-external-staging:{}",
            record.upstream_external_staging_id
        ),
        datacite_test_receipt_ref: format!(
            "workspace-sandbox-deposit:{}:datacite-test-receipt",
            record.package_id
        ),
        crossref_test_receipt_ref: format!(
            "workspace-sandbox-deposit:{}:crossref-test-receipt",
            record.package_id
        ),
        registry_submission_ledger_ref: format!(
            "workspace-sandbox-deposit:{}:registry-submission-ledger",
            record.package_id
        ),
        sandbox_deposit_bundle_ref: format!(
            "workspace-sandbox-deposit:{}:sandbox-deposit-bundle",
            record.package_id
        ),
        program_id: record.program_id.clone(),
        campaign_id: record.campaign_id.clone(),
        manuscript_pack_id: record.manuscript_pack_id.clone(),
        jats_pack_id: record.jats_pack_id.clone(),
        readiness_state: upstream.package.readiness_state.clone(),
        technical_external_staging_state: upstream
            .package
            .technical_external_staging_state
            .clone(),
        registry_handshake_state: registry_handshake_state.clone(),
        section_profile: upstream.package.section_profile.clone(),
        article_type: upstream.package.article_type.clone(),
        managed_attach_state: record.managed_attach_state.clone(),
        stable_attach_alias: record.stable_attach_alias.clone(),
        note: "The sandbox deposit handshake layer executes real network roundtrips against test registries, preserving receipts and leaving epistemic readiness explicit.".to_string(),
    };
    let continuity = WorkspaceSandboxDepositHandshakeContinuity {
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
        technical_blocker_count: upstream.continuity.technical_blocker_count,
        epistemic_blocker_count: upstream.continuity.epistemic_blocker_count,
        technical_ready_for_external_staging: upstream.continuity.technical_ready_for_external_staging,
        external_registry_live_boundary_proven: record
            .registry_submission_ledger
            .live_registry_response_count
            == 2,
        live_registry_response_count: record.registry_submission_ledger.live_registry_response_count,
        accepted_registry_count: record.registry_submission_ledger.accepted_submission_count,
        auth_blocked_registry_count: record
            .registry_submission_ledger
            .auth_blocked_submission_count,
        findable_publication_allowed: upstream.continuity.findable_publication_allowed,
        readiness_state: upstream.package.readiness_state.clone(),
        source_env_file: upstream.continuity.source_env_file.clone(),
        source_workspace_folder: upstream.continuity.source_workspace_folder.clone(),
        source_shell_entry_hint: upstream.continuity.source_shell_entry_hint.clone(),
        restart_recovered_session: true,
    };

    Ok(WorkspaceSandboxDepositHandshakeResponse {
        status: "ok".to_string(),
        phase: WORKSPACE_SANDBOX_DEPOSIT_PHASE.to_string(),
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
        publication_package: upstream.publication_package.clone(),
        external_staging: upstream.clone(),
        external_staging_readiness_report: upstream.external_staging_readiness_report.clone(),
        external_staging_bundle: upstream.external_staging_bundle.clone(),
        datacite_test_receipt: record.datacite_test_receipt.clone(),
        crossref_test_receipt: record.crossref_test_receipt.clone(),
        registry_submission_ledger: record.registry_submission_ledger.clone(),
        sandbox_deposit_bundle,
    })
}

fn build_sandbox_deposit_payload_manifest(
    record: &WorkspaceSandboxDepositHandshakeRecord,
    upstream: &WorkspaceExternalRegistryStagingResponse,
) -> Vec<ScholarlyReleasePayloadItem> {
    let mut payloads = upstream.external_staging_bundle.payload_manifest.clone();
    payloads.push(ScholarlyReleasePayloadItem {
        logical_path: "receipts/datacite-test-receipt.json".to_string(),
        payload_kind: "datacite-test-receipt".to_string(),
        media_type: "application/json".to_string(),
        reference: format!(
            "workspace-sandbox-deposit:{}:datacite-test-receipt",
            record.package_id
        ),
    });
    payloads.push(ScholarlyReleasePayloadItem {
        logical_path: "receipts/crossref-test-receipt.json".to_string(),
        payload_kind: "crossref-test-receipt".to_string(),
        media_type: "application/json".to_string(),
        reference: format!(
            "workspace-sandbox-deposit:{}:crossref-test-receipt",
            record.package_id
        ),
    });
    payloads.push(ScholarlyReleasePayloadItem {
        logical_path: "reports/registry-submission-ledger.json".to_string(),
        payload_kind: "registry-submission-ledger".to_string(),
        media_type: "application/json".to_string(),
        reference: format!(
            "workspace-sandbox-deposit:{}:registry-submission-ledger",
            record.package_id
        ),
    });
    payloads.push(ScholarlyReleasePayloadItem {
        logical_path: "release/sandbox-deposit-bundle.json".to_string(),
        payload_kind: "sandbox-deposit-bundle".to_string(),
        media_type: "application/json".to_string(),
        reference: format!(
            "workspace-sandbox-deposit:{}:sandbox-deposit-bundle",
            record.package_id
        ),
    });
    payloads.push(ScholarlyReleasePayloadItem {
        logical_path: "contracts/datacite-test-receipt-schema.yaml".to_string(),
        payload_kind: "datacite-test-receipt-contract".to_string(),
        media_type: "text/yaml".to_string(),
        reference: "docs/darwin/hpc/contracts/datacite-test-receipt-schema.yaml"
            .to_string(),
    });
    payloads.push(ScholarlyReleasePayloadItem {
        logical_path: "contracts/crossref-test-receipt-schema.yaml".to_string(),
        payload_kind: "crossref-test-receipt-contract".to_string(),
        media_type: "text/yaml".to_string(),
        reference: "docs/darwin/hpc/contracts/crossref-test-receipt-schema.yaml"
            .to_string(),
    });
    payloads.push(ScholarlyReleasePayloadItem {
        logical_path: "contracts/registry-submission-ledger-schema.yaml".to_string(),
        payload_kind: "registry-submission-ledger-contract".to_string(),
        media_type: "text/yaml".to_string(),
        reference: "docs/darwin/hpc/contracts/registry-submission-ledger-schema.yaml"
            .to_string(),
    });
    payloads
}

fn build_sandbox_deposit_bundle(
    record: &WorkspaceSandboxDepositHandshakeRecord,
    upstream: &WorkspaceExternalRegistryStagingResponse,
    payload_manifest: &[ScholarlyReleasePayloadItem],
    registry_handshake_state: &str,
) -> SandboxDepositBundle {
    SandboxDepositBundle {
        bundle_version: WORKSPACE_SANDBOX_DEPOSIT_VERSION.to_string(),
        bundle_kind: "sandbox-deposit-bundle".to_string(),
        bundle_id: format!("{}-sandbox-deposit-bundle", record.package_id),
        program_id: record.program_id.clone(),
        campaign_id: record.campaign_id.clone(),
        workstream_id: record.workstream_id.clone(),
        workspace_id: record.workspace_id.clone(),
        session_id: record.session_id.clone(),
        manuscript_pack_id: record.manuscript_pack_id.clone(),
        jats_pack_id: record.jats_pack_id.clone(),
        readiness_state: upstream.package.readiness_state.clone(),
        technical_external_staging_state: upstream
            .package
            .technical_external_staging_state
            .clone(),
        registry_handshake_state: registry_handshake_state.to_string(),
        workspace_external_staging_ref: format!(
            "workspace-external-staging:{}",
            record.upstream_external_staging_id
        ),
        datacite_test_receipt_ref: format!(
            "workspace-sandbox-deposit:{}:datacite-test-receipt",
            record.package_id
        ),
        crossref_test_receipt_ref: format!(
            "workspace-sandbox-deposit:{}:crossref-test-receipt",
            record.package_id
        ),
        registry_submission_ledger_ref: format!(
            "workspace-sandbox-deposit:{}:registry-submission-ledger",
            record.package_id
        ),
        payload_manifest: payload_manifest.to_vec(),
        provenance: upstream.external_staging_bundle.provenance.clone(),
        citation: upstream.external_staging_bundle.citation.clone(),
        note: "The sandbox deposit bundle preserves real test-registry receipts without crossing into production publication or hiding epistemic pending state.".to_string(),
    }
}

fn build_registry_submission_ledger(
    package_id: &str,
    upstream: &WorkspaceExternalRegistryStagingResponse,
    datacite_receipt: &DataCiteTestReceipt,
    crossref_receipt: &CrossrefTestReceipt,
) -> RegistrySubmissionLedger {
    let entries = vec![
        RegistrySubmissionLedgerEntry {
            registry: datacite_receipt.registry.clone(),
            receipt_ref: format!(
                "workspace-sandbox-deposit:{}:datacite-test-receipt",
                package_id
            ),
            performed_at: datacite_receipt.performed_at,
            target_url: datacite_receipt.target_url.clone(),
            credential_state: datacite_receipt.credential_state.clone(),
            real_network_call_attempted: datacite_receipt.real_network_call_attempted,
            transport_ok: datacite_receipt.transport_ok,
            accepted: datacite_receipt.accepted,
            http_status: datacite_receipt.http_status,
            registry_state: datacite_receipt.registry_state.clone(),
            response_identifier: datacite_receipt.response_identifier.clone(),
            response_summary: datacite_receipt.response_summary.clone(),
        },
        RegistrySubmissionLedgerEntry {
            registry: crossref_receipt.registry.clone(),
            receipt_ref: format!(
                "workspace-sandbox-deposit:{}:crossref-test-receipt",
                package_id
            ),
            performed_at: crossref_receipt.performed_at,
            target_url: crossref_receipt.target_url.clone(),
            credential_state: crossref_receipt.credential_state.clone(),
            real_network_call_attempted: crossref_receipt.real_network_call_attempted,
            transport_ok: crossref_receipt.transport_ok,
            accepted: crossref_receipt.accepted,
            http_status: crossref_receipt.http_status,
            registry_state: crossref_receipt.registry_state.clone(),
            response_identifier: crossref_receipt.response_identifier.clone(),
            response_summary: crossref_receipt.response_summary.clone(),
        },
    ];
    let live_network_attempt_count = entries
        .iter()
        .filter(|entry| entry.real_network_call_attempted)
        .count();
    let live_registry_response_count = entries
        .iter()
        .filter(|entry| entry.transport_ok && entry.http_status.is_some())
        .count();
    let accepted_submission_count = entries.iter().filter(|entry| entry.accepted).count();
    let auth_blocked_submission_count = entries
        .iter()
        .filter(|entry| entry.registry_state == "auth-blocked")
        .count();

    RegistrySubmissionLedger {
        ledger_profile: REGISTRY_SUBMISSION_LEDGER_PROFILE.to_string(),
        ledger_id: format!("{}-registry-ledger", package_id),
        workstream_id: upstream.package.workstream_id.clone(),
        workspace_id: upstream.package.workspace_id.clone(),
        session_id: upstream.package.session_id.clone(),
        campaign_id: upstream.package.campaign_id.clone(),
        package_id: package_id.to_string(),
        readiness_state: upstream.package.readiness_state.clone(),
        registry_handshake_state: derive_registry_handshake_state(datacite_receipt, crossref_receipt),
        submission_count: entries.len(),
        live_network_attempt_count,
        live_registry_response_count,
        accepted_submission_count,
        auth_blocked_submission_count,
        entries,
        note: "The registry submission ledger records sandbox handshake receipts exactly as observed, including auth-blocked or accepted states.".to_string(),
    }
}

fn derive_registry_handshake_state(
    datacite_receipt: &DataCiteTestReceipt,
    crossref_receipt: &CrossrefTestReceipt,
) -> String {
    let receipts = [
        datacite_receipt.transport_ok && datacite_receipt.http_status.is_some(),
        crossref_receipt.transport_ok && crossref_receipt.http_status.is_some(),
    ];
    let all_live = receipts.iter().all(|value| *value);
    let any_transport_failed = !all_live;
    let all_accepted = datacite_receipt.accepted && crossref_receipt.accepted;
    let any_auth_blocked = datacite_receipt.registry_state == "auth-blocked"
        || crossref_receipt.registry_state == "auth-blocked";

    if all_accepted {
        "live-accepted".to_string()
    } else if all_live && any_auth_blocked {
        "live-auth-blocked".to_string()
    } else if all_live {
        "live-with-nonaccepting-receipts".to_string()
    } else if any_transport_failed {
        "transport-failed".to_string()
    } else {
        "unknown".to_string()
    }
}

fn perform_datacite_test_handshake(
    payload: &DataCiteTestStagingPayload,
    readiness_state: &str,
) -> DataCiteTestReceipt {
    if !sandbox_network_enabled() {
        return DataCiteTestReceipt {
            receipt_profile: DATACITE_TEST_RECEIPT_PROFILE.to_string(),
            registry: "datacite-test".to_string(),
            receipt_id: format!("datacite-test-disabled-{}", Utc::now().timestamp_millis()),
            target_url: format!("{}{}", datacite_test_api_base_url(), payload.request_path),
            request_method: payload.request_method.clone(),
            performed_at: Utc::now(),
            credential_state: "network-disabled-for-tests".to_string(),
            real_network_call_attempted: false,
            transport_ok: false,
            accepted: false,
            http_status: None,
            registry_state: "network-disabled".to_string(),
            response_content_type: None,
            response_identifier: None,
            response_summary: "sandbox network disabled for local tests".to_string(),
            response_body_excerpt: String::new(),
            readiness_state: readiness_state.to_string(),
            note: "Set BEAGLE_SANDBOX_DEPOSIT_NETWORK=true to execute live sandbox handshakes.".to_string(),
        };
    }

    let credential = test_credential(
        DATACITE_TEST_USERNAME_ENV,
        DATACITE_TEST_PASSWORD_ENV,
        true,
    );
    let target_url = format!("{}{}", datacite_test_api_base_url(), payload.request_path);
    let body = match serde_json::to_vec(&payload.payload) {
        Ok(bytes) => bytes,
        Err(error) => {
            return transport_failed_datacite_receipt(
                target_url,
                readiness_state,
                credential.state,
                format!("failed to serialize DataCite payload: {error}"),
            )
        }
    };

    let client = match Client::builder().timeout(Duration::from_secs(20)).build() {
        Ok(client) => client,
        Err(error) => {
            return transport_failed_datacite_receipt(
                target_url,
                readiness_state,
                credential.state,
                format!("failed to build HTTP client: {error}"),
            )
        }
    };

    let response = client
        .post(&target_url)
        .basic_auth(credential.username, Some(credential.password))
        .header(CONTENT_TYPE, "application/vnd.api+json")
        .header(ACCEPT, "application/vnd.api+json")
        .body(body)
        .send();

    match response {
        Ok(response) => {
            let status = response.status().as_u16();
            let content_type = response
                .headers()
                .get(CONTENT_TYPE)
                .and_then(|value| value.to_str().ok())
                .map(|value| value.to_string());
            let body = response.text().unwrap_or_default();
            let parsed = serde_json::from_str::<serde_json::Value>(&body).ok();
            let response_identifier = parsed
                .as_ref()
                .and_then(|value| value.pointer("/data/id").and_then(|value| value.as_str()))
                .map(|value| value.to_string())
                .or_else(|| {
                    parsed.as_ref().and_then(|value| {
                        value
                            .pointer("/data/attributes/doi")
                            .and_then(|value| value.as_str())
                            .map(|value| value.to_string())
                    })
                });
            let response_summary = parsed
                .as_ref()
                .and_then(|value| {
                    value
                        .pointer("/errors/0/title")
                        .and_then(|value| value.as_str())
                        .map(|value| value.to_string())
                })
                .or_else(|| {
                    parsed.as_ref().and_then(|value| {
                        value
                            .pointer("/data/attributes/state")
                            .and_then(|value| value.as_str())
                            .map(|value| format!("state={value}"))
                    })
                })
                .unwrap_or_else(|| clip_text(&body, 240));
            let accepted = (200..300).contains(&status);
            let registry_state = map_registry_state(status, accepted);
            let credential_state = finalize_credential_state(&credential.state, status, accepted);

            DataCiteTestReceipt {
                receipt_profile: DATACITE_TEST_RECEIPT_PROFILE.to_string(),
                registry: "datacite-test".to_string(),
                receipt_id: format!("datacite-test-{}", Utc::now().timestamp_millis()),
                target_url,
                request_method: payload.request_method.clone(),
                performed_at: Utc::now(),
                credential_state,
                real_network_call_attempted: true,
                transport_ok: true,
                accepted,
                http_status: Some(status),
                registry_state,
                response_content_type: content_type,
                response_identifier,
                response_summary,
                response_body_excerpt: clip_text(&body, 600),
                readiness_state: readiness_state.to_string(),
                note: "Live POST executed against the DataCite test API; acceptance depends on repository test credentials and payload validity.".to_string(),
            }
        }
        Err(error) => transport_failed_datacite_receipt(
            target_url,
            readiness_state,
            credential.state,
            error.to_string(),
        ),
    }
}

fn transport_failed_datacite_receipt(
    target_url: String,
    readiness_state: &str,
    credential_state: String,
    detail: String,
) -> DataCiteTestReceipt {
    DataCiteTestReceipt {
        receipt_profile: DATACITE_TEST_RECEIPT_PROFILE.to_string(),
        registry: "datacite-test".to_string(),
        receipt_id: format!("datacite-test-transport-{}", Utc::now().timestamp_millis()),
        target_url,
        request_method: "POST".to_string(),
        performed_at: Utc::now(),
        credential_state,
        real_network_call_attempted: true,
        transport_ok: false,
        accepted: false,
        http_status: None,
        registry_state: "transport-failed".to_string(),
        response_content_type: None,
        response_identifier: None,
        response_summary: "transport failed".to_string(),
        response_body_excerpt: clip_text(&detail, 600),
        readiness_state: readiness_state.to_string(),
        note: "The DataCite test API was targeted, but no HTTP receipt was obtained.".to_string(),
    }
}

fn perform_crossref_test_handshake(
    bundle: &CrossrefDryRunBundle,
    readiness_state: &str,
) -> CrossrefTestReceipt {
    if !sandbox_network_enabled() {
        return CrossrefTestReceipt {
            receipt_profile: CROSSREF_TEST_RECEIPT_PROFILE.to_string(),
            registry: "crossref-test".to_string(),
            receipt_id: format!("crossref-test-disabled-{}", Utc::now().timestamp_millis()),
            target_url: crossref_test_deposit_url(),
            request_method: "POST".to_string(),
            performed_at: Utc::now(),
            credential_state: "network-disabled-for-tests".to_string(),
            real_network_call_attempted: false,
            transport_ok: false,
            accepted: false,
            http_status: None,
            registry_state: "network-disabled".to_string(),
            response_content_type: None,
            response_identifier: None,
            response_summary: "sandbox network disabled for local tests".to_string(),
            response_body_excerpt: String::new(),
            readiness_state: readiness_state.to_string(),
            note: "Set BEAGLE_SANDBOX_DEPOSIT_NETWORK=true to execute live sandbox handshakes.".to_string(),
        };
    }

    let credential = test_credential(
        CROSSREF_TEST_USERNAME_ENV,
        CROSSREF_TEST_PASSWORD_ENV,
        false,
    );
    let target_url = crossref_test_deposit_url();
    let client = match Client::builder().timeout(Duration::from_secs(20)).build() {
        Ok(client) => client,
        Err(error) => {
            return transport_failed_crossref_receipt(
                target_url,
                readiness_state,
                credential.state,
                format!("failed to build HTTP client: {error}"),
            )
        }
    };

    let part = match multipart::Part::text(bundle.xml_bundle.clone())
        .file_name("beagle-crossref.xml")
        .mime_str("application/xml")
    {
        Ok(part) => part,
        Err(error) => {
            return transport_failed_crossref_receipt(
                target_url,
                readiness_state,
                credential.state,
                format!("failed to build Crossref multipart payload: {error}"),
            )
        }
    };
    let form = multipart::Form::new()
        .text("operation", "doMDUpload")
        .text("login_id", credential.username.clone())
        .text("login_passwd", credential.password.clone())
        .part("fname", part);

    let response = client.post(&target_url).multipart(form).send();
    match response {
        Ok(response) => {
            let status = response.status().as_u16();
            let content_type = response
                .headers()
                .get(CONTENT_TYPE)
                .and_then(|value| value.to_str().ok())
                .map(|value| value.to_string());
            let body = response.text().unwrap_or_default();
            let response_summary = extract_tag(&body, "h2")
                .or_else(|| extract_tag(&body, "title"))
                .unwrap_or_else(|| clip_text(&body, 240));
            let response_identifier = extract_tag(&body, "batch_id")
                .or_else(|| extract_tag(&body, "doi_batch_id"));
            let accepted = (200..300).contains(&status)
                && !body.to_ascii_lowercase().contains("failure");
            let registry_state = map_registry_state(status, accepted);
            let credential_state = finalize_credential_state(&credential.state, status, accepted);

            CrossrefTestReceipt {
                receipt_profile: CROSSREF_TEST_RECEIPT_PROFILE.to_string(),
                registry: "crossref-test".to_string(),
                receipt_id: format!("crossref-test-{}", Utc::now().timestamp_millis()),
                target_url,
                request_method: "POST".to_string(),
                performed_at: Utc::now(),
                credential_state,
                real_network_call_attempted: true,
                transport_ok: true,
                accepted,
                http_status: Some(status),
                registry_state,
                response_content_type: content_type,
                response_identifier,
                response_summary,
                response_body_excerpt: clip_text(&body, 600),
                readiness_state: readiness_state.to_string(),
                note: "Live POST executed against the Crossref test deposit endpoint; acceptance depends on member test credentials and XML validity.".to_string(),
            }
        }
        Err(error) => transport_failed_crossref_receipt(
            target_url,
            readiness_state,
            credential.state,
            error.to_string(),
        ),
    }
}

fn transport_failed_crossref_receipt(
    target_url: String,
    readiness_state: &str,
    credential_state: String,
    detail: String,
) -> CrossrefTestReceipt {
    CrossrefTestReceipt {
        receipt_profile: CROSSREF_TEST_RECEIPT_PROFILE.to_string(),
        registry: "crossref-test".to_string(),
        receipt_id: format!("crossref-test-transport-{}", Utc::now().timestamp_millis()),
        target_url,
        request_method: "POST".to_string(),
        performed_at: Utc::now(),
        credential_state,
        real_network_call_attempted: true,
        transport_ok: false,
        accepted: false,
        http_status: None,
        registry_state: "transport-failed".to_string(),
        response_content_type: None,
        response_identifier: None,
        response_summary: "transport failed".to_string(),
        response_body_excerpt: clip_text(&detail, 600),
        readiness_state: readiness_state.to_string(),
        note: "The Crossref test endpoint was targeted, but no HTTP receipt was obtained.".to_string(),
    }
}

#[derive(Debug, Clone)]
struct TestCredential {
    username: String,
    password: String,
    state: String,
}

fn test_credential(username_env: &str, password_env: &str, allow_no_auth: bool) -> TestCredential {
    let username = env::var(username_env).ok().map(|value| value.trim().to_string());
    let password = env::var(password_env).ok().map(|value| value.trim().to_string());

    match (username, password) {
        (Some(username), Some(password))
            if !username.is_empty()
                && !password.is_empty()
                && !is_placeholder_value(&username)
                && !is_placeholder_value(&password) =>
        {
            TestCredential {
                username,
                password,
                state: "provided-test-credentials".to_string(),
            }
        }
        (Some(username), Some(password))
            if !username.is_empty() && !password.is_empty() && !allow_no_auth =>
        {
            TestCredential {
                username: PLACEHOLDER_REGISTRY_USER.to_string(),
                password: PLACEHOLDER_REGISTRY_PASSWORD.to_string(),
                state: if is_placeholder_value(&username) || is_placeholder_value(&password) {
                    "placeholder-test-credentials".to_string()
                } else {
                    "missing-test-credentials".to_string()
                },
            }
        }
        _ => TestCredential {
            username: PLACEHOLDER_REGISTRY_USER.to_string(),
            password: PLACEHOLDER_REGISTRY_PASSWORD.to_string(),
            state: "missing-test-credentials".to_string(),
        },
    }
}

fn datacite_test_api_base_url() -> String {
    env::var(DATACITE_TEST_API_BASE_ENV)
        .ok()
        .map(|value| value.trim().to_string())
        .filter(|value| !value.is_empty())
        .unwrap_or_else(|| DEFAULT_DATACITE_TEST_API_BASE_URL.to_string())
}

fn crossref_test_deposit_url() -> String {
    env::var(CROSSREF_TEST_DEPOSIT_URL_ENV)
        .ok()
        .map(|value| value.trim().to_string())
        .filter(|value| !value.is_empty())
        .unwrap_or_else(|| DEFAULT_CROSSREF_TEST_DEPOSIT_URL.to_string())
}

fn sandbox_network_enabled() -> bool {
    env::var(SANDBOX_NETWORK_ENV)
        .ok()
        .map(|value| {
            let normalized = value.trim().to_ascii_lowercase();
            !matches!(normalized.as_str(), "0" | "false" | "no" | "off")
        })
        .unwrap_or(true)
}

fn map_registry_state(status: u16, accepted: bool) -> String {
    if accepted {
        "accepted".to_string()
    } else if status == 401 || status == 403 {
        "auth-blocked".to_string()
    } else if (400..500).contains(&status) {
        "request-rejected".to_string()
    } else if status >= 500 {
        "endpoint-error".to_string()
    } else {
        "nonaccepting-response".to_string()
    }
}

fn finalize_credential_state(state: &str, status: u16, accepted: bool) -> String {
    if accepted && state == "provided-test-credentials" {
        "provided-test-credentials-accepted".to_string()
    } else if (status == 401 || status == 403) && state == "provided-test-credentials" {
        "provided-test-credentials-rejected".to_string()
    } else {
        state.to_string()
    }
}

fn is_placeholder_value(value: &str) -> bool {
    let normalized = value.trim().to_ascii_lowercase();
    normalized.is_empty()
        || matches!(
            normalized.as_str(),
            "replace-me" | "dummy" | "placeholder" | "beagle-placeholder"
        )
}

fn clip_text(value: &str, max_chars: usize) -> String {
    let trimmed = value.split_whitespace().collect::<Vec<_>>().join(" ");
    if trimmed.chars().count() <= max_chars {
        trimmed
    } else {
        let mut clipped = trimmed.chars().take(max_chars).collect::<String>();
        clipped.push_str("...");
        clipped
    }
}

fn extract_tag(body: &str, tag: &str) -> Option<String> {
    let open = format!("<{tag}>");
    let close = format!("</{tag}>");
    let start = body.find(&open)? + open.len();
    let end = body[start..].find(&close)? + start;
    Some(body[start..end].trim().to_string())
}

fn write_sandbox_deposit_record(
    data_dir: &Path,
    workspace_id: &str,
    record: &WorkspaceSandboxDepositHandshakeRecord,
) -> anyhow::Result<()> {
    let path = sandbox_deposit_record_path(data_dir, workspace_id);
    if let Some(parent) = path.parent() {
        fs::create_dir_all(parent)
            .with_context(|| format!("create sandbox deposit directory {}", parent.display()))?;
    }
    let payload = serde_json::to_vec_pretty(record)
        .context("serialize sandbox deposit record")?;
    fs::write(&path, payload)
        .with_context(|| format!("write sandbox deposit record {}", path.display()))?;
    Ok(())
}

fn read_sandbox_deposit_record(
    data_dir: &Path,
    workspace_id: &str,
) -> anyhow::Result<Option<WorkspaceSandboxDepositHandshakeRecord>> {
    let path = sandbox_deposit_record_path(data_dir, workspace_id);
    if !path.exists() {
        return Ok(None);
    }
    let bytes =
        fs::read(&path).with_context(|| format!("read sandbox deposit record {}", path.display()))?;
    let record = serde_json::from_slice(&bytes)
        .with_context(|| format!("parse sandbox deposit record {}", path.display()))?;
    Ok(Some(record))
}

fn sandbox_deposit_record_path(data_dir: &Path, workspace_id: &str) -> PathBuf {
    workspace_sandbox_deposit_dir(data_dir).join(format!(
        "{}.json",
        sanitize_component(workspace_id)
    ))
}

fn workspace_sandbox_deposit_dir(data_dir: &Path) -> PathBuf {
    crate::workspace_plane::workspace_plane_dir(data_dir).join("sandbox-deposit-handshake")
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
    use crate::workspace_external_registry_staging::{
        record_workspace_external_registry_staging, WorkspaceExternalRegistryStagingRequest,
    };
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

    struct EnvGuard {
        key: &'static str,
        previous: Option<String>,
    }

    impl EnvGuard {
        fn set(key: &'static str, value: &str) -> Self {
            let previous = env::var(key).ok();
            unsafe { env::set_var(key, value) };
            Self { key, previous }
        }
    }

    impl Drop for EnvGuard {
        fn drop(&mut self) {
            if let Some(previous) = self.previous.as_ref() {
                unsafe { env::set_var(self.key, previous) };
            } else {
                unsafe { env::remove_var(self.key) };
            }
        }
    }

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
                        source_phase: Some("B21.5".to_string()),
                        source_run_id: Some("b215-external-registry-dry-run".to_string()),
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
                    snippet: "Execute real sandbox registry handshakes without crossing into production publication.".to_string(),
                    timestamp: None,
                    relevance: 0.92,
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
    ) -> (WorkstreamContextPacketResponse, WorkspaceExternalRegistryStagingResponse) {
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
        let _publication = record_workspace_publication_package(
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
        let external_staging = record_workspace_external_registry_staging(
            data_dir,
            cfg,
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
        (context_packet, external_staging)
    }

    #[test]
    fn workspace_sandbox_deposit_handshake_records_live_receipt_shapes_with_same_identity() {
        let temp_root = env::temp_dir().join(format!(
            "beagle-b216-test-{}",
            Utc::now()
                .timestamp_nanos_opt()
                .unwrap_or_else(|| Utc::now().timestamp_micros() * 1000)
        ));
        fs::create_dir_all(&temp_root).expect("create temp dir");
        let cfg = test_config(&temp_root);
        let _network_guard = EnvGuard::set(SANDBOX_NETWORK_ENV, "false");
        let (context_packet, external_staging) = seed_upstream(&temp_root, &cfg);

        let response = record_workspace_sandbox_deposit_handshake(
            &temp_root,
            &cfg,
            "beagle-darwin-hpc-governance",
            context_packet,
            WorkspaceSandboxDepositHandshakeRequest {
                source_subagent_id: "manuscript",
                requested_tool_id: Some("claude-code"),
                handshake_goal:
                    "Execute real sandbox registry handshakes without crossing into production publication.",
                summary:
                    "Freeze the canonical campaign as a registry-facing sandbox handshake package.",
                handshake_notes:
                    "Keep receipts and readiness explicit even when credentials are absent.",
            },
        )
        .expect("record sandbox deposit handshake");

        assert_eq!(response.package.workstream_id, external_staging.package.workstream_id);
        assert_eq!(response.package.workspace_id, external_staging.package.workspace_id);
        assert_eq!(response.package.session_id, external_staging.package.session_id);
        assert_eq!(response.package.source_subagent_id, "manuscript");
        assert_eq!(
            response.package.registry_handshake_state,
            "transport-failed"
        );
        assert_eq!(
            response.datacite_test_receipt.registry_state,
            "network-disabled"
        );
        assert_eq!(
            response.crossref_test_receipt.registry_state,
            "network-disabled"
        );
        assert_eq!(
            response.registry_submission_ledger.submission_count,
            2
        );
    }

    #[test]
    fn workspace_sandbox_deposit_handshake_latest_survives_restart_shaping() {
        let temp_root = env::temp_dir().join(format!(
            "beagle-b216-restart-{}",
            Utc::now()
                .timestamp_nanos_opt()
                .unwrap_or_else(|| Utc::now().timestamp_micros() * 1000)
        ));
        fs::create_dir_all(&temp_root).expect("create temp dir");
        let cfg = test_config(&temp_root);
        let _network_guard = EnvGuard::set(SANDBOX_NETWORK_ENV, "false");
        let (context_packet, _external_staging) = seed_upstream(&temp_root, &cfg);

        let recorded = record_workspace_sandbox_deposit_handshake(
            &temp_root,
            &cfg,
            "beagle-darwin-hpc-governance",
            context_packet.clone(),
            WorkspaceSandboxDepositHandshakeRequest {
                source_subagent_id: "manuscript",
                requested_tool_id: Some("claude-code"),
                handshake_goal:
                    "Execute real sandbox registry handshakes without crossing into production publication.",
                summary:
                    "Freeze the canonical campaign as a registry-facing sandbox handshake package.",
                handshake_notes:
                    "Keep receipts and readiness explicit even when credentials are absent.",
            },
        )
        .expect("record sandbox deposit handshake");

        let shaped = read_workspace_sandbox_deposit_handshake(
            &temp_root,
            &cfg,
            "beagle-darwin-hpc-governance",
            context_packet,
        )
        .expect("shape sandbox deposit")
        .expect("sandbox deposit present");

        assert_eq!(shaped.package.package_id, recorded.package.package_id);
        assert_eq!(
            shaped.package.upstream_external_staging_id,
            recorded.package.upstream_external_staging_id
        );
        assert_eq!(
            shaped.datacite_test_receipt.registry_state,
            recorded.datacite_test_receipt.registry_state
        );
        assert_eq!(
            shaped.crossref_test_receipt.registry_state,
            recorded.crossref_test_receipt.registry_state
        );
        assert_eq!(
            shaped.registry_submission_ledger.registry_handshake_state,
            recorded.registry_submission_ledger.registry_handshake_state
        );
        assert!(shaped.continuity.restart_recovered_session);
    }
}
