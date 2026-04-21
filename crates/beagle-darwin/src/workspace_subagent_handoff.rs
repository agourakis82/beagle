use crate::workspace_plane::{load_workspace_session, workspace_plane_dir, write_workspace_session};
use crate::workspace_subagent_routing::{
    build_workstream_workspace_subagent_route, WorkspaceSubAgentRoutePlane,
    WorkspaceSubAgentRouteRequest,
};
use crate::workspace_subagents::{
    build_workstream_workspace_subagents, WorkspaceSubAgentRole, WorkspaceSubAgentsPlane,
};
use crate::{WorkstreamContextPacket, WorkstreamContextPacketResponse};
use anyhow::{anyhow, Context};
use beagle_config::BeagleConfig;
use chrono::{DateTime, Utc};
use serde::{Deserialize, Serialize};
use std::fs;
use std::path::{Path, PathBuf};

const WORKSPACE_SUBAGENT_HANDOFF_PHASE: &str = "B20.9";
const WORKSPACE_SUBAGENT_HANDOFF_VERSION: &str = "beagle-cross-subagent-session-handoff-v1";
const WORKSPACE_SUBAGENT_HANDOFF_KIND: &str = "workspace-subagent-handoff";
const WORKSPACE_SUBAGENT_API_PREFIX: &str = "/api/darwin/workstreams";

#[derive(Debug, Clone, Serialize, Deserialize)]
struct WorkspaceSubAgentHandoffRecord {
    handoff_version: String,
    handoff_id: String,
    workstream_id: String,
    workspace_id: String,
    session_id: String,
    source_subagent_id: String,
    source_role_tag: String,
    target_subagent_id: String,
    target_role_tag: String,
    requested_work_mode: Option<String>,
    requested_tool_id: Option<String>,
    intent: String,
    summary: String,
    handoff_text: String,
    recorded_at: DateTime<Utc>,
    managed_attach_state: String,
    stable_attach_alias: String,
}

#[derive(Debug, Clone)]
pub struct WorkspaceSubAgentHandoffRequest<'a> {
    pub source_subagent_id: &'a str,
    pub target_subagent_id: &'a str,
    pub requested_work_mode: Option<&'a str>,
    pub requested_tool_id: Option<&'a str>,
    pub intent: &'a str,
    pub summary: &'a str,
}

#[derive(Debug, Clone, Serialize)]
pub struct WorkspaceSubAgentHandoffPlane {
    pub handoff_version: String,
    pub handoff_kind: String,
    pub handoff_id: String,
    pub workstream_id: String,
    pub workspace_id: String,
    pub session_id: String,
    pub handoff_state: String,
    pub recorded_at: DateTime<Utc>,
    pub source_subagent_id: String,
    pub source_role_tag: String,
    pub target_subagent_id: String,
    pub target_role_tag: String,
    pub requested_work_mode: Option<String>,
    pub requested_tool_id: Option<String>,
    pub intent: String,
    pub summary: String,
    pub handoff_text: String,
    pub workspace_subagent_handoff_path: String,
    pub workspace_subagent_list_path: String,
    pub target_route_path: String,
    pub context_packet_ref: String,
    pub managed_attach_state: String,
    pub stable_attach_alias: String,
    pub note: String,
}

#[derive(Debug, Clone, Serialize)]
pub struct WorkspaceSubAgentHandoffPropagation {
    pub handoff_present: bool,
    pub propagated_handoff: Option<String>,
    pub last_result_available: bool,
    pub last_result_run_label: Option<String>,
    pub last_result_manifest_key: Option<String>,
    pub recommended_recipe_id: Option<String>,
    pub latest_physio_source: Option<String>,
    pub experiment_id: Option<String>,
    pub memory_hit_count: usize,
    pub retrieval_context_present: bool,
    pub retrieval_memory_ids: Vec<String>,
    pub retrieval_suggested_subagent_id: Option<String>,
    pub retrieval_suggested_work_mode: Option<String>,
    pub retrieval_influence_reason: Option<String>,
    pub compiled_context_present: bool,
    pub compiled_context_task_profile: Option<String>,
    pub compiled_context_budget_profile_id: Option<String>,
    pub compiled_context_top_memory_ids: Vec<String>,
    pub compiled_context_preview: Option<String>,
    pub execution_state_present: bool,
    pub execution_plan_id: Option<String>,
    pub execution_current_state: Option<String>,
    pub execution_receipt_id: Option<String>,
    pub execution_reflection_present: bool,
    pub execution_quality_score: Option<u8>,
    pub execution_replan_required: bool,
    pub execution_operator_followup_action: Option<String>,
    pub execution_review_requested: bool,
    pub execution_review_inbox_state: Option<String>,
    pub execution_review_inbox_item_id: Option<String>,
    pub execution_review_decision_id: Option<String>,
    pub execution_review_decision_action: Option<String>,
    pub execution_follow_on_plan_id: Option<String>,
    pub execution_follow_on_plan_available: bool,
    pub execution_approval_gating_decision_id: Option<String>,
    pub execution_approval_gating_decision_class: Option<String>,
    pub execution_approval_gating_dispatch_ready: bool,
    pub execution_approval_gating_blocked: bool,
    pub execution_continuation_dispatched: bool,
    pub execution_continuation_current_state: Option<String>,
    pub execution_continuation_dispatch_id: Option<String>,
    pub execution_continuation_receipt_id: Option<String>,
    pub execution_continuation_next_execution_id: Option<String>,
    pub source_env_file: String,
    pub target_env_file: String,
    pub source_workspace_folder: String,
    pub target_workspace_folder: String,
    pub source_shell_entry_hint: String,
    pub target_shell_entry_hint: String,
}

#[derive(Debug, Clone, Serialize)]
pub struct WorkspaceSubAgentHandoffResponse {
    pub status: String,
    pub phase: String,
    pub handoff: WorkspaceSubAgentHandoffPlane,
    pub propagation: WorkspaceSubAgentHandoffPropagation,
    pub source_role: WorkspaceSubAgentRole,
    pub target_role: WorkspaceSubAgentRole,
    pub target_route: WorkspaceSubAgentRoutePlane,
    pub subagents: WorkspaceSubAgentsPlane,
    pub context_packet: WorkstreamContextPacket,
}

pub fn record_workspace_subagent_handoff(
    data_dir: &Path,
    cfg: &BeagleConfig,
    workstream_id: &str,
    mut context_packet: WorkstreamContextPacketResponse,
    request: WorkspaceSubAgentHandoffRequest<'_>,
) -> anyhow::Result<WorkspaceSubAgentHandoffResponse> {
    let subagents_response =
        build_workstream_workspace_subagents(cfg, workstream_id, context_packet.clone())?;
    let source_subagent_id = normalize_selector(request.source_subagent_id);
    let target_subagent_id = normalize_selector(request.target_subagent_id);
    if source_subagent_id == target_subagent_id {
        return Err(anyhow!("source and target sub-agents must differ"));
    }

    let source_role = find_role(&subagents_response.subagents.roles, &source_subagent_id)?
        .clone();
    let target_role = find_role(&subagents_response.subagents.roles, &target_subagent_id)?
        .clone();

    let requested_work_mode = request.requested_work_mode.map(normalize_selector);
    let requested_tool_id = request.requested_tool_id.map(|value| value.trim().to_ascii_lowercase());
    let recorded_at = Utc::now();
    let intent = normalize_sentence(request.intent);
    let summary = normalize_sentence(request.summary);
    if intent.is_empty() {
        return Err(anyhow!("handoff intent must not be empty"));
    }
    if summary.is_empty() {
        return Err(anyhow!("handoff summary must not be empty"));
    }
    let handoff_text = format!(
        "subagent handoff {} -> {} [{}]: {}",
        source_role.subagent_id, target_role.subagent_id, intent, summary
    );
    let handoff_id = format!(
        "{}-{}-{}",
        sanitize_component(&context_packet.packet.session_id),
        sanitize_component(&source_role.subagent_id),
        recorded_at.timestamp_millis()
    );

    persist_workspace_session_handoff(
        data_dir,
        cfg,
        &context_packet.packet.workspace_id,
        &context_packet.packet.session_id,
        &handoff_text,
        recorded_at,
    )?;

    let record = WorkspaceSubAgentHandoffRecord {
        handoff_version: WORKSPACE_SUBAGENT_HANDOFF_VERSION.to_string(),
        handoff_id: handoff_id.clone(),
        workstream_id: context_packet.packet.workstream_id.clone(),
        workspace_id: context_packet.packet.workspace_id.clone(),
        session_id: context_packet.packet.session_id.clone(),
        source_subagent_id: source_role.subagent_id.clone(),
        source_role_tag: source_role.role_tag.clone(),
        target_subagent_id: target_role.subagent_id.clone(),
        target_role_tag: target_role.role_tag.clone(),
        requested_work_mode,
        requested_tool_id,
        intent,
        summary,
        handoff_text: handoff_text.clone(),
        recorded_at,
        managed_attach_state: target_role.managed_attach_state.clone(),
        stable_attach_alias: target_role.stable_attach_alias.clone(),
    };
    write_handoff_record(data_dir, &context_packet.packet.workspace_id, &record)?;

    overlay_context_packet_handoff(&mut context_packet.packet, &handoff_text);

    response_from_state(cfg, workstream_id, context_packet, subagents_response.subagents, record)
}

pub fn read_workspace_subagent_handoff(
    data_dir: &Path,
    cfg: &BeagleConfig,
    workstream_id: &str,
    mut context_packet: WorkstreamContextPacketResponse,
) -> anyhow::Result<Option<WorkspaceSubAgentHandoffResponse>> {
    let Some(record) = read_handoff_record(data_dir, &context_packet.packet.workspace_id)? else {
        return Ok(None);
    };
    let subagents_response =
        build_workstream_workspace_subagents(cfg, workstream_id, context_packet.clone())?;
    overlay_context_packet_handoff(&mut context_packet.packet, &record.handoff_text);
    Ok(Some(response_from_state(
        cfg,
        workstream_id,
        context_packet,
        subagents_response.subagents,
        record,
    )?))
}

fn response_from_state(
    cfg: &BeagleConfig,
    workstream_id: &str,
    context_packet: WorkstreamContextPacketResponse,
    subagents: WorkspaceSubAgentsPlane,
    record: WorkspaceSubAgentHandoffRecord,
) -> anyhow::Result<WorkspaceSubAgentHandoffResponse> {
    let source_role = find_role(&subagents.roles, &record.source_subagent_id)?.clone();
    let target_role = find_role(&subagents.roles, &record.target_subagent_id)?.clone();
    let target_route = build_workstream_workspace_subagent_route(
        cfg,
        workstream_id,
        context_packet.clone(),
        WorkspaceSubAgentRouteRequest {
            tool_id: record.requested_tool_id.as_deref(),
            work_mode: record.requested_work_mode.as_deref(),
            preferred_subagent: Some(&record.target_subagent_id),
        },
    )?;

    let handoff_path = format!(
        "{}/{}/workspace-subagent-handoff",
        WORKSPACE_SUBAGENT_API_PREFIX, context_packet.packet.workstream_id
    );
    let list_path = format!(
        "{}/{}/workspace-subagent-list",
        WORKSPACE_SUBAGENT_API_PREFIX, context_packet.packet.workstream_id
    );
    let context_packet_ref = format!(
        "{}/{}/context-packet",
        WORKSPACE_SUBAGENT_API_PREFIX, context_packet.packet.workstream_id
    );
    let target_route_path = format!(
        "{}?preferred_subagent={}",
        target_route.route.workspace_subagent_route_path, record.target_subagent_id
    );
    let propagation = WorkspaceSubAgentHandoffPropagation {
        handoff_present: true,
        propagated_handoff: context_packet.packet.handoff.last_handoff.clone(),
        last_result_available: context_packet.packet.last_result.available,
        last_result_run_label: context_packet
            .packet
            .last_result
            .summary
            .as_ref()
            .map(|summary| summary.run_label.clone()),
        last_result_manifest_key: context_packet
            .packet
            .last_result
            .summary
            .as_ref()
            .map(|summary| summary.manifest_key.clone()),
        recommended_recipe_id: context_packet
            .packet
            .recommended_recipe
            .as_ref()
            .map(|recipe| recipe.id.clone()),
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
        retrieval_context_present: context_packet.packet.retrieval_context.is_some(),
        retrieval_memory_ids: context_packet
            .packet
            .retrieval_context
            .as_ref()
            .map(|context| context.top_memory_ids.clone())
            .unwrap_or_default(),
        retrieval_suggested_subagent_id: context_packet
            .packet
            .retrieval_context
            .as_ref()
            .and_then(|context| context.suggested_subagent_id.clone()),
        retrieval_suggested_work_mode: context_packet
            .packet
            .retrieval_context
            .as_ref()
            .and_then(|context| context.suggested_work_mode.clone()),
        retrieval_influence_reason: context_packet
            .packet
            .retrieval_context
            .as_ref()
            .map(|context| context.influence_reason.clone()),
        compiled_context_present: context_packet
            .packet
            .retrieval_context
            .as_ref()
            .and_then(|context| context.compiled_context_task_profile.as_ref())
            .is_some(),
        compiled_context_task_profile: context_packet
            .packet
            .retrieval_context
            .as_ref()
            .and_then(|context| context.compiled_context_task_profile.clone()),
        compiled_context_budget_profile_id: context_packet
            .packet
            .retrieval_context
            .as_ref()
            .and_then(|context| context.compiled_context_budget_profile_id.clone()),
        compiled_context_top_memory_ids: context_packet
            .packet
            .retrieval_context
            .as_ref()
            .map(|context| context.compiled_context_top_memory_ids.clone())
            .unwrap_or_default(),
        compiled_context_preview: context_packet
            .packet
            .retrieval_context
            .as_ref()
            .and_then(|context| context.compiled_context_preview.clone()),
        execution_state_present: context_packet
            .packet
            .retrieval_context
            .as_ref()
            .and_then(|context| context.execution.as_ref())
            .is_some(),
        execution_plan_id: context_packet
            .packet
            .retrieval_context
            .as_ref()
            .and_then(|context| context.execution.as_ref())
            .map(|execution| execution.plan_id.clone()),
        execution_current_state: context_packet
            .packet
            .retrieval_context
            .as_ref()
            .and_then(|context| context.execution.as_ref())
            .map(|execution| execution.current_state.clone()),
        execution_receipt_id: context_packet
            .packet
            .retrieval_context
            .as_ref()
            .and_then(|context| context.execution.as_ref())
            .and_then(|execution| execution.latest_receipt_id.clone()),
        execution_reflection_present: context_packet
            .packet
            .retrieval_context
            .as_ref()
            .and_then(|context| context.execution.as_ref())
            .map(|execution| execution.reflection_available)
            .unwrap_or(false),
        execution_quality_score: context_packet
            .packet
            .retrieval_context
            .as_ref()
            .and_then(|context| context.execution.as_ref())
            .and_then(|execution| execution.latest_quality_score),
        execution_replan_required: context_packet
            .packet
            .retrieval_context
            .as_ref()
            .and_then(|context| context.execution.as_ref())
            .map(|execution| execution.replan_required)
            .unwrap_or(false),
        execution_operator_followup_action: context_packet
            .packet
            .retrieval_context
            .as_ref()
            .and_then(|context| context.execution.as_ref())
            .and_then(|execution| execution.operator_followup_action.clone()),
        execution_review_requested: context_packet
            .packet
            .retrieval_context
            .as_ref()
            .and_then(|context| context.execution.as_ref())
            .map(|execution| execution.review_requested)
            .unwrap_or(false),
        execution_review_inbox_state: context_packet
            .packet
            .retrieval_context
            .as_ref()
            .and_then(|context| context.execution.as_ref())
            .and_then(|execution| execution.review_inbox_state.clone()),
        execution_review_inbox_item_id: context_packet
            .packet
            .retrieval_context
            .as_ref()
            .and_then(|context| context.execution.as_ref())
            .and_then(|execution| execution.latest_review_inbox_item_id.clone()),
        execution_review_decision_id: context_packet
            .packet
            .retrieval_context
            .as_ref()
            .and_then(|context| context.execution.as_ref())
            .and_then(|execution| execution.latest_review_decision_id.clone()),
        execution_review_decision_action: context_packet
            .packet
            .retrieval_context
            .as_ref()
            .and_then(|context| context.execution.as_ref())
            .and_then(|execution| execution.latest_review_decision_action.clone()),
        execution_follow_on_plan_id: context_packet
            .packet
            .retrieval_context
            .as_ref()
            .and_then(|context| context.execution.as_ref())
            .and_then(|execution| execution.latest_follow_on_plan_id.clone()),
        execution_follow_on_plan_available: context_packet
            .packet
            .retrieval_context
            .as_ref()
            .and_then(|context| context.execution.as_ref())
            .map(|execution| execution.follow_on_plan_available)
            .unwrap_or(false),
        execution_approval_gating_decision_id: context_packet
            .packet
            .retrieval_context
            .as_ref()
            .and_then(|context| context.execution.as_ref())
            .and_then(|execution| execution.latest_approval_gating_decision_id.clone()),
        execution_approval_gating_decision_class: context_packet
            .packet
            .retrieval_context
            .as_ref()
            .and_then(|context| context.execution.as_ref())
            .and_then(|execution| execution.approval_gating_decision_class.clone()),
        execution_approval_gating_dispatch_ready: context_packet
            .packet
            .retrieval_context
            .as_ref()
            .and_then(|context| context.execution.as_ref())
            .map(|execution| execution.approval_gating_dispatch_ready)
            .unwrap_or(false),
        execution_approval_gating_blocked: context_packet
            .packet
            .retrieval_context
            .as_ref()
            .and_then(|context| context.execution.as_ref())
            .map(|execution| execution.approval_gating_blocked)
            .unwrap_or(false),
        execution_continuation_dispatched: context_packet
            .packet
            .retrieval_context
            .as_ref()
            .and_then(|context| context.execution.as_ref())
            .map(|execution| execution.continuation_dispatched)
            .unwrap_or(false),
        execution_continuation_current_state: context_packet
            .packet
            .retrieval_context
            .as_ref()
            .and_then(|context| context.execution.as_ref())
            .and_then(|execution| execution.continuation_current_state.clone()),
        execution_continuation_dispatch_id: context_packet
            .packet
            .retrieval_context
            .as_ref()
            .and_then(|context| context.execution.as_ref())
            .and_then(|execution| execution.latest_continuation_dispatch_id.clone()),
        execution_continuation_receipt_id: context_packet
            .packet
            .retrieval_context
            .as_ref()
            .and_then(|context| context.execution.as_ref())
            .and_then(|execution| execution.latest_continuation_receipt_id.clone()),
        execution_continuation_next_execution_id: context_packet
            .packet
            .retrieval_context
            .as_ref()
            .and_then(|context| context.execution.as_ref())
            .and_then(|execution| execution.continuation_next_execution_id.clone()),
        source_env_file: source_role.env_file.clone(),
        target_env_file: target_role.env_file.clone(),
        source_workspace_folder: source_role.workspace_folder.clone(),
        target_workspace_folder: target_role.workspace_folder.clone(),
        source_shell_entry_hint: source_role.shell_entry_hint.clone(),
        target_shell_entry_hint: target_role.shell_entry_hint.clone(),
    };
    let handoff = WorkspaceSubAgentHandoffPlane {
        handoff_version: record.handoff_version.clone(),
        handoff_kind: WORKSPACE_SUBAGENT_HANDOFF_KIND.to_string(),
        handoff_id: record.handoff_id.clone(),
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
        handoff_text: record.handoff_text.clone(),
        workspace_subagent_handoff_path: handoff_path,
        workspace_subagent_list_path: list_path,
        target_route_path,
        context_packet_ref,
        managed_attach_state: record.managed_attach_state.clone(),
        stable_attach_alias: record.stable_attach_alias.clone(),
        note: "The cross-subagent handoff keeps one Beagle-owned session/workspace identity while moving bounded intent between specialized inner environments.".to_string(),
    };

    Ok(WorkspaceSubAgentHandoffResponse {
        status: "ok".to_string(),
        phase: WORKSPACE_SUBAGENT_HANDOFF_PHASE.to_string(),
        handoff,
        propagation,
        source_role,
        target_role,
        target_route: target_route.route,
        subagents,
        context_packet: context_packet.packet,
    })
}

fn persist_workspace_session_handoff(
    data_dir: &Path,
    cfg: &BeagleConfig,
    workspace_id: &str,
    session_id: &str,
    handoff_text: &str,
    recorded_at: DateTime<Utc>,
) -> anyhow::Result<()> {
    let Some(mut state) = load_workspace_session(data_dir, cfg, workspace_id)? else {
        return Ok(());
    };
    if state.session_id != session_id {
        return Ok(());
    }
    state.last_handoff = Some(handoff_text.to_string());
    state.updated_at = recorded_at;
    write_workspace_session(data_dir, &state)
}

fn overlay_context_packet_handoff(packet: &mut WorkstreamContextPacket, handoff_text: &str) {
    packet.handoff.handoff_present = true;
    packet.handoff.last_handoff = Some(handoff_text.to_string());
}

fn handoff_records_dir(data_dir: &Path) -> PathBuf {
    workspace_plane_dir(data_dir).join("subagent-handoffs")
}

fn handoff_record_path(data_dir: &Path, workspace_id: &str) -> PathBuf {
    handoff_records_dir(data_dir).join(format!("{}.json", sanitize_component(workspace_id)))
}

fn write_handoff_record(
    data_dir: &Path,
    workspace_id: &str,
    record: &WorkspaceSubAgentHandoffRecord,
) -> anyhow::Result<()> {
    let dir = handoff_records_dir(data_dir);
    fs::create_dir_all(&dir)
        .with_context(|| format!("failed to create subagent handoff dir {}", dir.display()))?;
    let path = handoff_record_path(data_dir, workspace_id);
    let body = serde_json::to_string_pretty(record)?;
    fs::write(&path, body)
        .with_context(|| format!("failed to write subagent handoff record {}", path.display()))
}

fn read_handoff_record(
    data_dir: &Path,
    workspace_id: &str,
) -> anyhow::Result<Option<WorkspaceSubAgentHandoffRecord>> {
    let path = handoff_record_path(data_dir, workspace_id);
    if !path.exists() {
        return Ok(None);
    }
    let body = fs::read_to_string(&path)
        .with_context(|| format!("failed to read subagent handoff record {}", path.display()))?;
    let record = serde_json::from_str::<WorkspaceSubAgentHandoffRecord>(&body).with_context(|| {
        format!(
            "failed to parse subagent handoff record {}",
            path.display()
        )
    })?;
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
    value.trim().split_whitespace().collect::<Vec<_>>().join(" ")
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
    use crate::{
        WorkstreamContextPacketExperimentFlags, WorkstreamContextPacketHandoff,
        WorkstreamContextPacketLastResult, WorkstreamContextPacketMemoryHit,
        WorkstreamContextPacketPhysioSnapshot, WorkstreamContextPacketRecipe,
        WorkstreamContextPacketResponse, WorkstreamContextPacketResultSummary,
        WorkspaceSessionState,
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
                    snippet: "Keep one workspace identity while switching to experiments review.".to_string(),
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
            graph: GraphConfig::default(),
            hermes: HermesConfig::default(),
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

    fn seed_workspace_session(data_dir: &Path, cfg: &BeagleConfig) {
        let mut state = WorkspaceSessionState::new(
            cfg,
            "beagle-cluster-pilot".to_string(),
            Some("ws-cluster-workspace-habitat".to_string()),
        );
        state.last_handoff = Some("resume from canonical Beagle workspace state".to_string());
        write_workspace_session(data_dir, &state).unwrap();
    }

    fn temp_data_dir(test_name: &str) -> PathBuf {
        let dir = env::temp_dir().join(format!(
            "beagle-b209-{}-{}",
            test_name,
            Utc::now().timestamp_nanos_opt().unwrap_or_default()
        ));
        fs::create_dir_all(&dir).unwrap();
        dir
    }

    #[test]
    fn workspace_subagent_handoff_records_core_to_experiments_with_same_identity() {
        let dir = temp_data_dir("record");
        let cfg = test_config(&dir);
        seed_workspace_session(&dir, &cfg);

        let response = record_workspace_subagent_handoff(
            &dir,
            &cfg,
            "beagle-darwin-hpc-governance",
            packet(),
            WorkspaceSubAgentHandoffRequest {
                source_subagent_id: "core",
                target_subagent_id: "experiments",
                requested_work_mode: Some("analysis"),
                requested_tool_id: Some("claude-code"),
                intent: "analysis",
                summary: "Shift to experiments review with the current result and handoff.",
            },
        )
        .expect("record handoff");

        assert_eq!(response.phase, "B20.9");
        assert_eq!(response.handoff.workstream_id, "beagle-darwin-hpc-governance");
        assert_eq!(response.handoff.workspace_id, "beagle-cluster-pilot");
        assert_eq!(response.handoff.session_id, "ws-cluster-workspace-habitat");
        assert_eq!(response.handoff.source_subagent_id, "core");
        assert_eq!(response.handoff.target_subagent_id, "experiments");
        assert_eq!(response.target_route.selection.selected_subagent_id, "experiments");
        assert_eq!(
            response.context_packet.handoff.last_handoff.as_deref(),
            Some(response.handoff.handoff_text.as_str())
        );

        let persisted = load_workspace_session(&dir, &cfg, "beagle-cluster-pilot")
            .unwrap()
            .unwrap();
        assert_eq!(
            persisted.last_handoff.as_deref(),
            Some(response.handoff.handoff_text.as_str())
        );
    }

    #[test]
    fn workspace_subagent_handoff_latest_survives_restart_shaping() {
        let dir = temp_data_dir("restart");
        let cfg = test_config(&dir);
        seed_workspace_session(&dir, &cfg);

        let initial = record_workspace_subagent_handoff(
            &dir,
            &cfg,
            "beagle-darwin-hpc-governance",
            packet(),
            WorkspaceSubAgentHandoffRequest {
                source_subagent_id: "core",
                target_subagent_id: "experiments",
                requested_work_mode: Some("analysis"),
                requested_tool_id: Some("claude-code"),
                intent: "analysis",
                summary: "Pass the same bounded session into experiments.",
            },
        )
        .expect("record handoff");

        let recovered = read_workspace_subagent_handoff(
            &dir,
            &cfg,
            "beagle-darwin-hpc-governance",
            packet(),
        )
        .expect("read latest handoff")
        .expect("handoff present");

        assert_eq!(recovered.handoff.handoff_id, initial.handoff.handoff_id);
        assert_eq!(recovered.handoff.target_subagent_id, "experiments");
        assert_eq!(recovered.target_route.selection.selected_subagent_id, "experiments");
        assert_eq!(
            recovered.context_packet.handoff.last_handoff.as_deref(),
            Some(recovered.handoff.handoff_text.as_str())
        );
    }
}
