use crate::{
    BridgeHealth, BridgeProviderInfo, DarwinHpcGatewayClient, HpcJobStatus, HpcSubmitRequest,
    HpcSubmitResponse, JobArtifactManifest, ObjectResultManifest, ResultCatalogQuery, ToolBridge,
};
use anyhow::{anyhow, bail, Context};
use beagle_config::BeagleConfig;
use chrono::{DateTime, Utc};
use serde::{Deserialize, Serialize};
use std::{
    fs,
    path::{Path, PathBuf},
    time::Duration,
};
use tokio::time::sleep;

const DEFAULT_WORKSPACE_PROFILE_ID: &str = "cpu-short-v1";
const DEFAULT_POLL_INTERVAL_SECONDS: u64 = 5;
const DEFAULT_POLL_TIMEOUT_SECONDS: u64 = 180;

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct WorkspaceSessionState {
    pub workspace_id: String,
    pub canonical_repo: String,
    pub canonical_track: String,
    pub operator_name: Option<String>,
    pub session_id: String,
    pub created_at: DateTime<Utc>,
    pub updated_at: DateTime<Utc>,
    pub last_bootstrap_at: DateTime<Utc>,
    pub bootstrap_count: u64,
    pub last_handoff: Option<String>,
    pub last_workflow_kind: Option<String>,
    pub last_job_id: Option<u64>,
    pub last_job_state: Option<String>,
    pub last_job_profile_id: Option<String>,
    pub last_job_run_label: Option<String>,
    pub last_job_artifact_ready: bool,
    pub last_published_result_job_id: Option<u64>,
    pub last_published_result_run_label: Option<String>,
    pub last_published_result_profile_id: Option<String>,
    pub last_published_manifest_key: Option<String>,
}

impl WorkspaceSessionState {
    pub fn new(cfg: &BeagleConfig, workspace_id: String, session_id: Option<String>) -> Self {
        let now = Utc::now();
        Self {
            workspace_id,
            canonical_repo: cfg.workspace.canonical_repo.clone(),
            canonical_track: cfg.workspace.canonical_track.clone(),
            operator_name: cfg.workspace.operator_name.clone(),
            session_id: session_id.unwrap_or_else(generate_session_id),
            created_at: now,
            updated_at: now,
            last_bootstrap_at: now,
            bootstrap_count: 0,
            last_handoff: None,
            last_workflow_kind: None,
            last_job_id: None,
            last_job_state: None,
            last_job_profile_id: None,
            last_job_run_label: None,
            last_job_artifact_ready: false,
            last_published_result_job_id: None,
            last_published_result_run_label: None,
            last_published_result_profile_id: None,
            last_published_manifest_key: None,
        }
    }
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct WorkspaceBootstrapResponse {
    pub status: String,
    pub workspace_id: String,
    pub canonical_repo: String,
    pub canonical_track: String,
    pub operator_name: Option<String>,
    pub session_id: String,
    pub recovered_session: bool,
    pub bootstrap_count: u64,
    pub last_handoff: Option<String>,
    pub last_workflow_kind: Option<String>,
    pub last_job_id: Option<u64>,
    pub last_published_result_job_id: Option<u64>,
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
    pub canonical_track: String,
    pub submitted_job: HpcSubmitResponse,
    pub final_job: HpcJobStatus,
    pub artifact_manifest: JobArtifactManifest,
    pub published_result: crate::ResultCatalogEntry,
    pub published_result_manifest: ObjectResultManifest,
    pub bridge_health: BridgeHealth,
    pub bridge_providers: Vec<BridgeProviderInfo>,
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

    let mut state = match read_workspace_session(data_dir, &workspace_id)? {
        Some(existing) => existing,
        None => WorkspaceSessionState::new(cfg, workspace_id.clone(), requested_session_id),
    };

    let recovered = state.bootstrap_count > 0;
    state.bootstrap_count += 1;
    state.last_bootstrap_at = Utc::now();
    state.updated_at = Utc::now();

    if state.operator_name.is_none() {
        state.operator_name = cfg.workspace.operator_name.clone();
    }

    write_workspace_session(data_dir, &state)?;

    Ok(WorkspaceBootstrapResponse {
        status: "ok".to_string(),
        workspace_id: state.workspace_id.clone(),
        canonical_repo: state.canonical_repo.clone(),
        canonical_track: state.canonical_track.clone(),
        operator_name: state.operator_name.clone(),
        session_id: state.session_id.clone(),
        recovered_session: recovered,
        bootstrap_count: state.bootstrap_count,
        last_handoff: state.last_handoff.clone(),
        last_workflow_kind: state.last_workflow_kind.clone(),
        last_job_id: state.last_job_id,
        last_published_result_job_id: state.last_published_result_job_id,
    })
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

    let run_label = request.run_label.clone().unwrap_or_else(|| {
        format!(
            "b124-{}",
            Utc::now().format("%m%d%H%M%S")
        )
    });

    let submit_request = HpcSubmitRequest {
        profile_id: profile_id.clone(),
        parameters: serde_json::json!({
            "run_label": run_label,
        }),
    };

    let submitted_job = gateway.submit_job(&submit_request).await?;

    let poll_interval_seconds = request
        .poll_interval_seconds
        .unwrap_or(DEFAULT_POLL_INTERVAL_SECONDS);
    let timeout_seconds = request.timeout_seconds.unwrap_or(DEFAULT_POLL_TIMEOUT_SECONDS);
    let started = std::time::Instant::now();

    let final_job = loop {
        let job = gateway.job_status(submitted_job.job_id).await?;
        let state = job.state.as_deref().unwrap_or("UNKNOWN");
        if is_success_state(state) {
            break job;
        }
        if is_failure_state(state) {
            bail!("pilot job entered failure state: {}", state);
        }
        if started.elapsed().as_secs() >= timeout_seconds {
            bail!("timed out waiting for workspace pilot job completion");
        }
        sleep(Duration::from_secs(poll_interval_seconds)).await;
    };

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

    let published_result_manifest = gateway.result_manifest(published_result.job_id).await?;
    let bridge_health = bridge.health();
    let bridge_providers = bridge.providers();

    let handoff = format!(
        "workspace={} session={} completed {} job {} and recovered published result {} from {}",
        workspace_id,
        bootstrap.session_id,
        profile_id,
        final_job.job_id,
        published_result.job_id,
        published_result.run_label
    );

    let mut state = read_workspace_session(data_dir, workspace_id)?
        .unwrap_or_else(|| WorkspaceSessionState::new(cfg, workspace_id.to_string(), Some(bootstrap.session_id.clone())));

    state.updated_at = Utc::now();
    state.last_handoff = Some(handoff.clone());
    state.last_workflow_kind = Some("operator_workflow_pilot".to_string());
    state.last_job_id = Some(final_job.job_id);
    state.last_job_state = final_job.state.clone();
    state.last_job_profile_id = Some(profile_id);
    state.last_job_run_label = Some(run_label);
    state.last_job_artifact_ready = final_job.artifact_ready.unwrap_or(false);
    state.last_published_result_job_id = Some(published_result.job_id);
    state.last_published_result_run_label = Some(published_result.run_label.clone());
    state.last_published_result_profile_id = Some(published_result.profile_id.clone());
    state.last_published_manifest_key = Some(published_result.artifact_manifest_key.clone());

    write_workspace_session(data_dir, &state)?;

    Ok(WorkspacePilotResponse {
        status: "ok".to_string(),
        workspace_id: state.workspace_id,
        session_id: state.session_id,
        canonical_repo: state.canonical_repo,
        canonical_track: state.canonical_track,
        submitted_job,
        final_job,
        artifact_manifest,
        published_result,
        published_result_manifest,
        bridge_health,
        bridge_providers,
        handoff,
    })
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
