use crate::code_provenance::CodeProvenanceCaptureRequest;
use crate::collaborative_workbench::CollaborativeComputeExperimentWorkbenchBundle;
use crate::result_catalog::DarwinHpcGatewayClient;
use crate::run_capsule::{read_run_capsule_by_run_id, ReplayRequest};
use crate::tool_bridge::ToolBridge;
use crate::workbench_run::{
    orchestrate_workbench_run, WorkbenchRunDispatchRequest, WorkbenchRunOrchestrationBundle,
};
use crate::workspace_plane::workspace_plane_dir;
use crate::WorkstreamControlRoomDetailResponse;
use anyhow::{anyhow, Context};
use chrono::{DateTime, Utc};
use serde::{Deserialize, Serialize};
use std::fs;
use std::path::{Path, PathBuf};

const REPLAY_EXECUTION_PHASE: &str = "B25.7";
const REPLAY_EXECUTION_KIND: &str = "replay-execution";
const REPLAY_EXECUTION_VERSION: &str = "beagle-replay-execution-v1";
const WORKBENCH_API_PREFIX: &str = "/api/darwin/workstreams";

#[derive(Debug, Clone)]
pub struct ReplayExecutionRequest<'a> {
    pub requested_by: &'a str,
    pub requester_role_id: &'a str,
    pub execution_mode: &'a str,
    pub run_label: Option<&'a str>,
    pub reservation_note: &'a str,
    pub dispatch_note: &'a str,
    pub poll_interval_seconds: Option<u64>,
    pub timeout_seconds: Option<u64>,
    pub code_provenance_capture: Option<&'a CodeProvenanceCaptureRequest>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ReplayExecutionReceipt {
    pub phase: String,
    pub contract_kind: String,
    pub contract_version: String,
    pub replay_execution_id: String,
    pub replay_request_id: String,
    pub source_run_id: String,
    pub source_submitted_job_id: u64,
    pub source_run_label: String,
    pub source_intent_text: String,
    pub workstream_id: String,
    pub workspace_id: String,
    pub session_id: String,
    pub same_beagle_owned_identity: bool,
    pub requested_by: String,
    pub requester_role_id: String,
    pub execution_mode: String,
    pub replay_mode: String,
    pub selected_subagent_id: String,
    pub task_family: String,
    pub compute_profile_id: String,
    pub run_label: String,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub source_branch: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub source_commit: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub source_tree_ish: Option<String>,
    pub source_dirty_state: String,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub source_patch_ref: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub source_source_fingerprint: Option<String>,
    pub source_config_fingerprint: String,
    pub source_result_manifest_key: String,
    pub dispatched_run_id: String,
    pub submitted_job_id: u64,
    pub published_result_job_id: u64,
    pub replay_request_path: String,
    pub workbench_run_path: String,
    pub run_capsule_path: String,
    pub run_diff_path: String,
    pub recorded_at: DateTime<Utc>,
    pub note: String,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ReplayExecutionBundle {
    pub status: String,
    pub phase: String,
    pub replay_request: ReplayRequest,
    pub replay_execution: ReplayExecutionReceipt,
    pub run_orchestration: WorkbenchRunOrchestrationBundle,
}

pub async fn execute_replay_request(
    data_dir: &Path,
    cfg: &beagle_config::BeagleConfig,
    gateway: &DarwinHpcGatewayClient,
    bridge: &ToolBridge,
    detail: &WorkstreamControlRoomDetailResponse,
    workbench_bundle: &CollaborativeComputeExperimentWorkbenchBundle,
    replay_request: &ReplayRequest,
    request: &ReplayExecutionRequest<'_>,
) -> anyhow::Result<ReplayExecutionBundle> {
    let requested_by = normalize_sentence(request.requested_by);
    let requester_role_id = normalize_selector(request.requester_role_id);
    let execution_mode = normalize_execution_mode(request.execution_mode)?;
    let reservation_note = normalize_sentence(request.reservation_note);
    let dispatch_note = normalize_sentence(request.dispatch_note);
    if requested_by.is_empty() {
        return Err(anyhow!("requested_by must not be empty"));
    }
    if requester_role_id.is_empty() {
        return Err(anyhow!("requester_role_id must not be empty"));
    }
    if reservation_note.is_empty() {
        return Err(anyhow!("reservation_note must not be empty"));
    }
    if dispatch_note.is_empty() {
        return Err(anyhow!("dispatch_note must not be empty"));
    }

    let source_capsule = read_run_capsule_by_run_id(
        data_dir,
        &replay_request.workspace_id,
        &replay_request.source_run_id,
    )?
    .ok_or_else(|| {
        anyhow!(
            "source run capsule {} missing for workspace {}",
            replay_request.source_run_id,
            replay_request.workspace_id
        )
    })?;

    let default_run_label = default_run_label(
        replay_request.source_run_label.as_str(),
        execution_mode.as_str(),
    );
    let requested_run_label = request
        .run_label
        .map(normalize_sentence)
        .filter(|value| !value.is_empty())
        .unwrap_or(default_run_label);

    let run_orchestration = orchestrate_workbench_run(
        data_dir,
        cfg,
        gateway,
        bridge,
        detail,
        workbench_bundle,
        &WorkbenchRunDispatchRequest {
            requested_by: &requested_by,
            requester_role_id: &requester_role_id,
            selected_subagent_id: replay_request.selected_subagent_id.as_str(),
            task_family: replay_request.task_family.as_str(),
            intent_text: source_capsule.input_manifest.intent_text.as_str(),
            compute_profile_id: replay_request.compute_profile_id.as_str(),
            run_label: Some(requested_run_label.as_str()),
            recipe_kind: replay_request.recipe_kind.as_deref(),
            experiment_id: replay_request.experiment_id.as_deref(),
            reservation_note: &reservation_note,
            dispatch_note: &dispatch_note,
            poll_interval_seconds: request.poll_interval_seconds,
            timeout_seconds: request.timeout_seconds,
            code_provenance_capture: request.code_provenance_capture,
        },
    )
    .await?;

    let replay_execution = ReplayExecutionReceipt {
        phase: REPLAY_EXECUTION_PHASE.to_string(),
        contract_kind: REPLAY_EXECUTION_KIND.to_string(),
        contract_version: REPLAY_EXECUTION_VERSION.to_string(),
        replay_execution_id: format!(
            "{}-replay-execution-{}",
            sanitize_component(&replay_request.session_id),
            Utc::now().timestamp_millis()
        ),
        replay_request_id: replay_request.replay_request_id.clone(),
        source_run_id: replay_request.source_run_id.clone(),
        source_submitted_job_id: replay_request.source_submitted_job_id,
        source_run_label: replay_request.source_run_label.clone(),
        source_intent_text: replay_request.source_intent_text.clone(),
        workstream_id: replay_request.workstream_id.clone(),
        workspace_id: replay_request.workspace_id.clone(),
        session_id: replay_request.session_id.clone(),
        same_beagle_owned_identity: replay_request.same_beagle_owned_identity
            && run_orchestration.run.same_beagle_owned_identity
            && replay_request.workspace_id == run_orchestration.run.workspace_id
            && replay_request.session_id == run_orchestration.run.session_id
            && replay_request.workstream_id == run_orchestration.run.workstream_id,
        requested_by,
        requester_role_id,
        execution_mode: execution_mode.clone(),
        replay_mode: match execution_mode.as_str() {
            "branch-fork" => "bounded-workbench-branch-fork".to_string(),
            _ => replay_request.replay_mode.clone(),
        },
        selected_subagent_id: replay_request.selected_subagent_id.clone(),
        task_family: replay_request.task_family.clone(),
        compute_profile_id: replay_request.compute_profile_id.clone(),
        run_label: run_orchestration.run.run_label.clone(),
        source_branch: replay_request.source_branch.clone(),
        source_commit: replay_request.source_commit.clone(),
        source_tree_ish: replay_request.source_tree_ish.clone(),
        source_dirty_state: replay_request.source_dirty_state.clone(),
        source_patch_ref: replay_request.source_patch_ref.clone(),
        source_source_fingerprint: replay_request.source_source_fingerprint.clone(),
        source_config_fingerprint: replay_request.config_fingerprint.clone(),
        source_result_manifest_key: replay_request.result_manifest_key.clone(),
        dispatched_run_id: run_orchestration.run.run_id.clone(),
        submitted_job_id: run_orchestration.run.submitted_job_id,
        published_result_job_id: run_orchestration.run.published_result_job_id,
        replay_request_path: format!(
            "{}/{}/replay-request",
            WORKBENCH_API_PREFIX, replay_request.workstream_id
        ),
        workbench_run_path: run_orchestration.run.workbench_run_path.clone(),
        run_capsule_path: format!(
            "{}/{}/run-capsule",
            WORKBENCH_API_PREFIX, replay_request.workstream_id
        ),
        run_diff_path: format!(
            "{}/{}/run-diff",
            WORKBENCH_API_PREFIX, replay_request.workstream_id
        ),
        recorded_at: Utc::now(),
        note: format!(
            "B25.7 re-submits source run {} through the existing bounded workbench lane in {} mode, keeps the same Beagle-owned workspace/session identity, and records one explicit replay/fork receipt instead of opening a second execution plane.",
            replay_request.source_run_id, execution_mode
        ),
    };
    write_replay_execution(data_dir, &replay_execution)?;

    Ok(ReplayExecutionBundle {
        status: "ok".to_string(),
        phase: REPLAY_EXECUTION_PHASE.to_string(),
        replay_request: replay_request.clone(),
        replay_execution,
        run_orchestration,
    })
}

pub fn read_latest_replay_execution(
    data_dir: &Path,
    workspace_id: &str,
) -> anyhow::Result<Option<ReplayExecutionReceipt>> {
    let dir = replay_execution_dir(data_dir, workspace_id);
    if !dir.exists() {
        return Ok(None);
    }

    let mut receipts = Vec::new();
    for entry in fs::read_dir(&dir)
        .with_context(|| format!("failed to read replay execution dir {}", dir.display()))?
    {
        let entry = entry?;
        let path = entry.path();
        if path.extension().and_then(|value| value.to_str()) != Some("json") {
            continue;
        }
        let body = fs::read_to_string(&path)
            .with_context(|| format!("failed to read replay execution {}", path.display()))?;
        let receipt = serde_json::from_str::<ReplayExecutionReceipt>(&body)
            .with_context(|| format!("failed to parse replay execution {}", path.display()))?;
        receipts.push(receipt);
    }
    Ok(receipts.into_iter().max_by_key(|receipt| receipt.recorded_at))
}

fn write_replay_execution(
    data_dir: &Path,
    receipt: &ReplayExecutionReceipt,
) -> anyhow::Result<()> {
    let dir = replay_execution_dir(data_dir, &receipt.workspace_id);
    fs::create_dir_all(&dir)
        .with_context(|| format!("failed to create replay execution dir {}", dir.display()))?;
    let path = dir.join(format!(
        "{}.json",
        sanitize_component(&receipt.replay_execution_id)
    ));
    let body = serde_json::to_string_pretty(receipt)?;
    fs::write(&path, body)
        .with_context(|| format!("failed to write replay execution {}", path.display()))
}

fn replay_execution_dir(data_dir: &Path, workspace_id: &str) -> PathBuf {
    workspace_plane_dir(data_dir)
        .join("replay-executions")
        .join(sanitize_component(workspace_id))
}

fn default_run_label(source_run_label: &str, execution_mode: &str) -> String {
    let suffix = match execution_mode {
        "branch-fork" => "fork",
        _ => "replay",
    };
    let base = normalize_sentence(source_run_label);
    format!("{base}-{suffix}")
}

fn normalize_execution_mode(value: &str) -> anyhow::Result<String> {
    match value.trim().to_ascii_lowercase().replace('_', "-").as_str() {
        "replay" => Ok("replay".to_string()),
        "branch-fork" | "fork" => Ok("branch-fork".to_string()),
        other => Err(anyhow!(
            "execution_mode must be one of replay or branch-fork, got '{}'",
            other
        )),
    }
}

fn normalize_selector(value: &str) -> String {
    value.trim().to_ascii_lowercase().replace('_', "-")
}

fn normalize_sentence(value: &str) -> String {
    value.split_whitespace().collect::<Vec<_>>().join(" ")
}

fn sanitize_component(value: &str) -> String {
    let sanitized = value
        .trim()
        .chars()
        .map(|character| {
            if character.is_ascii_alphanumeric() {
                character.to_ascii_lowercase()
            } else {
                '-'
            }
        })
        .collect::<String>();
    sanitized.trim_matches('-').to_string()
}

#[cfg(test)]
mod tests {
    use super::{default_run_label, normalize_execution_mode};

    #[test]
    fn normalizes_execution_modes() {
        assert_eq!(normalize_execution_mode("replay").unwrap(), "replay");
        assert_eq!(normalize_execution_mode("fork").unwrap(), "branch-fork");
        assert_eq!(
            normalize_execution_mode("branch_fork").unwrap(),
            "branch-fork"
        );
        assert!(normalize_execution_mode("freeform").is_err());
    }

    #[test]
    fn derives_default_run_label_by_mode() {
        assert_eq!(default_run_label("baseline-run", "replay"), "baseline-run-replay");
        assert_eq!(
            default_run_label("baseline-run", "branch-fork"),
            "baseline-run-fork"
        );
    }
}
