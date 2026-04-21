use crate::collaborative_workbench::CollaborativeComputeExperimentWorkbenchBundle;
use crate::code_provenance::{
    capture_code_provenance, CodeProvenance, CodeProvenanceBundle,
    CodeProvenanceCaptureRequest,
};
use crate::object_results::{JobArtifactManifest, ObjectResultManifest};
use crate::result_catalog::ResultCatalogEntry;
use crate::source_fingerprint::SourceFingerprint;
use crate::workbench_reservation::WorkbenchReservation;
use crate::workbench_result_binding::{
    DeterministicResultBinding, WorkbenchBoundResultRef, WorkbenchResultBinding,
};
use crate::workbench_run::WorkbenchRun;
use crate::workspace_snapshot::{dirty_state_to_bool, WorkspaceSnapshot};
use crate::workspace_plane::{workspace_plane_dir, WorkspacePilotResponse};
use anyhow::Context;
use chrono::{DateTime, Utc};
use serde::{Deserialize, Serialize};
use sha2::{Digest, Sha256};
use std::fs;
use std::path::{Path, PathBuf};

const RUN_CAPSULE_PHASE: &str = "B25.6";
const RUN_CAPSULE_KIND: &str = "run-capsule";
const RUN_CAPSULE_VERSION: &str = "beagle-run-capsule-v2";
const REPLAY_REQUEST_PHASE: &str = "B25.7";
const REPLAY_REQUEST_KIND: &str = "replay-request";
const REPLAY_REQUEST_VERSION: &str = "beagle-replay-request-v3";
const WORKBENCH_API_PREFIX: &str = "/api/darwin/workstreams";

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct RunCapsuleGitSnapshot {
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub repo_root: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub branch: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub commit: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub tree_ish: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub patch_ref: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub dirty: Option<bool>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct RunCapsuleEnvironmentSnapshot {
    pub scheduler_kind: String,
    pub submit_mode: String,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub image_reference: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub image_digest: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub node_list: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub partition: Option<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct RunCapsuleInputManifest {
    pub requested_by: String,
    pub requester_role_id: String,
    pub intent_text: String,
    pub requested_run_label: String,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub retrieval_query_text: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub retrieval_query_type: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub retrieval_mode: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub dense_backend: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub sparse_backend: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub compiler_profile_id: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub graphrag_query_mode: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub temporal_truth_view: Option<String>,
    #[serde(default)]
    pub top_memory_ids: Vec<String>,
    pub memory_hit_count: usize,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct RunCapsule {
    pub phase: String,
    pub contract_kind: String,
    pub contract_version: String,
    pub capsule_id: String,
    pub captured_at: DateTime<Utc>,
    pub workstream_id: String,
    pub workspace_id: String,
    pub session_id: String,
    pub same_beagle_owned_identity: bool,
    pub run_id: String,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub parent_run_id: Option<String>,
    pub reservation_id: String,
    pub submitted_job_id: u64,
    pub published_result_job_id: u64,
    pub run_label: String,
    pub selected_subagent_id: String,
    pub task_family: String,
    pub compute_profile_id: String,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub recipe_kind: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub experiment_id: Option<String>,
    pub canonical_repo: String,
    pub canonical_branch: String,
    pub canonical_track: String,
    pub git: RunCapsuleGitSnapshot,
    pub environment: RunCapsuleEnvironmentSnapshot,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub retrieval_query_type: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub retrieval_profile: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub compiler_profile_id: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub graphrag_query_mode: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub temporal_truth_view: Option<String>,
    pub config_fingerprint: String,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub code_provenance: Option<CodeProvenance>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub workspace_snapshot: Option<WorkspaceSnapshot>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub source_fingerprint: Option<SourceFingerprint>,
    pub input_manifest: RunCapsuleInputManifest,
    pub published_result: ResultCatalogEntry,
    pub artifact_manifest: JobArtifactManifest,
    pub published_result_manifest: ObjectResultManifest,
    pub result_refs: Vec<WorkbenchBoundResultRef>,
    pub deterministic_result_lookup_scope: String,
    pub deterministic_identity_confirmed: bool,
    pub note: String,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ReplayRequest {
    pub phase: String,
    pub contract_kind: String,
    pub contract_version: String,
    pub replay_request_id: String,
    pub source_run_id: String,
    pub source_submitted_job_id: u64,
    pub source_run_label: String,
    pub source_intent_text: String,
    pub workstream_id: String,
    pub workspace_id: String,
    pub session_id: String,
    pub same_beagle_owned_identity: bool,
    pub replay_mode: String,
    pub selected_subagent_id: String,
    pub task_family: String,
    pub compute_profile_id: String,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub recipe_kind: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub experiment_id: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub retrieval_query_type: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub compiler_profile_id: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub graphrag_query_mode: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub temporal_truth_view: Option<String>,
    pub config_fingerprint: String,
    pub result_manifest_key: String,
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
    pub replay_execution_path: String,
    pub workbench_run_path: String,
    pub deterministic_result_binding_path: String,
    pub note: String,
}

pub fn record_run_capsule(
    data_dir: &Path,
    workbench_bundle: &CollaborativeComputeExperimentWorkbenchBundle,
    reservation: &WorkbenchReservation,
    run: &WorkbenchRun,
    result_binding: &WorkbenchResultBinding,
    deterministic_result_binding: &DeterministicResultBinding,
    pilot_response: &WorkspacePilotResponse,
    code_provenance_capture: Option<&CodeProvenanceCaptureRequest>,
) -> anyhow::Result<RunCapsule> {
    let captured_at = Utc::now();
    let parent_run_id = read_latest_run_capsule(data_dir, &reservation.workspace_id)?
        .map(|capsule| capsule.run_id);
    let environment = environment_snapshot(run, pilot_response);
    let provenance = capture_code_provenance(
        &crate::code_provenance::CodeProvenanceContext {
            workstream_id: &reservation.workstream_id,
            workspace_id: &reservation.workspace_id,
            session_id: &reservation.session_id,
            same_beagle_owned_identity: reservation.same_beagle_owned_identity,
            selected_subagent_id: &run.selected_subagent_id,
            workspace_root: &workbench_bundle.workbench_session.workspace_root,
            run_label: &run.run_label,
            submitted_job_id: run.submitted_job_id,
            image_reference: environment.image_reference.clone(),
            image_digest: environment.image_digest.clone(),
            artifact_manifest_key: Some(pilot_response.published_result.artifact_manifest_key.clone()),
        },
        code_provenance_capture,
    )?;
    let git = git_snapshot_from_provenance(&provenance);
    let input_manifest = input_manifest(workbench_bundle, reservation, pilot_response);
    let config_fingerprint = config_fingerprint(
        reservation,
        run,
        workbench_bundle,
        &provenance,
        &environment,
    )?;
    let capsule = RunCapsule {
        phase: RUN_CAPSULE_PHASE.to_string(),
        contract_kind: RUN_CAPSULE_KIND.to_string(),
        contract_version: RUN_CAPSULE_VERSION.to_string(),
        capsule_id: format!(
            "{}-run-capsule-{}",
            sanitize_component(&reservation.session_id),
            captured_at.timestamp_millis()
        ),
        captured_at,
        workstream_id: reservation.workstream_id.clone(),
        workspace_id: reservation.workspace_id.clone(),
        session_id: reservation.session_id.clone(),
        same_beagle_owned_identity: reservation.same_beagle_owned_identity,
        run_id: run.run_id.clone(),
        parent_run_id,
        reservation_id: reservation.reservation_id.clone(),
        submitted_job_id: run.submitted_job_id,
        published_result_job_id: run.published_result_job_id,
        run_label: run.run_label.clone(),
        selected_subagent_id: run.selected_subagent_id.clone(),
        task_family: run.task_family.clone(),
        compute_profile_id: run.compute_profile_id.clone(),
        recipe_kind: run.recipe_kind.clone(),
        experiment_id: run.experiment_id.clone(),
        canonical_repo: pilot_response.canonical_repo.clone(),
        canonical_branch: pilot_response.canonical_branch.clone(),
        canonical_track: pilot_response.canonical_track.clone(),
        git,
        environment,
        retrieval_query_type: workbench_bundle.workbench_run.retrieval_query_type.clone(),
        retrieval_profile: workbench_bundle
            .workbench_session
            .memory_context
            .retrieval_mode
            .clone(),
        compiler_profile_id: None,
        graphrag_query_mode: workbench_bundle.workbench_run.graphrag_query_mode.clone(),
        temporal_truth_view: workbench_bundle.workbench_run.temporal_truth_view.clone(),
        config_fingerprint,
        code_provenance: Some(provenance.code_provenance),
        workspace_snapshot: Some(provenance.workspace_snapshot),
        source_fingerprint: Some(provenance.source_fingerprint),
        input_manifest,
        published_result: pilot_response.published_result.clone(),
        artifact_manifest: pilot_response.artifact_manifest.clone(),
        published_result_manifest: pilot_response.published_result_manifest.clone(),
        result_refs: result_binding.result_refs.clone(),
        deterministic_result_lookup_scope: deterministic_result_binding
            .result_lookup_scope
            .clone(),
        deterministic_identity_confirmed: deterministic_result_binding.run_identity_confirmed,
        note: "B25.6 freezes one replay-grade run capsule with Beagle-owned identity, deterministic result linkage, and Git-aware code provenance bound to the same run.".to_string(),
    };
    write_run_capsule(data_dir, &capsule)?;
    Ok(capsule)
}

pub fn read_latest_run_capsule(
    data_dir: &Path,
    workspace_id: &str,
) -> anyhow::Result<Option<RunCapsule>> {
    let capsules = read_all_run_capsules(data_dir, workspace_id)?;
    Ok(capsules.into_iter().max_by_key(|capsule| capsule.captured_at))
}

pub fn read_prior_run_capsule(
    data_dir: &Path,
    workspace_id: &str,
) -> anyhow::Result<Option<RunCapsule>> {
    let latest = match read_latest_run_capsule(data_dir, workspace_id)? {
        Some(capsule) => capsule,
        None => return Ok(None),
    };
    if let Some(parent_run_id) = latest.parent_run_id.as_deref() {
        if let Some(parent) = read_run_capsule_by_run_id(data_dir, workspace_id, parent_run_id)? {
            return Ok(Some(parent));
        }
    }

    let mut capsules = read_all_run_capsules(data_dir, workspace_id)?;
    capsules.sort_by_key(|capsule| capsule.captured_at);
    if capsules.len() < 2 {
        return Ok(None);
    }
    Ok(capsules.into_iter().rev().nth(1))
}

pub fn read_run_capsule_by_run_id(
    data_dir: &Path,
    workspace_id: &str,
    run_id: &str,
) -> anyhow::Result<Option<RunCapsule>> {
    let path = run_capsule_path(data_dir, workspace_id, run_id);
    if !path.exists() {
        return Ok(None);
    }
    let body = fs::read_to_string(&path)
        .with_context(|| format!("failed to read run capsule {}", path.display()))?;
    let capsule = serde_json::from_str::<RunCapsule>(&body)
        .with_context(|| format!("failed to parse run capsule {}", path.display()))?;
    Ok(Some(capsule))
}

pub fn read_replay_request(
    data_dir: &Path,
    workstream_id: &str,
    workspace_id: &str,
) -> anyhow::Result<Option<ReplayRequest>> {
    let Some(capsule) = read_latest_run_capsule(data_dir, workspace_id)? else {
        return Ok(None);
    };
    Ok(Some(replay_request_from_capsule(workstream_id, &capsule)))
}

pub fn read_code_provenance(
    data_dir: &Path,
    workspace_id: &str,
) -> anyhow::Result<Option<CodeProvenance>> {
    Ok(read_latest_run_capsule(data_dir, workspace_id)?
        .and_then(|capsule| capsule.code_provenance))
}

pub fn read_workspace_snapshot(
    data_dir: &Path,
    workspace_id: &str,
) -> anyhow::Result<Option<WorkspaceSnapshot>> {
    Ok(read_latest_run_capsule(data_dir, workspace_id)?
        .and_then(|capsule| capsule.workspace_snapshot))
}

pub fn read_source_fingerprint(
    data_dir: &Path,
    workspace_id: &str,
) -> anyhow::Result<Option<SourceFingerprint>> {
    Ok(read_latest_run_capsule(data_dir, workspace_id)?
        .and_then(|capsule| capsule.source_fingerprint))
}

fn replay_request_from_capsule(workstream_id: &str, capsule: &RunCapsule) -> ReplayRequest {
    ReplayRequest {
        phase: REPLAY_REQUEST_PHASE.to_string(),
        contract_kind: REPLAY_REQUEST_KIND.to_string(),
        contract_version: REPLAY_REQUEST_VERSION.to_string(),
        replay_request_id: format!("replay-{}", capsule.run_id),
        source_run_id: capsule.run_id.clone(),
        source_submitted_job_id: capsule.submitted_job_id,
        source_run_label: capsule.run_label.clone(),
        source_intent_text: capsule.input_manifest.intent_text.clone(),
        workstream_id: capsule.workstream_id.clone(),
        workspace_id: capsule.workspace_id.clone(),
        session_id: capsule.session_id.clone(),
        same_beagle_owned_identity: capsule.same_beagle_owned_identity,
        replay_mode: "bounded-workbench-replay".to_string(),
        selected_subagent_id: capsule.selected_subagent_id.clone(),
        task_family: capsule.task_family.clone(),
        compute_profile_id: capsule.compute_profile_id.clone(),
        recipe_kind: capsule.recipe_kind.clone(),
        experiment_id: capsule.experiment_id.clone(),
        retrieval_query_type: capsule.retrieval_query_type.clone(),
        compiler_profile_id: capsule.compiler_profile_id.clone(),
        graphrag_query_mode: capsule.graphrag_query_mode.clone(),
        temporal_truth_view: capsule.temporal_truth_view.clone(),
        config_fingerprint: capsule.config_fingerprint.clone(),
        result_manifest_key: capsule.published_result.artifact_manifest_key.clone(),
        source_branch: capsule.git.branch.clone(),
        source_commit: capsule.git.commit.clone(),
        source_tree_ish: capsule.git.tree_ish.clone(),
        source_dirty_state: capsule
            .code_provenance
            .as_ref()
            .map(|provenance| provenance.dirty_state.clone())
            .unwrap_or_else(|| "unknown".to_string()),
        source_patch_ref: capsule.git.patch_ref.clone(),
        source_source_fingerprint: capsule
            .source_fingerprint
            .as_ref()
            .map(|fingerprint| fingerprint.source_fingerprint.clone())
            .or_else(|| {
                capsule
                    .code_provenance
                    .as_ref()
                    .map(|provenance| provenance.source_fingerprint.clone())
            }),
        replay_execution_path: format!(
            "{}/{}/replay-execution",
            WORKBENCH_API_PREFIX, workstream_id
        ),
        workbench_run_path: format!(
            "{}/{}/workbench-run-orchestration",
            WORKBENCH_API_PREFIX, workstream_id
        ),
        deterministic_result_binding_path: format!(
            "{}/{}/deterministic-result-binding",
            WORKBENCH_API_PREFIX, workstream_id
        ),
        note: "B25.7 turns the latest run capsule into a bounded replay/fork request that carries deterministic result linkage plus Git-aware code provenance without creating a second execution plane.".to_string(),
    }
}

fn write_run_capsule(data_dir: &Path, capsule: &RunCapsule) -> anyhow::Result<()> {
    let dir = run_capsules_dir(data_dir, &capsule.workspace_id);
    fs::create_dir_all(&dir)
        .with_context(|| format!("failed to create run capsule dir {}", dir.display()))?;
    let path = run_capsule_path(data_dir, &capsule.workspace_id, &capsule.run_id);
    let body = serde_json::to_string_pretty(capsule)?;
    fs::write(&path, body)
        .with_context(|| format!("failed to write run capsule {}", path.display()))
}

fn read_all_run_capsules(data_dir: &Path, workspace_id: &str) -> anyhow::Result<Vec<RunCapsule>> {
    let dir = run_capsules_dir(data_dir, workspace_id);
    if !dir.exists() {
        return Ok(Vec::new());
    }
    let mut capsules = Vec::new();
    for entry in fs::read_dir(&dir)
        .with_context(|| format!("failed to read run capsule dir {}", dir.display()))?
    {
        let entry = entry?;
        let path = entry.path();
        if path.extension().and_then(|value| value.to_str()) != Some("json") {
            continue;
        }
        let body = fs::read_to_string(&path)
            .with_context(|| format!("failed to read run capsule {}", path.display()))?;
        let capsule = serde_json::from_str::<RunCapsule>(&body)
            .with_context(|| format!("failed to parse run capsule {}", path.display()))?;
        capsules.push(capsule);
    }
    Ok(capsules)
}

fn run_capsules_dir(data_dir: &Path, workspace_id: &str) -> PathBuf {
    workspace_plane_dir(data_dir)
        .join("run-capsules")
        .join(sanitize_component(workspace_id))
}

fn run_capsule_path(data_dir: &Path, workspace_id: &str, run_id: &str) -> PathBuf {
    run_capsules_dir(data_dir, workspace_id).join(format!("{}.json", sanitize_component(run_id)))
}

fn environment_snapshot(
    run: &WorkbenchRun,
    pilot_response: &WorkspacePilotResponse,
) -> RunCapsuleEnvironmentSnapshot {
    let image_reference = std::env::var("BEAGLE_CORE_IMAGE_REF")
        .ok()
        .or_else(|| std::env::var("IMAGE_REF").ok())
        .filter(|value| !value.trim().is_empty());
    let image_digest = image_reference
        .as_deref()
        .and_then(|value| value.split("@sha256:").nth(1))
        .map(|digest| format!("sha256:{digest}"));
    RunCapsuleEnvironmentSnapshot {
        scheduler_kind: run.scheduler_kind.clone(),
        submit_mode: run.submit_mode.clone(),
        image_reference,
        image_digest,
        node_list: pilot_response.final_job.node_list.clone(),
        partition: pilot_response.final_job.partition.clone(),
    }
}

fn input_manifest(
    workbench_bundle: &CollaborativeComputeExperimentWorkbenchBundle,
    reservation: &WorkbenchReservation,
    pilot_response: &WorkspacePilotResponse,
) -> RunCapsuleInputManifest {
    RunCapsuleInputManifest {
        requested_by: reservation.requested_by.clone(),
        requester_role_id: reservation.requester_role_id.clone(),
        intent_text: reservation.intent_text.clone(),
        requested_run_label: pilot_response.requested_run_label.clone(),
        retrieval_query_text: workbench_bundle
            .workbench_session
            .memory_context
            .query_text
            .clone(),
        retrieval_query_type: workbench_bundle
            .workbench_run
            .retrieval_query_type
            .clone(),
        retrieval_mode: workbench_bundle
            .workbench_session
            .memory_context
            .retrieval_mode
            .clone(),
        dense_backend: workbench_bundle
            .workbench_session
            .memory_context
            .dense_backend
            .clone(),
        sparse_backend: workbench_bundle
            .workbench_session
            .memory_context
            .sparse_backend
            .clone(),
        compiler_profile_id: None,
        graphrag_query_mode: workbench_bundle.workbench_run.graphrag_query_mode.clone(),
        temporal_truth_view: workbench_bundle.workbench_run.temporal_truth_view.clone(),
        top_memory_ids: workbench_bundle
            .workbench_session
            .memory_context
            .top_memory_ids
            .clone(),
        memory_hit_count: workbench_bundle.workbench_session.memory_context.memory_hit_count,
    }
}

fn config_fingerprint(
    reservation: &WorkbenchReservation,
    run: &WorkbenchRun,
    workbench_bundle: &CollaborativeComputeExperimentWorkbenchBundle,
    provenance: &CodeProvenanceBundle,
    environment: &RunCapsuleEnvironmentSnapshot,
) -> anyhow::Result<String> {
    let payload = serde_json::json!({
        "requested_by": reservation.requested_by,
        "requester_role_id": reservation.requester_role_id,
        "selected_subagent_id": run.selected_subagent_id,
        "task_family": run.task_family,
        "compute_profile_id": run.compute_profile_id,
        "recipe_kind": run.recipe_kind,
        "experiment_id": run.experiment_id,
        "retrieval_query_type": workbench_bundle.workbench_run.retrieval_query_type,
        "retrieval_mode": workbench_bundle.workbench_session.memory_context.retrieval_mode,
        "graphrag_query_mode": workbench_bundle.workbench_run.graphrag_query_mode,
        "temporal_truth_view": workbench_bundle.workbench_run.temporal_truth_view,
        "canonical_repo": reservation.workstream_id,
        "repo_root": provenance.code_provenance.repo_root,
        "git_branch": provenance.code_provenance.branch,
        "git_commit": provenance.code_provenance.commit,
        "tree_ish": provenance.code_provenance.tree_ish,
        "dirty_state": provenance.code_provenance.dirty_state,
        "patch_ref": provenance.code_provenance.patch_ref,
        "source_fingerprint": provenance.code_provenance.source_fingerprint,
        "lockfile_fingerprints": provenance.code_provenance.lockfile_fingerprints,
        "scheduler_kind": environment.scheduler_kind,
        "submit_mode": environment.submit_mode,
        "image_reference": environment.image_reference,
        "image_digest": environment.image_digest
    });
    let normalized = serde_json::to_vec(&payload)?;
    let mut hasher = Sha256::new();
    hasher.update(normalized);
    Ok(format!("{:x}", hasher.finalize()))
}

fn git_snapshot_from_provenance(provenance: &CodeProvenanceBundle) -> RunCapsuleGitSnapshot {
    RunCapsuleGitSnapshot {
        repo_root: provenance.code_provenance.repo_root.clone(),
        branch: provenance.code_provenance.branch.clone(),
        commit: provenance.code_provenance.commit.clone(),
        tree_ish: provenance.code_provenance.tree_ish.clone(),
        patch_ref: provenance.code_provenance.patch_ref.clone(),
        dirty: dirty_state_to_bool(&provenance.code_provenance.dirty_state),
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
