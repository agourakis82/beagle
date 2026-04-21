use crate::workspace_subagents::{
    build_workstream_workspace_subagents, WorkspaceSubAgentRole, WorkspaceSubAgentsPlane,
    WorkspaceSubAgentsResponse,
};
use crate::{
    IntentPlannerAvailability, PlanExecutionStatusSummary, WorkstreamContextPacket,
    WorkstreamContextPacketResponse,
};
use beagle_config::BeagleConfig;
use serde::Serialize;

const WORKSPACE_SUBAGENT_LIST_PHASE: &str = "B20.8";
const WORKSPACE_SUBAGENT_LIST_VERSION: &str = "beagle-workspace-subagent-list-v1";
const WORKSPACE_SUBAGENT_LIST_KIND: &str = "workspace-subagent-list";
const WORKSPACE_SUBAGENT_ROUTE_VERSION: &str = "beagle-role-aware-subagent-routing-v1";
const WORKSPACE_SUBAGENT_ROUTE_KIND: &str = "workspace-subagent-route";
const WORKSPACE_SUBAGENT_API_PREFIX: &str = "/api/darwin/workstreams";

#[derive(Debug, Clone, Serialize)]
pub struct WorkspaceSubAgentListPlane {
    pub list_version: String,
    pub list_kind: String,
    pub workstream_id: String,
    pub workspace_id: String,
    pub session_id: String,
    pub workspace_subagent_list_path: String,
    pub workspace_subagent_route_path: String,
    pub workspace_subagent_handoff_path: String,
    pub stable_attach_alias: String,
    pub managed_attach_state: String,
    pub roles: Vec<WorkspaceSubAgentRole>,
    pub note: String,
}

#[derive(Debug, Clone, Serialize)]
pub struct WorkspaceSubAgentListResponse {
    pub status: String,
    pub phase: String,
    pub list: WorkspaceSubAgentListPlane,
    pub subagents: WorkspaceSubAgentsPlane,
    pub context_packet: WorkstreamContextPacket,
}

#[derive(Debug, Clone)]
pub struct WorkspaceSubAgentRouteRequest<'a> {
    pub tool_id: Option<&'a str>,
    pub work_mode: Option<&'a str>,
    pub preferred_subagent: Option<&'a str>,
}

#[derive(Debug, Clone, Serialize)]
pub struct WorkspaceSubAgentRouteSelection {
    pub requested_tool_id: Option<String>,
    pub requested_work_mode: Option<String>,
    pub preferred_subagent: Option<String>,
    pub selected_subagent_id: String,
    pub selected_role_tag: String,
    pub selected_specialization: String,
    pub selection_source: String,
    pub route_reason: String,
}

#[derive(Debug, Clone, Serialize)]
pub struct WorkspaceSubAgentRouteAttachMetadata {
    pub attach_method: String,
    pub managed_attach_state: String,
    pub stable_attach_alias: String,
    pub recommended_client: String,
    pub workspace_folder: String,
    pub env_file: String,
    pub devcontainer_config_file: String,
    pub shell_entry_hint: String,
    pub browser_url: String,
    pub managed_attach_path: String,
    pub launch_resume_path: String,
    pub subagent_list_path: String,
    pub subagent_handoff_path: String,
    pub context_packet_ref: String,
    pub cursor_remote_hint: String,
    pub browser_folder_hint: String,
}

#[derive(Debug, Clone, Serialize)]
pub struct WorkspaceSubAgentRoutePlane {
    pub route_version: String,
    pub route_kind: String,
    pub workstream_id: String,
    pub workspace_id: String,
    pub session_id: String,
    pub workspace_subagent_route_path: String,
    pub selection: WorkspaceSubAgentRouteSelection,
    pub attach_metadata: WorkspaceSubAgentRouteAttachMetadata,
    pub planner: Option<IntentPlannerAvailability>,
    pub execution: Option<PlanExecutionStatusSummary>,
    pub note: String,
}

#[derive(Debug, Clone, Serialize)]
pub struct WorkspaceSubAgentRouteResponse {
    pub status: String,
    pub phase: String,
    pub route: WorkspaceSubAgentRoutePlane,
    pub selected_role: WorkspaceSubAgentRole,
    pub subagents: WorkspaceSubAgentsPlane,
    pub context_packet: WorkstreamContextPacket,
}

pub fn default_subagent_for_tool(tool_id: &str) -> &'static str {
    match tool_id.trim().to_ascii_lowercase().as_str() {
        "claude-code" | "claude_code" | "claude" => "experiments",
        "cursor" | "codex" => "core",
        _ => "core",
    }
}

pub fn default_work_mode_for_tool(tool_id: &str) -> &'static str {
    match tool_id.trim().to_ascii_lowercase().as_str() {
        "claude-code" | "claude_code" | "claude" => "analysis",
        "cursor" => "interactive-editing",
        "codex" => "implementation",
        _ => "implementation",
    }
}

pub fn build_workstream_workspace_subagent_list(
    cfg: &BeagleConfig,
    workstream_id: &str,
    context_packet: WorkstreamContextPacketResponse,
) -> anyhow::Result<WorkspaceSubAgentListResponse> {
    let subagents_response = build_workstream_workspace_subagents(cfg, workstream_id, context_packet)?;
    Ok(list_response_from_subagents(subagents_response))
}

pub fn build_workstream_workspace_subagent_route(
    cfg: &BeagleConfig,
    workstream_id: &str,
    context_packet: WorkstreamContextPacketResponse,
    request: WorkspaceSubAgentRouteRequest<'_>,
) -> anyhow::Result<WorkspaceSubAgentRouteResponse> {
    let subagents_response = build_workstream_workspace_subagents(cfg, workstream_id, context_packet)?;
    Ok(route_response_from_subagents(subagents_response, request))
}

fn list_response_from_subagents(
    subagents_response: WorkspaceSubAgentsResponse,
) -> WorkspaceSubAgentListResponse {
    let list_path = format!(
        "{}/{}/workspace-subagent-list",
        WORKSPACE_SUBAGENT_API_PREFIX, subagents_response.subagents.workstream_id
    );
    let route_path = format!(
        "{}/{}/workspace-subagent-route",
        WORKSPACE_SUBAGENT_API_PREFIX, subagents_response.subagents.workstream_id
    );
    let handoff_path = format!(
        "{}/{}/workspace-subagent-handoff",
        WORKSPACE_SUBAGENT_API_PREFIX, subagents_response.subagents.workstream_id
    );
    let list = WorkspaceSubAgentListPlane {
        list_version: WORKSPACE_SUBAGENT_LIST_VERSION.to_string(),
        list_kind: WORKSPACE_SUBAGENT_LIST_KIND.to_string(),
        workstream_id: subagents_response.subagents.workstream_id.clone(),
        workspace_id: subagents_response.subagents.workspace_id.clone(),
        session_id: subagents_response.subagents.session_id.clone(),
        workspace_subagent_list_path: list_path,
        workspace_subagent_route_path: route_path,
        workspace_subagent_handoff_path: handoff_path,
        stable_attach_alias: subagents_response.subagents.stable_attach_alias.clone(),
        managed_attach_state: subagents_response.subagents.managed_attach_state.clone(),
        roles: subagents_response.subagents.roles.clone(),
        note: "The workspace-subagent list freezes role-tagged inner environments while preserving one canonical Beagle-owned workspace/session identity.".to_string(),
    };

    WorkspaceSubAgentListResponse {
        status: "ok".to_string(),
        phase: WORKSPACE_SUBAGENT_LIST_PHASE.to_string(),
        list,
        subagents: subagents_response.subagents,
        context_packet: subagents_response.context_packet,
    }
}

fn route_response_from_subagents(
    subagents_response: WorkspaceSubAgentsResponse,
    request: WorkspaceSubAgentRouteRequest<'_>,
) -> WorkspaceSubAgentRouteResponse {
    let requested_tool_id = request.tool_id.map(|tool| tool.trim().to_ascii_lowercase());
    let requested_work_mode = request.work_mode.map(normalize_selector);
    let preferred_subagent = request
        .preferred_subagent
        .map(|subagent| subagent.trim().to_ascii_lowercase());

    let (selected_role, selection_source, route_reason) = select_role(
        &subagents_response.subagents.roles,
        requested_tool_id.as_deref(),
        requested_work_mode.as_deref(),
        preferred_subagent.as_deref(),
        &subagents_response.context_packet,
    );

    let route_query = route_query_string(
        requested_tool_id.as_deref(),
        requested_work_mode.as_deref(),
        preferred_subagent.as_deref(),
    );
    let route_path = format!(
        "{}/{}/workspace-subagent-route{}",
        WORKSPACE_SUBAGENT_API_PREFIX, subagents_response.subagents.workstream_id, route_query
    );
    let list_path = format!(
        "{}/{}/workspace-subagent-list",
        WORKSPACE_SUBAGENT_API_PREFIX, subagents_response.subagents.workstream_id
    );
    let handoff_path = format!(
        "{}/{}/workspace-subagent-handoff",
        WORKSPACE_SUBAGENT_API_PREFIX, subagents_response.subagents.workstream_id
    );
    let context_packet_ref = format!(
        "{}/{}/context-packet",
        WORKSPACE_SUBAGENT_API_PREFIX, subagents_response.subagents.workstream_id
    );
    let attach_metadata = WorkspaceSubAgentRouteAttachMetadata {
        attach_method: selected_role.attach_method.clone(),
        managed_attach_state: selected_role.managed_attach_state.clone(),
        stable_attach_alias: selected_role.stable_attach_alias.clone(),
        recommended_client: selected_role.recommended_client.clone(),
        workspace_folder: selected_role.workspace_folder.clone(),
        env_file: selected_role.env_file.clone(),
        devcontainer_config_file: selected_role.devcontainer_config_file.clone(),
        shell_entry_hint: selected_role.shell_entry_hint.clone(),
        browser_url: selected_role.browser_url.clone(),
        managed_attach_path: selected_role.managed_attach_path.clone(),
        launch_resume_path: selected_role.launch_resume_path.clone(),
        subagent_list_path: list_path,
        subagent_handoff_path: handoff_path,
        context_packet_ref: context_packet_ref.clone(),
        cursor_remote_hint: format!(
            "Open host '{}' in Cursor Remote-SSH, then use folder '{}' and env file '{}'.",
            selected_role.stable_attach_alias, selected_role.workspace_folder, selected_role.env_file
        ),
        browser_folder_hint: format!(
            "Open '{}' in the shared browser workspace and source '{}'.",
            selected_role.workspace_folder, selected_role.env_file
        ),
    };
    let selection = WorkspaceSubAgentRouteSelection {
        requested_tool_id,
        requested_work_mode,
        preferred_subagent,
        selected_subagent_id: selected_role.subagent_id.clone(),
        selected_role_tag: selected_role.role_tag.clone(),
        selected_specialization: selected_role.specialization.clone(),
        selection_source,
        route_reason,
    };
    let route = WorkspaceSubAgentRoutePlane {
        route_version: WORKSPACE_SUBAGENT_ROUTE_VERSION.to_string(),
        route_kind: WORKSPACE_SUBAGENT_ROUTE_KIND.to_string(),
        workstream_id: subagents_response.subagents.workstream_id.clone(),
        workspace_id: subagents_response.subagents.workspace_id.clone(),
        session_id: subagents_response.subagents.session_id.clone(),
        workspace_subagent_route_path: route_path,
        selection,
        attach_metadata,
        planner: subagents_response
            .context_packet
            .retrieval_context
            .as_ref()
            .and_then(|context| context.planner.clone()),
        execution: subagents_response
            .context_packet
            .retrieval_context
            .as_ref()
            .and_then(|context| context.execution.clone()),
        note: "Role-aware routing only selects the right inner environment for the current work mode; it does not mint a new workspace identity.".to_string(),
    };

    WorkspaceSubAgentRouteResponse {
        status: "ok".to_string(),
        phase: WORKSPACE_SUBAGENT_LIST_PHASE.to_string(),
        route,
        selected_role: selected_role.clone(),
        subagents: subagents_response.subagents,
        context_packet: subagents_response.context_packet,
    }
}

fn select_role<'a>(
    roles: &'a [WorkspaceSubAgentRole],
    requested_tool_id: Option<&str>,
    requested_work_mode: Option<&str>,
    preferred_subagent: Option<&str>,
    context_packet: &WorkstreamContextPacket,
) -> (&'a WorkspaceSubAgentRole, String, String) {
    if let Some(preferred_subagent) = preferred_subagent {
        if let Some(role) = roles
            .iter()
            .find(|role| role.subagent_id.eq_ignore_ascii_case(preferred_subagent))
        {
            return (
                role,
                "preferred-subagent".to_string(),
                format!(
                    "explicit preferred_subagent={} selected the matching role",
                    preferred_subagent
                ),
            );
        }
    }

    if let Some(requested_work_mode) = requested_work_mode {
        if let Some(role) = roles.iter().find(|role| {
            role.recommended_work_modes
                .iter()
                .any(|mode| normalize_selector(mode) == requested_work_mode)
        }) {
            return (
                role,
                "work-mode".to_string(),
                format!(
                    "work_mode={} matched the role-tagged work modes for {}",
                    requested_work_mode, role.subagent_id
                ),
            );
        }
    }

    if let Some((role, route_reason)) =
        select_role_from_retrieval_context(roles, requested_tool_id, context_packet)
    {
        return (
            role,
            "retrieval-context".to_string(),
            route_reason,
        );
    }

    if let Some(requested_tool_id) = requested_tool_id {
        if let Some(role) = roles.iter().find(|role| {
            role.default_tools
                .iter()
                .any(|tool| normalize_selector(tool) == requested_tool_id)
        }) {
            return (
                role,
                "tool-default".to_string(),
                format!(
                    "tool_id={} matched the default tool affinity for {}",
                    requested_tool_id, role.subagent_id
                ),
            );
        }
    }

    let fallback = roles
        .iter()
        .find(|role| role.subagent_id == "core")
        .unwrap_or(&roles[0]);
    (
        fallback,
        "fallback-core".to_string(),
        "no explicit preferred_subagent, work_mode, or tool affinity matched; falling back to core".to_string(),
    )
}

fn select_role_from_retrieval_context<'a>(
    roles: &'a [WorkspaceSubAgentRole],
    requested_tool_id: Option<&str>,
    context_packet: &WorkstreamContextPacket,
) -> Option<(&'a WorkspaceSubAgentRole, String)> {
    let retrieval = context_packet.retrieval_context.as_ref()?;
    let suggested_subagent = retrieval.suggested_subagent_id.as_deref()?;
    let role = roles
        .iter()
        .find(|role| role.subagent_id.eq_ignore_ascii_case(suggested_subagent))?;

    if let Some(requested_tool_id) = requested_tool_id {
        let tool_supported = role
            .default_tools
            .iter()
            .any(|tool| normalize_selector(tool) == requested_tool_id);
        if !tool_supported {
            return None;
        }
    }

    Some((
        role,
        format!(
            "retrieval context suggested {} via {} with top_memory_ids={}",
            role.subagent_id,
            retrieval.influence_reason,
            retrieval.top_memory_ids.join(",")
        ),
    ))
}

fn normalize_selector(value: &str) -> String {
    value.trim().to_ascii_lowercase().replace('_', "-")
}

fn route_query_string(
    requested_tool_id: Option<&str>,
    requested_work_mode: Option<&str>,
    preferred_subagent: Option<&str>,
) -> String {
    let mut parts = Vec::new();
    if let Some(tool_id) = requested_tool_id {
        parts.push(format!("tool_id={}", tool_id));
    }
    if let Some(work_mode) = requested_work_mode {
        parts.push(format!("work_mode={}", work_mode));
    }
    if let Some(preferred_subagent) = preferred_subagent {
        parts.push(format!("preferred_subagent={}", preferred_subagent));
    }
    if parts.is_empty() {
        String::new()
    } else {
        format!("?{}", parts.join("&"))
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::{
        WorkstreamContextPacket, WorkstreamContextPacketExperimentFlags,
        WorkstreamContextPacketHandoff, WorkstreamContextPacketLastResult,
        WorkstreamContextPacketPhysioSnapshot, WorkstreamContextPacketRecipe,
        WorkstreamContextPacketResponse, WorkstreamContextPacketRetrievalContext,
        WorkstreamContextPacketRetrievalFilters,
    };
    use beagle_config::{
        AdvancedModulesConfig, BeagleConfig, ConsumerAccessConfig, GraphConfig, HermesConfig,
        LlmConfig, ObserverThresholds, StorageConfig, ToolBridgeConfig, WorkspaceHabitatConfig,
        WorkspacePlaneConfig,
    };
    use chrono::Utc;

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
                    last_handoff: Some("resume from managed launch".to_string()),
                },
                last_result: WorkstreamContextPacketLastResult {
                    available: false,
                    reference: None,
                    summary: None,
                    manifest: None,
                    error: None,
                },
                last_successful_task: None,
                latest_physio: Some(WorkstreamContextPacketPhysioSnapshot {
                    hr: Some(72.0),
                    hrv_level: Some("steady".to_string()),
                    spo2: Some(98.0),
                    timestamp: Some(Utc::now()),
                    source: Some("observer-smoke".to_string()),
                }),
                experiment_flags: Some(WorkstreamContextPacketExperimentFlags {
                    hrv_aware: Some(true),
                    observer_enabled: Some(true),
                    serendipity_enabled: Some(false),
                    triad_enabled: Some(false),
                    provider: Some("xai".to_string()),
                    model: Some("grok-4-1-fast-reasoning".to_string()),
                    experiment_id: Some("beagle_exp_002_hrv_aware_vs_blind".to_string()),
                    condition: Some("hrv_aware".to_string()),
                }),
                memory_hits: Vec::new(),
                retrieval_context: None,
                recommended_recipe: Some(WorkstreamContextPacketRecipe {
                    id: "beagle-darwin-hpc-governance.operator_cpu_loop".to_string(),
                    kind: "operator_cpu_loop".to_string(),
                    summary: "Resume with the bounded CPU operator loop.".to_string(),
                }),
                bounded_study_baseline: None,
            },
        }
    }

    fn packet_with_retrieval(
        suggested_subagent_id: &str,
        suggested_work_mode: &str,
        influence_reason: &str,
    ) -> WorkstreamContextPacketResponse {
        let mut response = packet();
        response.packet.retrieval_context = Some(WorkstreamContextPacketRetrievalContext {
            query_text: "bounded retrieval-aware route".to_string(),
            query_type: "general".to_string(),
            retrieval_mode: "dense+sparse-hybrid".to_string(),
            dense_backend: "voyage-4-large".to_string(),
            sparse_backend: "local-lexical".to_string(),
            routing_source: "retrieval-context".to_string(),
            routing_reason: "bounded retrieval guidance preferred the manuscript lane".to_string(),
            reranking_applied: true,
            reranking_profile_id: Some("b228-bounded-reranking-pilot".to_string()),
            reranker_backend: Some("voyage-rerank-2.5".to_string()),
            reranker_runtime_state: Some("pilot-active".to_string()),
            reranking_latency_ms: Some(42),
            top_k: 3,
            applied_filters: WorkstreamContextPacketRetrievalFilters {
                workstream_id: Some("beagle-darwin-hpc-governance".to_string()),
                campaign_id: Some("expedition-002-hrv-aware".to_string()),
                session_id: Some("ws-cluster-workspace-habitat".to_string()),
                source: Some("claude-code".to_string()),
                role: Some("assistant".to_string()),
                domain: Some("darwin-hpc".to_string()),
                tags: vec!["manuscript".to_string(), "claims".to_string()],
            },
            hit_count: 2,
            top_memory_ids: vec!["memory-manuscript-1".to_string()],
            top_domains: vec!["darwin-hpc".to_string()],
            top_tags: vec!["manuscript".to_string(), "claims".to_string()],
            promotion_policy_id: Some("b232-memory-promotion-policy".to_string()),
            retention_policy_id: Some("b232-memory-retention-policy".to_string()),
            graphrag_query_mode: Some("local".to_string()),
            graphrag_query_mode_reason: Some(
                "session/workstream scope requested a bounded local GraphRAG neighborhood"
                    .to_string(),
            ),
            graphrag_root_entity_type: Some("workstream".to_string()),
            graphrag_root_entity_id: Some("beagle-darwin-hpc-governance".to_string()),
            graphrag_node_count: 5,
            graphrag_edge_count: 4,
            graphrag_node_types: vec![
                "Workstream".to_string(),
                "Result".to_string(),
                "Claim".to_string(),
                "Manuscript".to_string(),
            ],
            graphrag_edge_types: vec![
                "uses".to_string(),
                "supports".to_string(),
                "appears_in".to_string(),
            ],
            memory_hierarchy_counts: vec![
                crate::WorkstreamContextPacketMemoryHierarchyCount {
                    memory_type: "semantic".to_string(),
                    count: 1,
                },
                crate::WorkstreamContextPacketMemoryHierarchyCount {
                    memory_type: "procedural".to_string(),
                    count: 1,
                },
            ],
            promoted_memory_count: 1,
            promoted_target_memory_types: vec!["procedural".to_string()],
            compiled_context_task_profile: Some("manuscript".to_string()),
            compiled_context_budget_profile_id: Some("b235-budget-manuscript".to_string()),
            compiled_context_retrieval_query_type: Some("general".to_string()),
            compiled_context_graphrag_query_mode: Some("global".to_string()),
            compiled_context_selected_memory_tiers: vec![
                "semantic".to_string(),
                "episodic".to_string(),
                "procedural".to_string(),
            ],
            compiled_context_source_slices: vec![
                crate::CompiledContextSourceSliceSummary {
                    source_kind: "semantic".to_string(),
                    budgeted_items: 4,
                    selected_count: 2,
                    support_ids: vec!["memory-manuscript-1".to_string()],
                },
            ],
            compiled_context_top_memory_ids: vec!["memory-manuscript-1".to_string()],
            compiled_context_preview: Some(
                "task_profile: manuscript\nretrieval_query_type: general".to_string(),
            ),
            planner: None,
            execution: None,
            temporal_truth_view: Some("both".to_string()),
            temporal_subject_refs: vec!["claim:expedition-002-qa-state".to_string()],
            temporal_current_memory_ids: vec!["memory-manuscript-1".to_string()],
            temporal_historical_memory_ids: vec!["memory-manuscript-0".to_string()],
            temporal_track_count: 1,
            temporal_contradiction_count: 1,
            temporal_contradiction_ids: vec!["contradiction-1".to_string()],
            temporal_preview: Some(
                "current truth preserved with one historical contradiction".to_string(),
            ),
            suggested_subagent_id: Some(suggested_subagent_id.to_string()),
            suggested_work_mode: Some(suggested_work_mode.to_string()),
            influence_reason: influence_reason.to_string(),
        });
        response
    }

    fn test_config() -> BeagleConfig {
        let mut cfg = BeagleConfig {
            profile: "cluster".to_string(),
            safe_mode: true,
            api_token: Some("test-token".to_string()),
            llm: LlmConfig::default(),
            storage: StorageConfig {
                data_dir: "/tmp/beagle-workspace-subagent-routing-tests".to_string(),
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

    #[test]
    fn workspace_subagent_list_keeps_same_identity_and_role_tags() {
        let response = build_workstream_workspace_subagent_list(
            &test_config(),
            "beagle-darwin-hpc-governance",
            packet(),
        )
        .expect("subagent list");

        assert_eq!(response.phase, "B20.8");
        assert_eq!(response.list.workstream_id, "beagle-darwin-hpc-governance");
        assert_eq!(response.list.workspace_id, "beagle-cluster-pilot");
        assert_eq!(response.list.session_id, "ws-cluster-workspace-habitat");
        assert_eq!(response.list.roles.len(), 3);
        assert!(response
            .list
            .roles
            .iter()
            .any(|role| role.subagent_id == "core" && role.role_tag == "core-runtime"));
        assert!(response
            .list
            .roles
            .iter()
            .any(|role| role.subagent_id == "experiments" && role.role_tag == "experiments-analysis"));
        assert!(response
            .list
            .roles
            .iter()
            .any(|role| role.subagent_id == "manuscript" && role.role_tag == "manuscript-authoring"));
    }

    #[test]
    fn workspace_subagent_route_selects_core_for_codex_implementation() {
        let response = build_workstream_workspace_subagent_route(
            &test_config(),
            "beagle-darwin-hpc-governance",
            packet(),
            WorkspaceSubAgentRouteRequest {
                tool_id: Some("codex"),
                work_mode: Some("implementation"),
                preferred_subagent: None,
            },
        )
        .expect("subagent route");

        assert_eq!(response.phase, "B20.8");
        assert_eq!(response.route.selection.selected_subagent_id, "core");
        assert_eq!(response.route.selection.selection_source, "work-mode");
        assert_eq!(response.route.attach_metadata.workspace_folder, "/workspace/beagle");
        assert_eq!(
            response.route.attach_metadata.devcontainer_config_file,
            "/workspace/beagle/.devcontainer/beagle-core/devcontainer.json"
        );
        assert!(response
            .route
            .attach_metadata
            .cursor_remote_hint
            .contains("beagle-cluster-pilot.coder"));
    }

    #[test]
    fn workspace_subagent_route_selects_experiments_for_claude_analysis() {
        let response = build_workstream_workspace_subagent_route(
            &test_config(),
            "beagle-darwin-hpc-governance",
            packet(),
            WorkspaceSubAgentRouteRequest {
                tool_id: Some("claude-code"),
                work_mode: Some("analysis"),
                preferred_subagent: None,
            },
        )
        .expect("subagent route");

        assert_eq!(response.route.selection.selected_subagent_id, "experiments");
        assert_eq!(response.route.selection.selected_role_tag, "experiments-analysis");
        assert_eq!(
            response.route.attach_metadata.workspace_folder,
            "/workspace/beagle/crates/beagle-experiments"
        );
        assert!(response
            .route
            .attach_metadata
            .browser_folder_hint
            .contains("/workspace/beagle/crates/beagle-experiments"));
    }

    #[test]
    fn workspace_subagent_route_selects_manuscript_for_claude_manuscript_mode() {
        let response = build_workstream_workspace_subagent_route(
            &test_config(),
            "beagle-darwin-hpc-governance",
            packet(),
            WorkspaceSubAgentRouteRequest {
                tool_id: Some("claude-code"),
                work_mode: Some("manuscript"),
                preferred_subagent: None,
            },
        )
        .expect("subagent route");

        assert_eq!(response.route.selection.selected_subagent_id, "manuscript");
        assert_eq!(response.route.selection.selected_role_tag, "manuscript-authoring");
        assert_eq!(
            response.route.attach_metadata.workspace_folder,
            "/workspace/beagle/docs/darwin/hpc"
        );
        assert!(response
            .route
            .attach_metadata
            .browser_folder_hint
            .contains("/workspace/beagle/docs/darwin/hpc"));
    }

    #[test]
    fn workspace_subagent_route_uses_retrieval_context_for_claude_without_work_mode() {
        let response = build_workstream_workspace_subagent_route(
            &test_config(),
            "beagle-darwin-hpc-governance",
            packet_with_retrieval(
                "manuscript",
                "manuscript",
                "retrieval top hits leaned editorial claims/review/manuscript work",
            ),
            WorkspaceSubAgentRouteRequest {
                tool_id: Some("claude-code"),
                work_mode: None,
                preferred_subagent: None,
            },
        )
        .expect("subagent route");

        assert_eq!(response.route.selection.selected_subagent_id, "manuscript");
        assert_eq!(response.route.selection.selection_source, "retrieval-context");
        assert!(response
            .route
            .selection
            .route_reason
            .contains("retrieval context suggested manuscript"));
    }
}
