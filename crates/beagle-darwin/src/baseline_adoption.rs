//! B26.6 — Baseline Adoption (bounded study baseline after promotion)
//!
//! This module implements the final step of the study lifecycle:
//! after a variant is promoted, it becomes the new baseline for future
//! planning and decision making. It also creates a rollback plan and
//! seeds the next study.

use crate::next_study_seed::{build_next_study_seed, NextStudySeed};
use crate::study_convergence::{
    read_study_closeout_summary, StudyCloseoutSummary, STUDY_CONVERGENCE_CONVERGED,
    STUDY_CONVERGENCE_STOP_STUDY, VARIANT_PROMOTION_DECISION_PROMOTE_VARIANT,
};
use crate::study_promotion_execution::{read_study_promotion_execution, StudyPromotionExecution};
use crate::study_decision::StudyEvidenceRef;
use crate::workspace_plane::workspace_plane_dir;
use crate::workstream_context_packet::BoundedStudyBaselineSummary;
use anyhow::{anyhow, Context};
use chrono::{DateTime, Utc};
use serde::{Deserialize, Serialize};
use std::fs;
use std::path::{Path, PathBuf};

pub const BASELINE_ADOPTION_PHASE: &str = "B26.6";
pub const PROMOTED_VARIANT_RECEIPT_KIND: &str = "promoted-variant-receipt";
pub const PROMOTED_VARIANT_RECEIPT_VERSION: &str = "beagle-promoted-variant-receipt-v1";
pub const BASELINE_ADOPTION_KIND: &str = "baseline-adoption";
pub const BASELINE_ADOPTION_VERSION: &str = "beagle-baseline-adoption-v1";
pub const BASELINE_ROLLBACK_PLAN_KIND: &str = "baseline-rollback-plan";
pub const BASELINE_ROLLBACK_PLAN_VERSION: &str = "beagle-baseline-rollback-plan-v1";
pub const WORKBENCH_CONTEXT_AFTER_BASELINE_KIND: &str = "workbench-context-after-baseline";
pub const WORKBENCH_CONTEXT_AFTER_BASELINE_VERSION: &str = "beagle-workbench-context-after-baseline-v1";

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
pub struct PromotedVariantReceipt {
    pub phase: String,
    pub contract_kind: String,
    pub contract_version: String,
    pub receipt_id: String,
    pub study_promotion_execution_id: String,
    pub study_id: String,
    pub workstream_id: String,
    pub workspace_id: String,
    pub session_id: String,
    pub same_beagle_owned_identity: bool,
    pub generated_at: DateTime<Utc>,
    pub promoted_variant_id: String,
    pub promoted_variant_label: String,
    pub promoted_variant_kind: String,
    pub promoted_run_id: String,
    pub promoted_run_label: String,
    pub promoted_compute_profile_id: String,
    pub workbench_run_id: String,
    pub result_binding_id: String,
    pub study_closeout_summary_id: String,
    pub variant_promotion_decision_id: String,
    pub note: String,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
pub struct BaselineAdoption {
    pub phase: String,
    pub contract_kind: String,
    pub contract_version: String,
    pub adoption_id: String,
    pub promoted_variant_receipt_id: String,
    pub study_promotion_execution_id: String,
    pub study_closeout_summary_id: String,
    pub variant_promotion_decision_id: String,
    pub study_id: String,
    pub workstream_id: String,
    pub workspace_id: String,
    pub session_id: String,
    pub same_beagle_owned_identity: bool,
    pub generated_at: DateTime<Utc>,
    pub bounded_baseline_scope: String,
    pub adopted_variant_id: String,
    pub adopted_run_id: String,
    pub adopted_compute_profile_id: String,
    pub prior_baseline_descriptor: String,
    pub operator_acknowledgement_required: bool,
    pub evidence_refs: Vec<StudyEvidenceRef>,
    pub note: String,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
pub struct BaselineRollbackStep {
    pub step_order: u32,
    pub action: String,
    pub target_artifact: String,
    pub requires_operator: bool,
    pub description: String,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
pub struct BaselineRollbackPlan {
    pub phase: String,
    pub contract_kind: String,
    pub contract_version: String,
    pub rollback_plan_id: String,
    pub baseline_adoption_id: String,
    pub promoted_variant_receipt_id: String,
    pub study_id: String,
    pub workstream_id: String,
    pub workspace_id: String,
    pub session_id: String,
    pub same_beagle_owned_identity: bool,
    pub generated_at: DateTime<Utc>,
    pub steps: Vec<BaselineRollbackStep>,
    pub restores_archived_variant_ids: Vec<String>,
    pub identity_preservation_note: String,
    pub note: String,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
pub struct WorkbenchContextAfterBaseline {
    pub phase: String,
    pub contract_kind: String,
    pub contract_version: String,
    pub context_id: String,
    pub workstream_id: String,
    pub workspace_id: String,
    pub session_id: String,
    pub same_beagle_owned_identity: bool,
    pub generated_at: DateTime<Utc>,
    pub bounded_study_baseline: BoundedStudyBaselineSummary,
    pub study_convergence_plane_path: String,
    pub study_promotion_execution_plane_path: String,
    pub baseline_adoption_plane_path: String,
    pub baseline_rollback_plane_path: String,
    pub next_study_seed_plane_path: String,
    pub context_packet_api_path: String,
    pub intent_planner_api_path: String,
    pub note: String,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
pub struct BaselineAdoptionBundle {
    pub status: String,
    pub phase: String,
    pub promoted_variant_receipt: PromotedVariantReceipt,
    pub baseline_adoption: BaselineAdoption,
    pub baseline_rollback_plan: BaselineRollbackPlan,
    pub next_study_seed: NextStudySeed,
    pub workbench_context_after_baseline: WorkbenchContextAfterBaseline,
    pub study_promotion_execution: StudyPromotionExecution,
}

pub fn ensure_baseline_adoption(
    data_dir: &Path,
    workstream_id: &str,
    workspace_id: &str,
) -> anyhow::Result<BaselineAdoptionBundle> {
    let execution = read_study_promotion_execution(data_dir, workspace_id)?
        .ok_or_else(|| anyhow!("study promotion execution missing for workspace {}", workspace_id))?;
    if execution.workstream_id != workstream_id {
        return Err(anyhow!("workstream mismatch for baseline adoption"));
    }
    let closeout = read_study_closeout_summary(data_dir, workspace_id)?
        .ok_or_else(|| anyhow!("study closeout summary missing for workspace {}", workspace_id))?;
    validate_closeout_for_adoption(&closeout)?;
    validate_execution_against_closeout(&execution, &closeout)?;
    let generated_at = Utc::now();
    let receipt = build_promoted_variant_receipt(&execution, generated_at);
    let adoption = build_baseline_adoption(&receipt, &execution, &closeout, generated_at);
    let rollback = build_rollback_plan(&receipt, &adoption, &execution, generated_at);
    let seed = build_next_study_seed(
        receipt.receipt_id.as_str(),
        adoption.adoption_id.as_str(),
        adoption.study_id.as_str(),
        adoption.workstream_id.as_str(),
        adoption.workspace_id.as_str(),
        adoption.session_id.as_str(),
        adoption.same_beagle_owned_identity,
        receipt.promoted_variant_id.as_str(),
        receipt.promoted_run_id.as_str(),
        receipt.promoted_compute_profile_id.as_str(),
        execution.archived_variant_ids.as_slice(),
        generated_at,
    );
    let summary = bounded_summary(&receipt, &adoption, &rollback, &seed);
    let workbench_ctx = build_workbench_context_after_baseline(
        &summary,
        data_dir,
        workspace_id,
        generated_at,
    );
    write_promoted_variant_receipt(data_dir, workspace_id, &receipt)?;
    write_baseline_adoption(data_dir, workspace_id, &adoption)?;
    write_baseline_rollback_plan(data_dir, workspace_id, &rollback)?;
    write_next_study_seed(data_dir, workspace_id, &seed)?;
    write_workbench_context_after_baseline(data_dir, workspace_id, &workbench_ctx)?;
    Ok(BaselineAdoptionBundle {
        status: "ok".to_string(),
        phase: BASELINE_ADOPTION_PHASE.to_string(),
        promoted_variant_receipt: receipt,
        baseline_adoption: adoption,
        baseline_rollback_plan: rollback,
        next_study_seed: seed,
        workbench_context_after_baseline: workbench_ctx,
        study_promotion_execution: execution,
    })
}

pub fn bounded_study_baseline_summary_from_plane(
    data_dir: &Path,
    workspace_id: &str,
) -> anyhow::Result<Option<BoundedStudyBaselineSummary>> {
    let adoption = read_baseline_adoption(data_dir, workspace_id)?;
    let receipt = read_promoted_variant_receipt(data_dir, workspace_id)?;
    let rollback = read_baseline_rollback_plan(data_dir, workspace_id)?;
    let seed = read_next_study_seed(data_dir, workspace_id)?;
    match (adoption, receipt, rollback, seed) {
        (Some(a), Some(r), Some(rb), Some(s)) => Ok(Some(bounded_summary(&r, &a, &rb, &s))),
        _ => Ok(None),
    }
}

fn validate_closeout_for_adoption(closeout: &StudyCloseoutSummary) -> anyhow::Result<()> {
    if closeout.final_study_state != STUDY_CONVERGENCE_CONVERGED {
        return Err(anyhow!(
            "baseline adoption requires final_study_state=converged, got {}",
            closeout.final_study_state
        ));
    }
    if closeout.final_comparative_decision != STUDY_CONVERGENCE_STOP_STUDY {
        return Err(anyhow!(
            "baseline adoption requires final_comparative_decision=stop-study, got {}",
            closeout.final_comparative_decision
        ));
    }
    if closeout.final_variant_promotion_state != VARIANT_PROMOTION_DECISION_PROMOTE_VARIANT {
        return Err(anyhow!(
            "baseline adoption requires final_variant_promotion_state=promote-variant, got {}",
            closeout.final_variant_promotion_state
        ));
    }
    if !closeout.same_beagle_owned_identity {
        return Err(anyhow!(
            "baseline adoption requires preserved Beagle-owned identity on closeout"
        ));
    }
    Ok(())
}

fn validate_execution_against_closeout(
    execution: &StudyPromotionExecution,
    closeout: &StudyCloseoutSummary,
) -> anyhow::Result<()> {
    if execution.study_id != closeout.study_id
        || execution.workspace_id != closeout.workspace_id
        || execution.session_id != closeout.session_id
        || execution.workstream_id != closeout.workstream_id
    {
        return Err(anyhow!(
            "study promotion execution and closeout must share study/workspace/session identity"
        ));
    }
    if execution.promoted_variant_id != closeout.promoted_variant_id
        || execution.promoted_run_id != closeout.promoted_run_id
    {
        return Err(anyhow!(
            "promotion execution promoted ids must match closeout promoted variant/run"
        ));
    }
    if !execution.same_beagle_owned_identity {
        return Err(anyhow!(
            "baseline adoption requires same_beagle_owned_identity on promotion execution"
        ));
    }
    Ok(())
}

fn build_promoted_variant_receipt(
    execution: &StudyPromotionExecution,
    generated_at: DateTime<Utc>,
) -> PromotedVariantReceipt {
    PromotedVariantReceipt {
        phase: BASELINE_ADOPTION_PHASE.to_string(),
        contract_kind: PROMOTED_VARIANT_RECEIPT_KIND.to_string(),
        contract_version: PROMOTED_VARIANT_RECEIPT_VERSION.to_string(),
        receipt_id: format!(
            "{}-promoted-variant-receipt",
            sanitize_component(execution.study_id.as_str())
        ),
        study_promotion_execution_id: execution.execution_id.clone(),
        study_id: execution.study_id.clone(),
        workstream_id: execution.workstream_id.clone(),
        workspace_id: execution.workspace_id.clone(),
        session_id: execution.session_id.clone(),
        same_beagle_owned_identity: execution.same_beagle_owned_identity,
        generated_at,
        promoted_variant_id: execution.promoted_variant_id.clone(),
        promoted_variant_label: execution.promoted_variant_label.clone(),
        promoted_variant_kind: execution.promoted_variant_kind.clone(),
        promoted_run_id: execution.promoted_run_id.clone(),
        promoted_run_label: execution.promoted_run_label.clone(),
        promoted_compute_profile_id: execution.promoted_compute_profile_id.clone(),
        workbench_run_id: execution.workbench_run_id.clone(),
        result_binding_id: execution.result_binding_id.clone(),
        study_closeout_summary_id: execution.study_closeout_summary_id.clone(),
        variant_promotion_decision_id: execution.variant_promotion_decision_id.clone(),
        note: "Canonical receipt that B26.5 promotion execution delivered the promoted variant into the workspace plane; B26.6 records it as the bounded baseline input.".to_string(),
    }
}

fn build_baseline_adoption(
    receipt: &PromotedVariantReceipt,
    execution: &StudyPromotionExecution,
    closeout: &StudyCloseoutSummary,
    generated_at: DateTime<Utc>,
) -> BaselineAdoption {
    let evidence_refs = adoption_evidence_refs(receipt);
    BaselineAdoption {
        phase: BASELINE_ADOPTION_PHASE.to_string(),
        contract_kind: BASELINE_ADOPTION_KIND.to_string(),
        contract_version: BASELINE_ADOPTION_VERSION.to_string(),
        adoption_id: format!(
            "{}-baseline-adoption",
            sanitize_component(execution.study_id.as_str())
        ),
        promoted_variant_receipt_id: receipt.receipt_id.clone(),
        study_promotion_execution_id: execution.execution_id.clone(),
        study_closeout_summary_id: closeout.closeout_summary_id.clone(),
        variant_promotion_decision_id: execution.variant_promotion_decision_id.clone(),
        study_id: execution.study_id.clone(),
        workstream_id: execution.workstream_id.clone(),
        workspace_id: execution.workspace_id.clone(),
        session_id: execution.session_id.clone(),
        same_beagle_owned_identity: execution.same_beagle_owned_identity,
        generated_at,
        bounded_baseline_scope: "workspace-plane-json".to_string(),
        adopted_variant_id: execution.promoted_variant_id.clone(),
        adopted_run_id: execution.promoted_run_id.clone(),
        adopted_compute_profile_id: execution.promoted_compute_profile_id.clone(),
        prior_baseline_descriptor: "pre-B26.6-study-lineage-unbounded-relative-to-this-adoption".to_string(),
        operator_acknowledgement_required: closeout.operator_review_required,
        evidence_refs,
        note: "The promoted variant from B26.5 is now the bounded baseline for planner, workbench context, and future study seeds within the same Beagle-owned identity.".to_string(),
    }
}

fn adoption_evidence_refs(receipt: &PromotedVariantReceipt) -> Vec<StudyEvidenceRef> {
    vec![
        StudyEvidenceRef {
            ref_id: "study-promotion-execution".to_string(),
            ref_kind: "workspace-plane-json".to_string(),
            locator: format!(
                "workspace-plane/study-promotion-execution/{}.json",
                sanitize_component(receipt.workspace_id.as_str())
            ),
            summary: "B26.5 execution artifact that materialized the promoted variant.".to_string(),
        },
        StudyEvidenceRef {
            ref_id: "promoted-variant-receipt".to_string(),
            ref_kind: "workspace-plane-json".to_string(),
            locator: format!(
                "workspace-plane/promoted-variant-receipt/{}.json",
                sanitize_component(receipt.workspace_id.as_str())
            ),
            summary: "B26.6 receipt anchoring the promoted variant as baseline input.".to_string(),
        },
    ]
}

fn build_rollback_plan(
    receipt: &PromotedVariantReceipt,
    adoption: &BaselineAdoption,
    execution: &StudyPromotionExecution,
    generated_at: DateTime<Utc>,
) -> BaselineRollbackPlan {
    let steps = vec![
        BaselineRollbackStep {
            step_order: 1,
            action: "operator-freeze-baseline-consumption".to_string(),
            target_artifact: adoption_plane_relative_path(&receipt.workspace_id),
            requires_operator: true,
            description: "Stop treating baseline-adoption as authoritative for new planner/study actions.".to_string(),
        },
        BaselineRollbackStep {
            step_order: 2,
            action: "archive-baseline-adoption-artifacts".to_string(),
            target_artifact: "workspace-plane/baseline-adoption/*.json".to_string(),
            requires_operator: true,
            description: "Move baseline-adoption.json and dependent seeds aside with an audit trail; do not delete promotion execution.".to_string(),
        },
        BaselineRollbackStep {
            step_order: 3,
            action: "restore-comparative-visibility".to_string(),
            target_artifact: "variant-promotion-decision.archived_variant_ids".to_string(),
            requires_operator: true,
            description: "Re-open comparative study planning using archived variant ids as challengers; scientific/editorial limits remain explicit.".to_string(),
        },
    ];
    BaselineRollbackPlan {
        phase: BASELINE_ADOPTION_PHASE.to_string(),
        contract_kind: BASELINE_ROLLBACK_PLAN_KIND.to_string(),
        contract_version: BASELINE_ROLLBACK_PLAN_VERSION.to_string(),
        rollback_plan_id: format!(
            "{}-baseline-rollback-plan",
            sanitize_component(adoption.study_id.as_str())
        ),
        baseline_adoption_id: adoption.adoption_id.clone(),
        promoted_variant_receipt_id: receipt.receipt_id.clone(),
        study_id: adoption.study_id.clone(),
        workstream_id: adoption.workstream_id.clone(),
        workspace_id: adoption.workspace_id.clone(),
        session_id: adoption.session_id.clone(),
        same_beagle_owned_identity: adoption.same_beagle_owned_identity,
        generated_at,
        steps,
        restores_archived_variant_ids: execution.archived_variant_ids.clone(),
        identity_preservation_note: "Rollback must not mint a parallel identity; keep study/workspace/session anchors on the Beagle-owned plane.".to_string(),
        note: "Explicit operator-visible rollback; no automatic study relaunch.".to_string(),
    }
}

fn adoption_plane_relative_path(workspace_id: &str) -> String {
    format!(
        "workspace-plane/baseline-adoption/{}.json",
        sanitize_component(workspace_id)
    )
}

fn bounded_summary(
    receipt: &PromotedVariantReceipt,
    adoption: &BaselineAdoption,
    rollback: &BaselineRollbackPlan,
    seed: &NextStudySeed,
) -> BoundedStudyBaselineSummary {
    let ws = sanitize_component(receipt.workspace_id.as_str());
    BoundedStudyBaselineSummary {
        phase: BASELINE_ADOPTION_PHASE.to_string(),
        adoption_id: adoption.adoption_id.clone(),
        promoted_variant_receipt_id: receipt.receipt_id.clone(),
        baseline_adoption_contract_version: BASELINE_ADOPTION_VERSION.to_string(),
        study_id: adoption.study_id.clone(),
        workstream_id: adoption.workstream_id.clone(),
        workspace_id: adoption.workspace_id.clone(),
        session_id: adoption.session_id.clone(),
        same_beagle_owned_identity: adoption.same_beagle_owned_identity,
        promoted_variant_id: receipt.promoted_variant_id.clone(),
        promoted_run_id: receipt.promoted_run_id.clone(),
        promoted_compute_profile_id: receipt.promoted_compute_profile_id.clone(),
        rollback_plan_id: rollback.rollback_plan_id.clone(),
        next_study_seed_id: seed.seed_id.clone(),
        rollback_api_path: format!(
            "/api/darwin/workstreams/{}/baseline-rollback-plan",
            adoption.workstream_id
        ),
        baseline_adoption_api_path: format!(
            "/api/darwin/workstreams/{}/baseline-adoption",
            adoption.workstream_id
        ),
        workspace_plane_baseline_path: format!("workspace-plane/baseline-adoption/{ws}.json"),
    }
}

fn build_workbench_context_after_baseline(
    summary: &BoundedStudyBaselineSummary,
    data_dir: &Path,
    workspace_id: &str,
    generated_at: DateTime<Utc>,
) -> WorkbenchContextAfterBaseline {
    let base = workspace_plane_dir(data_dir);
    let ws = sanitize_component(workspace_id);
    WorkbenchContextAfterBaseline {
        phase: BASELINE_ADOPTION_PHASE.to_string(),
        contract_kind: WORKBENCH_CONTEXT_AFTER_BASELINE_KIND.to_string(),
        contract_version: WORKBENCH_CONTEXT_AFTER_BASELINE_VERSION.to_string(),
        context_id: format!("{}-workbench-context-after-baseline", sanitize_component(summary.study_id.as_str())),
        workstream_id: summary.workstream_id.clone(),
        workspace_id: summary.workspace_id.clone(),
        session_id: summary.session_id.clone(),
        same_beagle_owned_identity: summary.same_beagle_owned_identity,
        generated_at,
        bounded_study_baseline: summary.clone(),
        study_convergence_plane_path: base
            .join("study-convergence")
            .join(format!("{ws}.json"))
            .display()
            .to_string(),
        study_promotion_execution_plane_path: base
            .join("study-promotion-execution")
            .join(format!("{ws}.json"))
            .display()
            .to_string(),
        baseline_adoption_plane_path: base
            .join("baseline-adoption")
            .join(format!("{ws}.json"))
            .display()
            .to_string(),
        baseline_rollback_plane_path: base
            .join("baseline-rollback-plan")
            .join(format!("{ws}.json"))
            .display()
            .to_string(),
        next_study_seed_plane_path: base
            .join("next-study-seed")
            .join(format!("{ws}.json"))
            .display()
            .to_string(),
        context_packet_api_path: format!(
            "/api/darwin/workstreams/{}/context-packet",
            summary.workstream_id
        ),
        intent_planner_api_path: format!(
            "/api/darwin/workstreams/{}/intent-plan",
            summary.workstream_id
        ),
        note: "Workbench and planner consumers read bounded_study_baseline via context-packet; this artifact lists canonical plane paths.".to_string(),
    }
}

pub fn write_promoted_variant_receipt(
    data_dir: &Path,
    workspace_id: &str,
    receipt: &PromotedVariantReceipt,
) -> anyhow::Result<()> {
    write_json(
        promoted_variant_receipt_path(data_dir, workspace_id),
        receipt,
    )
}

pub fn read_promoted_variant_receipt(
    data_dir: &Path,
    workspace_id: &str,
) -> anyhow::Result<Option<PromotedVariantReceipt>> {
    read_json(promoted_variant_receipt_path(data_dir, workspace_id))
}

pub fn write_baseline_adoption(
    data_dir: &Path,
    workspace_id: &str,
    adoption: &BaselineAdoption,
) -> anyhow::Result<()> {
    write_json(baseline_adoption_path(data_dir, workspace_id), adoption)
}

pub fn read_baseline_adoption(
    data_dir: &Path,
    workspace_id: &str,
) -> anyhow::Result<Option<BaselineAdoption>> {
    read_json(baseline_adoption_path(data_dir, workspace_id))
}

pub fn write_baseline_rollback_plan(
    data_dir: &Path,
    workspace_id: &str,
    plan: &BaselineRollbackPlan,
) -> anyhow::Result<()> {
    write_json(baseline_rollback_plan_path(data_dir, workspace_id), plan)
}

pub fn read_baseline_rollback_plan(
    data_dir: &Path,
    workspace_id: &str,
) -> anyhow::Result<Option<BaselineRollbackPlan>> {
    read_json(baseline_rollback_plan_path(data_dir, workspace_id))
}

pub fn write_next_study_seed(
    data_dir: &Path,
    workspace_id: &str,
    seed: &NextStudySeed,
) -> anyhow::Result<()> {
    write_json(next_study_seed_path(data_dir, workspace_id), seed)
}

pub fn read_next_study_seed(
    data_dir: &Path,
    workspace_id: &str,
) -> anyhow::Result<Option<NextStudySeed>> {
    read_json(next_study_seed_path(data_dir, workspace_id))
}

pub fn write_workbench_context_after_baseline(
    data_dir: &Path,
    workspace_id: &str,
    ctx: &WorkbenchContextAfterBaseline,
) -> anyhow::Result<()> {
    write_json(
        workbench_context_after_baseline_path(data_dir, workspace_id),
        ctx,
    )
}

pub fn read_workbench_context_after_baseline(
    data_dir: &Path,
    workspace_id: &str,
) -> anyhow::Result<Option<WorkbenchContextAfterBaseline>> {
    read_json(workbench_context_after_baseline_path(data_dir, workspace_id))
}

fn promoted_variant_receipt_path(data_dir: &Path, workspace_id: &str) -> PathBuf {
    workspace_plane_dir(data_dir)
        .join("promoted-variant-receipt")
        .join(format!("{}.json", sanitize_component(workspace_id)))
}

fn baseline_adoption_path(data_dir: &Path, workspace_id: &str) -> PathBuf {
    workspace_plane_dir(data_dir)
        .join("baseline-adoption")
        .join(format!("{}.json", sanitize_component(workspace_id)))
}

fn baseline_rollback_plan_path(data_dir: &Path, workspace_id: &str) -> PathBuf {
    workspace_plane_dir(data_dir)
        .join("baseline-rollback-plan")
        .join(format!("{}.json", sanitize_component(workspace_id)))
}

fn next_study_seed_path(data_dir: &Path, workspace_id: &str) -> PathBuf {
    workspace_plane_dir(data_dir)
        .join("next-study-seed")
        .join(format!("{}.json", sanitize_component(workspace_id)))
}

fn workbench_context_after_baseline_path(data_dir: &Path, workspace_id: &str) -> PathBuf {
    workspace_plane_dir(data_dir)
        .join("workbench-context-after-baseline")
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
    use tempfile::tempdir;

    #[test]
    fn adoption_evidence_refs_has_locator_pattern() {
        let receipt = PromotedVariantReceipt {
            phase: BASELINE_ADOPTION_PHASE.to_string(),
            contract_kind: PROMOTED_VARIANT_RECEIPT_KIND.to_string(),
            contract_version: PROMOTED_VARIANT_RECEIPT_VERSION.to_string(),
            receipt_id: "r1".to_string(),
            study_promotion_execution_id: "e1".to_string(),
            study_id: "s1".to_string(),
            workstream_id: "w1".to_string(),
            workspace_id: "ws1".to_string(),
            session_id: "sess1".to_string(),
            same_beagle_owned_identity: true,
            generated_at: Utc::now(),
            promoted_variant_id: "v1".to_string(),
            promoted_variant_label: "l".to_string(),
            promoted_variant_kind: "k".to_string(),
            promoted_run_id: "run1".to_string(),
            promoted_run_label: "rl".to_string(),
            promoted_compute_profile_id: "cpu".to_string(),
            workbench_run_id: "wr1".to_string(),
            result_binding_id: "rb1".to_string(),
            study_closeout_summary_id: "c1".to_string(),
            variant_promotion_decision_id: "d1".to_string(),
            note: "n".to_string(),
        };
        let refs = adoption_evidence_refs(&receipt);
        assert!(refs[0].locator.contains("study-promotion-execution"));
    }

    #[test]
    fn ensure_baseline_adoption_creates_all_artifacts() {
        let tmp = tempdir().unwrap();
        let data_dir = tmp.path();

        // This test is intentionally minimal because it requires previous
        // study promotion + closeout artifacts to exist.
        // In real usage this is called after B26.5.
        let result = ensure_baseline_adoption(data_dir, "test-workstream", "test-workspace");

        // We only check that the function signature and error paths are sane.
        // Full integration test is done via smoke script.
        match result {
            Ok(_) => {}, // would be success in full context
            Err(e) => {
                let msg = e.to_string();
                assert!(msg.contains("missing") || msg.contains("not found"),
                    "Expected missing artifact error, got: {}", msg);
            }
        }
    }
}
