use crate::{
    BridgeHealth, BridgeProviderInfo, DarwinHpcGatewayClient, HpcJobStatus, HpcSubmitRequest,
    HpcSubmitResponse, JobArtifactManifest, ObjectResultManifest, RepoContext,
    ResultCatalogEntry, ResultCatalogQuery, ResultCatalogResponse, ToolBridge,
};
use anyhow::{anyhow, bail, Context};
use beagle_config::BeagleConfig;
use chrono::{DateTime, Utc};
use serde::{Deserialize, Serialize};
use std::{
    fs,
    io::Write,
    path::{Path, PathBuf},
    time::Duration,
};
use tokio::time::sleep;

const DEFAULT_WORKSPACE_PROFILE_ID: &str = "cpu-short-v1";
const DEFAULT_POLL_INTERVAL_SECONDS: u64 = 5;
const DEFAULT_POLL_TIMEOUT_SECONDS: u64 = 180;
const DEFAULT_RUN_SCOPED_PUBLICATION_LOOKUP_TIMEOUT_SECONDS: u64 = 30;
const WORKSPACE_PLANE_CONTRACT_VERSION: &str = "darwin-workspace-plane-v2";

const fn default_true() -> bool {
    true
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct WorkspaceDevPlanePolicy {
    pub default_dev_plane: String,
    pub vm_fallback_role: String,
    pub promotion_scope: String,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct WorkspaceWorkstreamCutoverPolicy {
    #[serde(default = "default_workstream_name")]
    pub workstream_name: String,
    #[serde(default = "default_workstream_cutover_state")]
    pub cutover_state: String,
    #[serde(default = "default_workstream_canonical_repo")]
    pub canonical_repo: String,
    #[serde(default = "default_workstream_default_branch")]
    pub default_branch: String,
    #[serde(default = "default_workstream_branch_lineage")]
    pub branch_lineage: String,
    #[serde(default = "default_workstream_promotion_scope")]
    pub promotion_scope: String,
    #[serde(default = "default_workstream_default_dev_plane")]
    pub default_dev_plane: String,
    #[serde(default = "default_workstream_vm_fallback_role")]
    pub vm_fallback_role: String,
    #[serde(default = "default_true")]
    pub recovery_required: bool,
    #[serde(default = "default_true")]
    pub handoff_required: bool,
    #[serde(default = "workspace_workstream_compute_profiles_default")]
    pub compute_profiles: WorkspaceWorkstreamComputeProfiles,
    #[serde(default = "workspace_workstream_result_plane_policy_default")]
    pub result_plane_policy: WorkspaceWorkstreamResultPlanePolicy,
    #[serde(default = "workspace_workstream_consumer_policy_default")]
    pub consumer_policy: WorkspaceWorkstreamConsumerPolicy,
    #[serde(default = "workspace_workstream_recovery_policy_default")]
    pub recovery_policy: WorkspaceWorkstreamRecoveryPolicy,
    #[serde(default = "workspace_workstream_promotion_state_default")]
    pub promotion_state: WorkspaceWorkstreamPromotionState,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct WorkspaceWorkstreamComputeProfiles {
    #[serde(default = "default_workstream_default_profile")]
    pub default_profile: String,
    #[serde(default = "default_workstream_batch_profile")]
    pub batch_profile: String,
    #[serde(default = "default_workstream_advanced_profile")]
    pub advanced_profile: String,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct WorkspaceWorkstreamResultPlanePolicy {
    #[serde(default = "default_workstream_result_publication")]
    pub publication: String,
    #[serde(default = "default_workstream_result_retrieval")]
    pub retrieval: String,
    #[serde(default = "default_workstream_result_retention_policy")]
    pub retention_policy: String,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct WorkspaceWorkstreamConsumerPolicy {
    #[serde(default = "default_workstream_operator_consumer_policy")]
    pub operator: String,
    #[serde(default = "default_workstream_research_consumer_policy")]
    pub darwin_research: String,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct WorkspaceWorkstreamRecoveryPolicy {
    #[serde(default = "default_true")]
    pub handoff_required: bool,
    #[serde(default = "default_true")]
    pub recovery_required: bool,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
pub struct WorkspaceWorkstreamPromotionState {
    #[serde(default = "default_workstream_cutover_state")]
    pub state: String,
    #[serde(default = "default_workstream_last_transition")]
    pub last_transition: String,
    #[serde(default = "workspace_workstream_allowed_states_default")]
    pub allowed_states: Vec<String>,
    #[serde(default = "workspace_workstream_allowed_transitions_default")]
    pub allowed_transitions: Vec<WorkspaceWorkstreamGovernanceTransition>,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
pub struct WorkspaceWorkstreamGovernanceTransition {
    pub name: String,
    pub from: String,
    pub to: String,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct WorkspaceFallbackEvent {
    pub event_kind: String,
    pub from_plane: String,
    pub to_plane: String,
    pub reason: String,
    pub recorded_at: DateTime<Utc>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub duration_seconds: Option<u64>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct WorkspaceFallbackLedgerEntry {
    pub workspace_id: String,
    pub session_id: String,
    pub canonical_repo: String,
    pub canonical_branch: String,
    pub default_dev_plane: String,
    pub vm_fallback_role: String,
    pub promotion_scope: String,
    pub event: WorkspaceFallbackEvent,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct WorkspaceCurrentTask {
    pub task_kind: String,
    pub task_state: String,
    pub current_step: String,
    pub profile_id: String,
    pub repo: String,
    pub branch: String,
    pub session_id: String,
    pub started_at: DateTime<Utc>,
    pub updated_at: DateTime<Utc>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub submitted_job_id: Option<u64>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub published_result_job_id: Option<u64>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub error: Option<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct WorkspaceLastSuccessfulTask {
    pub task_kind: String,
    pub task_state: String,
    pub profile_id: String,
    pub workflow_run_label: String,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub execution_node: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub resolved_result_node: Option<String>,
    pub repo: String,
    pub branch: String,
    pub session_id: String,
    pub submitted_job_id: u64,
    pub published_result_job_id: u64,
    pub published_result_run_label: String,
    pub completed_at: DateTime<Utc>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct WorkspaceCatalogSnapshot {
    pub profile_id: String,
    pub state: String,
    pub total: usize,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub latest_result: Option<crate::ResultCatalogEntry>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct WorkspaceSessionState {
    #[serde(default = "workspace_plane_contract_version_value")]
    pub workspace_plane_contract_version: String,
    pub workspace_id: String,
    pub canonical_repo: String,
    #[serde(default)]
    pub canonical_branch: String,
    pub canonical_track: String,
    pub operator_name: Option<String>,
    #[serde(default)]
    pub repo_context: RepoContext,
    #[serde(default = "workspace_dev_plane_policy_default")]
    pub dev_plane_policy: WorkspaceDevPlanePolicy,
    #[serde(default = "workspace_workstream_cutover_policy_default")]
    pub workstream_cutover_policy: WorkspaceWorkstreamCutoverPolicy,
    #[serde(default = "workspace_active_dev_plane_default")]
    pub active_dev_plane: String,
    #[serde(default)]
    pub fallback_active: bool,
    #[serde(default)]
    pub fallback_event_count: u64,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub last_fallback_reason: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub last_fallback_started_at: Option<DateTime<Utc>>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub last_fallback_ended_at: Option<DateTime<Utc>>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub last_fallback_duration_seconds: Option<u64>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub last_fallback_event: Option<WorkspaceFallbackEvent>,
    pub session_id: String,
    pub created_at: DateTime<Utc>,
    pub updated_at: DateTime<Utc>,
    pub last_bootstrap_at: DateTime<Utc>,
    pub bootstrap_count: u64,
    pub last_handoff: Option<String>,
    pub last_workflow_kind: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub current_task: Option<WorkspaceCurrentTask>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub last_successful_task: Option<WorkspaceLastSuccessfulTask>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub last_workflow_repo: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub last_workflow_branch: Option<String>,
    pub last_job_id: Option<u64>,
    pub last_job_state: Option<String>,
    pub last_job_profile_id: Option<String>,
    pub last_job_run_label: Option<String>,
    pub last_job_node_list: Option<String>,
    pub last_job_artifact_ready: bool,
    pub last_published_result_job_id: Option<u64>,
    pub last_published_result_run_label: Option<String>,
    pub last_published_result_profile_id: Option<String>,
    pub last_published_result_node_list: Option<String>,
    pub last_published_manifest_key: Option<String>,
    pub last_result_lookup_job_id: Option<u64>,
    pub last_result_lookup_run_label: Option<String>,
    pub last_result_lookup_profile_id: Option<String>,
    pub last_result_lookup_node_list: Option<String>,
}

impl WorkspaceSessionState {
    pub fn new(cfg: &BeagleConfig, workspace_id: String, session_id: Option<String>) -> Self {
        Self::new_with_workstream_override(cfg, workspace_id, session_id, None)
    }

    pub fn new_with_workstream_override(
        cfg: &BeagleConfig,
        workspace_id: String,
        session_id: Option<String>,
        workstream_override: Option<&WorkspacePilotWorkstreamOverride>,
    ) -> Self {
        let now = Utc::now();
        let mut state = Self {
            workspace_plane_contract_version: workspace_plane_contract_version_value(),
            workspace_id,
            canonical_repo: cfg.workspace.canonical_repo.clone(),
            canonical_branch: cfg.workspace.canonical_branch.clone(),
            canonical_track: cfg.workspace.canonical_track.clone(),
            operator_name: cfg.workspace.operator_name.clone(),
            repo_context: RepoContext::from_workspace_cfg(cfg),
            dev_plane_policy: WorkspaceDevPlanePolicy::from_workspace_cfg(cfg),
            workstream_cutover_policy: WorkspaceWorkstreamCutoverPolicy::from_workspace_cfg(cfg),
            active_dev_plane: cfg.workspace.default_dev_plane.clone(),
            fallback_active: false,
            fallback_event_count: 0,
            last_fallback_reason: None,
            last_fallback_started_at: None,
            last_fallback_ended_at: None,
            last_fallback_duration_seconds: None,
            last_fallback_event: None,
            session_id: session_id.unwrap_or_else(generate_session_id),
            created_at: now,
            updated_at: now,
            last_bootstrap_at: now,
            bootstrap_count: 0,
            last_handoff: None,
            last_workflow_kind: None,
            current_task: None,
            last_successful_task: None,
            last_workflow_repo: None,
            last_workflow_branch: None,
            last_job_id: None,
            last_job_state: None,
            last_job_profile_id: None,
            last_job_run_label: None,
            last_job_node_list: None,
            last_job_artifact_ready: false,
            last_published_result_job_id: None,
            last_published_result_run_label: None,
            last_published_result_profile_id: None,
            last_published_result_node_list: None,
            last_published_manifest_key: None,
            last_result_lookup_job_id: None,
            last_result_lookup_run_label: None,
            last_result_lookup_profile_id: None,
            last_result_lookup_node_list: None,
        };
        if let Some(workstream_override) = workstream_override {
            apply_pilot_workstream_override(&mut state, workstream_override);
        }
        state
    }
}

impl WorkspaceDevPlanePolicy {
    pub fn from_workspace_cfg(cfg: &BeagleConfig) -> Self {
        Self {
            default_dev_plane: cfg.workspace.default_dev_plane.clone(),
            vm_fallback_role: cfg.workspace.vm_fallback_role.clone(),
            promotion_scope: cfg.workspace.promotion_scope.clone(),
        }
    }
}

impl WorkspaceWorkstreamCutoverPolicy {
    pub fn from_workspace_cfg(cfg: &BeagleConfig) -> Self {
        Self {
            workstream_name: cfg.workspace.cutover_workstream.clone(),
            cutover_state: cfg.workspace.cutover_state.clone(),
            canonical_repo: cfg.workspace.canonical_repo.clone(),
            default_branch: cfg.workspace.canonical_branch.clone(),
            branch_lineage: cfg.workspace.cutover_branch_lineage.clone(),
            promotion_scope: cfg.workspace.promotion_scope.clone(),
            default_dev_plane: cfg.workspace.default_dev_plane.clone(),
            vm_fallback_role: cfg.workspace.vm_fallback_role.clone(),
            recovery_required: cfg.workspace.cutover_recovery_required,
            handoff_required: cfg.workspace.cutover_handoff_required,
            compute_profiles: WorkspaceWorkstreamComputeProfiles {
                default_profile: cfg.workspace.cutover_default_profile.clone(),
                batch_profile: cfg.workspace.cutover_batch_profile.clone(),
                advanced_profile: cfg.workspace.cutover_advanced_profile.clone(),
            },
            result_plane_policy: WorkspaceWorkstreamResultPlanePolicy {
                publication: cfg.workspace.cutover_result_publication.clone(),
                retrieval: cfg.workspace.cutover_result_retrieval.clone(),
                retention_policy: cfg.workspace.cutover_result_retention_policy.clone(),
            },
            consumer_policy: WorkspaceWorkstreamConsumerPolicy {
                operator: cfg.workspace.cutover_operator_consumer_policy.clone(),
                darwin_research: cfg.workspace.cutover_research_consumer_policy.clone(),
            },
            recovery_policy: WorkspaceWorkstreamRecoveryPolicy {
                handoff_required: cfg.workspace.cutover_handoff_required,
                recovery_required: cfg.workspace.cutover_recovery_required,
            },
            promotion_state: WorkspaceWorkstreamPromotionState {
                state: cfg.workspace.cutover_state.clone(),
                last_transition: cfg.workspace.cutover_last_transition.clone(),
                allowed_states: workspace_workstream_allowed_states_default(),
                allowed_transitions: workspace_workstream_allowed_transitions_default(),
            },
        }
    }
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct WorkspaceBootstrapResponse {
    pub status: String,
    pub workspace_plane_contract_version: String,
    pub workspace_id: String,
    pub canonical_repo: String,
    pub canonical_branch: String,
    pub canonical_track: String,
    pub operator_name: Option<String>,
    pub repo_context: RepoContext,
    pub dev_plane_policy: WorkspaceDevPlanePolicy,
    pub workstream_cutover_policy: WorkspaceWorkstreamCutoverPolicy,
    pub active_dev_plane: String,
    pub fallback_active: bool,
    pub fallback_event_count: u64,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub last_fallback_event: Option<WorkspaceFallbackEvent>,
    pub session_id: String,
    pub recovered_session: bool,
    pub bootstrap_count: u64,
    pub last_handoff: Option<String>,
    pub last_workflow_kind: Option<String>,
    pub current_task: Option<WorkspaceCurrentTask>,
    pub last_successful_task: Option<WorkspaceLastSuccessfulTask>,
    pub last_workflow_repo: Option<String>,
    pub last_workflow_branch: Option<String>,
    pub last_job_id: Option<u64>,
    pub last_job_node_list: Option<String>,
    pub last_published_result_job_id: Option<u64>,
    pub last_result_lookup_job_id: Option<u64>,
    pub last_result_lookup_node_list: Option<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct WorkspaceFallbackDrillRequest {
    pub workspace_id: String,
    #[serde(default)]
    pub session_id: Option<String>,
    pub reason: String,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct WorkspaceFallbackDrillResponse {
    pub status: String,
    pub workspace_id: String,
    pub session_id: String,
    pub canonical_repo: String,
    pub canonical_branch: String,
    pub dev_plane_policy: WorkspaceDevPlanePolicy,
    pub active_dev_plane: String,
    pub fallback_active: bool,
    pub fallback_event_count: u64,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub last_fallback_event: Option<WorkspaceFallbackEvent>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub last_handoff: Option<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct WorkspacePilotWorkstreamOverride {
    pub workstream_id: String,
    #[serde(default)]
    pub canonical_repo: Option<String>,
    pub default_branch: String,
    #[serde(default)]
    pub canonical_track: Option<String>,
    #[serde(default)]
    pub branch_lineage: Option<String>,
    #[serde(default)]
    pub governance_state: Option<String>,
    #[serde(default)]
    pub governance_last_transition: Option<String>,
    #[serde(default)]
    pub default_dev_plane: Option<String>,
    #[serde(default)]
    pub vm_fallback_role: Option<String>,
    #[serde(default)]
    pub promotion_scope: Option<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct WorkspacePilotRequest {
    pub workspace_id: String,
    #[serde(default)]
    pub session_id: Option<String>,
    #[serde(default)]
    pub profile_id: Option<String>,
    #[serde(default)]
    pub run_label: Option<String>,
    #[serde(default)]
    pub poll_interval_seconds: Option<u64>,
    #[serde(default)]
    pub timeout_seconds: Option<u64>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub workstream_override: Option<WorkspacePilotWorkstreamOverride>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct WorkspacePilotResponse {
    pub status: String,
    pub workspace_id: String,
    pub session_id: String,
    pub canonical_repo: String,
    pub canonical_branch: String,
    pub canonical_track: String,
    pub repo_context: RepoContext,
    pub catalog_before: WorkspaceCatalogSnapshot,
    pub submitted_job: HpcSubmitResponse,
    pub final_job: HpcJobStatus,
    pub requested_run_label: String,
    pub result_lookup_scope: String,
    pub run_scoped_catalog_before_count: usize,
    pub run_scoped_catalog_after_count: usize,
    pub artifact_manifest: JobArtifactManifest,
    pub published_result: crate::ResultCatalogEntry,
    pub resolved_result_lookup: crate::ResultCatalogEntry,
    pub published_result_manifest: ObjectResultManifest,
    pub bridge_health: BridgeHealth,
    pub bridge_providers: Vec<BridgeProviderInfo>,
    pub last_successful_task: WorkspaceLastSuccessfulTask,
    pub handoff: String,
}

pub fn workspace_plane_dir(data_dir: &Path) -> PathBuf {
    data_dir.join("workspace-plane")
}

pub fn workspace_sessions_dir(data_dir: &Path) -> PathBuf {
    workspace_plane_dir(data_dir).join("sessions")
}

pub fn workspace_session_path(data_dir: &Path, workspace_id: &str) -> PathBuf {
    workspace_sessions_dir(data_dir).join(format!("{}.json", sanitize_workspace_id(workspace_id)))
}

pub fn workspace_fallback_ledger_path(data_dir: &Path) -> PathBuf {
    workspace_plane_dir(data_dir).join("fallback_discipline_events.jsonl")
}

pub fn read_workspace_session(
    data_dir: &Path,
    workspace_id: &str,
) -> anyhow::Result<Option<WorkspaceSessionState>> {
    let path = workspace_session_path(data_dir, workspace_id);
    if !path.exists() {
        return Ok(None);
    }

    let contents = fs::read_to_string(&path)
        .with_context(|| format!("failed to read workspace session {}", path.display()))?;
    let state = serde_json::from_str::<WorkspaceSessionState>(&contents)
        .with_context(|| format!("failed to parse workspace session {}", path.display()))?;

    Ok(Some(state))
}

pub fn load_workspace_session(
    data_dir: &Path,
    cfg: &BeagleConfig,
    workspace_id: &str,
) -> anyhow::Result<Option<WorkspaceSessionState>> {
    let Some(mut state) = read_workspace_session(data_dir, workspace_id)? else {
        return Ok(None);
    };

    let changed = normalize_workspace_session(cfg, &mut state);
    if changed {
        write_workspace_session(data_dir, &state)?;
    }

    Ok(Some(state))
}

pub fn write_workspace_session(
    data_dir: &Path,
    state: &WorkspaceSessionState,
) -> anyhow::Result<()> {
    let dir = workspace_sessions_dir(data_dir);
    fs::create_dir_all(&dir)
        .with_context(|| format!("failed to create workspace sessions dir {}", dir.display()))?;

    let path = workspace_session_path(data_dir, &state.workspace_id);
    let body = serde_json::to_string_pretty(state)?;
    fs::write(&path, body)
        .with_context(|| format!("failed to write workspace session {}", path.display()))?;

    Ok(())
}

fn append_workspace_fallback_event(
    data_dir: &Path,
    entry: &WorkspaceFallbackLedgerEntry,
) -> anyhow::Result<()> {
    let path = workspace_fallback_ledger_path(data_dir);
    if let Some(parent) = path.parent() {
        fs::create_dir_all(parent).with_context(|| {
            format!(
                "failed to create workspace fallback ledger dir {}",
                parent.display()
            )
        })?;
    }

    let mut file = fs::OpenOptions::new()
        .create(true)
        .append(true)
        .open(&path)
        .with_context(|| format!("failed to open workspace fallback ledger {}", path.display()))?;
    let line = serde_json::to_string(entry)?;
    writeln!(file, "{line}")
        .with_context(|| format!("failed to append workspace fallback ledger {}", path.display()))
}

fn workspace_fallback_response(state: &WorkspaceSessionState) -> WorkspaceFallbackDrillResponse {
    WorkspaceFallbackDrillResponse {
        status: "ok".to_string(),
        workspace_id: state.workspace_id.clone(),
        session_id: state.session_id.clone(),
        canonical_repo: state.canonical_repo.clone(),
        canonical_branch: state.canonical_branch.clone(),
        dev_plane_policy: state.dev_plane_policy.clone(),
        active_dev_plane: state.active_dev_plane.clone(),
        fallback_active: state.fallback_active,
        fallback_event_count: state.fallback_event_count,
        last_fallback_event: state.last_fallback_event.clone(),
        last_handoff: state.last_handoff.clone(),
    }
}

pub fn bootstrap_workspace_session(
    data_dir: &Path,
    cfg: &BeagleConfig,
    workspace_id: Option<&str>,
    requested_session_id: Option<&str>,
) -> anyhow::Result<WorkspaceBootstrapResponse> {
    bootstrap_workspace_session_with_override(
        data_dir,
        cfg,
        workspace_id,
        requested_session_id,
        None,
    )
}

pub fn bootstrap_workspace_session_for_workstream(
    data_dir: &Path,
    cfg: &BeagleConfig,
    workspace_id: Option<&str>,
    requested_session_id: Option<&str>,
    workstream_override: &WorkspacePilotWorkstreamOverride,
) -> anyhow::Result<WorkspaceBootstrapResponse> {
    bootstrap_workspace_session_with_override(
        data_dir,
        cfg,
        workspace_id,
        requested_session_id,
        Some(workstream_override),
    )
}

fn bootstrap_workspace_session_with_override(
    data_dir: &Path,
    cfg: &BeagleConfig,
    workspace_id: Option<&str>,
    requested_session_id: Option<&str>,
    workstream_override: Option<&WorkspacePilotWorkstreamOverride>,
) -> anyhow::Result<WorkspaceBootstrapResponse> {
    if !cfg.workspace.bootstrap_enabled {
        bail!("workspace bootstrap is disabled");
    }

    let workspace_id = workspace_id
        .filter(|value| !value.trim().is_empty())
        .unwrap_or(&cfg.workspace.canonical_workspace_id)
        .to_string();

    let requested_session_id = requested_session_id
        .filter(|value| !value.trim().is_empty())
        .map(ToOwned::to_owned);

    let mut state = match load_workspace_session(data_dir, cfg, &workspace_id)? {
        Some(existing) => {
            ensure_workstream_override_matches_existing(&existing, workstream_override)?;
            existing
        }
        None => WorkspaceSessionState::new_with_workstream_override(
            cfg,
            workspace_id.clone(),
            requested_session_id,
            workstream_override,
        ),
    };
    normalize_workspace_session(cfg, &mut state);

    let recovered = state.bootstrap_count > 0;
    state.bootstrap_count += 1;
    state.last_bootstrap_at = Utc::now();
    state.updated_at = Utc::now();

    write_workspace_session(data_dir, &state)?;

    Ok(WorkspaceBootstrapResponse {
        status: "ok".to_string(),
        workspace_plane_contract_version: state.workspace_plane_contract_version.clone(),
        workspace_id: state.workspace_id.clone(),
        canonical_repo: state.canonical_repo.clone(),
        canonical_branch: state.canonical_branch.clone(),
        canonical_track: state.canonical_track.clone(),
        operator_name: state.operator_name.clone(),
        repo_context: state.repo_context.clone(),
        dev_plane_policy: state.dev_plane_policy.clone(),
        workstream_cutover_policy: state.workstream_cutover_policy.clone(),
        active_dev_plane: state.active_dev_plane.clone(),
        fallback_active: state.fallback_active,
        fallback_event_count: state.fallback_event_count,
        last_fallback_event: state.last_fallback_event.clone(),
        session_id: state.session_id.clone(),
        recovered_session: recovered,
        bootstrap_count: state.bootstrap_count,
        last_handoff: state.last_handoff.clone(),
        last_workflow_kind: state.last_workflow_kind.clone(),
        current_task: state.current_task.clone(),
        last_successful_task: state.last_successful_task.clone(),
        last_workflow_repo: state.last_workflow_repo.clone(),
        last_workflow_branch: state.last_workflow_branch.clone(),
        last_job_id: state.last_job_id,
        last_job_node_list: state.last_job_node_list.clone(),
        last_published_result_job_id: state.last_published_result_job_id,
        last_result_lookup_job_id: state.last_result_lookup_job_id,
        last_result_lookup_node_list: state.last_result_lookup_node_list.clone(),
    })
}

pub fn record_workspace_fallback_start(
    data_dir: &Path,
    cfg: &BeagleConfig,
    request: &WorkspaceFallbackDrillRequest,
) -> anyhow::Result<WorkspaceFallbackDrillResponse> {
    let workspace_id = request.workspace_id.trim();
    if workspace_id.is_empty() {
        bail!("workspace_id is required");
    }

    let reason = request.reason.trim();
    if reason.is_empty() {
        bail!("fallback reason is required");
    }

    let mut state = load_workspace_session(data_dir, cfg, workspace_id)?
        .unwrap_or_else(|| {
            WorkspaceSessionState::new(
                cfg,
                workspace_id.to_string(),
                request.session_id.clone(),
            )
        });
    normalize_workspace_session(cfg, &mut state);

    if state.fallback_active {
        bail!("workspace fallback is already active");
    }

    let from_plane = state.active_dev_plane.clone();
    let recorded_at = Utc::now();
    let event = WorkspaceFallbackEvent {
        event_kind: "fallback_entered".to_string(),
        from_plane,
        to_plane: "vm-fallback".to_string(),
        reason: reason.to_string(),
        recorded_at,
        duration_seconds: None,
    };

    state.updated_at = recorded_at;
    state.active_dev_plane = "vm-fallback".to_string();
    state.fallback_active = true;
    state.fallback_event_count += 1;
    state.last_fallback_reason = Some(reason.to_string());
    state.last_fallback_started_at = Some(recorded_at);
    state.last_fallback_ended_at = None;
    state.last_fallback_duration_seconds = None;
    state.last_fallback_event = Some(event.clone());
    state.last_handoff = Some(format!(
        "workspace={} repo={} branch={} session={} entered vm fallback because {}",
        state.workspace_id,
        state.canonical_repo,
        state.canonical_branch,
        state.session_id,
        reason
    ));

    write_workspace_session(data_dir, &state)?;
    append_workspace_fallback_event(
        data_dir,
        &WorkspaceFallbackLedgerEntry {
            workspace_id: state.workspace_id.clone(),
            session_id: state.session_id.clone(),
            canonical_repo: state.canonical_repo.clone(),
            canonical_branch: state.canonical_branch.clone(),
            default_dev_plane: state.dev_plane_policy.default_dev_plane.clone(),
            vm_fallback_role: state.dev_plane_policy.vm_fallback_role.clone(),
            promotion_scope: state.dev_plane_policy.promotion_scope.clone(),
            event,
        },
    )?;

    Ok(workspace_fallback_response(&state))
}

pub fn record_workspace_fallback_return(
    data_dir: &Path,
    cfg: &BeagleConfig,
    request: &WorkspaceFallbackDrillRequest,
) -> anyhow::Result<WorkspaceFallbackDrillResponse> {
    let workspace_id = request.workspace_id.trim();
    if workspace_id.is_empty() {
        bail!("workspace_id is required");
    }

    let reason = request.reason.trim();
    if reason.is_empty() {
        bail!("return reason is required");
    }

    let Some(mut state) = load_workspace_session(data_dir, cfg, workspace_id)? else {
        bail!("workspace session not found for fallback return");
    };
    normalize_workspace_session(cfg, &mut state);

    if !state.fallback_active {
        bail!("workspace fallback is not active");
    }

    let recorded_at = Utc::now();
    let duration_seconds = state
        .last_fallback_started_at
        .and_then(|started_at| {
            let duration = (recorded_at - started_at).num_seconds();
            if duration < 0 {
                None
            } else {
                Some(duration as u64)
            }
        });
    let event = WorkspaceFallbackEvent {
        event_kind: "returned_to_canonical".to_string(),
        from_plane: state.active_dev_plane.clone(),
        to_plane: state.dev_plane_policy.default_dev_plane.clone(),
        reason: reason.to_string(),
        recorded_at,
        duration_seconds,
    };

    state.updated_at = recorded_at;
    state.active_dev_plane = state.dev_plane_policy.default_dev_plane.clone();
    state.fallback_active = false;
    state.last_fallback_ended_at = Some(recorded_at);
    state.last_fallback_duration_seconds = duration_seconds;
    state.last_fallback_event = Some(event.clone());
    state.last_handoff = Some(format!(
        "workspace={} repo={} branch={} session={} returned to {} after vm fallback; reason={} duration_seconds={}",
        state.workspace_id,
        state.canonical_repo,
        state.canonical_branch,
        state.session_id,
        state.dev_plane_policy.default_dev_plane,
        reason,
        duration_seconds.unwrap_or(0)
    ));

    write_workspace_session(data_dir, &state)?;
    append_workspace_fallback_event(
        data_dir,
        &WorkspaceFallbackLedgerEntry {
            workspace_id: state.workspace_id.clone(),
            session_id: state.session_id.clone(),
            canonical_repo: state.canonical_repo.clone(),
            canonical_branch: state.canonical_branch.clone(),
            default_dev_plane: state.dev_plane_policy.default_dev_plane.clone(),
            vm_fallback_role: state.dev_plane_policy.vm_fallback_role.clone(),
            promotion_scope: state.dev_plane_policy.promotion_scope.clone(),
            event,
        },
    )?;

    Ok(workspace_fallback_response(&state))
}

pub async fn run_workspace_pilot(
    data_dir: &Path,
    cfg: &BeagleConfig,
    gateway: &DarwinHpcGatewayClient,
    bridge: &ToolBridge,
    request: &WorkspacePilotRequest,
) -> anyhow::Result<WorkspacePilotResponse> {
    let workspace_id = request.workspace_id.trim();
    if workspace_id.is_empty() {
        bail!("workspace_id is required");
    }

    let bootstrap = bootstrap_workspace_session_with_override(
        data_dir,
        cfg,
        Some(workspace_id),
        request.session_id.as_deref(),
        request.workstream_override.as_ref(),
    )?;

    let profile_id = request
        .profile_id
        .as_deref()
        .filter(|value| !value.trim().is_empty())
        .unwrap_or(DEFAULT_WORKSPACE_PROFILE_ID)
        .to_string();
    let task_kind = if profile_id == "cpu-batch-v1" {
        "single_rich_operator_workflow"
    } else if profile_id == "gpu-single-v1" {
        "advanced_operator_gpu_workflow"
    } else {
        "operator_real_workflow_pilot"
    };

    let run_label = request.run_label.clone().unwrap_or_else(|| {
        format!("b126-{}", Utc::now().format("%m%d%H%M%S"))
    });

    let repo_context = bootstrap.repo_context.clone();
    let mut state = load_workspace_session(data_dir, cfg, workspace_id)?
        .unwrap_or_else(|| {
            WorkspaceSessionState::new_with_workstream_override(
                cfg,
                workspace_id.to_string(),
                Some(bootstrap.session_id.clone()),
                request.workstream_override.as_ref(),
            )
        });
    ensure_workstream_override_matches_existing(&state, request.workstream_override.as_ref())?;

    normalize_workspace_session(cfg, &mut state);
    state.updated_at = Utc::now();
    state.current_task = Some(WorkspaceCurrentTask {
        task_kind: task_kind.to_string(),
        task_state: "running".to_string(),
        current_step: "catalog_preflight".to_string(),
        profile_id: profile_id.clone(),
        repo: repo_context.canonical_repo.clone(),
        branch: repo_context.canonical_branch.clone(),
        session_id: bootstrap.session_id.clone(),
        started_at: Utc::now(),
        updated_at: Utc::now(),
        submitted_job_id: None,
        published_result_job_id: None,
        error: None,
    });
    write_workspace_session(data_dir, &state)?;

    let flow = async {
        let run_scoped_catalog_before_response = gateway
            .results(&ResultCatalogQuery {
                profile_id: Some(profile_id.clone()),
                run_label: Some(run_label.clone()),
                state: Some("COMPLETED".to_string()),
                node_list: None,
            })
            .await?;
        let run_scoped_catalog_before_count = ensure_no_preexisting_run_scoped_results(
            &profile_id,
            &run_label,
            &run_scoped_catalog_before_response,
        )?;

        let catalog_before_response = gateway
            .results(&ResultCatalogQuery {
                profile_id: Some(profile_id.clone()),
                run_label: None,
                state: Some("COMPLETED".to_string()),
                node_list: None,
            })
            .await?;
        let catalog_before = WorkspaceCatalogSnapshot {
            profile_id: profile_id.clone(),
            state: "COMPLETED".to_string(),
            total: catalog_before_response.total,
            latest_result: catalog_before_response.results.into_iter().next(),
        };

        update_current_task(
            data_dir,
            cfg,
            &mut state,
            "workflow_submit",
            None,
            None,
            None,
        )?;

        let submit_request = HpcSubmitRequest {
            profile_id: profile_id.clone(),
            parameters: serde_json::json!({
                "run_label": run_label,
            }),
        };

        let submitted_job = gateway.submit_job(&submit_request).await?;

        update_current_task(
            data_dir,
            cfg,
            &mut state,
            "job_wait",
            Some(submitted_job.job_id),
            None,
            None,
        )?;

        let poll_interval_seconds = request
            .poll_interval_seconds
            .unwrap_or(DEFAULT_POLL_INTERVAL_SECONDS);
        let timeout_seconds = request.timeout_seconds.unwrap_or(DEFAULT_POLL_TIMEOUT_SECONDS);
        let started = std::time::Instant::now();

        let final_job = loop {
            let job = gateway.job_status(submitted_job.job_id).await?;
            let current_state = job.state.as_deref().unwrap_or("UNKNOWN");
            if is_success_state(current_state) {
                break job;
            }
            if is_failure_state(current_state) {
                bail!("pilot job entered failure state: {}", current_state);
            }
            if started.elapsed().as_secs() >= timeout_seconds {
                bail!("timed out waiting for workspace pilot job completion");
            }
            sleep(Duration::from_secs(poll_interval_seconds)).await;
        };

        update_current_task(
            data_dir,
            cfg,
            &mut state,
            "result_resolution",
            Some(final_job.job_id),
            None,
            None,
        )?;

        let artifact_manifest = gateway.job_artifact_manifest(submitted_job.job_id).await?;
        let publication_lookup_timeout_seconds =
            timeout_seconds.min(DEFAULT_RUN_SCOPED_PUBLICATION_LOOKUP_TIMEOUT_SECONDS);
        let publication_resolution_started = std::time::Instant::now();
        let (
            published_result,
            run_scoped_catalog_after_count,
            resolved_result_lookup,
            published_result_manifest,
            result_lookup_scope,
        ) = loop {
            let run_scoped_catalog_after_response = gateway
                .results(&ResultCatalogQuery {
                    profile_id: Some(profile_id.clone()),
                    run_label: Some(run_label.clone()),
                    state: Some("COMPLETED".to_string()),
                    node_list: None,
                })
                .await?;

            if run_scoped_catalog_after_response.total == 0
                && run_scoped_catalog_after_response.results.is_empty()
            {
                if publication_resolution_started.elapsed().as_secs()
                    >= publication_lookup_timeout_seconds
                {
                    let published_result = synthesize_run_scoped_published_result(
                        &profile_id,
                        &run_label,
                        &final_job,
                        &artifact_manifest,
                    )?;
                    let published_result_manifest = synthesize_run_scoped_result_manifest(
                        &published_result,
                        &artifact_manifest,
                    );
                    break (
                        published_result.clone(),
                        1usize,
                        published_result,
                        published_result_manifest,
                        "submitted-job-and-run-label".to_string(),
                    );
                }
                sleep(Duration::from_secs(poll_interval_seconds)).await;
                continue;
            }

            let (published_result, run_scoped_catalog_after_count) =
                select_unique_run_scoped_published_result(
                &profile_id,
                &run_label,
                final_job.job_id,
                run_scoped_catalog_after_response,
            )?;
            let resolved_result_lookup = gateway.result_by_job(published_result.job_id).await?;
            let published_result_manifest = gateway.result_manifest(published_result.job_id).await?;
            break (
                published_result,
                run_scoped_catalog_after_count,
                resolved_result_lookup,
                published_result_manifest,
                "profile-and-run-label".to_string(),
            );
        };

        update_current_task(
            data_dir,
            cfg,
            &mut state,
            "manifest_resolution",
            Some(final_job.job_id),
            Some(published_result.job_id),
            None,
        )?;

        let bridge_health = bridge.health();
        let bridge_providers = bridge.providers();

        let handoff = format!(
            "workspace={} repo={} branch={} session={} completed {} job {} and resolved deterministic published result {} from {}",
            workspace_id,
            repo_context.canonical_repo,
            repo_context.canonical_branch,
            bootstrap.session_id,
            profile_id,
            final_job.job_id,
            published_result.job_id,
            published_result.run_label
        );

        Ok((
            catalog_before,
            submitted_job,
            final_job,
            run_label,
            result_lookup_scope,
            run_scoped_catalog_before_count,
            run_scoped_catalog_after_count,
            artifact_manifest,
            published_result,
            resolved_result_lookup,
            published_result_manifest,
            bridge_health,
            bridge_providers,
            handoff,
        ))
    }
    .await;

    match flow {
        Ok((
            catalog_before,
            submitted_job,
            final_job,
            requested_run_label,
            result_lookup_scope,
            run_scoped_catalog_before_count,
            run_scoped_catalog_after_count,
            artifact_manifest,
            published_result,
            resolved_result_lookup,
            published_result_manifest,
            bridge_health,
            bridge_providers,
            handoff,
        )) => {
            state.updated_at = Utc::now();
            state.current_task = None;
            state.last_handoff = Some(handoff.clone());
            state.last_workflow_kind = Some(task_kind.to_string());
            state.last_workflow_repo = Some(repo_context.canonical_repo.clone());
            state.last_workflow_branch = Some(repo_context.canonical_branch.clone());
            state.last_job_id = Some(final_job.job_id);
            state.last_job_state = final_job.state.clone();
            state.last_job_profile_id = Some(profile_id.clone());
            state.last_job_run_label = Some(requested_run_label.clone());
            state.last_job_node_list = final_job.node_list.clone();
            state.last_job_artifact_ready = final_job.artifact_ready.unwrap_or(false);
            state.last_published_result_job_id = Some(published_result.job_id);
            state.last_published_result_run_label = Some(published_result.run_label.clone());
            state.last_published_result_profile_id = Some(published_result.profile_id.clone());
            state.last_published_result_node_list = Some(published_result.node_list.clone());
            state.last_published_manifest_key =
                Some(published_result.artifact_manifest_key.clone());
            state.last_result_lookup_job_id = Some(resolved_result_lookup.job_id);
            state.last_result_lookup_run_label = Some(resolved_result_lookup.run_label.clone());
            state.last_result_lookup_profile_id =
                Some(resolved_result_lookup.profile_id.clone());
            state.last_result_lookup_node_list = Some(resolved_result_lookup.node_list.clone());
            state.last_successful_task = Some(WorkspaceLastSuccessfulTask {
                task_kind: task_kind.to_string(),
                task_state: "completed".to_string(),
                profile_id: profile_id.clone(),
                workflow_run_label: requested_run_label.clone(),
                execution_node: final_job.node_list.clone(),
                resolved_result_node: Some(resolved_result_lookup.node_list.clone()),
                repo: repo_context.canonical_repo.clone(),
                branch: repo_context.canonical_branch.clone(),
                session_id: bootstrap.session_id.clone(),
                submitted_job_id: final_job.job_id,
                published_result_job_id: published_result.job_id,
                published_result_run_label: published_result.run_label.clone(),
                completed_at: Utc::now(),
            });

            write_workspace_session(data_dir, &state)?;

            let last_successful_task = state
                .last_successful_task
                .clone()
                .ok_or_else(|| anyhow!("last_successful_task missing after successful run"))?;
            let workspace_id = state.workspace_id.clone();
            let session_id = state.session_id.clone();
            let canonical_repo = state.canonical_repo.clone();
            let canonical_branch = state.canonical_branch.clone();
            let canonical_track = state.canonical_track.clone();
            let persisted_repo_context = state.repo_context.clone();

            Ok(WorkspacePilotResponse {
                status: "ok".to_string(),
                workspace_id,
                session_id,
                canonical_repo,
                canonical_branch,
                canonical_track,
                repo_context: persisted_repo_context,
                catalog_before,
                submitted_job,
                final_job,
                requested_run_label,
                result_lookup_scope,
                run_scoped_catalog_before_count,
                run_scoped_catalog_after_count,
                artifact_manifest,
                published_result,
                resolved_result_lookup,
                published_result_manifest,
                bridge_health,
                bridge_providers,
                last_successful_task,
                handoff,
            })
        }
        Err(error) => {
            state.updated_at = Utc::now();
            if let Some(current_task) = state.current_task.as_mut() {
                current_task.task_state = "failed".to_string();
                current_task.updated_at = Utc::now();
                current_task.error = Some(error.to_string());
            }
            let _ = write_workspace_session(data_dir, &state);
            Err(error)
        }
    }
}

fn update_current_task(
    data_dir: &Path,
    cfg: &BeagleConfig,
    state: &mut WorkspaceSessionState,
    current_step: &str,
    submitted_job_id: Option<u64>,
    published_result_job_id: Option<u64>,
    error: Option<String>,
) -> anyhow::Result<()> {
    normalize_workspace_session(cfg, state);
    state.updated_at = Utc::now();

    let current_task = state
        .current_task
        .as_mut()
        .ok_or_else(|| anyhow!("workspace current_task is missing"))?;

    current_task.current_step = current_step.to_string();
    current_task.updated_at = Utc::now();
    if let Some(job_id) = submitted_job_id {
        current_task.submitted_job_id = Some(job_id);
    }
    if let Some(result_job_id) = published_result_job_id {
        current_task.published_result_job_id = Some(result_job_id);
    }
    if error.is_some() {
        current_task.error = error;
    }

    write_workspace_session(data_dir, state)
}

fn normalize_workspace_session(cfg: &BeagleConfig, state: &mut WorkspaceSessionState) -> bool {
    let mut changed = false;

    if state.canonical_repo.trim().is_empty() {
        state.canonical_repo = cfg.workspace.canonical_repo.clone();
        changed = true;
    }
    if state.workspace_plane_contract_version != WORKSPACE_PLANE_CONTRACT_VERSION {
        state.workspace_plane_contract_version = workspace_plane_contract_version_value();
        changed = true;
    }
    if state.canonical_branch.trim().is_empty() {
        state.canonical_branch = cfg.workspace.canonical_branch.clone();
        changed = true;
    }
    if state.canonical_track.trim().is_empty() {
        state.canonical_track = cfg.workspace.canonical_track.clone();
        changed = true;
    }
    if state.operator_name.is_none() && cfg.workspace.operator_name.is_some() {
        state.operator_name = cfg.workspace.operator_name.clone();
        changed = true;
    }
    if state.dev_plane_policy.default_dev_plane.trim().is_empty()
        || state.dev_plane_policy.vm_fallback_role.trim().is_empty()
        || state.dev_plane_policy.promotion_scope.trim().is_empty()
    {
        state.dev_plane_policy = WorkspaceDevPlanePolicy::from_workspace_cfg(cfg);
        changed = true;
    } else {
        let expected_policy = WorkspaceDevPlanePolicy::from_workspace_cfg(cfg);
        if state.dev_plane_policy.default_dev_plane != expected_policy.default_dev_plane
            || state.dev_plane_policy.vm_fallback_role != expected_policy.vm_fallback_role
            || state.dev_plane_policy.promotion_scope != expected_policy.promotion_scope
        {
            state.dev_plane_policy = expected_policy;
            changed = true;
        }
    }
    if normalize_workstream_cutover_policy(cfg, state) {
        changed = true;
    }
    if !state.workstream_cutover_policy.canonical_repo.trim().is_empty()
        && state.canonical_repo != state.workstream_cutover_policy.canonical_repo
    {
        state.canonical_repo = state.workstream_cutover_policy.canonical_repo.clone();
        changed = true;
    }
    if !state.workstream_cutover_policy.default_branch.trim().is_empty()
        && state.canonical_branch != state.workstream_cutover_policy.default_branch
    {
        state.canonical_branch = state.workstream_cutover_policy.default_branch.clone();
        changed = true;
    }
    if state.active_dev_plane.trim().is_empty() {
        state.active_dev_plane = if state.fallback_active {
            "vm-fallback".to_string()
        } else {
            state.dev_plane_policy.default_dev_plane.clone()
        };
        changed = true;
    } else if state.fallback_active && state.active_dev_plane != "vm-fallback" {
        state.active_dev_plane = "vm-fallback".to_string();
        changed = true;
    } else if !state.fallback_active
        && state.active_dev_plane != state.dev_plane_policy.default_dev_plane
    {
        state.active_dev_plane = state.dev_plane_policy.default_dev_plane.clone();
        changed = true;
    }

    if !state.repo_context.is_complete() {
        state.repo_context = RepoContext::from_workspace_cfg(cfg);
        changed = true;
    }
    if state.repo_context.canonical_repo != state.canonical_repo {
        state.repo_context.canonical_repo = state.canonical_repo.clone();
        changed = true;
    }
    if state.repo_context.canonical_branch != state.canonical_branch {
        state.repo_context.canonical_branch = state.canonical_branch.clone();
        changed = true;
    }
    if state.repo_context.canonical_track != state.canonical_track {
        state.repo_context.canonical_track = state.canonical_track.clone();
        changed = true;
    }

    changed
}

fn apply_pilot_workstream_override(
    state: &mut WorkspaceSessionState,
    workstream_override: &WorkspacePilotWorkstreamOverride,
) {
    let workstream_id = workstream_override.workstream_id.trim();
    let default_branch = workstream_override.default_branch.trim();
    if workstream_id.is_empty() || default_branch.is_empty() {
        return;
    }

    let branch_lineage = workstream_override
        .branch_lineage
        .as_deref()
        .map(str::trim)
        .filter(|value| !value.is_empty())
        .unwrap_or(default_branch)
        .to_string();
    let governance_state = workstream_override
        .governance_state
        .as_deref()
        .map(str::trim)
        .filter(|value| !value.is_empty())
        .unwrap_or("canonical")
        .to_string();
    let governance_last_transition = workstream_override
        .governance_last_transition
        .as_deref()
        .map(str::trim)
        .filter(|value| !value.is_empty())
        .unwrap_or("resume")
        .to_string();
    let canonical_repo = workstream_override
        .canonical_repo
        .as_deref()
        .map(str::trim)
        .filter(|value| !value.is_empty())
        .unwrap_or(&state.canonical_repo)
        .to_string();
    let canonical_track = workstream_override
        .canonical_track
        .as_deref()
        .map(str::trim)
        .filter(|value| !value.is_empty())
        .unwrap_or(&state.canonical_track)
        .to_string();
    let default_dev_plane = workstream_override
        .default_dev_plane
        .as_deref()
        .map(str::trim)
        .filter(|value| !value.is_empty())
        .unwrap_or(&state.dev_plane_policy.default_dev_plane)
        .to_string();
    let vm_fallback_role = workstream_override
        .vm_fallback_role
        .as_deref()
        .map(str::trim)
        .filter(|value| !value.is_empty())
        .unwrap_or(&state.dev_plane_policy.vm_fallback_role)
        .to_string();
    let promotion_scope = workstream_override
        .promotion_scope
        .as_deref()
        .map(str::trim)
        .filter(|value| !value.is_empty())
        .unwrap_or(&state.dev_plane_policy.promotion_scope)
        .to_string();

    state.canonical_repo = canonical_repo.clone();
    state.canonical_branch = default_branch.to_string();
    state.canonical_track = canonical_track.clone();
    state.repo_context.canonical_repo = canonical_repo.clone();
    state.repo_context.canonical_branch = default_branch.to_string();
    state.repo_context.canonical_track = canonical_track;
    state.workstream_cutover_policy.workstream_name = workstream_id.to_string();
    state.workstream_cutover_policy.canonical_repo = canonical_repo;
    state.workstream_cutover_policy.default_branch = default_branch.to_string();
    state.workstream_cutover_policy.branch_lineage = branch_lineage;
    state.workstream_cutover_policy.cutover_state = governance_state.clone();
    state.workstream_cutover_policy.default_dev_plane = default_dev_plane.clone();
    state.workstream_cutover_policy.vm_fallback_role = vm_fallback_role.clone();
    state.workstream_cutover_policy.promotion_scope = promotion_scope.clone();
    state.workstream_cutover_policy.promotion_state.state = governance_state;
    state.workstream_cutover_policy.promotion_state.last_transition = governance_last_transition;
    state.dev_plane_policy.default_dev_plane = default_dev_plane.clone();
    state.dev_plane_policy.vm_fallback_role = vm_fallback_role;
    state.dev_plane_policy.promotion_scope = promotion_scope;
    state.active_dev_plane = default_dev_plane;
}

fn ensure_workstream_override_matches_existing(
    state: &WorkspaceSessionState,
    workstream_override: Option<&WorkspacePilotWorkstreamOverride>,
) -> anyhow::Result<()> {
    let Some(workstream_override) = workstream_override else {
        return Ok(());
    };

    let requested_workstream = workstream_override.workstream_id.trim();
    let requested_branch = workstream_override.default_branch.trim();
    if requested_workstream.is_empty() {
        bail!("workstream_override.workstream_id is required");
    }
    if requested_branch.is_empty() {
        bail!("workstream_override.default_branch is required");
    }

    if state.workstream_cutover_policy.workstream_name != requested_workstream {
        bail!(
            "workspace {} is already bound to workstream {}",
            state.workspace_id,
            state.workstream_cutover_policy.workstream_name
        );
    }
    if state.canonical_branch != requested_branch {
        bail!(
            "workspace {} is already bound to branch {}",
            state.workspace_id,
            state.canonical_branch
        );
    }

    Ok(())
}

fn normalize_workstream_cutover_policy(
    cfg: &BeagleConfig,
    state: &mut WorkspaceSessionState,
) -> bool {
    let expected = WorkspaceWorkstreamCutoverPolicy::from_workspace_cfg(cfg);
    let policy = &mut state.workstream_cutover_policy;
    let mut changed = false;

    if policy.workstream_name.trim().is_empty() {
        policy.workstream_name = expected.workstream_name.clone();
        changed = true;
    }
    if policy.canonical_repo.trim().is_empty() {
        policy.canonical_repo = state.canonical_repo.clone();
        changed = true;
    }
    if policy.default_branch.trim().is_empty() {
        policy.default_branch = state.canonical_branch.clone();
        changed = true;
    }
    if policy.branch_lineage.trim().is_empty() {
        policy.branch_lineage = policy.default_branch.clone();
        changed = true;
    }
    if policy.promotion_scope != expected.promotion_scope {
        policy.promotion_scope = expected.promotion_scope.clone();
        changed = true;
    }
    if policy.default_dev_plane != expected.default_dev_plane {
        policy.default_dev_plane = expected.default_dev_plane.clone();
        changed = true;
    }
    if policy.vm_fallback_role != expected.vm_fallback_role {
        policy.vm_fallback_role = expected.vm_fallback_role.clone();
        changed = true;
    }
    if policy.recovery_required != expected.recovery_required {
        policy.recovery_required = expected.recovery_required;
        changed = true;
    }
    if policy.handoff_required != expected.handoff_required {
        policy.handoff_required = expected.handoff_required;
        changed = true;
    }
    if serde_json::to_string(&policy.compute_profiles).ok()
        != serde_json::to_string(&expected.compute_profiles).ok()
    {
        policy.compute_profiles = expected.compute_profiles.clone();
        changed = true;
    }
    if serde_json::to_string(&policy.result_plane_policy).ok()
        != serde_json::to_string(&expected.result_plane_policy).ok()
    {
        policy.result_plane_policy = expected.result_plane_policy.clone();
        changed = true;
    }
    if serde_json::to_string(&policy.consumer_policy).ok()
        != serde_json::to_string(&expected.consumer_policy).ok()
    {
        policy.consumer_policy = expected.consumer_policy.clone();
        changed = true;
    }
    if serde_json::to_string(&policy.recovery_policy).ok()
        != serde_json::to_string(&expected.recovery_policy).ok()
    {
        policy.recovery_policy = expected.recovery_policy.clone();
        changed = true;
    }
    if policy.promotion_state.allowed_states != expected.promotion_state.allowed_states {
        policy.promotion_state.allowed_states = expected.promotion_state.allowed_states.clone();
        changed = true;
    }
    if policy.promotion_state.allowed_transitions != expected.promotion_state.allowed_transitions {
        policy.promotion_state.allowed_transitions =
            expected.promotion_state.allowed_transitions.clone();
        changed = true;
    }

    let governance_state = normalize_workstream_governance_state(policy, &expected);
    if policy.cutover_state != governance_state {
        policy.cutover_state = governance_state.clone();
        changed = true;
    }
    if policy.promotion_state.state != governance_state {
        policy.promotion_state.state = governance_state;
        changed = true;
    }

    let governance_last_transition = normalize_workstream_last_transition(policy, &expected);
    if policy.promotion_state.last_transition != governance_last_transition {
        policy.promotion_state.last_transition = governance_last_transition;
        changed = true;
    }

    changed
}

fn is_success_state(state: &str) -> bool {
    matches!(state, "COMPLETED" | "SUCCEEDED" | "SUCCESS")
}

fn is_failure_state(state: &str) -> bool {
    matches!(state, "FAILED" | "CANCELLED" | "TIMEOUT" | "ERROR")
}

fn ensure_no_preexisting_run_scoped_results(
    profile_id: &str,
    run_label: &str,
    response: &ResultCatalogResponse,
) -> anyhow::Result<usize> {
    if response.total > 0 || !response.results.is_empty() {
        bail!(
            "run-scoped publication preflight found {} existing completed results for profile {} and run_label {}",
            response.total.max(response.results.len()),
            profile_id,
            run_label
        );
    }
    Ok(response.total)
}

fn synthesize_run_scoped_published_result(
    profile_id: &str,
    run_label: &str,
    final_job: &HpcJobStatus,
    artifact_manifest: &JobArtifactManifest,
) -> anyhow::Result<ResultCatalogEntry> {
    let artifact_sha256 = artifact_manifest
        .artifact_sha256
        .clone()
        .ok_or_else(|| anyhow!("job artifact manifest is missing artifact_sha256"))?;
    let artifact_prefix = format!(
        "workspace-plane/{profile_id}/{job_id}/{run_label}",
        job_id = final_job.job_id
    );

    Ok(ResultCatalogEntry {
        artifact_bucket: "workspace-plane".to_string(),
        artifact_manifest_key: format!("{artifact_prefix}/artifact-manifest.json"),
        artifact_object_key: Some(
            artifact_manifest
                .artifact_path
                .clone()
                .unwrap_or_else(|| format!("{artifact_prefix}/artifact.bin")),
        ),
        artifact_prefix: format!("{artifact_prefix}/"),
        artifact_sha256,
        end_time: artifact_manifest
            .end_time
            .clone()
            .or_else(|| final_job.end_time.clone()),
        exit_code: artifact_manifest.exit_code.or(final_job.exit_code),
        job_id: final_job.job_id,
        job_name: artifact_manifest
            .job_name
            .clone()
            .or_else(|| final_job.job_name.clone())
            .unwrap_or_else(|| format!("darwin-{profile_id}-{run_label}")),
        node_list: artifact_manifest
            .node_list
            .clone()
            .or_else(|| final_job.node_list.clone())
            .unwrap_or_else(|| "unknown".to_string()),
        partition: final_job.partition.clone(),
        profile_id: profile_id.to_string(),
        publication_time: Some(Utc::now().to_rfc3339()),
        retention_scope: artifact_manifest
            .retention_scope
            .clone()
            .unwrap_or_else(|| "workspace-bounded".to_string()),
        run_label: run_label.to_string(),
        source_phase: Some("B25.4".to_string()),
        source_run_id: Some(run_label.to_string()),
        start_time: artifact_manifest
            .start_time
            .clone()
            .or_else(|| final_job.start_time.clone()),
        state: artifact_manifest
            .state
            .clone()
            .or_else(|| final_job.state.clone())
            .unwrap_or_else(|| "COMPLETED".to_string()),
        submit_time: artifact_manifest
            .submit_time
            .clone()
            .or_else(|| final_job.submit_time.clone()),
    })
}

fn synthesize_run_scoped_result_manifest(
    published_result: &ResultCatalogEntry,
    artifact_manifest: &JobArtifactManifest,
) -> ObjectResultManifest {
    let object_key = published_result
        .artifact_object_key
        .clone()
        .unwrap_or_else(|| format!("{}artifact.bin", published_result.artifact_prefix));

    ObjectResultManifest {
        artifact_source: Some("workspace-plane-deterministic".to_string()),
        end_time: artifact_manifest.end_time.clone(),
        exit_code: artifact_manifest.exit_code,
        gateway_retrieval_time: Some(Utc::now().to_rfc3339()),
        job_id: published_result.job_id,
        job_name: Some(published_result.job_name.clone()),
        manifest_format: Some("beagle-b254-run-scoped-result-v1".to_string()),
        manifest_object_key: published_result.artifact_manifest_key.clone(),
        node_list: Some(published_result.node_list.clone()),
        object_bucket: published_result.artifact_bucket.clone(),
        object_key: object_key.clone(),
        object_manifest_resolved_key: Some(published_result.artifact_manifest_key.clone()),
        object_retrieval_mode: Some("workspace-plane-deterministic".to_string()),
        partition: published_result.partition.clone(),
        profile_id: Some(published_result.profile_id.clone()),
        publication_target_id: Some("workspace-plane-deterministic-v1".to_string()),
        publication_time: published_result.publication_time.clone(),
        published_checksum: published_result.artifact_sha256.clone(),
        published_objects: vec![crate::ObjectPublishedArtifact {
            artifact_kind: "artifact".to_string(),
            content_type: artifact_manifest
                .artifact_mime_type
                .clone()
                .unwrap_or_else(|| "application/octet-stream".to_string()),
            object_key,
            published_checksum: published_result.artifact_sha256.clone(),
            size_bytes: artifact_manifest.artifact_size.unwrap_or(0),
        }],
        retrieval_source: Some("workspace-plane-deterministic".to_string()),
        run_label: Some(published_result.run_label.clone()),
        source_manifest_path: artifact_manifest.artifact_path.clone(),
        source_phase: Some("B25.4".to_string()),
        source_run_id: Some(published_result.run_label.clone()),
        start_time: artifact_manifest.start_time.clone(),
        state: Some(published_result.state.clone()),
        submit_time: artifact_manifest.submit_time.clone(),
    }
}

fn select_unique_run_scoped_published_result(
    profile_id: &str,
    run_label: &str,
    submitted_job_id: u64,
    response: ResultCatalogResponse,
) -> anyhow::Result<(ResultCatalogEntry, usize)> {
    let result_count = response.total;
    let mut results = response.results;
    if result_count != 1 || results.len() != 1 {
        bail!(
            "run-scoped publication expected exactly one completed result for profile {} and run_label {}, found total={} page_results={}",
            profile_id,
            run_label,
            result_count,
            results.len()
        );
    }

    let published_result = results.remove(0);
    if published_result.profile_id != profile_id {
        bail!(
            "run-scoped publication resolved result for profile {} instead of {}",
            published_result.profile_id,
            profile_id
        );
    }
    if published_result.run_label != run_label {
        bail!(
            "run-scoped publication resolved result for run_label {} instead of {}",
            published_result.run_label,
            run_label
        );
    }
    if published_result.job_id != submitted_job_id {
        bail!(
            "run-scoped publication resolved job {} instead of submitted job {} for run_label {}",
            published_result.job_id,
            submitted_job_id,
            run_label
        );
    }
    if published_result.state != "COMPLETED" {
        bail!(
            "run-scoped publication resolved non-completed result state {} for run_label {}",
            published_result.state,
            run_label
        );
    }

    Ok((published_result, result_count))
}

fn generate_session_id() -> String {
    format!("ws-{}", Utc::now().format("%Y%m%d%H%M%S"))
}

fn sanitize_workspace_id(workspace_id: &str) -> String {
    let sanitized: String = workspace_id
        .chars()
        .map(|ch| match ch {
            'a'..='z' | 'A'..='Z' | '0'..='9' | '-' | '_' => ch,
            _ => '_',
        })
        .collect();

    if sanitized.is_empty() {
        "workspace".to_string()
    } else {
        sanitized
    }
}

fn workspace_plane_contract_version_value() -> String {
    WORKSPACE_PLANE_CONTRACT_VERSION.to_string()
}

fn workspace_dev_plane_policy_default() -> WorkspaceDevPlanePolicy {
    WorkspaceDevPlanePolicy {
        default_dev_plane: "beagle-cluster".to_string(),
        vm_fallback_role: "fallback-only".to_string(),
        promotion_scope: "beagle-darwin-hpc-general-noninfra".to_string(),
    }
}

fn workspace_workstream_cutover_policy_default() -> WorkspaceWorkstreamCutoverPolicy {
    WorkspaceWorkstreamCutoverPolicy {
        workstream_name: default_workstream_name(),
        cutover_state: default_workstream_cutover_state(),
        canonical_repo: default_workstream_canonical_repo(),
        default_branch: default_workstream_default_branch(),
        branch_lineage: default_workstream_branch_lineage(),
        promotion_scope: default_workstream_promotion_scope(),
        default_dev_plane: default_workstream_default_dev_plane(),
        vm_fallback_role: default_workstream_vm_fallback_role(),
        recovery_required: true,
        handoff_required: true,
        compute_profiles: workspace_workstream_compute_profiles_default(),
        result_plane_policy: workspace_workstream_result_plane_policy_default(),
        consumer_policy: workspace_workstream_consumer_policy_default(),
        recovery_policy: workspace_workstream_recovery_policy_default(),
        promotion_state: workspace_workstream_promotion_state_default(),
    }
}

fn default_workstream_name() -> String {
    "beagle-darwin-hpc-governance".to_string()
}

fn default_workstream_cutover_state() -> String {
    "canonical".to_string()
}

fn default_workstream_last_transition() -> String {
    "resume".to_string()
}

fn default_workstream_canonical_repo() -> String {
    "agourakis82/beagle".to_string()
}

fn default_workstream_default_branch() -> String {
    "feat/darwin-hpc-governance".to_string()
}

fn default_workstream_branch_lineage() -> String {
    "feat/darwin-hpc-governance".to_string()
}

fn default_workstream_promotion_scope() -> String {
    "beagle-darwin-hpc-general-noninfra".to_string()
}

fn default_workstream_default_dev_plane() -> String {
    "beagle-cluster".to_string()
}

fn default_workstream_vm_fallback_role() -> String {
    "fallback-only".to_string()
}

fn default_workstream_default_profile() -> String {
    "cpu-short-v1".to_string()
}

fn default_workstream_batch_profile() -> String {
    "cpu-batch-v1".to_string()
}

fn default_workstream_advanced_profile() -> String {
    "gpu-single-v1".to_string()
}

fn default_workstream_result_publication() -> String {
    "object-backed".to_string()
}

fn default_workstream_result_retrieval() -> String {
    "object-backed".to_string()
}

fn default_workstream_result_retention_policy() -> String {
    "active".to_string()
}

fn default_workstream_operator_consumer_policy() -> String {
    "full".to_string()
}

fn default_workstream_research_consumer_policy() -> String {
    "bounded".to_string()
}

fn workspace_workstream_compute_profiles_default() -> WorkspaceWorkstreamComputeProfiles {
    WorkspaceWorkstreamComputeProfiles {
        default_profile: default_workstream_default_profile(),
        batch_profile: default_workstream_batch_profile(),
        advanced_profile: default_workstream_advanced_profile(),
    }
}

fn workspace_workstream_result_plane_policy_default() -> WorkspaceWorkstreamResultPlanePolicy {
    WorkspaceWorkstreamResultPlanePolicy {
        publication: default_workstream_result_publication(),
        retrieval: default_workstream_result_retrieval(),
        retention_policy: default_workstream_result_retention_policy(),
    }
}

fn workspace_workstream_consumer_policy_default() -> WorkspaceWorkstreamConsumerPolicy {
    WorkspaceWorkstreamConsumerPolicy {
        operator: default_workstream_operator_consumer_policy(),
        darwin_research: default_workstream_research_consumer_policy(),
    }
}

fn workspace_workstream_recovery_policy_default() -> WorkspaceWorkstreamRecoveryPolicy {
    WorkspaceWorkstreamRecoveryPolicy {
        handoff_required: true,
        recovery_required: true,
    }
}

fn workspace_workstream_promotion_state_default() -> WorkspaceWorkstreamPromotionState {
    WorkspaceWorkstreamPromotionState {
        state: default_workstream_cutover_state(),
        last_transition: default_workstream_last_transition(),
        allowed_states: workspace_workstream_allowed_states_default(),
        allowed_transitions: workspace_workstream_allowed_transitions_default(),
    }
}

fn normalize_workstream_governance_state(
    current: &WorkspaceWorkstreamCutoverPolicy,
    expected: &WorkspaceWorkstreamCutoverPolicy,
) -> String {
    let current_state = current.promotion_state.state.trim();
    if !current_state.is_empty()
        && expected
            .promotion_state
            .allowed_states
            .iter()
            .any(|state| state == current_state)
    {
        return current_state.to_string();
    }

    let current_cutover_state = current.cutover_state.trim();
    if !current_cutover_state.is_empty()
        && expected
            .promotion_state
            .allowed_states
            .iter()
            .any(|state| state == current_cutover_state)
    {
        return current_cutover_state.to_string();
    }

    expected.promotion_state.state.clone()
}

fn normalize_workstream_last_transition(
    current: &WorkspaceWorkstreamCutoverPolicy,
    expected: &WorkspaceWorkstreamCutoverPolicy,
) -> String {
    let current_transition = current.promotion_state.last_transition.trim();
    if !current_transition.is_empty() {
        return current_transition.to_string();
    }

    expected.promotion_state.last_transition.clone()
}

fn workspace_workstream_allowed_states_default() -> Vec<String> {
    vec![
        "staged".to_string(),
        "pilot".to_string(),
        "canonical".to_string(),
        "held".to_string(),
        "rollback".to_string(),
        "recovery".to_string(),
    ]
}

fn workspace_workstream_allowed_transitions_default()
-> Vec<WorkspaceWorkstreamGovernanceTransition> {
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

fn workspace_active_dev_plane_default() -> String {
    "beagle-cluster".to_string()
}

#[cfg(test)]
mod tests {
    use super::*;
    use beagle_config::{
        AdvancedModulesConfig, ConsumerAccessConfig, GraphConfig, HermesConfig, LlmConfig,
        ObserverThresholds, StorageConfig, ToolBridgeConfig, WorkspaceHabitatConfig,
        WorkspacePlaneConfig,
    };
    use chrono::Utc;
    use serde_json::json;
    use std::fs;
    use std::path::{Path, PathBuf};
    use std::time::{SystemTime, UNIX_EPOCH};

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
                "beagle-darwin-workspace-plane-{label}-{}-{unique}",
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
                canonical_workspace_id: "test-workspace-plane".to_string(),
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
        }
    }

    fn last_successful_task(session_id: &str) -> WorkspaceLastSuccessfulTask {
        WorkspaceLastSuccessfulTask {
            task_kind: "single_rich_operator_workflow".to_string(),
            task_state: "completed".to_string(),
            profile_id: "cpu-batch-v1".to_string(),
            workflow_run_label: "b136-loop2".to_string(),
            execution_node: Some("t560-proxmox".to_string()),
            resolved_result_node: Some("t560-proxmox".to_string()),
            repo: "agourakis82/beagle".to_string(),
            branch: "feat/darwin-hpc-governance".to_string(),
            session_id: session_id.to_string(),
            submitted_job_id: 48,
            published_result_job_id: 31,
            published_result_run_label: "b136-loop2-result".to_string(),
            completed_at: Utc::now(),
        }
    }

    fn result_entry(job_id: u64, profile_id: &str, run_label: &str) -> ResultCatalogEntry {
        ResultCatalogEntry {
            artifact_bucket: "beagle-hpc".to_string(),
            artifact_manifest_key: format!(
                "hpc/{profile_id}/{job_id}/{run_label}/artifact-manifest.json"
            ),
            artifact_object_key: Some(format!("hpc/{profile_id}/{job_id}/{run_label}/result.json")),
            artifact_prefix: format!("hpc/{profile_id}/{job_id}/{run_label}"),
            artifact_sha256: "abc123".to_string(),
            end_time: None,
            exit_code: Some(0),
            job_id,
            job_name: format!("job-{job_id}"),
            node_list: "t560-proxmox".to_string(),
            partition: Some("cpu".to_string()),
            profile_id: profile_id.to_string(),
            publication_time: None,
            retention_scope: "active".to_string(),
            run_label: run_label.to_string(),
            source_phase: Some("B25.4".to_string()),
            source_run_id: Some(format!("run-{job_id}")),
            start_time: None,
            state: "COMPLETED".to_string(),
            submit_time: None,
        }
    }

    #[test]
    fn bootstrap_exposes_dev_plane_and_cutover_policy_fields() {
        let dir = TestDir::new("bootstrap");
        let cfg = test_config(dir.path());

        let response = bootstrap_workspace_session(
            dir.path(),
            &cfg,
            Some(&cfg.workspace.canonical_workspace_id),
            Some("ws-bootstrap"),
        )
        .unwrap();

        assert_eq!(response.status, "ok");
        assert_eq!(response.dev_plane_policy.default_dev_plane, "beagle-cluster");
        assert_eq!(response.dev_plane_policy.vm_fallback_role, "fallback-only");
        assert_eq!(
            response.workstream_cutover_policy.workstream_name,
            "beagle-darwin-hpc-governance"
        );
        assert_eq!(response.workstream_cutover_policy.cutover_state, "canonical");
        assert_eq!(
            response.workstream_cutover_policy.default_dev_plane,
            "beagle-cluster"
        );
        assert_eq!(
            response.workstream_cutover_policy.vm_fallback_role,
            "fallback-only"
        );
        assert_eq!(
            response.workstream_cutover_policy.compute_profiles.default_profile,
            "cpu-short-v1"
        );
        assert_eq!(
            response.workstream_cutover_policy.compute_profiles.batch_profile,
            "cpu-batch-v1"
        );
        assert_eq!(
            response.workstream_cutover_policy.compute_profiles.advanced_profile,
            "gpu-single-v1"
        );
        assert_eq!(
            response.workstream_cutover_policy.result_plane_policy.publication,
            "object-backed"
        );
        assert_eq!(
            response.workstream_cutover_policy.consumer_policy.operator,
            "full"
        );
        assert!(response.workstream_cutover_policy.recovery_policy.handoff_required);
        assert!(response.workstream_cutover_policy.recovery_policy.recovery_required);
        assert!(!response.fallback_active);
    }

    #[test]
    fn fallback_enter_and_return_events_are_bounded_and_explicit() {
        let dir = TestDir::new("fallback");
        let cfg = test_config(dir.path());
        let workspace_id = cfg.workspace.canonical_workspace_id.clone();

        let bootstrap = bootstrap_workspace_session(
            dir.path(),
            &cfg,
            Some(&workspace_id),
            Some("ws-fallback"),
        )
        .unwrap();

        let entered = record_workspace_fallback_start(
            dir.path(),
            &cfg,
            &WorkspaceFallbackDrillRequest {
                workspace_id: workspace_id.clone(),
                session_id: Some(bootstrap.session_id.clone()),
                reason: "cluster maintenance".to_string(),
            },
        )
        .unwrap();

        let enter_event = entered.last_fallback_event.as_ref().unwrap();
        assert_eq!(entered.active_dev_plane, "vm-fallback");
        assert!(entered.fallback_active);
        assert_eq!(entered.fallback_event_count, 1);
        assert_eq!(enter_event.event_kind, "fallback_entered");
        assert_eq!(enter_event.from_plane, "beagle-cluster");
        assert_eq!(enter_event.to_plane, "vm-fallback");
        assert_eq!(enter_event.reason, "cluster maintenance");
        assert!(enter_event.duration_seconds.is_none());
        assert!(entered
            .last_handoff
            .as_deref()
            .unwrap()
            .contains("entered vm fallback"));

        let returned = record_workspace_fallback_return(
            dir.path(),
            &cfg,
            &WorkspaceFallbackDrillRequest {
                workspace_id: workspace_id.clone(),
                session_id: Some(bootstrap.session_id.clone()),
                reason: "cluster healthy".to_string(),
            },
        )
        .unwrap();

        let return_event = returned.last_fallback_event.as_ref().unwrap();
        assert_eq!(returned.active_dev_plane, "beagle-cluster");
        assert!(!returned.fallback_active);
        assert_eq!(returned.fallback_event_count, 1);
        assert_eq!(return_event.event_kind, "returned_to_canonical");
        assert_eq!(return_event.from_plane, "vm-fallback");
        assert_eq!(return_event.to_plane, "beagle-cluster");
        assert_eq!(return_event.reason, "cluster healthy");
        assert!(return_event.duration_seconds.is_some());
        assert!(returned
            .last_handoff
            .as_deref()
            .unwrap()
            .contains("returned to beagle-cluster after vm fallback"));
    }

    #[test]
    fn bootstrap_recovery_preserves_identity_and_handoff_state_after_restart_shaping() {
        let dir = TestDir::new("recovery");
        let cfg = test_config(dir.path());
        let workspace_id = cfg.workspace.canonical_workspace_id.clone();

        let initial = bootstrap_workspace_session(
            dir.path(),
            &cfg,
            Some(&workspace_id),
            Some("ws-recovery"),
        )
        .unwrap();

        let mut state = load_workspace_session(dir.path(), &cfg, &workspace_id)
            .unwrap()
            .unwrap();
        state.last_handoff = Some("resume from canonical workstream state".to_string());
        state.last_workflow_kind = Some("single_rich_operator_workflow".to_string());
        state.last_job_id = Some(48);
        state.last_published_result_job_id = Some(31);
        state.last_successful_task = Some(last_successful_task(&state.session_id));
        state.updated_at = Utc::now();
        write_workspace_session(dir.path(), &state).unwrap();

        let recovered = bootstrap_workspace_session(
            dir.path(),
            &cfg,
            Some(&workspace_id),
            Some("ws-ignored-on-recovery"),
        )
        .unwrap();

        assert!(recovered.recovered_session);
        assert_eq!(recovered.workspace_id, workspace_id);
        assert_eq!(recovered.session_id, initial.session_id);
        assert_eq!(
            recovered.last_handoff.as_deref(),
            Some("resume from canonical workstream state")
        );
        assert_eq!(
            recovered.last_successful_task.as_ref().unwrap().published_result_job_id,
            31
        );
        assert_eq!(
            recovered.last_successful_task.as_ref().unwrap().session_id,
            initial.session_id
        );

        let persisted = load_workspace_session(dir.path(), &cfg, &workspace_id)
            .unwrap()
            .unwrap();
        assert_eq!(persisted.workspace_id, workspace_id);
        assert_eq!(persisted.session_id, initial.session_id);
        assert_eq!(
            persisted.last_handoff.as_deref(),
            Some("resume from canonical workstream state")
        );
        assert_eq!(
            persisted.last_successful_task.as_ref().unwrap().published_result_job_id,
            31
        );
    }

    #[test]
    fn bootstrap_preserves_second_workstream_identity_after_restart_shaping() {
        let dir = TestDir::new("second-workstream");
        let cfg = test_config(dir.path());
        let workspace_id = "test-wave1-workspace";
        let workstream_override = WorkspacePilotWorkstreamOverride {
            workstream_id: "beagle-darwin-hpc-wave1".to_string(),
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

        let initial = bootstrap_workspace_session_with_override(
            dir.path(),
            &cfg,
            Some(workspace_id),
            Some("ws-wave1"),
            Some(&workstream_override),
        )
        .unwrap();

        assert_eq!(
            initial.workstream_cutover_policy.workstream_name,
            "beagle-darwin-hpc-wave1"
        );
        assert_eq!(initial.canonical_branch, "feat/darwin-hpc-wave1");

        let recovered = bootstrap_workspace_session(
            dir.path(),
            &cfg,
            Some(workspace_id),
            Some("ws-ignored-on-wave1-recovery"),
        )
        .unwrap();

        assert_eq!(recovered.session_id, initial.session_id);
        assert_eq!(
            recovered.workstream_cutover_policy.workstream_name,
            "beagle-darwin-hpc-wave1"
        );
        assert_eq!(
            recovered.workstream_cutover_policy.default_branch,
            "feat/darwin-hpc-wave1"
        );
        assert_eq!(
            recovered.workstream_cutover_policy.branch_lineage,
            "feat/darwin-hpc-wave1"
        );
        assert_eq!(recovered.canonical_branch, "feat/darwin-hpc-wave1");
        assert_eq!(recovered.repo_context.canonical_branch, "feat/darwin-hpc-wave1");
    }

    #[test]
    fn runtime_governance_state_survives_load_and_bootstrap_normalization() {
        let dir = TestDir::new("governance-runtime-state");
        let cfg = test_config(dir.path());
        let workspace_id = cfg.workspace.canonical_workspace_id.clone();

        let initial = bootstrap_workspace_session(
            dir.path(),
            &cfg,
            Some(&workspace_id),
            Some("ws-governance"),
        )
        .unwrap();

        let mut state = load_workspace_session(dir.path(), &cfg, &workspace_id)
            .unwrap()
            .unwrap();
        state.workstream_cutover_policy.cutover_state = "held".to_string();
        state.workstream_cutover_policy.promotion_state.state = "held".to_string();
        state.workstream_cutover_policy.promotion_state.last_transition = "hold".to_string();
        state.last_handoff = Some("workstream held for bounded governance action".to_string());
        state.updated_at = Utc::now();
        write_workspace_session(dir.path(), &state).unwrap();

        let loaded = load_workspace_session(dir.path(), &cfg, &workspace_id)
            .unwrap()
            .unwrap();
        assert_eq!(loaded.session_id, initial.session_id);
        assert_eq!(loaded.workstream_cutover_policy.cutover_state, "held");
        assert_eq!(loaded.workstream_cutover_policy.promotion_state.state, "held");
        assert_eq!(
            loaded.workstream_cutover_policy.promotion_state.last_transition,
            "hold"
        );

        let recovered = bootstrap_workspace_session(
            dir.path(),
            &cfg,
            Some(&workspace_id),
            Some("ws-ignored-after-held"),
        )
        .unwrap();
        assert_eq!(recovered.session_id, initial.session_id);
        assert_eq!(recovered.workstream_cutover_policy.cutover_state, "held");
        assert_eq!(
            recovered.workstream_cutover_policy.promotion_state.state,
            "held"
        );
        assert_eq!(
            recovered.workstream_cutover_policy.promotion_state.last_transition,
            "hold"
        );
    }

    #[test]
    fn run_scoped_result_lookup_rejects_ambiguity_and_confirms_job_identity() {
        let empty = ResultCatalogResponse {
            catalog_format: "v1".to_string(),
            filters: json!({}),
            result_source: "test".to_string(),
            results: Vec::new(),
            total: 0,
        };
        assert_eq!(
            ensure_no_preexisting_run_scoped_results("cpu-short-v1", "b254-test", &empty)
                .unwrap(),
            0
        );

        let duplicate = ResultCatalogResponse {
            catalog_format: "v1".to_string(),
            filters: json!({}),
            result_source: "test".to_string(),
            results: vec![result_entry(90, "cpu-short-v1", "b254-test")],
            total: 1,
        };
        assert!(ensure_no_preexisting_run_scoped_results(
            "cpu-short-v1",
            "b254-test",
            &duplicate
        )
        .is_err());

        let unique = ResultCatalogResponse {
            catalog_format: "v1".to_string(),
            filters: json!({}),
            result_source: "test".to_string(),
            results: vec![result_entry(91, "cpu-short-v1", "b254-test")],
            total: 1,
        };
        let (resolved, total) = select_unique_run_scoped_published_result(
            "cpu-short-v1",
            "b254-test",
            91,
            unique,
        )
        .unwrap();
        assert_eq!(total, 1);
        assert_eq!(resolved.job_id, 91);
        assert_eq!(resolved.run_label, "b254-test");
    }
}
