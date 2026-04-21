use crate::claim_layer::{build_campaign_claims, build_campaign_manuscript_pack};
use crate::evidence_pack::build_campaign_evidence_pack;
use crate::program_context_packet::{
    build_program_context_packet, resolve_campaign_context_binding,
};
use crate::workspace_plane::workspace_plane_dir;
use crate::workspace_subagent_handoff::{
    read_workspace_subagent_handoff, record_workspace_subagent_handoff,
    WorkspaceSubAgentHandoffRequest,
};
use crate::workspace_subagent_routing::{
    build_workstream_workspace_subagent_route, WorkspaceSubAgentRoutePlane,
    WorkspaceSubAgentRouteRequest,
};
use crate::workspace_subagents::{
    build_workstream_workspace_subagents, WorkspaceSubAgentRole, WorkspaceSubAgentsPlane,
};
use crate::{
    CampaignClaimsResponse, EvidencePack, ManuscriptPack, ProgramContextPacket,
    WorkstreamContextPacket, WorkstreamContextPacketResponse,
};
use anyhow::{anyhow, Context};
use beagle_config::BeagleConfig;
use chrono::{DateTime, Utc};
use serde::{Deserialize, Serialize};
use std::fs;
use std::path::{Path, PathBuf};

const WORKSPACE_MANUSCRIPT_HANDOFF_PHASE: &str = "B21.1";
const WORKSPACE_MANUSCRIPT_HANDOFF_VERSION: &str =
    "beagle-evidence-to-manuscript-loop-v1";
const WORKSPACE_MANUSCRIPT_HANDOFF_KIND: &str = "workspace-manuscript-handoff";
const WORKSPACE_SUBAGENT_API_PREFIX: &str = "/api/darwin/workstreams";
const CAMPAIGN_API_PREFIX: &str = "/api/darwin/campaigns";
const PROGRAM_API_PREFIX: &str = "/api/darwin/programs";

#[derive(Debug, Clone, Serialize, Deserialize)]
struct WorkspaceManuscriptHandoffRecord {
    manuscript_handoff_version: String,
    manuscript_handoff_id: String,
    workstream_id: String,
    workspace_id: String,
    session_id: String,
    source_subagent_id: String,
    source_role_tag: String,
    target_subagent_id: String,
    target_role_tag: String,
    requested_work_mode: String,
    requested_tool_id: Option<String>,
    intent: String,
    summary: String,
    manuscript_goal: String,
    upstream_handoff_id: String,
    upstream_source_subagent_id: String,
    upstream_target_subagent_id: String,
    subagent_handoff_id: String,
    subagent_handoff_text: String,
    recorded_at: DateTime<Utc>,
    program_id: String,
    campaign_id: String,
    managed_attach_state: String,
    stable_attach_alias: String,
}

#[derive(Debug, Clone)]
pub struct WorkspaceManuscriptHandoffRequest<'a> {
    pub source_subagent_id: &'a str,
    pub requested_work_mode: Option<&'a str>,
    pub requested_tool_id: Option<&'a str>,
    pub intent: &'a str,
    pub summary: &'a str,
    pub manuscript_goal: &'a str,
}

#[derive(Debug, Clone, Serialize)]
pub struct WorkspaceManuscriptHandoffPlane {
    pub manuscript_handoff_version: String,
    pub manuscript_handoff_kind: String,
    pub manuscript_handoff_id: String,
    pub workstream_id: String,
    pub workspace_id: String,
    pub session_id: String,
    pub handoff_state: String,
    pub recorded_at: DateTime<Utc>,
    pub source_subagent_id: String,
    pub source_role_tag: String,
    pub target_subagent_id: String,
    pub target_role_tag: String,
    pub requested_work_mode: String,
    pub requested_tool_id: Option<String>,
    pub intent: String,
    pub summary: String,
    pub manuscript_goal: String,
    pub upstream_handoff_id: String,
    pub upstream_source_subagent_id: String,
    pub upstream_target_subagent_id: String,
    pub subagent_handoff_id: String,
    pub subagent_handoff_text: String,
    pub workspace_manuscript_handoff_path: String,
    pub workspace_subagent_handoff_ref: String,
    pub upstream_handoff_ref: String,
    pub workspace_subagent_list_path: String,
    pub target_route_path: String,
    pub program_context_packet_ref: String,
    pub campaign_context_packet_ref: String,
    pub evidence_pack_ref: String,
    pub claims_ref: String,
    pub manuscript_pack_ref: String,
    pub program_id: String,
    pub campaign_id: String,
    pub manuscript_target_id: Option<String>,
    pub readiness_state: String,
    pub managed_attach_state: String,
    pub stable_attach_alias: String,
    pub note: String,
}

#[derive(Debug, Clone, Serialize)]
pub struct WorkspaceManuscriptHandoffContinuity {
    pub handoff_present: bool,
    pub propagated_handoff: Option<String>,
    pub last_result_available: bool,
    pub latest_physio_source: Option<String>,
    pub experiment_id: Option<String>,
    pub memory_hit_count: usize,
    pub result_ref_count: usize,
    pub memory_ref_count: usize,
    pub physio_ref_count: usize,
    pub recipe_ref_count: usize,
    pub claim_count: usize,
    pub supported_claim_count: usize,
    pub claim_ids: Vec<String>,
    pub manuscript_pack_id: String,
    pub manuscript_title: String,
    pub manuscript_gap_count: usize,
    pub manuscript_readiness_state: String,
    pub source_env_file: String,
    pub target_env_file: String,
    pub source_workspace_folder: String,
    pub target_workspace_folder: String,
    pub source_shell_entry_hint: String,
    pub target_shell_entry_hint: String,
}

#[derive(Debug, Clone, Serialize)]
pub struct WorkspaceManuscriptHandoffResponse {
    pub status: String,
    pub phase: String,
    pub manuscript_handoff: WorkspaceManuscriptHandoffPlane,
    pub continuity: WorkspaceManuscriptHandoffContinuity,
    pub source_role: WorkspaceSubAgentRole,
    pub target_role: WorkspaceSubAgentRole,
    pub target_route: WorkspaceSubAgentRoutePlane,
    pub subagents: WorkspaceSubAgentsPlane,
    pub context_packet: WorkstreamContextPacket,
    pub program_context: ProgramContextPacket,
    pub evidence_pack: EvidencePack,
    pub claims: CampaignClaimsResponse,
    pub manuscript_pack: ManuscriptPack,
}

pub fn record_workspace_manuscript_handoff(
    data_dir: &Path,
    cfg: &BeagleConfig,
    workstream_id: &str,
    context_packet: WorkstreamContextPacketResponse,
    request: WorkspaceManuscriptHandoffRequest<'_>,
) -> anyhow::Result<WorkspaceManuscriptHandoffResponse> {
    let upstream = read_workspace_subagent_handoff(data_dir, cfg, workstream_id, context_packet.clone())?
        .ok_or_else(|| anyhow!("an upstream cross-subagent handoff is required before manuscript continuity"))?;
    let source_subagent_id = normalize_selector(request.source_subagent_id);
    if upstream.handoff.target_subagent_id != source_subagent_id {
        return Err(anyhow!(
            "upstream handoff must target source sub-agent '{}' before manuscript continuity",
            source_subagent_id
        ));
    }

    let requested_work_mode = request
        .requested_work_mode
        .map(normalize_selector)
        .filter(|value| !value.is_empty())
        .unwrap_or_else(|| "manuscript".to_string());
    let requested_tool_id = request
        .requested_tool_id
        .map(normalize_selector)
        .filter(|value| !value.is_empty())
        .or_else(|| Some("claude-code".to_string()));
    let intent = normalize_sentence(request.intent);
    let summary = normalize_sentence(request.summary);
    let manuscript_goal = normalize_sentence(request.manuscript_goal);
    if intent.is_empty() {
        return Err(anyhow!("manuscript handoff intent must not be empty"));
    }
    if summary.is_empty() {
        return Err(anyhow!("manuscript handoff summary must not be empty"));
    }
    if manuscript_goal.is_empty() {
        return Err(anyhow!("manuscript handoff goal must not be empty"));
    }

    let subagent_handoff = record_workspace_subagent_handoff(
        data_dir,
        cfg,
        workstream_id,
        context_packet,
        WorkspaceSubAgentHandoffRequest {
            source_subagent_id: &source_subagent_id,
            target_subagent_id: "manuscript",
            requested_work_mode: Some(&requested_work_mode),
            requested_tool_id: requested_tool_id.as_deref(),
            intent: &intent,
            summary: &summary,
        },
    )?;

    let binding = resolve_campaign_context_binding(
        &resolve_campaign_id(workstream_id, &subagent_handoff.context_packet)?,
    )?;
    let record = WorkspaceManuscriptHandoffRecord {
        manuscript_handoff_version: WORKSPACE_MANUSCRIPT_HANDOFF_VERSION.to_string(),
        manuscript_handoff_id: format!(
            "{}-manuscript-{}",
            sanitize_component(&subagent_handoff.context_packet.session_id),
            Utc::now().timestamp_millis()
        ),
        workstream_id: subagent_handoff.context_packet.workstream_id.clone(),
        workspace_id: subagent_handoff.context_packet.workspace_id.clone(),
        session_id: subagent_handoff.context_packet.session_id.clone(),
        source_subagent_id: subagent_handoff.source_role.subagent_id.clone(),
        source_role_tag: subagent_handoff.source_role.role_tag.clone(),
        target_subagent_id: subagent_handoff.target_role.subagent_id.clone(),
        target_role_tag: subagent_handoff.target_role.role_tag.clone(),
        requested_work_mode,
        requested_tool_id,
        intent,
        summary,
        manuscript_goal,
        upstream_handoff_id: upstream.handoff.handoff_id.clone(),
        upstream_source_subagent_id: upstream.handoff.source_subagent_id.clone(),
        upstream_target_subagent_id: upstream.handoff.target_subagent_id.clone(),
        subagent_handoff_id: subagent_handoff.handoff.handoff_id.clone(),
        subagent_handoff_text: subagent_handoff.handoff.handoff_text.clone(),
        recorded_at: Utc::now(),
        program_id: binding.program.id.clone(),
        campaign_id: binding.campaign.id.clone(),
        managed_attach_state: subagent_handoff.handoff.managed_attach_state.clone(),
        stable_attach_alias: subagent_handoff.handoff.stable_attach_alias.clone(),
    };
    write_manuscript_handoff_record(data_dir, &record.workspace_id, &record)?;

    response_from_state(
        cfg,
        workstream_id,
        WorkstreamContextPacketResponse {
            status: "ok".to_string(),
            phase: WORKSPACE_MANUSCRIPT_HANDOFF_PHASE.to_string(),
            packet: subagent_handoff.context_packet,
        },
        record,
    )
}

pub fn read_workspace_manuscript_handoff(
    data_dir: &Path,
    cfg: &BeagleConfig,
    workstream_id: &str,
    mut context_packet: WorkstreamContextPacketResponse,
) -> anyhow::Result<Option<WorkspaceManuscriptHandoffResponse>> {
    let Some(record) = read_manuscript_handoff_record(data_dir, &context_packet.packet.workspace_id)? else {
        return Ok(None);
    };
    overlay_context_packet_handoff(&mut context_packet.packet, &record.subagent_handoff_text);
    Ok(Some(response_from_state(
        cfg,
        workstream_id,
        context_packet,
        record,
    )?))
}

fn response_from_state(
    cfg: &BeagleConfig,
    workstream_id: &str,
    mut context_packet: WorkstreamContextPacketResponse,
    record: WorkspaceManuscriptHandoffRecord,
) -> anyhow::Result<WorkspaceManuscriptHandoffResponse> {
    overlay_context_packet_handoff(&mut context_packet.packet, &record.subagent_handoff_text);
    let subagents_response =
        build_workstream_workspace_subagents(cfg, workstream_id, context_packet.clone())?;
    let source_role = find_role(&subagents_response.subagents.roles, &record.source_subagent_id)?.clone();
    let target_role = find_role(&subagents_response.subagents.roles, &record.target_subagent_id)?.clone();
    let target_route = build_workstream_workspace_subagent_route(
        cfg,
        workstream_id,
        context_packet.clone(),
        WorkspaceSubAgentRouteRequest {
            tool_id: record.requested_tool_id.as_deref(),
            work_mode: Some(&record.requested_work_mode),
            preferred_subagent: Some(&record.target_subagent_id),
        },
    )?;
    let binding = resolve_campaign_context_binding(&record.campaign_id)?;
    let program_context =
        build_program_context_packet(&binding, &[context_packet.packet.clone()])?;
    let evidence_response = build_campaign_evidence_pack(&binding, &program_context.packet)?;
    let claims_response =
        build_campaign_claims(&binding, &program_context.packet, &evidence_response)?;
    let manuscript_response =
        build_campaign_manuscript_pack(&binding, &program_context.packet, &evidence_response)?;

    let evidence_pack_ref = format!(
        "{}/{}/evidence-pack",
        CAMPAIGN_API_PREFIX, record.campaign_id
    );
    let claims_ref = format!("{}/{}/claims", CAMPAIGN_API_PREFIX, record.campaign_id);
    let manuscript_pack_ref = format!(
        "{}/{}/manuscript-pack",
        CAMPAIGN_API_PREFIX, record.campaign_id
    );
    let workspace_manuscript_handoff_path = format!(
        "{}/{}/workspace-manuscript-handoff",
        WORKSPACE_SUBAGENT_API_PREFIX, record.workstream_id
    );
    let workspace_subagent_list_path = format!(
        "{}/{}/workspace-subagent-list",
        WORKSPACE_SUBAGENT_API_PREFIX, record.workstream_id
    );
    let program_context_packet_ref = format!(
        "{}/{}/context-packet",
        PROGRAM_API_PREFIX, record.program_id
    );
    let campaign_context_packet_ref = format!(
        "{}/{}/context-packet",
        CAMPAIGN_API_PREFIX, record.campaign_id
    );
    let supported_claim_count = claims_response
        .claims
        .iter()
        .filter(|claim| claim.claim_state == "supported")
        .count();
    let continuity = WorkspaceManuscriptHandoffContinuity {
        handoff_present: true,
        propagated_handoff: context_packet.packet.handoff.last_handoff.clone(),
        last_result_available: context_packet.packet.last_result.available,
        latest_physio_source: context_packet
            .packet
            .latest_physio
            .as_ref()
            .and_then(|physio| physio.source.clone()),
        experiment_id: context_packet
            .packet
            .experiment_flags
            .as_ref()
            .and_then(|flags| flags.experiment_id.clone()),
        memory_hit_count: context_packet.packet.memory_hits.len(),
        result_ref_count: evidence_response.pack.result_refs.len(),
        memory_ref_count: evidence_response.pack.memory_refs.len(),
        physio_ref_count: evidence_response.pack.physio_refs.len(),
        recipe_ref_count: evidence_response.pack.recipe_refs.len(),
        claim_count: claims_response.claims.len(),
        supported_claim_count,
        claim_ids: claims_response
            .claims
            .iter()
            .map(|claim| claim.claim_id.clone())
            .collect(),
        manuscript_pack_id: manuscript_response.pack.pack_id.clone(),
        manuscript_title: manuscript_response.pack.title.clone(),
        manuscript_gap_count: manuscript_response.pack.gaps.len(),
        manuscript_readiness_state: manuscript_response.pack.readiness_state.clone(),
        source_env_file: source_role.env_file.clone(),
        target_env_file: target_role.env_file.clone(),
        source_workspace_folder: source_role.workspace_folder.clone(),
        target_workspace_folder: target_role.workspace_folder.clone(),
        source_shell_entry_hint: source_role.shell_entry_hint.clone(),
        target_shell_entry_hint: target_role.shell_entry_hint.clone(),
    };
    let manuscript_handoff = WorkspaceManuscriptHandoffPlane {
        manuscript_handoff_version: record.manuscript_handoff_version.clone(),
        manuscript_handoff_kind: WORKSPACE_MANUSCRIPT_HANDOFF_KIND.to_string(),
        manuscript_handoff_id: record.manuscript_handoff_id.clone(),
        workstream_id: record.workstream_id.clone(),
        workspace_id: record.workspace_id.clone(),
        session_id: record.session_id.clone(),
        handoff_state: "recorded".to_string(),
        recorded_at: record.recorded_at,
        source_subagent_id: record.source_subagent_id.clone(),
        source_role_tag: record.source_role_tag.clone(),
        target_subagent_id: record.target_subagent_id.clone(),
        target_role_tag: record.target_role_tag.clone(),
        requested_work_mode: record.requested_work_mode.clone(),
        requested_tool_id: record.requested_tool_id.clone(),
        intent: record.intent.clone(),
        summary: record.summary.clone(),
        manuscript_goal: record.manuscript_goal.clone(),
        upstream_handoff_id: record.upstream_handoff_id.clone(),
        upstream_source_subagent_id: record.upstream_source_subagent_id.clone(),
        upstream_target_subagent_id: record.upstream_target_subagent_id.clone(),
        subagent_handoff_id: record.subagent_handoff_id.clone(),
        subagent_handoff_text: record.subagent_handoff_text.clone(),
        workspace_manuscript_handoff_path,
        workspace_subagent_handoff_ref: format!(
            "workspace-subagent-handoff:{}",
            record.subagent_handoff_id
        ),
        upstream_handoff_ref: format!(
            "workspace-subagent-handoff:{}",
            record.upstream_handoff_id
        ),
        workspace_subagent_list_path,
        target_route_path: target_route.route.workspace_subagent_route_path.clone(),
        program_context_packet_ref,
        campaign_context_packet_ref,
        evidence_pack_ref,
        claims_ref,
        manuscript_pack_ref,
        program_id: record.program_id.clone(),
        campaign_id: record.campaign_id.clone(),
        manuscript_target_id: manuscript_response
            .pack
            .manuscript_target
            .as_ref()
            .map(|target| target.id.clone()),
        readiness_state: manuscript_response.pack.readiness_state.clone(),
        managed_attach_state: record.managed_attach_state.clone(),
        stable_attach_alias: record.stable_attach_alias.clone(),
        note: "The manuscript handoff keeps one Beagle-owned session/workspace identity while converting bounded experiment context into bounded campaign manuscript work.".to_string(),
    };

    Ok(WorkspaceManuscriptHandoffResponse {
        status: "ok".to_string(),
        phase: WORKSPACE_MANUSCRIPT_HANDOFF_PHASE.to_string(),
        manuscript_handoff,
        continuity,
        source_role,
        target_role,
        target_route: target_route.route,
        subagents: subagents_response.subagents,
        context_packet: context_packet.packet,
        program_context: program_context.packet,
        evidence_pack: evidence_response.pack,
        claims: claims_response,
        manuscript_pack: manuscript_response.pack,
    })
}

fn resolve_campaign_id(
    workstream_id: &str,
    context_packet: &WorkstreamContextPacket,
) -> anyhow::Result<String> {
    let binding = crate::program_context_packet::resolve_program_campaign_binding_for_workstream(
        workstream_id,
    )?
    .ok_or_else(|| {
        anyhow!(
            "no canonical program/campaign binding found for workstream '{}'",
            workstream_id
        )
    })?;
    if binding.campaign.workstreams.iter().any(|entry| entry.id == context_packet.workstream_id) {
        return Ok(binding.campaign.id);
    }
    Err(anyhow!(
        "resolved campaign does not include workstream '{}'",
        context_packet.workstream_id
    ))
}

fn overlay_context_packet_handoff(packet: &mut WorkstreamContextPacket, handoff_text: &str) {
    packet.handoff.handoff_present = true;
    packet.handoff.last_handoff = Some(handoff_text.to_string());
}

fn manuscript_handoff_records_dir(data_dir: &Path) -> PathBuf {
    workspace_plane_dir(data_dir).join("manuscript-handoffs")
}

fn manuscript_handoff_record_path(data_dir: &Path, workspace_id: &str) -> PathBuf {
    manuscript_handoff_records_dir(data_dir)
        .join(format!("{}.json", sanitize_component(workspace_id)))
}

fn write_manuscript_handoff_record(
    data_dir: &Path,
    workspace_id: &str,
    record: &WorkspaceManuscriptHandoffRecord,
) -> anyhow::Result<()> {
    let dir = manuscript_handoff_records_dir(data_dir);
    fs::create_dir_all(&dir).with_context(|| {
        format!(
            "failed to create manuscript handoff dir {}",
            dir.display()
        )
    })?;
    let path = manuscript_handoff_record_path(data_dir, workspace_id);
    let body = serde_json::to_string_pretty(record)?;
    fs::write(&path, body).with_context(|| {
        format!(
            "failed to write manuscript handoff record {}",
            path.display()
        )
    })
}

fn read_manuscript_handoff_record(
    data_dir: &Path,
    workspace_id: &str,
) -> anyhow::Result<Option<WorkspaceManuscriptHandoffRecord>> {
    let path = manuscript_handoff_record_path(data_dir, workspace_id);
    if !path.exists() {
        return Ok(None);
    }
    let body = fs::read_to_string(&path).with_context(|| {
        format!(
            "failed to read manuscript handoff record {}",
            path.display()
        )
    })?;
    let record = serde_json::from_str::<WorkspaceManuscriptHandoffRecord>(&body).with_context(
        || {
            format!(
                "failed to parse manuscript handoff record {}",
                path.display()
            )
        },
    )?;
    Ok(Some(record))
}

fn find_role<'a>(
    roles: &'a [WorkspaceSubAgentRole],
    subagent_id: &str,
) -> anyhow::Result<&'a WorkspaceSubAgentRole> {
    roles
        .iter()
        .find(|role| role.subagent_id == subagent_id)
        .ok_or_else(|| anyhow!("unknown sub-agent '{}'", subagent_id))
}

fn normalize_selector(value: &str) -> String {
    value.trim().to_ascii_lowercase()
}

fn normalize_sentence(value: &str) -> String {
    value
        .trim()
        .split_whitespace()
        .collect::<Vec<_>>()
        .join(" ")
}

fn sanitize_component(value: &str) -> String {
    let sanitized = value
        .chars()
        .map(|ch| {
            if ch.is_ascii_alphanumeric() || matches!(ch, '-' | '_') {
                ch
            } else {
                '-'
            }
        })
        .collect::<String>();
    sanitized.trim_matches('-').to_string()
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::workspace_plane::{write_workspace_session, WorkspaceSessionState};
    use crate::workspace_subagent_handoff::record_workspace_subagent_handoff;
    use crate::{
        WorkstreamContextPacketExperimentFlags, WorkstreamContextPacketHandoff,
        WorkstreamContextPacketLastResult, WorkstreamContextPacketMemoryHit,
        WorkstreamContextPacketPhysioSnapshot, WorkstreamContextPacketRecipe,
        WorkstreamContextPacketResultSummary,
    };
    use beagle_config::{
        AdvancedModulesConfig, BeagleConfig, ConsumerAccessConfig, GraphConfig, HermesConfig,
        LlmConfig, ObserverThresholds, StorageConfig, ToolBridgeConfig, WorkspaceHabitatConfig,
        WorkspacePlaneConfig,
    };
    use std::{env, path::PathBuf};

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
                        source_phase: Some("B20.8".to_string()),
                        source_run_id: Some("b208-role-aware-routing".to_string()),
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
                    snippet: "Shift the same bounded campaign from experiments interpretation into manuscript assembly.".to_string(),
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

    #[test]
    fn workspace_manuscript_handoff_records_experiments_to_manuscript_with_same_identity() {
        let data_dir = temp_data_dir("workspace-manuscript-handoff");
        let cfg = test_config(&data_dir);
        seed_workspace_session(&data_dir, &cfg);

        record_workspace_subagent_handoff(
            &data_dir,
            &cfg,
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

        let response = record_workspace_manuscript_handoff(
            &data_dir,
            &cfg,
            "beagle-darwin-hpc-governance",
            packet(),
            WorkspaceManuscriptHandoffRequest {
                source_subagent_id: "experiments",
                requested_work_mode: Some("manuscript"),
                requested_tool_id: Some("claude-code"),
                intent: "manuscript",
                summary: "Shift the experiments interpretation into manuscript drafting.",
                manuscript_goal: "Freeze a bounded manuscript-oriented packet for the active campaign.",
            },
        )
        .expect("manuscript handoff");

        assert_eq!(response.phase, "B21.1");
        assert_eq!(
            response.manuscript_handoff.workstream_id,
            "beagle-darwin-hpc-governance"
        );
        assert_eq!(response.manuscript_handoff.workspace_id, "beagle-cluster-pilot");
        assert_eq!(
            response.manuscript_handoff.session_id,
            "ws-cluster-workspace-habitat"
        );
        assert_eq!(response.manuscript_handoff.source_subagent_id, "experiments");
        assert_eq!(response.manuscript_handoff.target_subagent_id, "manuscript");
        assert_eq!(response.target_route.selection.selected_subagent_id, "manuscript");
        assert_eq!(response.target_role.role_tag, "manuscript-authoring");
        assert_eq!(response.continuity.claim_count, response.claims.claims.len());
        assert_eq!(response.manuscript_pack.claim_ids, response.continuity.claim_ids);
        assert_eq!(response.evidence_pack.campaign_id, response.claims.campaign_id);
        assert_eq!(response.evidence_pack.campaign_id, response.manuscript_pack.campaign_id);
        assert_eq!(
            response.context_packet.handoff.last_handoff.as_deref(),
            Some(response.manuscript_handoff.subagent_handoff_text.as_str())
        );
    }

    #[test]
    fn workspace_manuscript_handoff_latest_survives_restart_shaping() {
        let data_dir = temp_data_dir("workspace-manuscript-handoff-restart");
        let cfg = test_config(&data_dir);
        seed_workspace_session(&data_dir, &cfg);

        record_workspace_subagent_handoff(
            &data_dir,
            &cfg,
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

        let recorded = record_workspace_manuscript_handoff(
            &data_dir,
            &cfg,
            "beagle-darwin-hpc-governance",
            packet(),
            WorkspaceManuscriptHandoffRequest {
                source_subagent_id: "experiments",
                requested_work_mode: Some("manuscript"),
                requested_tool_id: Some("claude-code"),
                intent: "manuscript",
                summary: "Shift the experiments interpretation into manuscript drafting.",
                manuscript_goal: "Freeze a bounded manuscript-oriented packet for the active campaign.",
            },
        )
        .expect("record manuscript handoff");

        let shaped = read_workspace_manuscript_handoff(
            &data_dir,
            &cfg,
            "beagle-darwin-hpc-governance",
            packet(),
        )
        .expect("read manuscript handoff")
        .expect("manuscript handoff present");

        assert_eq!(
            shaped.manuscript_handoff.manuscript_handoff_id,
            recorded.manuscript_handoff.manuscript_handoff_id
        );
        assert_eq!(
            shaped.manuscript_handoff.upstream_handoff_id,
            recorded.manuscript_handoff.upstream_handoff_id
        );
        assert_eq!(shaped.manuscript_handoff.session_id, "ws-cluster-workspace-habitat");
        assert_eq!(shaped.target_route.selection.selected_subagent_id, "manuscript");
        assert_eq!(
            shaped.manuscript_handoff.manuscript_pack_ref,
            recorded.manuscript_handoff.manuscript_pack_ref
        );
        assert_eq!(
            shaped.context_packet.handoff.last_handoff,
            recorded.context_packet.handoff.last_handoff
        );
    }
}
