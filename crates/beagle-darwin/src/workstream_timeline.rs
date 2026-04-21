use crate::workspace_plane::{
    load_workspace_session, workspace_fallback_ledger_path, workspace_plane_dir,
    workspace_sessions_dir, WorkspaceFallbackLedgerEntry, WorkspaceSessionState,
};
use crate::{
    resolve_registered_workstream, WorkstreamGovernanceActionLedgerEntry,
    WorkstreamLastResultReference,
};
use anyhow::{anyhow, Context};
use beagle_config::BeagleConfig;
use chrono::{DateTime, Utc};
use serde::{Deserialize, Serialize};
use std::{fs, path::Path};

const DEFAULT_TIMELINE_LIMIT: usize = 50;
const MAX_TIMELINE_LIMIT: usize = 200;

#[derive(Debug, Clone, Serialize)]
pub struct WorkstreamTimelineIdentity {
    pub workstream_id: String,
    pub workspace_id: String,
    pub session_id: String,
    pub repo: String,
    pub branch: String,
    pub active_dev_plane: String,
    pub fallback_active: bool,
    pub governance_state: String,
    pub governance_last_transition: String,
}

#[derive(Debug, Clone, Serialize)]
pub struct WorkstreamTimelineEvent {
    pub event_id: String,
    pub event_kind: String,
    pub event_source: String,
    pub recorded_at: DateTime<Utc>,
    pub workstream_id: String,
    pub workspace_id: String,
    pub session_id: String,
    pub repo: String,
    pub branch: String,
    pub summary: String,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub governance_transition: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub governance_state: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub from_state: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub to_state: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub from_plane: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub to_plane: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub workflow_kind: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub profile_id: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub submitted_job_id: Option<u64>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub result_job_id: Option<u64>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub result_run_label: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub manifest_key: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub handoff: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub active_dev_plane: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub fallback_active: Option<bool>,
}

#[derive(Debug, Clone, Serialize)]
pub struct WorkstreamTimelineResponse {
    pub status: String,
    pub workstream_id: String,
    pub identity: Option<WorkstreamTimelineIdentity>,
    pub total_events: usize,
    pub returned_events: usize,
    pub limit: usize,
    pub events: Vec<WorkstreamTimelineEvent>,
}

#[derive(Debug, Clone, Serialize)]
pub struct WorkstreamTimelineEventDetailResponse {
    pub status: String,
    pub workstream_id: String,
    pub identity: Option<WorkstreamTimelineIdentity>,
    pub total_events: usize,
    pub event: WorkstreamTimelineEvent,
}

#[derive(Debug, Clone)]
struct SortableTimelineEvent {
    sort_priority: usize,
    event: WorkstreamTimelineEvent,
}

pub fn get_workstream_timeline(
    data_dir: &Path,
    cfg: &BeagleConfig,
    workstream_id: &str,
    limit: Option<usize>,
) -> anyhow::Result<WorkstreamTimelineResponse> {
    let _entry = resolve_registered_workstream(workstream_id)?;
    let live_session = resolve_latest_workstream_session(data_dir, cfg, workstream_id)?;
    let identity = live_session
        .as_ref()
        .map(|session| WorkstreamTimelineIdentity::from_session(workstream_id, session));
    let timeline_limit = normalize_limit(limit);
    let events = build_workstream_timeline_events(data_dir, cfg, workstream_id, live_session.as_ref())?;
    let total_events = events.len();
    let events = limit_events(events, timeline_limit);
    let returned_events = events.len();

    Ok(WorkstreamTimelineResponse {
        status: "ok".to_string(),
        workstream_id: workstream_id.to_string(),
        identity,
        total_events,
        returned_events,
        limit: timeline_limit,
        events,
    })
}

pub fn get_workstream_timeline_event(
    data_dir: &Path,
    cfg: &BeagleConfig,
    workstream_id: &str,
    event_id: &str,
) -> anyhow::Result<WorkstreamTimelineEventDetailResponse> {
    let _entry = resolve_registered_workstream(workstream_id)?;
    let live_session = resolve_latest_workstream_session(data_dir, cfg, workstream_id)?;
    let identity = live_session
        .as_ref()
        .map(|session| WorkstreamTimelineIdentity::from_session(workstream_id, session));
    let events = build_workstream_timeline_events(data_dir, cfg, workstream_id, live_session.as_ref())?;
    let total_events = events.len();
    let event = events
        .into_iter()
        .find(|event| event.event_id == event_id)
        .ok_or_else(|| {
            anyhow!(
                "timeline event {} is not present for workstream {}",
                event_id,
                workstream_id
            )
        })?;

    Ok(WorkstreamTimelineEventDetailResponse {
        status: "ok".to_string(),
        workstream_id: workstream_id.to_string(),
        identity,
        total_events,
        event,
    })
}

impl WorkstreamTimelineIdentity {
    fn from_session(workstream_id: &str, session: &WorkspaceSessionState) -> Self {
        Self {
            workstream_id: workstream_id.to_string(),
            workspace_id: session.workspace_id.clone(),
            session_id: session.session_id.clone(),
            repo: session.canonical_repo.clone(),
            branch: session.canonical_branch.clone(),
            active_dev_plane: session.active_dev_plane.clone(),
            fallback_active: session.fallback_active,
            governance_state: session.workstream_cutover_policy.promotion_state.state.clone(),
            governance_last_transition: session
                .workstream_cutover_policy
                .promotion_state
                .last_transition
                .clone(),
        }
    }
}

fn build_workstream_timeline_events(
    data_dir: &Path,
    _cfg: &BeagleConfig,
    workstream_id: &str,
    live_session: Option<&WorkspaceSessionState>,
) -> anyhow::Result<Vec<WorkstreamTimelineEvent>> {
    let Some(session) = live_session else {
        return Ok(Vec::new());
    };

    let governance_entries = read_governance_ledger_entries(data_dir, workstream_id, session)?;
    let fallback_entries = read_fallback_ledger_entries(data_dir, session)?;
    let mut sortable = Vec::new();

    sortable.push(SortableTimelineEvent {
        sort_priority: 10,
        event: WorkstreamTimelineEvent {
            event_id: build_event_id(
                "session-bootstrap",
                session.created_at,
                &format!("{}-{}", session.workspace_id, session.session_id),
            ),
            event_kind: "session_bootstrap".to_string(),
            event_source: "workspace_session".to_string(),
            recorded_at: session.created_at,
            workstream_id: workstream_id.to_string(),
            workspace_id: session.workspace_id.clone(),
            session_id: session.session_id.clone(),
            repo: session.canonical_repo.clone(),
            branch: session.canonical_branch.clone(),
            summary: format!(
                "session {} bootstrapped for workspace {} on {}",
                session.session_id, session.workspace_id, session.active_dev_plane
            ),
            governance_transition: None,
            governance_state: Some(session.workstream_cutover_policy.promotion_state.state.clone()),
            from_state: None,
            to_state: None,
            from_plane: None,
            to_plane: None,
            workflow_kind: None,
            profile_id: None,
            submitted_job_id: None,
            result_job_id: None,
            result_run_label: None,
            manifest_key: None,
            handoff: None,
            active_dev_plane: Some(session.active_dev_plane.clone()),
            fallback_active: Some(session.fallback_active),
        },
    });

    if let Some(task) = session.last_successful_task.as_ref() {
        sortable.push(SortableTimelineEvent {
            sort_priority: 20,
            event: WorkstreamTimelineEvent {
                event_id: build_event_id(
                    "workflow-completed",
                    task.completed_at,
                    &format!("{}-{}", session.workspace_id, task.submitted_job_id),
                ),
                event_kind: "workflow_completed".to_string(),
                event_source: "workspace_session".to_string(),
                recorded_at: task.completed_at,
                workstream_id: workstream_id.to_string(),
                workspace_id: session.workspace_id.clone(),
                session_id: session.session_id.clone(),
                repo: task.repo.clone(),
                branch: task.branch.clone(),
                summary: format!(
                    "workflow {} completed with profile {} as job {}",
                    task.task_kind, task.profile_id, task.submitted_job_id
                ),
                governance_transition: None,
                governance_state: None,
                from_state: None,
                to_state: None,
                from_plane: None,
                to_plane: None,
                workflow_kind: Some(task.task_kind.clone()),
                profile_id: Some(task.profile_id.clone()),
                submitted_job_id: Some(task.submitted_job_id),
                result_job_id: Some(task.published_result_job_id),
                result_run_label: Some(task.published_result_run_label.clone()),
                manifest_key: session.last_published_manifest_key.clone(),
                handoff: workflow_seed_handoff(session, &governance_entries),
                active_dev_plane: Some(session.active_dev_plane.clone()),
                fallback_active: Some(session.fallback_active),
            },
        });

        if let Some(reference) = last_result_reference_from_session(session) {
            sortable.push(SortableTimelineEvent {
                sort_priority: 30,
                event: WorkstreamTimelineEvent {
                    event_id: build_event_id(
                        "result-reference",
                        task.completed_at,
                        &format!("{}-{}", session.workspace_id, reference.job_id),
                    ),
                    event_kind: "result_reference".to_string(),
                    event_source: "workspace_session".to_string(),
                    recorded_at: task.completed_at,
                    workstream_id: workstream_id.to_string(),
                    workspace_id: session.workspace_id.clone(),
                    session_id: session.session_id.clone(),
                    repo: session.canonical_repo.clone(),
                    branch: session.canonical_branch.clone(),
                    summary: format!(
                        "published result {} remained resolvable for workflow {}",
                        reference.job_id, task.workflow_run_label
                    ),
                    governance_transition: None,
                    governance_state: None,
                    from_state: None,
                    to_state: None,
                    from_plane: None,
                    to_plane: None,
                    workflow_kind: Some(task.task_kind.clone()),
                    profile_id: reference.profile_id.clone(),
                    submitted_job_id: Some(task.submitted_job_id),
                    result_job_id: Some(reference.job_id),
                    result_run_label: reference.run_label.clone(),
                    manifest_key: reference.manifest_key.clone(),
                    handoff: workflow_seed_handoff(session, &governance_entries),
                    active_dev_plane: Some(session.active_dev_plane.clone()),
                    fallback_active: Some(session.fallback_active),
                },
            });
        }
    }

    for (index, entry) in governance_entries.iter().enumerate() {
        sortable.push(SortableTimelineEvent {
            sort_priority: 40,
            event: WorkstreamTimelineEvent {
                event_id: build_event_id(
                    "governance-transition",
                    entry.recorded_at,
                    &format!("{}-{}", entry.action, entry.recorded_at.timestamp_millis()),
                ),
                event_kind: "governance_transition".to_string(),
                event_source: "workstream_governance_actions".to_string(),
                recorded_at: entry.recorded_at,
                workstream_id: entry.workstream_id.clone(),
                workspace_id: entry.workspace_id.clone(),
                session_id: entry.session_id.clone(),
                repo: entry.canonical_repo.clone(),
                branch: entry.canonical_branch.clone(),
                summary: format!(
                    "governance action {} moved {} -> {}",
                    entry.action, entry.from_state, entry.to_state
                ),
                governance_transition: Some(entry.action.clone()),
                governance_state: Some(entry.to_state.clone()),
                from_state: Some(entry.from_state.clone()),
                to_state: Some(entry.to_state.clone()),
                from_plane: None,
                to_plane: None,
                workflow_kind: None,
                profile_id: session.last_job_profile_id.clone(),
                submitted_job_id: entry.last_successful_task_job_id,
                result_job_id: entry.last_published_result_job_id,
                result_run_label: session.last_published_result_run_label.clone(),
                manifest_key: session.last_published_manifest_key.clone(),
                handoff: resulting_handoff_for_governance_event(index, &governance_entries, session),
                active_dev_plane: Some(entry.active_dev_plane.clone()),
                fallback_active: Some(entry.fallback_active),
            },
        });
    }

    for entry in fallback_entries {
        let duration_fragment = entry
            .event
            .duration_seconds
            .map(|seconds| format!(" duration={}s", seconds))
            .unwrap_or_default();
        sortable.push(SortableTimelineEvent {
            sort_priority: 50,
            event: WorkstreamTimelineEvent {
                event_id: build_event_id(
                    "fallback-event",
                    entry.event.recorded_at,
                    &format!("{}-{}", entry.event.event_kind, entry.event.recorded_at.timestamp_millis()),
                ),
                event_kind: "fallback_event".to_string(),
                event_source: "fallback_discipline_events".to_string(),
                recorded_at: entry.event.recorded_at,
                workstream_id: workstream_id.to_string(),
                workspace_id: entry.workspace_id.clone(),
                session_id: entry.session_id.clone(),
                repo: entry.canonical_repo.clone(),
                branch: entry.canonical_branch.clone(),
                summary: format!(
                    "fallback event {} moved {} -> {} reason={}{}",
                    entry.event.event_kind,
                    entry.event.from_plane,
                    entry.event.to_plane,
                    entry.event.reason,
                    duration_fragment
                ),
                governance_transition: None,
                governance_state: None,
                from_state: None,
                to_state: None,
                from_plane: Some(entry.event.from_plane.clone()),
                to_plane: Some(entry.event.to_plane.clone()),
                workflow_kind: None,
                profile_id: None,
                submitted_job_id: None,
                result_job_id: None,
                result_run_label: None,
                manifest_key: None,
                handoff: None,
                active_dev_plane: Some(entry.event.to_plane.clone()),
                fallback_active: Some(entry.event.to_plane == entry.vm_fallback_role),
            },
        });
    }

    if session.bootstrap_count > 1 {
        sortable.push(SortableTimelineEvent {
            sort_priority: 60,
            event: WorkstreamTimelineEvent {
                event_id: build_event_id(
                    "recovery-bootstrap",
                    session.last_bootstrap_at,
                    &format!("{}-{}", session.workspace_id, session.bootstrap_count),
                ),
                event_kind: "recovery_bootstrap".to_string(),
                event_source: "workspace_session".to_string(),
                recorded_at: session.last_bootstrap_at,
                workstream_id: workstream_id.to_string(),
                workspace_id: session.workspace_id.clone(),
                session_id: session.session_id.clone(),
                repo: session.canonical_repo.clone(),
                branch: session.canonical_branch.clone(),
                summary: format!(
                    "session {} recovered after restart; bootstrap_count={}",
                    session.session_id, session.bootstrap_count
                ),
                governance_transition: Some(
                    session
                        .workstream_cutover_policy
                        .promotion_state
                        .last_transition
                        .clone(),
                ),
                governance_state: Some(
                    session.workstream_cutover_policy.promotion_state.state.clone(),
                ),
                from_state: None,
                to_state: None,
                from_plane: None,
                to_plane: None,
                workflow_kind: session.last_workflow_kind.clone(),
                profile_id: session.last_job_profile_id.clone(),
                submitted_job_id: session.last_job_id,
                result_job_id: session.last_published_result_job_id,
                result_run_label: session.last_published_result_run_label.clone(),
                manifest_key: session.last_published_manifest_key.clone(),
                handoff: session.last_handoff.clone(),
                active_dev_plane: Some(session.active_dev_plane.clone()),
                fallback_active: Some(session.fallback_active),
            },
        });
    }

    sortable.sort_by(|left, right| {
        left.event
            .recorded_at
            .cmp(&right.event.recorded_at)
            .then(left.sort_priority.cmp(&right.sort_priority))
            .then(left.event.event_id.cmp(&right.event.event_id))
    });

    Ok(sortable.into_iter().map(|entry| entry.event).collect())
}

fn limit_events(mut events: Vec<WorkstreamTimelineEvent>, limit: usize) -> Vec<WorkstreamTimelineEvent> {
    if limit >= events.len() {
        return events;
    }

    let start = events.len().saturating_sub(limit);
    events.drain(0..start);
    events
}

fn normalize_limit(limit: Option<usize>) -> usize {
    limit.unwrap_or(DEFAULT_TIMELINE_LIMIT).min(MAX_TIMELINE_LIMIT)
}

fn read_governance_ledger_entries(
    data_dir: &Path,
    workstream_id: &str,
    session: &WorkspaceSessionState,
) -> anyhow::Result<Vec<WorkstreamGovernanceActionLedgerEntry>> {
    let path = workspace_plane_dir(data_dir).join("workstream-governance-actions.jsonl");
    read_jsonl_entries::<WorkstreamGovernanceActionLedgerEntry>(&path).map(|entries| {
        entries
            .into_iter()
            .filter(|entry| {
                entry.workstream_id == workstream_id
                    && entry.workspace_id == session.workspace_id
                    && entry.session_id == session.session_id
            })
            .collect()
    })
}

fn read_fallback_ledger_entries(
    data_dir: &Path,
    session: &WorkspaceSessionState,
) -> anyhow::Result<Vec<WorkspaceFallbackLedgerEntry>> {
    let path = workspace_fallback_ledger_path(data_dir);
    read_jsonl_entries::<WorkspaceFallbackLedgerEntry>(&path).map(|entries| {
        entries
            .into_iter()
            .filter(|entry| {
                entry.workspace_id == session.workspace_id && entry.session_id == session.session_id
            })
            .collect()
    })
}

fn read_jsonl_entries<T>(path: &Path) -> anyhow::Result<Vec<T>>
where
    T: for<'de> Deserialize<'de>,
{
    if !path.exists() {
        return Ok(Vec::new());
    }

    let body = fs::read_to_string(path)
        .with_context(|| format!("failed to read timeline ledger {}", path.display()))?;
    let mut entries = Vec::new();

    for (index, line) in body.lines().enumerate() {
        let trimmed = line.trim();
        if trimmed.is_empty() {
            continue;
        }

        let entry = serde_json::from_str::<T>(trimmed).with_context(|| {
            format!(
                "failed to parse timeline ledger {} line {}",
                path.display(),
                index + 1
            )
        })?;
        entries.push(entry);
    }

    Ok(entries)
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

fn workflow_seed_handoff(
    session: &WorkspaceSessionState,
    governance_entries: &[WorkstreamGovernanceActionLedgerEntry],
) -> Option<String> {
    governance_entries
        .first()
        .and_then(|entry| sanitize_handoff(entry.previous_handoff.as_ref()))
        .or_else(|| sanitize_handoff(session.last_handoff.as_ref()))
}

fn resulting_handoff_for_governance_event(
    index: usize,
    governance_entries: &[WorkstreamGovernanceActionLedgerEntry],
    session: &WorkspaceSessionState,
) -> Option<String> {
    governance_entries
        .get(index + 1)
        .and_then(|entry| sanitize_handoff(entry.previous_handoff.as_ref()))
        .or_else(|| sanitize_handoff(session.last_handoff.as_ref()))
}

fn sanitize_handoff(value: Option<&String>) -> Option<String> {
    value
        .map(|handoff| handoff.trim())
        .filter(|handoff| !handoff.is_empty())
        .map(ToOwned::to_owned)
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

fn build_event_id(kind: &str, recorded_at: DateTime<Utc>, suffix: &str) -> String {
    format!(
        "{}-{}-{}",
        kind,
        recorded_at.timestamp_millis(),
        sanitize_event_token(suffix)
    )
}

fn sanitize_event_token(value: &str) -> String {
    let mut token = String::with_capacity(value.len());
    let mut previous_dash = false;

    for ch in value.chars() {
        if ch.is_ascii_alphanumeric() {
            token.push(ch.to_ascii_lowercase());
            previous_dash = false;
        } else if !previous_dash {
            token.push('-');
            previous_dash = true;
        }
    }

    let trimmed = token.trim_matches('-').to_string();
    if trimmed.is_empty() {
        "event".to_string()
    } else {
        trimmed
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::workspace_plane::{
        workspace_fallback_ledger_path, write_workspace_session, WorkspaceFallbackEvent,
        WorkspaceLastSuccessfulTask,
    };
    use beagle_config::{
        AdvancedModulesConfig, ConsumerAccessConfig, GraphConfig, HermesConfig, LlmConfig,
        ObserverThresholds, StorageConfig, ToolBridgeConfig, WorkspaceHabitatConfig,
        WorkspacePlaneConfig,
    };
    use chrono::{TimeZone, Utc};
    use std::io::Write;
    use std::path::{Path, PathBuf};
    use std::time::{SystemTime, UNIX_EPOCH};

    const CANONICAL_WORKSTREAM_ID: &str = "beagle-darwin-hpc-governance";

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
                "beagle-darwin-workstream-timeline-{label}-{}-{unique}",
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
                canonical_workspace_id: "test-workstream-timeline".to_string(),
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

    fn seeded_session(cfg: &BeagleConfig) -> WorkspaceSessionState {
        let created_at = Utc.with_ymd_and_hms(2026, 3, 22, 10, 15, 0).unwrap();
        let completed_at = Utc.with_ymd_and_hms(2026, 3, 22, 10, 16, 0).unwrap();
        let recovered_at = Utc.with_ymd_and_hms(2026, 3, 22, 10, 19, 0).unwrap();

        let mut session = WorkspaceSessionState::new(
            cfg,
            cfg.workspace.canonical_workspace_id.clone(),
            Some("ws-timeline".to_string()),
        );
        session.created_at = created_at;
        session.updated_at = recovered_at;
        session.last_bootstrap_at = recovered_at;
        session.bootstrap_count = 2;
        session.last_workflow_kind = Some("single_rich_operator_workflow".to_string());
        session.last_handoff = Some("workspace=test-workstream-timeline repo=agourakis82/beagle branch=feat/darwin-hpc-governance session=ws-timeline governance action resume moved held -> canonical".to_string());
        session.last_successful_task = Some(WorkspaceLastSuccessfulTask {
            task_kind: "single_rich_operator_workflow".to_string(),
            task_state: "completed".to_string(),
            profile_id: "cpu-batch-v1".to_string(),
            workflow_run_label: "b154-seed".to_string(),
            execution_node: Some("t560-proxmox".to_string()),
            resolved_result_node: Some("t560-proxmox".to_string()),
            repo: "agourakis82/beagle".to_string(),
            branch: "feat/darwin-hpc-governance".to_string(),
            session_id: "ws-timeline".to_string(),
            submitted_job_id: 57,
            published_result_job_id: 31,
            published_result_run_label: "b102-20260319-072237-cpu-batch".to_string(),
            completed_at,
        });
        session.last_workflow_repo = Some("agourakis82/beagle".to_string());
        session.last_workflow_branch = Some("feat/darwin-hpc-governance".to_string());
        session.last_job_id = Some(57);
        session.last_job_state = Some("COMPLETED".to_string());
        session.last_job_profile_id = Some("cpu-batch-v1".to_string());
        session.last_job_run_label = Some("b154-seed".to_string());
        session.last_job_node_list = Some("t560-proxmox".to_string());
        session.last_job_artifact_ready = true;
        session.last_published_result_job_id = Some(31);
        session.last_published_result_run_label = Some("b102-20260319-072237-cpu-batch".to_string());
        session.last_published_result_profile_id = Some("cpu-batch-v1".to_string());
        session.last_published_result_node_list = Some("t560-proxmox".to_string());
        session.last_published_manifest_key = Some(
            "hpc/cpu-batch-v1/31/b102-20260319-072237-cpu-batch/artifact-manifest.json"
                .to_string(),
        );
        session
    }

    fn append_governance_ledger(
        dir: &Path,
        session: &WorkspaceSessionState,
    ) -> std::io::Result<()> {
        let path = workspace_plane_dir(dir).join("workstream-governance-actions.jsonl");
        fs::create_dir_all(path.parent().unwrap())?;
        let mut file = fs::OpenOptions::new()
            .create(true)
            .append(true)
            .open(path)?;

        let hold = WorkstreamGovernanceActionLedgerEntry {
            phase: "B15.3".to_string(),
            workstream_id: CANONICAL_WORKSTREAM_ID.to_string(),
            workspace_id: session.workspace_id.clone(),
            session_id: session.session_id.clone(),
            canonical_repo: session.canonical_repo.clone(),
            canonical_branch: session.canonical_branch.clone(),
            action: "hold".to_string(),
            from_state: "canonical".to_string(),
            to_state: "held".to_string(),
            active_dev_plane: session.active_dev_plane.clone(),
            fallback_active: false,
            last_successful_task_job_id: Some(57),
            last_published_result_job_id: Some(31),
            previous_handoff: Some("workspace=test-workstream-timeline repo=agourakis82/beagle branch=feat/darwin-hpc-governance session=ws-timeline completed cpu-batch-v1 job 57 and resolved published result 31".to_string()),
            recorded_at: Utc.with_ymd_and_hms(2026, 3, 22, 10, 17, 0).unwrap(),
        };
        let resume = WorkstreamGovernanceActionLedgerEntry {
            phase: "B15.3".to_string(),
            workstream_id: CANONICAL_WORKSTREAM_ID.to_string(),
            workspace_id: session.workspace_id.clone(),
            session_id: session.session_id.clone(),
            canonical_repo: session.canonical_repo.clone(),
            canonical_branch: session.canonical_branch.clone(),
            action: "resume".to_string(),
            from_state: "held".to_string(),
            to_state: "canonical".to_string(),
            active_dev_plane: session.active_dev_plane.clone(),
            fallback_active: false,
            last_successful_task_job_id: Some(57),
            last_published_result_job_id: Some(31),
            previous_handoff: Some("workspace=test-workstream-timeline repo=agourakis82/beagle branch=feat/darwin-hpc-governance session=ws-timeline governance action hold moved canonical -> held".to_string()),
            recorded_at: Utc.with_ymd_and_hms(2026, 3, 22, 10, 18, 0).unwrap(),
        };

        writeln!(file, "{}", serde_json::to_string(&hold).unwrap())?;
        writeln!(file, "{}", serde_json::to_string(&resume).unwrap())?;
        Ok(())
    }

    fn append_fallback_ledger(
        dir: &Path,
        session: &WorkspaceSessionState,
    ) -> std::io::Result<()> {
        let path = workspace_fallback_ledger_path(dir);
        fs::create_dir_all(path.parent().unwrap())?;
        let mut file = fs::OpenOptions::new()
            .create(true)
            .append(true)
            .open(path)?;
        let fallback = WorkspaceFallbackLedgerEntry {
            workspace_id: session.workspace_id.clone(),
            session_id: session.session_id.clone(),
            canonical_repo: session.canonical_repo.clone(),
            canonical_branch: session.canonical_branch.clone(),
            default_dev_plane: session.dev_plane_policy.default_dev_plane.clone(),
            vm_fallback_role: session.dev_plane_policy.vm_fallback_role.clone(),
            promotion_scope: session.dev_plane_policy.promotion_scope.clone(),
            event: WorkspaceFallbackEvent {
                event_kind: "fallback_return".to_string(),
                from_plane: "beagle-vm".to_string(),
                to_plane: "beagle-cluster".to_string(),
                reason: "operator drill complete".to_string(),
                recorded_at: Utc.with_ymd_and_hms(2026, 3, 22, 10, 17, 30).unwrap(),
                duration_seconds: Some(2),
            },
        };
        writeln!(file, "{}", serde_json::to_string(&fallback).unwrap())?;
        Ok(())
    }

    #[test]
    fn timeline_orders_loops_governance_fallback_and_recovery_events() {
        let dir = TestDir::new("timeline");
        let cfg = test_config(dir.path());
        let session = seeded_session(&cfg);
        write_workspace_session(dir.path(), &session).unwrap();
        append_governance_ledger(dir.path(), &session).unwrap();
        append_fallback_ledger(dir.path(), &session).unwrap();

        let response = get_workstream_timeline(dir.path(), &cfg, CANONICAL_WORKSTREAM_ID, None)
            .unwrap();

        let event_kinds = response
            .events
            .iter()
            .map(|event| event.event_kind.as_str())
            .collect::<Vec<_>>();
        assert_eq!(response.status, "ok");
        assert_eq!(response.workstream_id, CANONICAL_WORKSTREAM_ID);
        assert_eq!(response.identity.as_ref().unwrap().session_id, "ws-timeline");
        assert_eq!(
            event_kinds,
            vec![
                "session_bootstrap",
                "workflow_completed",
                "result_reference",
                "governance_transition",
                "fallback_event",
                "governance_transition",
                "recovery_bootstrap",
            ]
        );
        assert!(
            response.events[1]
                .handoff
                .as_deref()
                .unwrap()
                .contains("completed cpu-batch-v1 job 57")
        );
        assert_eq!(
            response.events[3].governance_transition.as_deref(),
            Some("hold")
        );
        assert!(
            response.events[3]
                .handoff
                .as_deref()
                .unwrap()
                .contains("governance action hold moved canonical -> held")
        );
        assert_eq!(
            response.events[5].governance_transition.as_deref(),
            Some("resume")
        );
        assert!(
            response.events[5]
                .handoff
                .as_deref()
                .unwrap()
                .contains("governance action resume moved held -> canonical")
        );
        assert_eq!(response.events[6].event_kind, "recovery_bootstrap");
    }

    #[test]
    fn timeline_limit_returns_latest_events_in_order() {
        let dir = TestDir::new("timeline-limit");
        let cfg = test_config(dir.path());
        let session = seeded_session(&cfg);
        write_workspace_session(dir.path(), &session).unwrap();
        append_governance_ledger(dir.path(), &session).unwrap();

        let response =
            get_workstream_timeline(dir.path(), &cfg, CANONICAL_WORKSTREAM_ID, Some(2)).unwrap();

        assert_eq!(response.total_events, 6);
        assert_eq!(response.returned_events, 2);
        assert_eq!(response.events[0].event_kind, "governance_transition");
        assert_eq!(
            response.events[0].governance_transition.as_deref(),
            Some("resume")
        );
        assert_eq!(response.events[1].event_kind, "recovery_bootstrap");
    }

    #[test]
    fn timeline_event_detail_returns_requested_event() {
        let dir = TestDir::new("timeline-detail");
        let cfg = test_config(dir.path());
        let session = seeded_session(&cfg);
        write_workspace_session(dir.path(), &session).unwrap();
        append_governance_ledger(dir.path(), &session).unwrap();

        let timeline = get_workstream_timeline(dir.path(), &cfg, CANONICAL_WORKSTREAM_ID, None)
            .unwrap();
        let hold_event = timeline
            .events
            .iter()
            .find(|event| event.governance_transition.as_deref() == Some("hold"))
            .unwrap();

        let detail = get_workstream_timeline_event(
            dir.path(),
            &cfg,
            CANONICAL_WORKSTREAM_ID,
            &hold_event.event_id,
        )
        .unwrap();

        assert_eq!(detail.status, "ok");
        assert_eq!(detail.workstream_id, CANONICAL_WORKSTREAM_ID);
        assert_eq!(detail.event.event_id, hold_event.event_id);
        assert_eq!(
            detail.event.governance_transition.as_deref(),
            Some("hold")
        );
        assert_eq!(detail.event.from_state.as_deref(), Some("canonical"));
        assert_eq!(detail.event.to_state.as_deref(), Some("held"));
    }
}
