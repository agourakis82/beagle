use crate::collaborative_workbench::CollaborativeComputeExperimentWorkbenchBundle;
use crate::workspace_plane::workspace_plane_dir;
use anyhow::{anyhow, Context};
use chrono::{DateTime, Utc};
use serde::{Deserialize, Serialize};
use std::fs;
use std::path::{Path, PathBuf};

const WORKBENCH_RESERVATION_PHASE: &str = "B25.3";
const WORKBENCH_RESERVATION_KIND: &str = "workbench-reservation";
const WORKBENCH_RESERVATION_VERSION: &str = "beagle-workbench-reservation-v1";
const WORKBENCH_API_PREFIX: &str = "/api/darwin/workstreams";

#[derive(Debug, Clone, Serialize, Deserialize)]
struct WorkbenchReservationRecord {
    contract_version: String,
    reservation_id: String,
    workstream_id: String,
    workspace_id: String,
    session_id: String,
    same_beagle_owned_identity: bool,
    requested_by: String,
    requester_role_id: String,
    compute_profile_id: String,
    compute_kind: String,
    compute_partition: String,
    gpu_requested: bool,
    selected_subagent_id: String,
    task_family: String,
    intent_text: String,
    recipe_kind: Option<String>,
    experiment_id: Option<String>,
    submit_mode: String,
    gpu_access_mode: String,
    reserved_at: DateTime<Utc>,
    reservation_note: String,
}

#[derive(Debug, Clone)]
pub struct WorkbenchReservationRequest<'a> {
    pub requested_by: &'a str,
    pub requester_role_id: &'a str,
    pub compute_profile_id: &'a str,
    pub selected_subagent_id: &'a str,
    pub task_family: &'a str,
    pub intent_text: &'a str,
    pub recipe_kind: Option<&'a str>,
    pub experiment_id: Option<&'a str>,
    pub reservation_note: &'a str,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct WorkbenchReservation {
    pub phase: String,
    pub contract_kind: String,
    pub contract_version: String,
    pub reservation_id: String,
    pub workstream_id: String,
    pub workspace_id: String,
    pub session_id: String,
    pub same_beagle_owned_identity: bool,
    pub reservation_state: String,
    pub requested_by: String,
    pub requester_role_id: String,
    pub compute_profile_id: String,
    pub compute_kind: String,
    pub compute_partition: String,
    pub gpu_requested: bool,
    pub scheduler_kind: String,
    pub quota_policy_kind: String,
    pub submit_mode: String,
    pub gpu_access_mode: String,
    pub bounded_partner_access: bool,
    pub selected_subagent_id: String,
    pub task_family: String,
    pub intent_text: String,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub recipe_kind: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub experiment_id: Option<String>,
    pub reserved_at: DateTime<Utc>,
    pub reservation_note: String,
    pub workspace_tenancy_path: String,
    pub compute_selection_path: String,
    pub collaboration_access_path: String,
    pub workbench_reservation_path: String,
    pub note: String,
}

pub fn record_workbench_reservation(
    data_dir: &Path,
    workbench_bundle: &CollaborativeComputeExperimentWorkbenchBundle,
    request: &WorkbenchReservationRequest<'_>,
) -> anyhow::Result<WorkbenchReservation> {
    let requested_by = normalize_sentence(request.requested_by);
    let requester_role_id = normalize_selector(request.requester_role_id);
    let compute_profile_id = normalize_selector(request.compute_profile_id);
    let selected_subagent_id = normalize_selector(request.selected_subagent_id);
    let task_family = normalize_selector(request.task_family);
    let intent_text = normalize_sentence(request.intent_text);
    let reservation_note = normalize_sentence(request.reservation_note);

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
    if reservation_note.is_empty() {
        return Err(anyhow!("reservation_note must not be empty"));
    }

    ensure_subagent_allowed(workbench_bundle, &selected_subagent_id)?;
    let compute_scope = role_scope_for_request(
        &workbench_bundle.compute_selection.role_scopes,
        &requester_role_id,
        &compute_profile_id,
    )?;
    let collaboration_role = collaboration_role_for_request(
        &workbench_bundle.collaboration_access.roles,
        &requester_role_id,
        &compute_profile_id,
    )?;
    let compute_class = workbench_bundle
        .compute_selection
        .compute_classes
        .iter()
        .find(|class| class.profile_id == compute_profile_id)
        .ok_or_else(|| anyhow!("unknown compute profile '{}'", compute_profile_id))?;
    let reserved_at = Utc::now();
    let reservation_id = format!(
        "{}-reservation-{}",
        sanitize_component(&workbench_bundle.workbench_session.session_id),
        reserved_at.timestamp_millis()
    );
    let record = WorkbenchReservationRecord {
        contract_version: WORKBENCH_RESERVATION_VERSION.to_string(),
        reservation_id,
        workstream_id: workbench_bundle.workbench_session.workstream_id.clone(),
        workspace_id: workbench_bundle.workbench_session.workspace_id.clone(),
        session_id: workbench_bundle.workbench_session.session_id.clone(),
        same_beagle_owned_identity: workbench_bundle
            .workbench_session
            .same_beagle_owned_identity,
        requested_by,
        requester_role_id,
        compute_profile_id,
        compute_kind: compute_class.kind.clone(),
        compute_partition: compute_class.partition.clone(),
        gpu_requested: compute_class.gpu,
        selected_subagent_id,
        task_family,
        intent_text,
        recipe_kind: request.recipe_kind.map(normalize_sentence),
        experiment_id: request.experiment_id.map(normalize_selector),
        submit_mode: compute_scope.submit_mode.clone(),
        gpu_access_mode: compute_scope.gpu_access_mode.clone(),
        reserved_at,
        reservation_note,
    };
    write_reservation_record(data_dir, &record.workspace_id, &record)?;
    Ok(reservation_from_record(
        workbench_bundle,
        Some(collaboration_role),
        record,
    ))
}

pub fn read_workbench_reservation(
    data_dir: &Path,
    workbench_bundle: &CollaborativeComputeExperimentWorkbenchBundle,
) -> anyhow::Result<Option<WorkbenchReservation>> {
    let Some(record) = read_reservation_record(
        data_dir,
        &workbench_bundle.workbench_session.workspace_id,
    )? else {
        return Ok(None);
    };
    let collaboration_role = workbench_bundle
        .collaboration_access
        .roles
        .iter()
        .find(|role| role.role_id == record.requester_role_id);
    Ok(Some(reservation_from_record(
        workbench_bundle,
        collaboration_role,
        record,
    )))
}

pub(crate) fn role_scope_for_request<'a>(
    role_scopes: &'a [crate::ComputeRoleScope],
    requester_role_id: &str,
    compute_profile_id: &str,
) -> anyhow::Result<&'a crate::ComputeRoleScope> {
    let scope = role_scopes
        .iter()
        .find(|scope| scope.role_id == requester_role_id)
        .ok_or_else(|| anyhow!("unknown requester_role_id '{}'", requester_role_id))?;
    if !scope
        .allowed_profile_ids
        .iter()
        .any(|profile| profile == compute_profile_id)
    {
        return Err(anyhow!(
            "role '{}' is not allowed to reserve compute profile '{}'",
            requester_role_id,
            compute_profile_id
        ));
    }
    Ok(scope)
}

fn collaboration_role_for_request<'a>(
    roles: &'a [crate::PartnerAccessRole],
    requester_role_id: &str,
    compute_profile_id: &str,
) -> anyhow::Result<&'a crate::PartnerAccessRole> {
    let role = roles
        .iter()
        .find(|role| role.role_id == requester_role_id)
        .ok_or_else(|| anyhow!("unknown collaboration role '{}'", requester_role_id))?;
    if !role.workspace_attach_allowed || !role.shared_workspace_allowed {
        return Err(anyhow!(
            "role '{}' is not allowed to use the shared workspace workbench",
            requester_role_id
        ));
    }
    if !role
        .allowed_profile_ids
        .iter()
        .any(|profile| profile == compute_profile_id)
    {
        return Err(anyhow!(
            "role '{}' is not allowed to use compute profile '{}'",
            requester_role_id,
            compute_profile_id
        ));
    }
    Ok(role)
}

fn ensure_subagent_allowed(
    workbench_bundle: &CollaborativeComputeExperimentWorkbenchBundle,
    selected_subagent_id: &str,
) -> anyhow::Result<()> {
    if workbench_bundle
        .workbench_session
        .subagent_roles
        .iter()
        .any(|role| role.subagent_id == selected_subagent_id)
    {
        Ok(())
    } else {
        Err(anyhow!(
            "unknown subagent '{}' for workbench '{}'",
            selected_subagent_id,
            workbench_bundle.workbench_session.workstream_id
        ))
    }
}

fn reservation_from_record(
    workbench_bundle: &CollaborativeComputeExperimentWorkbenchBundle,
    collaboration_role: Option<&crate::PartnerAccessRole>,
    record: WorkbenchReservationRecord,
) -> WorkbenchReservation {
    let workstream_id = &workbench_bundle.workbench_session.workstream_id;
    WorkbenchReservation {
        phase: WORKBENCH_RESERVATION_PHASE.to_string(),
        contract_kind: WORKBENCH_RESERVATION_KIND.to_string(),
        contract_version: record.contract_version.clone(),
        reservation_id: record.reservation_id.clone(),
        workstream_id: record.workstream_id.clone(),
        workspace_id: record.workspace_id.clone(),
        session_id: record.session_id.clone(),
        same_beagle_owned_identity: record.same_beagle_owned_identity,
        reservation_state: "reserved".to_string(),
        requested_by: record.requested_by.clone(),
        requester_role_id: record.requester_role_id.clone(),
        compute_profile_id: record.compute_profile_id.clone(),
        compute_kind: record.compute_kind.clone(),
        compute_partition: record.compute_partition.clone(),
        gpu_requested: record.gpu_requested,
        scheduler_kind: workbench_bundle.compute_selection.scheduler_kind.clone(),
        quota_policy_kind: workbench_bundle.compute_selection.quota_policy_kind.clone(),
        submit_mode: record.submit_mode.clone(),
        gpu_access_mode: record.gpu_access_mode.clone(),
        bounded_partner_access: collaboration_role
            .map(|role| !role.cluster_admin_allowed && !role.direct_kubernetes_access_allowed)
            .unwrap_or(false),
        selected_subagent_id: record.selected_subagent_id.clone(),
        task_family: record.task_family.clone(),
        intent_text: record.intent_text.clone(),
        recipe_kind: record.recipe_kind.clone(),
        experiment_id: record.experiment_id.clone(),
        reserved_at: record.reserved_at,
        reservation_note: record.reservation_note.clone(),
        workspace_tenancy_path: format!("{}/{}/workspace-tenancy", WORKBENCH_API_PREFIX, workstream_id),
        compute_selection_path: format!("{}/{}/compute-selection", WORKBENCH_API_PREFIX, workstream_id),
        collaboration_access_path: format!("{}/{}/collaboration-access", WORKBENCH_API_PREFIX, workstream_id),
        workbench_reservation_path: format!("{}/{}/workbench-reservation", WORKBENCH_API_PREFIX, workstream_id),
        note: "B25.3 keeps reservation creation explicit and operator-visible: compute is reserved inside the Beagle workbench contract before the run is dispatched, with role/profile scope checks applied up front.".to_string(),
    }
}

fn reservation_records_dir(data_dir: &Path) -> PathBuf {
    workspace_plane_dir(data_dir).join("workbench-reservations")
}

fn reservation_record_path(data_dir: &Path, workspace_id: &str) -> PathBuf {
    reservation_records_dir(data_dir).join(format!("{}.json", sanitize_component(workspace_id)))
}

fn write_reservation_record(
    data_dir: &Path,
    workspace_id: &str,
    record: &WorkbenchReservationRecord,
) -> anyhow::Result<()> {
    let dir = reservation_records_dir(data_dir);
    fs::create_dir_all(&dir)
        .with_context(|| format!("failed to create workbench reservation dir {}", dir.display()))?;
    let path = reservation_record_path(data_dir, workspace_id);
    let body = serde_json::to_string_pretty(record)?;
    fs::write(&path, body)
        .with_context(|| format!("failed to write workbench reservation record {}", path.display()))
}

fn read_reservation_record(
    data_dir: &Path,
    workspace_id: &str,
) -> anyhow::Result<Option<WorkbenchReservationRecord>> {
    let path = reservation_record_path(data_dir, workspace_id);
    if !path.exists() {
        return Ok(None);
    }
    let body = fs::read_to_string(&path)
        .with_context(|| format!("failed to read workbench reservation record {}", path.display()))?;
    let record = serde_json::from_str::<WorkbenchReservationRecord>(&body).with_context(|| {
        format!(
            "failed to parse workbench reservation record {}",
            path.display()
        )
    })?;
    Ok(Some(record))
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
    use super::role_scope_for_request;
    use crate::workspace_tenancy::ComputeRoleScope;

    #[test]
    fn rejects_profile_outside_role_scope() {
        let scopes = vec![ComputeRoleScope {
            role_id: "partner-dev".to_string(),
            allowed_profile_ids: vec!["cpu-short-v1".to_string(), "gpu-single-v1".to_string()],
            submit_mode: "scoped-profile-submit".to_string(),
            gpu_access_mode: "typed-isolated-gpu".to_string(),
            quota_boundary: "role+profile-id".to_string(),
            note: "test".to_string(),
        }];
        let error = role_scope_for_request(&scopes, "partner-dev", "cpu-batch-v1")
            .unwrap_err()
            .to_string();
        assert!(error.contains("not allowed"));
    }
}
