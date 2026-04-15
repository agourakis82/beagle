use crate::{
    BridgeHealth, BridgeProviderInfo, DarwinHpcGatewayClient, HpcJobStatus, HpcSubmitRequest,
    HpcSubmitResponse, JobArtifactManifest, ObjectResultManifest, RepoContext,
    ResultCatalogQuery, ToolBridge,
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
const WORKSPACE_PLANE_CONTRACT_VERSION: &str = "darwin-workspace-plane-v2";

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct WorkspaceDevPlanePolicy {
    pub default_dev_plane: String,
    pub vm_fallback_role: String,
    pub promotion_scope: String,
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
        let now = Utc::now();
        Self {
            workspace_plane_contract_version: workspace_plane_contract_version_value(),
            workspace_id,
            canonical_repo: cfg.workspace.canonical_repo.clone(),
            canonical_branch: cfg.workspace.canonical_branch.clone(),
            canonical_track: cfg.workspace.canonical_track.clone(),
            operator_name: cfg.workspace.operator_name.clone(),
            repo_context: RepoContext::from_workspace_cfg(cfg),
            dev_plane_policy: WorkspaceDevPlanePolicy::from_workspace_cfg(cfg),
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
        }
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
        Some(existing) => existing,
        None => WorkspaceSessionState::new(cfg, workspace_id.clone(), requested_session_id),
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

    let bootstrap = bootstrap_workspace_session(
        data_dir,
        cfg,
        Some(workspace_id),
        request.session_id.as_deref(),
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
            WorkspaceSessionState::new(
                cfg,
                workspace_id.to_string(),
                Some(bootstrap.session_id.clone()),
            )
        });

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
        let published_result = gateway
            .results(&ResultCatalogQuery {
                profile_id: Some(profile_id.clone()),
                run_label: None,
                state: Some("COMPLETED".to_string()),
                node_list: None,
            })
            .await?
            .results
            .into_iter()
            .next()
            .ok_or_else(|| anyhow!("no published result found for profile {}", profile_id))?;

        update_current_task(
            data_dir,
            cfg,
            &mut state,
            "manifest_resolution",
            Some(final_job.job_id),
            Some(published_result.job_id),
            None,
        )?;

        let resolved_result_lookup = gateway.result_by_job(published_result.job_id).await?;
        let published_result_manifest = gateway.result_manifest(published_result.job_id).await?;
        let bridge_health = bridge.health();
        let bridge_providers = bridge.providers();

        let handoff = format!(
            "workspace={} repo={} branch={} session={} completed {} job {} and resolved published result {} from {}",
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
            state.last_job_run_label = Some(run_label.clone());
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
                workflow_run_label: run_label.clone(),
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
    } else {
        if state.repo_context.canonical_repo != state.canonical_repo {
            state.canonical_repo = state.repo_context.canonical_repo.clone();
            changed = true;
        }
        if state.repo_context.canonical_branch != state.canonical_branch {
            state.canonical_branch = state.repo_context.canonical_branch.clone();
            changed = true;
        }
        if state.repo_context.canonical_track != state.canonical_track {
            state.canonical_track = state.repo_context.canonical_track.clone();
            changed = true;
        }
    }

    changed
}

fn is_success_state(state: &str) -> bool {
    matches!(state, "COMPLETED" | "SUCCEEDED" | "SUCCESS")
}

fn is_failure_state(state: &str) -> bool {
    matches!(state, "FAILED" | "CANCELLED" | "TIMEOUT" | "ERROR")
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
        promotion_scope: "beagle-darwin-hpc-small-medium".to_string(),
    }
}

fn workspace_active_dev_plane_default() -> String {
    "beagle-cluster".to_string()
}
