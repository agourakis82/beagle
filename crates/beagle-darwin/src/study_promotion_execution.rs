use crate::run_diff::{read_run_diff, RunDiff};
use crate::study_convergence::{read_study_convergence, read_study_closeout_summary,
    read_variant_promotion_decision, StudyCloseoutSummary, StudyConvergence,
    VariantPromotionDecision};
use crate::study_continuation::{read_study_run_update, StudyRunUpdate};
use crate::study_decision::StudyEvidenceRef;
use crate::workspace_plane::workspace_plane_dir;
use anyhow::{anyhow, Context};
use chrono::{DateTime, Utc};
use serde::{Deserialize, Serialize};
use serde_json;
use std::fs;
use std::path::{Path, PathBuf};

pub const STUDY_PROMOTION_EXECUTION_PHASE: &str = "B26.5";
pub const STUDY_PROMOTION_EXECUTION_KIND: &str = "study-promotion-execution";
pub const STUDY_PROMOTION_EXECUTION_VERSION: &str = "beagle-study-promotion-execution-v1";

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
pub struct StudyPromotionExecution {
    pub phase: String,
    pub contract_kind: String,
    pub contract_version: String,
    pub execution_id: String,
    pub study_id: String,
    pub workstream_id: String,
    pub workspace_id: String,
    pub session_id: String,
    pub same_beagle_owned_identity: bool,
    pub generated_at: DateTime<Utc>,
    pub study_convergence_id: String,
    pub variant_promotion_decision_id: String,
    pub study_closeout_summary_id: String,
    pub promoted_variant_id: String,
    pub promoted_variant_label: String,
    pub promoted_variant_kind: String,
    pub promoted_run_id: String,
    pub promoted_run_label: String,
    pub promoted_compute_profile_id: String,
    pub promoted_run_score: u16,
    pub promoted_run_reason: String,
    pub workbench_run_id: String,
    pub result_binding_id: String,
    pub run_result_identity_receipt_id: String,
    pub deterministic_result_binding_id: String,
    pub run_lineage_relation: String,
    pub run_diff_changed_categories: Vec<String>,
    pub archived_variant_count: usize,
    pub archived_variant_ids: Vec<String>,
    pub archived_variant_labels: Vec<String>,
    pub archived_variant_kinds: Vec<String>,
    pub decision_basis_summary: String,
    pub evidence_refs: Vec<StudyEvidenceRef>,
    pub note: String,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
pub struct StudyPromotionExecutionBundle {
    pub status: String,
    pub phase: String,
    pub study_convergence: StudyConvergence,
    pub variant_promotion_decision: VariantPromotionDecision,
    pub study_closeout_summary: StudyCloseoutSummary,
    pub study_promotion_execution: StudyPromotionExecution,
}

pub fn ensure_study_promotion_execution(
    data_dir: &Path,
    workstream_id: &str,
    workspace_id: &str,
) -> anyhow::Result<StudyPromotionExecutionBundle> {
    let study_convergence = read_study_convergence(data_dir, workspace_id)?
        .ok_or_else(|| anyhow!("study convergence missing for workspace {}", workspace_id))?;
    if study_convergence.workstream_id != workstream_id {
        return Err(anyhow!("workstream mismatch for study convergence"));
    }
    if !study_convergence.enough_evidence_to_stop {
        return Err(anyhow!("study conversion has not converged for workspace {}", workspace_id));
    }
    let variant_promotion_decision = read_variant_promotion_decision(data_dir, workspace_id)?
        .ok_or_else(|| anyhow!("variant promotion decision missing for workspace {}", workspace_id))?;
    let study_closeout_summary = read_study_closeout_summary(data_dir, workspace_id)?
        .ok_or_else(|| anyhow!("study closeout summary missing for workspace {}", workspace_id))?;
    let study_run_update = read_study_run_update(data_dir, workspace_id)?
        .ok_or_else(|| anyhow!("study run update missing for workspace {}", workspace_id))?;
    validate_identity(&study_convergence, &variant_promotion_decision, &study_closeout_summary)?;
    let run_diff = read_run_diff(data_dir, workspace_id)?;
    let evidence_refs = promotion_evidence_refs(data_dir, workspace_id);
    let generated_at = Utc::now();
    let archived_variants = archived_variants_from_decision(&variant_promotion_decision);
    let promotion_execution = build_promotion_execution(
        &study_convergence,
        &variant_promotion_decision,
        &study_closeout_summary,
        &study_run_update,
        run_diff.as_ref(),
        &archived_variants,
        evidence_refs,
        generated_at,
    );
    write_study_promotion_execution(data_dir, workspace_id, &promotion_execution)?;
    Ok(StudyPromotionExecutionBundle {
        status: "ok".to_string(),
        phase: STUDY_PROMOTION_EXECUTION_PHASE.to_string(),
        study_convergence,
        variant_promotion_decision,
        study_closeout_summary,
        study_promotion_execution: promotion_execution,
    })
}

fn build_promotion_execution(
    convergence: &StudyConvergence,
    decision: &VariantPromotionDecision,
    closeout: &StudyCloseoutSummary,
    update: &StudyRunUpdate,
    run_diff: Option<&RunDiff>,
    archived_variants: &[(String, String, String)],
    evidence_refs: Vec<StudyEvidenceRef>,
    generated_at: DateTime<Utc>,
) -> StudyPromotionExecution {
    let lineage_relation = run_diff
        .map(|diff| diff.lineage_relation.clone())
        .unwrap_or_else(|| "unknown".to_string());
    let changed_categories = run_diff
        .map(|diff| diff.changed_categories.clone())
        .unwrap_or_default();
    StudyPromotionExecution {
        phase: STUDY_PROMOTION_EXECUTION_PHASE.to_string(),
        contract_kind: STUDY_PROMOTION_EXECUTION_KIND.to_string(),
        contract_version: STUDY_PROMOTION_EXECUTION_VERSION.to_string(),
        execution_id: format!(
            "{}-study-promotion-execution",
            sanitize_component(convergence.study_id.as_str())
        ),
        study_id: convergence.study_id.clone(),
        workstream_id: convergence.workstream_id.clone(),
        workspace_id: convergence.workspace_id.clone(),
        session_id: convergence.session_id.clone(),
        same_beagle_owned_identity: convergence.same_beagle_owned_identity,
        generated_at,
        study_convergence_id: convergence.convergence_id.clone(),
        variant_promotion_decision_id: decision.decision_id.clone(),
        study_closeout_summary_id: closeout.closeout_summary_id.clone(),
        promoted_variant_id: decision.promoted_variant_id.clone(),
        promoted_variant_label: decision.promoted_variant_label.clone(),
        promoted_variant_kind: decision.promoted_variant_kind.clone(),
        promoted_run_id: decision.promoted_run_id.clone(),
        promoted_run_label: decision.promoted_run_label.clone(),
        promoted_compute_profile_id: decision.promoted_compute_profile_id.clone(),
        promoted_run_score: convergence.best_run_score,
        promoted_run_reason: convergence.best_run_reason.clone(),
        workbench_run_id: update.dispatched_run_id.clone(),
        result_binding_id: update.result_binding_id.clone(),
        run_result_identity_receipt_id: update.run_result_identity_receipt_id.clone(),
        deterministic_result_binding_id: update.deterministic_result_binding_id.clone(),
        run_lineage_relation: lineage_relation,
        run_diff_changed_categories: changed_categories,
        archived_variant_count: archived_variants.len(),
        archived_variant_ids: archived_variants.iter().map(|entry| entry.0.clone()).collect(),
        archived_variant_labels: archived_variants.iter().map(|entry| entry.1.clone()).collect(),
        archived_variant_kinds: archived_variants.iter().map(|entry| entry.2.clone()).collect(),
        decision_basis_summary: format!(
            "promoted_variant={} best_score={} enough_evidence=true archived={} dispatched_run={}",
            decision.promoted_variant_id,
            convergence.best_run_score,
            archived_variants.len(),
            update.dispatched_run_id
        ),
        evidence_refs,
        note: "B26.5 materializes the promoted variant, archives the losers, and records the workbench, memory, and lineage bindings while preserving the Beagle-owned identity.".to_string(),
    }
}

fn archived_variants_from_decision(
    decision: &VariantPromotionDecision,
) -> Vec<(String, String, String)> {
    decision
        .archived_variant_ids
        .iter()
        .zip(decision.archived_variant_labels.iter())
        .zip(decision.archived_variant_kinds.iter())
        .map(|((id, label), kind)| (id.clone(), label.clone(), kind.clone()))
        .collect()
}

fn promotion_evidence_refs(data_dir: &Path, workspace_id: &str) -> Vec<StudyEvidenceRef> {
    let base = workspace_plane_dir(data_dir);
    vec![
        StudyEvidenceRef {
            ref_id: "study-convergence".to_string(),
            ref_kind: "workspace-plane-json".to_string(),
            locator: base
                .join("study-convergence")
                .join(format!("{}.json", sanitize_component(workspace_id)))
                .display()
                .to_string(),
            summary: "Convergence gate recording whether the study had enough evidence to stop.".to_string(),
        },
        StudyEvidenceRef {
            ref_id: "variant-promotion-decision".to_string(),
            ref_kind: "workspace-plane-json".to_string(),
            locator: base
                .join("variant-promotion-decision")
                .join(format!("{}.json", sanitize_component(workspace_id)))
                .display()
                .to_string(),
            summary: "Operator-visible variant promotion decision that selected the winner and archived the rest.".to_string(),
        },
        StudyEvidenceRef {
            ref_id: "study-closeout-summary".to_string(),
            ref_kind: "workspace-plane-json".to_string(),
            locator: base
                .join("study-closeout-summary")
                .join(format!("{}.json", sanitize_component(workspace_id)))
                .display()
                .to_string(),
            summary: "Closeout summary that froze the comparative and promotion outcomes.".to_string(),
        },
        StudyEvidenceRef {
            ref_id: "study-run-update".to_string(),
            ref_kind: "workspace-plane-json".to_string(),
            locator: base
                .join("study-run-update")
                .join(format!("{}.json", sanitize_component(workspace_id)))
                .display()
                .to_string(),
            summary: "Run update showing the dispatched workbench run that validated the promoted variant.".to_string(),
        },
        StudyEvidenceRef {
            ref_id: "run-diff".to_string(),
            ref_kind: "workspace-plane-json".to_string(),
            locator: base
                .join("run-diff")
                .join(format!("{}.json", sanitize_component(workspace_id)))
                .display()
                .to_string(),
            summary: "Run diff capturing code/config/environment/result lineage for the promoted variant.".to_string(),
        },
        StudyEvidenceRef {
            ref_id: "run-result-identity-receipt".to_string(),
            ref_kind: "workspace-plane-json".to_string(),
            locator: base
                .join("run-result-identity-receipt")
                .join(format!("{}.json", sanitize_component(workspace_id)))
                .display()
                .to_string(),
            summary: "Memory binding proving the promoted run's result identity is recorded.".to_string(),
        },
        StudyEvidenceRef {
            ref_id: "workbench-result-binding".to_string(),
            ref_kind: "workspace-plane-json".to_string(),
            locator: base
                .join("workbench-result-binding")
                .join(format!("{}.json", sanitize_component(workspace_id)))
                .display()
                .to_string(),
            summary: "Workbench result binding tying the promoted run back into the operator-managed workbench.".to_string(),
        },
    ]
}

fn validate_identity(
    convergence: &StudyConvergence,
    decision: &VariantPromotionDecision,
    closeout: &StudyCloseoutSummary,
) -> anyhow::Result<()> {
    if convergence.study_id != decision.study_id
        || convergence.study_id != closeout.study_id
        || convergence.workstream_id != decision.workstream_id
        || convergence.workstream_id != closeout.workstream_id
        || convergence.workspace_id != decision.workspace_id
        || convergence.workspace_id != closeout.workspace_id
        || convergence.session_id != decision.session_id
        || convergence.session_id != closeout.session_id
    {
        return Err(anyhow!(
            "study promotion execution artifacts must share study/workstream/workspace/session identity"
        ));
    }
    if !(
        convergence.same_beagle_owned_identity
            && decision.same_beagle_owned_identity
            && closeout.same_beagle_owned_identity
    ) {
        return Err(anyhow!(
            "study promotion execution requires preserved Beagle-owned identity"
        ));
    }
    Ok(())
}

pub fn write_study_promotion_execution(
    data_dir: &Path,
    workspace_id: &str,
    execution: &StudyPromotionExecution,
) -> anyhow::Result<()> {
    write_json(
        study_promotion_execution_path(data_dir, workspace_id),
        execution,
    )
}

pub fn read_study_promotion_execution(
    data_dir: &Path,
    workspace_id: &str,
) -> anyhow::Result<Option<StudyPromotionExecution>> {
    read_json(study_promotion_execution_path(data_dir, workspace_id))
}

fn study_promotion_execution_path(data_dir: &Path, workspace_id: &str) -> PathBuf {
    workspace_plane_dir(data_dir)
        .join("study-promotion-execution")
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

    #[test]
    fn write_and_read_roundtrip() {
        let mut data_dir = std::env::temp_dir();
        let unique = SystemTime::now()
            .duration_since(UNIX_EPOCH)
            .expect("system time")
            .as_nanos();
        data_dir.push(format!("beagle-study-promotion-test-{}", unique));
        std::fs::create_dir_all(&data_dir).expect("tempdir");
        let execution = StudyPromotionExecution {
            phase: STUDY_PROMOTION_EXECUTION_PHASE.to_string(),
            contract_kind: STUDY_PROMOTION_EXECUTION_KIND.to_string(),
            contract_version: STUDY_PROMOTION_EXECUTION_VERSION.to_string(),
            execution_id: "promotion-1".to_string(),
            study_id: "study-1".to_string(),
            workstream_id: "workstream-1".to_string(),
            workspace_id: "workspace-1".to_string(),
            session_id: "session-1".to_string(),
            same_beagle_owned_identity: true,
            generated_at: Utc::now(),
            study_convergence_id: "convergence-1".to_string(),
            variant_promotion_decision_id: "decision-1".to_string(),
            study_closeout_summary_id: "closeout-1".to_string(),
            promoted_variant_id: "variant-1".to_string(),
            promoted_variant_label: "baseline".to_string(),
            promoted_variant_kind: "baseline".to_string(),
            promoted_run_id: "run-1".to_string(),
            promoted_run_label: "baseline-run".to_string(),
            promoted_compute_profile_id: "cpu".to_string(),
            promoted_run_score: 140,
            promoted_run_reason: "score".to_string(),
            workbench_run_id: "run-1".to_string(),
            result_binding_id: "binding-1".to_string(),
            run_result_identity_receipt_id: "receipt-1".to_string(),
            deterministic_result_binding_id: "det-binding-1".to_string(),
            run_lineage_relation: "direct-parent".to_string(),
            run_diff_changed_categories: vec!["code".to_string()],
            archived_variant_count: 1,
            archived_variant_ids: vec!["variant-2".to_string()],
            archived_variant_labels: vec!["replay".to_string()],
            archived_variant_kinds: vec!["replay".to_string()],
            decision_basis_summary: "summary".to_string(),
            evidence_refs: Vec::new(),
            note: "note".to_string(),
        };
        write_study_promotion_execution(&data_dir, "workspace-1", &execution)
            .expect("write execution");
        let read_execution = read_study_promotion_execution(&data_dir, "workspace-1")
            .expect("read execution")
            .expect("execution exists");
        assert_eq!(read_execution.promoted_variant_id, "variant-1");
        std::fs::remove_dir_all(&data_dir).expect("cleanup");
    }
}
