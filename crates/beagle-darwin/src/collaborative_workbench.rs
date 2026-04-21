use crate::execution_state::PlanExecutionStatusSummary;
use crate::result_catalog::HpcProfileCatalog;
use crate::workspace_plane::WorkspaceSessionState;
use crate::workspace_subagents::{build_workstream_workspace_subagents, WorkspaceSubAgentRole};
use crate::workspace_tenancy::{
    build_multi_user_gpu_workspace_tenancy_bundle, ComputeRoleScope, ComputeTenancyClass,
    PartnerAccessRole, WorkspaceClientAccessPath,
};
use crate::{
    WorkstreamContextPacket, WorkstreamContextPacketResponse, WorkstreamLastResultReference,
};
use anyhow::Result;
use beagle_config::BeagleConfig;
use serde::Serialize;

const COLLABORATIVE_WORKBENCH_PHASE: &str = "B25.2";
const COLLABORATIVE_WORKBENCH_VERSION: &str =
    "beagle-collaborative-compute-experiment-workbench-v1";
const WORKBENCH_SESSION_VERSION: &str = "beagle-workbench-session-v1";
const WORKBENCH_COMPUTE_SELECTION_VERSION: &str = "beagle-workbench-compute-selection-v1";
const WORKBENCH_COLLABORATION_VERSION: &str = "beagle-workbench-collaboration-v1";
const WORKBENCH_RUN_VERSION: &str = "beagle-workbench-run-v1";

#[derive(Debug, Clone, Serialize)]
pub struct WorkbenchMemoryContextSummary {
    pub retrieval_ready: bool,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub query_text: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub query_type: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub retrieval_mode: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub dense_backend: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub sparse_backend: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub graphrag_query_mode: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub temporal_truth_view: Option<String>,
    pub top_memory_ids: Vec<String>,
    pub memory_hit_count: usize,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub experiment_id: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub suggested_subagent_id: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub suggested_work_mode: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub influence_reason: Option<String>,
}

#[derive(Debug, Clone, Serialize)]
pub struct CollaborativeWorkbenchSessionContract {
    pub phase: String,
    pub contract_kind: String,
    pub contract_version: String,
    pub workstream_id: String,
    pub workspace_id: String,
    pub session_id: String,
    pub same_beagle_owned_identity: bool,
    pub workspace_identity_owner: String,
    pub workspace_tenancy_state: String,
    pub stable_workspace_alias: String,
    pub workspace_root: String,
    pub default_dev_plane: String,
    pub active_dev_plane: String,
    pub governance_state: String,
    pub fallback_active: bool,
    pub workspace_tenancy_path: String,
    pub workspace_subagents_path: String,
    pub workspace_subagent_route_path: String,
    pub context_packet_path: String,
    pub plan_execution_path: String,
    pub client_access: Vec<WorkspaceClientAccessPath>,
    pub subagent_roles: Vec<WorkspaceSubAgentRole>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub recommended_subagent_id: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub live_selected_subagent_id: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub live_execution_state: Option<String>,
    pub memory_context: WorkbenchMemoryContextSummary,
    pub note: String,
}

#[derive(Debug, Clone, Serialize)]
pub struct CollaborativeWorkbenchComputeSelectionContract {
    pub phase: String,
    pub contract_kind: String,
    pub contract_version: String,
    pub workstream_id: String,
    pub workspace_id: String,
    pub session_id: String,
    pub same_beagle_owned_identity: bool,
    pub scheduler_kind: String,
    pub quota_policy_kind: String,
    pub selection_mode: String,
    pub default_profile_id: String,
    pub batch_profile_id: String,
    pub gpu_ready_profile_id: String,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub last_used_profile_id: Option<String>,
    pub last_used_profile_source: String,
    pub suggested_profile_id: String,
    pub suggested_profile_reason: String,
    pub live_gpu_access_mode: String,
    pub shared_gpu_access_state: String,
    pub compute_classes: Vec<ComputeTenancyClass>,
    pub role_scopes: Vec<ComputeRoleScope>,
    pub note: String,
}

#[derive(Debug, Clone, Serialize)]
pub struct CollaborativeWorkbenchCollaborationContract {
    pub phase: String,
    pub contract_kind: String,
    pub contract_version: String,
    pub workstream_id: String,
    pub workspace_id: String,
    pub session_id: String,
    pub same_beagle_owned_identity: bool,
    pub partner_access_state: String,
    pub workspace_sharing_mode: String,
    pub stable_workspace_alias: String,
    pub collaboration_pattern: String,
    pub direct_cluster_admin_grant: bool,
    pub direct_kubernetes_access_grant: bool,
    pub per_user_cluster_identity_live: bool,
    pub roles: Vec<PartnerAccessRole>,
    pub note: String,
}

#[derive(Debug, Clone, Serialize)]
pub struct WorkbenchResultReference {
    pub job_id: u64,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub run_label: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub profile_id: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub node_list: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub manifest_key: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub state: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub source_phase: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub source_run_id: Option<String>,
}

#[derive(Debug, Clone, Serialize)]
pub struct CollaborativeWorkbenchRunContract {
    pub phase: String,
    pub contract_kind: String,
    pub contract_version: String,
    pub workstream_id: String,
    pub workspace_id: String,
    pub session_id: String,
    pub same_beagle_owned_identity: bool,
    pub execution_available: bool,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub execution_id: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub plan_id: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub current_state: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub selected_subagent_id: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub recipe_kind: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub experiment_id: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub current_profile_id: Option<String>,
    pub result_link_count: usize,
    pub review_requested: bool,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub operator_followup_action: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub autonomy_policy_rollout_status: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub execution_state_path: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub execution_receipt_path: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub execution_result_links_path: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub review_inbox_path: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub follow_on_plan_path: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub continuation_state_path: Option<String>,
    pub last_result_available: bool,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub last_result_reference: Option<WorkbenchResultReference>,
    pub top_memory_ids: Vec<String>,
    pub memory_hit_count: usize,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub retrieval_query_type: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub graphrag_query_mode: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub temporal_truth_view: Option<String>,
    pub note: String,
}

#[derive(Debug, Clone, Serialize)]
pub struct CollaborativeComputeExperimentWorkbench {
    pub status: String,
    pub phase: String,
    pub contract_kind: String,
    pub contract_version: String,
    pub workstream_id: String,
    pub workspace_id: String,
    pub session_id: String,
    pub same_beagle_owned_identity: bool,
    pub session: CollaborativeWorkbenchSessionContract,
    pub compute_selection: CollaborativeWorkbenchComputeSelectionContract,
    pub collaboration_access: CollaborativeWorkbenchCollaborationContract,
    pub run: CollaborativeWorkbenchRunContract,
    pub note: String,
}

#[derive(Debug, Clone)]
pub struct CollaborativeComputeExperimentWorkbenchBundle {
    pub workbench_session: CollaborativeWorkbenchSessionContract,
    pub compute_selection: CollaborativeWorkbenchComputeSelectionContract,
    pub collaboration_access: CollaborativeWorkbenchCollaborationContract,
    pub workbench_run: CollaborativeWorkbenchRunContract,
    pub collaborative_workbench: CollaborativeComputeExperimentWorkbench,
}

pub fn build_collaborative_compute_experiment_workbench(
    cfg: &BeagleConfig,
    workstream_id: &str,
    context_packet: WorkstreamContextPacketResponse,
    workspace_session: &WorkspaceSessionState,
    profile_catalog: &HpcProfileCatalog,
) -> Result<CollaborativeComputeExperimentWorkbenchBundle> {
    let tenancy_bundle = build_multi_user_gpu_workspace_tenancy_bundle(
        cfg,
        workstream_id,
        context_packet.clone(),
        workspace_session,
        profile_catalog,
    )?;
    let subagents_response =
        build_workstream_workspace_subagents(cfg, workstream_id, context_packet.clone())?;
    let memory_context = memory_context_summary(&context_packet.packet);
    let execution = execution_summary(&context_packet.packet);
    let (last_used_profile_id, last_used_profile_source) =
        last_used_profile(context_packet.packet.last_result.reference.as_ref(), workspace_session);
    let (suggested_profile_id, suggested_profile_reason) = suggested_profile(
        &tenancy_bundle.compute_tenancy,
        workspace_session,
        &memory_context,
        execution,
        last_used_profile_id.as_deref(),
    );

    let workbench_session = CollaborativeWorkbenchSessionContract {
        phase: COLLABORATIVE_WORKBENCH_PHASE.to_string(),
        contract_kind: "workbench-session".to_string(),
        contract_version: WORKBENCH_SESSION_VERSION.to_string(),
        workstream_id: context_packet.packet.workstream_id.clone(),
        workspace_id: context_packet.packet.workspace_id.clone(),
        session_id: context_packet.packet.session_id.clone(),
        same_beagle_owned_identity: tenancy_bundle.workspace_tenancy.same_beagle_owned_identity,
        workspace_identity_owner: "beagle".to_string(),
        workspace_tenancy_state: tenancy_bundle
            .workspace_tenancy
            .workspace_tenancy_state
            .clone(),
        stable_workspace_alias: tenancy_bundle.workspace_tenancy.stable_workspace_alias.clone(),
        workspace_root: tenancy_bundle.workspace_tenancy.repo_hydration.repo_root.clone(),
        default_dev_plane: workspace_session.dev_plane_policy.default_dev_plane.clone(),
        active_dev_plane: workspace_session.active_dev_plane.clone(),
        governance_state: context_packet.packet.governance_state.clone(),
        fallback_active: workspace_session.fallback_active,
        workspace_tenancy_path: format!(
            "/api/darwin/workstreams/{}/workspace-tenancy",
            context_packet.packet.workstream_id
        ),
        workspace_subagents_path: subagents_response.subagents.workspace_subagents_path.clone(),
        workspace_subagent_route_path: format!(
            "/api/darwin/workstreams/{}/workspace-subagent-route",
            context_packet.packet.workstream_id
        ),
        context_packet_path: format!(
            "/api/darwin/workstreams/{}/context-packet",
            context_packet.packet.workstream_id
        ),
        plan_execution_path: format!(
            "/api/darwin/workstreams/{}/plan-execution",
            context_packet.packet.workstream_id
        ),
        client_access: tenancy_bundle
            .workspace_tenancy
            .vscode_cursor_access
            .clients
            .clone(),
        subagent_roles: subagents_response.subagents.roles.clone(),
        recommended_subagent_id: memory_context.suggested_subagent_id.clone(),
        live_selected_subagent_id: execution.map(|summary| summary.selected_subagent_id.clone()),
        live_execution_state: execution.map(|summary| summary.current_state.clone()),
        memory_context,
        note: "B25.2 freezes the Beagle-owned workspace/session envelope, IDE access paths, subagent roster, and active retrieval context into one collaborative workbench session contract.".to_string(),
    };

    let compute_selection = CollaborativeWorkbenchComputeSelectionContract {
        phase: COLLABORATIVE_WORKBENCH_PHASE.to_string(),
        contract_kind: "workbench-compute-selection".to_string(),
        contract_version: WORKBENCH_COMPUTE_SELECTION_VERSION.to_string(),
        workstream_id: context_packet.packet.workstream_id.clone(),
        workspace_id: context_packet.packet.workspace_id.clone(),
        session_id: context_packet.packet.session_id.clone(),
        same_beagle_owned_identity: tenancy_bundle.compute_tenancy.same_beagle_owned_identity,
        scheduler_kind: tenancy_bundle.compute_tenancy.scheduler_kind.clone(),
        quota_policy_kind: tenancy_bundle.compute_tenancy.quota_policy_kind.clone(),
        selection_mode: "operator-explicit-profile-pick".to_string(),
        default_profile_id: tenancy_bundle.compute_tenancy.default_profile_id.clone(),
        batch_profile_id: tenancy_bundle.compute_tenancy.batch_profile_id.clone(),
        gpu_ready_profile_id: tenancy_bundle.compute_tenancy.advanced_profile_id.clone(),
        last_used_profile_id,
        last_used_profile_source,
        suggested_profile_id,
        suggested_profile_reason,
        live_gpu_access_mode: tenancy_bundle.compute_tenancy.live_gpu_access_mode.clone(),
        shared_gpu_access_state: tenancy_bundle
            .compute_tenancy
            .shared_gpu_access_state
            .clone(),
        compute_classes: tenancy_bundle.compute_tenancy.compute_classes.clone(),
        role_scopes: tenancy_bundle.compute_tenancy.role_scopes.clone(),
        note: "B25.2 keeps compute selection explicit and bounded: the operator or partner-dev chooses from the canonical Slurm-backed profile set rather than inheriting unrestricted cluster access.".to_string(),
    };

    let collaboration_access = CollaborativeWorkbenchCollaborationContract {
        phase: COLLABORATIVE_WORKBENCH_PHASE.to_string(),
        contract_kind: "workbench-collaboration-access".to_string(),
        contract_version: WORKBENCH_COLLABORATION_VERSION.to_string(),
        workstream_id: context_packet.packet.workstream_id.clone(),
        workspace_id: context_packet.packet.workspace_id.clone(),
        session_id: context_packet.packet.session_id.clone(),
        same_beagle_owned_identity: tenancy_bundle.partner_access.same_beagle_owned_identity,
        partner_access_state: tenancy_bundle.partner_access.partner_access_state.clone(),
        workspace_sharing_mode: tenancy_bundle.partner_access.workspace_sharing_mode.clone(),
        stable_workspace_alias: tenancy_bundle.partner_access.stable_workspace_alias.clone(),
        collaboration_pattern: "shared-workspace-plus-scoped-compute".to_string(),
        direct_cluster_admin_grant: tenancy_bundle.partner_access.direct_cluster_admin_grant,
        direct_kubernetes_access_grant: tenancy_bundle.partner_access.direct_kubernetes_access_grant,
        per_user_cluster_identity_live: tenancy_bundle.partner_access.per_user_cluster_identity_live,
        roles: tenancy_bundle.partner_access.roles.clone(),
        note: "B25.2 turns the shared Beagle-owned workspace into a bounded collaboration surface: the operator keeps control, and partner-dev access stays scoped to approved clients and compute profiles.".to_string(),
    };

    let workbench_run = CollaborativeWorkbenchRunContract {
        phase: COLLABORATIVE_WORKBENCH_PHASE.to_string(),
        contract_kind: "workbench-run".to_string(),
        contract_version: WORKBENCH_RUN_VERSION.to_string(),
        workstream_id: context_packet.packet.workstream_id.clone(),
        workspace_id: context_packet.packet.workspace_id.clone(),
        session_id: context_packet.packet.session_id.clone(),
        same_beagle_owned_identity: tenancy_bundle.workspace_tenancy.same_beagle_owned_identity,
        execution_available: execution.is_some(),
        execution_id: execution.map(|summary| summary.execution_id.clone()),
        plan_id: execution.map(|summary| summary.plan_id.clone()),
        current_state: execution.map(|summary| summary.current_state.clone()),
        selected_subagent_id: execution.map(|summary| summary.selected_subagent_id.clone()),
        recipe_kind: execution.and_then(|summary| summary.recipe_kind.clone()),
        experiment_id: execution.and_then(|summary| summary.experiment_id.clone()),
        current_profile_id: workspace_session
            .current_task
            .as_ref()
            .map(|task| task.profile_id.clone())
            .or_else(|| {
                workspace_session
                    .last_successful_task
                    .as_ref()
                    .map(|task| task.profile_id.clone())
            })
            .or_else(|| {
                context_packet
                    .packet
                    .last_result
                    .reference
                    .as_ref()
                    .and_then(|reference| reference.profile_id.clone())
            }),
        result_link_count: execution.map(|summary| summary.result_link_count).unwrap_or(0),
        review_requested: execution.map(|summary| summary.review_requested).unwrap_or(false),
        operator_followup_action: execution.and_then(|summary| summary.operator_followup_action.clone()),
        autonomy_policy_rollout_status: execution
            .and_then(|summary| summary.autonomy_policy_rollout_status.clone()),
        execution_state_path: execution.map(|summary| summary.execution_state_path.clone()),
        execution_receipt_path: execution.map(|summary| summary.execution_receipt_path.clone()),
        execution_result_links_path: execution
            .map(|summary| summary.execution_result_links_path.clone()),
        review_inbox_path: execution.and_then(|summary| summary.review_inbox_path.clone()),
        follow_on_plan_path: execution.and_then(|summary| summary.follow_on_plan_path.clone()),
        continuation_state_path: execution.and_then(|summary| summary.continuation_state_path.clone()),
        last_result_available: context_packet.packet.last_result.available,
        last_result_reference: workbench_result_reference(&context_packet.packet),
        top_memory_ids: context_packet
            .packet
            .retrieval_context
            .as_ref()
            .map(|retrieval| retrieval.top_memory_ids.clone())
            .unwrap_or_default(),
        memory_hit_count: context_packet.packet.memory_hits.len(),
        retrieval_query_type: context_packet
            .packet
            .retrieval_context
            .as_ref()
            .map(|retrieval| retrieval.query_type.clone()),
        graphrag_query_mode: context_packet
            .packet
            .retrieval_context
            .as_ref()
            .and_then(|retrieval| retrieval.graphrag_query_mode.clone()),
        temporal_truth_view: context_packet
            .packet
            .retrieval_context
            .as_ref()
            .and_then(|retrieval| retrieval.temporal_truth_view.clone()),
        note: "B25.2 keeps execution state, result refs, and retrieval context in the same workbench contract so the operator does not have to stitch together multiple planes by hand.".to_string(),
    };

    let collaborative_workbench = CollaborativeComputeExperimentWorkbench {
        status: "ok".to_string(),
        phase: COLLABORATIVE_WORKBENCH_PHASE.to_string(),
        contract_kind: "collaborative-compute-experiment-workbench".to_string(),
        contract_version: COLLABORATIVE_WORKBENCH_VERSION.to_string(),
        workstream_id: context_packet.packet.workstream_id.clone(),
        workspace_id: context_packet.packet.workspace_id.clone(),
        session_id: context_packet.packet.session_id.clone(),
        same_beagle_owned_identity: tenancy_bundle.workspace_tenancy.same_beagle_owned_identity,
        session: workbench_session.clone(),
        compute_selection: compute_selection.clone(),
        collaboration_access: collaboration_access.clone(),
        run: workbench_run.clone(),
        note: "B25.2 does not introduce a new autonomous runtime. It composes the existing Beagle-owned workspace, context, compute, and collaboration surfaces into one bounded lab-OS workbench.".to_string(),
    };

    Ok(CollaborativeComputeExperimentWorkbenchBundle {
        workbench_session,
        compute_selection,
        collaboration_access,
        workbench_run,
        collaborative_workbench,
    })
}

fn memory_context_summary(packet: &WorkstreamContextPacket) -> WorkbenchMemoryContextSummary {
    if let Some(retrieval) = packet.retrieval_context.as_ref() {
        WorkbenchMemoryContextSummary {
            retrieval_ready: true,
            query_text: Some(retrieval.query_text.clone()),
            query_type: Some(retrieval.query_type.clone()),
            retrieval_mode: Some(retrieval.retrieval_mode.clone()),
            dense_backend: Some(retrieval.dense_backend.clone()),
            sparse_backend: Some(retrieval.sparse_backend.clone()),
            graphrag_query_mode: retrieval.graphrag_query_mode.clone(),
            temporal_truth_view: retrieval.temporal_truth_view.clone(),
            top_memory_ids: retrieval.top_memory_ids.clone(),
            memory_hit_count: packet.memory_hits.len(),
            experiment_id: packet
                .experiment_flags
                .as_ref()
                .and_then(|flags| flags.experiment_id.clone())
                .or_else(|| {
                    retrieval
                        .execution
                        .as_ref()
                        .and_then(|summary| summary.experiment_id.clone())
                }),
            suggested_subagent_id: retrieval.suggested_subagent_id.clone(),
            suggested_work_mode: retrieval.suggested_work_mode.clone(),
            influence_reason: Some(retrieval.influence_reason.clone()),
        }
    } else {
        WorkbenchMemoryContextSummary {
            retrieval_ready: false,
            query_text: None,
            query_type: None,
            retrieval_mode: None,
            dense_backend: None,
            sparse_backend: None,
            graphrag_query_mode: None,
            temporal_truth_view: None,
            top_memory_ids: Vec::new(),
            memory_hit_count: packet.memory_hits.len(),
            experiment_id: packet
                .experiment_flags
                .as_ref()
                .and_then(|flags| flags.experiment_id.clone()),
            suggested_subagent_id: None,
            suggested_work_mode: None,
            influence_reason: None,
        }
    }
}

fn execution_summary(packet: &WorkstreamContextPacket) -> Option<&PlanExecutionStatusSummary> {
    packet
        .retrieval_context
        .as_ref()
        .and_then(|retrieval| retrieval.execution.as_ref())
}

fn last_used_profile(
    last_result_reference: Option<&WorkstreamLastResultReference>,
    workspace_session: &WorkspaceSessionState,
) -> (Option<String>, String) {
    if let Some(task) = workspace_session.current_task.as_ref() {
        return (Some(task.profile_id.clone()), "current-task".to_string());
    }
    if let Some(task) = workspace_session.last_successful_task.as_ref() {
        return (Some(task.profile_id.clone()), "last-successful-task".to_string());
    }
    if let Some(reference) = last_result_reference {
        if let Some(profile_id) = reference.profile_id.as_ref() {
            return (Some(profile_id.clone()), "last-result-reference".to_string());
        }
    }
    (None, "none".to_string())
}

fn suggested_profile(
    compute_tenancy: &crate::workspace_tenancy::ComputeTenancyContract,
    workspace_session: &WorkspaceSessionState,
    memory_context: &WorkbenchMemoryContextSummary,
    execution: Option<&PlanExecutionStatusSummary>,
    last_used_profile_id: Option<&str>,
) -> (String, String) {
    if let Some(profile_id) = workspace_session
        .current_task
        .as_ref()
        .map(|task| task.profile_id.as_str())
        .or(last_used_profile_id)
    {
        return (
            profile_id.to_string(),
            "The active or most recent workspace task already binds the canonical compute profile, so the workbench keeps that lane sticky.".to_string(),
        );
    }

    if let Some(summary) = execution {
        if summary.recipe_kind.as_deref() == Some("operator_gpu_loop") {
            return (
                compute_tenancy.advanced_profile_id.clone(),
                "The current execution recipe is explicitly GPU-oriented, so the workbench suggests the typed GPU lane.".to_string(),
            );
        }
        if summary.recipe_kind.as_deref() == Some("operator_cpu_loop") {
            return (
                compute_tenancy.batch_profile_id.clone(),
                "The current execution recipe is a bounded CPU operator loop, so the workbench suggests the longer CPU batch lane.".to_string(),
            );
        }
        if summary.experiment_id.is_some() {
            return (
                compute_tenancy.advanced_profile_id.clone(),
                "An active experiment target is present and no previous profile is pinned, so the workbench suggests the GPU-ready lane while leaving final selection operator-visible.".to_string(),
            );
        }
    }

    if memory_context.experiment_id.is_some() {
        return (
            compute_tenancy.advanced_profile_id.clone(),
            "The current memory/context focus is an experiment lane, so the workbench surfaces the GPU-ready profile as the first bounded option.".to_string(),
        );
    }

    (
        compute_tenancy.default_profile_id.clone(),
        "No active task or experiment-specific profile is pinned, so the workbench falls back to the canonical short CPU lane for bounded interactive work.".to_string(),
    )
}

fn workbench_result_reference(packet: &WorkstreamContextPacket) -> Option<WorkbenchResultReference> {
    let reference = packet.last_result.reference.as_ref()?;
    let summary = packet.last_result.summary.as_ref();
    Some(WorkbenchResultReference {
        job_id: reference.job_id,
        run_label: reference.run_label.clone(),
        profile_id: reference.profile_id.clone(),
        node_list: reference.node_list.clone(),
        manifest_key: reference.manifest_key.clone(),
        state: summary.map(|value| value.state.clone()),
        source_phase: summary.and_then(|value| value.source_phase.clone()),
        source_run_id: summary.and_then(|value| value.source_run_id.clone()),
    })
}

#[cfg(test)]
mod tests {
    use super::{
        build_collaborative_compute_experiment_workbench, COLLABORATIVE_WORKBENCH_PHASE,
    };
    use crate::execution_state::PlanExecutionStatusSummary;
    use crate::result_catalog::{HpcProfile, HpcProfileCatalog};
    use crate::workstream_context_packet::{
        WorkstreamContextPacket, WorkstreamContextPacketExperimentFlags,
        WorkstreamContextPacketHandoff, WorkstreamContextPacketLastResult,
        WorkstreamContextPacketMemoryHit, WorkstreamContextPacketResponse,
        WorkstreamContextPacketRetrievalContext, WorkstreamContextPacketRetrievalFilters,
    };
    use crate::workspace_plane::WorkspaceSessionState;
    use beagle_config::{
        AdvancedModulesConfig, BeagleConfig, ConsumerAccessConfig, GraphConfig, HermesConfig,
        LlmConfig, ObserverThresholds, StorageConfig, ToolBridgeConfig, WorkspacePlaneConfig,
    };
    use chrono::Utc;

    fn cfg() -> BeagleConfig {
        let mut workspace = WorkspacePlaneConfig::default();
        workspace.canonical_workspace_id = "beagle-cluster-pilot".to_string();
        workspace.canonical_repo = "agourakis82/beagle".to_string();
        workspace.canonical_branch = "feat/darwin-hpc-governance".to_string();
        workspace.habitat.ssh_user = "openvscode-server".to_string();
        BeagleConfig {
            profile: "dev".to_string(),
            safe_mode: true,
            api_token: None,
            llm: LlmConfig::default(),
            storage: StorageConfig {
                data_dir: "/tmp/beagle-tests".to_string(),
            },
            graph: GraphConfig::default(),
            hermes: HermesConfig::default(),
            tool_bridge: ToolBridgeConfig::default(),
            workspace,
            consumers: ConsumerAccessConfig::default(),
            advanced: AdvancedModulesConfig::default(),
            observer: ObserverThresholds::default(),
        }
    }

    fn context_packet() -> WorkstreamContextPacketResponse {
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
                    last_handoff: Some("resume workbench".to_string()),
                },
                last_result: WorkstreamContextPacketLastResult {
                    available: false,
                    reference: None,
                    summary: None,
                    manifest: None,
                    error: None,
                },
                last_successful_task: None,
                latest_physio: None,
                experiment_flags: Some(WorkstreamContextPacketExperimentFlags {
                    hrv_aware: Some(true),
                    observer_enabled: Some(true),
                    serendipity_enabled: Some(false),
                    triad_enabled: Some(false),
                    provider: Some("codex".to_string()),
                    model: Some("gpt-5.4".to_string()),
                    experiment_id: Some("beagle-exp-workbench".to_string()),
                    condition: Some("steady".to_string()),
                }),
                memory_hits: vec![WorkstreamContextPacketMemoryHit {
                    memory_id: Some("memory-1".to_string()),
                    source: "bridge".to_string(),
                    conversation_id: None,
                    turn_index: Some(0),
                    role: Some("assistant".to_string()),
                    snippet: "Keep one workspace identity while executing bounded workbench flows."
                        .to_string(),
                    timestamp: None,
                    relevance: 0.91,
                    tags: vec!["workbench".to_string()],
                    domain: Some("darwin-hpc".to_string()),
                    physio_snapshot: None,
                }],
                retrieval_context: Some(WorkstreamContextPacketRetrievalContext {
                    query_text: "run collaborative experiment workbench".to_string(),
                    query_type: "general".to_string(),
                    retrieval_mode: "hybrid".to_string(),
                    dense_backend: "voyage-4-large".to_string(),
                    sparse_backend: "local-lexical".to_string(),
                    routing_source: "router".to_string(),
                    routing_reason: "analysis".to_string(),
                    reranking_applied: false,
                    reranking_profile_id: None,
                    reranker_backend: None,
                    reranker_runtime_state: None,
                    reranking_latency_ms: None,
                    top_k: 4,
                    applied_filters: WorkstreamContextPacketRetrievalFilters::default(),
                    hit_count: 1,
                    top_memory_ids: vec!["memory-1".to_string()],
                    top_domains: vec!["darwin-hpc".to_string()],
                    top_tags: vec!["workbench".to_string()],
                    promotion_policy_id: None,
                    retention_policy_id: None,
                    graphrag_query_mode: Some("global".to_string()),
                    graphrag_query_mode_reason: Some("analysis".to_string()),
                    graphrag_root_entity_type: Some("Campaign".to_string()),
                    graphrag_root_entity_id: Some("beagle-exp-workbench".to_string()),
                    graphrag_node_count: 4,
                    graphrag_edge_count: 3,
                    graphrag_node_types: vec!["Campaign".to_string()],
                    graphrag_edge_types: vec!["uses".to_string()],
                    memory_hierarchy_counts: vec![],
                    promoted_memory_count: 0,
                    promoted_target_memory_types: vec![],
                    compiled_context_task_profile: Some("analysis".to_string()),
                    compiled_context_budget_profile_id: Some("b235-budget-analysis".to_string()),
                    compiled_context_retrieval_query_type: Some("general".to_string()),
                    compiled_context_graphrag_query_mode: Some("global".to_string()),
                    compiled_context_selected_memory_tiers: vec!["semantic".to_string()],
                    compiled_context_source_slices: vec![],
                    compiled_context_top_memory_ids: vec!["memory-1".to_string()],
                    compiled_context_preview: Some("workbench preview".to_string()),
                    planner: None,
                    execution: Some(PlanExecutionStatusSummary {
                        state_version: "beagle-plan-execution-state-v1".to_string(),
                        execution_id: "exec-workbench".to_string(),
                        plan_id: "plan-workbench".to_string(),
                        current_state: "succeeded".to_string(),
                        selected_subagent_id: "experiments".to_string(),
                        retrieval_query_type: "general".to_string(),
                        compiler_profile_id: "b235-budget-analysis".to_string(),
                        graphrag_query_mode: "global".to_string(),
                        temporal_truth_view: "both".to_string(),
                        approved_at: Utc::now(),
                        started_at: Some(Utc::now()),
                        finished_at: Some(Utc::now()),
                        latest_receipt_id: Some("receipt-workbench".to_string()),
                        recipe_kind: Some("operator_gpu_loop".to_string()),
                        experiment_id: Some("beagle-exp-workbench".to_string()),
                        result_link_count: 5,
                        handoff_updated: true,
                        handoff_ref: Some("/api/darwin/workstreams/beagle-darwin-hpc-governance/workspace-subagent-handoff".to_string()),
                        reflection_available: true,
                        latest_reflection_id: Some("reflection-1".to_string()),
                        latest_trajectory_eval_id: Some("trajectory-1".to_string()),
                        latest_replan_suggestion_id: None,
                        latest_quality_score: Some(95),
                        latest_trajectory_quality: Some("clean".to_string()),
                        replan_required: false,
                        operator_followup_action: Some("observe".to_string()),
                        review_requested: false,
                        review_inbox_state: None,
                        latest_review_inbox_item_id: None,
                        latest_review_decision_id: None,
                        latest_review_decision_action: None,
                        latest_follow_on_plan_id: None,
                        follow_on_plan_available: false,
                        latest_autonomy_policy_id: None,
                        latest_risk_evaluation_id: None,
                        latest_approval_gating_decision_id: None,
                        latest_autonomy_calibration_dataset_id: None,
                        latest_autonomy_policy_eval_report_id: None,
                        latest_escalation_thresholds_id: None,
                        latest_shadow_policy_comparison_id: None,
                        latest_updated_policy_recommendation_id: None,
                        latest_autonomy_policy_current_id: None,
                        latest_autonomy_policy_candidate_id: None,
                        latest_rollout_metrics_id: None,
                        latest_guarded_rollout_decision_id: None,
                        approval_gating_decision_class: Some("auto-continue".to_string()),
                        approval_gating_risk_level: Some("low".to_string()),
                        approval_gating_dispatch_ready: true,
                        approval_gating_blocked: false,
                        continuation_dispatched: false,
                        latest_continuation_dispatch_id: None,
                        latest_continuation_receipt_id: None,
                        continuation_current_state: None,
                        continuation_source_execution_id: None,
                        continuation_next_execution_id: None,
                        continuation_next_plan_id: None,
                        continuation_review_action: None,
                        autonomy_policy_calibration_status: Some("analysis-shadow-rechecked".to_string()),
                        autonomy_policy_rollout_status: Some("implementation-and-analysis-canary-live".to_string()),
                        review_inbox_path: None,
                        review_decision_path: None,
                        follow_on_plan_path: None,
                        autonomy_policy_path: None,
                        risk_evaluation_path: None,
                        approval_gating_decision_path: None,
                        autonomy_calibration_dataset_path: None,
                        autonomy_policy_eval_report_path: None,
                        escalation_thresholds_path: None,
                        shadow_policy_comparison_path: None,
                        updated_policy_recommendation_path: None,
                        autonomy_policy_current_path: None,
                        autonomy_policy_candidate_path: None,
                        rollout_metrics_path: None,
                        rollout_decision_path: None,
                        continuation_dispatch_path: None,
                        continuation_receipt_path: None,
                        continuation_state_path: None,
                        reflection_path: Some("/reflection".to_string()),
                        trajectory_eval_path: Some("/trajectory".to_string()),
                        replan_suggestion_path: None,
                        execution_state_path: "/state".to_string(),
                        execution_receipt_path: "/receipt".to_string(),
                        execution_result_links_path: "/links".to_string(),
                        operator_execution_state: "operator-visible-bounded".to_string(),
                        note: "workbench".to_string(),
                    }),
                    temporal_truth_view: Some("both".to_string()),
                    temporal_subject_refs: vec!["claim:1".to_string()],
                    temporal_current_memory_ids: vec!["memory-1".to_string()],
                    temporal_historical_memory_ids: vec!["memory-0".to_string()],
                    temporal_track_count: 1,
                    temporal_contradiction_count: 0,
                    temporal_contradiction_ids: vec![],
                    temporal_preview: Some("truth".to_string()),
                    suggested_subagent_id: Some("experiments".to_string()),
                    suggested_work_mode: Some("analysis".to_string()),
                    influence_reason: "analysis".to_string(),
                }),
                recommended_recipe: None,
                bounded_study_baseline: None,
            },
        }
    }

    fn profile_catalog() -> HpcProfileCatalog {
        HpcProfileCatalog {
            profiles: vec![
                HpcProfile {
                    id: "cpu-short-v1".to_string(),
                    description: "Short-lived CPU canary profile".to_string(),
                    kind: "cpu".to_string(),
                    single_node: true,
                    gpu: false,
                    partition: "cpu".to_string(),
                    max_walltime: "00:02:00".to_string(),
                    artifact_mode: "deterministic-small".to_string(),
                    allowed_parameters: vec!["run_label".to_string()],
                },
                HpcProfile {
                    id: "cpu-batch-v1".to_string(),
                    description: "Longer single-node CPU batch profile".to_string(),
                    kind: "cpu".to_string(),
                    single_node: true,
                    gpu: false,
                    partition: "cpu".to_string(),
                    max_walltime: "00:10:00".to_string(),
                    artifact_mode: "deterministic-medium".to_string(),
                    allowed_parameters: vec!["run_label".to_string()],
                },
                HpcProfile {
                    id: "gpu-single-v1".to_string(),
                    description: "Single-node GPU profile on the Slurm execution plane".to_string(),
                    kind: "gpu".to_string(),
                    single_node: true,
                    gpu: true,
                    partition: "gpu".to_string(),
                    max_walltime: "00:05:00".to_string(),
                    artifact_mode: "deterministic-small".to_string(),
                    allowed_parameters: vec!["run_label".to_string()],
                },
            ],
        }
    }

    #[test]
    fn collaborative_workbench_keeps_identity_and_surfaces_compute_focus() {
        let cfg = cfg();
        let session = WorkspaceSessionState::new(
            &cfg,
            "beagle-cluster-pilot".to_string(),
            Some("ws-cluster-workspace-habitat".to_string()),
        );
        let bundle = build_collaborative_compute_experiment_workbench(
            &cfg,
            "beagle-darwin-hpc-governance",
            context_packet(),
            &session,
            &profile_catalog(),
        )
        .unwrap();

        assert_eq!(bundle.collaborative_workbench.phase, COLLABORATIVE_WORKBENCH_PHASE);
        assert!(bundle.collaborative_workbench.same_beagle_owned_identity);
        assert_eq!(
            bundle.workbench_session.recommended_subagent_id.as_deref(),
            Some("experiments")
        );
        assert_eq!(
            bundle.compute_selection.suggested_profile_id,
            "gpu-single-v1"
        );
        assert!(bundle.workbench_run.execution_available);
        assert_eq!(
            bundle.workbench_run.selected_subagent_id.as_deref(),
            Some("experiments")
        );
        assert_eq!(
            bundle.collaboration_access.roles[1].role_id,
            "partner-dev"
        );
    }
}
