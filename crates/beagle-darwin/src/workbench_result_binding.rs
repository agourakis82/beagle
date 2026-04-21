use crate::workspace_plane::{workspace_plane_dir, WorkspacePilotResponse};
use crate::workbench_reservation::WorkbenchReservation;
use crate::workbench_run::WorkbenchRun;
use anyhow::Context;
use chrono::{DateTime, Utc};
use serde::{Deserialize, Serialize};
use std::fs;
use std::path::{Path, PathBuf};

const WORKBENCH_RESULT_BINDING_PHASE: &str = "B25.3";
const WORKBENCH_RESULT_BINDING_KIND: &str = "workbench-result-binding";
const WORKBENCH_RESULT_BINDING_VERSION: &str = "beagle-workbench-result-binding-v1";
const RUN_RESULT_IDENTITY_RECEIPT_PHASE: &str = "B25.4";
const RUN_RESULT_IDENTITY_RECEIPT_KIND: &str = "run-result-identity-receipt";
const RUN_RESULT_IDENTITY_RECEIPT_VERSION: &str = "beagle-run-result-identity-receipt-v1";
const RUN_SCOPED_PUBLICATION_PHASE: &str = "B25.4";
const RUN_SCOPED_PUBLICATION_KIND: &str = "run-scoped-publication";
const RUN_SCOPED_PUBLICATION_VERSION: &str = "beagle-run-scoped-publication-v1";
const DETERMINISTIC_RESULT_BINDING_PHASE: &str = "B25.4";
const DETERMINISTIC_RESULT_BINDING_KIND: &str = "deterministic-result-binding";
const DETERMINISTIC_RESULT_BINDING_VERSION: &str = "beagle-deterministic-result-binding-v1";
const WORKBENCH_API_PREFIX: &str = "/api/darwin/workstreams";

#[derive(Debug, Clone, Serialize, Deserialize)]
struct WorkbenchResultBindingRecord {
    contract_version: String,
    binding_id: String,
    reservation_id: String,
    run_id: String,
    workstream_id: String,
    workspace_id: String,
    session_id: String,
    same_beagle_owned_identity: bool,
    compute_profile_id: String,
    selected_subagent_id: String,
    task_family: String,
    recipe_kind: Option<String>,
    experiment_id: Option<String>,
    submitted_job_id: u64,
    published_result_job_id: u64,
    published_result_run_label: String,
    published_result_profile_id: String,
    resolved_result_lookup_job_id: u64,
    artifact_manifest_job_id: u64,
    published_result_manifest_job_id: u64,
    published_result_manifest_key: String,
    final_job_state: String,
    artifact_ready: bool,
    result_bound_at: DateTime<Utc>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct WorkbenchBoundResultRef {
    pub ref_id: String,
    pub ref_kind: String,
    pub locator: String,
    pub summary: String,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct WorkbenchResultBinding {
    pub phase: String,
    pub contract_kind: String,
    pub contract_version: String,
    pub binding_id: String,
    pub reservation_id: String,
    pub run_id: String,
    pub workstream_id: String,
    pub workspace_id: String,
    pub session_id: String,
    pub same_beagle_owned_identity: bool,
    pub compute_profile_id: String,
    pub selected_subagent_id: String,
    pub task_family: String,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub recipe_kind: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub experiment_id: Option<String>,
    pub submitted_job_id: u64,
    pub published_result_job_id: u64,
    pub final_job_state: String,
    pub artifact_ready: bool,
    pub result_bound_at: DateTime<Utc>,
    pub result_catalog_lookup_path: String,
    pub result_manifest_path: String,
    pub workbench_run_path: String,
    pub collaborative_workbench_path: String,
    pub result_refs: Vec<WorkbenchBoundResultRef>,
    pub note: String,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
struct RunResultIdentityReceiptRecord {
    contract_version: String,
    receipt_id: String,
    reservation_id: String,
    run_id: String,
    workstream_id: String,
    workspace_id: String,
    session_id: String,
    same_beagle_owned_identity: bool,
    compute_profile_id: String,
    selected_subagent_id: String,
    task_family: String,
    submitted_job_id: u64,
    final_job_id: u64,
    requested_run_label: String,
    published_result_job_id: u64,
    published_result_run_label: String,
    resolved_result_lookup_job_id: u64,
    result_manifest_job_id: u64,
    published_result_manifest_key: String,
    result_manifest_object_key: String,
    result_lookup_scope: String,
    catalog_before_matching_run_count: usize,
    catalog_after_matching_run_count: usize,
    deterministic_identity_confirmed: bool,
    receipt_created_at: DateTime<Utc>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct RunResultIdentityReceipt {
    pub phase: String,
    pub contract_kind: String,
    pub contract_version: String,
    pub receipt_id: String,
    pub reservation_id: String,
    pub run_id: String,
    pub workstream_id: String,
    pub workspace_id: String,
    pub session_id: String,
    pub same_beagle_owned_identity: bool,
    pub compute_profile_id: String,
    pub selected_subagent_id: String,
    pub task_family: String,
    pub submitted_job_id: u64,
    pub final_job_id: u64,
    pub requested_run_label: String,
    pub published_result_job_id: u64,
    pub published_result_run_label: String,
    pub resolved_result_lookup_job_id: u64,
    pub result_manifest_job_id: u64,
    pub published_result_manifest_key: String,
    pub result_manifest_object_key: String,
    pub result_lookup_scope: String,
    pub catalog_before_matching_run_count: usize,
    pub catalog_after_matching_run_count: usize,
    pub deterministic_identity_confirmed: bool,
    pub receipt_created_at: DateTime<Utc>,
    pub workbench_run_path: String,
    pub run_scoped_publication_path: String,
    pub deterministic_result_binding_path: String,
    pub note: String,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
struct RunScopedPublicationRecord {
    contract_version: String,
    publication_id: String,
    reservation_id: String,
    run_id: String,
    workstream_id: String,
    workspace_id: String,
    session_id: String,
    same_beagle_owned_identity: bool,
    compute_profile_id: String,
    selected_subagent_id: String,
    task_family: String,
    submitted_job_id: u64,
    requested_run_label: String,
    published_result_job_id: u64,
    published_result_run_label: String,
    published_result_profile_id: String,
    final_job_state: String,
    result_lookup_scope: String,
    catalog_before_matching_run_count: usize,
    catalog_after_matching_run_count: usize,
    no_profile_latest_ambiguity: bool,
    published_result_manifest_key: String,
    published_at: DateTime<Utc>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct RunScopedPublication {
    pub phase: String,
    pub contract_kind: String,
    pub contract_version: String,
    pub publication_id: String,
    pub reservation_id: String,
    pub run_id: String,
    pub workstream_id: String,
    pub workspace_id: String,
    pub session_id: String,
    pub same_beagle_owned_identity: bool,
    pub compute_profile_id: String,
    pub selected_subagent_id: String,
    pub task_family: String,
    pub submitted_job_id: u64,
    pub requested_run_label: String,
    pub published_result_job_id: u64,
    pub published_result_run_label: String,
    pub published_result_profile_id: String,
    pub final_job_state: String,
    pub publication_state: String,
    pub result_lookup_scope: String,
    pub catalog_before_matching_run_count: usize,
    pub catalog_after_matching_run_count: usize,
    pub no_profile_latest_ambiguity: bool,
    pub published_result_manifest_key: String,
    pub published_at: DateTime<Utc>,
    pub result_catalog_lookup_path: String,
    pub run_result_identity_receipt_path: String,
    pub deterministic_result_binding_path: String,
    pub note: String,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
struct DeterministicResultBindingRecord {
    contract_version: String,
    binding_id: String,
    reservation_id: String,
    run_id: String,
    workstream_id: String,
    workspace_id: String,
    session_id: String,
    same_beagle_owned_identity: bool,
    compute_profile_id: String,
    selected_subagent_id: String,
    task_family: String,
    submitted_job_id: u64,
    requested_run_label: String,
    published_result_job_id: u64,
    published_result_run_label: String,
    resolved_result_lookup_job_id: u64,
    result_manifest_job_id: u64,
    published_result_manifest_key: String,
    result_manifest_object_key: String,
    result_lookup_scope: String,
    catalog_before_matching_run_count: usize,
    catalog_after_matching_run_count: usize,
    run_identity_confirmed: bool,
    no_profile_latest_ambiguity: bool,
    result_bound_at: DateTime<Utc>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct DeterministicResultBinding {
    pub phase: String,
    pub contract_kind: String,
    pub contract_version: String,
    pub binding_id: String,
    pub reservation_id: String,
    pub run_id: String,
    pub workstream_id: String,
    pub workspace_id: String,
    pub session_id: String,
    pub same_beagle_owned_identity: bool,
    pub compute_profile_id: String,
    pub selected_subagent_id: String,
    pub task_family: String,
    pub submitted_job_id: u64,
    pub requested_run_label: String,
    pub published_result_job_id: u64,
    pub published_result_run_label: String,
    pub resolved_result_lookup_job_id: u64,
    pub result_manifest_job_id: u64,
    pub published_result_manifest_key: String,
    pub result_manifest_object_key: String,
    pub result_lookup_scope: String,
    pub catalog_before_matching_run_count: usize,
    pub catalog_after_matching_run_count: usize,
    pub run_identity_confirmed: bool,
    pub no_profile_latest_ambiguity: bool,
    pub result_bound_at: DateTime<Utc>,
    pub result_catalog_lookup_path: String,
    pub result_manifest_path: String,
    pub artifact_manifest_path: String,
    pub run_result_identity_receipt_path: String,
    pub run_scoped_publication_path: String,
    pub result_refs: Vec<WorkbenchBoundResultRef>,
    pub note: String,
}

pub fn record_workbench_result_binding(
    data_dir: &Path,
    workstream_id: &str,
    reservation: &WorkbenchReservation,
    run: &WorkbenchRun,
    pilot_response: &WorkspacePilotResponse,
) -> anyhow::Result<WorkbenchResultBinding> {
    let result_bound_at = Utc::now();
    let binding_id = format!(
        "{}-result-binding-{}",
        sanitize_component(&reservation.session_id),
        result_bound_at.timestamp_millis()
    );
    let record = WorkbenchResultBindingRecord {
        contract_version: WORKBENCH_RESULT_BINDING_VERSION.to_string(),
        binding_id,
        reservation_id: reservation.reservation_id.clone(),
        run_id: run.run_id.clone(),
        workstream_id: reservation.workstream_id.clone(),
        workspace_id: reservation.workspace_id.clone(),
        session_id: reservation.session_id.clone(),
        same_beagle_owned_identity: reservation.same_beagle_owned_identity,
        compute_profile_id: reservation.compute_profile_id.clone(),
        selected_subagent_id: reservation.selected_subagent_id.clone(),
        task_family: reservation.task_family.clone(),
        recipe_kind: reservation.recipe_kind.clone(),
        experiment_id: reservation.experiment_id.clone(),
        submitted_job_id: pilot_response.submitted_job.job_id,
        published_result_job_id: pilot_response.published_result.job_id,
        published_result_run_label: pilot_response.published_result.run_label.clone(),
        published_result_profile_id: pilot_response.published_result.profile_id.clone(),
        resolved_result_lookup_job_id: pilot_response.resolved_result_lookup.job_id,
        artifact_manifest_job_id: pilot_response.artifact_manifest.job_id,
        published_result_manifest_job_id: pilot_response.published_result_manifest.job_id,
        published_result_manifest_key: pilot_response
            .published_result
            .artifact_manifest_key
            .clone(),
        final_job_state: pilot_response
            .final_job
            .state
            .clone()
            .unwrap_or_else(|| "UNKNOWN".to_string()),
        artifact_ready: pilot_response.final_job.artifact_ready.unwrap_or(false),
        result_bound_at,
    };
    write_binding_record(data_dir, &record.workspace_id, &record)?;
    Ok(binding_from_record(workstream_id, &record))
}

pub fn read_workbench_result_binding(
    data_dir: &Path,
    workstream_id: &str,
    workspace_id: &str,
) -> anyhow::Result<Option<WorkbenchResultBinding>> {
    let Some(record) = read_binding_record(data_dir, workspace_id)? else {
        return Ok(None);
    };
    Ok(Some(binding_from_record(workstream_id, &record)))
}

pub fn record_run_result_identity_receipt(
    data_dir: &Path,
    workstream_id: &str,
    reservation: &WorkbenchReservation,
    run: &WorkbenchRun,
    pilot_response: &WorkspacePilotResponse,
) -> anyhow::Result<RunResultIdentityReceipt> {
    let receipt_created_at = Utc::now();
    let record = RunResultIdentityReceiptRecord {
        contract_version: RUN_RESULT_IDENTITY_RECEIPT_VERSION.to_string(),
        receipt_id: format!(
            "{}-run-result-identity-{}",
            sanitize_component(&reservation.session_id),
            receipt_created_at.timestamp_millis()
        ),
        reservation_id: reservation.reservation_id.clone(),
        run_id: run.run_id.clone(),
        workstream_id: reservation.workstream_id.clone(),
        workspace_id: reservation.workspace_id.clone(),
        session_id: reservation.session_id.clone(),
        same_beagle_owned_identity: reservation.same_beagle_owned_identity,
        compute_profile_id: reservation.compute_profile_id.clone(),
        selected_subagent_id: reservation.selected_subagent_id.clone(),
        task_family: reservation.task_family.clone(),
        submitted_job_id: pilot_response.submitted_job.job_id,
        final_job_id: pilot_response.final_job.job_id,
        requested_run_label: pilot_response.requested_run_label.clone(),
        published_result_job_id: pilot_response.published_result.job_id,
        published_result_run_label: pilot_response.published_result.run_label.clone(),
        resolved_result_lookup_job_id: pilot_response.resolved_result_lookup.job_id,
        result_manifest_job_id: pilot_response.published_result_manifest.job_id,
        published_result_manifest_key: pilot_response
            .published_result
            .artifact_manifest_key
            .clone(),
        result_manifest_object_key: pilot_response
            .published_result_manifest
            .manifest_object_key
            .clone(),
        result_lookup_scope: pilot_response.result_lookup_scope.clone(),
        catalog_before_matching_run_count: pilot_response.run_scoped_catalog_before_count,
        catalog_after_matching_run_count: pilot_response.run_scoped_catalog_after_count,
        deterministic_identity_confirmed: pilot_response.submitted_job.job_id
            == pilot_response.final_job.job_id
            && pilot_response.final_job.job_id == pilot_response.published_result.job_id
            && pilot_response.published_result.job_id
                == pilot_response.resolved_result_lookup.job_id
            && pilot_response.requested_run_label == pilot_response.published_result.run_label
            && pilot_response.resolved_result_lookup.run_label
                == pilot_response.published_result.run_label,
        receipt_created_at,
    };
    write_run_result_identity_receipt_record(data_dir, &record.workspace_id, &record)?;
    Ok(run_result_identity_receipt_from_record(workstream_id, &record))
}

pub fn read_run_result_identity_receipt(
    data_dir: &Path,
    workstream_id: &str,
    workspace_id: &str,
) -> anyhow::Result<Option<RunResultIdentityReceipt>> {
    let Some(record) = read_run_result_identity_receipt_record(data_dir, workspace_id)? else {
        return Ok(None);
    };
    Ok(Some(run_result_identity_receipt_from_record(
        workstream_id,
        &record,
    )))
}

pub fn record_run_scoped_publication(
    data_dir: &Path,
    workstream_id: &str,
    reservation: &WorkbenchReservation,
    run: &WorkbenchRun,
    pilot_response: &WorkspacePilotResponse,
) -> anyhow::Result<RunScopedPublication> {
    let published_at = Utc::now();
    let record = RunScopedPublicationRecord {
        contract_version: RUN_SCOPED_PUBLICATION_VERSION.to_string(),
        publication_id: format!(
            "{}-run-scoped-publication-{}",
            sanitize_component(&reservation.session_id),
            published_at.timestamp_millis()
        ),
        reservation_id: reservation.reservation_id.clone(),
        run_id: run.run_id.clone(),
        workstream_id: reservation.workstream_id.clone(),
        workspace_id: reservation.workspace_id.clone(),
        session_id: reservation.session_id.clone(),
        same_beagle_owned_identity: reservation.same_beagle_owned_identity,
        compute_profile_id: reservation.compute_profile_id.clone(),
        selected_subagent_id: reservation.selected_subagent_id.clone(),
        task_family: reservation.task_family.clone(),
        submitted_job_id: pilot_response.submitted_job.job_id,
        requested_run_label: pilot_response.requested_run_label.clone(),
        published_result_job_id: pilot_response.published_result.job_id,
        published_result_run_label: pilot_response.published_result.run_label.clone(),
        published_result_profile_id: pilot_response.published_result.profile_id.clone(),
        final_job_state: pilot_response
            .final_job
            .state
            .clone()
            .unwrap_or_else(|| "UNKNOWN".to_string()),
        result_lookup_scope: pilot_response.result_lookup_scope.clone(),
        catalog_before_matching_run_count: pilot_response.run_scoped_catalog_before_count,
        catalog_after_matching_run_count: pilot_response.run_scoped_catalog_after_count,
        no_profile_latest_ambiguity: pilot_response.run_scoped_catalog_before_count == 0
            && pilot_response.run_scoped_catalog_after_count == 1
            && pilot_response.requested_run_label == pilot_response.published_result.run_label,
        published_result_manifest_key: pilot_response
            .published_result
            .artifact_manifest_key
            .clone(),
        published_at,
    };
    write_run_scoped_publication_record(data_dir, &record.workspace_id, &record)?;
    Ok(run_scoped_publication_from_record(workstream_id, &record))
}

pub fn read_run_scoped_publication(
    data_dir: &Path,
    workstream_id: &str,
    workspace_id: &str,
) -> anyhow::Result<Option<RunScopedPublication>> {
    let Some(record) = read_run_scoped_publication_record(data_dir, workspace_id)? else {
        return Ok(None);
    };
    Ok(Some(run_scoped_publication_from_record(
        workstream_id,
        &record,
    )))
}

pub fn record_deterministic_result_binding(
    data_dir: &Path,
    workstream_id: &str,
    reservation: &WorkbenchReservation,
    run: &WorkbenchRun,
    pilot_response: &WorkspacePilotResponse,
) -> anyhow::Result<DeterministicResultBinding> {
    let result_bound_at = Utc::now();
    let record = DeterministicResultBindingRecord {
        contract_version: DETERMINISTIC_RESULT_BINDING_VERSION.to_string(),
        binding_id: format!(
            "{}-deterministic-binding-{}",
            sanitize_component(&reservation.session_id),
            result_bound_at.timestamp_millis()
        ),
        reservation_id: reservation.reservation_id.clone(),
        run_id: run.run_id.clone(),
        workstream_id: reservation.workstream_id.clone(),
        workspace_id: reservation.workspace_id.clone(),
        session_id: reservation.session_id.clone(),
        same_beagle_owned_identity: reservation.same_beagle_owned_identity,
        compute_profile_id: reservation.compute_profile_id.clone(),
        selected_subagent_id: reservation.selected_subagent_id.clone(),
        task_family: reservation.task_family.clone(),
        submitted_job_id: pilot_response.submitted_job.job_id,
        requested_run_label: pilot_response.requested_run_label.clone(),
        published_result_job_id: pilot_response.published_result.job_id,
        published_result_run_label: pilot_response.published_result.run_label.clone(),
        resolved_result_lookup_job_id: pilot_response.resolved_result_lookup.job_id,
        result_manifest_job_id: pilot_response.published_result_manifest.job_id,
        published_result_manifest_key: pilot_response
            .published_result
            .artifact_manifest_key
            .clone(),
        result_manifest_object_key: pilot_response
            .published_result_manifest
            .manifest_object_key
            .clone(),
        result_lookup_scope: pilot_response.result_lookup_scope.clone(),
        catalog_before_matching_run_count: pilot_response.run_scoped_catalog_before_count,
        catalog_after_matching_run_count: pilot_response.run_scoped_catalog_after_count,
        run_identity_confirmed: pilot_response.submitted_job.job_id
            == pilot_response.published_result.job_id
            && pilot_response.published_result.job_id
                == pilot_response.resolved_result_lookup.job_id
            && pilot_response.requested_run_label == pilot_response.published_result.run_label,
        no_profile_latest_ambiguity: pilot_response.run_scoped_catalog_before_count == 0
            && pilot_response.run_scoped_catalog_after_count == 1,
        result_bound_at,
    };
    write_deterministic_result_binding_record(data_dir, &record.workspace_id, &record)?;
    Ok(deterministic_result_binding_from_record(workstream_id, &record))
}

pub fn read_deterministic_result_binding(
    data_dir: &Path,
    workstream_id: &str,
    workspace_id: &str,
) -> anyhow::Result<Option<DeterministicResultBinding>> {
    let Some(record) = read_deterministic_result_binding_record(data_dir, workspace_id)? else {
        return Ok(None);
    };
    Ok(Some(deterministic_result_binding_from_record(
        workstream_id,
        &record,
    )))
}

fn binding_from_record(
    workstream_id: &str,
    record: &WorkbenchResultBindingRecord,
) -> WorkbenchResultBinding {
    let result_catalog_lookup_path = format!(
        "/api/darwin/hpc/results/{}",
        record.published_result_job_id
    );
    let result_manifest_path = format!(
        "/api/darwin/hpc/results/{}/manifest",
        record.published_result_job_id
    );
    WorkbenchResultBinding {
        phase: WORKBENCH_RESULT_BINDING_PHASE.to_string(),
        contract_kind: WORKBENCH_RESULT_BINDING_KIND.to_string(),
        contract_version: record.contract_version.clone(),
        binding_id: record.binding_id.clone(),
        reservation_id: record.reservation_id.clone(),
        run_id: record.run_id.clone(),
        workstream_id: record.workstream_id.clone(),
        workspace_id: record.workspace_id.clone(),
        session_id: record.session_id.clone(),
        same_beagle_owned_identity: record.same_beagle_owned_identity,
        compute_profile_id: record.compute_profile_id.clone(),
        selected_subagent_id: record.selected_subagent_id.clone(),
        task_family: record.task_family.clone(),
        recipe_kind: record.recipe_kind.clone(),
        experiment_id: record.experiment_id.clone(),
        submitted_job_id: record.submitted_job_id,
        published_result_job_id: record.published_result_job_id,
        final_job_state: record.final_job_state.clone(),
        artifact_ready: record.artifact_ready,
        result_bound_at: record.result_bound_at,
        result_catalog_lookup_path: result_catalog_lookup_path.clone(),
        result_manifest_path: result_manifest_path.clone(),
        workbench_run_path: format!(
            "{}/{}/workbench-run-orchestration",
            WORKBENCH_API_PREFIX, workstream_id
        ),
        collaborative_workbench_path: format!(
            "{}/{}/collaborative-workbench",
            WORKBENCH_API_PREFIX, workstream_id
        ),
        result_refs: vec![
            WorkbenchBoundResultRef {
                ref_id: format!("submitted-job-{}", record.submitted_job_id),
                ref_kind: "submitted-job".to_string(),
                locator: format!("/api/darwin/hpc/jobs/{}", record.submitted_job_id),
                summary: format!(
                    "Submitted bounded workbench run on profile {}",
                    record.compute_profile_id
                ),
            },
            WorkbenchBoundResultRef {
                ref_id: format!("published-result-{}", record.published_result_job_id),
                ref_kind: "published-result".to_string(),
                locator: result_catalog_lookup_path,
                summary: format!(
                    "Published result {} ({})",
                    record.published_result_job_id, record.published_result_run_label
                ),
            },
            WorkbenchBoundResultRef {
                ref_id: format!("manifest-{}", record.published_result_job_id),
                ref_kind: "result-manifest".to_string(),
                locator: result_manifest_path,
                summary: format!(
                    "Resolved manifest {} for published result {}",
                    record.published_result_manifest_key, record.published_result_job_id
                ),
            },
        ],
        note: "B25.3 binds published result refs and execution receipts back into the same Beagle-owned workbench/session envelope instead of leaving them as detached scheduler artifacts.".to_string(),
    }
}

fn run_result_identity_receipt_from_record(
    workstream_id: &str,
    record: &RunResultIdentityReceiptRecord,
) -> RunResultIdentityReceipt {
    RunResultIdentityReceipt {
        phase: RUN_RESULT_IDENTITY_RECEIPT_PHASE.to_string(),
        contract_kind: RUN_RESULT_IDENTITY_RECEIPT_KIND.to_string(),
        contract_version: record.contract_version.clone(),
        receipt_id: record.receipt_id.clone(),
        reservation_id: record.reservation_id.clone(),
        run_id: record.run_id.clone(),
        workstream_id: record.workstream_id.clone(),
        workspace_id: record.workspace_id.clone(),
        session_id: record.session_id.clone(),
        same_beagle_owned_identity: record.same_beagle_owned_identity,
        compute_profile_id: record.compute_profile_id.clone(),
        selected_subagent_id: record.selected_subagent_id.clone(),
        task_family: record.task_family.clone(),
        submitted_job_id: record.submitted_job_id,
        final_job_id: record.final_job_id,
        requested_run_label: record.requested_run_label.clone(),
        published_result_job_id: record.published_result_job_id,
        published_result_run_label: record.published_result_run_label.clone(),
        resolved_result_lookup_job_id: record.resolved_result_lookup_job_id,
        result_manifest_job_id: record.result_manifest_job_id,
        published_result_manifest_key: record.published_result_manifest_key.clone(),
        result_manifest_object_key: record.result_manifest_object_key.clone(),
        result_lookup_scope: record.result_lookup_scope.clone(),
        catalog_before_matching_run_count: record.catalog_before_matching_run_count,
        catalog_after_matching_run_count: record.catalog_after_matching_run_count,
        deterministic_identity_confirmed: record.deterministic_identity_confirmed,
        receipt_created_at: record.receipt_created_at,
        workbench_run_path: format!(
            "{}/{}/workbench-run-orchestration",
            WORKBENCH_API_PREFIX, workstream_id
        ),
        run_scoped_publication_path: format!(
            "{}/{}/run-scoped-publication",
            WORKBENCH_API_PREFIX, workstream_id
        ),
        deterministic_result_binding_path: format!(
            "{}/{}/deterministic-result-binding",
            WORKBENCH_API_PREFIX, workstream_id
        ),
        note: "B25.4 freezes the submitted job, requested run label, published result, and manifest identity into one deterministic per-run receipt so restart recovery cannot drift to profile-latest resolution.".to_string(),
    }
}

fn run_scoped_publication_from_record(
    workstream_id: &str,
    record: &RunScopedPublicationRecord,
) -> RunScopedPublication {
    RunScopedPublication {
        phase: RUN_SCOPED_PUBLICATION_PHASE.to_string(),
        contract_kind: RUN_SCOPED_PUBLICATION_KIND.to_string(),
        contract_version: record.contract_version.clone(),
        publication_id: record.publication_id.clone(),
        reservation_id: record.reservation_id.clone(),
        run_id: record.run_id.clone(),
        workstream_id: record.workstream_id.clone(),
        workspace_id: record.workspace_id.clone(),
        session_id: record.session_id.clone(),
        same_beagle_owned_identity: record.same_beagle_owned_identity,
        compute_profile_id: record.compute_profile_id.clone(),
        selected_subagent_id: record.selected_subagent_id.clone(),
        task_family: record.task_family.clone(),
        submitted_job_id: record.submitted_job_id,
        requested_run_label: record.requested_run_label.clone(),
        published_result_job_id: record.published_result_job_id,
        published_result_run_label: record.published_result_run_label.clone(),
        published_result_profile_id: record.published_result_profile_id.clone(),
        final_job_state: record.final_job_state.clone(),
        publication_state: "published".to_string(),
        result_lookup_scope: record.result_lookup_scope.clone(),
        catalog_before_matching_run_count: record.catalog_before_matching_run_count,
        catalog_after_matching_run_count: record.catalog_after_matching_run_count,
        no_profile_latest_ambiguity: record.no_profile_latest_ambiguity,
        published_result_manifest_key: record.published_result_manifest_key.clone(),
        published_at: record.published_at,
        result_catalog_lookup_path: format!(
            "/api/darwin/hpc/results/{}",
            record.published_result_job_id
        ),
        run_result_identity_receipt_path: format!(
            "{}/{}/run-result-identity-receipt",
            WORKBENCH_API_PREFIX, workstream_id
        ),
        deterministic_result_binding_path: format!(
            "{}/{}/deterministic-result-binding",
            WORKBENCH_API_PREFIX, workstream_id
        ),
        note: "B25.4 resolves publication by profile plus run label and refuses canonical binding if the published result is ambiguous or inherited from a previous profile-latest artifact.".to_string(),
    }
}

fn deterministic_result_binding_from_record(
    workstream_id: &str,
    record: &DeterministicResultBindingRecord,
) -> DeterministicResultBinding {
    let result_catalog_lookup_path = format!(
        "/api/darwin/hpc/results/{}",
        record.published_result_job_id
    );
    let result_manifest_path = format!(
        "/api/darwin/hpc/results/{}/manifest",
        record.published_result_job_id
    );
    let artifact_manifest_path = format!(
        "/api/darwin/hpc/jobs/{}/artifact-manifest",
        record.submitted_job_id
    );
    DeterministicResultBinding {
        phase: DETERMINISTIC_RESULT_BINDING_PHASE.to_string(),
        contract_kind: DETERMINISTIC_RESULT_BINDING_KIND.to_string(),
        contract_version: record.contract_version.clone(),
        binding_id: record.binding_id.clone(),
        reservation_id: record.reservation_id.clone(),
        run_id: record.run_id.clone(),
        workstream_id: record.workstream_id.clone(),
        workspace_id: record.workspace_id.clone(),
        session_id: record.session_id.clone(),
        same_beagle_owned_identity: record.same_beagle_owned_identity,
        compute_profile_id: record.compute_profile_id.clone(),
        selected_subagent_id: record.selected_subagent_id.clone(),
        task_family: record.task_family.clone(),
        submitted_job_id: record.submitted_job_id,
        requested_run_label: record.requested_run_label.clone(),
        published_result_job_id: record.published_result_job_id,
        published_result_run_label: record.published_result_run_label.clone(),
        resolved_result_lookup_job_id: record.resolved_result_lookup_job_id,
        result_manifest_job_id: record.result_manifest_job_id,
        published_result_manifest_key: record.published_result_manifest_key.clone(),
        result_manifest_object_key: record.result_manifest_object_key.clone(),
        result_lookup_scope: record.result_lookup_scope.clone(),
        catalog_before_matching_run_count: record.catalog_before_matching_run_count,
        catalog_after_matching_run_count: record.catalog_after_matching_run_count,
        run_identity_confirmed: record.run_identity_confirmed,
        no_profile_latest_ambiguity: record.no_profile_latest_ambiguity,
        result_bound_at: record.result_bound_at,
        result_catalog_lookup_path: result_catalog_lookup_path.clone(),
        result_manifest_path: result_manifest_path.clone(),
        artifact_manifest_path: artifact_manifest_path.clone(),
        run_result_identity_receipt_path: format!(
            "{}/{}/run-result-identity-receipt",
            WORKBENCH_API_PREFIX, workstream_id
        ),
        run_scoped_publication_path: format!(
            "{}/{}/run-scoped-publication",
            WORKBENCH_API_PREFIX, workstream_id
        ),
        result_refs: vec![
            WorkbenchBoundResultRef {
                ref_id: format!("submitted-job-{}", record.submitted_job_id),
                ref_kind: "submitted-job".to_string(),
                locator: format!("/api/darwin/hpc/jobs/{}", record.submitted_job_id),
                summary: format!(
                    "Submitted bounded workbench run {}",
                    record.requested_run_label
                ),
            },
            WorkbenchBoundResultRef {
                ref_id: format!("published-result-{}", record.published_result_job_id),
                ref_kind: "published-result".to_string(),
                locator: result_catalog_lookup_path,
                summary: format!(
                    "Run-scoped published result {} ({})",
                    record.published_result_job_id, record.published_result_run_label
                ),
            },
            WorkbenchBoundResultRef {
                ref_id: format!("artifact-manifest-{}", record.submitted_job_id),
                ref_kind: "artifact-manifest".to_string(),
                locator: artifact_manifest_path,
                summary: format!(
                    "Artifact manifest for submitted job {}",
                    record.submitted_job_id
                ),
            },
            WorkbenchBoundResultRef {
                ref_id: format!("manifest-{}", record.published_result_job_id),
                ref_kind: "result-manifest".to_string(),
                locator: result_manifest_path,
                summary: format!(
                    "Resolved manifest {} for published result {}",
                    record.published_result_manifest_key, record.published_result_job_id
                ),
            },
        ],
        note: "B25.4 binds result lookup by run identity instead of profile-latest fallback, so the workbench can recover the same published result deterministically after restart.".to_string(),
    }
}

fn binding_records_dir(data_dir: &Path) -> PathBuf {
    workspace_plane_dir(data_dir).join("workbench-result-bindings")
}

fn binding_record_path(data_dir: &Path, workspace_id: &str) -> PathBuf {
    binding_records_dir(data_dir).join(format!("{}.json", sanitize_component(workspace_id)))
}

fn write_binding_record(
    data_dir: &Path,
    workspace_id: &str,
    record: &WorkbenchResultBindingRecord,
) -> anyhow::Result<()> {
    let dir = binding_records_dir(data_dir);
    fs::create_dir_all(&dir)
        .with_context(|| format!("failed to create workbench result binding dir {}", dir.display()))?;
    let path = binding_record_path(data_dir, workspace_id);
    let body = serde_json::to_string_pretty(record)?;
    fs::write(&path, body)
        .with_context(|| format!("failed to write workbench result binding record {}", path.display()))
}

fn read_binding_record(
    data_dir: &Path,
    workspace_id: &str,
) -> anyhow::Result<Option<WorkbenchResultBindingRecord>> {
    let path = binding_record_path(data_dir, workspace_id);
    if !path.exists() {
        return Ok(None);
    }
    let body = fs::read_to_string(&path)
        .with_context(|| format!("failed to read workbench result binding record {}", path.display()))?;
    let record = serde_json::from_str::<WorkbenchResultBindingRecord>(&body).with_context(|| {
        format!(
            "failed to parse workbench result binding record {}",
            path.display()
        )
    })?;
    Ok(Some(record))
}

fn run_result_identity_receipts_dir(data_dir: &Path) -> PathBuf {
    workspace_plane_dir(data_dir).join("run-result-identity-receipts")
}

fn run_result_identity_receipt_path(data_dir: &Path, workspace_id: &str) -> PathBuf {
    run_result_identity_receipts_dir(data_dir)
        .join(format!("{}.json", sanitize_component(workspace_id)))
}

fn write_run_result_identity_receipt_record(
    data_dir: &Path,
    workspace_id: &str,
    record: &RunResultIdentityReceiptRecord,
) -> anyhow::Result<()> {
    let dir = run_result_identity_receipts_dir(data_dir);
    fs::create_dir_all(&dir).with_context(|| {
        format!(
            "failed to create run result identity receipt dir {}",
            dir.display()
        )
    })?;
    let path = run_result_identity_receipt_path(data_dir, workspace_id);
    let body = serde_json::to_string_pretty(record)?;
    fs::write(&path, body).with_context(|| {
        format!(
            "failed to write run result identity receipt record {}",
            path.display()
        )
    })
}

fn read_run_result_identity_receipt_record(
    data_dir: &Path,
    workspace_id: &str,
) -> anyhow::Result<Option<RunResultIdentityReceiptRecord>> {
    let path = run_result_identity_receipt_path(data_dir, workspace_id);
    if !path.exists() {
        return Ok(None);
    }
    let body = fs::read_to_string(&path).with_context(|| {
        format!(
            "failed to read run result identity receipt record {}",
            path.display()
        )
    })?;
    let record = serde_json::from_str::<RunResultIdentityReceiptRecord>(&body).with_context(|| {
        format!(
            "failed to parse run result identity receipt record {}",
            path.display()
        )
    })?;
    Ok(Some(record))
}

fn run_scoped_publications_dir(data_dir: &Path) -> PathBuf {
    workspace_plane_dir(data_dir).join("run-scoped-publications")
}

fn run_scoped_publication_path(data_dir: &Path, workspace_id: &str) -> PathBuf {
    run_scoped_publications_dir(data_dir).join(format!("{}.json", sanitize_component(workspace_id)))
}

fn write_run_scoped_publication_record(
    data_dir: &Path,
    workspace_id: &str,
    record: &RunScopedPublicationRecord,
) -> anyhow::Result<()> {
    let dir = run_scoped_publications_dir(data_dir);
    fs::create_dir_all(&dir).with_context(|| {
        format!("failed to create run scoped publication dir {}", dir.display())
    })?;
    let path = run_scoped_publication_path(data_dir, workspace_id);
    let body = serde_json::to_string_pretty(record)?;
    fs::write(&path, body).with_context(|| {
        format!(
            "failed to write run scoped publication record {}",
            path.display()
        )
    })
}

fn read_run_scoped_publication_record(
    data_dir: &Path,
    workspace_id: &str,
) -> anyhow::Result<Option<RunScopedPublicationRecord>> {
    let path = run_scoped_publication_path(data_dir, workspace_id);
    if !path.exists() {
        return Ok(None);
    }
    let body = fs::read_to_string(&path).with_context(|| {
        format!("failed to read run scoped publication record {}", path.display())
    })?;
    let record = serde_json::from_str::<RunScopedPublicationRecord>(&body).with_context(|| {
        format!(
            "failed to parse run scoped publication record {}",
            path.display()
        )
    })?;
    Ok(Some(record))
}

fn deterministic_result_bindings_dir(data_dir: &Path) -> PathBuf {
    workspace_plane_dir(data_dir).join("deterministic-result-bindings")
}

fn deterministic_result_binding_path(data_dir: &Path, workspace_id: &str) -> PathBuf {
    deterministic_result_bindings_dir(data_dir)
        .join(format!("{}.json", sanitize_component(workspace_id)))
}

fn write_deterministic_result_binding_record(
    data_dir: &Path,
    workspace_id: &str,
    record: &DeterministicResultBindingRecord,
) -> anyhow::Result<()> {
    let dir = deterministic_result_bindings_dir(data_dir);
    fs::create_dir_all(&dir).with_context(|| {
        format!(
            "failed to create deterministic result binding dir {}",
            dir.display()
        )
    })?;
    let path = deterministic_result_binding_path(data_dir, workspace_id);
    let body = serde_json::to_string_pretty(record)?;
    fs::write(&path, body).with_context(|| {
        format!(
            "failed to write deterministic result binding record {}",
            path.display()
        )
    })
}

fn read_deterministic_result_binding_record(
    data_dir: &Path,
    workspace_id: &str,
) -> anyhow::Result<Option<DeterministicResultBindingRecord>> {
    let path = deterministic_result_binding_path(data_dir, workspace_id);
    if !path.exists() {
        return Ok(None);
    }
    let body = fs::read_to_string(&path).with_context(|| {
        format!(
            "failed to read deterministic result binding record {}",
            path.display()
        )
    })?;
    let record = serde_json::from_str::<DeterministicResultBindingRecord>(&body).with_context(
        || {
            format!(
                "failed to parse deterministic result binding record {}",
                path.display()
            )
        },
    )?;
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

#[cfg(test)]
mod tests {
    use super::*;
    use chrono::Utc;

    #[test]
    fn deterministic_result_binding_keeps_run_scoped_identity_fields_aligned() {
        let record = DeterministicResultBindingRecord {
            contract_version: DETERMINISTIC_RESULT_BINDING_VERSION.to_string(),
            binding_id: "binding-1".to_string(),
            reservation_id: "reservation-1".to_string(),
            run_id: "run-1".to_string(),
            workstream_id: "beagle-darwin-hpc-governance".to_string(),
            workspace_id: "beagle-cluster-pilot".to_string(),
            session_id: "ws-cluster-workspace-habitat".to_string(),
            same_beagle_owned_identity: true,
            compute_profile_id: "cpu-short-v1".to_string(),
            selected_subagent_id: "experiments".to_string(),
            task_family: "analysis".to_string(),
            submitted_job_id: 101,
            requested_run_label: "b254-test".to_string(),
            published_result_job_id: 101,
            published_result_run_label: "b254-test".to_string(),
            resolved_result_lookup_job_id: 101,
            result_manifest_job_id: 101,
            published_result_manifest_key: "hpc/cpu-short-v1/101/b254-test/artifact-manifest.json"
                .to_string(),
            result_manifest_object_key:
                "hpc/cpu-short-v1/101/b254-test/object-result-manifest.json".to_string(),
            result_lookup_scope: "profile-and-run-label".to_string(),
            catalog_before_matching_run_count: 0,
            catalog_after_matching_run_count: 1,
            run_identity_confirmed: true,
            no_profile_latest_ambiguity: true,
            result_bound_at: Utc::now(),
        };

        let binding = deterministic_result_binding_from_record(
            "beagle-darwin-hpc-governance",
            &record,
        );

        assert_eq!(binding.submitted_job_id, binding.published_result_job_id);
        assert_eq!(binding.requested_run_label, binding.published_result_run_label);
        assert!(binding.run_identity_confirmed);
        assert!(binding.no_profile_latest_ambiguity);
        assert_eq!(binding.result_refs.len(), 4);
    }
}
