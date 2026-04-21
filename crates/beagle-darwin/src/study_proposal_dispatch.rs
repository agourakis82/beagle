use crate::code_provenance::CodeProvenanceCaptureRequest;
use crate::collaborative_workbench::CollaborativeComputeExperimentWorkbenchBundle;
use crate::result_catalog::DarwinHpcGatewayClient;
use crate::study_continuation::{
    build_study_continuation_state, build_study_run_update, read_study_continuation_state,
    read_study_run_update, write_study_continuation_state, write_study_run_update,
    StudyContinuationState, StudyRunUpdate,
};
use crate::study_decision::{ensure_study_decision_engine, StudyDecisionEngineBundle, StudyEvidenceRef};
use crate::study_registry::{
    ensure_study_registry_sweep, StudyRegistrySweepBundle,
};
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

pub const STUDY_PROPOSAL_DISPATCH_PHASE: &str = "B26.3";
pub const STUDY_PROPOSAL_DISPATCH_KIND: &str = "study-proposal-dispatch";
pub const STUDY_PROPOSAL_DISPATCH_VERSION: &str = "beagle-study-proposal-dispatch-v1";

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
pub struct StudyProposalDispatch {
    pub phase: String,
    pub contract_kind: String,
    pub contract_version: String,
    pub dispatch_id: String,
    pub proposal_id: String,
    pub study_decision_id: String,
    pub next_run_proposal_id: String,
    pub study_id: String,
    pub workstream_id: String,
    pub workspace_id: String,
    pub session_id: String,
    pub same_beagle_owned_identity: bool,
    pub proposal_state: String,
    pub approved_by: String,
    pub approved_at: DateTime<Utc>,
    pub dispatch_state: String,
    pub dispatched_at: DateTime<Utc>,
    pub study_state: String,
    pub requested_by: String,
    pub requester_role_id: String,
    pub selected_subagent_id: String,
    pub task_family: String,
    pub approved_run_label: String,
    pub approved_variant_id: String,
    pub approved_variant_label: String,
    pub approved_compute_profile_id: String,
    pub approved_recipe_kind: Option<String>,
    pub approved_experiment_id: Option<String>,
    pub approved_replay_mode: Option<String>,
    pub source_run_id: String,
    pub reservation_id: String,
    pub run_id: String,
    pub submitted_job_id: u64,
    pub published_result_job_id: u64,
    pub result_binding_id: String,
    pub run_result_identity_receipt_id: String,
    pub run_scoped_publication_id: String,
    pub deterministic_result_binding_id: String,
    pub study_registry_id: String,
    pub study_dag_id: String,
    pub study_sweep_id: String,
    pub comparative_result_summary_id: String,
    pub operator_review_required: bool,
    pub evidence_refs: Vec<StudyEvidenceRef>,
    pub note: String,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct StudyProposalDispatchBundle {
    pub status: String,
    pub phase: String,
    pub study_registry_sweep_before: StudyRegistrySweepBundle,
    pub study_decision_engine_before: StudyDecisionEngineBundle,
    pub study_proposal_dispatch: StudyProposalDispatch,
    pub run_orchestration: WorkbenchRunOrchestrationBundle,
    pub study_registry_sweep_after: StudyRegistrySweepBundle,
    pub study_decision_engine_after: StudyDecisionEngineBundle,
    pub study_run_update: StudyRunUpdate,
    pub study_continuation_state: StudyContinuationState,
}

#[derive(Debug, Clone)]
pub struct StudyProposalDispatchRequest<'a> {
    pub approved_by: &'a str,
    pub dispatch_note: Option<&'a str>,
    pub proposed_run_label_override: Option<&'a str>,
    pub proposed_compute_profile_id_override: Option<&'a str>,
}

pub async fn ensure_study_proposal_dispatch(
    data_dir: &Path,
    cfg: &beagle_config::BeagleConfig,
    gateway: &DarwinHpcGatewayClient,
    bridge: &ToolBridge,
    detail: &WorkstreamControlRoomDetailResponse,
    workbench_bundle: &CollaborativeComputeExperimentWorkbenchBundle,
    workstream_id: &str,
    request: &StudyProposalDispatchRequest<'_>,
) -> anyhow::Result<StudyProposalDispatchBundle> {
    let workspace_id = workbench_bundle.workbench_session.workspace_id.as_str();
    let study_registry_sweep_before = ensure_study_registry_sweep(data_dir, workstream_id, workspace_id)
        .map_err(|error| anyhow!("failed to load study registry sweep: {}", error))?;
    let study_decision_engine_before =
        ensure_study_decision_engine(data_dir, workstream_id, workspace_id)
            .map_err(|error| anyhow!("failed to load study decision engine: {}", error))?;

    validate_identity(
        workstream_id,
        workspace_id,
        &study_registry_sweep_before,
        &study_decision_engine_before,
    )?;

    if let Some(existing_state) = read_study_continuation_state(data_dir, workspace_id)? {
        if existing_state.study_id == study_registry_sweep_before.study_registry.study_id
            && existing_state.proposal_id == study_decision_engine_before.next_run_proposal.proposal_id
            && existing_state.study_state == "study-updated"
        {
            let Some(existing_dispatch) = read_study_proposal_dispatch(data_dir, workspace_id)? else {
                return Err(anyhow!("study continuation state exists without proposal dispatch"));
            };
            let Some(existing_update) = read_study_run_update(data_dir, workspace_id)? else {
                return Err(anyhow!("study continuation state exists without run update"));
            };
            let study_registry_sweep_after = ensure_study_registry_sweep(
                data_dir,
                workstream_id,
                workspace_id,
            )?;
            let study_decision_engine_after =
                ensure_study_decision_engine(data_dir, workstream_id, workspace_id)?;
            return Ok(StudyProposalDispatchBundle {
                status: "ok".to_string(),
                phase: STUDY_PROPOSAL_DISPATCH_PHASE.to_string(),
                study_registry_sweep_before,
                study_decision_engine_before,
                study_proposal_dispatch: existing_dispatch,
                run_orchestration: read_run_orchestration_for_dispatch(
                    data_dir,
                    workbench_bundle,
                    workspace_id,
                    &existing_update.dispatched_run_id,
                )?,
                study_registry_sweep_after,
                study_decision_engine_after,
                study_run_update: existing_update,
                study_continuation_state: existing_state,
            });
        }
    }

    let proposal = &study_decision_engine_before.next_run_proposal;
    let source_run = study_registry_sweep_before
        .study_registry
        .runs
        .iter()
        .find(|run| run.run_id == proposal.proposed_source_run_id)
        .or_else(|| {
            study_registry_sweep_before
                .study_registry
                .runs
                .iter()
                .find(|run| run.run_id == study_registry_sweep_before.study_registry.baseline_run_id)
        })
        .ok_or_else(|| {
            anyhow!(
                "unable to locate source run for proposal {}",
                proposal.proposal_id
            )
        })?;

    let approved_compute_profile_id = request
        .proposed_compute_profile_id_override
        .map(normalize_selector)
        .filter(|value| !value.is_empty())
        .unwrap_or_else(|| proposal.proposed_compute_profile_id.clone());
    let approved_run_label = request
        .proposed_run_label_override
        .map(normalize_sentence)
        .filter(|value| !value.is_empty())
        .unwrap_or_else(|| proposal.proposed_run_label.clone());
    let dispatch_note = request.dispatch_note.map(normalize_sentence).filter(|value| !value.is_empty()).unwrap_or_else(|| {
        format!(
            "Dispatch the approved next-run proposal {} as a bounded continuation of study {}.",
            proposal.proposal_id, study_registry_sweep_before.study_registry.study_id
        )
    });
    let requested_by = normalize_sentence(request.approved_by);
    if requested_by.is_empty() {
        return Err(anyhow!("approved_by must not be empty"));
    }

    let intent_text = format!(
        "Continue study {} from proposal {}",
        study_registry_sweep_before.study_registry.study_id, proposal.proposal_id
    );
    let code_provenance_capture_default = CodeProvenanceCaptureRequest::default();
    let run_dispatch = WorkbenchRunDispatchRequest {
        requested_by: &requested_by,
        requester_role_id: &requested_by,
        selected_subagent_id: source_run.selected_subagent_id.as_str(),
        task_family: source_run.task_family.as_str(),
        intent_text: intent_text.as_str(),
        compute_profile_id: approved_compute_profile_id.as_str(),
        run_label: Some(approved_run_label.as_str()),
        recipe_kind: proposal.proposed_recipe_kind.as_deref(),
        experiment_id: proposal.proposed_experiment_id.as_deref(),
        reservation_note: &dispatch_note,
        dispatch_note: &dispatch_note,
        poll_interval_seconds: Some(5),
        timeout_seconds: Some(600),
        code_provenance_capture: Some(&code_provenance_capture_default),
    };

    let run_orchestration = orchestrate_workbench_run(
        data_dir,
        cfg,
        gateway,
        bridge,
        detail,
        workbench_bundle,
        &run_dispatch,
    )
    .await
    .map_err(|error| anyhow!("study proposal dispatch failed: {}", error))?;

    let study_registry_sweep_after = ensure_study_registry_sweep(
        data_dir,
        workstream_id,
        workspace_id,
    )?;
    let study_decision_engine_after =
        ensure_study_decision_engine(data_dir, workstream_id, workspace_id)?;

    validate_identity(
        workstream_id,
        workspace_id,
        &study_registry_sweep_after,
        &study_decision_engine_after,
    )?;

    let generated_at = Utc::now();
    let evidence_refs = evidence_refs(workspace_id);
    let study_proposal_dispatch = StudyProposalDispatch {
        phase: STUDY_PROPOSAL_DISPATCH_PHASE.to_string(),
        contract_kind: STUDY_PROPOSAL_DISPATCH_KIND.to_string(),
        contract_version: STUDY_PROPOSAL_DISPATCH_VERSION.to_string(),
        dispatch_id: format!(
            "{}-study-proposal-dispatch-{}",
            sanitize_component(study_registry_sweep_before.study_registry.study_id.as_str()),
            generated_at.timestamp_millis()
        ),
        proposal_id: proposal.proposal_id.clone(),
        study_decision_id: study_decision_engine_before.study_decision.decision_id.clone(),
        next_run_proposal_id: proposal.proposal_id.clone(),
        study_id: study_registry_sweep_before.study_registry.study_id.clone(),
        workstream_id: study_registry_sweep_before.study_registry.workstream_id.clone(),
        workspace_id: study_registry_sweep_before.study_registry.workspace_id.clone(),
        session_id: study_registry_sweep_before.study_registry.session_id.clone(),
        same_beagle_owned_identity: study_registry_sweep_before.study_registry.same_beagle_owned_identity
            && study_decision_engine_before.study_decision.same_beagle_owned_identity
            && study_decision_engine_after.study_decision.same_beagle_owned_identity,
        proposal_state: "proposal-approved".to_string(),
        approved_by: requested_by.clone(),
        approved_at: generated_at,
        dispatch_state: run_orchestration.run.current_state.clone(),
        dispatched_at: run_orchestration
            .run
            .lifecycle_transitions
            .last()
            .map(|transition| transition.transitioned_at)
            .unwrap_or(generated_at),
        study_state: "study-updated".to_string(),
        requested_by: requested_by.clone(),
        requester_role_id: requested_by.clone(),
        selected_subagent_id: source_run.selected_subagent_id.clone(),
        task_family: source_run.task_family.clone(),
        approved_run_label,
        approved_variant_id: proposal.proposed_variant_id.clone(),
        approved_variant_label: proposal.proposed_variant_label.clone(),
        approved_compute_profile_id: approved_compute_profile_id.clone(),
        approved_recipe_kind: proposal.proposed_recipe_kind.clone(),
        approved_experiment_id: proposal.proposed_experiment_id.clone(),
        approved_replay_mode: proposal.proposed_replay_mode.clone(),
        source_run_id: proposal.proposed_source_run_id.clone(),
        reservation_id: run_orchestration.reservation.reservation_id.clone(),
        run_id: run_orchestration.run.run_id.clone(),
        submitted_job_id: run_orchestration.run.submitted_job_id,
        published_result_job_id: run_orchestration.run.published_result_job_id,
        result_binding_id: run_orchestration.result_binding.binding_id.clone(),
        run_result_identity_receipt_id: run_orchestration
            .run_result_identity_receipt
            .receipt_id
            .clone(),
        run_scoped_publication_id: run_orchestration.run_scoped_publication.publication_id.clone(),
        deterministic_result_binding_id: run_orchestration
            .deterministic_result_binding
            .binding_id
            .clone(),
        study_registry_id: study_registry_sweep_after.study_registry.study_id.clone(),
        study_dag_id: study_registry_sweep_after.study_dag.study_dag_id.clone(),
        study_sweep_id: study_registry_sweep_after.study_sweep.study_sweep_id.clone(),
        comparative_result_summary_id: study_registry_sweep_after
            .comparative_result_summary
            .comparative_result_summary_id
            .clone(),
        operator_review_required: true,
        evidence_refs: evidence_refs.clone(),
        note: "B26.3 approves one bounded next-run proposal, dispatches it as a real run through the existing workbench lane, and keeps the study state tied to the same Beagle-owned identity.".to_string(),
    };
    write_study_proposal_dispatch(data_dir, workspace_id, &study_proposal_dispatch)?;

    let study_run_update = build_study_run_update(
        &study_registry_sweep_before,
        &study_registry_sweep_after,
        &study_decision_engine_after,
        &study_proposal_dispatch.dispatch_id,
        requested_by.as_str(),
        approved_compute_profile_id.as_str(),
        &run_orchestration,
        "proposal-approved",
        run_orchestration.run.current_state.as_str(),
        run_orchestration.run.current_state.as_str(),
        "study-updated",
        study_run_update_evidence_refs(
            &study_registry_sweep_before,
            &study_registry_sweep_after,
            &study_decision_engine_after,
            &study_proposal_dispatch,
            &run_orchestration,
        ),
        generated_at,
    );
    write_study_run_update(data_dir, workspace_id, &study_run_update)?;

    let study_continuation_state = build_study_continuation_state(
        &study_run_update,
        &study_decision_engine_after,
        &study_proposal_dispatch.dispatch_id,
        "proposal-approved",
        run_orchestration.run.current_state.as_str(),
        run_orchestration.run.current_state.as_str(),
        "study-updated",
        study_continuation_evidence_refs(
            &study_registry_sweep_after,
            &study_decision_engine_after,
            &study_proposal_dispatch,
            &study_run_update,
        ),
        generated_at,
    );
    write_study_continuation_state(data_dir, workspace_id, &study_continuation_state)?;

    Ok(StudyProposalDispatchBundle {
        status: "ok".to_string(),
        phase: STUDY_PROPOSAL_DISPATCH_PHASE.to_string(),
        study_registry_sweep_before,
        study_decision_engine_before,
        study_proposal_dispatch,
        run_orchestration,
        study_registry_sweep_after,
        study_decision_engine_after,
        study_run_update,
        study_continuation_state,
    })
}

pub fn read_study_proposal_dispatch(
    data_dir: &Path,
    workspace_id: &str,
) -> anyhow::Result<Option<StudyProposalDispatch>> {
    read_json(study_proposal_dispatch_path(data_dir, workspace_id))
}

pub fn write_study_proposal_dispatch(
    data_dir: &Path,
    workspace_id: &str,
    dispatch: &StudyProposalDispatch,
) -> anyhow::Result<()> {
    write_json(study_proposal_dispatch_path(data_dir, workspace_id), dispatch)
}

pub fn read_latest_study_proposal_dispatch_bundle(
    data_dir: &Path,
    workbench_bundle: &CollaborativeComputeExperimentWorkbenchBundle,
    workstream_id: &str,
    workspace_id: &str,
) -> anyhow::Result<Option<StudyProposalDispatchBundle>> {
    let Some(study_proposal_dispatch) = read_study_proposal_dispatch(data_dir, workspace_id)? else {
        return Ok(None);
    };
    let Some(study_run_update) = read_study_run_update(data_dir, workspace_id)? else {
        return Ok(None);
    };
    let Some(study_continuation_state) = read_study_continuation_state(data_dir, workspace_id)? else {
        return Ok(None);
    };
    let study_registry_sweep_before =
        ensure_study_registry_sweep(data_dir, workstream_id, workspace_id)?;
    let study_decision_engine_before =
        ensure_study_decision_engine(data_dir, workstream_id, workspace_id)?;
    Ok(Some(StudyProposalDispatchBundle {
        status: "ok".to_string(),
        phase: STUDY_PROPOSAL_DISPATCH_PHASE.to_string(),
        study_registry_sweep_before: study_registry_sweep_before.clone(),
        study_decision_engine_before: study_decision_engine_before.clone(),
        study_proposal_dispatch,
        run_orchestration: read_run_orchestration_for_dispatch(
            data_dir,
            workbench_bundle,
            workspace_id,
            &study_run_update.dispatched_run_id,
        )?,
        study_registry_sweep_after: study_registry_sweep_before,
        study_decision_engine_after: study_decision_engine_before,
        study_run_update,
        study_continuation_state,
    }))
}

fn read_run_orchestration_for_dispatch(
    data_dir: &Path,
    workbench_bundle: &CollaborativeComputeExperimentWorkbenchBundle,
    workspace_id: &str,
    run_id: &str,
) -> anyhow::Result<WorkbenchRunOrchestrationBundle> {
    let run = crate::workbench_run::read_workbench_run(data_dir, workspace_id)?
        .ok_or_else(|| anyhow!("workbench run missing for workspace {}", workspace_id))?;
    if run.run_id != run_id {
        return Err(anyhow!(
            "workbench run mismatch: expected '{}' but found '{}'",
            run_id,
            run.run_id
        ));
    }
    let reservation = crate::workbench_reservation::read_workbench_reservation(
        data_dir,
        workbench_bundle,
    )?
        .ok_or_else(|| anyhow!("workbench reservation missing for workspace {}", workspace_id))?;
    let result_binding =
        crate::workbench_result_binding::read_workbench_result_binding(data_dir, &reservation.workstream_id, workspace_id)?
            .ok_or_else(|| anyhow!("workbench result binding missing for workspace {}", workspace_id))?;
    let run_result_identity_receipt = crate::workbench_result_binding::read_run_result_identity_receipt(
        data_dir,
        &reservation.workstream_id,
        workspace_id,
    )?
    .ok_or_else(|| anyhow!("run result identity receipt missing for workspace {}", workspace_id))?;
    let run_scoped_publication = crate::workbench_result_binding::read_run_scoped_publication(
        data_dir,
        &reservation.workstream_id,
        workspace_id,
    )?
    .ok_or_else(|| anyhow!("run scoped publication missing for workspace {}", workspace_id))?;
    let deterministic_result_binding = crate::workbench_result_binding::read_deterministic_result_binding(
        data_dir,
        &reservation.workstream_id,
        workspace_id,
    )?
    .ok_or_else(|| anyhow!("deterministic result binding missing for workspace {}", workspace_id))?;
    Ok(WorkbenchRunOrchestrationBundle {
        status: "ok".to_string(),
        phase: STUDY_PROPOSAL_DISPATCH_PHASE.to_string(),
        reservation,
        run,
        result_binding,
        run_result_identity_receipt,
        run_scoped_publication,
        deterministic_result_binding,
    })
}

fn study_proposal_dispatch_dir(data_dir: &Path) -> PathBuf {
    workspace_plane_dir(data_dir).join("study-proposal-dispatch")
}

fn study_proposal_dispatch_path(data_dir: &Path, workspace_id: &str) -> PathBuf {
    study_proposal_dispatch_dir(data_dir).join(format!("{}.json", sanitize_component(workspace_id)))
}

fn write_json<T>(path: PathBuf, value: &T) -> anyhow::Result<()>
where
    T: Serialize,
{
    if let Some(parent) = path.parent() {
        fs::create_dir_all(parent)
            .with_context(|| format!("failed to create proposal dispatch dir {}", parent.display()))?;
    }
    let body = serde_json::to_string_pretty(value)?;
    fs::write(&path, body)
        .with_context(|| format!("failed to write proposal dispatch artifact {}", path.display()))
}

fn read_json<T>(path: PathBuf) -> anyhow::Result<Option<T>>
where
    T: for<'de> Deserialize<'de>,
{
    if !path.exists() {
        return Ok(None);
    }
    let body = fs::read_to_string(&path)
        .with_context(|| format!("failed to read proposal dispatch artifact {}", path.display()))?;
    let value = serde_json::from_str::<T>(&body)
        .with_context(|| format!("failed to parse proposal dispatch artifact {}", path.display()))?;
    Ok(Some(value))
}

fn validate_identity(
    workstream_id: &str,
    workspace_id: &str,
    study_registry_sweep: &StudyRegistrySweepBundle,
    decision_engine: &StudyDecisionEngineBundle,
) -> anyhow::Result<()> {
    if study_registry_sweep.study_registry.workstream_id != workstream_id
        || decision_engine.study_registry.workstream_id != workstream_id
    {
        return Err(anyhow!("study proposal dispatch workstream mismatch"));
    }
    if study_registry_sweep.study_registry.workspace_id != workspace_id
        || decision_engine.study_registry.workspace_id != workspace_id
    {
        return Err(anyhow!("study proposal dispatch workspace mismatch"));
    }
    if study_registry_sweep.study_registry.session_id != decision_engine.study_registry.session_id {
        return Err(anyhow!("study proposal dispatch session mismatch"));
    }
    if !(study_registry_sweep.study_registry.same_beagle_owned_identity
        && decision_engine.study_decision.same_beagle_owned_identity
        && decision_engine.study_decision_basis.same_beagle_owned_identity)
    {
        return Err(anyhow!(
            "study proposal dispatch requires preserved Beagle-owned identity"
        ));
    }
    Ok(())
}

fn evidence_refs(workspace_id: &str) -> Vec<StudyEvidenceRef> {
    vec![
        StudyEvidenceRef {
            ref_id: "study-decision".to_string(),
            ref_kind: "workspace-plane-json".to_string(),
            locator: format!(
                "/var/lib/beagle/workspace-plane/study-decision/{}.json",
                sanitize_component(workspace_id)
            ),
            summary: "Canonical study decision chosen from the B26.2 decision engine.".to_string(),
        },
        StudyEvidenceRef {
            ref_id: "next-run-proposal".to_string(),
            ref_kind: "workspace-plane-json".to_string(),
            locator: format!(
                "/var/lib/beagle/workspace-plane/next-run-proposal/{}.json",
                sanitize_component(workspace_id)
            ),
            summary: "Canonical next-run proposal reviewed and approved by the operator path.".to_string(),
        },
    ]
}

fn study_run_update_evidence_refs(
    _before: &StudyRegistrySweepBundle,
    after: &StudyRegistrySweepBundle,
    decision: &StudyDecisionEngineBundle,
    dispatch: &StudyProposalDispatch,
    run_orchestration: &WorkbenchRunOrchestrationBundle,
) -> Vec<StudyEvidenceRef> {
    vec![
        StudyEvidenceRef {
            ref_id: "study-registry-after".to_string(),
            ref_kind: "workspace-plane-json".to_string(),
            locator: format!(
                "/var/lib/beagle/workspace-plane/study-registry/{}.json",
                sanitize_component(after.study_registry.workspace_id.as_str())
            ),
            summary: "Study registry after continuation includes the newly dispatched run.".to_string(),
        },
        StudyEvidenceRef {
            ref_id: "study-sweep-after".to_string(),
            ref_kind: "workspace-plane-json".to_string(),
            locator: format!(
                "/var/lib/beagle/workspace-plane/study-sweep/{}.json",
                sanitize_component(after.study_registry.workspace_id.as_str())
            ),
            summary: "Study sweep after continuation binds the new run to the same study DAG.".to_string(),
        },
        StudyEvidenceRef {
            ref_id: "comparative-result-summary-after".to_string(),
            ref_kind: "workspace-plane-json".to_string(),
            locator: format!(
                "/var/lib/beagle/workspace-plane/comparative-result-summary/{}.json",
                sanitize_component(after.study_registry.workspace_id.as_str())
            ),
            summary: "Comparative summary after continuation reflects the new run lineage.".to_string(),
        },
        StudyEvidenceRef {
            ref_id: "workbench-run".to_string(),
            ref_kind: "workspace-plane-json".to_string(),
            locator: format!(
                "/var/lib/beagle/workspace-plane/workbench-runs/{}.json",
                sanitize_component(after.study_registry.workspace_id.as_str())
            ),
            summary: format!(
                "Bound workbench run {} and published result {} through the same Beagle-owned identity.",
                run_orchestration.run.run_id, run_orchestration.run.published_result_job_id
            ),
        },
        StudyEvidenceRef {
            ref_id: "study-decision-after".to_string(),
            ref_kind: "workspace-plane-json".to_string(),
            locator: format!(
                "/var/lib/beagle/workspace-plane/study-decision/{}.json",
                sanitize_component(after.study_registry.workspace_id.as_str())
            ),
            summary: format!(
                "Refreshed study decision {} after the continuation run completed.",
                decision.study_decision.decision_id
            ),
        },
        StudyEvidenceRef {
            ref_id: "proposal-dispatch".to_string(),
            ref_kind: "workspace-plane-json".to_string(),
            locator: format!(
                "/var/lib/beagle/workspace-plane/study-proposal-dispatch/{}.json",
                sanitize_component(after.study_registry.workspace_id.as_str())
            ),
            summary: format!(
                "Approved proposal {} dispatched as a bounded continuation run.",
                dispatch.proposal_id
            ),
        },
    ]
}

fn study_continuation_evidence_refs(
    after: &StudyRegistrySweepBundle,
    decision: &StudyDecisionEngineBundle,
    dispatch: &StudyProposalDispatch,
    update: &StudyRunUpdate,
) -> Vec<StudyEvidenceRef> {
    vec![
        StudyEvidenceRef {
            ref_id: "study-continuation-state".to_string(),
            ref_kind: "workspace-plane-json".to_string(),
            locator: format!(
                "/var/lib/beagle/workspace-plane/study-continuation-state/{}.json",
                sanitize_component(after.study_registry.workspace_id.as_str())
            ),
            summary: "Continuation state records the proposal, dispatch, run update, and study refresh.".to_string(),
        },
        StudyEvidenceRef {
            ref_id: "study-run-update".to_string(),
            ref_kind: "workspace-plane-json".to_string(),
            locator: format!(
                "/var/lib/beagle/workspace-plane/study-run-update/{}.json",
                sanitize_component(after.study_registry.workspace_id.as_str())
            ),
            summary: format!(
                "Run update {} binds the newly dispatched run back into the study.",
                update.update_id
            ),
        },
        StudyEvidenceRef {
            ref_id: "next-run-proposal-after".to_string(),
            ref_kind: "workspace-plane-json".to_string(),
            locator: format!(
                "/var/lib/beagle/workspace-plane/next-run-proposal/{}.json",
                sanitize_component(after.study_registry.workspace_id.as_str())
            ),
            summary: format!(
                "Refreshed next-run proposal {} after continuation completed.",
                decision.next_run_proposal.proposal_id
            ),
        },
        StudyEvidenceRef {
            ref_id: "proposal-dispatch".to_string(),
            ref_kind: "workspace-plane-json".to_string(),
            locator: format!(
                "/var/lib/beagle/workspace-plane/study-proposal-dispatch/{}.json",
                sanitize_component(after.study_registry.workspace_id.as_str())
            ),
            summary: format!(
                "Proposal dispatch {} was approved and executed by the operator path.",
                dispatch.dispatch_id
            ),
        },
    ]
}

fn sanitize_component(value: &str) -> String {
    let mut sanitized = String::new();
    let mut last_was_dash = false;
    for character in value.trim().chars() {
        if character.is_ascii_alphanumeric() {
            sanitized.push(character.to_ascii_lowercase());
            last_was_dash = false;
        } else if !last_was_dash && !sanitized.is_empty() {
            sanitized.push('-');
            last_was_dash = true;
        }
    }
    sanitized.trim_matches('-').to_string()
}

fn normalize_sentence(value: &str) -> String {
    value.split_whitespace().collect::<Vec<_>>().join(" ")
}

fn normalize_selector(value: &str) -> String {
    value.trim().to_ascii_lowercase().replace('_', "-")
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::fs;
    use std::time::{SystemTime, UNIX_EPOCH};

    fn temp_workspace_dir(name: &str) -> PathBuf {
        let mut path = std::env::temp_dir();
        let stamp = SystemTime::now()
            .duration_since(UNIX_EPOCH)
            .expect("clock went backwards")
            .as_millis();
        path.push(format!(
            "beagle-study-proposal-dispatch-{}-{}",
            sanitize_component(name),
            stamp
        ));
        path
    }

    #[test]
    fn sanitize_and_normalize_helpers_are_stable() {
        assert_eq!(sanitize_component(" Study  Proposal "), "study-proposal");
        assert_eq!(normalize_sentence("  bounded   continuation  "), "bounded continuation");
        assert_eq!(normalize_selector("CPU_SHORT_v1"), "cpu-short-v1");
    }

    #[test]
    fn proposal_dispatch_roundtrip() {
        let data_dir = temp_workspace_dir("roundtrip");
        let dispatch = StudyProposalDispatch {
            phase: STUDY_PROPOSAL_DISPATCH_PHASE.to_string(),
            contract_kind: STUDY_PROPOSAL_DISPATCH_KIND.to_string(),
            contract_version: STUDY_PROPOSAL_DISPATCH_VERSION.to_string(),
            dispatch_id: "dispatch-1".to_string(),
            proposal_id: "proposal-1".to_string(),
            study_decision_id: "decision-1".to_string(),
            next_run_proposal_id: "proposal-1".to_string(),
            study_id: "study-1".to_string(),
            workstream_id: "workstream-1".to_string(),
            workspace_id: "workspace-1".to_string(),
            session_id: "session-1".to_string(),
            same_beagle_owned_identity: true,
            proposal_state: "proposal-approved".to_string(),
            approved_by: "beagle-operator".to_string(),
            approved_at: Utc::now(),
            dispatch_state: "running".to_string(),
            dispatched_at: Utc::now(),
            study_state: "study-updated".to_string(),
            requested_by: "beagle-operator".to_string(),
            requester_role_id: "beagle-operator".to_string(),
            selected_subagent_id: "subagent-1".to_string(),
            task_family: "study-family".to_string(),
            approved_run_label: "study-run".to_string(),
            approved_variant_id: "variant-1".to_string(),
            approved_variant_label: "variant-1".to_string(),
            approved_compute_profile_id: "cpu-short-v1".to_string(),
            approved_recipe_kind: Some("continuation".to_string()),
            approved_experiment_id: Some("experiment-1".to_string()),
            approved_replay_mode: Some("replay".to_string()),
            source_run_id: "source-run-1".to_string(),
            reservation_id: "reservation-1".to_string(),
            run_id: "run-1".to_string(),
            submitted_job_id: 100,
            published_result_job_id: 200,
            result_binding_id: "binding-1".to_string(),
            run_result_identity_receipt_id: "receipt-1".to_string(),
            run_scoped_publication_id: "publication-1".to_string(),
            deterministic_result_binding_id: "det-binding-1".to_string(),
            study_registry_id: "study-1".to_string(),
            study_dag_id: "study-dag-1".to_string(),
            study_sweep_id: "study-sweep-1".to_string(),
            comparative_result_summary_id: "summary-1".to_string(),
            operator_review_required: true,
            evidence_refs: vec![StudyEvidenceRef {
                ref_id: "ref-1".to_string(),
                ref_kind: "workspace-plane-json".to_string(),
                locator: "/tmp/ref-1".to_string(),
                summary: "reference".to_string(),
            }],
            note: "note".to_string(),
        };
        write_study_proposal_dispatch(&data_dir, "workspace-1", &dispatch)
            .expect("write proposal dispatch");
        let loaded = read_study_proposal_dispatch(&data_dir, "workspace-1")
            .expect("read proposal dispatch")
            .expect("missing proposal dispatch");
        assert_eq!(loaded, dispatch);

        fs::remove_dir_all(&data_dir).ok();
    }
}
