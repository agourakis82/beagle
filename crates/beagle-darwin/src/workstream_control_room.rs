use crate::{
    DarwinHpcGatewayClient, ObjectResultManifest, ResultCatalogEntry, WorkspaceCurrentTask,
    WorkspaceLastSuccessfulTask, WorkspaceSessionState,
};
use crate::workstream_timeline::get_workstream_timeline;
use crate::workspace_plane::{
    bootstrap_workspace_session, load_workspace_session, workspace_plane_dir,
    workspace_sessions_dir, write_workspace_session, WorkspaceWorkstreamComputeProfiles,
    WorkspaceWorkstreamConsumerPolicy, WorkspaceWorkstreamGovernanceTransition,
    WorkspaceWorkstreamRecoveryPolicy, WorkspaceWorkstreamResultPlanePolicy,
};
use anyhow::{anyhow, Context};
use beagle_config::BeagleConfig;
use chrono::{DateTime, Utc};
use serde::de::DeserializeOwned;
use serde::{Deserialize, Serialize};
use serde_json::Value;
use std::{collections::BTreeMap, env, fs, io::Write, path::Path};

const REGISTRY_PATH: &str = "docs/darwin/hpc/workstreams/registry.yaml";
const WORKSTREAM_SPEC_PATH: &str = "docs/darwin/hpc/workstreams/beagle-darwin-hpc-governance.yaml";
const SECOND_WORKSTREAM_SPEC_PATH: &str = "docs/darwin/hpc/workstreams/beagle-darwin-hpc-wave1.yaml";
const THIRD_WORKSTREAM_SPEC_PATH: &str = "docs/darwin/hpc/workstreams/sounio-lang-main.yaml";
const RECIPE_REPO_NATIVE_PATH: &str =
    "docs/darwin/hpc/workstreams/recipes/beagle-darwin-hpc-governance.repo_native_dev_loop.yaml";
const RECIPE_OPERATOR_CPU_PATH: &str =
    "docs/darwin/hpc/workstreams/recipes/beagle-darwin-hpc-governance.operator_cpu_loop.yaml";
const RECIPE_OPERATOR_GPU_PATH: &str =
    "docs/darwin/hpc/workstreams/recipes/beagle-darwin-hpc-governance.operator_gpu_loop.yaml";
const RECIPE_RECOVERY_RESUME_PATH: &str =
    "docs/darwin/hpc/workstreams/recipes/beagle-darwin-hpc-governance.recovery_resume_loop.yaml";
const SECOND_RECIPE_REPO_NATIVE_PATH: &str =
    "docs/darwin/hpc/workstreams/recipes/beagle-darwin-hpc-wave1.repo_native_dev_loop.yaml";
const SECOND_RECIPE_OPERATOR_CPU_PATH: &str =
    "docs/darwin/hpc/workstreams/recipes/beagle-darwin-hpc-wave1.operator_cpu_loop.yaml";
const SECOND_RECIPE_RECOVERY_RESUME_PATH: &str =
    "docs/darwin/hpc/workstreams/recipes/beagle-darwin-hpc-wave1.recovery_resume_loop.yaml";
const THIRD_RECIPE_REPO_NATIVE_PATH: &str =
    "docs/darwin/hpc/workstreams/recipes/sounio-lang-main.repo_native_dev_loop.yaml";
const THIRD_RECIPE_OPERATOR_CPU_PATH: &str =
    "docs/darwin/hpc/workstreams/recipes/sounio-lang-main.operator_cpu_loop.yaml";
const THIRD_RECIPE_OPERATOR_GPU_PATH: &str =
    "docs/darwin/hpc/workstreams/recipes/sounio-lang-main.operator_gpu_loop.yaml";
const THIRD_RECIPE_RECOVERY_RESUME_PATH: &str =
    "docs/darwin/hpc/workstreams/recipes/sounio-lang-main.recovery_resume_loop.yaml";

const EMBEDDED_REGISTRY_YAML: &str = include_str!("../../../docs/darwin/hpc/workstreams/registry.yaml");
const EMBEDDED_WORKSTREAM_SPEC_YAML: &str =
    include_str!("../../../docs/darwin/hpc/workstreams/beagle-darwin-hpc-governance.yaml");
const EMBEDDED_SECOND_WORKSTREAM_SPEC_YAML: &str =
    include_str!("../../../docs/darwin/hpc/workstreams/beagle-darwin-hpc-wave1.yaml");
const EMBEDDED_THIRD_WORKSTREAM_SPEC_YAML: &str =
    include_str!("../../../docs/darwin/hpc/workstreams/sounio-lang-main.yaml");
const EMBEDDED_REPO_NATIVE_RECIPE_YAML: &str = include_str!(
    "../../../docs/darwin/hpc/workstreams/recipes/beagle-darwin-hpc-governance.repo_native_dev_loop.yaml"
);
const EMBEDDED_OPERATOR_CPU_RECIPE_YAML: &str = include_str!(
    "../../../docs/darwin/hpc/workstreams/recipes/beagle-darwin-hpc-governance.operator_cpu_loop.yaml"
);
const EMBEDDED_OPERATOR_GPU_RECIPE_YAML: &str = include_str!(
    "../../../docs/darwin/hpc/workstreams/recipes/beagle-darwin-hpc-governance.operator_gpu_loop.yaml"
);
const EMBEDDED_RECOVERY_RESUME_RECIPE_YAML: &str = include_str!(
    "../../../docs/darwin/hpc/workstreams/recipes/beagle-darwin-hpc-governance.recovery_resume_loop.yaml"
);
const EMBEDDED_SECOND_REPO_NATIVE_RECIPE_YAML: &str = include_str!(
    "../../../docs/darwin/hpc/workstreams/recipes/beagle-darwin-hpc-wave1.repo_native_dev_loop.yaml"
);
const EMBEDDED_SECOND_OPERATOR_CPU_RECIPE_YAML: &str = include_str!(
    "../../../docs/darwin/hpc/workstreams/recipes/beagle-darwin-hpc-wave1.operator_cpu_loop.yaml"
);
const EMBEDDED_SECOND_RECOVERY_RESUME_RECIPE_YAML: &str = include_str!(
    "../../../docs/darwin/hpc/workstreams/recipes/beagle-darwin-hpc-wave1.recovery_resume_loop.yaml"
);
const EMBEDDED_THIRD_REPO_NATIVE_RECIPE_YAML: &str = include_str!(
    "../../../docs/darwin/hpc/workstreams/recipes/sounio-lang-main.repo_native_dev_loop.yaml"
);
const EMBEDDED_THIRD_OPERATOR_CPU_RECIPE_YAML: &str = include_str!(
    "../../../docs/darwin/hpc/workstreams/recipes/sounio-lang-main.operator_cpu_loop.yaml"
);
const EMBEDDED_THIRD_OPERATOR_GPU_RECIPE_YAML: &str = include_str!(
    "../../../docs/darwin/hpc/workstreams/recipes/sounio-lang-main.operator_gpu_loop.yaml"
);
const EMBEDDED_THIRD_RECOVERY_RESUME_RECIPE_YAML: &str = include_str!(
    "../../../docs/darwin/hpc/workstreams/recipes/sounio-lang-main.recovery_resume_loop.yaml"
);

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct WorkstreamRegistryDocument {
    #[serde(default)]
    pub phase: String,
    #[serde(default)]
    pub mode: String,
    #[serde(default)]
    pub status: String,
    #[serde(default)]
    pub registry: WorkstreamRegistryMeta,
    #[serde(default)]
    pub workstreams: Vec<WorkstreamRegistryEntry>,
}

#[derive(Debug, Clone, Default, Serialize, Deserialize)]
pub struct WorkstreamRegistryMeta {
    #[serde(default)]
    pub root: String,
    #[serde(default)]
    pub canonical_format: String,
    #[serde(default)]
    pub recipe_root: String,
    #[serde(default)]
    pub governance_model: String,
    #[serde(default)]
    pub current_canonical_workstreams: Vec<String>,
}

#[derive(Debug, Clone, Default, Serialize, Deserialize)]
pub struct WorkstreamRegistryRecipeFiles {
    #[serde(default)]
    pub repo_native_dev_loop: String,
    #[serde(default)]
    pub operator_cpu_loop: String,
    #[serde(default)]
    pub operator_gpu_loop: String,
    #[serde(default)]
    pub recovery_resume_loop: String,
}

#[derive(Debug, Clone, Default, Serialize, Deserialize)]
pub struct WorkstreamRegistryEntry {
    #[serde(default)]
    pub id: String,
    #[serde(default)]
    pub spec_file: String,
    #[serde(default)]
    pub promotion_state: String,
    #[serde(default)]
    pub source_phase: String,
    #[serde(default)]
    pub cutover_workspace_id: String,
    #[serde(default)]
    pub canonical_session_id: String,
    #[serde(default)]
    pub latest_validation_phase: String,
    #[serde(default)]
    pub latest_validation_workspace_id: String,
    #[serde(default)]
    pub latest_validation_session_id: String,
    #[serde(default)]
    pub recipe_set_state: String,
    #[serde(default)]
    pub latest_recipe_validation_phase: String,
    #[serde(default)]
    pub latest_recipe_validation_workspace_id: String,
    #[serde(default)]
    pub latest_recipe_validation_session_id: String,
    #[serde(default)]
    pub governance_state: String,
    #[serde(default)]
    pub governance_last_transition: String,
    #[serde(default)]
    pub latest_governance_validation_phase: String,
    #[serde(default)]
    pub latest_governance_validation_workspace_id: String,
    #[serde(default)]
    pub latest_governance_validation_session_id: String,
    #[serde(default)]
    pub recipe_files: WorkstreamRegistryRecipeFiles,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct WorkstreamSpecDocument {
    pub id: String,
    pub repo: String,
    pub default_branch: String,
    pub branch_lineage: String,
    pub scope: String,
    pub default_dev_plane: String,
    pub vm_fallback_role: String,
    pub compute_profiles: WorkspaceWorkstreamComputeProfiles,
    pub result_plane: WorkspaceWorkstreamResultPlanePolicy,
    pub consumer_policy: WorkspaceWorkstreamConsumerPolicy,
    pub recovery_policy: WorkspaceWorkstreamRecoveryPolicy,
    pub recipes: WorkstreamSpecRecipeRegistry,
    pub promotion_state: WorkstreamSpecPromotionState,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct WorkstreamSpecRecipeRegistry {
    #[serde(default)]
    pub registry_root: String,
    #[serde(default)]
    pub validation_state: String,
    #[serde(default)]
    pub repo_native_dev_loop: String,
    #[serde(default)]
    pub operator_cpu_loop: String,
    #[serde(default)]
    pub operator_gpu_loop: String,
    #[serde(default)]
    pub recovery_resume_loop: String,
    #[serde(default)]
    pub latest_validation_phase: String,
    #[serde(default)]
    pub latest_validation_workspace_id: String,
    #[serde(default)]
    pub latest_validation_session_id: String,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct WorkstreamSpecPromotionState {
    #[serde(default)]
    pub state: String,
    #[serde(default)]
    pub last_transition: String,
    #[serde(default)]
    pub allowed_states: Vec<String>,
    #[serde(default)]
    pub allowed_transitions: Vec<WorkspaceWorkstreamGovernanceTransition>,
    #[serde(default)]
    pub source_phase: String,
    #[serde(default)]
    pub canonical_workspace_id: String,
    #[serde(default)]
    pub canonical_session_id: String,
    #[serde(default)]
    pub latest_validation_phase: String,
    #[serde(default)]
    pub latest_validation_workspace_id: String,
    #[serde(default)]
    pub latest_validation_session_id: String,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct WorkstreamRecipeStep {
    pub id: String,
    pub action: String,
    pub success_condition: String,
    pub recovery_point: String,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct WorkstreamRecipeDocument {
    pub api_version: String,
    pub phase: String,
    pub id: String,
    pub workstream: String,
    pub kind: String,
    pub summary: String,
    #[serde(default)]
    pub inputs: Value,
    #[serde(default)]
    pub steps: Vec<WorkstreamRecipeStep>,
    #[serde(default)]
    pub outputs: Value,
    #[serde(default)]
    pub recovery_points: Vec<String>,
    #[serde(default)]
    pub success_criteria: Vec<String>,
}

#[derive(Debug, Clone, Serialize)]
pub struct WorkstreamLiveSessionSummary {
    pub workspace_id: String,
    pub session_id: String,
    pub updated_at: DateTime<Utc>,
    pub active_dev_plane: String,
    pub fallback_active: bool,
    pub fallback_event_count: u64,
    pub last_handoff: Option<String>,
    pub last_workflow_kind: Option<String>,
    pub last_job_id: Option<u64>,
    pub last_job_state: Option<String>,
    pub last_job_profile_id: Option<String>,
    pub last_job_run_label: Option<String>,
    pub last_job_node_list: Option<String>,
    pub last_published_result_job_id: Option<u64>,
    pub last_published_result_run_label: Option<String>,
    pub last_published_result_profile_id: Option<String>,
    pub last_published_result_node_list: Option<String>,
    pub current_task: Option<WorkspaceCurrentTask>,
    pub last_successful_task: Option<WorkspaceLastSuccessfulTask>,
}

#[derive(Debug, Clone, Serialize)]
pub struct WorkstreamLastResultReference {
    pub job_id: u64,
    pub run_label: Option<String>,
    pub profile_id: Option<String>,
    pub node_list: Option<String>,
    pub manifest_key: Option<String>,
}

#[derive(Debug, Clone, Serialize)]
pub struct WorkstreamControlRoomActionAvailability {
    pub enabled: bool,
    pub endpoint: String,
    pub reason: String,
}

#[derive(Debug, Clone, Serialize)]
pub struct WorkstreamControlRoomActionSupport {
    pub hold: WorkstreamControlRoomActionAvailability,
    pub resume: WorkstreamControlRoomActionAvailability,
}

#[derive(Debug, Clone, Serialize)]
pub struct WorkstreamControlRoomListEntry {
    pub id: String,
    pub repo: String,
    pub default_branch: String,
    pub scope: String,
    pub default_dev_plane: String,
    pub vm_fallback_role: String,
    pub promotion_state: String,
    pub governance_last_transition: String,
    pub recipe_count: usize,
    pub latest_session: Option<WorkstreamLiveSessionSummary>,
    pub handoff_ready: bool,
    pub result_ready: bool,
}

#[derive(Debug, Clone, Serialize)]
pub struct WorkstreamControlRoomListResponse {
    pub status: String,
    pub registry_phase: String,
    pub registry_status: String,
    pub workstreams: Vec<WorkstreamControlRoomListEntry>,
}

#[derive(Debug, Clone, Serialize)]
pub struct WorkstreamPortfolioActivitySummary {
    pub event_id: String,
    pub event_kind: String,
    pub recorded_at: DateTime<Utc>,
    pub workspace_id: String,
    pub session_id: String,
    pub summary: String,
}

#[derive(Debug, Clone, Serialize)]
pub struct WorkstreamPortfolioEntry {
    pub id: String,
    pub repo: String,
    pub default_branch: String,
    pub scope: String,
    pub default_dev_plane: String,
    pub vm_fallback_role: String,
    pub governance_state: String,
    pub governance_last_transition: String,
    pub recipe_count: usize,
    pub live_session: Option<WorkstreamLiveSessionSummary>,
    pub handoff_present: bool,
    pub last_handoff: Option<String>,
    pub last_result_reference: Option<WorkstreamLastResultReference>,
    pub result_ready: bool,
    pub latest_activity: Option<WorkstreamPortfolioActivitySummary>,
    pub timeline_total_events: usize,
}

#[derive(Debug, Clone, Serialize)]
pub struct WorkstreamPortfolioSummary {
    pub total_workstreams: usize,
    pub canonical_workstreams: usize,
    pub live_sessions: usize,
    pub handoff_ready_workstreams: usize,
    pub result_ready_workstreams: usize,
    pub fallback_active_workstreams: usize,
    pub governance_states: BTreeMap<String, usize>,
}

#[derive(Debug, Clone, Serialize)]
pub struct WorkstreamPortfolioResponse {
    pub status: String,
    pub registry_phase: String,
    pub registry_status: String,
    pub canonical_workstream_ids: Vec<String>,
    pub summary: WorkstreamPortfolioSummary,
    pub workstreams: Vec<WorkstreamPortfolioEntry>,
}

#[derive(Debug, Clone, Serialize)]
pub struct WorkstreamControlRoomStatusResponse {
    pub status: String,
    pub workstream_id: String,
    pub repo: String,
    pub default_branch: String,
    pub scope: String,
    pub default_dev_plane: String,
    pub vm_fallback_role: String,
    pub governance_state: String,
    pub governance_last_transition: String,
    pub allowed_states: Vec<String>,
    pub allowed_transitions: Vec<WorkspaceWorkstreamGovernanceTransition>,
    pub recipe_ids: Vec<String>,
    pub recipe_count: usize,
    pub live_session: Option<WorkstreamLiveSessionSummary>,
    pub handoff_ready: bool,
    pub result_ready: bool,
    pub actions: WorkstreamControlRoomActionSupport,
}

#[derive(Debug, Clone, Serialize)]
pub struct WorkstreamControlRoomHandoffResponse {
    pub status: String,
    pub workstream_id: String,
    pub handoff_required: bool,
    pub recovery_required: bool,
    pub live_session: Option<WorkstreamLiveSessionSummary>,
    pub handoff_present: bool,
    pub last_handoff: Option<String>,
    pub last_successful_task: Option<WorkspaceLastSuccessfulTask>,
    pub last_result_reference: Option<WorkstreamLastResultReference>,
}

#[derive(Debug, Clone, Serialize)]
pub struct WorkstreamControlRoomLastResultResponse {
    pub status: String,
    pub workstream_id: String,
    pub live_session: Option<WorkstreamLiveSessionSummary>,
    pub last_result_reference: Option<WorkstreamLastResultReference>,
    pub result: Option<ResultCatalogEntry>,
    pub manifest: Option<ObjectResultManifest>,
}

#[derive(Debug, Clone, Serialize)]
pub struct WorkstreamControlRoomRecipeSetResponse {
    pub status: String,
    pub workstream_id: String,
    pub validation_state: String,
    pub latest_validation_phase: String,
    pub latest_validation_workspace_id: String,
    pub latest_validation_session_id: String,
    pub recipe_count: usize,
    pub recipes: Vec<WorkstreamRecipeDocument>,
}

#[derive(Debug, Clone, Serialize)]
pub struct WorkstreamControlRoomDetailResponse {
    pub status: String,
    pub registry_phase: String,
    pub registry_status: String,
    pub registry_entry: WorkstreamRegistryEntry,
    pub spec: WorkstreamSpecDocument,
    pub recipes: Vec<WorkstreamRecipeDocument>,
    pub status_view: WorkstreamControlRoomStatusResponse,
    pub handoff_view: WorkstreamControlRoomHandoffResponse,
    pub last_result_reference: Option<WorkstreamLastResultReference>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct WorkstreamGovernanceActionLedgerEntry {
    pub phase: String,
    pub workstream_id: String,
    pub workspace_id: String,
    pub session_id: String,
    pub canonical_repo: String,
    pub canonical_branch: String,
    pub action: String,
    pub from_state: String,
    pub to_state: String,
    pub active_dev_plane: String,
    pub fallback_active: bool,
    pub last_successful_task_job_id: Option<u64>,
    pub last_published_result_job_id: Option<u64>,
    pub previous_handoff: Option<String>,
    pub recorded_at: DateTime<Utc>,
}

#[derive(Debug, Clone, Serialize)]
pub struct WorkstreamControlRoomActionResponse {
    pub status: String,
    pub phase: String,
    pub workstream_id: String,
    pub action: String,
    pub workspace_id: String,
    pub session_id: String,
    pub previous_governance_state: String,
    pub governance_state: String,
    pub governance_last_transition: String,
    pub active_dev_plane: String,
    pub fallback_active: bool,
    pub last_handoff: Option<String>,
    pub last_successful_task: Option<WorkspaceLastSuccessfulTask>,
    pub last_result_reference: Option<WorkstreamLastResultReference>,
    pub ledger_appended: bool,
    pub recorded_at: DateTime<Utc>,
}

pub fn resolve_registered_workstream(workstream_id: &str) -> anyhow::Result<WorkstreamRegistryEntry> {
    let registry = load_registry_document()?;
    registry
        .workstreams
        .into_iter()
        .find(|entry| entry.id == workstream_id)
        .ok_or_else(|| anyhow!("workstream {} is not present in the canonical registry", workstream_id))
}

pub fn list_workstream_control_room(
    data_dir: &Path,
    cfg: &BeagleConfig,
) -> anyhow::Result<WorkstreamControlRoomListResponse> {
    let registry = load_registry_document()?;
    let mut workstreams = Vec::new();

    for entry in &registry.workstreams {
        let spec = load_workstream_spec(entry)?;
        let recipes = load_workstream_recipes(entry, &spec)?;
        let live_session = resolve_latest_workstream_session(data_dir, cfg, &entry.id)?;
        let handoff_ready = live_session
            .as_ref()
            .and_then(|session| session.last_handoff.as_ref())
            .map(|handoff| !handoff.trim().is_empty())
            .unwrap_or(false);
        let result_ready = live_session
            .as_ref()
            .and_then(last_result_reference_from_session)
            .is_some();

        workstreams.push(WorkstreamControlRoomListEntry {
            id: entry.id.clone(),
            repo: spec.repo,
            default_branch: spec.default_branch,
            scope: spec.scope,
            default_dev_plane: spec.default_dev_plane,
            vm_fallback_role: spec.vm_fallback_role,
            promotion_state: spec.promotion_state.state,
            governance_last_transition: spec.promotion_state.last_transition,
            recipe_count: recipes.len(),
            latest_session: live_session.as_ref().map(WorkstreamLiveSessionSummary::from),
            handoff_ready,
            result_ready,
        });
    }

    Ok(WorkstreamControlRoomListResponse {
        status: "ok".to_string(),
        registry_phase: registry.phase,
        registry_status: registry.status,
        workstreams,
    })
}

pub async fn get_workstream_portfolio_control_room(
    data_dir: &Path,
    cfg: &BeagleConfig,
    gateway: &DarwinHpcGatewayClient,
) -> anyhow::Result<WorkstreamPortfolioResponse> {
    let registry = load_registry_document()?;
    let mut workstreams = Vec::new();
    let mut governance_states = BTreeMap::new();
    let mut live_sessions = 0usize;
    let mut handoff_ready_workstreams = 0usize;
    let mut result_ready_workstreams = 0usize;
    let mut fallback_active_workstreams = 0usize;

    for entry in &registry.workstreams {
        let status = get_workstream_control_room_status(data_dir, cfg, &entry.id)?;
        let handoff = get_workstream_control_room_handoff(data_dir, cfg, &entry.id)?;
        let last_result = get_workstream_control_room_last_result(data_dir, cfg, gateway, &entry.id).await?;
        let timeline = get_workstream_timeline(data_dir, cfg, &entry.id, Some(1))?;

        let latest_activity = timeline.events.first().map(|event| WorkstreamPortfolioActivitySummary {
            event_id: event.event_id.clone(),
            event_kind: event.event_kind.clone(),
            recorded_at: event.recorded_at,
            workspace_id: event.workspace_id.clone(),
            session_id: event.session_id.clone(),
            summary: event.summary.clone(),
        });

        if status.live_session.is_some() {
            live_sessions += 1;
        }
        if status.handoff_ready {
            handoff_ready_workstreams += 1;
        }
        if status.result_ready {
            result_ready_workstreams += 1;
        }
        if status
            .live_session
            .as_ref()
            .map(|session| session.fallback_active)
            .unwrap_or(false)
        {
            fallback_active_workstreams += 1;
        }
        *governance_states
            .entry(status.governance_state.clone())
            .or_insert(0usize) += 1;

        workstreams.push(WorkstreamPortfolioEntry {
            id: entry.id.clone(),
            repo: status.repo,
            default_branch: status.default_branch,
            scope: status.scope,
            default_dev_plane: status.default_dev_plane,
            vm_fallback_role: status.vm_fallback_role,
            governance_state: status.governance_state,
            governance_last_transition: status.governance_last_transition,
            recipe_count: status.recipe_count,
            live_session: status.live_session,
            handoff_present: handoff.handoff_present,
            last_handoff: handoff.last_handoff,
            last_result_reference: last_result.last_result_reference,
            result_ready: last_result.result.is_some() && last_result.manifest.is_some(),
            latest_activity,
            timeline_total_events: timeline.total_events,
        });
    }

    Ok(WorkstreamPortfolioResponse {
        status: "ok".to_string(),
        registry_phase: registry.phase,
        registry_status: registry.status,
        canonical_workstream_ids: registry.registry.current_canonical_workstreams.clone(),
        summary: WorkstreamPortfolioSummary {
            total_workstreams: workstreams.len(),
            canonical_workstreams: registry.registry.current_canonical_workstreams.len(),
            live_sessions,
            handoff_ready_workstreams,
            result_ready_workstreams,
            fallback_active_workstreams,
            governance_states,
        },
        workstreams,
    })
}

pub fn get_workstream_control_room_recipes(
    workstream_id: &str,
) -> anyhow::Result<WorkstreamControlRoomRecipeSetResponse> {
    let entry = resolve_registered_workstream(workstream_id)?;
    let spec = load_workstream_spec(&entry)?;
    let recipes = load_workstream_recipes(&entry, &spec)?;

    Ok(WorkstreamControlRoomRecipeSetResponse {
        status: "ok".to_string(),
        workstream_id: workstream_id.to_string(),
        validation_state: spec.recipes.validation_state,
        latest_validation_phase: spec.recipes.latest_validation_phase,
        latest_validation_workspace_id: spec.recipes.latest_validation_workspace_id,
        latest_validation_session_id: spec.recipes.latest_validation_session_id,
        recipe_count: recipes.len(),
        recipes,
    })
}

pub fn get_workstream_control_room_status(
    data_dir: &Path,
    cfg: &BeagleConfig,
    workstream_id: &str,
) -> anyhow::Result<WorkstreamControlRoomStatusResponse> {
    let entry = resolve_registered_workstream(workstream_id)?;
    let spec = load_workstream_spec(&entry)?;
    let recipes = load_workstream_recipes(&entry, &spec)?;
    let recipe_ids = recipes.iter().map(|recipe| recipe.id.clone()).collect::<Vec<_>>();
    let live_session = resolve_latest_workstream_session(data_dir, cfg, workstream_id)?;
    let handoff_ready = live_session
        .as_ref()
        .and_then(|session| session.last_handoff.as_ref())
        .map(|handoff| !handoff.trim().is_empty())
        .unwrap_or(false);
    let result_ready = live_session
        .as_ref()
        .and_then(last_result_reference_from_session)
        .is_some();

    let governance_state = live_session
        .as_ref()
        .map(|session| session.workstream_cutover_policy.promotion_state.state.clone())
        .unwrap_or_else(|| spec.promotion_state.state.clone());
    let governance_last_transition = live_session
        .as_ref()
        .map(|session| session.workstream_cutover_policy.promotion_state.last_transition.clone())
        .unwrap_or_else(|| spec.promotion_state.last_transition.clone());
    let allowed_states = spec.promotion_state.allowed_states.clone();
    let allowed_transitions = spec.promotion_state.allowed_transitions.clone();

    Ok(WorkstreamControlRoomStatusResponse {
        status: "ok".to_string(),
        workstream_id: workstream_id.to_string(),
        repo: spec.repo.clone(),
        default_branch: spec.default_branch.clone(),
        scope: spec.scope.clone(),
        default_dev_plane: spec.default_dev_plane.clone(),
        vm_fallback_role: spec.vm_fallback_role.clone(),
        governance_state: governance_state.clone(),
        governance_last_transition: governance_last_transition,
        allowed_states,
        allowed_transitions: allowed_transitions.clone(),
        recipe_ids,
        recipe_count: recipes.len(),
        live_session: live_session.as_ref().map(WorkstreamLiveSessionSummary::from),
        handoff_ready,
        result_ready,
        actions: bounded_actions(workstream_id, &governance_state, &allowed_transitions),
    })
}

pub fn get_workstream_control_room_handoff(
    data_dir: &Path,
    cfg: &BeagleConfig,
    workstream_id: &str,
) -> anyhow::Result<WorkstreamControlRoomHandoffResponse> {
    let entry = resolve_registered_workstream(workstream_id)?;
    let spec = load_workstream_spec(&entry)?;
    let live_session = resolve_latest_workstream_session(data_dir, cfg, workstream_id)?;

    Ok(WorkstreamControlRoomHandoffResponse {
        status: "ok".to_string(),
        workstream_id: workstream_id.to_string(),
        handoff_required: spec.recovery_policy.handoff_required,
        recovery_required: spec.recovery_policy.recovery_required,
        live_session: live_session.as_ref().map(WorkstreamLiveSessionSummary::from),
        handoff_present: live_session
            .as_ref()
            .and_then(|session| session.last_handoff.as_ref())
            .map(|handoff| !handoff.trim().is_empty())
            .unwrap_or(false),
        last_handoff: live_session.as_ref().and_then(|session| session.last_handoff.clone()),
        last_successful_task: live_session
            .as_ref()
            .and_then(|session| session.last_successful_task.clone()),
        last_result_reference: live_session
            .as_ref()
            .and_then(last_result_reference_from_session),
    })
}

pub async fn get_workstream_control_room_last_result(
    data_dir: &Path,
    cfg: &BeagleConfig,
    gateway: &DarwinHpcGatewayClient,
    workstream_id: &str,
) -> anyhow::Result<WorkstreamControlRoomLastResultResponse> {
    let _entry = resolve_registered_workstream(workstream_id)?;
    let live_session = resolve_latest_workstream_session(data_dir, cfg, workstream_id)?;
    let last_result_reference = live_session
        .as_ref()
        .and_then(last_result_reference_from_session);

    let (result, manifest) = if let Some(reference) = &last_result_reference {
        let result = gateway
            .result_by_job(reference.job_id)
            .await
            .map_err(|error| anyhow!(error.to_string()))?;
        let manifest = gateway
            .result_manifest(reference.job_id)
            .await
            .map_err(|error| anyhow!(error.to_string()))?;
        (Some(result), Some(manifest))
    } else {
        (None, None)
    };

    Ok(WorkstreamControlRoomLastResultResponse {
        status: "ok".to_string(),
        workstream_id: workstream_id.to_string(),
        live_session: live_session.as_ref().map(WorkstreamLiveSessionSummary::from),
        last_result_reference,
        result,
        manifest,
    })
}

pub fn get_workstream_control_room_detail(
    data_dir: &Path,
    cfg: &BeagleConfig,
    workstream_id: &str,
) -> anyhow::Result<WorkstreamControlRoomDetailResponse> {
    let registry = load_registry_document()?;
    let entry = registry
        .workstreams
        .iter()
        .find(|entry| entry.id == workstream_id)
        .cloned()
        .ok_or_else(|| anyhow!("workstream {} is not present in the canonical registry", workstream_id))?;
    let spec = load_workstream_spec(&entry)?;
    let recipes = load_workstream_recipes(&entry, &spec)?;
    let status_view = get_workstream_control_room_status(data_dir, cfg, workstream_id)?;
    let handoff_view = get_workstream_control_room_handoff(data_dir, cfg, workstream_id)?;
    let last_result_reference = handoff_view.last_result_reference.clone();

    Ok(WorkstreamControlRoomDetailResponse {
        status: "ok".to_string(),
        registry_phase: registry.phase,
        registry_status: registry.status,
        registry_entry: entry,
        spec,
        recipes,
        status_view,
        handoff_view,
        last_result_reference,
    })
}

pub fn run_workstream_control_room_action(
    data_dir: &Path,
    cfg: &BeagleConfig,
    workstream_id: &str,
    action: &str,
) -> anyhow::Result<WorkstreamControlRoomActionResponse> {
    let entry = resolve_registered_workstream(workstream_id)?;
    let spec = load_workstream_spec(&entry)?;
    let mut session = resolve_mutable_workstream_session(data_dir, cfg, workstream_id)?;

    if session.workstream_cutover_policy.workstream_name != workstream_id {
        return Err(anyhow!(
            "latest session {} is not bound to workstream {}",
            session.workspace_id,
            workstream_id
        ));
    }
    if session.current_task.is_some() {
        return Err(anyhow!(
            "bounded control-room action {} cannot run while a current task is active",
            action
        ));
    }

    let current_state = session.workstream_cutover_policy.promotion_state.state.clone();
    let transition = allowed_governance_transition(
        &current_state,
        action,
        &session
            .workstream_cutover_policy
            .promotion_state
            .allowed_transitions,
    )
    .or_else(|| {
        allowed_governance_transition(&current_state, action, &spec.promotion_state.allowed_transitions)
    })
    .cloned()
    .ok_or_else(|| {
        anyhow!(
            "bounded control-room action {} is not allowed from current state {}",
            action,
            current_state
        )
    })?;

    let recorded_at = Utc::now();
    let previous_handoff = session.last_handoff.clone();
    let last_successful_task_job_id = session
        .last_successful_task
        .as_ref()
        .map(|task| task.submitted_job_id);
    let last_published_result_job_id = session.last_published_result_job_id;
    let last_result_reference = last_result_reference_from_session(&session);

    session.updated_at = recorded_at;
    session.workstream_cutover_policy.cutover_state = transition.to.clone();
    session.workstream_cutover_policy.promotion_state.state = transition.to.clone();
    session.workstream_cutover_policy.promotion_state.last_transition = transition.name.clone();
    session.last_handoff = Some(format!(
        "workspace={} repo={} branch={} session={} governance action {} moved {} -> {}; previous_handoff={} last_successful_task_job_id={} last_result_job_id={}",
        session.workspace_id,
        session.canonical_repo,
        session.canonical_branch,
        session.session_id,
        transition.name,
        current_state,
        transition.to,
        previous_handoff.as_deref().unwrap_or("none"),
        last_successful_task_job_id
            .map(|job_id| job_id.to_string())
            .unwrap_or_else(|| "none".to_string()),
        last_published_result_job_id
            .map(|job_id| job_id.to_string())
            .unwrap_or_else(|| "none".to_string())
    ));

    write_workspace_session(data_dir, &session)?;
    append_workstream_governance_action(
        data_dir,
        &WorkstreamGovernanceActionLedgerEntry {
            phase: "B15.3".to_string(),
            workstream_id: workstream_id.to_string(),
            workspace_id: session.workspace_id.clone(),
            session_id: session.session_id.clone(),
            canonical_repo: session.canonical_repo.clone(),
            canonical_branch: session.canonical_branch.clone(),
            action: transition.name.clone(),
            from_state: current_state.clone(),
            to_state: transition.to.clone(),
            active_dev_plane: session.active_dev_plane.clone(),
            fallback_active: session.fallback_active,
            last_successful_task_job_id,
            last_published_result_job_id,
            previous_handoff,
            recorded_at,
        },
    )?;

    Ok(WorkstreamControlRoomActionResponse {
        status: "ok".to_string(),
        phase: "B15.3".to_string(),
        workstream_id: workstream_id.to_string(),
        action: transition.name.clone(),
        workspace_id: session.workspace_id.clone(),
        session_id: session.session_id.clone(),
        previous_governance_state: current_state,
        governance_state: session.workstream_cutover_policy.promotion_state.state.clone(),
        governance_last_transition: session
            .workstream_cutover_policy
            .promotion_state
            .last_transition
            .clone(),
        active_dev_plane: session.active_dev_plane.clone(),
        fallback_active: session.fallback_active,
        last_handoff: session.last_handoff.clone(),
        last_successful_task: session.last_successful_task.clone(),
        last_result_reference,
        ledger_appended: true,
        recorded_at,
    })
}

impl From<&WorkspaceSessionState> for WorkstreamLiveSessionSummary {
    fn from(session: &WorkspaceSessionState) -> Self {
        Self {
            workspace_id: session.workspace_id.clone(),
            session_id: session.session_id.clone(),
            updated_at: session.updated_at,
            active_dev_plane: session.active_dev_plane.clone(),
            fallback_active: session.fallback_active,
            fallback_event_count: session.fallback_event_count,
            last_handoff: session.last_handoff.clone(),
            last_workflow_kind: session.last_workflow_kind.clone(),
            last_job_id: session.last_job_id,
            last_job_state: session.last_job_state.clone(),
            last_job_profile_id: session.last_job_profile_id.clone(),
            last_job_run_label: session.last_job_run_label.clone(),
            last_job_node_list: session.last_job_node_list.clone(),
            last_published_result_job_id: session.last_published_result_job_id,
            last_published_result_run_label: session.last_published_result_run_label.clone(),
            last_published_result_profile_id: session.last_published_result_profile_id.clone(),
            last_published_result_node_list: session.last_published_result_node_list.clone(),
            current_task: session.current_task.clone(),
            last_successful_task: session.last_successful_task.clone(),
        }
    }
}

fn bounded_actions(
    workstream_id: &str,
    governance_state: &str,
    allowed_transitions: &[WorkspaceWorkstreamGovernanceTransition],
) -> WorkstreamControlRoomActionSupport {
    let hold_enabled = allowed_governance_transition(governance_state, "hold", allowed_transitions).is_some();
    let resume_enabled =
        allowed_governance_transition(governance_state, "resume", allowed_transitions).is_some();

    WorkstreamControlRoomActionSupport {
        hold: WorkstreamControlRoomActionAvailability {
            enabled: hold_enabled,
            endpoint: format!("/api/darwin/workstreams/{workstream_id}/hold"),
            reason: if hold_enabled {
                "Bounded governance action available from the current workstream state.".to_string()
            } else {
                format!(
                    "Bounded hold is not available from current state {}; only explicit allowed transitions are exposed here.",
                    governance_state
                )
            },
        },
        resume: WorkstreamControlRoomActionAvailability {
            enabled: resume_enabled,
            endpoint: format!("/api/darwin/workstreams/{workstream_id}/resume"),
            reason: if resume_enabled {
                "Bounded governance action available from the current workstream state.".to_string()
            } else {
                format!(
                    "Bounded resume is not available from current state {}; only explicit allowed transitions are exposed here.",
                    governance_state
                )
            },
        },
    }
}

fn allowed_governance_transition<'a>(
    current_state: &str,
    action: &str,
    allowed_transitions: &'a [WorkspaceWorkstreamGovernanceTransition],
) -> Option<&'a WorkspaceWorkstreamGovernanceTransition> {
    allowed_transitions.iter().find(|transition| {
        transition.name == action && transition.from == current_state
    })
}

fn workstream_governance_action_ledger_path(data_dir: &Path) -> std::path::PathBuf {
    workspace_plane_dir(data_dir).join("workstream-governance-actions.jsonl")
}

fn append_workstream_governance_action(
    data_dir: &Path,
    entry: &WorkstreamGovernanceActionLedgerEntry,
) -> anyhow::Result<()> {
    let path = workstream_governance_action_ledger_path(data_dir);
    if let Some(parent) = path.parent() {
        fs::create_dir_all(parent).with_context(|| {
            format!(
                "failed to create workstream governance action ledger dir {}",
                parent.display()
            )
        })?;
    }

    let mut file = fs::OpenOptions::new()
        .create(true)
        .append(true)
        .open(&path)
        .with_context(|| {
            format!(
                "failed to open workstream governance action ledger {}",
                path.display()
            )
        })?;
    let line = serde_json::to_string(entry)?;
    writeln!(file, "{line}").with_context(|| {
        format!(
            "failed to append workstream governance action ledger {}",
            path.display()
        )
    })
}

fn resolve_mutable_workstream_session(
    data_dir: &Path,
    cfg: &BeagleConfig,
    workstream_id: &str,
) -> anyhow::Result<WorkspaceSessionState> {
    if let Some(session) = resolve_latest_workstream_session(data_dir, cfg, workstream_id)? {
        return Ok(session);
    }

    if cfg.workspace.cutover_workstream != workstream_id {
        return Err(anyhow!(
            "no live session recorded for workstream {} and it is not the canonical cutover workstream",
            workstream_id
        ));
    }

    bootstrap_workspace_session(
        data_dir,
        cfg,
        Some(&cfg.workspace.canonical_workspace_id),
        None,
    )?;

    load_workspace_session(data_dir, cfg, &cfg.workspace.canonical_workspace_id)?
        .ok_or_else(|| {
            anyhow!(
                "failed to resolve mutable workstream session for {} after bootstrap",
                workstream_id
            )
        })
}

fn last_result_reference_from_session(
    session: &WorkspaceSessionState,
) -> Option<WorkstreamLastResultReference> {
    session
        .last_published_result_job_id
        .map(|job_id| WorkstreamLastResultReference {
            job_id,
            run_label: session.last_published_result_run_label.clone(),
            profile_id: session.last_published_result_profile_id.clone(),
            node_list: session.last_published_result_node_list.clone(),
            manifest_key: session.last_published_manifest_key.clone(),
        })
}

fn load_registry_document() -> anyhow::Result<WorkstreamRegistryDocument> {
    load_yaml_document(REGISTRY_PATH)
}

fn load_workstream_spec(entry: &WorkstreamRegistryEntry) -> anyhow::Result<WorkstreamSpecDocument> {
    load_yaml_document(&entry.spec_file)
}

fn load_workstream_recipes(
    entry: &WorkstreamRegistryEntry,
    spec: &WorkstreamSpecDocument,
) -> anyhow::Result<Vec<WorkstreamRecipeDocument>> {
    let mut recipes = Vec::new();

    for recipe_path in recipe_paths_in_order(entry, spec) {
        recipes.push(load_yaml_document(recipe_path)?);
    }

    Ok(recipes)
}

fn recipe_paths_in_order<'a>(
    entry: &'a WorkstreamRegistryEntry,
    spec: &'a WorkstreamSpecDocument,
) -> Vec<&'a str> {
    let registry_paths = [
        entry.recipe_files.repo_native_dev_loop.as_str(),
        entry.recipe_files.operator_cpu_loop.as_str(),
        entry.recipe_files.operator_gpu_loop.as_str(),
        entry.recipe_files.recovery_resume_loop.as_str(),
    ];

    let mut ordered = registry_paths
        .into_iter()
        .filter(|path| !path.trim().is_empty())
        .collect::<Vec<_>>();

    if ordered.is_empty() {
        ordered = [
            spec.recipes.repo_native_dev_loop.as_str(),
            spec.recipes.operator_cpu_loop.as_str(),
            spec.recipes.operator_gpu_loop.as_str(),
            spec.recipes.recovery_resume_loop.as_str(),
        ]
        .into_iter()
        .filter(|path| !path.trim().is_empty())
        .collect::<Vec<_>>();
    }

    ordered
}

fn load_yaml_document<T>(path: &str) -> anyhow::Result<T>
where
    T: DeserializeOwned,
{
    let body = load_document_text(path)?;
    serde_yaml::from_str::<T>(&body)
        .with_context(|| format!("failed to decode workstream control-room document {}", path))
}

fn load_document_text(path: &str) -> anyhow::Result<String> {
    if let Some(contents) = load_document_text_from_fs(path)? {
        return Ok(contents);
    }

    embedded_document(path)
        .map(str::to_string)
        .ok_or_else(|| anyhow!("workstream control-room document {} is not embedded", path))
}

fn load_document_text_from_fs(path: &str) -> anyhow::Result<Option<String>> {
    let mut candidate_roots = Vec::new();

    if let Ok(root) = env::var("BEAGLE_REPO_ROOT") {
        if !root.trim().is_empty() {
            candidate_roots.push(root);
        }
    }

    if let Ok(current_dir) = env::current_dir() {
        candidate_roots.push(current_dir.display().to_string());
    }

    for root in candidate_roots {
        let candidate = Path::new(&root).join(path);
        if candidate.exists() {
            let contents = fs::read_to_string(&candidate).with_context(|| {
                format!("failed to read workstream control-room document {}", candidate.display())
            })?;
            return Ok(Some(contents));
        }
    }

    Ok(None)
}

fn embedded_document(path: &str) -> Option<&'static str> {
    match path {
        REGISTRY_PATH => Some(EMBEDDED_REGISTRY_YAML),
        WORKSTREAM_SPEC_PATH => Some(EMBEDDED_WORKSTREAM_SPEC_YAML),
        SECOND_WORKSTREAM_SPEC_PATH => Some(EMBEDDED_SECOND_WORKSTREAM_SPEC_YAML),
        THIRD_WORKSTREAM_SPEC_PATH => Some(EMBEDDED_THIRD_WORKSTREAM_SPEC_YAML),
        RECIPE_REPO_NATIVE_PATH => Some(EMBEDDED_REPO_NATIVE_RECIPE_YAML),
        RECIPE_OPERATOR_CPU_PATH => Some(EMBEDDED_OPERATOR_CPU_RECIPE_YAML),
        RECIPE_OPERATOR_GPU_PATH => Some(EMBEDDED_OPERATOR_GPU_RECIPE_YAML),
        RECIPE_RECOVERY_RESUME_PATH => Some(EMBEDDED_RECOVERY_RESUME_RECIPE_YAML),
        SECOND_RECIPE_REPO_NATIVE_PATH => Some(EMBEDDED_SECOND_REPO_NATIVE_RECIPE_YAML),
        SECOND_RECIPE_OPERATOR_CPU_PATH => Some(EMBEDDED_SECOND_OPERATOR_CPU_RECIPE_YAML),
        SECOND_RECIPE_RECOVERY_RESUME_PATH => Some(EMBEDDED_SECOND_RECOVERY_RESUME_RECIPE_YAML),
        THIRD_RECIPE_REPO_NATIVE_PATH => Some(EMBEDDED_THIRD_REPO_NATIVE_RECIPE_YAML),
        THIRD_RECIPE_OPERATOR_CPU_PATH => Some(EMBEDDED_THIRD_OPERATOR_CPU_RECIPE_YAML),
        THIRD_RECIPE_OPERATOR_GPU_PATH => Some(EMBEDDED_THIRD_OPERATOR_GPU_RECIPE_YAML),
        THIRD_RECIPE_RECOVERY_RESUME_PATH => Some(EMBEDDED_THIRD_RECOVERY_RESUME_RECIPE_YAML),
        _ => None,
    }
}

fn resolve_latest_workstream_session(
    data_dir: &Path,
    cfg: &BeagleConfig,
    workstream_id: &str,
) -> anyhow::Result<Option<WorkspaceSessionState>> {
    let sessions_dir = workspace_sessions_dir(data_dir);
    if !sessions_dir.exists() {
        return Ok(None);
    }

    let mut latest: Option<(DateTime<Utc>, String)> = None;

    for entry in fs::read_dir(&sessions_dir)
        .with_context(|| format!("failed to read workspace sessions dir {}", sessions_dir.display()))?
    {
        let entry = entry?;
        let path = entry.path();
        if path.extension().and_then(|value| value.to_str()) != Some("json") {
            continue;
        }

        let Ok(contents) = fs::read_to_string(&path) else {
            continue;
        };
        let Ok(session) = serde_json::from_str::<WorkspaceSessionState>(&contents) else {
            continue;
        };

        if session.workstream_cutover_policy.workstream_name != workstream_id {
            continue;
        }

        let candidate = (session.updated_at, session.workspace_id.clone());
        let should_replace = latest
            .as_ref()
            .map(|(updated_at, _)| candidate.0 > *updated_at)
            .unwrap_or(true);
        if should_replace {
            latest = Some(candidate);
        }
    }

    if let Some((_, workspace_id)) = latest {
        return load_workspace_session(data_dir, cfg, &workspace_id);
    }

    if cfg.workspace.cutover_workstream == workstream_id {
        return load_workspace_session(data_dir, cfg, &cfg.workspace.canonical_workspace_id);
    }

    Ok(None)
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::workspace_plane::{write_workspace_session, WorkspaceLastSuccessfulTask};
    use beagle_config::{
        AdvancedModulesConfig, ConsumerAccessConfig, GraphConfig, HermesConfig, LlmConfig,
        ObserverThresholds, StorageConfig, ToolBridgeConfig, WorkspaceHabitatConfig,
        WorkspacePlaneConfig,
    };
    use chrono::Utc;
    use std::fs;
    use std::path::{Path, PathBuf};
    use std::sync::Mutex;
    use std::time::{SystemTime, UNIX_EPOCH};
    use tokio::io::{AsyncReadExt, AsyncWriteExt};
    use tokio::net::TcpListener;

    const CANONICAL_WORKSTREAM_ID: &str = "beagle-darwin-hpc-governance";
    const SECOND_WORKSTREAM_ID: &str = "beagle-darwin-hpc-wave1";
    static ENV_LOCK: Mutex<()> = Mutex::new(());

    struct TestDir {
        path: PathBuf,
    }

    impl TestDir {
        fn new(label: &str) -> Self {
            let unique = SystemTime::now()
                .duration_since(UNIX_EPOCH)
                .unwrap()
                .as_nanos();
            let path = std::env::temp_dir().join(format!(
                "beagle-darwin-workstream-control-room-{label}-{}-{unique}",
                std::process::id()
            ));
            fs::create_dir_all(&path).unwrap();
            Self { path }
        }

        fn path(&self) -> &Path {
            &self.path
        }
    }

    impl Drop for TestDir {
        fn drop(&mut self) {
            let _ = fs::remove_dir_all(&self.path);
        }
    }

    fn test_config(data_dir: &Path) -> BeagleConfig {
        BeagleConfig {
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
                canonical_workspace_id: "test-workstream-control-room".to_string(),
                canonical_repo: "agourakis82/beagle".to_string(),
                canonical_branch: "feat/darwin-hpc-governance".to_string(),
                canonical_track: "darwin-hpc".to_string(),
                operator_name: Some("test-operator".to_string()),
                default_dev_plane: "beagle-cluster".to_string(),
                vm_fallback_role: "fallback-only".to_string(),
                promotion_scope: "beagle-darwin-hpc-general-noninfra".to_string(),
                cutover_workstream: CANONICAL_WORKSTREAM_ID.to_string(),
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
        }
    }

    fn seeded_session(cfg: &BeagleConfig, workspace_id: &str, session_id: &str) -> WorkspaceSessionState {
        let mut session = WorkspaceSessionState::new(
            cfg,
            workspace_id.to_string(),
            Some(session_id.to_string()),
        );
        session.updated_at = Utc::now();
        session
    }

    fn last_successful_task_for(
        session_id: &str,
        branch: &str,
        profile_id: &str,
        submitted_job_id: u64,
        published_result_job_id: u64,
    ) -> WorkspaceLastSuccessfulTask {
        WorkspaceLastSuccessfulTask {
            task_kind: "advanced_operator_gpu_workflow".to_string(),
            task_state: "completed".to_string(),
            profile_id: profile_id.to_string(),
            workflow_run_label: format!("{branch}-workflow"),
            execution_node: Some("r740-proxmox".to_string()),
            resolved_result_node: Some("r740-proxmox".to_string()),
            repo: "agourakis82/beagle".to_string(),
            branch: branch.to_string(),
            session_id: session_id.to_string(),
            submitted_job_id,
            published_result_job_id,
            published_result_run_label: format!("{branch}-result"),
            completed_at: Utc::now(),
        }
    }

    fn last_successful_task(session_id: &str) -> WorkspaceLastSuccessfulTask {
        last_successful_task_for(
            session_id,
            "feat/darwin-hpc-governance",
            "gpu-single-v1",
            53,
            32,
        )
    }

    async fn spawn_gateway_server(
        result: ResultCatalogEntry,
        manifest: ObjectResultManifest,
    ) -> (String, tokio::task::JoinHandle<()>) {
        let listener = TcpListener::bind("127.0.0.1:0").await.unwrap();
        let base_url = format!("http://{}", listener.local_addr().unwrap());
        let result_body = serde_json::to_vec(&result).unwrap();
        let manifest_body = serde_json::to_vec(&manifest).unwrap();

        let handle = tokio::spawn(async move {
            for _ in 0..2 {
                let (mut stream, _) = listener.accept().await.unwrap();
                let mut buf = [0u8; 4096];
                let read = stream.read(&mut buf).await.unwrap();
                let request = String::from_utf8_lossy(&buf[..read]);
                let first_line = request.lines().next().unwrap_or_default();
                let (status_line, body) = if first_line.starts_with("GET /results/42/manifest ") {
                    ("HTTP/1.1 200 OK\r\n", manifest_body.as_slice())
                } else if first_line.starts_with("GET /results/42 ") {
                    ("HTTP/1.1 200 OK\r\n", result_body.as_slice())
                } else {
                    ("HTTP/1.1 404 Not Found\r\n", b"{\"error\":\"not_found\"}" as &[u8])
                };

                let headers = format!(
                    "{status_line}content-type: application/json\r\ncontent-length: {}\r\nconnection: close\r\n\r\n",
                    body.len()
                );
                stream.write_all(headers.as_bytes()).await.unwrap();
                stream.write_all(body).await.unwrap();
            }
        });

        (base_url, handle)
    }

    #[test]
    fn list_returns_canonical_workstream_and_preserves_governance_and_recipe_count() {
        let dir = TestDir::new("list");
        let cfg = test_config(dir.path());

        let response = list_workstream_control_room(dir.path(), &cfg).unwrap();
        let workstream = response
            .workstreams
            .iter()
            .find(|entry| entry.id == CANONICAL_WORKSTREAM_ID)
            .unwrap();

        assert_eq!(response.status, "ok");
        assert_eq!(workstream.id, CANONICAL_WORKSTREAM_ID);
        assert_eq!(workstream.promotion_state, "canonical");
        assert_eq!(workstream.governance_last_transition, "resume");
        assert_eq!(workstream.recipe_count, 4);
    }

    #[test]
    fn list_and_recipes_include_second_workstream_from_registry() {
        let dir = TestDir::new("second-workstream-list");
        let cfg = test_config(dir.path());

        let list = list_workstream_control_room(dir.path(), &cfg).unwrap();
        let detail = get_workstream_control_room_detail(dir.path(), &cfg, SECOND_WORKSTREAM_ID).unwrap();
        let recipes = get_workstream_control_room_recipes(SECOND_WORKSTREAM_ID).unwrap();

        let workstream = list
            .workstreams
            .iter()
            .find(|entry| entry.id == SECOND_WORKSTREAM_ID)
            .unwrap();

        assert_eq!(workstream.id, SECOND_WORKSTREAM_ID);
        assert_eq!(workstream.default_branch, "feat/darwin-hpc-wave1");
        assert_eq!(workstream.promotion_state, "canonical");
        assert_eq!(workstream.recipe_count, 3);
        assert_eq!(detail.spec.id, SECOND_WORKSTREAM_ID);
        assert_eq!(detail.spec.default_branch, "feat/darwin-hpc-wave1");
        assert_eq!(recipes.recipe_count, 3);
        assert_eq!(
            recipes
                .recipes
                .iter()
                .map(|recipe| recipe.id.as_str())
                .collect::<Vec<_>>(),
            vec![
                "beagle-darwin-hpc-wave1.repo_native_dev_loop",
                "beagle-darwin-hpc-wave1.operator_cpu_loop",
                "beagle-darwin-hpc-wave1.recovery_resume_loop",
            ]
        );
    }

    #[test]
    fn detail_and_recipes_views_preserve_canonical_shape() {
        let dir = TestDir::new("detail");
        let cfg = test_config(dir.path());

        let detail = get_workstream_control_room_detail(dir.path(), &cfg, CANONICAL_WORKSTREAM_ID)
            .unwrap();
        let recipes = get_workstream_control_room_recipes(CANONICAL_WORKSTREAM_ID).unwrap();

        assert_eq!(detail.registry_entry.id, CANONICAL_WORKSTREAM_ID);
        assert_eq!(detail.registry_entry.promotion_state, "canonical");
        assert_eq!(detail.spec.id, CANONICAL_WORKSTREAM_ID);
        assert_eq!(detail.spec.promotion_state.state, "canonical");
        assert_eq!(detail.status_view.governance_state, "canonical");
        assert_eq!(detail.spec.default_dev_plane, "beagle-cluster");
        assert_eq!(detail.spec.vm_fallback_role, "fallback-only");

        let recipe_ids = recipes
            .recipes
            .iter()
            .map(|recipe| recipe.id.as_str())
            .collect::<Vec<_>>();
        assert_eq!(recipes.status, "ok");
        assert_eq!(recipes.workstream_id, CANONICAL_WORKSTREAM_ID);
        assert_eq!(recipes.recipe_count, 4);
        assert_eq!(
            recipe_ids,
            vec![
                "beagle-darwin-hpc-governance.repo_native_dev_loop",
                "beagle-darwin-hpc-governance.operator_cpu_loop",
                "beagle-darwin-hpc-governance.operator_gpu_loop",
                "beagle-darwin-hpc-governance.recovery_resume_loop",
            ]
        );
    }

    #[test]
    fn status_view_exposes_canonical_resume_and_nonfallback_session() {
        let dir = TestDir::new("status");
        let cfg = test_config(dir.path());
        let mut session = seeded_session(&cfg, &cfg.workspace.canonical_workspace_id, "ws-status");
        session.last_handoff = Some("ready for operator handoff".to_string());
        write_workspace_session(dir.path(), &session).unwrap();

        let status = get_workstream_control_room_status(dir.path(), &cfg, CANONICAL_WORKSTREAM_ID)
            .unwrap();

        assert_eq!(status.status, "ok");
        assert_eq!(status.workstream_id, CANONICAL_WORKSTREAM_ID);
        assert_eq!(status.governance_state, "canonical");
        assert_eq!(status.governance_last_transition, "resume");
        assert_eq!(status.default_dev_plane, "beagle-cluster");
        assert_eq!(status.vm_fallback_role, "fallback-only");
        assert_eq!(status.live_session.as_ref().unwrap().session_id, "ws-status");
        assert!(!status.live_session.as_ref().unwrap().fallback_active);
        assert!(status.actions.hold.enabled);
        assert!(!status.actions.resume.enabled);
    }

    #[tokio::test]
    async fn last_result_view_resolves_published_result_and_manifest() {
        let dir = TestDir::new("last-result");
        let cfg = test_config(dir.path());
        let mut session = seeded_session(&cfg, &cfg.workspace.canonical_workspace_id, "ws-result");
        session.last_published_result_job_id = Some(42);
        session.last_published_result_run_label = Some("canonical-run".to_string());
        session.last_published_result_profile_id = Some("gpu-single-v1".to_string());
        session.last_published_result_node_list = Some("r740-proxmox".to_string());
        session.last_published_manifest_key = Some("results/42/manifest.json".to_string());
        write_workspace_session(dir.path(), &session).unwrap();

        let result = ResultCatalogEntry {
            artifact_bucket: "beagle-results".to_string(),
            artifact_manifest_key: "results/42/manifest.json".to_string(),
            artifact_object_key: Some("results/42/output.txt".to_string()),
            artifact_prefix: "results/42".to_string(),
            artifact_sha256: "abc123".to_string(),
            end_time: Some("2026-03-22T00:00:00Z".to_string()),
            exit_code: Some(0),
            job_id: 42,
            job_name: "gpu-job".to_string(),
            node_list: "r740-proxmox".to_string(),
            partition: Some("gpu".to_string()),
            profile_id: "gpu-single-v1".to_string(),
            publication_time: Some("2026-03-22T00:01:00Z".to_string()),
            retention_scope: "active".to_string(),
            run_label: "canonical-run".to_string(),
            source_phase: Some("B143".to_string()),
            source_run_id: Some("b143-0321200310".to_string()),
            start_time: Some("2026-03-22T00:00:10Z".to_string()),
            state: "COMPLETED".to_string(),
            submit_time: Some("2026-03-21T23:59:30Z".to_string()),
        };
        let manifest = ObjectResultManifest {
            artifact_source: Some("object-backed".to_string()),
            end_time: Some("2026-03-22T00:00:00Z".to_string()),
            exit_code: Some(0),
            gateway_retrieval_time: Some("2026-03-22T00:01:05Z".to_string()),
            job_id: 42,
            job_name: Some("gpu-job".to_string()),
            manifest_format: Some("json".to_string()),
            manifest_object_key: "results/42/manifest.json".to_string(),
            node_list: Some("r740-proxmox".to_string()),
            object_bucket: "beagle-results".to_string(),
            object_key: "results/42/output.txt".to_string(),
            object_manifest_resolved_key: Some("results/42/manifest.json".to_string()),
            object_retrieval_mode: Some("catalog".to_string()),
            partition: Some("gpu".to_string()),
            profile_id: Some("gpu-single-v1".to_string()),
            publication_target_id: Some("rgw".to_string()),
            publication_time: Some("2026-03-22T00:01:00Z".to_string()),
            published_checksum: "abc123".to_string(),
            published_objects: vec![],
            retrieval_source: Some("gateway".to_string()),
            run_label: Some("canonical-run".to_string()),
            source_manifest_path: Some("/tmp/manifest.json".to_string()),
            source_phase: Some("B143".to_string()),
            source_run_id: Some("b143-0321200310".to_string()),
            start_time: Some("2026-03-22T00:00:10Z".to_string()),
            state: Some("COMPLETED".to_string()),
            submit_time: Some("2026-03-21T23:59:30Z".to_string()),
        };

        let (base_url, handle) = spawn_gateway_server(result.clone(), manifest.clone()).await;
        let _env_lock = ENV_LOCK.lock().unwrap();
        std::env::set_var("BEAGLE_DARWIN_HPC_GATEWAY_BASE_URL", &base_url);
        std::env::set_var("BEAGLE_DARWIN_HPC_GATEWAY_TIMEOUT_SECONDS", "5");

        let gateway = DarwinHpcGatewayClient::from_env().unwrap();
        let response = get_workstream_control_room_last_result(
            dir.path(),
            &cfg,
            &gateway,
            CANONICAL_WORKSTREAM_ID,
        )
        .await
        .unwrap();

        std::env::remove_var("BEAGLE_DARWIN_HPC_GATEWAY_BASE_URL");
        std::env::remove_var("BEAGLE_DARWIN_HPC_GATEWAY_TIMEOUT_SECONDS");
        handle.await.unwrap();

        assert_eq!(response.status, "ok");
        assert_eq!(response.workstream_id, CANONICAL_WORKSTREAM_ID);
        assert_eq!(response.last_result_reference.as_ref().unwrap().job_id, 42);
        assert_eq!(response.result.as_ref().unwrap().job_id, 42);
        assert_eq!(response.result.as_ref().unwrap().run_label, "canonical-run");
        assert_eq!(response.manifest.as_ref().unwrap().job_id, 42);
        assert_eq!(
            response.manifest.as_ref().unwrap().manifest_object_key,
            "results/42/manifest.json"
        );
    }

    #[tokio::test]
    async fn last_result_view_handles_missing_result_without_panic() {
        let dir = TestDir::new("missing-last-result");
        let cfg = test_config(dir.path());
        let gateway = DarwinHpcGatewayClient::from_env().unwrap();

        let response = get_workstream_control_room_last_result(
            dir.path(),
            &cfg,
            &gateway,
            CANONICAL_WORKSTREAM_ID,
        )
        .await
        .unwrap();

        assert_eq!(response.status, "ok");
        assert_eq!(response.workstream_id, CANONICAL_WORKSTREAM_ID);
        assert!(response.last_result_reference.is_none());
        assert!(response.result.is_none());
        assert!(response.manifest.is_none());
    }

    #[tokio::test]
    async fn portfolio_surface_aggregates_both_canonical_workstreams() {
        let dir = TestDir::new("portfolio");
        let cfg = test_config(dir.path());

        let mut governance = seeded_session(
            &cfg,
            &cfg.workspace.canonical_workspace_id,
            "ws-governance-portfolio",
        );
        governance.updated_at = Utc::now();
        governance.last_handoff = Some("governance handoff".to_string());
        governance.last_successful_task = Some(last_successful_task_for(
            "ws-governance-portfolio",
            "feat/darwin-hpc-governance",
            "gpu-single-v1",
            53,
            32,
        ));
        write_workspace_session(dir.path(), &governance).unwrap();

        let wave1_override = crate::workspace_plane::WorkspacePilotWorkstreamOverride {
            workstream_id: SECOND_WORKSTREAM_ID.to_string(),
            canonical_repo: None,
            default_branch: "feat/darwin-hpc-wave1".to_string(),
            canonical_track: None,
            branch_lineage: Some("feat/darwin-hpc-wave1".to_string()),
            governance_state: Some("canonical".to_string()),
            governance_last_transition: Some("resume".to_string()),
            default_dev_plane: None,
            vm_fallback_role: None,
            promotion_scope: None,
        };
        let mut wave1 = WorkspaceSessionState::new_with_workstream_override(
            &cfg,
            "wave1-portfolio".to_string(),
            Some("ws-wave1-portfolio".to_string()),
            Some(&wave1_override),
        );
        wave1.updated_at = Utc::now();
        wave1.last_handoff = Some("wave1 handoff".to_string());
        wave1.last_successful_task = Some(last_successful_task_for(
            "ws-wave1-portfolio",
            "feat/darwin-hpc-wave1",
            "cpu-batch-v1",
            59,
            31,
        ));
        write_workspace_session(dir.path(), &wave1).unwrap();

        let gateway = DarwinHpcGatewayClient::from_env().unwrap();
        let portfolio = get_workstream_portfolio_control_room(dir.path(), &cfg, &gateway)
            .await
            .unwrap();

        assert_eq!(portfolio.status, "ok");
        assert_eq!(portfolio.summary.total_workstreams, 2);
        assert_eq!(portfolio.summary.canonical_workstreams, 2);
        assert_eq!(portfolio.summary.live_sessions, 2);
        assert_eq!(
            portfolio.canonical_workstream_ids,
            vec![
                CANONICAL_WORKSTREAM_ID.to_string(),
                SECOND_WORKSTREAM_ID.to_string()
            ]
        );

        let governance_entry = portfolio
            .workstreams
            .iter()
            .find(|entry| entry.id == CANONICAL_WORKSTREAM_ID)
            .unwrap();
        assert_eq!(governance_entry.governance_state, "canonical");
        assert_eq!(
            governance_entry.live_session.as_ref().unwrap().session_id,
            "ws-governance-portfolio"
        );
        assert!(governance_entry.handoff_present);
        assert_eq!(
            governance_entry.latest_activity.as_ref().unwrap().event_kind,
            "workflow_completed"
        );

        let wave1_entry = portfolio
            .workstreams
            .iter()
            .find(|entry| entry.id == SECOND_WORKSTREAM_ID)
            .unwrap();
        assert_eq!(wave1_entry.default_branch, "feat/darwin-hpc-wave1");
        assert_eq!(wave1_entry.recipe_count, 3);
        assert_eq!(
            wave1_entry.live_session.as_ref().unwrap().session_id,
            "ws-wave1-portfolio"
        );
        assert!(wave1_entry.handoff_present);
        assert_eq!(
            wave1_entry.latest_activity.as_ref().unwrap().event_kind,
            "workflow_completed"
        );
        assert_eq!(portfolio.summary.fallback_active_workstreams, 0);
        assert_eq!(
            *portfolio.summary.governance_states.get("canonical").unwrap(),
            2
        );
    }

    #[test]
    fn handoff_view_returns_coherent_data_and_handles_absence_gracefully() {
        let dir = TestDir::new("handoff");
        let cfg = test_config(dir.path());
        let mut session = seeded_session(&cfg, &cfg.workspace.canonical_workspace_id, "ws-handoff");
        session.last_handoff = Some("handoff ready after gpu workflow".to_string());
        session.last_successful_task = Some(last_successful_task("ws-handoff"));
        session.last_published_result_job_id = Some(32);
        session.last_published_result_run_label = Some("b143-loop3-result".to_string());
        session.last_published_result_profile_id = Some("gpu-single-v1".to_string());
        session.last_published_result_node_list = Some("r740-proxmox".to_string());
        session.last_published_manifest_key = Some("results/32/manifest.json".to_string());
        write_workspace_session(dir.path(), &session).unwrap();

        let present = get_workstream_control_room_handoff(dir.path(), &cfg, CANONICAL_WORKSTREAM_ID)
            .unwrap();

        assert_eq!(present.status, "ok");
        assert_eq!(present.workstream_id, CANONICAL_WORKSTREAM_ID);
        assert!(present.handoff_required);
        assert!(present.recovery_required);
        assert!(present.handoff_present);
        assert_eq!(
            present.live_session.as_ref().unwrap().session_id,
            "ws-handoff"
        );
        assert_eq!(
            present.last_handoff.as_deref(),
            Some("handoff ready after gpu workflow")
        );
        assert_eq!(
            present.last_successful_task.as_ref().unwrap().published_result_job_id,
            32
        );
        assert_eq!(
            present.last_result_reference.as_ref().unwrap().manifest_key.as_deref(),
            Some("results/32/manifest.json")
        );

        let empty_dir = TestDir::new("handoff-absent");
        let absent = get_workstream_control_room_handoff(
            empty_dir.path(),
            &cfg,
            CANONICAL_WORKSTREAM_ID,
        )
        .unwrap();
        assert_eq!(absent.status, "ok");
        assert!(!absent.handoff_present);
        assert!(absent.live_session.is_none());
        assert!(absent.last_handoff.is_none());
        assert!(absent.last_successful_task.is_none());
        assert!(absent.last_result_reference.is_none());
    }

    #[test]
    fn bounded_actions_follow_the_current_governance_state() {
        let allowed_transitions = workspace_workstream_allowed_transitions();
        let canonical_actions =
            bounded_actions(CANONICAL_WORKSTREAM_ID, "canonical", &allowed_transitions);

        assert!(canonical_actions.hold.enabled);
        assert_eq!(
            canonical_actions.hold.endpoint,
            "/api/darwin/workstreams/beagle-darwin-hpc-governance/hold"
        );
        assert!(canonical_actions.hold.reason.contains("available"));
        assert!(!canonical_actions.resume.enabled);

        let held_actions = bounded_actions(CANONICAL_WORKSTREAM_ID, "held", &allowed_transitions);
        assert!(!held_actions.hold.enabled);
        assert!(held_actions.hold.reason.contains("not available"));
        assert!(held_actions.resume.enabled);
        assert_eq!(
            held_actions.resume.endpoint,
            "/api/darwin/workstreams/beagle-darwin-hpc-governance/resume"
        );
        assert!(held_actions.resume.reason.contains("available"));
    }

    #[test]
    fn governance_action_mutates_state_and_appends_ledger() {
        let dir = TestDir::new("governance-action");
        let cfg = test_config(dir.path());
        let mut session = seeded_session(&cfg, &cfg.workspace.canonical_workspace_id, "ws-governance-action");
        session.last_handoff = Some("seed handoff before governance action".to_string());
        session.last_successful_task = Some(last_successful_task("ws-governance-action"));
        session.last_published_result_job_id = Some(32);
        session.last_published_result_run_label = Some("b143-loop3-result".to_string());
        session.last_published_result_profile_id = Some("gpu-single-v1".to_string());
        session.last_published_result_node_list = Some("r740-proxmox".to_string());
        session.last_published_manifest_key = Some("results/32/manifest.json".to_string());
        write_workspace_session(dir.path(), &session).unwrap();

        let held = run_workstream_control_room_action(
            dir.path(),
            &cfg,
            CANONICAL_WORKSTREAM_ID,
            "hold",
        )
        .unwrap();
        assert_eq!(held.action, "hold");
        assert_eq!(held.previous_governance_state, "canonical");
        assert_eq!(held.governance_state, "held");
        assert_eq!(held.governance_last_transition, "hold");
        assert_eq!(held.session_id, "ws-governance-action");
        assert!(held.ledger_appended);
        assert!(held
            .last_handoff
            .as_deref()
            .unwrap()
            .contains("governance action hold moved canonical -> held"));
        assert_eq!(held.last_result_reference.as_ref().unwrap().job_id, 32);

        let held_status =
            get_workstream_control_room_status(dir.path(), &cfg, CANONICAL_WORKSTREAM_ID).unwrap();
        assert_eq!(held_status.governance_state, "held");
        assert_eq!(held_status.governance_last_transition, "hold");
        assert!(!held_status.actions.hold.enabled);
        assert!(held_status.actions.resume.enabled);

        let resumed = run_workstream_control_room_action(
            dir.path(),
            &cfg,
            CANONICAL_WORKSTREAM_ID,
            "resume",
        )
        .unwrap();
        assert_eq!(resumed.action, "resume");
        assert_eq!(resumed.previous_governance_state, "held");
        assert_eq!(resumed.governance_state, "canonical");
        assert_eq!(resumed.governance_last_transition, "resume");
        assert_eq!(resumed.session_id, "ws-governance-action");
        assert!(resumed
            .last_handoff
            .as_deref()
            .unwrap()
            .contains("governance action resume moved held -> canonical"));

        let ledger_path = workstream_governance_action_ledger_path(dir.path());
        let ledger = fs::read_to_string(&ledger_path).unwrap();
        assert!(ledger.contains("\"action\":\"hold\""));
        assert!(ledger.contains("\"action\":\"resume\""));
        assert!(ledger.contains("\"session_id\":\"ws-governance-action\""));
    }

    fn workspace_workstream_allowed_transitions() -> Vec<WorkspaceWorkstreamGovernanceTransition> {
        vec![
            WorkspaceWorkstreamGovernanceTransition {
                name: "promote".to_string(),
                from: "staged".to_string(),
                to: "pilot".to_string(),
            },
            WorkspaceWorkstreamGovernanceTransition {
                name: "promote".to_string(),
                from: "pilot".to_string(),
                to: "canonical".to_string(),
            },
            WorkspaceWorkstreamGovernanceTransition {
                name: "hold".to_string(),
                from: "canonical".to_string(),
                to: "held".to_string(),
            },
            WorkspaceWorkstreamGovernanceTransition {
                name: "resume".to_string(),
                from: "held".to_string(),
                to: "canonical".to_string(),
            },
            WorkspaceWorkstreamGovernanceTransition {
                name: "rollback".to_string(),
                from: "canonical".to_string(),
                to: "rollback".to_string(),
            },
            WorkspaceWorkstreamGovernanceTransition {
                name: "recover".to_string(),
                from: "rollback".to_string(),
                to: "recovery".to_string(),
            },
            WorkspaceWorkstreamGovernanceTransition {
                name: "resume".to_string(),
                from: "recovery".to_string(),
                to: "canonical".to_string(),
            },
        ]
    }
}
