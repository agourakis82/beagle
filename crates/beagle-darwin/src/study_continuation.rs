use crate::study_decision::{StudyDecisionEngineBundle, StudyEvidenceRef};
use crate::study_registry::StudyRegistrySweepBundle;
use crate::workspace_plane::workspace_plane_dir;
use crate::workbench_run::WorkbenchRunOrchestrationBundle;
use anyhow::Context;
use chrono::{DateTime, Utc};
use serde::{Deserialize, Serialize};
use std::fs;
use std::path::{Path, PathBuf};

pub const STUDY_RUN_UPDATE_PHASE: &str = "B26.3";
pub const STUDY_RUN_UPDATE_KIND: &str = "study-run-update";
pub const STUDY_RUN_UPDATE_VERSION: &str = "beagle-study-run-update-v1";
pub const STUDY_CONTINUATION_STATE_PHASE: &str = "B26.3";
pub const STUDY_CONTINUATION_STATE_KIND: &str = "study-continuation-state";
pub const STUDY_CONTINUATION_STATE_VERSION: &str = "beagle-study-continuation-state-v1";

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
pub struct StudyRunUpdate {
    pub phase: String,
    pub contract_kind: String,
    pub contract_version: String,
    pub update_id: String,
    pub proposal_dispatch_id: String,
    pub study_decision_id: String,
    pub next_run_proposal_id: String,
    pub study_id: String,
    pub workstream_id: String,
    pub workspace_id: String,
    pub session_id: String,
    pub same_beagle_owned_identity: bool,
    pub previous_run_count: usize,
    pub updated_run_count: usize,
    pub previous_variant_count: usize,
    pub updated_variant_count: usize,
    pub previous_compared_run_count: usize,
    pub updated_compared_run_count: usize,
    pub dispatched_run_id: String,
    pub dispatched_run_label: String,
    pub dispatched_variant_id: String,
    pub dispatched_variant_label: String,
    pub approved_by: String,
    pub approved_compute_profile_id: String,
    pub proposal_state: String,
    pub dispatch_state: String,
    pub run_state: String,
    pub study_state: String,
    pub study_registry_id: String,
    pub study_dag_id: String,
    pub study_sweep_id: String,
    pub comparative_result_summary_id: String,
    pub result_binding_id: String,
    pub run_result_identity_receipt_id: String,
    pub run_scoped_publication_id: String,
    pub deterministic_result_binding_id: String,
    pub latest_run_diff_categories: Vec<String>,
    pub changed_categories_union: Vec<String>,
    pub evidence_refs: Vec<StudyEvidenceRef>,
    pub note: String,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
pub struct StudyContinuationState {
    pub phase: String,
    pub contract_kind: String,
    pub contract_version: String,
    pub continuation_state_id: String,
    pub study_id: String,
    pub workstream_id: String,
    pub workspace_id: String,
    pub session_id: String,
    pub same_beagle_owned_identity: bool,
    pub proposal_id: String,
    pub proposal_state: String,
    pub proposal_dispatch_id: String,
    pub run_update_id: String,
    pub study_decision_id: String,
    pub next_run_proposal_id: String,
    pub study_registry_id: String,
    pub study_dag_id: String,
    pub study_sweep_id: String,
    pub comparative_result_summary_id: String,
    pub dispatched_run_id: String,
    pub dispatched_run_label: String,
    pub approved_by: String,
    pub approved_compute_profile_id: String,
    pub dispatch_state: String,
    pub run_state: String,
    pub study_state: String,
    pub updated_run_count: usize,
    pub updated_variant_count: usize,
    pub updated_compared_run_count: usize,
    pub operator_review_required: bool,
    pub evidence_refs: Vec<StudyEvidenceRef>,
    pub note: String,
}

pub fn build_study_run_update(
    before: &StudyRegistrySweepBundle,
    after: &StudyRegistrySweepBundle,
    decision: &StudyDecisionEngineBundle,
    proposal_dispatch_id: &str,
    approved_by: &str,
    approved_compute_profile_id: &str,
    run_orchestration: &WorkbenchRunOrchestrationBundle,
    proposal_state: &str,
    dispatch_state: &str,
    run_state: &str,
    study_state: &str,
    evidence_refs: Vec<StudyEvidenceRef>,
    generated_at: DateTime<Utc>,
) -> StudyRunUpdate {
    let update_id = format!(
        "{}-study-run-update-{}",
        sanitize_component(before.study_registry.study_id.as_str()),
        generated_at.timestamp_millis()
    );
    StudyRunUpdate {
        phase: STUDY_RUN_UPDATE_PHASE.to_string(),
        contract_kind: STUDY_RUN_UPDATE_KIND.to_string(),
        contract_version: STUDY_RUN_UPDATE_VERSION.to_string(),
        update_id: update_id.clone(),
        proposal_dispatch_id: proposal_dispatch_id.to_string(),
        study_decision_id: decision.study_decision.decision_id.clone(),
        next_run_proposal_id: decision.next_run_proposal.proposal_id.clone(),
        study_id: after.study_registry.study_id.clone(),
        workstream_id: after.study_registry.workstream_id.clone(),
        workspace_id: after.study_registry.workspace_id.clone(),
        session_id: after.study_registry.session_id.clone(),
        same_beagle_owned_identity: before.study_registry.same_beagle_owned_identity
            && after.study_registry.same_beagle_owned_identity
            && decision.study_decision.same_beagle_owned_identity
            && decision.study_decision_basis.same_beagle_owned_identity,
        previous_run_count: before.study_registry.run_count,
        updated_run_count: after.study_registry.run_count,
        previous_variant_count: before.study_registry.variant_count,
        updated_variant_count: after.study_registry.variant_count,
        previous_compared_run_count: before.comparative_result_summary.compared_run_count,
        updated_compared_run_count: after.comparative_result_summary.compared_run_count,
        dispatched_run_id: run_orchestration.run.run_id.clone(),
        dispatched_run_label: run_orchestration.run.run_label.clone(),
        dispatched_variant_id: decision.study_decision.recommended_next_variant_id.clone(),
        dispatched_variant_label: decision
            .study_decision
            .recommended_next_variant_label
            .clone(),
        approved_by: approved_by.to_string(),
        approved_compute_profile_id: approved_compute_profile_id.to_string(),
        proposal_state: proposal_state.to_string(),
        dispatch_state: dispatch_state.to_string(),
        run_state: run_state.to_string(),
        study_state: study_state.to_string(),
        study_registry_id: after.study_registry.study_id.clone(),
        study_dag_id: after.study_dag.study_dag_id.clone(),
        study_sweep_id: after.study_sweep.study_sweep_id.clone(),
        comparative_result_summary_id: after
            .comparative_result_summary
            .comparative_result_summary_id
            .clone(),
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
        latest_run_diff_categories: after
            .comparative_result_summary
            .latest_run_diff_categories
            .clone()
            .unwrap_or_default(),
        changed_categories_union: after.comparative_result_summary.changed_categories_union.clone(),
        evidence_refs,
        note: "B26.3 records the bounded study continuation after a proposal becomes a real run, then binds the new result back into the same study registry, sweep, and comparative summary.".to_string(),
    }
}

pub fn build_study_continuation_state(
    update: &StudyRunUpdate,
    decision: &StudyDecisionEngineBundle,
    proposal_dispatch_id: &str,
    proposal_state: &str,
    dispatch_state: &str,
    run_state: &str,
    study_state: &str,
    evidence_refs: Vec<StudyEvidenceRef>,
    generated_at: DateTime<Utc>,
) -> StudyContinuationState {
    StudyContinuationState {
        phase: STUDY_CONTINUATION_STATE_PHASE.to_string(),
        contract_kind: STUDY_CONTINUATION_STATE_KIND.to_string(),
        contract_version: STUDY_CONTINUATION_STATE_VERSION.to_string(),
        continuation_state_id: format!(
            "{}-study-continuation-state-{}",
            sanitize_component(update.study_id.as_str()),
            generated_at.timestamp_millis()
        ),
        study_id: update.study_id.clone(),
        workstream_id: update.workstream_id.clone(),
        workspace_id: update.workspace_id.clone(),
        session_id: update.session_id.clone(),
        same_beagle_owned_identity: update.same_beagle_owned_identity
            && decision.study_decision.same_beagle_owned_identity
            && decision.study_decision_basis.same_beagle_owned_identity,
        proposal_id: decision.next_run_proposal.proposal_id.clone(),
        proposal_state: proposal_state.to_string(),
        proposal_dispatch_id: proposal_dispatch_id.to_string(),
        run_update_id: update.update_id.clone(),
        study_decision_id: decision.study_decision.decision_id.clone(),
        next_run_proposal_id: decision.next_run_proposal.proposal_id.clone(),
        study_registry_id: update.study_registry_id.clone(),
        study_dag_id: update.study_dag_id.clone(),
        study_sweep_id: update.study_sweep_id.clone(),
        comparative_result_summary_id: update.comparative_result_summary_id.clone(),
        dispatched_run_id: update.dispatched_run_id.clone(),
        dispatched_run_label: update.dispatched_run_label.clone(),
        approved_by: update.approved_by.clone(),
        approved_compute_profile_id: update.approved_compute_profile_id.clone(),
        dispatch_state: dispatch_state.to_string(),
        run_state: run_state.to_string(),
        study_state: study_state.to_string(),
        updated_run_count: update.updated_run_count,
        updated_variant_count: update.updated_variant_count,
        updated_compared_run_count: update.updated_compared_run_count,
        operator_review_required: true,
        evidence_refs,
        note: "B26.3 freezes the study continuation state after dispatch and result binding so restart can recover the same proposal, the same run update, and the same Beagle-owned identity.".to_string(),
    }
}

pub fn read_study_run_update(
    data_dir: &Path,
    workspace_id: &str,
) -> anyhow::Result<Option<StudyRunUpdate>> {
    read_json(study_run_update_path(data_dir, workspace_id))
}

pub fn read_study_continuation_state(
    data_dir: &Path,
    workspace_id: &str,
) -> anyhow::Result<Option<StudyContinuationState>> {
    read_json(study_continuation_state_path(data_dir, workspace_id))
}

pub fn write_study_run_update(
    data_dir: &Path,
    workspace_id: &str,
    update: &StudyRunUpdate,
) -> anyhow::Result<()> {
    write_json(study_run_update_path(data_dir, workspace_id), update)
}

pub fn write_study_continuation_state(
    data_dir: &Path,
    workspace_id: &str,
    state: &StudyContinuationState,
) -> anyhow::Result<()> {
    write_json(study_continuation_state_path(data_dir, workspace_id), state)
}

fn study_continuation_dir(data_dir: &Path) -> PathBuf {
    workspace_plane_dir(data_dir).join("study-continuation-state")
}

fn study_run_update_dir(data_dir: &Path) -> PathBuf {
    workspace_plane_dir(data_dir).join("study-run-update")
}

fn study_continuation_state_path(data_dir: &Path, workspace_id: &str) -> PathBuf {
    study_continuation_dir(data_dir).join(format!("{}.json", sanitize_component(workspace_id)))
}

fn study_run_update_path(data_dir: &Path, workspace_id: &str) -> PathBuf {
    study_run_update_dir(data_dir).join(format!("{}.json", sanitize_component(workspace_id)))
}

fn read_json<T>(path: PathBuf) -> anyhow::Result<Option<T>>
where
    T: for<'de> Deserialize<'de>,
{
    if !path.exists() {
        return Ok(None);
    }
    let body = fs::read_to_string(&path)
        .with_context(|| format!("failed to read continuation artifact {}", path.display()))?;
    let value = serde_json::from_str::<T>(&body)
        .with_context(|| format!("failed to parse continuation artifact {}", path.display()))?;
    Ok(Some(value))
}

fn write_json<T>(path: PathBuf, value: &T) -> anyhow::Result<()>
where
    T: Serialize,
{
    if let Some(parent) = path.parent() {
        fs::create_dir_all(parent)
            .with_context(|| format!("failed to create continuation dir {}", parent.display()))?;
    }
    let body = serde_json::to_string_pretty(value)?;
    fs::write(&path, body)
        .with_context(|| format!("failed to write continuation artifact {}", path.display()))
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
    use std::fs;
    use std::time::{SystemTime, UNIX_EPOCH};

    fn temp_workspace_dir(name: &str) -> PathBuf {
        let mut path = std::env::temp_dir();
        let stamp = SystemTime::now()
            .duration_since(UNIX_EPOCH)
            .expect("clock went backwards")
            .as_millis();
        path.push(format!(
            "beagle-study-continuation-{}-{}",
            sanitize_component(name),
            stamp
        ));
        path
    }

    #[test]
    fn study_continuation_roundtrip() {
        let data_dir = temp_workspace_dir("roundtrip");
        let update = StudyRunUpdate {
            phase: STUDY_RUN_UPDATE_PHASE.to_string(),
            contract_kind: STUDY_RUN_UPDATE_KIND.to_string(),
            contract_version: STUDY_RUN_UPDATE_VERSION.to_string(),
            update_id: "update-1".to_string(),
            proposal_dispatch_id: "dispatch-1".to_string(),
            study_decision_id: "decision-1".to_string(),
            next_run_proposal_id: "proposal-1".to_string(),
            study_id: "study-1".to_string(),
            workstream_id: "workstream-1".to_string(),
            workspace_id: "workspace-1".to_string(),
            session_id: "session-1".to_string(),
            same_beagle_owned_identity: true,
            previous_run_count: 1,
            updated_run_count: 2,
            previous_variant_count: 1,
            updated_variant_count: 2,
            previous_compared_run_count: 1,
            updated_compared_run_count: 2,
            dispatched_run_id: "run-2".to_string(),
            dispatched_run_label: "run-label".to_string(),
            dispatched_variant_id: "variant-2".to_string(),
            dispatched_variant_label: "variant-label".to_string(),
            approved_by: "beagle-operator".to_string(),
            approved_compute_profile_id: "cpu-short-v1".to_string(),
            proposal_state: "proposal-approved".to_string(),
            dispatch_state: "running".to_string(),
            run_state: "running".to_string(),
            study_state: "study-updated".to_string(),
            study_registry_id: "study-1".to_string(),
            study_dag_id: "study-dag-1".to_string(),
            study_sweep_id: "study-sweep-1".to_string(),
            comparative_result_summary_id: "summary-1".to_string(),
            result_binding_id: "binding-1".to_string(),
            run_result_identity_receipt_id: "receipt-1".to_string(),
            run_scoped_publication_id: "publication-1".to_string(),
            deterministic_result_binding_id: "det-binding-1".to_string(),
            latest_run_diff_categories: vec!["code".to_string()],
            changed_categories_union: vec!["code".to_string(), "config".to_string()],
            evidence_refs: vec![StudyEvidenceRef {
                ref_id: "ref-1".to_string(),
                ref_kind: "workspace-plane-json".to_string(),
                locator: "/tmp/ref-1".to_string(),
                summary: "reference".to_string(),
            }],
            note: "note".to_string(),
        };
        write_study_run_update(&data_dir, "workspace-1", &update).expect("write run update");
        let loaded = read_study_run_update(&data_dir, "workspace-1")
            .expect("read run update")
            .expect("missing run update");
        assert_eq!(loaded, update);

        let continuation = StudyContinuationState {
            phase: STUDY_CONTINUATION_STATE_PHASE.to_string(),
            contract_kind: STUDY_CONTINUATION_STATE_KIND.to_string(),
            contract_version: STUDY_CONTINUATION_STATE_VERSION.to_string(),
            continuation_state_id: "state-1".to_string(),
            study_id: "study-1".to_string(),
            workstream_id: "workstream-1".to_string(),
            workspace_id: "workspace-1".to_string(),
            session_id: "session-1".to_string(),
            same_beagle_owned_identity: true,
            proposal_id: "proposal-1".to_string(),
            proposal_state: "proposal-approved".to_string(),
            proposal_dispatch_id: "dispatch-1".to_string(),
            run_update_id: "update-1".to_string(),
            study_decision_id: "decision-1".to_string(),
            next_run_proposal_id: "proposal-1".to_string(),
            study_registry_id: "study-1".to_string(),
            study_dag_id: "study-dag-1".to_string(),
            study_sweep_id: "study-sweep-1".to_string(),
            comparative_result_summary_id: "summary-1".to_string(),
            dispatched_run_id: "run-2".to_string(),
            dispatched_run_label: "run-label".to_string(),
            approved_by: "beagle-operator".to_string(),
            approved_compute_profile_id: "cpu-short-v1".to_string(),
            dispatch_state: "running".to_string(),
            run_state: "running".to_string(),
            study_state: "study-updated".to_string(),
            updated_run_count: 2,
            updated_variant_count: 2,
            updated_compared_run_count: 2,
            operator_review_required: true,
            evidence_refs: vec![StudyEvidenceRef {
                ref_id: "ref-1".to_string(),
                ref_kind: "workspace-plane-json".to_string(),
                locator: "/tmp/ref-1".to_string(),
                summary: "reference".to_string(),
            }],
            note: "note".to_string(),
        };
        write_study_continuation_state(&data_dir, "workspace-1", &continuation)
            .expect("write continuation");
        let loaded = read_study_continuation_state(&data_dir, "workspace-1")
            .expect("read continuation")
            .expect("missing continuation");
        assert_eq!(loaded, continuation);

        fs::remove_dir_all(&data_dir).ok();
    }
}
