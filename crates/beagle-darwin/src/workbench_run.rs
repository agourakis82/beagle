use crate::collaborative_workbench::CollaborativeComputeExperimentWorkbenchBundle;
use crate::code_provenance::CodeProvenanceCaptureRequest;
use crate::result_catalog::DarwinHpcGatewayClient;
use crate::run_capsule::record_run_capsule;
use crate::tool_bridge::ToolBridge;
use crate::workbench_reservation::{
    record_workbench_reservation, role_scope_for_request, WorkbenchReservation,
    WorkbenchReservationRequest,
};
use crate::workbench_result_binding::{
    record_deterministic_result_binding, record_run_result_identity_receipt,
    record_run_scoped_publication, record_workbench_result_binding, DeterministicResultBinding,
    RunResultIdentityReceipt, RunScopedPublication, WorkbenchResultBinding,
};
use crate::workspace_plane::{
    run_workspace_pilot, workspace_plane_dir, WorkspacePilotRequest,
    WorkspacePilotResponse, WorkspacePilotWorkstreamOverride,
};
use crate::WorkstreamControlRoomDetailResponse;
use anyhow::{anyhow, Context};
use beagle_config::BeagleConfig;
use chrono::{DateTime, Utc};
use serde::{Deserialize, Serialize};
use std::fs;
use std::path::{Path, PathBuf};

const WORKBENCH_RUN_PHASE: &str = "B25.3";
const WORKBENCH_RUN_KIND: &str = "workbench-run-orchestration";
const WORKBENCH_RUN_VERSION: &str = "beagle-workbench-run-orchestration-v1";
const WORKBENCH_API_PREFIX: &str = "/api/darwin/workstreams";

#[derive(Debug, Clone, Serialize, Deserialize)]
struct WorkbenchRunRecord {
    contract_version: String,
    run_id: String,
    reservation_id: String,
    workstream_id: String,
    workspace_id: String,
    session_id: String,
    same_beagle_owned_identity: bool,
    requested_by: String,
    requester_role_id: String,
    selected_subagent_id: String,
    task_family: String,
    intent_text: String,
    recipe_kind: Option<String>,
    experiment_id: Option<String>,
    compute_profile_id: String,
    run_label: String,
    scheduler_kind: String,
    submit_mode: String,
    current_state: String,
    lifecycle_transitions: Vec<WorkbenchRunTransition>,
    submitted_job_id: u64,
    published_result_job_id: u64,
    published_result_manifest_key: String,
    artifact_ready: bool,
    dispatch_note: String,
}

#[derive(Debug, Clone)]
pub struct WorkbenchRunDispatchRequest<'a> {
    pub requested_by: &'a str,
    pub requester_role_id: &'a str,
    pub selected_subagent_id: &'a str,
    pub task_family: &'a str,
    pub intent_text: &'a str,
    pub compute_profile_id: &'a str,
    pub run_label: Option<&'a str>,
    pub recipe_kind: Option<&'a str>,
    pub experiment_id: Option<&'a str>,
    pub reservation_note: &'a str,
    pub dispatch_note: &'a str,
    pub poll_interval_seconds: Option<u64>,
    pub timeout_seconds: Option<u64>,
    pub code_provenance_capture: Option<&'a CodeProvenanceCaptureRequest>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct WorkbenchRunTransition {
    pub state: String,
    pub transitioned_at: DateTime<Utc>,
    pub note: String,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct WorkbenchRun {
    pub phase: String,
    pub contract_kind: String,
    pub contract_version: String,
    pub run_id: String,
    pub reservation_id: String,
    pub workstream_id: String,
    pub workspace_id: String,
    pub session_id: String,
    pub same_beagle_owned_identity: bool,
    pub requested_by: String,
    pub requester_role_id: String,
    pub selected_subagent_id: String,
    pub task_family: String,
    pub intent_text: String,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub recipe_kind: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub experiment_id: Option<String>,
    pub compute_profile_id: String,
    pub run_label: String,
    pub scheduler_kind: String,
    pub submit_mode: String,
    pub current_state: String,
    pub lifecycle_transitions: Vec<WorkbenchRunTransition>,
    pub submitted_job_id: u64,
    pub published_result_job_id: u64,
    pub published_result_manifest_key: String,
    pub artifact_ready: bool,
    pub bounded_partner_access: bool,
    pub direct_cluster_admin_grant: bool,
    pub direct_kubernetes_access_grant: bool,
    pub workbench_run_path: String,
    pub workbench_result_binding_path: String,
    pub collaborative_workbench_path: String,
    pub note: String,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct WorkbenchRunOrchestrationBundle {
    pub status: String,
    pub phase: String,
    pub reservation: WorkbenchReservation,
    pub run: WorkbenchRun,
    pub result_binding: WorkbenchResultBinding,
    pub run_result_identity_receipt: RunResultIdentityReceipt,
    pub run_scoped_publication: RunScopedPublication,
    pub deterministic_result_binding: DeterministicResultBinding,
}

pub async fn orchestrate_workbench_run(
    data_dir: &Path,
    cfg: &BeagleConfig,
    gateway: &DarwinHpcGatewayClient,
    bridge: &ToolBridge,
    detail: &WorkstreamControlRoomDetailResponse,
    workbench_bundle: &CollaborativeComputeExperimentWorkbenchBundle,
    request: &WorkbenchRunDispatchRequest<'_>,
) -> anyhow::Result<WorkbenchRunOrchestrationBundle> {
    let requested_by = normalize_sentence(request.requested_by);
    let requester_role_id = normalize_selector(request.requester_role_id);
    let compute_profile_id = normalize_selector(request.compute_profile_id);
    let selected_subagent_id = normalize_selector(request.selected_subagent_id);
    let task_family = normalize_selector(request.task_family);
    let intent_text = normalize_sentence(request.intent_text);
    let dispatch_note = normalize_sentence(request.dispatch_note);

    if requested_by.is_empty() {
        return Err(anyhow!("requested_by must not be empty"));
    }
    if requester_role_id.is_empty() {
        return Err(anyhow!("requester_role_id must not be empty"));
    }
    if compute_profile_id.is_empty() {
        return Err(anyhow!("compute_profile_id must not be empty"));
    }
    if selected_subagent_id.is_empty() {
        return Err(anyhow!("selected_subagent_id must not be empty"));
    }
    if task_family.is_empty() {
        return Err(anyhow!("task_family must not be empty"));
    }
    if intent_text.is_empty() {
        return Err(anyhow!("intent_text must not be empty"));
    }
    if dispatch_note.is_empty() {
        return Err(anyhow!("dispatch_note must not be empty"));
    }

    let reservation = record_workbench_reservation(
        data_dir,
        workbench_bundle,
        &WorkbenchReservationRequest {
            requested_by: &requested_by,
            requester_role_id: &requester_role_id,
            compute_profile_id: &compute_profile_id,
            selected_subagent_id: &selected_subagent_id,
            task_family: &task_family,
            intent_text: &intent_text,
            recipe_kind: request.recipe_kind,
            experiment_id: request.experiment_id,
            reservation_note: request.reservation_note,
        },
    )?;
    let collaboration_role = workbench_bundle
        .collaboration_access
        .roles
        .iter()
        .find(|role| role.role_id == requester_role_id)
        .ok_or_else(|| anyhow!("unknown collaboration role '{}'", requester_role_id))?;
    let role_scope = role_scope_for_request(
        &workbench_bundle.compute_selection.role_scopes,
        &requester_role_id,
        &compute_profile_id,
    )?;

    let pilot_request = WorkspacePilotRequest {
        workspace_id: reservation.workspace_id.clone(),
        session_id: Some(reservation.session_id.clone()),
        profile_id: Some(compute_profile_id.clone()),
        run_label: request.run_label.map(normalize_sentence),
        poll_interval_seconds: request.poll_interval_seconds,
        timeout_seconds: request.timeout_seconds,
        workstream_override: Some(WorkspacePilotWorkstreamOverride {
            workstream_id: reservation.workstream_id.clone(),
            canonical_repo: Some(detail.spec.repo.clone()),
            default_branch: detail.spec.default_branch.clone(),
            canonical_track: Some(cfg.workspace.canonical_track.clone()),
            branch_lineage: None,
            governance_state: Some(detail.status_view.governance_state.clone()),
            governance_last_transition: Some(detail.status_view.governance_last_transition.clone()),
            default_dev_plane: Some(detail.spec.default_dev_plane.clone()),
            vm_fallback_role: Some(detail.spec.vm_fallback_role.clone()),
            promotion_scope: Some(detail.spec.scope.clone()),
        }),
    };

    let pilot_response = run_workspace_pilot(data_dir, cfg, gateway, bridge, &pilot_request).await?;
    let run_record = run_record_from_pilot(
        workbench_bundle,
        &reservation,
        collaboration_role,
        role_scope.submit_mode.as_str(),
        &dispatch_note,
        &pilot_response,
    );
    write_run_record(data_dir, &run_record.workspace_id, &run_record)?;
    let run = run_from_record(&run_record);
    let result_binding = record_workbench_result_binding(
        data_dir,
        &detail.registry_entry.id,
        &reservation,
        &run,
        &pilot_response,
    )?;
    let run_result_identity_receipt = record_run_result_identity_receipt(
        data_dir,
        &detail.registry_entry.id,
        &reservation,
        &run,
        &pilot_response,
    )?;
    let run_scoped_publication = record_run_scoped_publication(
        data_dir,
        &detail.registry_entry.id,
        &reservation,
        &run,
        &pilot_response,
    )?;
    let deterministic_result_binding = record_deterministic_result_binding(
        data_dir,
        &detail.registry_entry.id,
        &reservation,
        &run,
        &pilot_response,
    )?;
    record_run_capsule(
        data_dir,
        workbench_bundle,
        &reservation,
        &run,
        &result_binding,
        &deterministic_result_binding,
        &pilot_response,
        request.code_provenance_capture,
    )?;

    Ok(WorkbenchRunOrchestrationBundle {
        status: "ok".to_string(),
        phase: WORKBENCH_RUN_PHASE.to_string(),
        reservation,
        run,
        result_binding,
        run_result_identity_receipt,
        run_scoped_publication,
        deterministic_result_binding,
    })
}

pub fn read_workbench_run(
    data_dir: &Path,
    workspace_id: &str,
) -> anyhow::Result<Option<WorkbenchRun>> {
    let Some(record) = read_run_record(data_dir, workspace_id)? else {
        return Ok(None);
    };
    Ok(Some(run_from_record(&record)))
}

fn run_record_from_pilot(
    workbench_bundle: &CollaborativeComputeExperimentWorkbenchBundle,
    reservation: &WorkbenchReservation,
    collaboration_role: &crate::PartnerAccessRole,
    submit_mode: &str,
    dispatch_note: &str,
    pilot_response: &WorkspacePilotResponse,
) -> WorkbenchRunRecord {
    let finished_at = Utc::now();
    let queued_at = pilot_response
        .submitted_job
        .submitted_at
        .as_deref()
        .and_then(parse_gateway_timestamp)
        .unwrap_or(reservation.reserved_at);
    let running_at = pilot_response
        .final_job
        .start_time
        .as_deref()
        .and_then(parse_gateway_timestamp)
        .unwrap_or(queued_at);
    let current_state = normalize_job_state(pilot_response.final_job.state.as_deref());
    let run_id = format!(
        "{}-run-{}",
        sanitize_component(&reservation.session_id),
        finished_at.timestamp_millis()
    );
    WorkbenchRunRecord {
        contract_version: WORKBENCH_RUN_VERSION.to_string(),
        run_id,
        reservation_id: reservation.reservation_id.clone(),
        workstream_id: reservation.workstream_id.clone(),
        workspace_id: reservation.workspace_id.clone(),
        session_id: reservation.session_id.clone(),
        same_beagle_owned_identity: reservation.same_beagle_owned_identity,
        requested_by: reservation.requested_by.clone(),
        requester_role_id: reservation.requester_role_id.clone(),
        selected_subagent_id: reservation.selected_subagent_id.clone(),
        task_family: reservation.task_family.clone(),
        intent_text: reservation.intent_text.clone(),
        recipe_kind: reservation.recipe_kind.clone(),
        experiment_id: reservation.experiment_id.clone(),
        compute_profile_id: reservation.compute_profile_id.clone(),
        run_label: pilot_response.published_result.run_label.clone(),
        scheduler_kind: workbench_bundle.compute_selection.scheduler_kind.clone(),
        submit_mode: submit_mode.to_string(),
        current_state,
        lifecycle_transitions: vec![
            WorkbenchRunTransition {
                state: "reserved".to_string(),
                transitioned_at: reservation.reserved_at,
                note: reservation.reservation_note.clone(),
            },
            WorkbenchRunTransition {
                state: "queued".to_string(),
                transitioned_at: queued_at,
                note: format!(
                    "Workbench dispatched bounded submit on profile {}",
                    reservation.compute_profile_id
                ),
            },
            WorkbenchRunTransition {
                state: "running".to_string(),
                transitioned_at: running_at,
                note: dispatch_note.to_string(),
            },
            WorkbenchRunTransition {
                state: normalize_job_state(pilot_response.final_job.state.as_deref()),
                transitioned_at: finished_at,
                note: format!(
                    "Scheduler completed job {} and published result {}",
                    pilot_response.final_job.job_id, pilot_response.published_result.job_id
                ),
            },
        ],
        submitted_job_id: pilot_response.submitted_job.job_id,
        published_result_job_id: pilot_response.published_result.job_id,
        published_result_manifest_key: pilot_response
            .published_result
            .artifact_manifest_key
            .clone(),
        artifact_ready: pilot_response.final_job.artifact_ready.unwrap_or(false),
        dispatch_note: format!(
            "{} bounded_partner_access={} cluster_admin={} kubernetes_access={}",
            dispatch_note,
            !collaboration_role.cluster_admin_allowed && !collaboration_role.direct_kubernetes_access_allowed,
            collaboration_role.cluster_admin_allowed,
            collaboration_role.direct_kubernetes_access_allowed
        ),
    }
}

fn run_from_record(record: &WorkbenchRunRecord) -> WorkbenchRun {
    WorkbenchRun {
        phase: WORKBENCH_RUN_PHASE.to_string(),
        contract_kind: WORKBENCH_RUN_KIND.to_string(),
        contract_version: record.contract_version.clone(),
        run_id: record.run_id.clone(),
        reservation_id: record.reservation_id.clone(),
        workstream_id: record.workstream_id.clone(),
        workspace_id: record.workspace_id.clone(),
        session_id: record.session_id.clone(),
        same_beagle_owned_identity: record.same_beagle_owned_identity,
        requested_by: record.requested_by.clone(),
        requester_role_id: record.requester_role_id.clone(),
        selected_subagent_id: record.selected_subagent_id.clone(),
        task_family: record.task_family.clone(),
        intent_text: record.intent_text.clone(),
        recipe_kind: record.recipe_kind.clone(),
        experiment_id: record.experiment_id.clone(),
        compute_profile_id: record.compute_profile_id.clone(),
        run_label: record.run_label.clone(),
        scheduler_kind: record.scheduler_kind.clone(),
        submit_mode: record.submit_mode.clone(),
        current_state: record.current_state.clone(),
        lifecycle_transitions: record.lifecycle_transitions.clone(),
        submitted_job_id: record.submitted_job_id,
        published_result_job_id: record.published_result_job_id,
        published_result_manifest_key: record.published_result_manifest_key.clone(),
        artifact_ready: record.artifact_ready,
        bounded_partner_access: record.requester_role_id == "partner-dev",
        direct_cluster_admin_grant: false,
        direct_kubernetes_access_grant: false,
        workbench_run_path: format!(
            "{}/{}/workbench-run-orchestration",
            WORKBENCH_API_PREFIX, record.workstream_id
        ),
        workbench_result_binding_path: format!(
            "{}/{}/workbench-result-binding",
            WORKBENCH_API_PREFIX, record.workstream_id
        ),
        collaborative_workbench_path: format!(
            "{}/{}/collaborative-workbench",
            WORKBENCH_API_PREFIX, record.workstream_id
        ),
        note: "B25.3 dispatches one bounded run from a workbench reservation, tracks it through scheduler-backed states, and keeps the result in the same Beagle-owned workspace/session envelope.".to_string(),
    }
}

fn run_records_dir(data_dir: &Path) -> PathBuf {
    workspace_plane_dir(data_dir).join("workbench-runs")
}

fn run_record_path(data_dir: &Path, workspace_id: &str) -> PathBuf {
    run_records_dir(data_dir).join(format!("{}.json", sanitize_component(workspace_id)))
}

fn write_run_record(
    data_dir: &Path,
    workspace_id: &str,
    record: &WorkbenchRunRecord,
) -> anyhow::Result<()> {
    let dir = run_records_dir(data_dir);
    fs::create_dir_all(&dir)
        .with_context(|| format!("failed to create workbench run dir {}", dir.display()))?;
    let path = run_record_path(data_dir, workspace_id);
    let body = serde_json::to_string_pretty(record)?;
    fs::write(&path, body)
        .with_context(|| format!("failed to write workbench run record {}", path.display()))
}

fn read_run_record(
    data_dir: &Path,
    workspace_id: &str,
) -> anyhow::Result<Option<WorkbenchRunRecord>> {
    let path = run_record_path(data_dir, workspace_id);
    if !path.exists() {
        return Ok(None);
    }
    let body = fs::read_to_string(&path)
        .with_context(|| format!("failed to read workbench run record {}", path.display()))?;
    let record = serde_json::from_str::<WorkbenchRunRecord>(&body)
        .with_context(|| format!("failed to parse workbench run record {}", path.display()))?;
    Ok(Some(record))
}

fn parse_gateway_timestamp(value: &str) -> Option<DateTime<Utc>> {
    chrono::DateTime::parse_from_rfc3339(value)
        .map(|dt| dt.with_timezone(&Utc))
        .ok()
}

fn normalize_job_state(value: Option<&str>) -> String {
    match value.unwrap_or("UNKNOWN").trim().to_ascii_uppercase().as_str() {
        "PENDING" | "CONFIGURING" => "queued".to_string(),
        "RUNNING" | "COMPLETING" => "running".to_string(),
        "COMPLETED" => "succeeded".to_string(),
        "FAILED" | "TIMEOUT" | "CANCELLED" | "NODE_FAIL" | "OUT_OF_MEMORY" => {
            "failed".to_string()
        }
        "STOPPED" => "stopped".to_string(),
        _ => "failed".to_string(),
    }
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

fn normalize_selector(value: &str) -> String {
    value.trim().to_ascii_lowercase().replace('_', "-")
}

fn normalize_sentence(value: &str) -> String {
    value.split_whitespace().collect::<Vec<_>>().join(" ")
}

#[cfg(test)]
mod tests {
    use super::normalize_job_state;

    #[test]
    fn maps_completed_to_succeeded() {
        assert_eq!(normalize_job_state(Some("COMPLETED")), "succeeded");
        assert_eq!(normalize_job_state(Some("RUNNING")), "running");
        assert_eq!(normalize_job_state(Some("PENDING")), "queued");
    }
}
