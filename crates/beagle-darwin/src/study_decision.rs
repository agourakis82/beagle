use crate::next_run_proposal::{
    build_next_run_proposal, write_next_run_proposal, NextRunProposal,
};
use crate::study_registry::{
    read_comparative_result_summary, read_study_registry, read_study_sweep, ComparativeResultSummary,
    StudyRegistry,
};
use crate::study_sweep::StudySweep;
use anyhow::{anyhow, Context};
use chrono::{DateTime, Utc};
use serde::{Deserialize, Serialize};
use std::collections::BTreeMap;
use std::fs;
use std::path::{Path, PathBuf};

pub const STUDY_DECISION_PHASE: &str = "B26.2";
pub const STUDY_DECISION_KIND: &str = "study-decision";
pub const STUDY_DECISION_VERSION: &str = "beagle-study-decision-v1";
pub const STUDY_DECISION_BASIS_KIND: &str = "study-decision-basis";
pub const STUDY_DECISION_BASIS_VERSION: &str = "beagle-study-decision-basis-v1";
pub const STUDY_DECISION_CONTINUE_SWEEP: &str = "continue-sweep";
pub const STUDY_DECISION_STOP_STUDY: &str = "stop-study";
pub const STUDY_DECISION_PROMOTE_VARIANT: &str = "promote-variant";
pub const STUDY_DECISION_ARCHIVE_VARIANT: &str = "archive-variant";
pub const STUDY_DECISION_RERUN_VARIANT: &str = "rerun-variant";

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
pub struct StudyEvidenceRef {
    pub ref_id: String,
    pub ref_kind: String,
    pub locator: String,
    pub summary: String,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
pub struct StudyDecisionBasis {
    pub phase: String,
    pub contract_kind: String,
    pub contract_version: String,
    pub basis_id: String,
    pub study_id: String,
    pub workstream_id: String,
    pub workspace_id: String,
    pub session_id: String,
    pub same_beagle_owned_identity: bool,
    pub generated_at: DateTime<Utc>,
    pub study_decision_id: String,
    pub baseline_run_id: String,
    pub latest_run_id: String,
    pub registry_run_count: usize,
    pub sweep_variant_count: usize,
    pub compared_run_count: usize,
    pub successful_run_count: usize,
    pub failed_run_count: usize,
    pub latest_run_diff_categories: Vec<String>,
    pub changed_categories_union: Vec<String>,
    pub best_run_id: String,
    pub best_variant_id: String,
    pub best_run_label: String,
    pub best_variant_label: String,
    pub best_run_score: u16,
    pub best_run_reason: String,
    pub recommended_action: String,
    pub evidence_refs: Vec<StudyEvidenceRef>,
    pub note: String,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
pub struct StudyDecision {
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
    pub study_decision_basis_id: String,
    pub recommended_action: String,
    pub recommended_next_variant_id: String,
    pub recommended_next_variant_label: String,
    pub recommended_next_compute_profile_id: String,
    pub recommended_next_run_label: String,
    pub operator_review_required: bool,
    pub next_run_proposal_id: String,
    pub decision_basis_summary: String,
    pub note: String,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
pub struct StudyDecisionEngineBundle {
    pub status: String,
    pub phase: String,
    pub study_registry: StudyRegistry,
    pub study_sweep: StudySweep,
    pub comparative_result_summary: ComparativeResultSummary,
    pub study_decision_basis: StudyDecisionBasis,
    pub study_decision: StudyDecision,
    pub next_run_proposal: NextRunProposal,
}

#[derive(Debug, Clone)]
struct VariantObservation {
    run_id: String,
    run_label: String,
    variant_id: String,
    variant_label: String,
    variant_kind: String,
    compute_profile_id: String,
    recipe_kind: Option<String>,
    experiment_id: Option<String>,
    replay_mode: Option<String>,
    source_run_id: Option<String>,
    source_dirty_state: String,
    changed_categories_count: usize,
    same_beagle_owned_identity: bool,
    score: u16,
    reason: String,
}

pub fn ensure_study_decision_engine(
    data_dir: &Path,
    workstream_id: &str,
    workspace_id: &str,
) -> anyhow::Result<StudyDecisionEngineBundle> {
    let study_registry = read_study_registry(data_dir, workspace_id)?
        .ok_or_else(|| anyhow!("study registry missing for workspace {}", workspace_id))?;
    let study_sweep = read_study_sweep(data_dir, workspace_id)?
        .ok_or_else(|| anyhow!("study sweep missing for workspace {}", workspace_id))?;
    let comparative_result_summary = read_comparative_result_summary(data_dir, workspace_id)?
        .ok_or_else(|| anyhow!("comparative result summary missing for workspace {}", workspace_id))?;

    validate_identity(
        workstream_id,
        workspace_id,
        &study_registry,
        &study_sweep,
        &comparative_result_summary,
    )?;

    let generated_at = Utc::now();
    let observations = collect_variant_observations(
        &study_registry,
        &study_sweep,
        &comparative_result_summary,
    )?;
    let best = select_best_variant(&observations)?;
    let latest_run_id = comparative_result_summary
        .runs
        .iter()
        .max_by_key(|run| run.published_result_job_id)
        .map(|run| run.run_id.clone())
        .unwrap_or_else(|| study_registry.baseline_run_id.clone());
    let latest_run_diff_categories = comparative_result_summary
        .latest_run_diff_categories
        .clone()
        .unwrap_or_default();
    let recommended_action = recommended_action(
        comparative_result_summary.compared_run_count,
        &latest_run_diff_categories,
        comparative_result_summary.changed_categories_union.as_slice(),
        &best,
    );
    let evidence_refs = evidence_refs(data_dir, workspace_id);
    let study_decision_basis = build_study_decision_basis(
        &study_registry,
        &study_sweep,
        &comparative_result_summary,
        &best,
        latest_run_id.as_str(),
        latest_run_diff_categories,
        evidence_refs.clone(),
        recommended_action.as_str(),
        generated_at,
    );
    let study_decision_id = format!(
        "{}-study-decision",
        sanitize_component(study_registry.study_id.as_str())
    );
    let proposed_run_label = format!(
        "{}-rerun-{}",
        sanitize_component(study_registry.study_id.as_str()),
        sanitize_component(best.run_label.as_str())
    );
    let next_run_proposal = build_next_run_proposal(
        &study_registry,
        study_decision_id.as_str(),
        study_decision_basis.basis_id.as_str(),
        recommended_action.as_str(),
        proposed_run_label.as_str(),
        best.variant_id.as_str(),
        best.variant_label.as_str(),
        best.run_id.as_str(),
        best.compute_profile_id.as_str(),
        best.recipe_kind.as_deref(),
        best.experiment_id.as_deref(),
        best.replay_mode.as_deref(),
        evidence_refs.clone(),
        generated_at,
    );
    let study_decision = build_study_decision(
        &study_registry,
        &study_decision_basis,
        &next_run_proposal,
        &best,
        proposed_run_label.as_str(),
        recommended_action.as_str(),
        generated_at,
    );

    write_study_decision_basis(data_dir, workspace_id, &study_decision_basis)?;
    write_study_decision(data_dir, workspace_id, &study_decision)?;
    write_next_run_proposal(data_dir, workspace_id, &next_run_proposal)?;

    Ok(StudyDecisionEngineBundle {
        status: "ok".to_string(),
        phase: STUDY_DECISION_PHASE.to_string(),
        study_registry,
        study_sweep,
        comparative_result_summary,
        study_decision_basis,
        study_decision,
        next_run_proposal,
    })
}

pub fn read_study_decision(
    data_dir: &Path,
    workspace_id: &str,
) -> anyhow::Result<Option<StudyDecision>> {
    read_json(study_decision_path(data_dir, workspace_id))
}

pub fn read_study_decision_basis(
    data_dir: &Path,
    workspace_id: &str,
) -> anyhow::Result<Option<StudyDecisionBasis>> {
    read_json(study_decision_basis_path(data_dir, workspace_id))
}

fn build_study_decision_basis(
    study_registry: &StudyRegistry,
    study_sweep: &StudySweep,
    comparative_result_summary: &ComparativeResultSummary,
    best: &VariantObservation,
    latest_run_id: &str,
    latest_run_diff_categories: Vec<String>,
    evidence_refs: Vec<StudyEvidenceRef>,
    recommended_action: &str,
    generated_at: DateTime<Utc>,
) -> StudyDecisionBasis {
    StudyDecisionBasis {
        phase: STUDY_DECISION_PHASE.to_string(),
        contract_kind: STUDY_DECISION_BASIS_KIND.to_string(),
        contract_version: STUDY_DECISION_BASIS_VERSION.to_string(),
        basis_id: format!(
            "{}-study-decision-basis",
            sanitize_component(study_registry.study_id.as_str())
        ),
        study_id: study_registry.study_id.clone(),
        workstream_id: study_registry.workstream_id.clone(),
        workspace_id: study_registry.workspace_id.clone(),
        session_id: study_registry.session_id.clone(),
        same_beagle_owned_identity: study_registry.same_beagle_owned_identity
            && study_sweep.same_beagle_owned_identity
            && comparative_result_summary.same_beagle_owned_identity
            && best.same_beagle_owned_identity,
        generated_at,
        study_decision_id: format!(
            "{}-study-decision",
            sanitize_component(study_registry.study_id.as_str())
        ),
        baseline_run_id: study_registry.baseline_run_id.clone(),
        latest_run_id: latest_run_id.to_string(),
        registry_run_count: study_registry.run_count,
        sweep_variant_count: study_sweep.variant_count,
        compared_run_count: comparative_result_summary.compared_run_count,
        successful_run_count: successful_run_count(comparative_result_summary),
        failed_run_count: failed_run_count(comparative_result_summary),
        latest_run_diff_categories,
        changed_categories_union: comparative_result_summary.changed_categories_union.clone(),
        best_run_id: best.run_id.clone(),
        best_variant_id: best.variant_id.clone(),
        best_run_label: best.run_label.clone(),
        best_variant_label: best.variant_label.clone(),
        best_run_score: best.score,
        best_run_reason: best.reason.clone(),
        recommended_action: recommended_action.to_string(),
        evidence_refs,
        note: "B26.2 turns the study registry and comparative summary into a bounded decision basis: it explains why one variant is preferred, which evidence supports the choice, and which next run should be reviewed rather than auto-launched.".to_string(),
    }
}

fn build_study_decision(
    study_registry: &StudyRegistry,
    basis: &StudyDecisionBasis,
    proposal: &NextRunProposal,
    best: &VariantObservation,
    proposed_run_label: &str,
    recommended_action: &str,
    generated_at: DateTime<Utc>,
) -> StudyDecision {
    StudyDecision {
        phase: STUDY_DECISION_PHASE.to_string(),
        contract_kind: STUDY_DECISION_KIND.to_string(),
        contract_version: STUDY_DECISION_VERSION.to_string(),
        decision_id: basis.study_decision_id.clone(),
        study_id: study_registry.study_id.clone(),
        workstream_id: study_registry.workstream_id.clone(),
        workspace_id: study_registry.workspace_id.clone(),
        session_id: study_registry.session_id.clone(),
        same_beagle_owned_identity: basis.same_beagle_owned_identity,
        generated_at,
        study_decision_basis_id: basis.basis_id.clone(),
        recommended_action: recommended_action.to_string(),
        recommended_next_variant_id: best.variant_id.clone(),
        recommended_next_variant_label: best.variant_label.clone(),
        recommended_next_compute_profile_id: best.compute_profile_id.clone(),
        recommended_next_run_label: proposed_run_label.to_string(),
        operator_review_required: true,
        next_run_proposal_id: proposal.proposal_id.clone(),
        decision_basis_summary: format!(
            "baseline={} best={} score={} latest_diff={}",
            basis.baseline_run_id,
            basis.best_run_id,
            basis.best_run_score,
            basis.latest_run_diff_categories.join(",")
        ),
        note: "B26.2 exposes a bounded study decision only; the operator can review the basis and next-run proposal, but the runtime does not launch the run automatically.".to_string(),
    }
}

fn collect_variant_observations(
    registry: &StudyRegistry,
    sweep: &StudySweep,
    summary: &ComparativeResultSummary,
) -> anyhow::Result<Vec<VariantObservation>> {
    let sweep_by_run_id: BTreeMap<&str, &crate::study_sweep::StudySweepVariant> =
        sweep.variants.iter().map(|variant| (variant.run_id.as_str(), variant)).collect();
    let registry_by_run_id: BTreeMap<&str, &crate::study_registry::StudyRunRegistration> =
        registry.runs.iter().map(|run| (run.run_id.as_str(), run)).collect();

    let mut observations = Vec::new();
    for run_summary in &summary.runs {
        let Some(run) = registry_by_run_id.get(run_summary.run_id.as_str()) else {
            continue;
        };
        let Some(variant) = sweep_by_run_id.get(run_summary.run_id.as_str()) else {
            continue;
        };
        let changed_categories_count = run_summary.changed_categories_vs_baseline.len();
        let score = compute_variant_score(run_summary, changed_categories_count);
        observations.push(VariantObservation {
            run_id: run.run_id.clone(),
            run_label: run.run_label.clone(),
            variant_id: variant.variant_id.clone(),
            variant_label: variant.variant_label.clone(),
            variant_kind: variant.variant_kind.clone(),
            compute_profile_id: run.compute_profile_id.clone(),
            recipe_kind: run.recipe_kind.clone(),
            experiment_id: run.experiment_id.clone(),
            replay_mode: run.replay_mode.clone(),
            source_run_id: run.source_run_id.clone(),
            source_dirty_state: run.source_dirty_state.clone(),
            changed_categories_count,
            same_beagle_owned_identity: run.same_beagle_owned_identity
                && run_summary.same_beagle_owned_identity,
            score,
            reason: format!(
                "changed_categories={} replay_mode={} source_dirty_state={} identity={}",
                changed_categories_count,
                run_summary.replay_mode.as_deref().unwrap_or("none"),
                run_summary.source_dirty_state,
                run_summary.same_beagle_owned_identity
            ),
        });
    }

    if observations.is_empty() {
        return Err(anyhow!("no variant observations available for study {}", registry.study_id));
    }

    Ok(observations)
}

fn select_best_variant(observations: &[VariantObservation]) -> anyhow::Result<VariantObservation> {
    observations
        .iter()
        .cloned()
        .max_by(|left, right| {
            left.score
                .cmp(&right.score)
                .then_with(|| right.changed_categories_count.cmp(&left.changed_categories_count))
                .then_with(|| left.variant_kind.cmp(&right.variant_kind))
                .then_with(|| left.run_label.cmp(&right.run_label))
        })
        .ok_or_else(|| anyhow!("unable to select best variant observation"))
}

fn recommended_action(
    compared_run_count: usize,
    latest_run_diff_categories: &[String],
    changed_categories_union: &[String],
    best: &VariantObservation,
) -> String {
    if latest_run_diff_categories.len() == 1 && latest_run_diff_categories[0] == "result" {
        return STUDY_DECISION_RERUN_VARIANT.to_string();
    }
    if changed_categories_union.is_empty() {
        return STUDY_DECISION_STOP_STUDY.to_string();
    }
    if compared_run_count >= 3 && best.changed_categories_count == 0 {
        return STUDY_DECISION_PROMOTE_VARIANT.to_string();
    }
    if changed_categories_union.iter().any(|category| {
        matches!(
            category.as_str(),
            "code" | "config" | "environment"
        )
    }) {
        return STUDY_DECISION_CONTINUE_SWEEP.to_string();
    }
    STUDY_DECISION_ARCHIVE_VARIANT.to_string()
}

fn compute_variant_score(
    run_summary: &crate::study_registry::ComparativeRunSummary,
    changed_categories_count: usize,
) -> u16 {
    let mut score: i32 = 100;
    score -= (changed_categories_count as i32) * 15;
    if changed_categories_count == 0 {
        score += 20;
    }
    if run_summary.run_role == "baseline" || run_summary.run_role == "source" {
        score += 10;
    }
    if run_summary.same_beagle_owned_identity {
        score += 10;
    } else {
        score -= 100;
    }
    if run_summary.source_dirty_state == "clean" {
        score += 5;
    } else if run_summary.source_dirty_state == "dirty" {
        score -= 5;
    }
    if run_summary.replay_mode.is_some() {
        score += 5;
    }
    score.clamp(0, u16::MAX as i32) as u16
}

fn successful_run_count(summary: &ComparativeResultSummary) -> usize {
    summary
        .runs
        .iter()
        .filter(|run| run.changed_categories_vs_baseline.is_empty() || run.same_beagle_owned_identity)
        .count()
}

fn failed_run_count(summary: &ComparativeResultSummary) -> usize {
    summary
        .runs
        .iter()
        .filter(|run| !run.same_beagle_owned_identity)
        .count()
}

fn validate_identity(
    workstream_id: &str,
    workspace_id: &str,
    registry: &StudyRegistry,
    sweep: &StudySweep,
    summary: &ComparativeResultSummary,
) -> anyhow::Result<()> {
    if registry.workstream_id != workstream_id {
        return Err(anyhow!(
            "study registry workstream mismatch: expected '{}' but found '{}'",
            workstream_id,
            registry.workstream_id
        ));
    }
    if registry.workspace_id != workspace_id {
        return Err(anyhow!(
            "study registry workspace mismatch: expected '{}' but found '{}'",
            workspace_id,
            registry.workspace_id
        ));
    }
    if sweep.workstream_id != workstream_id || summary.workstream_id != workstream_id {
        return Err(anyhow!(
            "study decision workstream mismatch for '{}'",
            workstream_id
        ));
    }
    if sweep.workspace_id != workspace_id || summary.workspace_id != workspace_id {
        return Err(anyhow!(
            "study decision workspace mismatch for '{}'",
            workspace_id
        ));
    }
    if registry.session_id != sweep.session_id || registry.session_id != summary.session_id {
        return Err(anyhow!(
            "study decision session mismatch for study {}",
            registry.study_id
        ));
    }
    if !(registry.same_beagle_owned_identity
        && sweep.same_beagle_owned_identity
        && summary.same_beagle_owned_identity)
    {
        return Err(anyhow!(
            "study decision requires preserved Beagle-owned identity"
        ));
    }
    Ok(())
}

fn evidence_refs(data_dir: &Path, workspace_id: &str) -> Vec<StudyEvidenceRef> {
    let base = crate::workspace_plane::workspace_plane_dir(data_dir);
    vec![
        StudyEvidenceRef {
            ref_id: "study-registry".to_string(),
            ref_kind: "workspace-plane-json".to_string(),
            locator: base
                .join("study-registry")
                .join(format!("{}.json", sanitize_component(workspace_id)))
                .display()
                .to_string(),
            summary: "Canonical registry tying the study to one workstream, one workspace, one session, and the related run set.".to_string(),
        },
        StudyEvidenceRef {
            ref_id: "study-sweep".to_string(),
            ref_kind: "workspace-plane-json".to_string(),
            locator: base
                .join("study-sweep")
                .join(format!("{}.json", sanitize_component(workspace_id)))
                .display()
                .to_string(),
            summary: "Sweep variant graph with baseline, replay, branch-fork, and direct variants bound to canonical runs.".to_string(),
        },
        StudyEvidenceRef {
            ref_id: "comparative-result-summary".to_string(),
            ref_kind: "workspace-plane-json".to_string(),
            locator: base
                .join("comparative-result-summary")
                .join(format!("{}.json", sanitize_component(workspace_id)))
                .display()
                .to_string(),
            summary: "Comparative summary with union categories and the latest diff categories used for the decision basis.".to_string(),
        },
        StudyEvidenceRef {
            ref_id: "run-diff".to_string(),
            ref_kind: "workspace-plane-json".to_string(),
            locator: base
                .join("run-diff")
                .join(format!("{}.json", sanitize_component(workspace_id)))
                .display()
                .to_string(),
            summary: "Latest run diff used to isolate whether the most recent change was code, config, environment, or result-only.".to_string(),
        },
    ]
}

pub(crate) fn write_study_decision_basis(
    data_dir: &Path,
    workspace_id: &str,
    basis: &StudyDecisionBasis,
) -> anyhow::Result<()> {
    write_json(study_decision_basis_path(data_dir, workspace_id), basis)
}

pub(crate) fn write_study_decision(
    data_dir: &Path,
    workspace_id: &str,
    decision: &StudyDecision,
) -> anyhow::Result<()> {
    write_json(study_decision_path(data_dir, workspace_id), decision)
}

fn study_decision_path(data_dir: &Path, workspace_id: &str) -> PathBuf {
    crate::workspace_plane::workspace_plane_dir(data_dir)
        .join("study-decision")
        .join(format!("{}.json", sanitize_component(workspace_id)))
}

fn study_decision_basis_path(data_dir: &Path, workspace_id: &str) -> PathBuf {
    crate::workspace_plane::workspace_plane_dir(data_dir)
        .join("study-decision-basis")
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
    use crate::study_registry::{ComparativeResultSummary, ComparativeRunSummary, StudyRegistry, StudyRunRegistration};
    use crate::study_sweep::{StudySweep, StudySweepVariant};
    use chrono::Utc;

    fn registry() -> StudyRegistry {
        StudyRegistry {
            phase: "B26.1".to_string(),
            contract_kind: "study-registry".to_string(),
            contract_version: "beagle-study-registry-v1".to_string(),
            study_id: "study".to_string(),
            study_label: "study-label".to_string(),
            workstream_id: "workstream".to_string(),
            workspace_id: "workspace".to_string(),
            session_id: "session".to_string(),
            same_beagle_owned_identity: true,
            created_at: Utc::now(),
            updated_at: Utc::now(),
            baseline_run_id: "run-1".to_string(),
            run_count: 2,
            variant_count: 2,
            run_ids: vec!["run-1".to_string(), "run-2".to_string()],
            variant_ids: vec!["variant-1".to_string(), "variant-2".to_string()],
            runs: vec![
                StudyRunRegistration {
                    run_id: "run-1".to_string(),
                    run_label: "baseline".to_string(),
                    submitted_job_id: 1,
                    published_result_job_id: 1,
                    selected_subagent_id: "experiments".to_string(),
                    task_family: "experiments".to_string(),
                    compute_profile_id: "cpu".to_string(),
                    recipe_kind: None,
                    experiment_id: None,
                    source_branch: None,
                    source_commit: None,
                    source_dirty_state: "unknown".to_string(),
                    source_fingerprint: None,
                    replay_mode: Some("bounded-workbench-replay".to_string()),
                    source_run_id: None,
                    replay_execution_id: None,
                    run_role: "baseline".to_string(),
                    same_beagle_owned_identity: true,
                },
                StudyRunRegistration {
                    run_id: "run-2".to_string(),
                    run_label: "variant".to_string(),
                    submitted_job_id: 2,
                    published_result_job_id: 2,
                    selected_subagent_id: "experiments".to_string(),
                    task_family: "experiments".to_string(),
                    compute_profile_id: "cpu".to_string(),
                    recipe_kind: None,
                    experiment_id: None,
                    source_branch: None,
                    source_commit: None,
                    source_dirty_state: "dirty".to_string(),
                    source_fingerprint: None,
                    replay_mode: Some("bounded-workbench-replay".to_string()),
                    source_run_id: Some("run-1".to_string()),
                    replay_execution_id: None,
                    run_role: "variant".to_string(),
                    same_beagle_owned_identity: true,
                },
            ],
            note: "note".to_string(),
        }
    }

    fn sweep() -> StudySweep {
        StudySweep {
            phase: "B26.1".to_string(),
            contract_kind: "study-sweep".to_string(),
            contract_version: "beagle-study-sweep-v1".to_string(),
            study_sweep_id: "study-study-sweep".to_string(),
            study_id: "study".to_string(),
            workstream_id: "workstream".to_string(),
            workspace_id: "workspace".to_string(),
            session_id: "session".to_string(),
            same_beagle_owned_identity: true,
            generated_at: Utc::now(),
            baseline_variant_id: "variant-1".to_string(),
            variant_count: 2,
            run_count: 2,
            variants: vec![
                StudySweepVariant {
                    variant_id: "variant-1".to_string(),
                    variant_label: "baseline".to_string(),
                    variant_kind: "baseline".to_string(),
                    source_run_id: None,
                    run_id: "run-1".to_string(),
                    run_label: "baseline".to_string(),
                    selected_subagent_id: "experiments".to_string(),
                    task_family: "experiments".to_string(),
                    compute_profile_id: "cpu".to_string(),
                    replay_mode: Some("bounded-workbench-replay".to_string()),
                    compiler_profile_id: None,
                    graphrag_query_mode: Some("local".to_string()),
                    temporal_truth_view: Some("both".to_string()),
                    recipe_kind: None,
                    experiment_id: None,
                },
                StudySweepVariant {
                    variant_id: "variant-2".to_string(),
                    variant_label: "variant".to_string(),
                    variant_kind: "direct".to_string(),
                    source_run_id: Some("run-1".to_string()),
                    run_id: "run-2".to_string(),
                    run_label: "variant".to_string(),
                    selected_subagent_id: "experiments".to_string(),
                    task_family: "experiments".to_string(),
                    compute_profile_id: "cpu".to_string(),
                    replay_mode: Some("bounded-workbench-replay".to_string()),
                    compiler_profile_id: None,
                    graphrag_query_mode: Some("local".to_string()),
                    temporal_truth_view: Some("both".to_string()),
                    recipe_kind: None,
                    experiment_id: None,
                },
            ],
            note: "note".to_string(),
        }
    }

    fn summary() -> ComparativeResultSummary {
        ComparativeResultSummary {
            phase: "B26.1".to_string(),
            contract_kind: "comparative-result-summary".to_string(),
            contract_version: "beagle-comparative-result-summary-v1".to_string(),
            comparative_result_summary_id: "study-comparative-result-summary".to_string(),
            study_id: "study".to_string(),
            workstream_id: "workstream".to_string(),
            workspace_id: "workspace".to_string(),
            session_id: "session".to_string(),
            same_beagle_owned_identity: true,
            generated_at: Utc::now(),
            baseline_run_id: "run-1".to_string(),
            compared_run_count: 2,
            changed_categories_union: vec!["result".to_string()],
            latest_run_diff_categories: Some(vec!["result".to_string()]),
            runs: vec![
                ComparativeRunSummary {
                    run_id: "run-1".to_string(),
                    run_label: "baseline".to_string(),
                    run_role: "baseline".to_string(),
                    submitted_job_id: 1,
                    published_result_job_id: 1,
                    source_run_id: None,
                    replay_mode: Some("bounded-workbench-replay".to_string()),
                    source_branch: None,
                    source_commit: None,
                    source_dirty_state: "unknown".to_string(),
                    source_fingerprint: None,
                    changed_categories_vs_baseline: vec![],
                    same_beagle_owned_identity: true,
                },
                ComparativeRunSummary {
                    run_id: "run-2".to_string(),
                    run_label: "variant".to_string(),
                    run_role: "variant".to_string(),
                    submitted_job_id: 2,
                    published_result_job_id: 2,
                    source_run_id: Some("run-1".to_string()),
                    replay_mode: Some("bounded-workbench-replay".to_string()),
                    source_branch: None,
                    source_commit: None,
                    source_dirty_state: "dirty".to_string(),
                    source_fingerprint: None,
                    changed_categories_vs_baseline: vec!["result".to_string()],
                    same_beagle_owned_identity: true,
                },
            ],
            note: "note".to_string(),
        }
    }

    #[test]
    fn action_prefers_rerun_when_latest_diff_is_result_only() {
        let observations = collect_variant_observations(&registry(), &sweep(), &summary()).unwrap();
        let best = select_best_variant(&observations).unwrap();
        assert_eq!(best.variant_id, "variant-1");
        assert_eq!(
            recommended_action(2, &["result".to_string()], &["result".to_string()], &best),
            STUDY_DECISION_RERUN_VARIANT
        );
    }
}
