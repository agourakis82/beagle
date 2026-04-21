use crate::{
    CompiledContextSourceSliceSummary,
    DarwinHpcGatewayClient, ObjectResultManifest, ResultCatalogEntry, WorkspaceLastSuccessfulTask,
    IntentPlannerAvailability, PlanExecutionStatusSummary,
    WorkstreamLastResultReference, get_workstream_control_room_detail,
    get_workstream_control_room_last_result,
};
use beagle_config::BeagleConfig;
use chrono::{DateTime, Utc};
use serde::{Deserialize, Serialize};
use std::path::Path;

const CONTEXT_PACKET_PHASE: &str = "B18.1";
const CONTEXT_PACKET_VERSION: &str = "beagle-memory-aware-context-packet-v1";

#[derive(Debug, Clone, Default)]
pub struct WorkstreamContextPacketAugmentation {
    pub latest_physio: Option<WorkstreamContextPacketPhysioSnapshot>,
    pub experiment_flags: Option<WorkstreamContextPacketExperimentFlags>,
    pub memory_hits: Vec<WorkstreamContextPacketMemoryHit>,
    pub retrieval_context: Option<WorkstreamContextPacketRetrievalContext>,
}

/// B26.6 — Summary surfaced on the context packet when baseline adoption completed.
#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
pub struct BoundedStudyBaselineSummary {
    pub phase: String,
    pub adoption_id: String,
    pub promoted_variant_receipt_id: String,
    pub baseline_adoption_contract_version: String,
    pub study_id: String,
    pub workstream_id: String,
    pub workspace_id: String,
    pub session_id: String,
    pub same_beagle_owned_identity: bool,
    pub promoted_variant_id: String,
    pub promoted_run_id: String,
    pub promoted_compute_profile_id: String,
    pub rollback_plan_id: String,
    pub next_study_seed_id: String,
    pub rollback_api_path: String,
    pub baseline_adoption_api_path: String,
    pub workspace_plane_baseline_path: String,
}

#[derive(Debug, Clone, Serialize)]
pub struct WorkstreamContextPacketResponse {
    pub status: String,
    pub phase: String,
    pub packet: WorkstreamContextPacket,
}

#[derive(Debug, Clone, Serialize)]
pub struct WorkstreamContextPacket {
    pub packet_version: String,
    pub workstream_id: String,
    pub workspace_id: String,
    pub session_id: String,
    pub repo: String,
    pub branch: String,
    pub governance_state: String,
    pub handoff: WorkstreamContextPacketHandoff,
    pub last_result: WorkstreamContextPacketLastResult,
    pub last_successful_task: Option<WorkspaceLastSuccessfulTask>,
    pub latest_physio: Option<WorkstreamContextPacketPhysioSnapshot>,
    pub experiment_flags: Option<WorkstreamContextPacketExperimentFlags>,
    pub memory_hits: Vec<WorkstreamContextPacketMemoryHit>,
    pub retrieval_context: Option<WorkstreamContextPacketRetrievalContext>,
    pub recommended_recipe: Option<WorkstreamContextPacketRecipe>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub bounded_study_baseline: Option<BoundedStudyBaselineSummary>,
}

#[derive(Debug, Clone, Default, Serialize)]
pub struct WorkstreamContextPacketRetrievalFilters {
    pub workstream_id: Option<String>,
    pub campaign_id: Option<String>,
    pub session_id: Option<String>,
    pub source: Option<String>,
    pub role: Option<String>,
    pub domain: Option<String>,
    pub tags: Vec<String>,
}

#[derive(Debug, Clone, Serialize)]
pub struct WorkstreamContextPacketRetrievalContext {
    pub query_text: String,
    pub query_type: String,
    pub retrieval_mode: String,
    pub dense_backend: String,
    pub sparse_backend: String,
    pub routing_source: String,
    pub routing_reason: String,
    pub reranking_applied: bool,
    pub reranking_profile_id: Option<String>,
    pub reranker_backend: Option<String>,
    pub reranker_runtime_state: Option<String>,
    pub reranking_latency_ms: Option<u64>,
    pub top_k: usize,
    pub applied_filters: WorkstreamContextPacketRetrievalFilters,
    pub hit_count: usize,
    pub top_memory_ids: Vec<String>,
    pub top_domains: Vec<String>,
    pub top_tags: Vec<String>,
    pub promotion_policy_id: Option<String>,
    pub retention_policy_id: Option<String>,
    pub graphrag_query_mode: Option<String>,
    pub graphrag_query_mode_reason: Option<String>,
    pub graphrag_root_entity_type: Option<String>,
    pub graphrag_root_entity_id: Option<String>,
    pub graphrag_node_count: usize,
    pub graphrag_edge_count: usize,
    pub graphrag_node_types: Vec<String>,
    pub graphrag_edge_types: Vec<String>,
    pub memory_hierarchy_counts: Vec<WorkstreamContextPacketMemoryHierarchyCount>,
    pub promoted_memory_count: usize,
    pub promoted_target_memory_types: Vec<String>,
    pub compiled_context_task_profile: Option<String>,
    pub compiled_context_budget_profile_id: Option<String>,
    pub compiled_context_retrieval_query_type: Option<String>,
    pub compiled_context_graphrag_query_mode: Option<String>,
    pub compiled_context_selected_memory_tiers: Vec<String>,
    pub compiled_context_source_slices: Vec<CompiledContextSourceSliceSummary>,
    pub compiled_context_top_memory_ids: Vec<String>,
    pub compiled_context_preview: Option<String>,
    pub planner: Option<IntentPlannerAvailability>,
    pub execution: Option<PlanExecutionStatusSummary>,
    pub temporal_truth_view: Option<String>,
    pub temporal_subject_refs: Vec<String>,
    pub temporal_current_memory_ids: Vec<String>,
    pub temporal_historical_memory_ids: Vec<String>,
    pub temporal_track_count: usize,
    pub temporal_contradiction_count: usize,
    pub temporal_contradiction_ids: Vec<String>,
    pub temporal_preview: Option<String>,
    pub suggested_subagent_id: Option<String>,
    pub suggested_work_mode: Option<String>,
    pub influence_reason: String,
}

#[derive(Debug, Clone, Serialize)]
pub struct WorkstreamContextPacketMemoryHierarchyCount {
    pub memory_type: String,
    pub count: usize,
}

#[derive(Debug, Clone, Serialize)]
pub struct WorkstreamContextPacketHandoff {
    pub handoff_required: bool,
    pub recovery_required: bool,
    pub handoff_present: bool,
    pub last_handoff: Option<String>,
}

#[derive(Debug, Clone, Serialize)]
pub struct WorkstreamContextPacketLastResult {
    pub available: bool,
    pub reference: Option<WorkstreamLastResultReference>,
    pub summary: Option<WorkstreamContextPacketResultSummary>,
    pub manifest: Option<WorkstreamContextPacketManifestSummary>,
    pub error: Option<String>,
}

#[derive(Debug, Clone, Serialize)]
pub struct WorkstreamContextPacketResultSummary {
    pub job_id: u64,
    pub state: String,
    pub run_label: String,
    pub profile_id: String,
    pub node_list: String,
    pub manifest_key: String,
    pub source_phase: Option<String>,
    pub source_run_id: Option<String>,
}

#[derive(Debug, Clone, Serialize)]
pub struct WorkstreamContextPacketManifestSummary {
    pub job_id: u64,
    pub object_bucket: String,
    pub object_key: String,
    pub manifest_object_key: String,
    pub profile_id: Option<String>,
    pub run_label: Option<String>,
}

#[derive(Debug, Clone, Serialize)]
pub struct WorkstreamContextPacketPhysioSnapshot {
    pub hr: Option<f64>,
    pub hrv_level: Option<String>,
    pub spo2: Option<f64>,
    pub timestamp: Option<DateTime<Utc>>,
    pub source: Option<String>,
}

#[derive(Debug, Clone, Serialize)]
pub struct WorkstreamContextPacketExperimentFlags {
    pub hrv_aware: Option<bool>,
    pub observer_enabled: Option<bool>,
    pub serendipity_enabled: Option<bool>,
    pub triad_enabled: Option<bool>,
    pub provider: Option<String>,
    pub model: Option<String>,
    pub experiment_id: Option<String>,
    pub condition: Option<String>,
}

#[derive(Debug, Clone, Serialize)]
pub struct WorkstreamContextPacketMemoryHit {
    pub memory_id: Option<String>,
    pub source: String,
    pub conversation_id: Option<String>,
    pub turn_index: Option<usize>,
    pub role: Option<String>,
    pub snippet: String,
    pub timestamp: Option<DateTime<Utc>>,
    pub relevance: f32,
    pub tags: Vec<String>,
    pub domain: Option<String>,
    pub physio_snapshot: Option<WorkstreamContextPacketPhysioSnapshot>,
}

#[derive(Debug, Clone, Serialize)]
pub struct WorkstreamContextPacketRecipe {
    pub id: String,
    pub kind: String,
    pub summary: String,
}

pub async fn get_workstream_context_packet(
    data_dir: &Path,
    cfg: &BeagleConfig,
    gateway: &DarwinHpcGatewayClient,
    workstream_id: &str,
    augmentation: WorkstreamContextPacketAugmentation,
) -> anyhow::Result<WorkstreamContextPacketResponse> {
    let detail = get_workstream_control_room_detail(data_dir, cfg, workstream_id)?;
    let last_result = match get_workstream_control_room_last_result(data_dir, cfg, gateway, workstream_id)
        .await
    {
        Ok(response) => last_result_from_response(&response, None),
        Err(error) => last_result_from_reference(
            detail.last_result_reference.clone(),
            Some(error.to_string()),
        ),
    };

    Ok(WorkstreamContextPacketResponse {
        status: "ok".to_string(),
        phase: CONTEXT_PACKET_PHASE.to_string(),
        packet: context_packet_from_detail(cfg, &detail, last_result, augmentation),
    })
}

fn context_packet_from_detail(
    cfg: &BeagleConfig,
    detail: &crate::WorkstreamControlRoomDetailResponse,
    last_result: WorkstreamContextPacketLastResult,
    augmentation: WorkstreamContextPacketAugmentation,
) -> WorkstreamContextPacket {
    let workspace_id = detail
        .status_view
        .live_session
        .as_ref()
        .map(|session| session.workspace_id.clone())
        .or_else(|| non_empty_string(&detail.registry_entry.latest_governance_validation_workspace_id))
        .or_else(|| non_empty_string(&detail.registry_entry.latest_validation_workspace_id))
        .or_else(|| non_empty_string(&detail.spec.promotion_state.latest_validation_workspace_id))
        .or_else(|| non_empty_string(&detail.spec.promotion_state.canonical_workspace_id))
        .unwrap_or_else(|| cfg.workspace.canonical_workspace_id.clone());

    let session_id = detail
        .status_view
        .live_session
        .as_ref()
        .map(|session| session.session_id.clone())
        .or_else(|| non_empty_string(&detail.registry_entry.latest_governance_validation_session_id))
        .or_else(|| non_empty_string(&detail.registry_entry.latest_validation_session_id))
        .or_else(|| non_empty_string(&detail.registry_entry.canonical_session_id))
        .or_else(|| non_empty_string(&detail.spec.promotion_state.latest_validation_session_id))
        .or_else(|| non_empty_string(&detail.spec.promotion_state.canonical_session_id))
        .unwrap_or_else(|| "unassigned-session".to_string());

    WorkstreamContextPacket {
        packet_version: CONTEXT_PACKET_VERSION.to_string(),
        workstream_id: detail.registry_entry.id.clone(),
        workspace_id,
        session_id,
        repo: detail.spec.repo.clone(),
        branch: detail.spec.default_branch.clone(),
        governance_state: detail.status_view.governance_state.clone(),
        handoff: WorkstreamContextPacketHandoff {
            handoff_required: detail.handoff_view.handoff_required,
            recovery_required: detail.handoff_view.recovery_required,
            handoff_present: detail.handoff_view.handoff_present,
            last_handoff: detail.handoff_view.last_handoff.clone(),
        },
        last_result,
        last_successful_task: detail.handoff_view.last_successful_task.clone(),
        latest_physio: augmentation.latest_physio,
        experiment_flags: augmentation.experiment_flags,
        memory_hits: augmentation.memory_hits,
        retrieval_context: augmentation.retrieval_context,
        recommended_recipe: recommended_recipe_from_detail(detail),
        bounded_study_baseline: None,
    }
}

fn recommended_recipe_from_detail(
    detail: &crate::WorkstreamControlRoomDetailResponse,
) -> Option<WorkstreamContextPacketRecipe> {
    let live_session = detail.status_view.live_session.as_ref();
    let current_task = live_session.and_then(|session| session.current_task.as_ref());
    let last_task = detail.handoff_view.last_successful_task.as_ref();

    if let Some(recipe) = current_task
        .and_then(|task| recipe_for_task(detail, &task.task_kind, &task.profile_id))
        .or_else(|| last_task.and_then(|task| recipe_for_task(detail, &task.task_kind, &task.profile_id)))
    {
        return Some(recipe);
    }

    if detail.handoff_view.handoff_present && detail.handoff_view.recovery_required {
        if let Some(recipe) = recipe_by_kind(detail, "recovery_resume_loop") {
            return Some(recipe);
        }
    }

    recipe_by_kind(detail, "repo_native_dev_loop")
}

fn recipe_for_task(
    detail: &crate::WorkstreamControlRoomDetailResponse,
    task_kind: &str,
    profile_id: &str,
) -> Option<WorkstreamContextPacketRecipe> {
    let task_kind = task_kind.trim().to_ascii_lowercase();
    let profile_id = profile_id.trim();
    let profiles = &detail.spec.compute_profiles;

    if task_kind.contains("gpu") || profile_id == profiles.advanced_profile {
        return recipe_by_kind(detail, "operator_gpu_loop");
    }
    if task_kind.contains("cpu") || profile_id == profiles.batch_profile {
        return recipe_by_kind(detail, "operator_cpu_loop");
    }
    if task_kind.contains("repo") {
        return recipe_by_kind(detail, "repo_native_dev_loop");
    }

    None
}

fn recipe_by_kind(
    detail: &crate::WorkstreamControlRoomDetailResponse,
    kind: &str,
) -> Option<WorkstreamContextPacketRecipe> {
    detail.recipes.iter().find(|recipe| recipe.kind == kind).map(|recipe| {
        WorkstreamContextPacketRecipe {
            id: recipe.id.clone(),
            kind: recipe.kind.clone(),
            summary: recipe.summary.clone(),
        }
    })
}

fn last_result_from_response(
    response: &crate::WorkstreamControlRoomLastResultResponse,
    error: Option<String>,
) -> WorkstreamContextPacketLastResult {
    WorkstreamContextPacketLastResult {
        available: response.result.is_some(),
        reference: response.last_result_reference.clone(),
        summary: response.result.as_ref().map(result_summary_from_entry),
        manifest: response.manifest.as_ref().map(manifest_summary_from_manifest),
        error,
    }
}

fn last_result_from_reference(
    reference: Option<WorkstreamLastResultReference>,
    error: Option<String>,
) -> WorkstreamContextPacketLastResult {
    WorkstreamContextPacketLastResult {
        available: false,
        reference,
        summary: None,
        manifest: None,
        error,
    }
}

fn result_summary_from_entry(entry: &ResultCatalogEntry) -> WorkstreamContextPacketResultSummary {
    WorkstreamContextPacketResultSummary {
        job_id: entry.job_id,
        state: entry.state.clone(),
        run_label: entry.run_label.clone(),
        profile_id: entry.profile_id.clone(),
        node_list: entry.node_list.clone(),
        manifest_key: entry.artifact_manifest_key.clone(),
        source_phase: entry.source_phase.clone(),
        source_run_id: entry.source_run_id.clone(),
    }
}

fn manifest_summary_from_manifest(
    manifest: &ObjectResultManifest,
) -> WorkstreamContextPacketManifestSummary {
    WorkstreamContextPacketManifestSummary {
        job_id: manifest.job_id,
        object_bucket: manifest.object_bucket.clone(),
        object_key: manifest.object_key.clone(),
        manifest_object_key: manifest.manifest_object_key.clone(),
        profile_id: manifest.profile_id.clone(),
        run_label: manifest.run_label.clone(),
    }
}

fn non_empty_string(value: &str) -> Option<String> {
    let trimmed = value.trim();
    if trimmed.is_empty() {
        None
    } else {
        Some(trimmed.to_string())
    }
}
