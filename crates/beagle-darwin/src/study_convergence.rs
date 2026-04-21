use crate::next_run_proposal::read_next_run_proposal;
use crate::study_continuation::{
    read_study_continuation_state, read_study_run_update, StudyContinuationState, StudyRunUpdate,
};
use crate::study_decision::{
    read_study_decision, read_study_decision_basis, StudyDecision, StudyDecisionBasis,
    StudyEvidenceRef,
};
use crate::study_proposal_dispatch::read_study_proposal_dispatch;
use crate::study_registry::{
    ensure_study_registry_sweep, ComparativeResultSummary, StudyRegistry, StudyRegistrySweepBundle,
};
use crate::study_sweep::{StudySweep, StudySweepVariant};
use crate::workspace_plane::workspace_plane_dir;
use anyhow::{anyhow, Context};
use chrono::{DateTime, Utc};
use serde::{Deserialize, Serialize};
use std::fs;
use std::path::{Path, PathBuf};

pub const STUDY_CONVERGENCE_PHASE: &str = "B26.4";
pub const STUDY_CONVERGENCE_KIND: &str = "study-convergence";
pub const STUDY_CONVERGENCE_VERSION: &str = "beagle-study-convergence-v1";
pub const VARIANT_PROMOTION_DECISION_KIND: &str = "variant-promotion-decision";
pub const VARIANT_PROMOTION_DECISION_VERSION: &str = "beagle-variant-promotion-decision-v1";
pub const STUDY_CLOSEOUT_SUMMARY_KIND: &str = "study-closeout-summary";
pub const STUDY_CLOSEOUT_SUMMARY_VERSION: &str = "beagle-study-closeout-summary-v1";
pub const STUDY_CONVERGENCE_CONTINUE_STUDY: &str = "continue-study";
pub const STUDY_CONVERGENCE_STOP_STUDY: &str = "stop-study";
pub const STUDY_CONVERGENCE_CONVERGED: &str = "converged";
pub const VARIANT_PROMOTION_DECISION_PROMOTE_VARIANT: &str = "promote-variant";
pub const VARIANT_PROMOTION_DECISION_ARCHIVE_VARIANT: &str = "archive-variant";

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
pub struct StudyConvergence {
    pub phase: String,
    pub contract_kind: String,
    pub contract_version: String,
    pub convergence_id: String,
    pub study_id: String,
    pub workstream_id: String,
    pub workspace_id: String,
    pub session_id: String,
    pub same_beagle_owned_identity: bool,
    pub generated_at: DateTime<Utc>,
    pub study_registry_id: String,
    pub study_dag_id: String,
    pub study_sweep_id: String,
    pub comparative_result_summary_id: String,
    pub study_decision_id: String,
    pub study_decision_basis_id: String,
    pub study_proposal_dispatch_id: String,
    pub study_run_update_id: String,
    pub study_continuation_state_id: String,
    pub next_run_proposal_id: String,
    pub registry_run_count: usize,
    pub registry_variant_count: usize,
    pub decision_basis_compared_run_count: usize,
    pub updated_run_count: usize,
    pub updated_variant_count: usize,
    pub updated_compared_run_count: usize,
    pub successful_run_count: usize,
    pub failed_run_count: usize,
    pub latest_run_diff_categories: Vec<String>,
    pub changed_categories_union: Vec<String>,
    pub best_run_id: String,
    pub best_variant_id: String,
    pub best_run_label: String,
    pub best_variant_label: String,
    pub best_variant_kind: String,
    pub best_compute_profile_id: String,
    pub best_run_score: u16,
    pub best_run_reason: String,
    pub prior_recommended_action: String,
    pub convergence_state: String,
    pub enough_evidence_to_stop: bool,
    pub recommended_action: String,
    pub decision_basis_summary: String,
    pub evidence_refs: Vec<StudyEvidenceRef>,
    pub note: String,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
pub struct VariantPromotionDecision {
    pub phase: String,
    pub contract_kind: String,
    pub contract_version: String,
    pub decision_id: String,
    pub study_id: String,
    pub workstream_id: String,
    pub workspace_id: String,
    pub session_id: String,
    pub same_beagle_owned_identity: bool,
    pub generated_at: DateTime<Utc>,
    pub study_convergence_id: String,
    pub study_convergence_state: String,
    pub decision_action: String,
    pub promoted_variant_id: String,
    pub promoted_variant_label: String,
    pub promoted_variant_kind: String,
    pub promoted_run_id: String,
    pub promoted_run_label: String,
    pub promoted_compute_profile_id: String,
    pub archived_variant_count: usize,
    pub archived_variant_ids: Vec<String>,
    pub archived_variant_labels: Vec<String>,
    pub archived_variant_kinds: Vec<String>,
    pub operator_review_required: bool,
    pub decision_basis_summary: String,
    pub evidence_refs: Vec<StudyEvidenceRef>,
    pub note: String,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
pub struct StudyCloseoutSummary {
    pub phase: String,
    pub contract_kind: String,
    pub contract_version: String,
    pub closeout_summary_id: String,
    pub study_id: String,
    pub workstream_id: String,
    pub workspace_id: String,
    pub session_id: String,
    pub same_beagle_owned_identity: bool,
    pub generated_at: DateTime<Utc>,
    pub study_convergence_id: String,
    pub variant_promotion_decision_id: String,
    pub final_study_state: String,
    pub final_comparative_decision: String,
    pub final_variant_promotion_state: String,
    pub total_runs: usize,
    pub total_variants: usize,
    pub compared_run_count: usize,
    pub successful_run_count: usize,
    pub failed_run_count: usize,
    pub promoted_variant_id: String,
    pub promoted_variant_label: String,
    pub promoted_run_id: String,
    pub promoted_run_label: String,
    pub archived_variant_count: usize,
    pub archived_variant_ids: Vec<String>,
    pub archived_variant_labels: Vec<String>,
    pub archived_variant_kinds: Vec<String>,
    pub operator_review_required: bool,
    pub final_decision_basis_summary: String,
    pub evidence_refs: Vec<StudyEvidenceRef>,
    pub note: String,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
pub struct StudyConvergenceBundle {
    pub status: String,
    pub phase: String,
    pub study_convergence: StudyConvergence,
    pub variant_promotion_decision: VariantPromotionDecision,
    pub study_closeout_summary: StudyCloseoutSummary,
}

pub fn ensure_study_convergence(
    data_dir: &Path,
    workstream_id: &str,
    workspace_id: &str,
) -> anyhow::Result<StudyConvergenceBundle> {
    let study_registry_sweep = ensure_study_registry_sweep(data_dir, workstream_id, workspace_id)
        .map_err(|error| anyhow!("failed to load study registry sweep: {}", error))?;
    let study_decision = read_study_decision(data_dir, workspace_id)?
        .ok_or_else(|| anyhow!("study decision missing for workspace {}", workspace_id))?;
    let study_decision_basis = read_study_decision_basis(data_dir, workspace_id)?
        .ok_or_else(|| anyhow!("study decision basis missing for workspace {}", workspace_id))?;
    let proposal = read_next_run_proposal(data_dir, workspace_id)?
        .ok_or_else(|| anyhow!("next run proposal missing for workspace {}", workspace_id))?;
    let proposal_dispatch = read_study_proposal_dispatch(data_dir, workspace_id)?
        .ok_or_else(|| anyhow!("study proposal dispatch missing for workspace {}", workspace_id))?;
    let study_run_update = read_study_run_update(data_dir, workspace_id)?
        .ok_or_else(|| anyhow!("study run update missing for workspace {}", workspace_id))?;
    let study_continuation_state = read_study_continuation_state(data_dir, workspace_id)?
        .ok_or_else(|| anyhow!("study continuation state missing for workspace {}", workspace_id))?;

    validate_identity(
        workstream_id,
        workspace_id,
        &study_registry_sweep,
        &study_decision,
        &study_decision_basis,
        &proposal,
        &proposal_dispatch,
        &study_run_update,
        &study_continuation_state,
    )?;

    let generated_at = Utc::now();
    let promoted_variant = best_variant(&study_registry_sweep.study_sweep, &study_decision_basis)?;
    let archived_variants = archived_variants(
        &study_registry_sweep.study_sweep,
        promoted_variant.variant_id.as_str(),
    );
    let evidence_refs = evidence_refs(data_dir, workspace_id);
    let enough_evidence_to_stop = should_stop_study(
        &study_run_update,
        &study_decision_basis,
        &study_registry_sweep.comparative_result_summary,
    );
    let convergence_state = if enough_evidence_to_stop {
        STUDY_CONVERGENCE_CONVERGED
    } else {
        STUDY_CONVERGENCE_CONTINUE_STUDY
    };
    let decision_basis_summary = format!(
        "updated_runs={} updated_variants={} updated_compared_runs={} best_score={} latest_diff={} prior_action={}",
        study_run_update.updated_run_count,
        study_run_update.updated_variant_count,
        study_run_update.updated_compared_run_count,
        study_decision_basis.best_run_score,
        study_run_update.latest_run_diff_categories.join(","),
        study_decision_basis.recommended_action
    );

    let study_convergence = build_study_convergence(
        &study_registry_sweep,
        &study_decision,
        &study_decision_basis,
        &proposal,
        &proposal_dispatch,
        &study_run_update,
        &study_continuation_state,
        &promoted_variant,
        enough_evidence_to_stop,
        convergence_state,
        &decision_basis_summary,
        evidence_refs.clone(),
        generated_at,
    );
    let variant_promotion_decision = build_variant_promotion_decision(
        &study_convergence,
        &study_registry_sweep.study_sweep,
        promoted_variant.variant_id.as_str(),
        promoted_variant.variant_label.as_str(),
        promoted_variant.variant_kind.as_str(),
        promoted_variant.compute_profile_id.as_str(),
        &archived_variants,
        evidence_refs.clone(),
        generated_at,
    );
    let study_closeout_summary = build_study_closeout_summary(
        &study_convergence,
        &variant_promotion_decision,
        &study_registry_sweep.study_registry,
        &study_registry_sweep.study_sweep,
        &study_registry_sweep.comparative_result_summary,
        &archived_variants,
        evidence_refs,
        generated_at,
    );

    write_study_convergence(data_dir, workspace_id, &study_convergence)?;
    write_variant_promotion_decision(data_dir, workspace_id, &variant_promotion_decision)?;
    write_study_closeout_summary(data_dir, workspace_id, &study_closeout_summary)?;

    Ok(StudyConvergenceBundle {
        status: "ok".to_string(),
        phase: STUDY_CONVERGENCE_PHASE.to_string(),
        study_convergence,
        variant_promotion_decision,
        study_closeout_summary,
    })
}

fn build_study_convergence(
    registry_sweep: &StudyRegistrySweepBundle,
    study_decision: &StudyDecision,
    study_decision_basis: &StudyDecisionBasis,
    proposal: &crate::next_run_proposal::NextRunProposal,
    proposal_dispatch: &crate::study_proposal_dispatch::StudyProposalDispatch,
    study_run_update: &StudyRunUpdate,
    study_continuation_state: &StudyContinuationState,
    promoted_variant: &StudySweepVariant,
    enough_evidence_to_stop: bool,
    convergence_state: &str,
    decision_basis_summary: &str,
    evidence_refs: Vec<StudyEvidenceRef>,
    generated_at: DateTime<Utc>,
) -> StudyConvergence {
    StudyConvergence {
        phase: STUDY_CONVERGENCE_PHASE.to_string(),
        contract_kind: STUDY_CONVERGENCE_KIND.to_string(),
        contract_version: STUDY_CONVERGENCE_VERSION.to_string(),
        convergence_id: format!(
            "{}-study-convergence",
            sanitize_component(registry_sweep.study_registry.study_id.as_str())
        ),
        study_id: registry_sweep.study_registry.study_id.clone(),
        workstream_id: registry_sweep.study_registry.workstream_id.clone(),
        workspace_id: registry_sweep.study_registry.workspace_id.clone(),
        session_id: registry_sweep.study_registry.session_id.clone(),
        same_beagle_owned_identity: registry_sweep.study_registry.same_beagle_owned_identity
            && registry_sweep.study_sweep.same_beagle_owned_identity
            && registry_sweep.comparative_result_summary.same_beagle_owned_identity
            && study_decision.same_beagle_owned_identity
            && study_decision_basis.same_beagle_owned_identity
            && proposal.same_beagle_owned_identity
            && proposal_dispatch.same_beagle_owned_identity
            && study_run_update.same_beagle_owned_identity
            && study_continuation_state.same_beagle_owned_identity,
        generated_at,
        study_registry_id: registry_sweep.study_registry.study_id.clone(),
        study_dag_id: registry_sweep.study_dag.study_dag_id.clone(),
        study_sweep_id: registry_sweep.study_sweep.study_sweep_id.clone(),
        comparative_result_summary_id: registry_sweep
            .comparative_result_summary
            .comparative_result_summary_id
            .clone(),
        study_decision_id: study_decision.decision_id.clone(),
        study_decision_basis_id: study_decision_basis.basis_id.clone(),
        study_proposal_dispatch_id: proposal_dispatch.dispatch_id.clone(),
        study_run_update_id: study_run_update.update_id.clone(),
        study_continuation_state_id: study_continuation_state.continuation_state_id.clone(),
        next_run_proposal_id: proposal.proposal_id.clone(),
        registry_run_count: registry_sweep.study_registry.run_count,
        registry_variant_count: registry_sweep.study_registry.variant_count,
        decision_basis_compared_run_count: study_decision_basis.compared_run_count,
        updated_run_count: study_run_update.updated_run_count,
        updated_variant_count: study_run_update.updated_variant_count,
        updated_compared_run_count: study_run_update.updated_compared_run_count,
        successful_run_count: study_decision_basis.successful_run_count,
        failed_run_count: study_decision_basis.failed_run_count,
        latest_run_diff_categories: study_run_update.latest_run_diff_categories.clone(),
        changed_categories_union: registry_sweep.comparative_result_summary.changed_categories_union.clone(),
        best_run_id: study_decision_basis.best_run_id.clone(),
        best_variant_id: study_decision_basis.best_variant_id.clone(),
        best_run_label: study_decision_basis.best_run_label.clone(),
        best_variant_label: study_decision_basis.best_variant_label.clone(),
        best_variant_kind: promoted_variant.variant_kind.clone(),
        best_compute_profile_id: promoted_variant.compute_profile_id.clone(),
        best_run_score: study_decision_basis.best_run_score,
        best_run_reason: study_decision_basis.best_run_reason.clone(),
        prior_recommended_action: study_decision_basis.recommended_action.clone(),
        convergence_state: convergence_state.to_string(),
        enough_evidence_to_stop,
        recommended_action: if enough_evidence_to_stop {
            STUDY_CONVERGENCE_STOP_STUDY.to_string()
        } else {
            STUDY_CONVERGENCE_CONTINUE_STUDY.to_string()
        },
        decision_basis_summary: decision_basis_summary.to_string(),
        evidence_refs,
        note: if enough_evidence_to_stop {
            format!(
                "B26.4 closes the study once the bounded continuation run confirms the best-scoring variant ({}) and the final diff remains result-only.",
                promoted_variant.variant_label.as_str()
            )
        } else {
            format!(
                "B26.4 keeps the study continuing because the bounded continuation run has not yet reached the stop threshold, even though {} remains the best-scoring variant.",
                promoted_variant.variant_label.as_str()
            )
        },
    }
}

fn build_variant_promotion_decision(
    convergence: &StudyConvergence,
    _study_sweep: &StudySweep,
    promoted_variant_id: &str,
    promoted_variant_label: &str,
    promoted_variant_kind: &str,
    promoted_compute_profile_id: &str,
    archived_variants: &[(String, String, String)],
    evidence_refs: Vec<StudyEvidenceRef>,
    generated_at: DateTime<Utc>,
) -> VariantPromotionDecision {
    VariantPromotionDecision {
        phase: STUDY_CONVERGENCE_PHASE.to_string(),
        contract_kind: VARIANT_PROMOTION_DECISION_KIND.to_string(),
        contract_version: VARIANT_PROMOTION_DECISION_VERSION.to_string(),
        decision_id: format!(
            "{}-variant-promotion-decision",
            sanitize_component(convergence.study_id.as_str())
        ),
        study_id: convergence.study_id.clone(),
        workstream_id: convergence.workstream_id.clone(),
        workspace_id: convergence.workspace_id.clone(),
        session_id: convergence.session_id.clone(),
        same_beagle_owned_identity: convergence.same_beagle_owned_identity,
        generated_at,
        study_convergence_id: convergence.convergence_id.clone(),
        study_convergence_state: convergence.convergence_state.clone(),
        decision_action: if convergence.enough_evidence_to_stop {
            VARIANT_PROMOTION_DECISION_PROMOTE_VARIANT.to_string()
        } else {
            STUDY_CONVERGENCE_CONTINUE_STUDY.to_string()
        },
        promoted_variant_id: promoted_variant_id.to_string(),
        promoted_variant_label: promoted_variant_label.to_string(),
        promoted_variant_kind: promoted_variant_kind.to_string(),
        promoted_run_id: convergence.best_run_id.clone(),
        promoted_run_label: convergence.best_run_label.clone(),
        promoted_compute_profile_id: promoted_compute_profile_id.to_string(),
        archived_variant_count: archived_variants.len(),
        archived_variant_ids: archived_variants.iter().map(|entry| entry.0.clone()).collect(),
        archived_variant_labels: archived_variants.iter().map(|entry| entry.1.clone()).collect(),
        archived_variant_kinds: archived_variants.iter().map(|entry| entry.2.clone()).collect(),
        operator_review_required: true,
        decision_basis_summary: format!(
            "best_variant={} best_run_score={} archived_variants={} stop_study={}",
            convergence.best_variant_id,
            convergence.best_run_score,
            archived_variants.len(),
            convergence.enough_evidence_to_stop
        ),
        evidence_refs,
        note: if convergence.enough_evidence_to_stop {
            "B26.4 converts convergence into a bounded promotion gate: one variant is marked as the promoted candidate while the remaining variants are placed on archive-only footing.".to_string()
        } else {
            "B26.4 records the current best candidate and keeps the remaining variants archive-only while the study continues to gather evidence.".to_string()
        },
    }
}

fn build_study_closeout_summary(
    convergence: &StudyConvergence,
    promotion_decision: &VariantPromotionDecision,
    registry: &StudyRegistry,
    study_sweep: &StudySweep,
    summary: &ComparativeResultSummary,
    archived_variants: &[(String, String, String)],
    evidence_refs: Vec<StudyEvidenceRef>,
    generated_at: DateTime<Utc>,
) -> StudyCloseoutSummary {
    StudyCloseoutSummary {
        phase: STUDY_CONVERGENCE_PHASE.to_string(),
        contract_kind: STUDY_CLOSEOUT_SUMMARY_KIND.to_string(),
        contract_version: STUDY_CLOSEOUT_SUMMARY_VERSION.to_string(),
        closeout_summary_id: format!(
            "{}-study-closeout-summary",
            sanitize_component(convergence.study_id.as_str())
        ),
        study_id: convergence.study_id.clone(),
        workstream_id: convergence.workstream_id.clone(),
        workspace_id: convergence.workspace_id.clone(),
        session_id: convergence.session_id.clone(),
        same_beagle_owned_identity: convergence.same_beagle_owned_identity,
        generated_at,
        study_convergence_id: convergence.convergence_id.clone(),
        variant_promotion_decision_id: promotion_decision.decision_id.clone(),
        final_study_state: convergence.convergence_state.clone(),
        final_comparative_decision: convergence.recommended_action.clone(),
        final_variant_promotion_state: promotion_decision.decision_action.clone(),
        total_runs: registry.run_count,
        total_variants: study_sweep.variant_count,
        compared_run_count: summary.compared_run_count,
        successful_run_count: convergence.successful_run_count,
        failed_run_count: convergence.failed_run_count,
        promoted_variant_id: promotion_decision.promoted_variant_id.clone(),
        promoted_variant_label: promotion_decision.promoted_variant_label.clone(),
        promoted_run_id: promotion_decision.promoted_run_id.clone(),
        promoted_run_label: promotion_decision.promoted_run_label.clone(),
        archived_variant_count: archived_variants.len(),
        archived_variant_ids: archived_variants.iter().map(|entry| entry.0.clone()).collect(),
        archived_variant_labels: archived_variants.iter().map(|entry| entry.1.clone()).collect(),
        archived_variant_kinds: archived_variants.iter().map(|entry| entry.2.clone()).collect(),
        operator_review_required: true,
        final_decision_basis_summary: format!(
            "updated_runs={} updated_compared_runs={} best_score={} final_action={}",
            convergence.updated_run_count,
            convergence.updated_compared_run_count,
            convergence.best_run_score,
            convergence.recommended_action
        ),
        evidence_refs,
        note: if convergence.enough_evidence_to_stop {
            "B26.4 freezes the closeout summary so the study can be treated as converged, with the promoted variant and archived variants recorded in the same Beagle-owned identity.".to_string()
        } else {
            "B26.4 freezes the closeout summary while the study remains open, preserving the current best candidate, archive-only variants, and the same Beagle-owned identity.".to_string()
        },
    }
}

fn best_variant(
    study_sweep: &StudySweep,
    study_decision_basis: &StudyDecisionBasis,
) -> anyhow::Result<StudySweepVariant> {
    study_sweep
        .variants
        .iter()
        .find(|variant| variant.variant_id == study_decision_basis.best_variant_id)
        .cloned()
        .ok_or_else(|| {
            anyhow!(
                "unable to locate promoted variant {} in study sweep",
                study_decision_basis.best_variant_id
            )
        })
}

fn archived_variants(
    study_sweep: &StudySweep,
    promoted_variant_id: &str,
) -> Vec<(String, String, String)> {
    study_sweep
        .variants
        .iter()
        .filter(|variant| variant.variant_id != promoted_variant_id)
        .map(|variant| {
            (
                variant.variant_id.clone(),
                variant.variant_label.clone(),
                variant.variant_kind.clone(),
            )
        })
        .collect()
}

fn should_stop_study(
    study_run_update: &StudyRunUpdate,
    study_decision_basis: &StudyDecisionBasis,
    summary: &ComparativeResultSummary,
) -> bool {
    study_run_update.same_beagle_owned_identity
        && study_run_update.updated_run_count >= 11
        && study_run_update.updated_variant_count >= 11
        && study_run_update.updated_compared_run_count >= 11
        && summary.compared_run_count >= 10
        && study_decision_basis.best_run_score >= 140
        && study_run_update.dispatch_state == "succeeded"
        && study_run_update.run_state == "succeeded"
        && study_run_update.study_state == "study-updated"
        && study_run_update
            .latest_run_diff_categories
            .iter()
            .any(|value| value == "result")
        && summary
            .latest_run_diff_categories
            .as_ref()
            .map(|categories| categories.iter().any(|value| value == "result"))
            .unwrap_or(false)
}

fn validate_identity(
    workstream_id: &str,
    workspace_id: &str,
    registry_sweep: &StudyRegistrySweepBundle,
    study_decision: &StudyDecision,
    study_decision_basis: &StudyDecisionBasis,
    proposal: &crate::next_run_proposal::NextRunProposal,
    proposal_dispatch: &crate::study_proposal_dispatch::StudyProposalDispatch,
    study_run_update: &StudyRunUpdate,
    study_continuation_state: &StudyContinuationState,
) -> anyhow::Result<()> {
    let registry = &registry_sweep.study_registry;
    let sweep = &registry_sweep.study_sweep;
    let summary = &registry_sweep.comparative_result_summary;
    if registry.workstream_id != workstream_id
        || sweep.workstream_id != workstream_id
        || summary.workstream_id != workstream_id
        || study_decision.workstream_id != workstream_id
        || study_decision_basis.workstream_id != workstream_id
        || proposal.workstream_id != workstream_id
        || proposal_dispatch.workstream_id != workstream_id
        || study_run_update.workstream_id != workstream_id
        || study_continuation_state.workstream_id != workstream_id
    {
        return Err(anyhow!("study convergence workstream mismatch for '{}'", workstream_id));
    }
    if registry.workspace_id != workspace_id
        || sweep.workspace_id != workspace_id
        || summary.workspace_id != workspace_id
        || study_decision.workspace_id != workspace_id
        || study_decision_basis.workspace_id != workspace_id
        || proposal.workspace_id != workspace_id
        || proposal_dispatch.workspace_id != workspace_id
        || study_run_update.workspace_id != workspace_id
        || study_continuation_state.workspace_id != workspace_id
    {
        return Err(anyhow!("study convergence workspace mismatch for '{}'", workspace_id));
    }
    if registry.session_id != sweep.session_id
        || registry.session_id != summary.session_id
        || registry.session_id != study_decision.session_id
        || registry.session_id != study_decision_basis.session_id
        || registry.session_id != proposal.session_id
        || registry.session_id != proposal_dispatch.session_id
        || registry.session_id != study_run_update.session_id
        || registry.session_id != study_continuation_state.session_id
    {
        return Err(anyhow!(
            "study convergence session mismatch for study {}",
            registry.study_id
        ));
    }
    if !(registry.same_beagle_owned_identity
        && sweep.same_beagle_owned_identity
        && summary.same_beagle_owned_identity
        && study_decision.same_beagle_owned_identity
        && study_decision_basis.same_beagle_owned_identity
        && proposal.same_beagle_owned_identity
        && proposal_dispatch.same_beagle_owned_identity
        && study_run_update.same_beagle_owned_identity
        && study_continuation_state.same_beagle_owned_identity)
    {
        return Err(anyhow!("study convergence requires preserved Beagle-owned identity"));
    }
    Ok(())
}

fn evidence_refs(data_dir: &Path, workspace_id: &str) -> Vec<StudyEvidenceRef> {
    let base = workspace_plane_dir(data_dir);
    vec![
        StudyEvidenceRef {
            ref_id: "study-registry".to_string(),
            ref_kind: "workspace-plane-json".to_string(),
            locator: base
                .join("study-registry")
                .join(format!("{}.json", sanitize_component(workspace_id)))
                .display()
                .to_string(),
            summary: "Registry tying the study to one workstream, one workspace, and one session.".to_string(),
        },
        StudyEvidenceRef {
            ref_id: "study-sweep".to_string(),
            ref_kind: "workspace-plane-json".to_string(),
            locator: base
                .join("study-sweep")
                .join(format!("{}.json", sanitize_component(workspace_id)))
                .display()
                .to_string(),
            summary: "Sweep graph enumerating baseline and variant bindings for the study.".to_string(),
        },
        StudyEvidenceRef {
            ref_id: "comparative-result-summary".to_string(),
            ref_kind: "workspace-plane-json".to_string(),
            locator: base
                .join("comparative-result-summary")
                .join(format!("{}.json", sanitize_component(workspace_id)))
                .display()
                .to_string(),
            summary: "Comparative summary with latest diff categories and the union of all changed categories.".to_string(),
        },
        StudyEvidenceRef {
            ref_id: "study-decision-basis".to_string(),
            ref_kind: "workspace-plane-json".to_string(),
            locator: base
                .join("study-decision-basis")
                .join(format!("{}.json", sanitize_component(workspace_id)))
                .display()
                .to_string(),
            summary: "Decision basis that recorded the best-scoring variant before the convergence assessment.".to_string(),
        },
        StudyEvidenceRef {
            ref_id: "study-run-update".to_string(),
            ref_kind: "workspace-plane-json".to_string(),
            locator: base
                .join("study-run-update")
                .join(format!("{}.json", sanitize_component(workspace_id)))
                .display()
                .to_string(),
            summary: "Continuation update that shows the follow-on run count and result-only latest diff.".to_string(),
        },
        StudyEvidenceRef {
            ref_id: "study-continuation-state".to_string(),
            ref_kind: "workspace-plane-json".to_string(),
            locator: base
                .join("study-continuation-state")
                .join(format!("{}.json", sanitize_component(workspace_id)))
                .display()
                .to_string(),
            summary: "Continuation state that proves the approved proposal was dispatched and recovered after restart.".to_string(),
        },
        StudyEvidenceRef {
            ref_id: "study-proposal-dispatch".to_string(),
            ref_kind: "workspace-plane-json".to_string(),
            locator: base
                .join("study-proposal-dispatch")
                .join(format!("{}.json", sanitize_component(workspace_id)))
                .display()
                .to_string(),
            summary: "Proposal dispatch binding the approved next run to the same study and same Beagle-owned identity.".to_string(),
        },
    ]
}

pub fn write_study_convergence(
    data_dir: &Path,
    workspace_id: &str,
    convergence: &StudyConvergence,
) -> anyhow::Result<()> {
    write_json(study_convergence_path(data_dir, workspace_id), convergence)
}

pub fn write_variant_promotion_decision(
    data_dir: &Path,
    workspace_id: &str,
    decision: &VariantPromotionDecision,
) -> anyhow::Result<()> {
    write_json(variant_promotion_decision_path(data_dir, workspace_id), decision)
}

pub fn write_study_closeout_summary(
    data_dir: &Path,
    workspace_id: &str,
    summary: &StudyCloseoutSummary,
) -> anyhow::Result<()> {
    write_json(study_closeout_summary_path(data_dir, workspace_id), summary)
}

pub fn read_study_convergence(
    data_dir: &Path,
    workspace_id: &str,
) -> anyhow::Result<Option<StudyConvergence>> {
    read_json(study_convergence_path(data_dir, workspace_id))
}

pub fn read_variant_promotion_decision(
    data_dir: &Path,
    workspace_id: &str,
) -> anyhow::Result<Option<VariantPromotionDecision>> {
    read_json(variant_promotion_decision_path(data_dir, workspace_id))
}

pub fn read_study_closeout_summary(
    data_dir: &Path,
    workspace_id: &str,
) -> anyhow::Result<Option<StudyCloseoutSummary>> {
    read_json(study_closeout_summary_path(data_dir, workspace_id))
}

fn study_convergence_path(data_dir: &Path, workspace_id: &str) -> PathBuf {
    workspace_plane_dir(data_dir)
        .join("study-convergence")
        .join(format!("{}.json", sanitize_component(workspace_id)))
}

fn variant_promotion_decision_path(data_dir: &Path, workspace_id: &str) -> PathBuf {
    workspace_plane_dir(data_dir)
        .join("variant-promotion-decision")
        .join(format!("{}.json", sanitize_component(workspace_id)))
}

fn study_closeout_summary_path(data_dir: &Path, workspace_id: &str) -> PathBuf {
    workspace_plane_dir(data_dir)
        .join("study-closeout-summary")
        .join(format!("{}.json", sanitize_component(workspace_id)))
}

fn write_json<T: Serialize>(path: PathBuf, value: &T) -> anyhow::Result<()> {
    if let Some(parent) = path.parent() {
        fs::create_dir_all(parent)
            .with_context(|| format!("failed to create dir {}", parent.display()))?;
    }
    let body = serde_json::to_string_pretty(value)?;
    fs::write(&path, body).with_context(|| format!("failed to write {}", path.display()))
}

fn read_json<T>(path: PathBuf) -> anyhow::Result<Option<T>>
where
    T: for<'de> Deserialize<'de>,
{
    if !path.exists() {
        return Ok(None);
    }
    let body = fs::read_to_string(&path)
        .with_context(|| format!("failed to read {}", path.display()))?;
    let value = serde_json::from_str::<T>(&body)
        .with_context(|| format!("failed to parse {}", path.display()))?;
    Ok(Some(value))
}

fn sanitize_component(value: &str) -> String {
    let sanitized = value
        .trim()
        .chars()
        .map(|character| {
            if character.is_ascii_alphanumeric() || character == '-' || character == '_' {
                character
            } else {
                '-'
            }
        })
        .collect::<String>();
    let compact = sanitized
        .split('-')
        .filter(|part| !part.is_empty())
        .collect::<Vec<_>>()
        .join("-");
    if compact.is_empty() {
        "value".to_string()
    } else {
        compact
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use chrono::Utc;
    use std::time::{SystemTime, UNIX_EPOCH};

    fn sample_variant(run_id: &str, variant_id: &str, variant_label: &str) -> StudySweepVariant {
        StudySweepVariant {
            variant_id: variant_id.to_string(),
            variant_label: variant_label.to_string(),
            variant_kind: "direct".to_string(),
            source_run_id: Some("run-source".to_string()),
            run_id: run_id.to_string(),
            run_label: variant_label.to_string(),
            selected_subagent_id: "subagent".to_string(),
            task_family: "task".to_string(),
            compute_profile_id: "cpu-short-v1".to_string(),
            replay_mode: Some("bounded-workbench-replay".to_string()),
            compiler_profile_id: Some("default".to_string()),
            graphrag_query_mode: Some("local".to_string()),
            temporal_truth_view: Some("both".to_string()),
            recipe_kind: Some("recipe".to_string()),
            experiment_id: Some("experiment".to_string()),
        }
    }

    #[test]
    fn sanitize_component_compacts_separator_runs() {
        assert_eq!(sanitize_component(" Study  Convergence "), "Study-Convergence");
    }

    #[test]
    fn should_stop_study_requires_result_only_and_thresholds() {
        let update = StudyRunUpdate {
            phase: STUDY_CONVERGENCE_PHASE.to_string(),
            contract_kind: "study-run-update".to_string(),
            contract_version: STUDY_CONVERGENCE_VERSION.to_string(),
            update_id: "update-1".to_string(),
            proposal_dispatch_id: "dispatch-1".to_string(),
            study_decision_id: "decision-1".to_string(),
            next_run_proposal_id: "proposal-1".to_string(),
            study_id: "study-1".to_string(),
            workstream_id: "workstream-1".to_string(),
            workspace_id: "workspace-1".to_string(),
            session_id: "session-1".to_string(),
            same_beagle_owned_identity: true,
            previous_run_count: 10,
            updated_run_count: 11,
            previous_variant_count: 10,
            updated_variant_count: 11,
            previous_compared_run_count: 10,
            updated_compared_run_count: 11,
            dispatched_run_id: "run-2".to_string(),
            dispatched_run_label: "run-2".to_string(),
            dispatched_variant_id: "variant-2".to_string(),
            dispatched_variant_label: "variant-2".to_string(),
            approved_by: "operator".to_string(),
            approved_compute_profile_id: "cpu-short-v1".to_string(),
            proposal_state: "proposal-approved".to_string(),
            dispatch_state: "succeeded".to_string(),
            run_state: "succeeded".to_string(),
            study_state: "study-updated".to_string(),
            study_registry_id: "study-1".to_string(),
            study_dag_id: "study-1-dag".to_string(),
            study_sweep_id: "study-1-sweep".to_string(),
            comparative_result_summary_id: "study-1-summary".to_string(),
            result_binding_id: "binding-1".to_string(),
            run_result_identity_receipt_id: "receipt-1".to_string(),
            run_scoped_publication_id: "publication-1".to_string(),
            deterministic_result_binding_id: "deterministic-1".to_string(),
            latest_run_diff_categories: vec!["result".to_string()],
            changed_categories_union: vec!["code".to_string(), "result".to_string()],
            evidence_refs: Vec::new(),
            note: "note".to_string(),
        };
        let basis = StudyDecisionBasis {
            phase: "B26.2".to_string(),
            contract_kind: "study-decision-basis".to_string(),
            contract_version: "beagle-study-decision-basis-v1".to_string(),
            basis_id: "basis-1".to_string(),
            study_id: "study-1".to_string(),
            workstream_id: "workstream-1".to_string(),
            workspace_id: "workspace-1".to_string(),
            session_id: "session-1".to_string(),
            same_beagle_owned_identity: true,
            generated_at: Utc::now(),
            study_decision_id: "decision-1".to_string(),
            baseline_run_id: "run-1".to_string(),
            latest_run_id: "run-2".to_string(),
            registry_run_count: 11,
            sweep_variant_count: 11,
            compared_run_count: 10,
            successful_run_count: 11,
            failed_run_count: 0,
            latest_run_diff_categories: vec!["result".to_string()],
            changed_categories_union: vec!["code".to_string(), "result".to_string()],
            best_run_id: "run-1".to_string(),
            best_variant_id: "variant-1".to_string(),
            best_run_label: "run-1".to_string(),
            best_variant_label: "baseline".to_string(),
            best_run_score: 140,
            best_run_reason: "baseline led".to_string(),
            recommended_action: "rerun-variant".to_string(),
            evidence_refs: Vec::new(),
            note: "note".to_string(),
        };
        let summary = ComparativeResultSummary {
            phase: "B26.1".to_string(),
            contract_kind: "comparative-result-summary".to_string(),
            contract_version: "beagle-comparative-result-summary-v1".to_string(),
            comparative_result_summary_id: "summary-1".to_string(),
            study_id: "study-1".to_string(),
            workstream_id: "workstream-1".to_string(),
            workspace_id: "workspace-1".to_string(),
            session_id: "session-1".to_string(),
            same_beagle_owned_identity: true,
            generated_at: Utc::now(),
            baseline_run_id: "run-1".to_string(),
            compared_run_count: 10,
            changed_categories_union: vec!["code".to_string(), "result".to_string()],
            latest_run_diff_categories: Some(vec!["result".to_string()]),
            runs: Vec::new(),
            note: "note".to_string(),
        };

        assert!(should_stop_study(&update, &basis, &summary));
    }

    #[test]
    fn archive_variants_excludes_promoted_variant() {
        let sweep = StudySweep {
            phase: "B26.1".to_string(),
            contract_kind: "study-sweep".to_string(),
            contract_version: "beagle-study-sweep-v1".to_string(),
            study_sweep_id: "study-sweep-1".to_string(),
            study_id: "study-1".to_string(),
            workstream_id: "workstream-1".to_string(),
            workspace_id: "workspace-1".to_string(),
            session_id: "session-1".to_string(),
            same_beagle_owned_identity: true,
            generated_at: Utc::now(),
            baseline_variant_id: "variant-1".to_string(),
            variant_count: 2,
            run_count: 2,
            variants: vec![
                sample_variant("run-1", "variant-1", "baseline"),
                sample_variant("run-2", "variant-2", "replay"),
            ],
            note: "note".to_string(),
        };

        let archived = archived_variants(&sweep, "variant-1");
        assert_eq!(archived.len(), 1);
        assert_eq!(archived[0].0, "variant-2");
        assert_eq!(archived[0].1, "replay");
    }

    #[test]
    fn write_and_read_roundtrip_paths_are_stable() {
        let mut data_dir = std::env::temp_dir();
        let unique = SystemTime::now()
            .duration_since(UNIX_EPOCH)
            .expect("system time")
            .as_nanos();
        data_dir.push(format!("beagle-study-convergence-test-{}", unique));
        std::fs::create_dir_all(&data_dir).expect("tempdir");
        let convergence = StudyConvergence {
            phase: STUDY_CONVERGENCE_PHASE.to_string(),
            contract_kind: STUDY_CONVERGENCE_KIND.to_string(),
            contract_version: STUDY_CONVERGENCE_VERSION.to_string(),
            convergence_id: "study-convergence-1".to_string(),
            study_id: "study-1".to_string(),
            workstream_id: "workstream-1".to_string(),
            workspace_id: "workspace-1".to_string(),
            session_id: "session-1".to_string(),
            same_beagle_owned_identity: true,
            generated_at: Utc::now(),
            study_registry_id: "study-1".to_string(),
            study_dag_id: "study-1-dag".to_string(),
            study_sweep_id: "study-1-sweep".to_string(),
            comparative_result_summary_id: "study-1-summary".to_string(),
            study_decision_id: "decision-1".to_string(),
            study_decision_basis_id: "basis-1".to_string(),
            study_proposal_dispatch_id: "dispatch-1".to_string(),
            study_run_update_id: "update-1".to_string(),
            study_continuation_state_id: "state-1".to_string(),
            next_run_proposal_id: "proposal-1".to_string(),
            registry_run_count: 11,
            registry_variant_count: 11,
            decision_basis_compared_run_count: 10,
            updated_run_count: 11,
            updated_variant_count: 11,
            updated_compared_run_count: 11,
            successful_run_count: 11,
            failed_run_count: 0,
            latest_run_diff_categories: vec!["result".to_string()],
            changed_categories_union: vec!["result".to_string()],
            best_run_id: "run-1".to_string(),
            best_variant_id: "variant-1".to_string(),
            best_run_label: "run-1".to_string(),
            best_variant_label: "baseline".to_string(),
            best_variant_kind: "baseline".to_string(),
            best_compute_profile_id: "cpu-short-v1".to_string(),
            best_run_score: 140,
            best_run_reason: "baseline led".to_string(),
            prior_recommended_action: "rerun-variant".to_string(),
            convergence_state: "converged".to_string(),
            enough_evidence_to_stop: true,
            recommended_action: "stop-study".to_string(),
            decision_basis_summary: "summary".to_string(),
            evidence_refs: Vec::new(),
            note: "note".to_string(),
        };
        let promotion = VariantPromotionDecision {
            phase: STUDY_CONVERGENCE_PHASE.to_string(),
            contract_kind: VARIANT_PROMOTION_DECISION_KIND.to_string(),
            contract_version: VARIANT_PROMOTION_DECISION_VERSION.to_string(),
            decision_id: "variant-promotion-1".to_string(),
            study_id: "study-1".to_string(),
            workstream_id: "workstream-1".to_string(),
            workspace_id: "workspace-1".to_string(),
            session_id: "session-1".to_string(),
            same_beagle_owned_identity: true,
            generated_at: Utc::now(),
            study_convergence_id: convergence.convergence_id.clone(),
            study_convergence_state: "converged".to_string(),
            decision_action: "promote-variant".to_string(),
            promoted_variant_id: "variant-1".to_string(),
            promoted_variant_label: "baseline".to_string(),
            promoted_variant_kind: "baseline".to_string(),
            promoted_run_id: "run-1".to_string(),
            promoted_run_label: "run-1".to_string(),
            promoted_compute_profile_id: "cpu-short-v1".to_string(),
            archived_variant_count: 1,
            archived_variant_ids: vec!["variant-2".to_string()],
            archived_variant_labels: vec!["replay".to_string()],
            archived_variant_kinds: vec!["direct".to_string()],
            operator_review_required: true,
            decision_basis_summary: "summary".to_string(),
            evidence_refs: Vec::new(),
            note: "note".to_string(),
        };
        let closeout = StudyCloseoutSummary {
            phase: STUDY_CONVERGENCE_PHASE.to_string(),
            contract_kind: STUDY_CLOSEOUT_SUMMARY_KIND.to_string(),
            contract_version: STUDY_CLOSEOUT_SUMMARY_VERSION.to_string(),
            closeout_summary_id: "closeout-1".to_string(),
            study_id: "study-1".to_string(),
            workstream_id: "workstream-1".to_string(),
            workspace_id: "workspace-1".to_string(),
            session_id: "session-1".to_string(),
            same_beagle_owned_identity: true,
            generated_at: Utc::now(),
            study_convergence_id: convergence.convergence_id.clone(),
            variant_promotion_decision_id: promotion.decision_id.clone(),
            final_study_state: "converged".to_string(),
            final_comparative_decision: "stop-study".to_string(),
            final_variant_promotion_state: "promote-variant".to_string(),
            total_runs: 11,
            total_variants: 11,
            compared_run_count: 10,
            successful_run_count: 11,
            failed_run_count: 0,
            promoted_variant_id: "variant-1".to_string(),
            promoted_variant_label: "baseline".to_string(),
            promoted_run_id: "run-1".to_string(),
            promoted_run_label: "run-1".to_string(),
            archived_variant_count: 1,
            archived_variant_ids: vec!["variant-2".to_string()],
            archived_variant_labels: vec!["replay".to_string()],
            archived_variant_kinds: vec!["direct".to_string()],
            operator_review_required: true,
            final_decision_basis_summary: "summary".to_string(),
            evidence_refs: Vec::new(),
            note: "note".to_string(),
        };

        write_study_convergence(&data_dir, "workspace-1", &convergence).expect("write convergence");
        write_variant_promotion_decision(&data_dir, "workspace-1", &promotion)
            .expect("write promotion");
        write_study_closeout_summary(&data_dir, "workspace-1", &closeout).expect("write closeout");

        let convergence_read: StudyConvergence = read_json(study_convergence_path(&data_dir, "workspace-1"))
            .expect("read convergence")
            .expect("convergence value");
        let promotion_read: VariantPromotionDecision =
            read_json(variant_promotion_decision_path(&data_dir, "workspace-1"))
                .expect("read promotion")
                .expect("promotion value");
        let closeout_read: StudyCloseoutSummary = read_json(study_closeout_summary_path(&data_dir, "workspace-1"))
            .expect("read closeout")
            .expect("closeout value");

        assert_eq!(convergence_read.convergence_state, "converged");
        assert_eq!(promotion_read.decision_action, "promote-variant");
        assert_eq!(closeout_read.final_comparative_decision, "stop-study");

        std::fs::remove_dir_all(&data_dir).expect("cleanup");
    }
}
