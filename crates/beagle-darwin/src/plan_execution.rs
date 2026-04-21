use crate::approval_gate::{build_approval_gating_decision, ApprovalGatingDecision};
use crate::autonomy_calibration::{
    build_analysis_canary_activation_bundle, build_analysis_sample_accumulation_bundle,
    build_analysis_shadow_calibration_bundle, build_analysis_shadow_soak_bundle,
    build_autonomy_policy_calibration_bundle, build_guarded_policy_rollout_bundle,
    build_implementation_canary_autonomy_bundle,
    build_manuscript_alignment_labeling_bundle,
    build_manuscript_alignment_signal_bundle,
    build_manuscript_quality_uplift_bundle,
    build_manuscript_sample_accumulation_bundle, build_manuscript_shadow_calibration_bundle,
    AnalysisCanaryActivationBundle, AnalysisCanaryMetrics, AnalysisCanaryRollbackDecision,
    AnalysisPromotionGate, AnalysisRolloutDecision, AnalysisRolloutMetrics,
    AnalysisSampleAccumulationBundle, AnalysisShadowCalibration,
    AnalysisShadowCalibrationBundle, AnalysisShadowSoak, AnalysisShadowSoakBundle,
    AnalysisSoakMetrics, AutonomyCalibrationDataset, AutonomyPolicyCalibrationBundle,
    AutonomyPolicyEvalReport, AutonomyShadowThreshold, CanaryRollbackDecision,
    CanaryRolloutMetrics, EscalationThresholds, GuardedPolicyRolloutBundle,
    GuardedRolloutDecision, ImplementationCanaryAutonomyBundle,
    ManuscriptAlignmentLabelingBundle, ManuscriptAlignmentLabels,
    ManuscriptAlignmentSignalBundle,
    ManuscriptContextAdequacy, ManuscriptPromotionEvidence, ManuscriptPromotionGate,
    ManuscriptQualityUpliftBundle, ManuscriptRolloutDecision, ManuscriptRolloutMetrics,
    ManuscriptSampleAccumulationBundle,
    ManuscriptShadowCalibration, ManuscriptShadowCalibrationBundle,
    ManuscriptShadowHistory, ManuscriptSoakMetrics, ManuscriptTrajectoryQuality,
    ManuscriptTuningRecommendation, PolicyRolloutMetrics, ShadowPolicyComparison,
    UpdatedPolicyRecommendation,
};
use crate::autonomy_policy::{build_autonomy_policy, AutonomyPolicy};
use crate::continuation_dispatch::{
    ContinuationDispatch, ContinuationDispatchRequest, CONTINUATION_DISPATCH_VERSION,
};
use crate::continuation_state::{
    ContinuationReceipt, ContinuationStatePlane, ContinuationStateTransition,
    CONTINUATION_RECEIPT_VERSION, CONTINUATION_STATE_VERSION,
};
use crate::execution_plan::ExecutionPlan;
use crate::execution_reflection::{build_execution_reflection, ExecutionReflection};
use crate::follow_on_plan::{build_follow_on_plan, FollowOnPlan};
use crate::replan::{build_replan_suggestion, ReplanSuggestion};
use crate::review_decision::{
    build_review_decision, normalize_review_decision_action, ReviewDecision,
    ReviewDecisionEditPatch,
};
use crate::review_inbox::{build_review_inbox_item, ReviewInboxItem};
use crate::risk_evaluation::{build_risk_evaluation, RiskEvaluation};
use crate::execution_state::{
    ExecutionReceipt, ExecutionResultLink, ExecutionResultLinksDocument, ExecutionStatePlane,
    ExecutionStateTransition, PlanApproval, PlanExecutionStatusSummary,
    EXECUTION_RECEIPT_VERSION, EXECUTION_RESULT_LINKS_VERSION, EXECUTION_STATE_VERSION,
    PLAN_APPROVAL_VERSION,
};
use crate::trajectory_eval::{build_trajectory_eval, TrajectoryEval};
use crate::workspace_plane::workspace_plane_dir;
use crate::workspace_subagent_handoff::{
    record_workspace_subagent_handoff, WorkspaceSubAgentHandoffRequest,
};
use crate::{WorkstreamContextPacket, WorkstreamContextPacketResponse};
use anyhow::{anyhow, Context};
use beagle_config::BeagleConfig;
use chrono::Utc;
use serde::{Deserialize, Serialize};
use std::fs;
use std::path::{Path, PathBuf};

const PLAN_EXECUTION_PHASE: &str = "B24.3";
const PLAN_EXECUTION_RECORD_VERSION: &str = "beagle-plan-execution-record-v1";
const PLAN_EXECUTION_API_PREFIX: &str = "/api/darwin/workstreams";
const OPERATOR_EXECUTION_STATE: &str = "operator-visible-bounded";

#[derive(Debug, Clone)]
pub struct PlanApprovalRequest<'a> {
    pub execution_plan: &'a ExecutionPlan,
    pub approved_by: &'a str,
    pub approval_note: &'a str,
}

#[derive(Debug, Clone)]
pub struct PlanExecutionStartRequest<'a> {
    pub plan_id: &'a str,
    pub started_by: &'a str,
    pub start_note: &'a str,
}

#[derive(Debug, Clone)]
pub struct PlanExecutionStopRequest<'a> {
    pub plan_id: &'a str,
    pub stopped_by: &'a str,
    pub stop_reason: &'a str,
}

#[derive(Debug, Clone)]
pub struct ReviewInboxMaterializeRequest<'a> {
    pub created_by: &'a str,
    pub create_note: &'a str,
}

#[derive(Debug, Clone)]
pub struct ReviewInboxDecisionRequest {
    pub inbox_item_id: String,
    pub decision_action: String,
    pub decided_by: String,
    pub decision_note: String,
    pub edit_patch: Option<ReviewDecisionEditPatch>,
}

#[derive(Debug, Clone, Serialize)]
pub struct PlanExecutionEnvelope {
    pub status: String,
    pub phase: String,
    pub execution_plan: ExecutionPlan,
    pub approval: PlanApproval,
    pub execution_state: ExecutionStatePlane,
    #[serde(default)]
    pub execution_receipt: Option<ExecutionReceipt>,
    pub execution_result_links: ExecutionResultLinksDocument,
    #[serde(default)]
    pub execution_reflection: Option<ExecutionReflection>,
    #[serde(default)]
    pub trajectory_eval: Option<TrajectoryEval>,
    #[serde(default)]
    pub replan_suggestion: Option<ReplanSuggestion>,
    #[serde(default)]
    pub review_inbox_item: Option<ReviewInboxItem>,
    #[serde(default)]
    pub review_decision: Option<ReviewDecision>,
    #[serde(default)]
    pub follow_on_plan: Option<FollowOnPlan>,
    #[serde(default)]
    pub autonomy_policy: Option<AutonomyPolicy>,
    #[serde(default)]
    pub risk_evaluation: Option<RiskEvaluation>,
    #[serde(default)]
    pub approval_gating_decision: Option<ApprovalGatingDecision>,
    #[serde(default)]
    pub autonomy_calibration_dataset: Option<AutonomyCalibrationDataset>,
    #[serde(default)]
    pub autonomy_policy_eval_report: Option<AutonomyPolicyEvalReport>,
    #[serde(default)]
    pub escalation_thresholds: Option<EscalationThresholds>,
    #[serde(default)]
    pub shadow_policy_comparison: Option<ShadowPolicyComparison>,
    #[serde(default)]
    pub updated_policy_recommendation: Option<UpdatedPolicyRecommendation>,
    #[serde(default)]
    pub autonomy_policy_current: Option<AutonomyShadowThreshold>,
    #[serde(default)]
    pub autonomy_policy_candidate: Option<AutonomyShadowThreshold>,
    #[serde(default)]
    pub rollout_metrics: Option<PolicyRolloutMetrics>,
    #[serde(default)]
    pub rollout_decision: Option<GuardedRolloutDecision>,
    #[serde(default)]
    pub autonomy_policy_control: Option<AutonomyPolicy>,
    #[serde(default)]
    pub autonomy_policy_canary: Option<AutonomyPolicy>,
    #[serde(default)]
    pub canary_rollout_metrics: Option<CanaryRolloutMetrics>,
    #[serde(default)]
    pub canary_rollback_decision: Option<CanaryRollbackDecision>,
    #[serde(default)]
    pub autonomy_policy_analysis_candidate: Option<AutonomyPolicy>,
    #[serde(default)]
    pub analysis_shadow_comparison: Option<AnalysisShadowCalibration>,
    #[serde(default)]
    pub analysis_rollout_metrics: Option<AnalysisRolloutMetrics>,
    #[serde(default)]
    pub analysis_rollout_decision: Option<AnalysisRolloutDecision>,
    #[serde(default)]
    pub analysis_shadow_history: Option<AnalysisShadowSoak>,
    #[serde(default)]
    pub analysis_soak_metrics: Option<AnalysisSoakMetrics>,
    #[serde(default)]
    pub analysis_promotion_gate: Option<AnalysisPromotionGate>,
    #[serde(default)]
    pub analysis_sample_accumulation: Option<AnalysisShadowSoak>,
    #[serde(default)]
    pub analysis_sample_accumulation_metrics: Option<AnalysisSoakMetrics>,
    #[serde(default)]
    pub analysis_promotion_gate_recheck: Option<AnalysisPromotionGate>,
    #[serde(default)]
    pub autonomy_policy_analysis_control: Option<AutonomyPolicy>,
    #[serde(default)]
    pub autonomy_policy_implementation_canary_retained: Option<AutonomyPolicy>,
    #[serde(default)]
    pub autonomy_policy_analysis_canary: Option<AutonomyPolicy>,
    #[serde(default)]
    pub analysis_canary_metrics: Option<AnalysisCanaryMetrics>,
    #[serde(default)]
    pub analysis_canary_rollback_decision: Option<AnalysisCanaryRollbackDecision>,
    #[serde(default)]
    pub autonomy_policy_manuscript_candidate: Option<AutonomyPolicy>,
    #[serde(default)]
    pub manuscript_shadow_comparison: Option<ManuscriptShadowCalibration>,
    #[serde(default)]
    pub manuscript_rollout_metrics: Option<ManuscriptRolloutMetrics>,
    #[serde(default)]
    pub manuscript_rollout_decision: Option<ManuscriptRolloutDecision>,
    #[serde(default)]
    pub manuscript_shadow_history: Option<ManuscriptShadowHistory>,
    #[serde(default)]
    pub manuscript_soak_metrics: Option<ManuscriptSoakMetrics>,
    #[serde(default)]
    pub manuscript_promotion_gate: Option<ManuscriptPromotionGate>,
    #[serde(default)]
    pub manuscript_alignment_labels: Option<ManuscriptAlignmentLabels>,
    #[serde(default)]
    pub manuscript_promotion_evidence: Option<ManuscriptPromotionEvidence>,
    #[serde(default)]
    pub manuscript_trajectory_quality: Option<ManuscriptTrajectoryQuality>,
    #[serde(default)]
    pub manuscript_context_adequacy: Option<ManuscriptContextAdequacy>,
    #[serde(default)]
    pub manuscript_tuning_recommendation: Option<ManuscriptTuningRecommendation>,
    #[serde(default)]
    pub continuation_dispatch: Option<ContinuationDispatch>,
    #[serde(default)]
    pub continuation_receipt: Option<ContinuationReceipt>,
    #[serde(default)]
    pub continuation_state: Option<ContinuationStatePlane>,
    pub context_packet: WorkstreamContextPacket,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
struct PersistedPlanExecutionRecord {
    record_version: String,
    execution_plan: ExecutionPlan,
    approval: PlanApproval,
    execution_state: ExecutionStatePlane,
    #[serde(default)]
    execution_receipt: Option<ExecutionReceipt>,
    execution_result_links: ExecutionResultLinksDocument,
    #[serde(default)]
    execution_reflection: Option<ExecutionReflection>,
    #[serde(default)]
    trajectory_eval: Option<TrajectoryEval>,
    #[serde(default)]
    replan_suggestion: Option<ReplanSuggestion>,
    #[serde(default)]
    review_inbox_item: Option<ReviewInboxItem>,
    #[serde(default)]
    review_decision: Option<ReviewDecision>,
    #[serde(default)]
    follow_on_plan: Option<FollowOnPlan>,
    #[serde(default)]
    autonomy_policy: Option<AutonomyPolicy>,
    #[serde(default)]
    risk_evaluation: Option<RiskEvaluation>,
    #[serde(default)]
    approval_gating_decision: Option<ApprovalGatingDecision>,
    #[serde(default)]
    autonomy_calibration_dataset: Option<AutonomyCalibrationDataset>,
    #[serde(default)]
    autonomy_policy_eval_report: Option<AutonomyPolicyEvalReport>,
    #[serde(default)]
    escalation_thresholds: Option<EscalationThresholds>,
    #[serde(default)]
    shadow_policy_comparison: Option<ShadowPolicyComparison>,
    #[serde(default)]
    updated_policy_recommendation: Option<UpdatedPolicyRecommendation>,
    #[serde(default)]
    autonomy_policy_current: Option<AutonomyShadowThreshold>,
    #[serde(default)]
    autonomy_policy_candidate: Option<AutonomyShadowThreshold>,
    #[serde(default)]
    rollout_metrics: Option<PolicyRolloutMetrics>,
    #[serde(default)]
    rollout_decision: Option<GuardedRolloutDecision>,
    #[serde(default)]
    autonomy_policy_control: Option<AutonomyPolicy>,
    #[serde(default)]
    autonomy_policy_canary: Option<AutonomyPolicy>,
    #[serde(default)]
    canary_rollout_metrics: Option<CanaryRolloutMetrics>,
    #[serde(default)]
    canary_rollback_decision: Option<CanaryRollbackDecision>,
    #[serde(default)]
    autonomy_policy_analysis_candidate: Option<AutonomyPolicy>,
    #[serde(default)]
    analysis_shadow_comparison: Option<AnalysisShadowCalibration>,
    #[serde(default)]
    analysis_rollout_metrics: Option<AnalysisRolloutMetrics>,
    #[serde(default)]
    analysis_rollout_decision: Option<AnalysisRolloutDecision>,
    #[serde(default)]
    analysis_shadow_history: Option<AnalysisShadowSoak>,
    #[serde(default)]
    analysis_soak_metrics: Option<AnalysisSoakMetrics>,
    #[serde(default)]
    analysis_promotion_gate: Option<AnalysisPromotionGate>,
    #[serde(default)]
    analysis_sample_accumulation: Option<AnalysisShadowSoak>,
    #[serde(default)]
    analysis_sample_accumulation_metrics: Option<AnalysisSoakMetrics>,
    #[serde(default)]
    analysis_promotion_gate_recheck: Option<AnalysisPromotionGate>,
    #[serde(default)]
    autonomy_policy_analysis_control: Option<AutonomyPolicy>,
    #[serde(default)]
    autonomy_policy_implementation_canary_retained: Option<AutonomyPolicy>,
    #[serde(default)]
    autonomy_policy_analysis_canary: Option<AutonomyPolicy>,
    #[serde(default)]
    analysis_canary_metrics: Option<AnalysisCanaryMetrics>,
    #[serde(default)]
    analysis_canary_rollback_decision: Option<AnalysisCanaryRollbackDecision>,
    #[serde(default)]
    autonomy_policy_manuscript_candidate: Option<AutonomyPolicy>,
    #[serde(default)]
    manuscript_shadow_comparison: Option<ManuscriptShadowCalibration>,
    #[serde(default)]
    manuscript_rollout_metrics: Option<ManuscriptRolloutMetrics>,
    #[serde(default)]
    manuscript_rollout_decision: Option<ManuscriptRolloutDecision>,
    #[serde(default)]
    manuscript_shadow_history: Option<ManuscriptShadowHistory>,
    #[serde(default)]
    manuscript_soak_metrics: Option<ManuscriptSoakMetrics>,
    #[serde(default)]
    manuscript_promotion_gate: Option<ManuscriptPromotionGate>,
    #[serde(default)]
    manuscript_alignment_labels: Option<ManuscriptAlignmentLabels>,
    #[serde(default)]
    manuscript_promotion_evidence: Option<ManuscriptPromotionEvidence>,
    #[serde(default)]
    manuscript_trajectory_quality: Option<ManuscriptTrajectoryQuality>,
    #[serde(default)]
    manuscript_context_adequacy: Option<ManuscriptContextAdequacy>,
    #[serde(default)]
    manuscript_tuning_recommendation: Option<ManuscriptTuningRecommendation>,
    #[serde(default)]
    continuation_dispatch: Option<ContinuationDispatch>,
    #[serde(default)]
    continuation_receipt: Option<ContinuationReceipt>,
    #[serde(default)]
    continuation_state: Option<ContinuationStatePlane>,
}

pub fn approve_execution_plan(
    data_dir: &Path,
    _cfg: &BeagleConfig,
    workstream_id: &str,
    context_packet: WorkstreamContextPacketResponse,
    request: PlanApprovalRequest<'_>,
) -> anyhow::Result<PlanApproval> {
    validate_plan_identity(workstream_id, &context_packet.packet, request.execution_plan)?;
    let approved_by = normalize_sentence(request.approved_by);
    let approval_note = normalize_sentence(request.approval_note);
    if approved_by.is_empty() {
        return Err(anyhow!("approved_by must not be empty"));
    }
    if approval_note.is_empty() {
        return Err(anyhow!("approval_note must not be empty"));
    }

    let approved_at = Utc::now();
    let execution_state_path = execution_state_path(workstream_id);
    let execution_receipt_path = execution_receipt_path(workstream_id);
    let execution_result_links_path = execution_result_links_path(workstream_id);
    let reflection_path = execution_reflection_path(workstream_id);
    let trajectory_eval_path = trajectory_eval_path(workstream_id);
    let replan_suggestion_path = replan_suggestion_path(workstream_id);
    let review_inbox_path = review_inbox_path(workstream_id);
    let review_decision_path = review_decision_path(workstream_id);
    let follow_on_plan_path = follow_on_plan_path(workstream_id);
    let approval = PlanApproval {
        approval_version: PLAN_APPROVAL_VERSION.to_string(),
        approval_id: format!(
            "{}-approval-{}",
            sanitize_component(&request.execution_plan.plan_id),
            approved_at.timestamp_millis()
        ),
        plan_id: request.execution_plan.plan_id.clone(),
        workstream_id: request.execution_plan.workstream_id.clone(),
        workspace_id: request.execution_plan.workspace_id.clone(),
        session_id: request.execution_plan.session_id.clone(),
        approved_by: approved_by.clone(),
        approval_note: approval_note.clone(),
        approval_state: "approved".to_string(),
        operator_visibility_confirmed: true,
        approved_at,
        operator_execution_state: OPERATOR_EXECUTION_STATE.to_string(),
        note: format!(
            "B24.3 requires explicit operator approval before bounded execution starts, and any reflection/replan output stays operator-visible instead of auto-running. approved_by={} visibility=confirmed",
            approved_by
        ),
    };
    let execution_id = format!(
        "{}-execution-{}",
        sanitize_component(&request.execution_plan.plan_id),
        approved_at.timestamp_millis()
    );
    let transitions = vec![
        ExecutionStateTransition {
            state: "planned".to_string(),
            transitioned_at: approved_at,
            note: "Execution plan accepted into the bounded operator-visible orchestrator.".to_string(),
        },
        ExecutionStateTransition {
            state: "approved".to_string(),
            transitioned_at: approved_at,
            note: format!(
                "Operator {} approved bounded execution: {}",
                approved_by, approval_note
            ),
        },
    ];
    let execution_state = ExecutionStatePlane {
        state_version: EXECUTION_STATE_VERSION.to_string(),
        execution_id: execution_id.clone(),
        planner_policy_id: request.execution_plan.planner_policy_id.clone(),
        plan_id: request.execution_plan.plan_id.clone(),
        workstream_id: request.execution_plan.workstream_id.clone(),
        workspace_id: request.execution_plan.workspace_id.clone(),
        session_id: request.execution_plan.session_id.clone(),
        program_id: request.execution_plan.program_id.clone(),
        campaign_id: request.execution_plan.campaign_id.clone(),
        task_family: request.execution_plan.task_family.clone(),
        tool_id: request.execution_plan.tool_id.clone(),
        work_mode: request.execution_plan.work_mode.clone(),
        current_state: "approved".to_string(),
        selected_subagent_id: request.execution_plan.selected_subagent_id.clone(),
        retrieval_query_type: request.execution_plan.retrieval_query_type.clone(),
        dense_backend: request.execution_plan.dense_backend.clone(),
        sparse_backend: request.execution_plan.sparse_backend.clone(),
        compiler_profile_id: request.execution_plan.compiler_profile_id.clone(),
        graphrag_query_mode: request.execution_plan.graphrag_query_mode.clone(),
        temporal_truth_view: request.execution_plan.temporal_truth_view.clone(),
        approved_by,
        approved_at,
        started_at: None,
        finished_at: None,
        stop_requested_at: None,
        stop_reason: None,
        latest_receipt_id: None,
        latest_reflection_id: None,
        latest_trajectory_eval_id: None,
        latest_replan_suggestion_id: None,
        recipe_id: request
            .execution_plan
            .recipe_target
            .as_ref()
            .map(|target| target.recipe_id.clone()),
        recipe_kind: request
            .execution_plan
            .recipe_target
            .as_ref()
            .map(|target| target.recipe_kind.clone()),
        experiment_id: request
            .execution_plan
            .experiment_target
            .as_ref()
            .map(|target| target.experiment_id.clone()),
        context_packet_ref: Some(request.execution_plan.context_packet_ref.clone()),
        program_context_packet_ref: request.execution_plan.program_context_packet_ref.clone(),
        tool_launch_path: request.execution_plan.tool_launch_path.clone(),
        workspace_subagent_route_path: request
            .execution_plan
            .workspace_subagent_route_path
            .clone(),
        workspace_subagent_handoff_path: request
            .execution_plan
            .workspace_subagent_handoff_path
            .clone(),
        reflection_path: Some(reflection_path),
        trajectory_eval_path: Some(trajectory_eval_path),
        replan_suggestion_path: Some(replan_suggestion_path),
        execution_state_path,
        execution_receipt_path,
        execution_result_links_path,
        state_transitions: transitions,
        latest_quality_score: None,
        latest_trajectory_quality: None,
        replan_required: false,
        operator_followup_action: None,
        review_requested: false,
        review_inbox_state: None,
        latest_review_inbox_item_id: None,
        latest_review_decision_id: None,
        latest_review_decision_action: None,
        latest_follow_on_plan_id: None,
        follow_on_plan_available: false,
        latest_autonomy_policy_id: None,
        latest_risk_evaluation_id: None,
        latest_approval_gating_decision_id: None,
        latest_autonomy_calibration_dataset_id: None,
        latest_autonomy_policy_eval_report_id: None,
        latest_escalation_thresholds_id: None,
        latest_shadow_policy_comparison_id: None,
        latest_updated_policy_recommendation_id: None,
        latest_autonomy_policy_current_id: None,
        latest_autonomy_policy_candidate_id: None,
        latest_rollout_metrics_id: None,
        latest_guarded_rollout_decision_id: None,
        approval_gating_decision_class: None,
        approval_gating_risk_level: None,
        approval_gating_dispatch_ready: false,
        approval_gating_blocked: false,
        continuation_dispatched: false,
        latest_continuation_dispatch_id: None,
        latest_continuation_receipt_id: None,
        continuation_current_state: None,
        continuation_source_execution_id: None,
        continuation_next_execution_id: None,
        continuation_next_plan_id: None,
        continuation_review_action: None,
        autonomy_policy_calibration_status: None,
        autonomy_policy_rollout_status: None,
        review_inbox_path: Some(review_inbox_path),
        review_decision_path: Some(review_decision_path),
        follow_on_plan_path: Some(follow_on_plan_path),
        autonomy_policy_path: Some(autonomy_policy_path(workstream_id)),
        risk_evaluation_path: Some(risk_evaluation_path(workstream_id)),
        approval_gating_decision_path: Some(approval_gating_decision_path(workstream_id)),
        autonomy_calibration_dataset_path: Some(autonomy_calibration_dataset_path(workstream_id)),
        autonomy_policy_eval_report_path: Some(autonomy_policy_eval_report_path(workstream_id)),
        escalation_thresholds_path: Some(escalation_thresholds_path(workstream_id)),
        shadow_policy_comparison_path: Some(shadow_policy_comparison_path(workstream_id)),
        updated_policy_recommendation_path: Some(updated_policy_recommendation_path(workstream_id)),
        autonomy_policy_current_path: Some(autonomy_policy_current_path(workstream_id)),
        autonomy_policy_candidate_path: Some(autonomy_policy_candidate_path(workstream_id)),
        rollout_metrics_path: Some(rollout_metrics_path(workstream_id)),
        rollout_decision_path: Some(rollout_decision_path(workstream_id)),
        continuation_dispatch_path: Some(continuation_dispatch_path(workstream_id)),
        continuation_receipt_path: Some(continuation_receipt_path(workstream_id)),
        continuation_state_path: Some(continuation_state_path(workstream_id)),
        operator_execution_state: OPERATOR_EXECUTION_STATE.to_string(),
        note: "B24.3 keeps execution bounded: approval persists state and visibility, but does not start autonomous work or auto-accept replan suggestions.".to_string(),
    };
    let result_links = ExecutionResultLinksDocument {
        links_version: EXECUTION_RESULT_LINKS_VERSION.to_string(),
        execution_id,
        plan_id: request.execution_plan.plan_id.clone(),
        workstream_id: request.execution_plan.workstream_id.clone(),
        workspace_id: request.execution_plan.workspace_id.clone(),
        session_id: request.execution_plan.session_id.clone(),
        links: vec![],
        note: "Result links are empty until bounded execution starts and produces receipts.".to_string(),
    };
    let record = PersistedPlanExecutionRecord {
        record_version: PLAN_EXECUTION_RECORD_VERSION.to_string(),
        execution_plan: request.execution_plan.clone(),
        approval: approval.clone(),
        execution_state,
        execution_receipt: None,
        execution_result_links: result_links,
        execution_reflection: None,
        trajectory_eval: None,
        replan_suggestion: None,
        review_inbox_item: None,
        review_decision: None,
        follow_on_plan: None,
        autonomy_policy: None,
        risk_evaluation: None,
        approval_gating_decision: None,
        autonomy_calibration_dataset: None,
        autonomy_policy_eval_report: None,
        escalation_thresholds: None,
        shadow_policy_comparison: None,
        updated_policy_recommendation: None,
        autonomy_policy_current: None,
        autonomy_policy_candidate: None,
        rollout_metrics: None,
        rollout_decision: None,
        autonomy_policy_control: None,
        autonomy_policy_canary: None,
        canary_rollout_metrics: None,
        canary_rollback_decision: None,
        autonomy_policy_analysis_candidate: None,
        analysis_shadow_comparison: None,
        analysis_rollout_metrics: None,
        analysis_rollout_decision: None,
        analysis_shadow_history: None,
        analysis_soak_metrics: None,
        analysis_promotion_gate: None,
        analysis_sample_accumulation: None,
        analysis_sample_accumulation_metrics: None,
        analysis_promotion_gate_recheck: None,
        autonomy_policy_analysis_control: None,
        autonomy_policy_implementation_canary_retained: None,
        autonomy_policy_analysis_canary: None,
        analysis_canary_metrics: None,
        analysis_canary_rollback_decision: None,
        autonomy_policy_manuscript_candidate: None,
        manuscript_shadow_comparison: None,
        manuscript_rollout_metrics: None,
        manuscript_rollout_decision: None,
        manuscript_shadow_history: None,
        manuscript_soak_metrics: None,
        manuscript_promotion_gate: None,
        manuscript_alignment_labels: None,
        manuscript_promotion_evidence: None,
        manuscript_trajectory_quality: None,
        manuscript_context_adequacy: None,
        manuscript_tuning_recommendation: None,
        continuation_dispatch: None,
        continuation_receipt: None,
        continuation_state: None,
    };
    write_execution_record(data_dir, &context_packet.packet.workspace_id, &record)?;
    Ok(approval)
}

pub fn start_execution_plan(
    data_dir: &Path,
    cfg: &BeagleConfig,
    workstream_id: &str,
    context_packet: WorkstreamContextPacketResponse,
    request: PlanExecutionStartRequest<'_>,
) -> anyhow::Result<ExecutionStatePlane> {
    let mut record = read_required_execution_record(data_dir, &context_packet.packet.workspace_id)?;
    validate_record_identity(workstream_id, &context_packet.packet, &record)?;
    if record.execution_plan.plan_id != request.plan_id {
        return Err(anyhow!(
            "execution plan mismatch: expected '{}' but received '{}'",
            record.execution_plan.plan_id,
            request.plan_id
        ));
    }
    if !matches!(record.execution_state.current_state.as_str(), "approved" | "planned") {
        return Err(anyhow!(
            "execution cannot start from current_state '{}'",
            record.execution_state.current_state
        ));
    }

    let started_by = normalize_sentence(request.started_by);
    let start_note = normalize_sentence(request.start_note);
    if started_by.is_empty() {
        return Err(anyhow!("started_by must not be empty"));
    }
    if start_note.is_empty() {
        return Err(anyhow!("start_note must not be empty"));
    }

    let started_at = Utc::now();
    record.execution_state.current_state = "running".to_string();
    record.execution_state.started_at = Some(started_at);
    record.execution_state.state_transitions.push(ExecutionStateTransition {
        state: "running".to_string(),
        transitioned_at: started_at,
        note: format!(
            "Operator {} started bounded execution: {}",
            started_by, start_note
        ),
    });

    let handoff_ref = maybe_record_execution_handoff(
        data_dir,
        cfg,
        workstream_id,
        &context_packet,
        &record.execution_plan,
    )?;
    let mut result_links = build_execution_result_links(
        &record.execution_plan,
        &record.execution_state.execution_id,
        handoff_ref.as_deref(),
    );
    let finished_at = Utc::now();
    record.execution_state.current_state = "succeeded".to_string();
    record.execution_state.finished_at = Some(finished_at);
    record.execution_state.state_transitions.push(ExecutionStateTransition {
        state: "succeeded".to_string(),
        transitioned_at: finished_at,
        note: "The bounded orchestrator closed execution with receipts and result links, without escalating into autonomous chaining.".to_string(),
    });
    let trajectory_eval = build_trajectory_eval(
        &record.execution_plan,
        &record.execution_state,
        &result_links,
        &context_packet.packet,
    );
    let reflection = build_execution_reflection(
        &record.execution_plan,
        &record.execution_state,
        &context_packet.packet,
        &trajectory_eval,
    );
    let replan_suggestion = build_replan_suggestion(
        &record.execution_plan,
        &context_packet.packet,
        &trajectory_eval,
        &reflection,
    );
    augment_result_links_with_reflection(
        &mut result_links,
        &record.execution_state.execution_id,
        record.execution_state.reflection_path.as_deref(),
        record.execution_state.trajectory_eval_path.as_deref(),
        record.execution_state.replan_suggestion_path.as_deref(),
    );
    let receipt = ExecutionReceipt {
        receipt_version: EXECUTION_RECEIPT_VERSION.to_string(),
        receipt_id: format!(
            "{}-receipt-{}",
            sanitize_component(&record.execution_state.execution_id),
            finished_at.timestamp_millis()
        ),
        execution_id: record.execution_state.execution_id.clone(),
        plan_id: record.execution_plan.plan_id.clone(),
        workstream_id: record.execution_plan.workstream_id.clone(),
        workspace_id: record.execution_plan.workspace_id.clone(),
        session_id: record.execution_plan.session_id.clone(),
        final_state: record.execution_state.current_state.clone(),
        recorded_at: finished_at,
        selected_subagent_id: record.execution_plan.selected_subagent_id.clone(),
        recipe_kind: record
            .execution_plan
            .recipe_target
            .as_ref()
            .map(|target| target.recipe_kind.clone()),
        experiment_id: record
            .execution_plan
            .experiment_target
            .as_ref()
            .map(|target| target.experiment_id.clone()),
        result_link_count: result_links.links.len(),
        result_links_path: record.execution_state.execution_result_links_path.clone(),
        handoff_updated: handoff_ref.is_some(),
        handoff_ref,
        reflection_id: Some(reflection.reflection_id.clone()),
        trajectory_eval_id: Some(trajectory_eval.trajectory_eval_id.clone()),
        replan_suggestion_id: Some(replan_suggestion.suggestion_id.clone()),
        quality_score: Some(reflection.overall_quality_score),
        trajectory_quality: Some(trajectory_eval.trajectory_quality.clone()),
        replan_required: replan_suggestion.replan_required,
        operator_followup_action: Some(replan_suggestion.requested_operator_action.clone()),
        review_requested: false,
        review_inbox_state: None,
        review_inbox_item_id: None,
        review_decision_id: None,
        review_decision_action: None,
        follow_on_plan_id: None,
        follow_on_plan_available: false,
        latest_autonomy_policy_id: None,
        latest_risk_evaluation_id: None,
        latest_approval_gating_decision_id: None,
        latest_autonomy_calibration_dataset_id: None,
        latest_autonomy_policy_eval_report_id: None,
        latest_escalation_thresholds_id: None,
        latest_shadow_policy_comparison_id: None,
        latest_updated_policy_recommendation_id: None,
        latest_autonomy_policy_current_id: None,
        latest_autonomy_policy_candidate_id: None,
        latest_rollout_metrics_id: None,
        latest_guarded_rollout_decision_id: None,
        approval_gating_decision_class: None,
        approval_gating_risk_level: None,
        approval_gating_dispatch_ready: false,
        approval_gating_blocked: false,
        continuation_dispatched: false,
        latest_continuation_dispatch_id: None,
        latest_continuation_receipt_id: None,
        continuation_current_state: None,
        continuation_source_execution_id: None,
        continuation_next_execution_id: None,
        continuation_next_plan_id: None,
        continuation_review_action: None,
        autonomy_policy_calibration_status: None,
        autonomy_policy_rollout_status: None,
        review_inbox_path: record.execution_state.review_inbox_path.clone(),
        review_decision_path: record.execution_state.review_decision_path.clone(),
        follow_on_plan_path: record.execution_state.follow_on_plan_path.clone(),
        autonomy_policy_path: record.execution_state.autonomy_policy_path.clone(),
        risk_evaluation_path: record.execution_state.risk_evaluation_path.clone(),
        approval_gating_decision_path: record.execution_state.approval_gating_decision_path.clone(),
        autonomy_calibration_dataset_path: record.execution_state.autonomy_calibration_dataset_path.clone(),
        autonomy_policy_eval_report_path: record.execution_state.autonomy_policy_eval_report_path.clone(),
        escalation_thresholds_path: record.execution_state.escalation_thresholds_path.clone(),
        shadow_policy_comparison_path: record.execution_state.shadow_policy_comparison_path.clone(),
        updated_policy_recommendation_path: record.execution_state.updated_policy_recommendation_path.clone(),
        autonomy_policy_current_path: record.execution_state.autonomy_policy_current_path.clone(),
        autonomy_policy_candidate_path: record.execution_state.autonomy_policy_candidate_path.clone(),
        rollout_metrics_path: record.execution_state.rollout_metrics_path.clone(),
        rollout_decision_path: record.execution_state.rollout_decision_path.clone(),
        continuation_dispatch_path: record.execution_state.continuation_dispatch_path.clone(),
        continuation_receipt_path: record.execution_state.continuation_receipt_path.clone(),
        continuation_state_path: record.execution_state.continuation_state_path.clone(),
        reflection_path: record.execution_state.reflection_path.clone(),
        trajectory_eval_path: record.execution_state.trajectory_eval_path.clone(),
        replan_suggestion_path: record.execution_state.replan_suggestion_path.clone(),
        operator_execution_state: OPERATOR_EXECUTION_STATE.to_string(),
        note: "B24.3 receipts link the bounded execution back into the same Beagle-owned workstream/workspace/session identity and attach reflection/replan outputs without auto-running them.".to_string(),
    };
    record.execution_state.latest_receipt_id = Some(receipt.receipt_id.clone());
    record.execution_state.latest_reflection_id = Some(reflection.reflection_id.clone());
    record.execution_state.latest_trajectory_eval_id = Some(trajectory_eval.trajectory_eval_id.clone());
    record.execution_state.latest_replan_suggestion_id =
        Some(replan_suggestion.suggestion_id.clone());
    record.execution_state.latest_quality_score = Some(reflection.overall_quality_score);
    record.execution_state.latest_trajectory_quality =
        Some(trajectory_eval.trajectory_quality.clone());
    record.execution_state.replan_required = replan_suggestion.replan_required;
    record.execution_state.operator_followup_action =
        Some(replan_suggestion.requested_operator_action.clone());
    clear_approval_gate_state(&mut record.execution_state);
    record.execution_receipt = Some(receipt);
    record.execution_result_links = result_links;
    record.execution_reflection = Some(reflection);
    record.trajectory_eval = Some(trajectory_eval);
    record.replan_suggestion = Some(replan_suggestion);
    record.review_inbox_item = None;
    record.review_decision = None;
    record.follow_on_plan = None;
    record.autonomy_policy = None;
    record.risk_evaluation = None;
    record.approval_gating_decision = None;
    record.continuation_dispatch = None;
    record.continuation_receipt = None;
    record.continuation_state = None;
    write_execution_record(data_dir, &context_packet.packet.workspace_id, &record)?;
    Ok(record.execution_state)
}

pub fn stop_execution_plan(
    data_dir: &Path,
    workstream_id: &str,
    context_packet: WorkstreamContextPacketResponse,
    request: PlanExecutionStopRequest<'_>,
) -> anyhow::Result<ExecutionStatePlane> {
    let mut record = read_required_execution_record(data_dir, &context_packet.packet.workspace_id)?;
    validate_record_identity(workstream_id, &context_packet.packet, &record)?;
    if record.execution_plan.plan_id != request.plan_id {
        return Err(anyhow!(
            "execution plan mismatch: expected '{}' but received '{}'",
            record.execution_plan.plan_id,
            request.plan_id
        ));
    }
    if matches!(
        record.execution_state.current_state.as_str(),
        "succeeded" | "failed" | "stopped"
    ) {
        return Err(anyhow!(
            "execution cannot be stopped from current_state '{}'",
            record.execution_state.current_state
        ));
    }

    let stopped_by = normalize_sentence(request.stopped_by);
    let stop_reason = normalize_sentence(request.stop_reason);
    if stopped_by.is_empty() {
        return Err(anyhow!("stopped_by must not be empty"));
    }
    if stop_reason.is_empty() {
        return Err(anyhow!("stop_reason must not be empty"));
    }

    let stopped_at = Utc::now();
    record.execution_state.current_state = "stopped".to_string();
    record.execution_state.stop_requested_at = Some(stopped_at);
    record.execution_state.finished_at = Some(stopped_at);
    record.execution_state.stop_reason = Some(stop_reason.clone());
    record.execution_state.state_transitions.push(ExecutionStateTransition {
        state: "stopped".to_string(),
        transitioned_at: stopped_at,
        note: format!("Operator {} stopped bounded execution: {}", stopped_by, stop_reason),
    });
    let mut result_links = build_execution_result_links(
        &record.execution_plan,
        &record.execution_state.execution_id,
        None,
    );
    let trajectory_eval = build_trajectory_eval(
        &record.execution_plan,
        &record.execution_state,
        &result_links,
        &context_packet.packet,
    );
    let reflection = build_execution_reflection(
        &record.execution_plan,
        &record.execution_state,
        &context_packet.packet,
        &trajectory_eval,
    );
    let replan_suggestion = build_replan_suggestion(
        &record.execution_plan,
        &context_packet.packet,
        &trajectory_eval,
        &reflection,
    );
    augment_result_links_with_reflection(
        &mut result_links,
        &record.execution_state.execution_id,
        record.execution_state.reflection_path.as_deref(),
        record.execution_state.trajectory_eval_path.as_deref(),
        record.execution_state.replan_suggestion_path.as_deref(),
    );
    let receipt = ExecutionReceipt {
        receipt_version: EXECUTION_RECEIPT_VERSION.to_string(),
        receipt_id: format!(
            "{}-receipt-{}",
            sanitize_component(&record.execution_state.execution_id),
            stopped_at.timestamp_millis()
        ),
        execution_id: record.execution_state.execution_id.clone(),
        plan_id: record.execution_plan.plan_id.clone(),
        workstream_id: record.execution_plan.workstream_id.clone(),
        workspace_id: record.execution_plan.workspace_id.clone(),
        session_id: record.execution_plan.session_id.clone(),
        final_state: "stopped".to_string(),
        recorded_at: stopped_at,
        selected_subagent_id: record.execution_plan.selected_subagent_id.clone(),
        recipe_kind: record
            .execution_plan
            .recipe_target
            .as_ref()
            .map(|target| target.recipe_kind.clone()),
        experiment_id: record
            .execution_plan
            .experiment_target
            .as_ref()
            .map(|target| target.experiment_id.clone()),
        result_link_count: result_links.links.len(),
        result_links_path: record.execution_state.execution_result_links_path.clone(),
        handoff_updated: false,
        handoff_ref: None,
        reflection_id: Some(reflection.reflection_id.clone()),
        trajectory_eval_id: Some(trajectory_eval.trajectory_eval_id.clone()),
        replan_suggestion_id: Some(replan_suggestion.suggestion_id.clone()),
        quality_score: Some(reflection.overall_quality_score),
        trajectory_quality: Some(trajectory_eval.trajectory_quality.clone()),
        replan_required: replan_suggestion.replan_required,
        operator_followup_action: Some(replan_suggestion.requested_operator_action.clone()),
        review_requested: false,
        review_inbox_state: None,
        review_inbox_item_id: None,
        review_decision_id: None,
        review_decision_action: None,
        follow_on_plan_id: None,
        follow_on_plan_available: false,
        latest_autonomy_policy_id: None,
        latest_risk_evaluation_id: None,
        latest_approval_gating_decision_id: None,
        latest_autonomy_calibration_dataset_id: None,
        latest_autonomy_policy_eval_report_id: None,
        latest_escalation_thresholds_id: None,
        latest_shadow_policy_comparison_id: None,
        latest_updated_policy_recommendation_id: None,
        latest_autonomy_policy_current_id: None,
        latest_autonomy_policy_candidate_id: None,
        latest_rollout_metrics_id: None,
        latest_guarded_rollout_decision_id: None,
        approval_gating_decision_class: None,
        approval_gating_risk_level: None,
        approval_gating_dispatch_ready: false,
        approval_gating_blocked: false,
        continuation_dispatched: false,
        latest_continuation_dispatch_id: None,
        latest_continuation_receipt_id: None,
        continuation_current_state: None,
        continuation_source_execution_id: None,
        continuation_next_execution_id: None,
        continuation_next_plan_id: None,
        continuation_review_action: None,
        autonomy_policy_calibration_status: None,
        autonomy_policy_rollout_status: None,
        review_inbox_path: record.execution_state.review_inbox_path.clone(),
        review_decision_path: record.execution_state.review_decision_path.clone(),
        follow_on_plan_path: record.execution_state.follow_on_plan_path.clone(),
        autonomy_policy_path: record.execution_state.autonomy_policy_path.clone(),
        risk_evaluation_path: record.execution_state.risk_evaluation_path.clone(),
        approval_gating_decision_path: record.execution_state.approval_gating_decision_path.clone(),
        autonomy_calibration_dataset_path: record.execution_state.autonomy_calibration_dataset_path.clone(),
        autonomy_policy_eval_report_path: record.execution_state.autonomy_policy_eval_report_path.clone(),
        escalation_thresholds_path: record.execution_state.escalation_thresholds_path.clone(),
        shadow_policy_comparison_path: record.execution_state.shadow_policy_comparison_path.clone(),
        updated_policy_recommendation_path: record.execution_state.updated_policy_recommendation_path.clone(),
        autonomy_policy_current_path: record.execution_state.autonomy_policy_current_path.clone(),
        autonomy_policy_candidate_path: record.execution_state.autonomy_policy_candidate_path.clone(),
        rollout_metrics_path: record.execution_state.rollout_metrics_path.clone(),
        rollout_decision_path: record.execution_state.rollout_decision_path.clone(),
        continuation_dispatch_path: record.execution_state.continuation_dispatch_path.clone(),
        continuation_receipt_path: record.execution_state.continuation_receipt_path.clone(),
        continuation_state_path: record.execution_state.continuation_state_path.clone(),
        reflection_path: record.execution_state.reflection_path.clone(),
        trajectory_eval_path: record.execution_state.trajectory_eval_path.clone(),
        replan_suggestion_path: record.execution_state.replan_suggestion_path.clone(),
        operator_execution_state: OPERATOR_EXECUTION_STATE.to_string(),
        note: "B24.3 stop receipts make bounded interruption explicit, preserve reflection, and ask for operator-visible replanning instead of auto-recovery.".to_string(),
    };
    record.execution_state.latest_receipt_id = Some(receipt.receipt_id.clone());
    record.execution_state.latest_reflection_id = Some(reflection.reflection_id.clone());
    record.execution_state.latest_trajectory_eval_id = Some(trajectory_eval.trajectory_eval_id.clone());
    record.execution_state.latest_replan_suggestion_id =
        Some(replan_suggestion.suggestion_id.clone());
    record.execution_state.latest_quality_score = Some(reflection.overall_quality_score);
    record.execution_state.latest_trajectory_quality =
        Some(trajectory_eval.trajectory_quality.clone());
    record.execution_state.replan_required = replan_suggestion.replan_required;
    record.execution_state.operator_followup_action =
        Some(replan_suggestion.requested_operator_action.clone());
    clear_approval_gate_state(&mut record.execution_state);
    record.execution_receipt = Some(receipt);
    record.execution_result_links = result_links;
    record.execution_reflection = Some(reflection);
    record.trajectory_eval = Some(trajectory_eval);
    record.replan_suggestion = Some(replan_suggestion);
    record.review_inbox_item = None;
    record.review_decision = None;
    record.follow_on_plan = None;
    record.autonomy_policy = None;
    record.risk_evaluation = None;
    record.approval_gating_decision = None;
    record.continuation_dispatch = None;
    record.continuation_receipt = None;
    record.continuation_state = None;
    write_execution_record(data_dir, &context_packet.packet.workspace_id, &record)?;
    Ok(record.execution_state)
}

pub fn materialize_review_inbox_item(
    data_dir: &Path,
    workstream_id: &str,
    context_packet: WorkstreamContextPacketResponse,
    request: ReviewInboxMaterializeRequest<'_>,
) -> anyhow::Result<ReviewInboxItem> {
    let mut record = read_required_execution_record(data_dir, &context_packet.packet.workspace_id)?;
    validate_record_identity(workstream_id, &context_packet.packet, &record)?;
    let created_by = normalize_sentence(request.created_by);
    let create_note = normalize_sentence(request.create_note);
    if created_by.is_empty() {
        return Err(anyhow!("created_by must not be empty"));
    }
    if create_note.is_empty() {
        return Err(anyhow!("create_note must not be empty"));
    }
    let Some(replan_suggestion) = record.replan_suggestion.as_ref() else {
        return Err(anyhow!("replan suggestion must exist before materializing review inbox"));
    };
    if let Some(existing) = record.review_inbox_item.as_ref() {
        if existing.replan_suggestion_id == replan_suggestion.suggestion_id {
            return Ok(existing.clone());
        }
    }

    let inbox_item = build_review_inbox_item(
        &record.execution_state,
        replan_suggestion,
        &created_by,
        &create_note,
        &review_decision_path(workstream_id),
        &follow_on_plan_path(workstream_id),
    );
    record.execution_state.review_requested = true;
    record.execution_state.review_inbox_state = Some(inbox_item.inbox_state.clone());
    record.execution_state.latest_review_inbox_item_id = Some(inbox_item.inbox_item_id.clone());
    record.execution_state.latest_review_decision_id = None;
    record.execution_state.latest_review_decision_action = None;
    record.execution_state.latest_follow_on_plan_id = None;
    record.execution_state.follow_on_plan_available = false;
    clear_approval_gate_state(&mut record.execution_state);
    clear_autonomy_calibration_evidence_artifacts(&mut record);
    record.execution_state.continuation_dispatched = false;
    record.execution_state.latest_continuation_dispatch_id = None;
    record.execution_state.latest_continuation_receipt_id = None;
    record.execution_state.continuation_current_state = None;
    record.execution_state.continuation_source_execution_id = None;
    record.execution_state.continuation_next_execution_id = None;
    record.execution_state.continuation_next_plan_id = None;
    record.execution_state.continuation_review_action = None;
    record.execution_state.operator_followup_action =
        Some(inbox_item.requested_operator_action.clone());
    record.review_inbox_item = Some(inbox_item.clone());
    record.review_decision = None;
    record.follow_on_plan = None;
    record.autonomy_policy = None;
    record.risk_evaluation = None;
    record.approval_gating_decision = None;
    record.continuation_dispatch = None;
    record.continuation_receipt = None;
    record.continuation_state = None;
    if let Some(receipt) = record.execution_receipt.as_mut() {
        sync_receipt_from_review_state(receipt, &record.execution_state);
        sync_receipt_from_approval_gate_state(receipt, &record.execution_state);
        sync_receipt_from_continuation_state(receipt, &record.execution_state);
    }
    upsert_result_link(
        &mut record.execution_result_links,
        execution_result_link(
            &record.execution_state.execution_id,
            "review-inbox-item",
            &review_inbox_path(workstream_id),
            "Operator-visible review inbox item materialized from the latest replan suggestion.",
        ),
    );
    remove_result_link_kind(&mut record.execution_result_links, "review-decision");
    remove_result_link_kind(&mut record.execution_result_links, "follow-on-plan");
    remove_result_link_kind(&mut record.execution_result_links, "autonomy-policy");
    remove_result_link_kind(&mut record.execution_result_links, "risk-evaluation");
    remove_result_link_kind(&mut record.execution_result_links, "approval-gating-decision");
    write_execution_record(data_dir, &context_packet.packet.workspace_id, &record)?;
    Ok(inbox_item)
}

pub fn decide_review_inbox_item(
    data_dir: &Path,
    cfg: &BeagleConfig,
    workstream_id: &str,
    context_packet: WorkstreamContextPacketResponse,
    request: ReviewInboxDecisionRequest,
) -> anyhow::Result<ReviewDecision> {
    let mut record = read_required_execution_record(data_dir, &context_packet.packet.workspace_id)?;
    validate_record_identity(workstream_id, &context_packet.packet, &record)?;
    let Some(inbox_item) = record.review_inbox_item.as_ref() else {
        return Err(anyhow!("review inbox item not found for workspace '{}'", record.execution_plan.workspace_id));
    };
    if inbox_item.inbox_item_id != request.inbox_item_id {
        return Err(anyhow!(
            "review inbox mismatch: expected '{}' but received '{}'",
            inbox_item.inbox_item_id,
            request.inbox_item_id
        ));
    }
    let Some(replan_suggestion) = record.replan_suggestion.as_ref() else {
        return Err(anyhow!("replan suggestion not found for current execution"));
    };
    let action = normalize_review_decision_action(&request.decision_action);
    if !matches!(action.as_str(), "approved" | "edited" | "rejected") {
        return Err(anyhow!(
            "unsupported review decision action '{}'",
            request.decision_action
        ));
    }
    let decided_by = normalize_sentence(&request.decided_by);
    let decision_note = normalize_sentence(&request.decision_note);
    if decided_by.is_empty() {
        return Err(anyhow!("decided_by must not be empty"));
    }
    if decision_note.is_empty() {
        return Err(anyhow!("decision_note must not be empty"));
    }

    let mut follow_on_plan = if matches!(action.as_str(), "approved" | "edited") {
        Some(build_follow_on_plan(
            &record.execution_plan,
            inbox_item,
            replan_suggestion,
            &action,
            &decided_by,
            request.edit_patch.as_ref(),
        ))
    } else {
        None
    };

    let mut decision = build_review_decision(
        &inbox_item.inbox_item_id,
        &record.execution_state.execution_id,
        &record.execution_plan.plan_id,
        &record.execution_plan.workstream_id,
        &record.execution_plan.workspace_id,
        &record.execution_plan.session_id,
        &action,
        &decided_by,
        &decision_note,
        request.edit_patch.as_ref(),
        follow_on_plan
            .as_ref()
            .map(|follow_on_plan| follow_on_plan.follow_on_plan_id.clone()),
    );

    let mut updated_inbox = inbox_item.clone();
    updated_inbox.inbox_state = action.clone();
    record.execution_state.review_requested = false;
    record.execution_state.review_inbox_state = Some(action.clone());
    record.execution_state.latest_review_inbox_item_id = Some(updated_inbox.inbox_item_id.clone());
    record.execution_state.latest_review_decision_id = Some(decision.decision_id.clone());
    record.execution_state.latest_review_decision_action = Some(action.clone());
    record.execution_state.latest_follow_on_plan_id = follow_on_plan
        .as_ref()
        .map(|follow_on_plan| follow_on_plan.follow_on_plan_id.clone());
    record.execution_state.follow_on_plan_available = follow_on_plan.is_some();
    clear_approval_gate_state(&mut record.execution_state);
    clear_autonomy_calibration_evidence_artifacts(&mut record);
    record.execution_state.continuation_dispatched = false;
    record.execution_state.latest_continuation_dispatch_id = None;
    record.execution_state.latest_continuation_receipt_id = None;
    record.execution_state.continuation_current_state = None;
    record.execution_state.continuation_source_execution_id = None;
    record.execution_state.continuation_next_execution_id = None;
    record.execution_state.continuation_next_plan_id = None;
    record.execution_state.continuation_review_action = None;
    record.execution_state.operator_followup_action = Some("review-and-plan-again".to_string());
    record.autonomy_policy = None;
    record.risk_evaluation = None;
    record.approval_gating_decision = None;
    if let Some(follow_on_plan_item) = follow_on_plan.as_mut() {
        let (autonomy_policy, risk_evaluation, approval_gating_decision) = evaluate_follow_on_plan_gate(
            &record,
            workstream_id,
            &updated_inbox,
            &decision,
            follow_on_plan_item,
        )?;
        follow_on_plan_item.follow_on_state =
            approval_gating_decision.follow_on_state_after_gating.clone();
        follow_on_plan_item.autonomy_policy_id = Some(autonomy_policy.policy_id.clone());
        follow_on_plan_item.risk_evaluation_id = Some(risk_evaluation.risk_evaluation_id.clone());
        follow_on_plan_item.approval_gating_decision_id =
            Some(approval_gating_decision.approval_gating_decision_id.clone());
        follow_on_plan_item.approval_gating_decision_class =
            Some(approval_gating_decision.decision_class.clone());
        follow_on_plan_item.approval_gating_decision_path =
            Some(approval_gating_decision_path(workstream_id));

        updated_inbox.requested_operator_action =
            approval_gating_decision.requested_operator_action.clone();
        updated_inbox.autonomy_policy_id = Some(autonomy_policy.policy_id.clone());
        updated_inbox.risk_evaluation_id = Some(risk_evaluation.risk_evaluation_id.clone());
        updated_inbox.approval_gating_decision_id =
            Some(approval_gating_decision.approval_gating_decision_id.clone());
        updated_inbox.approval_gating_decision_class =
            Some(approval_gating_decision.decision_class.clone());
        updated_inbox.autonomy_policy_path = Some(autonomy_policy_path(workstream_id));
        updated_inbox.risk_evaluation_path = Some(risk_evaluation_path(workstream_id));
        updated_inbox.approval_gating_decision_path =
            Some(approval_gating_decision_path(workstream_id));

        decision.autonomy_policy_id = Some(autonomy_policy.policy_id.clone());
        decision.risk_evaluation_id = Some(risk_evaluation.risk_evaluation_id.clone());
        decision.approval_gating_decision_id =
            Some(approval_gating_decision.approval_gating_decision_id.clone());
        decision.approval_gating_decision_class =
            Some(approval_gating_decision.decision_class.clone());
        decision.auto_continue_eligible = approval_gating_decision.auto_continuation_enabled;
        decision.dispatch_blocked = approval_gating_decision.blocked;

        record.execution_state.latest_autonomy_policy_id = Some(autonomy_policy.policy_id.clone());
        record.execution_state.latest_risk_evaluation_id =
            Some(risk_evaluation.risk_evaluation_id.clone());
        record.execution_state.latest_approval_gating_decision_id =
            Some(approval_gating_decision.approval_gating_decision_id.clone());
        record.execution_state.approval_gating_decision_class =
            Some(approval_gating_decision.decision_class.clone());
        record.execution_state.approval_gating_risk_level =
            Some(risk_evaluation.risk_level.clone());
        record.execution_state.approval_gating_dispatch_ready =
            approval_gating_decision.continuation_dispatch_permitted;
        record.execution_state.approval_gating_blocked = approval_gating_decision.blocked;
        record.execution_state.operator_followup_action =
            Some(approval_gating_decision.requested_operator_action.clone());

        record.autonomy_policy = Some(autonomy_policy);
        record.risk_evaluation = Some(risk_evaluation);
        record.approval_gating_decision = Some(approval_gating_decision);
    }
    record.review_inbox_item = Some(updated_inbox);
    record.review_decision = Some(decision.clone());
    record.follow_on_plan = follow_on_plan.clone();
    record.continuation_dispatch = None;
    record.continuation_receipt = None;
    record.continuation_state = None;
    if let Some(receipt) = record.execution_receipt.as_mut() {
        sync_receipt_from_review_state(receipt, &record.execution_state);
        sync_receipt_from_approval_gate_state(receipt, &record.execution_state);
        sync_receipt_from_continuation_state(receipt, &record.execution_state);
        receipt.operator_followup_action = record.execution_state.operator_followup_action.clone();
    }
    upsert_result_link(
        &mut record.execution_result_links,
        execution_result_link(
            &record.execution_state.execution_id,
            "review-decision",
            &review_decision_path(workstream_id),
            "Operator review decision recorded for the latest follow-on plan queue item.",
        ),
    );
    if follow_on_plan.is_some() {
        upsert_result_link(
            &mut record.execution_result_links,
            execution_result_link(
                &record.execution_state.execution_id,
                "follow-on-plan",
                &follow_on_plan_path(workstream_id),
                "Follow-on execution plan materialized from the operator review decision.",
            ),
        );
    } else {
        remove_result_link_kind(&mut record.execution_result_links, "follow-on-plan");
    }
    if record.autonomy_policy.is_some() {
        upsert_result_link(
            &mut record.execution_result_links,
            execution_result_link(
                &record.execution_state.execution_id,
                "autonomy-policy",
                &autonomy_policy_path(workstream_id),
                "Canonical autonomy policy snapshot linked to the same follow-on execution identity.",
            ),
        );
        upsert_result_link(
            &mut record.execution_result_links,
            execution_result_link(
                &record.execution_state.execution_id,
                "risk-evaluation",
                &risk_evaluation_path(workstream_id),
                "Risk evaluation for the bounded follow-on plan linked to the same execution identity.",
            ),
        );
        upsert_result_link(
            &mut record.execution_result_links,
            execution_result_link(
                &record.execution_state.execution_id,
                "approval-gating-decision",
                &approval_gating_decision_path(workstream_id),
                "Approval gating decision classifying the follow-on plan as auto-continue, review-required, or blocked.",
            ),
        );
    } else {
        remove_result_link_kind(&mut record.execution_result_links, "autonomy-policy");
        remove_result_link_kind(&mut record.execution_result_links, "risk-evaluation");
        remove_result_link_kind(&mut record.execution_result_links, "approval-gating-decision");
    }
    write_execution_record(data_dir, &context_packet.packet.workspace_id, &record)?;
    if record
        .approval_gating_decision
        .as_ref()
        .map(|decision| decision.auto_continuation_enabled)
        .unwrap_or(false)
    {
        dispatch_follow_on_plan(
            data_dir,
            cfg,
            workstream_id,
            context_packet,
            ContinuationDispatchRequest {
                dispatched_by: &decided_by,
                dispatch_note: if record
                    .approval_gating_decision
                    .as_ref()
                    .is_some_and(|decision| {
                        decision.matched_policy_rule == "guarded-implementation-canary-lane"
                    }) {
                    "B24.9 auto-continued the implementation follow-on plan on the guarded canary lane after policy evaluation."
                } else if record
                    .approval_gating_decision
                    .as_ref()
                    .is_some_and(|decision| {
                        decision.matched_policy_rule == "guarded-analysis-canary-lane"
                    }) {
                    "B24.13 auto-continued the analysis follow-on plan on the guarded canary lane after policy evaluation."
                } else {
                    "B24.6 auto-continued the low-risk follow-on plan after policy evaluation."
                },
            },
        )?;
    }
    Ok(decision)
}

pub fn dispatch_follow_on_plan(
    data_dir: &Path,
    cfg: &BeagleConfig,
    workstream_id: &str,
    context_packet: WorkstreamContextPacketResponse,
    request: ContinuationDispatchRequest<'_>,
) -> anyhow::Result<ContinuationDispatch> {
    let mut record = read_required_execution_record(data_dir, &context_packet.packet.workspace_id)?;
    validate_record_identity(workstream_id, &context_packet.packet, &record)?;

    let Some(review_inbox_item) = record.review_inbox_item.clone() else {
        return Err(anyhow!("review inbox item must exist before continuation dispatch"));
    };
    let Some(review_decision) = record.review_decision.clone() else {
        return Err(anyhow!("review decision must exist before continuation dispatch"));
    };
    let Some(mut follow_on_plan) = record.follow_on_plan.clone() else {
        return Err(anyhow!("follow-on plan must exist before continuation dispatch"));
    };
    if !matches!(review_decision.decision_action.as_str(), "approved" | "edited") {
        return Err(anyhow!(
            "continuation dispatch requires an approved or edited review decision, found '{}'",
            review_decision.decision_action
        ));
    }
    if let Some(existing) = record.continuation_dispatch.as_ref() {
        if existing.follow_on_plan_id == follow_on_plan.follow_on_plan_id {
            return Ok(existing.clone());
        }
    }
    clear_autonomy_calibration_evidence_artifacts(&mut record);
    if record.approval_gating_decision.is_none() {
        let (autonomy_policy, risk_evaluation, approval_gating_decision) = evaluate_follow_on_plan_gate(
            &record,
            workstream_id,
            &review_inbox_item,
            &review_decision,
            &follow_on_plan,
        )?;
        follow_on_plan.follow_on_state = approval_gating_decision.follow_on_state_after_gating.clone();
        follow_on_plan.autonomy_policy_id = Some(autonomy_policy.policy_id.clone());
        follow_on_plan.risk_evaluation_id = Some(risk_evaluation.risk_evaluation_id.clone());
        follow_on_plan.approval_gating_decision_id =
            Some(approval_gating_decision.approval_gating_decision_id.clone());
        follow_on_plan.approval_gating_decision_class =
            Some(approval_gating_decision.decision_class.clone());
        follow_on_plan.approval_gating_decision_path =
            Some(approval_gating_decision_path(workstream_id));
        record.execution_state.latest_autonomy_policy_id = Some(autonomy_policy.policy_id.clone());
        record.execution_state.latest_risk_evaluation_id =
            Some(risk_evaluation.risk_evaluation_id.clone());
        record.execution_state.latest_approval_gating_decision_id =
            Some(approval_gating_decision.approval_gating_decision_id.clone());
        record.execution_state.approval_gating_decision_class =
            Some(approval_gating_decision.decision_class.clone());
        record.execution_state.approval_gating_risk_level =
            Some(risk_evaluation.risk_level.clone());
        record.execution_state.approval_gating_dispatch_ready =
            approval_gating_decision.continuation_dispatch_permitted;
        record.execution_state.approval_gating_blocked = approval_gating_decision.blocked;
        record.execution_state.operator_followup_action =
            Some(approval_gating_decision.requested_operator_action.clone());
        record.follow_on_plan = Some(follow_on_plan.clone());
        record.autonomy_policy = Some(autonomy_policy);
        record.risk_evaluation = Some(risk_evaluation);
        record.approval_gating_decision = Some(approval_gating_decision);
        upsert_result_link(
            &mut record.execution_result_links,
            execution_result_link(
                &record.execution_state.execution_id,
                "autonomy-policy",
                &autonomy_policy_path(workstream_id),
                "Canonical autonomy policy snapshot linked to the same follow-on execution identity.",
            ),
        );
        upsert_result_link(
            &mut record.execution_result_links,
            execution_result_link(
                &record.execution_state.execution_id,
                "risk-evaluation",
                &risk_evaluation_path(workstream_id),
                "Risk evaluation for the bounded follow-on plan linked to the same execution identity.",
            ),
        );
        upsert_result_link(
            &mut record.execution_result_links,
            execution_result_link(
                &record.execution_state.execution_id,
                "approval-gating-decision",
                &approval_gating_decision_path(workstream_id),
                "Approval gating decision classifying the follow-on plan as auto-continue, review-required, or blocked.",
            ),
        );
        if let Some(receipt) = record.execution_receipt.as_mut() {
            sync_receipt_from_approval_gate_state(receipt, &record.execution_state);
            receipt.operator_followup_action = record.execution_state.operator_followup_action.clone();
        }
    }
    let approval_gating_decision = record
        .approval_gating_decision
        .clone()
        .ok_or_else(|| anyhow!("approval gating decision must exist before continuation dispatch"))?;
    if approval_gating_decision.blocked {
        return Err(anyhow!(
            "continuation dispatch blocked by approval gate '{}' for follow-on plan '{}'",
            approval_gating_decision.approval_gating_decision_id,
            follow_on_plan.follow_on_plan_id
        ));
    }

    let dispatched_by = normalize_sentence(request.dispatched_by);
    let dispatch_note = normalize_sentence(request.dispatch_note);
    if dispatched_by.is_empty() {
        return Err(anyhow!("dispatched_by must not be empty"));
    }
    if dispatch_note.is_empty() {
        return Err(anyhow!("dispatch_note must not be empty"));
    }

    let dispatched_at = Utc::now();
    let source_execution_id = record.execution_state.execution_id.clone();
    let source_plan_id = record.execution_plan.plan_id.clone();
    let source_receipt_id = record
        .execution_receipt
        .as_ref()
        .map(|receipt| receipt.receipt_id.clone());
    let next_execution_id = format!(
        "{}-execution-{}",
        sanitize_component(&follow_on_plan.execution_plan.plan_id),
        dispatched_at.timestamp_millis()
    );
    let continuation_dispatch = ContinuationDispatch {
        dispatch_version: CONTINUATION_DISPATCH_VERSION.to_string(),
        continuation_dispatch_id: format!(
            "{}-continuation-dispatch-{}",
            sanitize_component(&source_execution_id),
            dispatched_at.timestamp_millis()
        ),
        source_execution_id: source_execution_id.clone(),
        source_plan_id: source_plan_id.clone(),
        source_receipt_id: source_receipt_id.clone(),
        review_inbox_item_id: review_inbox_item.inbox_item_id.clone(),
        review_decision_id: review_decision.decision_id.clone(),
        follow_on_plan_id: follow_on_plan.follow_on_plan_id.clone(),
        workstream_id: follow_on_plan.workstream_id.clone(),
        workspace_id: follow_on_plan.workspace_id.clone(),
        session_id: follow_on_plan.session_id.clone(),
        review_action: review_decision.decision_action.clone(),
        dispatch_state: "dispatched".to_string(),
        dispatched_by: dispatched_by.clone(),
        dispatch_note: dispatch_note.clone(),
        dispatched_at,
        operator_visibility_confirmed: true,
        next_execution_id: next_execution_id.clone(),
        next_plan_id: follow_on_plan.execution_plan.plan_id.clone(),
        next_task_family: follow_on_plan.execution_plan.task_family.clone(),
        next_selected_subagent_id: follow_on_plan.execution_plan.selected_subagent_id.clone(),
        next_retrieval_query_type: follow_on_plan.execution_plan.retrieval_query_type.clone(),
        next_compiler_profile_id: follow_on_plan.execution_plan.compiler_profile_id.clone(),
        next_graphrag_query_mode: follow_on_plan.execution_plan.graphrag_query_mode.clone(),
        next_temporal_truth_view: follow_on_plan.execution_plan.temporal_truth_view.clone(),
        autonomy_policy_id: record
            .autonomy_policy
            .as_ref()
            .map(|policy| policy.policy_id.clone()),
        risk_evaluation_id: record
            .risk_evaluation
            .as_ref()
            .map(|evaluation| evaluation.risk_evaluation_id.clone()),
        approval_gating_decision_id: Some(
            approval_gating_decision.approval_gating_decision_id.clone(),
        ),
        approval_gating_decision_class: Some(approval_gating_decision.decision_class.clone()),
        approval_gating_risk_level: record
            .risk_evaluation
            .as_ref()
            .map(|evaluation| evaluation.risk_level.clone()),
        continuation_state_path: continuation_state_path(workstream_id),
        continuation_receipt_path: continuation_receipt_path(workstream_id),
        note: "B24.5 dispatches one operator-approved follow-on plan into the next bounded execution cycle, while keeping the same Beagle-owned workstream/workspace/session identity and chaining receipts explicitly.".to_string(),
    };

    let handoff_ref = maybe_record_execution_handoff(
        data_dir,
        cfg,
        workstream_id,
        &context_packet,
        &follow_on_plan.execution_plan,
    )?;
    let mut next_result_links = build_execution_result_links(
        &follow_on_plan.execution_plan,
        &next_execution_id,
        handoff_ref.as_deref(),
    );
    upsert_result_link(
        &mut next_result_links,
        execution_result_link(
            &next_execution_id,
            "continuation-dispatch",
            &continuation_dispatch_path(workstream_id),
            "Continuation dispatch metadata linked to the follow-on execution.",
        ),
    );
    upsert_result_link(
        &mut next_result_links,
        execution_result_link(
            &next_execution_id,
            "continuation-state",
            &continuation_dispatch.continuation_state_path,
            "Continuation state linked to the follow-on execution.",
        ),
    );
    upsert_result_link(
        &mut next_result_links,
        execution_result_link(
            &next_execution_id,
            "continuation-receipt",
            &continuation_dispatch.continuation_receipt_path,
            "Continuation receipt chaining review, dispatch, and the next bounded execution.",
        ),
    );

    let finished_at = Utc::now();
    let next_execution_state = ExecutionStatePlane {
        state_version: EXECUTION_STATE_VERSION.to_string(),
        execution_id: next_execution_id.clone(),
        planner_policy_id: follow_on_plan.execution_plan.planner_policy_id.clone(),
        plan_id: follow_on_plan.execution_plan.plan_id.clone(),
        workstream_id: follow_on_plan.execution_plan.workstream_id.clone(),
        workspace_id: follow_on_plan.execution_plan.workspace_id.clone(),
        session_id: follow_on_plan.execution_plan.session_id.clone(),
        program_id: follow_on_plan.execution_plan.program_id.clone(),
        campaign_id: follow_on_plan.execution_plan.campaign_id.clone(),
        task_family: follow_on_plan.execution_plan.task_family.clone(),
        tool_id: follow_on_plan.execution_plan.tool_id.clone(),
        work_mode: follow_on_plan.execution_plan.work_mode.clone(),
        current_state: "succeeded".to_string(),
        selected_subagent_id: follow_on_plan.execution_plan.selected_subagent_id.clone(),
        retrieval_query_type: follow_on_plan.execution_plan.retrieval_query_type.clone(),
        dense_backend: follow_on_plan.execution_plan.dense_backend.clone(),
        sparse_backend: follow_on_plan.execution_plan.sparse_backend.clone(),
        compiler_profile_id: follow_on_plan.execution_plan.compiler_profile_id.clone(),
        graphrag_query_mode: follow_on_plan.execution_plan.graphrag_query_mode.clone(),
        temporal_truth_view: follow_on_plan.execution_plan.temporal_truth_view.clone(),
        approved_by: dispatched_by.clone(),
        approved_at: dispatched_at,
        started_at: Some(dispatched_at),
        finished_at: Some(finished_at),
        stop_requested_at: None,
        stop_reason: None,
        latest_receipt_id: Some(format!(
            "{}-receipt-{}",
            sanitize_component(&next_execution_id),
            finished_at.timestamp_millis()
        )),
        latest_reflection_id: None,
        latest_trajectory_eval_id: None,
        latest_replan_suggestion_id: None,
        recipe_id: follow_on_plan
            .execution_plan
            .recipe_target
            .as_ref()
            .map(|target| target.recipe_id.clone()),
        recipe_kind: follow_on_plan
            .execution_plan
            .recipe_target
            .as_ref()
            .map(|target| target.recipe_kind.clone()),
        experiment_id: follow_on_plan
            .execution_plan
            .experiment_target
            .as_ref()
            .map(|target| target.experiment_id.clone()),
        context_packet_ref: Some(follow_on_plan.execution_plan.context_packet_ref.clone()),
        program_context_packet_ref: follow_on_plan.execution_plan.program_context_packet_ref.clone(),
        tool_launch_path: follow_on_plan.execution_plan.tool_launch_path.clone(),
        workspace_subagent_route_path: follow_on_plan.execution_plan.workspace_subagent_route_path.clone(),
        workspace_subagent_handoff_path: follow_on_plan
            .execution_plan
            .workspace_subagent_handoff_path
            .clone(),
        reflection_path: None,
        trajectory_eval_path: None,
        replan_suggestion_path: None,
        execution_state_path: execution_state_path(workstream_id),
        execution_receipt_path: execution_receipt_path(workstream_id),
        execution_result_links_path: execution_result_links_path(workstream_id),
        state_transitions: vec![
            ExecutionStateTransition {
                state: "planned".to_string(),
                transitioned_at: dispatched_at,
                note: "Follow-on plan entered the bounded continuation dispatch queue.".to_string(),
            },
            ExecutionStateTransition {
                state: "approved".to_string(),
                transitioned_at: dispatched_at,
                note: format!(
                    "Operator {} dispatched the approved follow-on plan: {}",
                    dispatched_by, dispatch_note
                ),
            },
            ExecutionStateTransition {
                state: "running".to_string(),
                transitioned_at: dispatched_at,
                note: "Continuation dispatch started the next bounded execution cycle.".to_string(),
            },
            ExecutionStateTransition {
                state: "succeeded".to_string(),
                transitioned_at: finished_at,
                note: "The continuation dispatch closed the next bounded execution with chained receipts and result links.".to_string(),
            },
        ],
        latest_quality_score: None,
        latest_trajectory_quality: None,
        replan_required: false,
        operator_followup_action: Some("review-dispatched-continuation-results".to_string()),
        review_requested: false,
        review_inbox_state: None,
        latest_review_inbox_item_id: None,
        latest_review_decision_id: None,
        latest_review_decision_action: None,
        latest_follow_on_plan_id: None,
        follow_on_plan_available: false,
        latest_autonomy_policy_id: None,
        latest_risk_evaluation_id: None,
        latest_approval_gating_decision_id: None,
        latest_autonomy_calibration_dataset_id: None,
        latest_autonomy_policy_eval_report_id: None,
        latest_escalation_thresholds_id: None,
        latest_shadow_policy_comparison_id: None,
        latest_updated_policy_recommendation_id: None,
        latest_autonomy_policy_current_id: None,
        latest_autonomy_policy_candidate_id: None,
        latest_rollout_metrics_id: None,
        latest_guarded_rollout_decision_id: None,
        approval_gating_decision_class: None,
        approval_gating_risk_level: None,
        approval_gating_dispatch_ready: false,
        approval_gating_blocked: false,
        continuation_dispatched: false,
        latest_continuation_dispatch_id: None,
        latest_continuation_receipt_id: None,
        continuation_current_state: None,
        continuation_source_execution_id: None,
        continuation_next_execution_id: None,
        continuation_next_plan_id: None,
        continuation_review_action: None,
        autonomy_policy_calibration_status: None,
        autonomy_policy_rollout_status: None,
        review_inbox_path: Some(review_inbox_path(workstream_id)),
        review_decision_path: Some(review_decision_path(workstream_id)),
        follow_on_plan_path: Some(follow_on_plan_path(workstream_id)),
        autonomy_policy_path: Some(autonomy_policy_path(workstream_id)),
        risk_evaluation_path: Some(risk_evaluation_path(workstream_id)),
        approval_gating_decision_path: Some(approval_gating_decision_path(workstream_id)),
        autonomy_calibration_dataset_path: Some(autonomy_calibration_dataset_path(workstream_id)),
        autonomy_policy_eval_report_path: Some(autonomy_policy_eval_report_path(workstream_id)),
        escalation_thresholds_path: Some(escalation_thresholds_path(workstream_id)),
        shadow_policy_comparison_path: Some(shadow_policy_comparison_path(workstream_id)),
        updated_policy_recommendation_path: Some(updated_policy_recommendation_path(workstream_id)),
        autonomy_policy_current_path: Some(autonomy_policy_current_path(workstream_id)),
        autonomy_policy_candidate_path: Some(autonomy_policy_candidate_path(workstream_id)),
        rollout_metrics_path: Some(rollout_metrics_path(workstream_id)),
        rollout_decision_path: Some(rollout_decision_path(workstream_id)),
        continuation_dispatch_path: Some(continuation_dispatch_path(workstream_id)),
        continuation_receipt_path: Some(continuation_receipt_path(workstream_id)),
        continuation_state_path: Some(continuation_state_path(workstream_id)),
        operator_execution_state: OPERATOR_EXECUTION_STATE.to_string(),
        note: "B24.5 next execution state proves that approved continuation dispatch stays bounded and identity-preserving instead of turning into an autonomous loop.".to_string(),
    };
    let next_execution_receipt = ExecutionReceipt {
        receipt_version: EXECUTION_RECEIPT_VERSION.to_string(),
        receipt_id: next_execution_state
            .latest_receipt_id
            .clone()
            .unwrap_or_else(|| format!("{}-receipt", sanitize_component(&next_execution_id))),
        execution_id: next_execution_id.clone(),
        plan_id: follow_on_plan.execution_plan.plan_id.clone(),
        workstream_id: follow_on_plan.execution_plan.workstream_id.clone(),
        workspace_id: follow_on_plan.execution_plan.workspace_id.clone(),
        session_id: follow_on_plan.execution_plan.session_id.clone(),
        final_state: "succeeded".to_string(),
        recorded_at: finished_at,
        selected_subagent_id: follow_on_plan.execution_plan.selected_subagent_id.clone(),
        recipe_kind: follow_on_plan
            .execution_plan
            .recipe_target
            .as_ref()
            .map(|target| target.recipe_kind.clone()),
        experiment_id: follow_on_plan
            .execution_plan
            .experiment_target
            .as_ref()
            .map(|target| target.experiment_id.clone()),
        result_link_count: next_result_links.links.len(),
        result_links_path: execution_result_links_path(workstream_id),
        handoff_updated: handoff_ref.is_some(),
        handoff_ref,
        reflection_id: None,
        trajectory_eval_id: None,
        replan_suggestion_id: None,
        quality_score: None,
        trajectory_quality: None,
        replan_required: false,
        operator_followup_action: Some("review-dispatched-continuation-results".to_string()),
        review_requested: false,
        review_inbox_state: None,
        review_inbox_item_id: None,
        review_decision_id: None,
        review_decision_action: None,
        follow_on_plan_id: None,
        follow_on_plan_available: false,
        latest_autonomy_policy_id: None,
        latest_risk_evaluation_id: None,
        latest_approval_gating_decision_id: None,
        latest_autonomy_calibration_dataset_id: None,
        latest_autonomy_policy_eval_report_id: None,
        latest_escalation_thresholds_id: None,
        latest_shadow_policy_comparison_id: None,
        latest_updated_policy_recommendation_id: None,
        latest_autonomy_policy_current_id: None,
        latest_autonomy_policy_candidate_id: None,
        latest_rollout_metrics_id: None,
        latest_guarded_rollout_decision_id: None,
        approval_gating_decision_class: None,
        approval_gating_risk_level: None,
        approval_gating_dispatch_ready: false,
        approval_gating_blocked: false,
        continuation_dispatched: false,
        latest_continuation_dispatch_id: None,
        latest_continuation_receipt_id: None,
        continuation_current_state: None,
        continuation_source_execution_id: None,
        continuation_next_execution_id: None,
        continuation_next_plan_id: None,
        continuation_review_action: None,
        autonomy_policy_calibration_status: None,
        autonomy_policy_rollout_status: None,
        review_inbox_path: Some(review_inbox_path(workstream_id)),
        review_decision_path: Some(review_decision_path(workstream_id)),
        follow_on_plan_path: Some(follow_on_plan_path(workstream_id)),
        autonomy_policy_path: Some(autonomy_policy_path(workstream_id)),
        risk_evaluation_path: Some(risk_evaluation_path(workstream_id)),
        approval_gating_decision_path: Some(approval_gating_decision_path(workstream_id)),
        autonomy_calibration_dataset_path: Some(autonomy_calibration_dataset_path(workstream_id)),
        autonomy_policy_eval_report_path: Some(autonomy_policy_eval_report_path(workstream_id)),
        escalation_thresholds_path: Some(escalation_thresholds_path(workstream_id)),
        shadow_policy_comparison_path: Some(shadow_policy_comparison_path(workstream_id)),
        updated_policy_recommendation_path: Some(updated_policy_recommendation_path(workstream_id)),
        autonomy_policy_current_path: Some(autonomy_policy_current_path(workstream_id)),
        autonomy_policy_candidate_path: Some(autonomy_policy_candidate_path(workstream_id)),
        rollout_metrics_path: Some(rollout_metrics_path(workstream_id)),
        rollout_decision_path: Some(rollout_decision_path(workstream_id)),
        continuation_dispatch_path: Some(continuation_dispatch_path(workstream_id)),
        continuation_receipt_path: Some(continuation_receipt_path(workstream_id)),
        continuation_state_path: Some(continuation_state_path(workstream_id)),
        reflection_path: None,
        trajectory_eval_path: None,
        replan_suggestion_path: None,
        operator_execution_state: OPERATOR_EXECUTION_STATE.to_string(),
        note: "B24.5 continuation receipts capture the next bounded execution without auto-opening another planning loop.".to_string(),
    };
    let chained_receipt_ids = source_receipt_id
        .iter()
        .cloned()
        .chain(std::iter::once(next_execution_receipt.receipt_id.clone()))
        .collect::<Vec<_>>();
    let continuation_state = ContinuationStatePlane {
        state_version: CONTINUATION_STATE_VERSION.to_string(),
        continuation_dispatch_id: continuation_dispatch.continuation_dispatch_id.clone(),
        workstream_id: follow_on_plan.workstream_id.clone(),
        workspace_id: follow_on_plan.workspace_id.clone(),
        session_id: follow_on_plan.session_id.clone(),
        source_execution_id: source_execution_id.clone(),
        source_plan_id: source_plan_id.clone(),
        source_receipt_id: source_receipt_id.clone(),
        review_inbox_item_id: review_inbox_item.inbox_item_id.clone(),
        review_decision_id: review_decision.decision_id.clone(),
        follow_on_plan_id: follow_on_plan.follow_on_plan_id.clone(),
        review_action: review_decision.decision_action.clone(),
        continuation_depth: 1,
        current_state: next_execution_state.current_state.clone(),
        dispatched_at,
        latest_continuation_receipt_id: Some(format!(
            "{}-continuation-receipt",
            sanitize_component(&continuation_dispatch.continuation_dispatch_id)
        )),
        continuation_state_path: continuation_state_path(workstream_id),
        continuation_receipt_path: continuation_receipt_path(workstream_id),
        chained_receipt_ids: chained_receipt_ids.clone(),
        state_transitions: vec![
            ContinuationStateTransition {
                state: "dispatched".to_string(),
                transitioned_at: dispatched_at,
                note: format!(
                    "Approved follow-on plan {} dispatched by {}.",
                    follow_on_plan.follow_on_plan_id, dispatched_by
                ),
            },
            ContinuationStateTransition {
                state: "succeeded".to_string(),
                transitioned_at: finished_at,
                note: "The next bounded execution completed and chained back to the previous receipt.".to_string(),
            },
        ],
        next_execution_state: next_execution_state.clone(),
        note: "B24.5 continuation state keeps the follow-on execution chain explicit and bounded on the same Beagle-owned identity.".to_string(),
    };
    let continuation_receipt = ContinuationReceipt {
        receipt_version: CONTINUATION_RECEIPT_VERSION.to_string(),
        continuation_receipt_id: continuation_state
            .latest_continuation_receipt_id
            .clone()
            .unwrap_or_else(|| format!("{}-continuation-receipt", continuation_dispatch.continuation_dispatch_id)),
        continuation_dispatch_id: continuation_dispatch.continuation_dispatch_id.clone(),
        workstream_id: follow_on_plan.workstream_id.clone(),
        workspace_id: follow_on_plan.workspace_id.clone(),
        session_id: follow_on_plan.session_id.clone(),
        source_execution_id: source_execution_id.clone(),
        source_plan_id: source_plan_id.clone(),
        source_receipt_id: source_receipt_id.clone(),
        review_decision_id: review_decision.decision_id.clone(),
        follow_on_plan_id: follow_on_plan.follow_on_plan_id.clone(),
        recorded_at: finished_at,
        review_action: review_decision.decision_action.clone(),
        chained_receipt_ids: chained_receipt_ids.clone(),
        handoff_updated: next_execution_receipt.handoff_updated,
        handoff_ref: next_execution_receipt.handoff_ref.clone(),
        next_execution_receipt: next_execution_receipt.clone(),
        next_execution_result_links: next_result_links.clone(),
        continuation_state_path: continuation_state_path(workstream_id),
        note: "B24.5 continuation receipts chain the original execution receipt to the next bounded execution, while staying operator-approved and non-autonomous.".to_string(),
    };

    follow_on_plan.follow_on_state = "dispatched".to_string();
    record.execution_state.continuation_dispatched = true;
    record.execution_state.latest_continuation_dispatch_id =
        Some(continuation_dispatch.continuation_dispatch_id.clone());
    record.execution_state.latest_continuation_receipt_id =
        Some(continuation_receipt.continuation_receipt_id.clone());
    record.execution_state.continuation_current_state =
        Some(continuation_state.current_state.clone());
    record.execution_state.continuation_source_execution_id = Some(source_execution_id.clone());
    record.execution_state.continuation_next_execution_id = Some(next_execution_id.clone());
    record.execution_state.continuation_next_plan_id =
        Some(follow_on_plan.execution_plan.plan_id.clone());
    record.execution_state.continuation_review_action =
        Some(review_decision.decision_action.clone());
    record.execution_state.operator_followup_action =
        Some("review-dispatched-continuation-results".to_string());
    if let Some(receipt) = record.execution_receipt.as_mut() {
        sync_receipt_from_review_state(receipt, &record.execution_state);
        sync_receipt_from_approval_gate_state(receipt, &record.execution_state);
        sync_receipt_from_continuation_state(receipt, &record.execution_state);
        receipt.operator_followup_action = record.execution_state.operator_followup_action.clone();
    }
    upsert_result_link(
        &mut record.execution_result_links,
        execution_result_link(
            &record.execution_state.execution_id,
            "continuation-dispatch",
            &continuation_dispatch_path(workstream_id),
            "Approved follow-on plan dispatched into the next bounded execution cycle.",
        ),
    );
    upsert_result_link(
        &mut record.execution_result_links,
        execution_result_link(
            &record.execution_state.execution_id,
            "continuation-state",
            &continuation_state_path(workstream_id),
            "Continuation state chaining the previous execution to the next bounded execution.",
        ),
    );
    upsert_result_link(
        &mut record.execution_result_links,
        execution_result_link(
            &record.execution_state.execution_id,
            "continuation-receipt",
            &continuation_receipt_path(workstream_id),
            "Continuation receipt chaining review, dispatch, and follow-on execution.",
        ),
    );
    record.follow_on_plan = Some(follow_on_plan);
    record.continuation_dispatch = Some(continuation_dispatch.clone());
    record.continuation_state = Some(continuation_state);
    record.continuation_receipt = Some(continuation_receipt);
    write_execution_record(data_dir, &context_packet.packet.workspace_id, &record)?;
    Ok(continuation_dispatch)
}

pub fn read_execution_state(
    data_dir: &Path,
    workspace_id: &str,
) -> anyhow::Result<Option<ExecutionStatePlane>> {
    Ok(read_execution_record(data_dir, workspace_id)?.map(|record| record.execution_state))
}

pub fn read_execution_receipt(
    data_dir: &Path,
    workspace_id: &str,
) -> anyhow::Result<Option<ExecutionReceipt>> {
    Ok(read_execution_record(data_dir, workspace_id)?.and_then(|record| record.execution_receipt))
}

pub fn read_execution_result_links(
    data_dir: &Path,
    workspace_id: &str,
) -> anyhow::Result<Option<ExecutionResultLinksDocument>> {
    Ok(read_execution_record(data_dir, workspace_id)?.map(|record| record.execution_result_links))
}

pub fn read_execution_reflection(
    data_dir: &Path,
    workspace_id: &str,
) -> anyhow::Result<Option<ExecutionReflection>> {
    Ok(read_execution_record(data_dir, workspace_id)?.and_then(|record| record.execution_reflection))
}

pub fn read_trajectory_eval(
    data_dir: &Path,
    workspace_id: &str,
) -> anyhow::Result<Option<TrajectoryEval>> {
    Ok(read_execution_record(data_dir, workspace_id)?.and_then(|record| record.trajectory_eval))
}

pub fn read_replan_suggestion(
    data_dir: &Path,
    workspace_id: &str,
) -> anyhow::Result<Option<ReplanSuggestion>> {
    Ok(read_execution_record(data_dir, workspace_id)?.and_then(|record| record.replan_suggestion))
}

pub fn read_review_inbox_item(
    data_dir: &Path,
    workspace_id: &str,
) -> anyhow::Result<Option<ReviewInboxItem>> {
    Ok(read_execution_record(data_dir, workspace_id)?.and_then(|record| record.review_inbox_item))
}

pub fn read_review_decision(
    data_dir: &Path,
    workspace_id: &str,
) -> anyhow::Result<Option<ReviewDecision>> {
    Ok(read_execution_record(data_dir, workspace_id)?.and_then(|record| record.review_decision))
}

pub fn read_follow_on_plan(
    data_dir: &Path,
    workspace_id: &str,
) -> anyhow::Result<Option<FollowOnPlan>> {
    Ok(read_execution_record(data_dir, workspace_id)?.and_then(|record| record.follow_on_plan))
}

pub fn read_autonomy_policy(
    data_dir: &Path,
    workspace_id: &str,
) -> anyhow::Result<Option<AutonomyPolicy>> {
    Ok(read_execution_record(data_dir, workspace_id)?.and_then(|record| record.autonomy_policy))
}

pub fn read_risk_evaluation(
    data_dir: &Path,
    workspace_id: &str,
) -> anyhow::Result<Option<RiskEvaluation>> {
    Ok(read_execution_record(data_dir, workspace_id)?.and_then(|record| record.risk_evaluation))
}

pub fn read_approval_gating_decision(
    data_dir: &Path,
    workspace_id: &str,
) -> anyhow::Result<Option<ApprovalGatingDecision>> {
    Ok(
        read_execution_record(data_dir, workspace_id)?
            .and_then(|record| record.approval_gating_decision),
    )
}

pub fn read_autonomy_calibration_dataset(
    data_dir: &Path,
    workspace_id: &str,
) -> anyhow::Result<Option<AutonomyCalibrationDataset>> {
    Ok(
        read_execution_record(data_dir, workspace_id)?
            .and_then(|record| record.autonomy_calibration_dataset),
    )
}

pub fn read_autonomy_policy_eval_report(
    data_dir: &Path,
    workspace_id: &str,
) -> anyhow::Result<Option<AutonomyPolicyEvalReport>> {
    Ok(
        read_execution_record(data_dir, workspace_id)?
            .and_then(|record| record.autonomy_policy_eval_report),
    )
}

pub fn read_escalation_thresholds(
    data_dir: &Path,
    workspace_id: &str,
) -> anyhow::Result<Option<EscalationThresholds>> {
    Ok(
        read_execution_record(data_dir, workspace_id)?
            .and_then(|record| record.escalation_thresholds),
    )
}

pub fn read_shadow_policy_comparison(
    data_dir: &Path,
    workspace_id: &str,
) -> anyhow::Result<Option<ShadowPolicyComparison>> {
    Ok(
        read_execution_record(data_dir, workspace_id)?
            .and_then(|record| record.shadow_policy_comparison),
    )
}

pub fn read_updated_policy_recommendation(
    data_dir: &Path,
    workspace_id: &str,
) -> anyhow::Result<Option<UpdatedPolicyRecommendation>> {
    Ok(
        read_execution_record(data_dir, workspace_id)?
            .and_then(|record| record.updated_policy_recommendation),
    )
}

pub fn read_autonomy_policy_current(
    data_dir: &Path,
    workspace_id: &str,
) -> anyhow::Result<Option<AutonomyShadowThreshold>> {
    Ok(
        read_execution_record(data_dir, workspace_id)?
            .and_then(|record| record.autonomy_policy_current),
    )
}

pub fn read_autonomy_policy_candidate(
    data_dir: &Path,
    workspace_id: &str,
) -> anyhow::Result<Option<AutonomyShadowThreshold>> {
    Ok(
        read_execution_record(data_dir, workspace_id)?
            .and_then(|record| record.autonomy_policy_candidate),
    )
}

pub fn read_rollout_metrics(
    data_dir: &Path,
    workspace_id: &str,
) -> anyhow::Result<Option<PolicyRolloutMetrics>> {
    Ok(read_execution_record(data_dir, workspace_id)?.and_then(|record| record.rollout_metrics))
}

pub fn read_guarded_rollout_decision(
    data_dir: &Path,
    workspace_id: &str,
) -> anyhow::Result<Option<GuardedRolloutDecision>> {
    Ok(read_execution_record(data_dir, workspace_id)?.and_then(|record| record.rollout_decision))
}

pub fn read_autonomy_policy_control(
    data_dir: &Path,
    workspace_id: &str,
) -> anyhow::Result<Option<AutonomyPolicy>> {
    Ok(
        read_execution_record(data_dir, workspace_id)?
            .and_then(|record| record.autonomy_policy_control),
    )
}

pub fn read_autonomy_policy_canary(
    data_dir: &Path,
    workspace_id: &str,
) -> anyhow::Result<Option<AutonomyPolicy>> {
    Ok(
        read_execution_record(data_dir, workspace_id)?
            .and_then(|record| record.autonomy_policy_canary),
    )
}

pub fn read_canary_rollout_metrics(
    data_dir: &Path,
    workspace_id: &str,
) -> anyhow::Result<Option<CanaryRolloutMetrics>> {
    Ok(
        read_execution_record(data_dir, workspace_id)?
            .and_then(|record| record.canary_rollout_metrics),
    )
}

pub fn read_canary_rollback_decision(
    data_dir: &Path,
    workspace_id: &str,
) -> anyhow::Result<Option<CanaryRollbackDecision>> {
    Ok(
        read_execution_record(data_dir, workspace_id)?
            .and_then(|record| record.canary_rollback_decision),
    )
}

pub fn read_autonomy_policy_analysis_candidate(
    data_dir: &Path,
    workspace_id: &str,
) -> anyhow::Result<Option<AutonomyPolicy>> {
    Ok(
        read_execution_record(data_dir, workspace_id)?
            .and_then(|record| record.autonomy_policy_analysis_candidate),
    )
}

pub fn read_analysis_shadow_comparison(
    data_dir: &Path,
    workspace_id: &str,
) -> anyhow::Result<Option<AnalysisShadowCalibration>> {
    Ok(
        read_execution_record(data_dir, workspace_id)?
            .and_then(|record| record.analysis_shadow_comparison),
    )
}

pub fn read_analysis_rollout_metrics(
    data_dir: &Path,
    workspace_id: &str,
) -> anyhow::Result<Option<AnalysisRolloutMetrics>> {
    Ok(
        read_execution_record(data_dir, workspace_id)?
            .and_then(|record| record.analysis_rollout_metrics),
    )
}

pub fn read_analysis_rollout_decision(
    data_dir: &Path,
    workspace_id: &str,
) -> anyhow::Result<Option<AnalysisRolloutDecision>> {
    Ok(
        read_execution_record(data_dir, workspace_id)?
            .and_then(|record| record.analysis_rollout_decision),
    )
}

pub fn read_analysis_shadow_history(
    data_dir: &Path,
    workspace_id: &str,
) -> anyhow::Result<Option<AnalysisShadowSoak>> {
    Ok(
        read_execution_record(data_dir, workspace_id)?
            .and_then(|record| record.analysis_shadow_history),
    )
}

pub fn read_analysis_soak_metrics(
    data_dir: &Path,
    workspace_id: &str,
) -> anyhow::Result<Option<AnalysisSoakMetrics>> {
    Ok(
        read_execution_record(data_dir, workspace_id)?
            .and_then(|record| record.analysis_soak_metrics),
    )
}

pub fn read_analysis_promotion_gate(
    data_dir: &Path,
    workspace_id: &str,
) -> anyhow::Result<Option<AnalysisPromotionGate>> {
    Ok(
        read_execution_record(data_dir, workspace_id)?
            .and_then(|record| record.analysis_promotion_gate),
    )
}

pub fn read_analysis_sample_accumulation(
    data_dir: &Path,
    workspace_id: &str,
) -> anyhow::Result<Option<AnalysisShadowSoak>> {
    Ok(
        read_execution_record(data_dir, workspace_id)?
            .and_then(|record| record.analysis_sample_accumulation),
    )
}

pub fn read_analysis_sample_accumulation_metrics(
    data_dir: &Path,
    workspace_id: &str,
) -> anyhow::Result<Option<AnalysisSoakMetrics>> {
    Ok(
        read_execution_record(data_dir, workspace_id)?
            .and_then(|record| record.analysis_sample_accumulation_metrics),
    )
}

pub fn read_analysis_promotion_gate_recheck(
    data_dir: &Path,
    workspace_id: &str,
) -> anyhow::Result<Option<AnalysisPromotionGate>> {
    Ok(
        read_execution_record(data_dir, workspace_id)?
            .and_then(|record| record.analysis_promotion_gate_recheck),
    )
}

pub fn read_autonomy_policy_analysis_control(
    data_dir: &Path,
    workspace_id: &str,
) -> anyhow::Result<Option<AutonomyPolicy>> {
    Ok(
        read_execution_record(data_dir, workspace_id)?
            .and_then(|record| record.autonomy_policy_analysis_control),
    )
}

pub fn read_autonomy_policy_implementation_canary_retained(
    data_dir: &Path,
    workspace_id: &str,
) -> anyhow::Result<Option<AutonomyPolicy>> {
    Ok(
        read_execution_record(data_dir, workspace_id)?
            .and_then(|record| record.autonomy_policy_implementation_canary_retained),
    )
}

pub fn read_autonomy_policy_analysis_canary(
    data_dir: &Path,
    workspace_id: &str,
) -> anyhow::Result<Option<AutonomyPolicy>> {
    Ok(
        read_execution_record(data_dir, workspace_id)?
            .and_then(|record| record.autonomy_policy_analysis_canary),
    )
}

pub fn read_analysis_canary_metrics(
    data_dir: &Path,
    workspace_id: &str,
) -> anyhow::Result<Option<AnalysisCanaryMetrics>> {
    Ok(
        read_execution_record(data_dir, workspace_id)?
            .and_then(|record| record.analysis_canary_metrics),
    )
}

pub fn read_analysis_canary_rollback_decision(
    data_dir: &Path,
    workspace_id: &str,
) -> anyhow::Result<Option<AnalysisCanaryRollbackDecision>> {
    Ok(
        read_execution_record(data_dir, workspace_id)?
            .and_then(|record| record.analysis_canary_rollback_decision),
    )
}

pub fn read_autonomy_policy_manuscript_candidate(
    data_dir: &Path,
    workspace_id: &str,
) -> anyhow::Result<Option<AutonomyPolicy>> {
    Ok(
        read_execution_record(data_dir, workspace_id)?
            .and_then(|record| record.autonomy_policy_manuscript_candidate),
    )
}

pub fn read_manuscript_shadow_comparison(
    data_dir: &Path,
    workspace_id: &str,
) -> anyhow::Result<Option<ManuscriptShadowCalibration>> {
    Ok(
        read_execution_record(data_dir, workspace_id)?
            .and_then(|record| record.manuscript_shadow_comparison),
    )
}

pub fn read_manuscript_rollout_metrics(
    data_dir: &Path,
    workspace_id: &str,
) -> anyhow::Result<Option<ManuscriptRolloutMetrics>> {
    Ok(
        read_execution_record(data_dir, workspace_id)?
            .and_then(|record| record.manuscript_rollout_metrics),
    )
}

pub fn read_manuscript_rollout_decision(
    data_dir: &Path,
    workspace_id: &str,
) -> anyhow::Result<Option<ManuscriptRolloutDecision>> {
    Ok(
        read_execution_record(data_dir, workspace_id)?
            .and_then(|record| record.manuscript_rollout_decision),
    )
}

pub fn read_manuscript_shadow_history(
    data_dir: &Path,
    workspace_id: &str,
) -> anyhow::Result<Option<ManuscriptShadowHistory>> {
    Ok(
        read_execution_record(data_dir, workspace_id)?
            .and_then(|record| record.manuscript_shadow_history),
    )
}

pub fn read_manuscript_soak_metrics(
    data_dir: &Path,
    workspace_id: &str,
) -> anyhow::Result<Option<ManuscriptSoakMetrics>> {
    Ok(
        read_execution_record(data_dir, workspace_id)?
            .and_then(|record| record.manuscript_soak_metrics),
    )
}

pub fn read_manuscript_alignment_labels(
    data_dir: &Path,
    workspace_id: &str,
) -> anyhow::Result<Option<ManuscriptAlignmentLabels>> {
    Ok(
        read_execution_record(data_dir, workspace_id)?
            .and_then(|record| record.manuscript_alignment_labels),
    )
}

pub fn read_manuscript_promotion_evidence(
    data_dir: &Path,
    workspace_id: &str,
) -> anyhow::Result<Option<ManuscriptPromotionEvidence>> {
    Ok(
        read_execution_record(data_dir, workspace_id)?
            .and_then(|record| record.manuscript_promotion_evidence),
    )
}

pub fn read_manuscript_promotion_gate(
    data_dir: &Path,
    workspace_id: &str,
) -> anyhow::Result<Option<ManuscriptPromotionGate>> {
    Ok(
        read_execution_record(data_dir, workspace_id)?
            .and_then(|record| record.manuscript_promotion_gate),
    )
}

pub fn read_manuscript_trajectory_quality(
    data_dir: &Path,
    workspace_id: &str,
) -> anyhow::Result<Option<ManuscriptTrajectoryQuality>> {
    Ok(
        read_execution_record(data_dir, workspace_id)?
            .and_then(|record| record.manuscript_trajectory_quality),
    )
}

pub fn read_manuscript_context_adequacy(
    data_dir: &Path,
    workspace_id: &str,
) -> anyhow::Result<Option<ManuscriptContextAdequacy>> {
    Ok(
        read_execution_record(data_dir, workspace_id)?
            .and_then(|record| record.manuscript_context_adequacy),
    )
}

pub fn read_manuscript_tuning_recommendation(
    data_dir: &Path,
    workspace_id: &str,
) -> anyhow::Result<Option<ManuscriptTuningRecommendation>> {
    Ok(
        read_execution_record(data_dir, workspace_id)?
            .and_then(|record| record.manuscript_tuning_recommendation),
    )
}

pub fn ensure_autonomy_policy_calibration(
    data_dir: &Path,
    workstream_id: &str,
    workspace_id: &str,
) -> anyhow::Result<AutonomyPolicyCalibrationBundle> {
    let mut record = read_required_execution_record(data_dir, workspace_id)?;
    if record.execution_plan.workstream_id != workstream_id {
        return Err(anyhow!(
            "plan execution workstream mismatch: expected '{}' but found '{}'",
            workstream_id,
            record.execution_plan.workstream_id
        ));
    }
    if let Some(bundle) = autonomy_policy_calibration_bundle_from_record(&record) {
        return Ok(bundle);
    }
    clear_autonomy_calibration_artifacts(&mut record);

    let mut follow_on_plan = record
        .follow_on_plan
        .clone()
        .ok_or_else(|| anyhow!("follow-on plan must exist before autonomy calibration"))?;
    let mut review_decision = record
        .review_decision
        .clone()
        .ok_or_else(|| anyhow!("review decision must exist before autonomy calibration"))?;
    let reflection = record
        .execution_reflection
        .clone()
        .ok_or_else(|| anyhow!("execution reflection must exist before autonomy calibration"))?;
    let trajectory_eval = record
        .trajectory_eval
        .clone()
        .ok_or_else(|| anyhow!("trajectory eval must exist before autonomy calibration"))?;
    let replan_suggestion = record
        .replan_suggestion
        .clone()
        .ok_or_else(|| anyhow!("replan suggestion must exist before autonomy calibration"))?;

    if record.autonomy_policy.is_none()
        || record.risk_evaluation.is_none()
        || record.approval_gating_decision.is_none()
    {
        let mut review_inbox_item = record
            .review_inbox_item
            .clone()
            .ok_or_else(|| anyhow!("review inbox item must exist before autonomy calibration"))?;
        let (autonomy_policy, risk_evaluation, approval_gating_decision) =
            evaluate_follow_on_plan_gate(
                &record,
                workstream_id,
                &review_inbox_item,
                &review_decision,
                &follow_on_plan,
            )?;
        if follow_on_plan.follow_on_state != "dispatched" {
            follow_on_plan.follow_on_state =
                approval_gating_decision.follow_on_state_after_gating.clone();
        }
        follow_on_plan.autonomy_policy_id = Some(autonomy_policy.policy_id.clone());
        follow_on_plan.risk_evaluation_id = Some(risk_evaluation.risk_evaluation_id.clone());
        follow_on_plan.approval_gating_decision_id = Some(
            approval_gating_decision
                .approval_gating_decision_id
                .clone(),
        );
        follow_on_plan.approval_gating_decision_class =
            Some(approval_gating_decision.decision_class.clone());
        follow_on_plan.approval_gating_decision_path =
            Some(approval_gating_decision_path(workstream_id));

        review_inbox_item.requested_operator_action =
            approval_gating_decision.requested_operator_action.clone();
        review_inbox_item.autonomy_policy_id = Some(autonomy_policy.policy_id.clone());
        review_inbox_item.risk_evaluation_id = Some(risk_evaluation.risk_evaluation_id.clone());
        review_inbox_item.approval_gating_decision_id = Some(
            approval_gating_decision
                .approval_gating_decision_id
                .clone(),
        );
        review_inbox_item.approval_gating_decision_class =
            Some(approval_gating_decision.decision_class.clone());
        review_inbox_item.autonomy_policy_path = Some(autonomy_policy_path(workstream_id));
        review_inbox_item.risk_evaluation_path = Some(risk_evaluation_path(workstream_id));
        review_inbox_item.approval_gating_decision_path =
            Some(approval_gating_decision_path(workstream_id));

        review_decision.autonomy_policy_id = Some(autonomy_policy.policy_id.clone());
        review_decision.risk_evaluation_id = Some(risk_evaluation.risk_evaluation_id.clone());
        review_decision.approval_gating_decision_id = Some(
            approval_gating_decision
                .approval_gating_decision_id
                .clone(),
        );
        review_decision.approval_gating_decision_class =
            Some(approval_gating_decision.decision_class.clone());
        review_decision.auto_continue_eligible =
            approval_gating_decision.auto_continuation_enabled;
        review_decision.dispatch_blocked = approval_gating_decision.blocked;

        record.execution_state.latest_autonomy_policy_id = Some(autonomy_policy.policy_id.clone());
        record.execution_state.latest_risk_evaluation_id =
            Some(risk_evaluation.risk_evaluation_id.clone());
        record.execution_state.latest_approval_gating_decision_id = Some(
            approval_gating_decision
                .approval_gating_decision_id
                .clone(),
        );
        record.execution_state.approval_gating_decision_class =
            Some(approval_gating_decision.decision_class.clone());
        record.execution_state.approval_gating_risk_level =
            Some(risk_evaluation.risk_level.clone());
        record.execution_state.approval_gating_dispatch_ready =
            approval_gating_decision.continuation_dispatch_permitted;
        record.execution_state.approval_gating_blocked = approval_gating_decision.blocked;
        if !record.execution_state.continuation_dispatched {
            record.execution_state.operator_followup_action =
                Some(approval_gating_decision.requested_operator_action.clone());
        }

        record.review_inbox_item = Some(review_inbox_item);
        record.review_decision = Some(review_decision.clone());
        record.follow_on_plan = Some(follow_on_plan.clone());
        record.autonomy_policy = Some(autonomy_policy);
        record.risk_evaluation = Some(risk_evaluation);
        record.approval_gating_decision = Some(approval_gating_decision);
        if let Some(receipt) = record.execution_receipt.as_mut() {
            sync_receipt_from_approval_gate_state(receipt, &record.execution_state);
            if !record.execution_state.continuation_dispatched {
                receipt.operator_followup_action =
                    record.execution_state.operator_followup_action.clone();
            }
        }
        upsert_result_link(
            &mut record.execution_result_links,
            execution_result_link(
                &record.execution_state.execution_id,
                "autonomy-policy",
                &autonomy_policy_path(workstream_id),
                "Canonical autonomy policy snapshot linked to the same follow-on execution identity.",
            ),
        );
        upsert_result_link(
            &mut record.execution_result_links,
            execution_result_link(
                &record.execution_state.execution_id,
                "risk-evaluation",
                &risk_evaluation_path(workstream_id),
                "Risk evaluation for the bounded follow-on plan linked to the same execution identity.",
            ),
        );
        upsert_result_link(
            &mut record.execution_result_links,
            execution_result_link(
                &record.execution_state.execution_id,
                "approval-gating-decision",
                &approval_gating_decision_path(workstream_id),
                "Approval gating decision classifying the follow-on plan as auto-continue, review-required, or blocked.",
            ),
        );
    }

    let autonomy_policy = record
        .autonomy_policy
        .as_ref()
        .ok_or_else(|| anyhow!("autonomy policy must exist before autonomy calibration"))?;
    let bundle = build_autonomy_policy_calibration_bundle(
        autonomy_policy,
        &record.execution_plan,
        &follow_on_plan,
        &review_decision,
        &reflection,
        &trajectory_eval,
        &replan_suggestion,
        record.approval_gating_decision.as_ref(),
        record.continuation_state.as_ref(),
        record.continuation_receipt.as_ref(),
    );
    persist_autonomy_policy_calibration(&mut record, workstream_id, &bundle);
    write_execution_record(data_dir, workspace_id, &record)?;
    Ok(bundle)
}

pub fn ensure_guarded_policy_rollout(
    data_dir: &Path,
    workstream_id: &str,
    workspace_id: &str,
) -> anyhow::Result<GuardedPolicyRolloutBundle> {
    let _ = ensure_autonomy_policy_calibration(data_dir, workstream_id, workspace_id)?;
    let mut record = read_required_execution_record(data_dir, workspace_id)?;
    if record.execution_plan.workstream_id != workstream_id {
        return Err(anyhow!(
            "plan execution workstream mismatch: expected '{}' but found '{}'",
            workstream_id,
            record.execution_plan.workstream_id
        ));
    }
    if let Some(bundle) = guarded_policy_rollout_bundle_from_record(&record) {
        return Ok(bundle);
    }
    clear_guarded_rollout_artifacts(&mut record);
    let autonomy_policy = record
        .autonomy_policy
        .as_ref()
        .ok_or_else(|| anyhow!("autonomy policy must exist before guarded rollout"))?;
    let calibration_bundle = autonomy_policy_calibration_bundle_from_record(&record)
        .ok_or_else(|| anyhow!("autonomy calibration bundle must exist before guarded rollout"))?;
    let bundle = build_guarded_policy_rollout_bundle(autonomy_policy, &calibration_bundle);
    persist_guarded_policy_rollout(&mut record, workstream_id, &bundle);
    write_execution_record(data_dir, workspace_id, &record)?;
    Ok(bundle)
}

pub fn ensure_implementation_canary_autonomy(
    data_dir: &Path,
    workstream_id: &str,
    workspace_id: &str,
) -> anyhow::Result<ImplementationCanaryAutonomyBundle> {
    let guarded_rollout = ensure_guarded_policy_rollout(data_dir, workstream_id, workspace_id)?;
    let mut record = read_required_execution_record(data_dir, workspace_id)?;
    if record.execution_plan.workstream_id != workstream_id {
        return Err(anyhow!(
            "plan execution workstream mismatch: expected '{}' but found '{}'",
            workstream_id,
            record.execution_plan.workstream_id
        ));
    }
    if let Some(bundle) = implementation_canary_bundle_from_record(&record) {
        return Ok(bundle);
    }
    clear_implementation_canary_artifacts(&mut record);
    let autonomy_policy = record
        .autonomy_policy
        .as_ref()
        .ok_or_else(|| anyhow!("autonomy policy must exist before implementation canary activation"))?;
    let bundle = build_implementation_canary_autonomy_bundle(autonomy_policy, &guarded_rollout);
    persist_implementation_canary_autonomy(&mut record, workstream_id, &bundle);
    write_execution_record(data_dir, workspace_id, &record)?;
    Ok(bundle)
}

pub fn ensure_analysis_shadow_calibration(
    data_dir: &Path,
    workstream_id: &str,
    workspace_id: &str,
) -> anyhow::Result<AnalysisShadowCalibrationBundle> {
    let rollout_bundle = ensure_guarded_policy_rollout(data_dir, workstream_id, workspace_id)?;
    let canary_bundle =
        ensure_implementation_canary_autonomy(data_dir, workstream_id, workspace_id)?;
    let mut record = read_required_execution_record(data_dir, workspace_id)?;
    if record.execution_plan.workstream_id != workstream_id {
        return Err(anyhow!(
            "plan execution workstream mismatch: expected '{}' but found '{}'",
            workstream_id,
            record.execution_plan.workstream_id
        ));
    }
    if let Some(bundle) = analysis_shadow_calibration_bundle_from_record(&record) {
        return Ok(bundle);
    }
    clear_analysis_shadow_artifacts(&mut record);
    let calibration_bundle = autonomy_policy_calibration_bundle_from_record(&record).ok_or_else(|| {
        anyhow!("autonomy calibration bundle must exist before analysis shadow calibration")
    })?;
    let bundle = build_analysis_shadow_calibration_bundle(
        &rollout_bundle,
        &calibration_bundle,
        &canary_bundle,
    );
    persist_analysis_shadow_calibration(&mut record, workstream_id, &bundle);
    write_execution_record(data_dir, workspace_id, &record)?;
    Ok(bundle)
}

pub fn ensure_analysis_shadow_soak(
    data_dir: &Path,
    workstream_id: &str,
    workspace_id: &str,
) -> anyhow::Result<AnalysisShadowSoakBundle> {
    let analysis_bundle = ensure_analysis_shadow_calibration(data_dir, workstream_id, workspace_id)?;
    let mut record = read_required_execution_record(data_dir, workspace_id)?;
    if record.execution_plan.workstream_id != workstream_id {
        return Err(anyhow!(
            "plan execution workstream mismatch: expected '{}' but found '{}'",
            workstream_id,
            record.execution_plan.workstream_id
        ));
    }
    if let Some(bundle) = analysis_shadow_soak_bundle_from_record(&record) {
        if bundle.analysis_shadow_history.source_analysis_shadow_calibration_id
            == analysis_bundle
                .analysis_shadow_comparison
                .analysis_shadow_calibration_id
        {
            return Ok(bundle);
        }
    }
    let previous_soak = record.analysis_shadow_history.clone();
    clear_analysis_shadow_soak_artifacts(&mut record);
    let calibration_bundle = autonomy_policy_calibration_bundle_from_record(&record).ok_or_else(|| {
        anyhow!("autonomy calibration bundle must exist before analysis shadow soak")
    })?;
    let bundle = build_analysis_shadow_soak_bundle(
        &calibration_bundle,
        &analysis_bundle,
        previous_soak.as_ref(),
    );
    persist_analysis_shadow_soak(&mut record, workstream_id, &bundle);
    write_execution_record(data_dir, workspace_id, &record)?;
    Ok(bundle)
}

pub fn ensure_analysis_sample_accumulation(
    data_dir: &Path,
    workstream_id: &str,
    workspace_id: &str,
) -> anyhow::Result<AnalysisSampleAccumulationBundle> {
    let soak_bundle = ensure_analysis_shadow_soak(data_dir, workstream_id, workspace_id)?;
    let mut record = read_required_execution_record(data_dir, workspace_id)?;
    if record.execution_plan.workstream_id != workstream_id {
        return Err(anyhow!(
            "plan execution workstream mismatch: expected '{}' but found '{}'",
            workstream_id,
            record.execution_plan.workstream_id
        ));
    }
    if let Some(bundle) = analysis_sample_accumulation_bundle_from_record(&record) {
        if bundle
            .analysis_shadow_history
            .source_analysis_shadow_calibration_id
            == soak_bundle
                .analysis_shadow_history
                .source_analysis_shadow_calibration_id
            && bundle
                .analysis_shadow_history
                .prior_shadow_sample_count
                == soak_bundle.analysis_shadow_history.shadow_sample_count
        {
            return Ok(bundle);
        }
    }
    clear_analysis_sample_accumulation_artifacts(&mut record);
    let calibration_bundle = autonomy_policy_calibration_bundle_from_record(&record).ok_or_else(|| {
        anyhow!("autonomy calibration bundle must exist before analysis sample accumulation")
    })?;
    let analysis_bundle = analysis_shadow_calibration_bundle_from_record(&record).ok_or_else(|| {
        anyhow!("analysis shadow calibration bundle must exist before analysis sample accumulation")
    })?;
    let bundle = build_analysis_sample_accumulation_bundle(
        &calibration_bundle,
        &analysis_bundle,
        &soak_bundle.analysis_shadow_history,
    );
    persist_analysis_sample_accumulation(&mut record, workstream_id, &bundle);
    write_execution_record(data_dir, workspace_id, &record)?;
    Ok(bundle)
}

pub fn ensure_analysis_canary_activation(
    data_dir: &Path,
    workstream_id: &str,
    workspace_id: &str,
) -> anyhow::Result<AnalysisCanaryActivationBundle> {
    let implementation_bundle =
        ensure_implementation_canary_autonomy(data_dir, workstream_id, workspace_id)?;
    let analysis_shadow_bundle =
        ensure_analysis_shadow_calibration(data_dir, workstream_id, workspace_id)?;
    let accumulation_bundle =
        ensure_analysis_sample_accumulation(data_dir, workstream_id, workspace_id)?;
    let mut record = read_required_execution_record(data_dir, workspace_id)?;
    if record.execution_plan.workstream_id != workstream_id {
        return Err(anyhow!(
            "plan execution workstream mismatch: expected '{}' but found '{}'",
            workstream_id,
            record.execution_plan.workstream_id
        ));
    }
    if let Some(bundle) = analysis_canary_activation_bundle_from_record(&record) {
        if bundle
            .analysis_canary_metrics
            .source_analysis_promotion_gate_id
            == accumulation_bundle
                .analysis_promotion_gate
                .analysis_promotion_gate_id
        {
            return Ok(bundle);
        }
    }
    clear_analysis_canary_activation_artifacts(&mut record);
    let bundle = build_analysis_canary_activation_bundle(
        &implementation_bundle,
        &analysis_shadow_bundle,
        &accumulation_bundle,
    );
    persist_analysis_canary_activation(&mut record, workstream_id, &bundle);
    write_execution_record(data_dir, workspace_id, &record)?;
    Ok(bundle)
}

pub fn ensure_manuscript_shadow_calibration(
    data_dir: &Path,
    workstream_id: &str,
    workspace_id: &str,
) -> anyhow::Result<ManuscriptShadowCalibrationBundle> {
    let rollout_bundle = ensure_guarded_policy_rollout(data_dir, workstream_id, workspace_id)?;
    let analysis_canary_bundle =
        ensure_analysis_canary_activation(data_dir, workstream_id, workspace_id)?;
    let mut record = read_required_execution_record(data_dir, workspace_id)?;
    if record.execution_plan.workstream_id != workstream_id {
        return Err(anyhow!(
            "plan execution workstream mismatch: expected '{}' but found '{}'",
            workstream_id,
            record.execution_plan.workstream_id
        ));
    }
    if let Some(bundle) = manuscript_shadow_calibration_bundle_from_record(&record) {
        if bundle
            .manuscript_rollout_metrics
            .source_analysis_canary_metrics_id
            == analysis_canary_bundle
                .analysis_canary_metrics
                .analysis_canary_metrics_id
        {
            return Ok(bundle);
        }
    }
    clear_manuscript_shadow_artifacts(&mut record);
    let calibration_bundle = autonomy_policy_calibration_bundle_from_record(&record).ok_or_else(
        || anyhow!("autonomy calibration bundle must exist before manuscript shadow calibration"),
    )?;
    let bundle = build_manuscript_shadow_calibration_bundle(
        &rollout_bundle,
        &calibration_bundle,
        &analysis_canary_bundle,
    );
    persist_manuscript_shadow_calibration(&mut record, workstream_id, &bundle);
    write_execution_record(data_dir, workspace_id, &record)?;
    Ok(bundle)
}

pub fn ensure_manuscript_sample_accumulation(
    data_dir: &Path,
    workstream_id: &str,
    workspace_id: &str,
) -> anyhow::Result<ManuscriptSampleAccumulationBundle> {
    let manuscript_bundle =
        ensure_manuscript_shadow_calibration(data_dir, workstream_id, workspace_id)?;
    let mut record = read_required_execution_record(data_dir, workspace_id)?;
    if record.execution_plan.workstream_id != workstream_id {
        return Err(anyhow!(
            "plan execution workstream mismatch: expected '{}' but found '{}'",
            workstream_id,
            record.execution_plan.workstream_id
        ));
    }
    if let Some(bundle) = manuscript_sample_accumulation_bundle_from_record(&record) {
        if bundle
            .manuscript_shadow_history
            .source_manuscript_shadow_calibration_id
            == manuscript_bundle
                .manuscript_shadow_comparison
                .manuscript_shadow_calibration_id
            && bundle.manuscript_shadow_history.prior_shadow_sample_count
                == manuscript_bundle.manuscript_shadow_comparison.compared_sample_count
        {
            return Ok(bundle);
        }
    }
    let previous_history = record.manuscript_shadow_history.clone();
    clear_manuscript_sample_accumulation_artifacts(&mut record);
    let calibration_bundle = autonomy_policy_calibration_bundle_from_record(&record).ok_or_else(
        || anyhow!("autonomy calibration bundle must exist before manuscript sample accumulation"),
    )?;
    let bundle = build_manuscript_sample_accumulation_bundle(
        &calibration_bundle,
        &manuscript_bundle,
        previous_history.as_ref(),
    );
    persist_manuscript_sample_accumulation(&mut record, workstream_id, &bundle);
    write_execution_record(data_dir, workspace_id, &record)?;
    Ok(bundle)
}

pub fn ensure_manuscript_alignment_labeling(
    data_dir: &Path,
    workstream_id: &str,
    workspace_id: &str,
) -> anyhow::Result<ManuscriptAlignmentLabelingBundle> {
    let accumulation_bundle =
        ensure_manuscript_sample_accumulation(data_dir, workstream_id, workspace_id)?;
    let mut record = read_required_execution_record(data_dir, workspace_id)?;
    if record.execution_plan.workstream_id != workstream_id {
        return Err(anyhow!(
            "plan execution workstream mismatch: expected '{}' but found '{}'",
            workstream_id,
            record.execution_plan.workstream_id
        ));
    }
    if let Some(bundle) = manuscript_alignment_labeling_bundle_from_record(&record) {
        if bundle
            .manuscript_alignment_labels
            .manuscript_shadow_history_id
            == accumulation_bundle
                .manuscript_shadow_history
                .manuscript_shadow_history_id
            && bundle
                .manuscript_promotion_evidence
                .manuscript_soak_metrics_id
                == accumulation_bundle
                    .manuscript_soak_metrics
                    .manuscript_soak_metrics_id
        {
            return Ok(bundle);
        }
    }
    clear_manuscript_alignment_labeling_artifacts(&mut record);
    let bundle = build_manuscript_alignment_labeling_bundle(
        &accumulation_bundle,
        record.review_decision.as_ref(),
        record.execution_reflection.as_ref(),
    );
    persist_manuscript_alignment_labeling(&mut record, workstream_id, &bundle);
    write_execution_record(data_dir, workspace_id, &record)?;
    Ok(bundle)
}

pub fn ensure_manuscript_alignment_signal_acquisition(
    data_dir: &Path,
    workstream_id: &str,
    workspace_id: &str,
) -> anyhow::Result<ManuscriptAlignmentSignalBundle> {
    let accumulation_bundle =
        ensure_manuscript_sample_accumulation(data_dir, workstream_id, workspace_id)?;
    let mut record = read_required_execution_record(data_dir, workspace_id)?;
    if record.execution_plan.workstream_id != workstream_id {
        return Err(anyhow!(
            "plan execution workstream mismatch: expected '{}' but found '{}'",
            workstream_id,
            record.execution_plan.workstream_id
        ));
    }
    if let Some(bundle) = manuscript_alignment_signal_bundle_from_record(&record) {
        if bundle
            .manuscript_shadow_history
            .source_manuscript_shadow_calibration_id
            == accumulation_bundle
                .manuscript_shadow_history
                .source_manuscript_shadow_calibration_id
            && bundle.manuscript_alignment_labels.workstream_id == workstream_id
            && bundle.manuscript_alignment_labels.workspace_id == workspace_id
        {
            return Ok(bundle);
        }
    }
    clear_manuscript_alignment_labeling_artifacts(&mut record);
    let bundle = build_manuscript_alignment_signal_bundle(
        &accumulation_bundle,
        record.review_decision.as_ref(),
        record.execution_reflection.as_ref(),
        record.follow_on_plan.as_ref(),
    );
    persist_manuscript_alignment_signal(&mut record, workstream_id, &bundle);
    write_execution_record(data_dir, workspace_id, &record)?;
    Ok(bundle)
}

pub fn ensure_manuscript_quality_uplift(
    data_dir: &Path,
    workstream_id: &str,
    workspace_id: &str,
    context_packet: &WorkstreamContextPacket,
) -> anyhow::Result<ManuscriptQualityUpliftBundle> {
    let alignment_bundle =
        ensure_manuscript_alignment_signal_acquisition(data_dir, workstream_id, workspace_id)?;
    let mut record = read_required_execution_record(data_dir, workspace_id)?;
    if record.execution_plan.workstream_id != workstream_id {
        return Err(anyhow!(
            "plan execution workstream mismatch: expected '{}' but found '{}'",
            workstream_id,
            record.execution_plan.workstream_id
        ));
    }
    if let Some(bundle) = manuscript_quality_uplift_bundle_from_record(&record) {
        if bundle
            .manuscript_trajectory_quality
            .manuscript_promotion_gate_id
            == alignment_bundle
                .manuscript_promotion_gate
                .manuscript_promotion_gate_id
            && bundle
                .manuscript_context_adequacy
                .source_plan_id
                == record.execution_plan.plan_id
            && bundle.manuscript_trajectory_quality.workstream_id == workstream_id
            && bundle.manuscript_trajectory_quality.workspace_id == workspace_id
        {
            if !manuscript_quality_uplift_state_is_synced(&record) {
                persist_manuscript_quality_uplift(&mut record, workstream_id, &bundle);
                write_execution_record(data_dir, workspace_id, &record)?;
            }
            return Ok(bundle);
        }
    }
    clear_manuscript_quality_uplift_artifacts(&mut record);
    let trajectory_eval = record
        .trajectory_eval
        .as_ref()
        .ok_or_else(|| anyhow!("trajectory eval missing for manuscript quality uplift"))?;
    let execution_reflection = record
        .execution_reflection
        .as_ref()
        .ok_or_else(|| anyhow!("execution reflection missing for manuscript quality uplift"))?;
    let bundle = build_manuscript_quality_uplift_bundle(
        &alignment_bundle,
        &record.execution_plan,
        trajectory_eval,
        execution_reflection,
        context_packet,
    );
    persist_manuscript_quality_uplift(&mut record, workstream_id, &bundle);
    write_execution_record(data_dir, workspace_id, &record)?;
    Ok(bundle)
}

pub fn read_continuation_dispatch(
    data_dir: &Path,
    workspace_id: &str,
) -> anyhow::Result<Option<ContinuationDispatch>> {
    Ok(read_execution_record(data_dir, workspace_id)?.and_then(|record| record.continuation_dispatch))
}

pub fn read_continuation_receipt(
    data_dir: &Path,
    workspace_id: &str,
) -> anyhow::Result<Option<ContinuationReceipt>> {
    Ok(read_execution_record(data_dir, workspace_id)?.and_then(|record| record.continuation_receipt))
}

pub fn read_continuation_state(
    data_dir: &Path,
    workspace_id: &str,
) -> anyhow::Result<Option<ContinuationStatePlane>> {
    Ok(read_execution_record(data_dir, workspace_id)?.and_then(|record| record.continuation_state))
}

pub fn read_execution_envelope(
    data_dir: &Path,
    workspace_id: &str,
    context_packet: WorkstreamContextPacket,
) -> anyhow::Result<Option<PlanExecutionEnvelope>> {
    let Some(record) = read_execution_record(data_dir, workspace_id)? else {
        return Ok(None);
    };
    Ok(Some(PlanExecutionEnvelope {
        status: "ok".to_string(),
        phase: PLAN_EXECUTION_PHASE.to_string(),
        execution_plan: record.execution_plan,
        approval: record.approval,
        execution_state: record.execution_state,
        execution_receipt: record.execution_receipt,
        execution_result_links: record.execution_result_links,
        execution_reflection: record.execution_reflection,
        trajectory_eval: record.trajectory_eval,
        replan_suggestion: record.replan_suggestion,
        review_inbox_item: record.review_inbox_item,
        review_decision: record.review_decision,
        follow_on_plan: record.follow_on_plan,
        autonomy_policy: record.autonomy_policy,
        risk_evaluation: record.risk_evaluation,
        approval_gating_decision: record.approval_gating_decision,
        autonomy_calibration_dataset: record.autonomy_calibration_dataset,
        autonomy_policy_eval_report: record.autonomy_policy_eval_report,
        escalation_thresholds: record.escalation_thresholds,
        shadow_policy_comparison: record.shadow_policy_comparison,
        updated_policy_recommendation: record.updated_policy_recommendation,
        autonomy_policy_current: record.autonomy_policy_current,
        autonomy_policy_candidate: record.autonomy_policy_candidate,
        rollout_metrics: record.rollout_metrics,
        rollout_decision: record.rollout_decision,
        autonomy_policy_control: record.autonomy_policy_control,
        autonomy_policy_canary: record.autonomy_policy_canary,
        canary_rollout_metrics: record.canary_rollout_metrics,
        canary_rollback_decision: record.canary_rollback_decision,
        autonomy_policy_analysis_candidate: record.autonomy_policy_analysis_candidate,
        analysis_shadow_comparison: record.analysis_shadow_comparison,
        analysis_rollout_metrics: record.analysis_rollout_metrics,
        analysis_rollout_decision: record.analysis_rollout_decision,
        analysis_shadow_history: record.analysis_shadow_history,
        analysis_soak_metrics: record.analysis_soak_metrics,
        analysis_promotion_gate: record.analysis_promotion_gate,
        analysis_sample_accumulation: record.analysis_sample_accumulation,
        analysis_sample_accumulation_metrics: record.analysis_sample_accumulation_metrics,
        analysis_promotion_gate_recheck: record.analysis_promotion_gate_recheck,
        autonomy_policy_analysis_control: record.autonomy_policy_analysis_control,
        autonomy_policy_implementation_canary_retained: record
            .autonomy_policy_implementation_canary_retained,
        autonomy_policy_analysis_canary: record.autonomy_policy_analysis_canary,
        analysis_canary_metrics: record.analysis_canary_metrics,
        analysis_canary_rollback_decision: record.analysis_canary_rollback_decision,
        autonomy_policy_manuscript_candidate: record.autonomy_policy_manuscript_candidate,
        manuscript_shadow_comparison: record.manuscript_shadow_comparison,
        manuscript_rollout_metrics: record.manuscript_rollout_metrics,
        manuscript_rollout_decision: record.manuscript_rollout_decision,
        manuscript_shadow_history: record.manuscript_shadow_history,
        manuscript_soak_metrics: record.manuscript_soak_metrics,
        manuscript_promotion_gate: record.manuscript_promotion_gate,
        manuscript_alignment_labels: record.manuscript_alignment_labels,
        manuscript_promotion_evidence: record.manuscript_promotion_evidence,
        manuscript_trajectory_quality: record.manuscript_trajectory_quality,
        manuscript_context_adequacy: record.manuscript_context_adequacy,
        manuscript_tuning_recommendation: record.manuscript_tuning_recommendation,
        continuation_dispatch: record.continuation_dispatch,
        continuation_receipt: record.continuation_receipt,
        continuation_state: record.continuation_state,
        context_packet,
    }))
}

pub fn execution_status_summary_for_packet(
    data_dir: &Path,
    packet: &WorkstreamContextPacket,
) -> anyhow::Result<Option<PlanExecutionStatusSummary>> {
    let Some(record) = read_execution_record(data_dir, &packet.workspace_id)? else {
        return Ok(None);
    };
    if record.execution_state.session_id != packet.session_id
        || record.execution_state.workstream_id != packet.workstream_id
    {
        return Ok(None);
    }
    Ok(Some(summary_from_record(&record)))
}

fn maybe_record_execution_handoff(
    data_dir: &Path,
    cfg: &BeagleConfig,
    workstream_id: &str,
    context_packet: &WorkstreamContextPacketResponse,
    plan: &ExecutionPlan,
) -> anyhow::Result<Option<String>> {
    if plan.selected_subagent_id.eq_ignore_ascii_case("core") {
        return Ok(None);
    }
    let summary = format!(
        "Execution {} started on {} with recipe {}",
        plan.plan_id,
        plan.selected_subagent_id,
        plan.recipe_target
            .as_ref()
            .map(|target| target.recipe_kind.as_str())
            .unwrap_or("bounded-execution")
    );
    let _handoff = record_workspace_subagent_handoff(
        data_dir,
        cfg,
        workstream_id,
        context_packet.clone(),
        WorkspaceSubAgentHandoffRequest {
            source_subagent_id: "core",
            target_subagent_id: &plan.selected_subagent_id,
            requested_work_mode: Some(&plan.work_mode),
            requested_tool_id: Some(&plan.tool_id),
            intent: &plan.task_family,
            summary: &summary,
        },
    )?;
    Ok(Some(plan.workspace_subagent_handoff_path.clone()))
}

fn build_execution_result_links(
    plan: &ExecutionPlan,
    execution_id: &str,
    handoff_ref: Option<&str>,
) -> ExecutionResultLinksDocument {
    let mut links = vec![
        execution_result_link(
            execution_id,
            "context-packet",
            &plan.context_packet_ref,
            "Latest workstream context packet for the executed plan.",
        ),
        execution_result_link(
            execution_id,
            "tool-launch",
            &plan.tool_launch_path,
            "Tool dock launch surface aligned with the executed plan.",
        ),
        execution_result_link(
            execution_id,
            "workspace-subagent-route",
            &plan.workspace_subagent_route_path,
            "Role-aware routing path selected for bounded execution.",
        ),
    ];

    if let Some(program_context_packet_ref) = plan.program_context_packet_ref.as_ref() {
        links.push(execution_result_link(
            execution_id,
            "program-context-packet",
            program_context_packet_ref,
            "Program/campaign context packet preserved across execution.",
        ));
    }

    if let Some(recipe_target) = plan.recipe_target.as_ref() {
        links.push(execution_result_link(
            execution_id,
            "recipe-target",
            &recipe_target.recipe_id,
            &format!("Canonical recipe target {}", recipe_target.recipe_kind),
        ));
    }

    if let Some(experiment_target) = plan.experiment_target.as_ref() {
        links.push(execution_result_link(
            execution_id,
            "experiment-spec",
            &experiment_target.spec_doc,
            "Experiment spec linked by the bounded execution receipt.",
        ));
        links.push(execution_result_link(
            execution_id,
            "experiment-results",
            &experiment_target.results_doc,
            "Experiment results doc linked by the bounded execution receipt.",
        ));
    }

    if let Some(handoff_ref) = handoff_ref {
        links.push(execution_result_link(
            execution_id,
            "workspace-subagent-handoff",
            handoff_ref,
            "Subagent handoff updated after bounded execution start.",
        ));
    }

    ExecutionResultLinksDocument {
        links_version: EXECUTION_RESULT_LINKS_VERSION.to_string(),
        execution_id: execution_id.to_string(),
        plan_id: plan.plan_id.clone(),
        workstream_id: plan.workstream_id.clone(),
        workspace_id: plan.workspace_id.clone(),
        session_id: plan.session_id.clone(),
        links,
        note: "B24.3 result links keep receipts, reflection outputs, tool surfaces, context packets, and experiment refs auditable inside the same Beagle-owned identity.".to_string(),
    }
}

fn execution_result_link(
    execution_id: &str,
    link_kind: &str,
    path: &str,
    summary: &str,
) -> ExecutionResultLink {
    ExecutionResultLink {
        link_id: format!(
            "{}-{}",
            sanitize_component(execution_id),
            sanitize_component(link_kind)
        ),
        link_kind: link_kind.to_string(),
        path: path.to_string(),
        summary: summary.to_string(),
    }
}

fn summary_from_record(record: &PersistedPlanExecutionRecord) -> PlanExecutionStatusSummary {
    PlanExecutionStatusSummary {
        state_version: record.execution_state.state_version.clone(),
        execution_id: record.execution_state.execution_id.clone(),
        plan_id: record.execution_state.plan_id.clone(),
        current_state: record.execution_state.current_state.clone(),
        selected_subagent_id: record.execution_state.selected_subagent_id.clone(),
        retrieval_query_type: record.execution_state.retrieval_query_type.clone(),
        compiler_profile_id: record.execution_state.compiler_profile_id.clone(),
        graphrag_query_mode: record.execution_state.graphrag_query_mode.clone(),
        temporal_truth_view: record.execution_state.temporal_truth_view.clone(),
        approved_at: record.execution_state.approved_at,
        started_at: record.execution_state.started_at,
        finished_at: record.execution_state.finished_at,
        latest_receipt_id: record.execution_state.latest_receipt_id.clone(),
        recipe_kind: record.execution_state.recipe_kind.clone(),
        experiment_id: record.execution_state.experiment_id.clone(),
        result_link_count: record.execution_result_links.links.len(),
        handoff_updated: record
            .execution_receipt
            .as_ref()
            .map(|receipt| receipt.handoff_updated)
            .unwrap_or(false),
        handoff_ref: record
            .execution_receipt
            .as_ref()
            .and_then(|receipt| receipt.handoff_ref.clone()),
        reflection_available: record.execution_reflection.is_some(),
        latest_reflection_id: record.execution_state.latest_reflection_id.clone(),
        latest_trajectory_eval_id: record.execution_state.latest_trajectory_eval_id.clone(),
        latest_replan_suggestion_id: record.execution_state.latest_replan_suggestion_id.clone(),
        latest_quality_score: record.execution_state.latest_quality_score,
        latest_trajectory_quality: record.execution_state.latest_trajectory_quality.clone(),
        replan_required: record.execution_state.replan_required,
        operator_followup_action: record.execution_state.operator_followup_action.clone(),
        review_requested: record.execution_state.review_requested,
        review_inbox_state: record.execution_state.review_inbox_state.clone(),
        latest_review_inbox_item_id: record.execution_state.latest_review_inbox_item_id.clone(),
        latest_review_decision_id: record.execution_state.latest_review_decision_id.clone(),
        latest_review_decision_action: record
            .execution_state
            .latest_review_decision_action
            .clone(),
        latest_follow_on_plan_id: record.execution_state.latest_follow_on_plan_id.clone(),
        follow_on_plan_available: record.execution_state.follow_on_plan_available,
        latest_autonomy_policy_id: record.execution_state.latest_autonomy_policy_id.clone(),
        latest_risk_evaluation_id: record.execution_state.latest_risk_evaluation_id.clone(),
        latest_approval_gating_decision_id: record
            .execution_state
            .latest_approval_gating_decision_id
            .clone(),
        latest_autonomy_calibration_dataset_id: record
            .execution_state
            .latest_autonomy_calibration_dataset_id
            .clone(),
        latest_autonomy_policy_eval_report_id: record
            .execution_state
            .latest_autonomy_policy_eval_report_id
            .clone(),
        latest_escalation_thresholds_id: record
            .execution_state
            .latest_escalation_thresholds_id
            .clone(),
        latest_shadow_policy_comparison_id: record
            .execution_state
            .latest_shadow_policy_comparison_id
            .clone(),
        latest_updated_policy_recommendation_id: record
            .execution_state
            .latest_updated_policy_recommendation_id
            .clone(),
        latest_autonomy_policy_current_id: record
            .execution_state
            .latest_autonomy_policy_current_id
            .clone(),
        latest_autonomy_policy_candidate_id: record
            .execution_state
            .latest_autonomy_policy_candidate_id
            .clone(),
        latest_rollout_metrics_id: record
            .execution_state
            .latest_rollout_metrics_id
            .clone(),
        latest_guarded_rollout_decision_id: record
            .execution_state
            .latest_guarded_rollout_decision_id
            .clone(),
        approval_gating_decision_class: record
            .execution_state
            .approval_gating_decision_class
            .clone(),
        approval_gating_risk_level: record.execution_state.approval_gating_risk_level.clone(),
        approval_gating_dispatch_ready: record.execution_state.approval_gating_dispatch_ready,
        approval_gating_blocked: record.execution_state.approval_gating_blocked,
        continuation_dispatched: record.execution_state.continuation_dispatched,
        latest_continuation_dispatch_id: record
            .execution_state
            .latest_continuation_dispatch_id
            .clone(),
        latest_continuation_receipt_id: record
            .execution_state
            .latest_continuation_receipt_id
            .clone(),
        continuation_current_state: record.execution_state.continuation_current_state.clone(),
        continuation_source_execution_id: record
            .execution_state
            .continuation_source_execution_id
            .clone(),
        continuation_next_execution_id: record
            .execution_state
            .continuation_next_execution_id
            .clone(),
        continuation_next_plan_id: record.execution_state.continuation_next_plan_id.clone(),
        continuation_review_action: record.execution_state.continuation_review_action.clone(),
        autonomy_policy_calibration_status: record
            .execution_state
            .autonomy_policy_calibration_status
            .clone(),
        autonomy_policy_rollout_status: record
            .execution_state
            .autonomy_policy_rollout_status
            .clone(),
        review_inbox_path: record.execution_state.review_inbox_path.clone(),
        review_decision_path: record.execution_state.review_decision_path.clone(),
        follow_on_plan_path: record.execution_state.follow_on_plan_path.clone(),
        autonomy_policy_path: record.execution_state.autonomy_policy_path.clone(),
        risk_evaluation_path: record.execution_state.risk_evaluation_path.clone(),
        approval_gating_decision_path: record
            .execution_state
            .approval_gating_decision_path
            .clone(),
        autonomy_calibration_dataset_path: record
            .execution_state
            .autonomy_calibration_dataset_path
            .clone(),
        autonomy_policy_eval_report_path: record
            .execution_state
            .autonomy_policy_eval_report_path
            .clone(),
        escalation_thresholds_path: record.execution_state.escalation_thresholds_path.clone(),
        shadow_policy_comparison_path: record
            .execution_state
            .shadow_policy_comparison_path
            .clone(),
        updated_policy_recommendation_path: record
            .execution_state
            .updated_policy_recommendation_path
            .clone(),
        autonomy_policy_current_path: record
            .execution_state
            .autonomy_policy_current_path
            .clone(),
        autonomy_policy_candidate_path: record
            .execution_state
            .autonomy_policy_candidate_path
            .clone(),
        rollout_metrics_path: record.execution_state.rollout_metrics_path.clone(),
        rollout_decision_path: record.execution_state.rollout_decision_path.clone(),
        continuation_dispatch_path: record.execution_state.continuation_dispatch_path.clone(),
        continuation_receipt_path: record.execution_state.continuation_receipt_path.clone(),
        continuation_state_path: record.execution_state.continuation_state_path.clone(),
        reflection_path: record.execution_state.reflection_path.clone(),
        trajectory_eval_path: record.execution_state.trajectory_eval_path.clone(),
        replan_suggestion_path: record.execution_state.replan_suggestion_path.clone(),
        execution_state_path: record.execution_state.execution_state_path.clone(),
        execution_receipt_path: record.execution_state.execution_receipt_path.clone(),
        execution_result_links_path: record.execution_state.execution_result_links_path.clone(),
        operator_execution_state: record.execution_state.operator_execution_state.clone(),
        note: format!(
            "B24.8 latest execution summary for task_family={} current_state={} result_links={} quality_score={:?} replan_required={} review_state={:?} follow_on_plan_available={} approval_gate={:?} continuation_dispatched={} continuation_state={:?} calibration_status={:?} rollout_status={:?}",
            record.execution_state.task_family,
            record.execution_state.current_state,
            record.execution_result_links.links.len(),
            record.execution_state.latest_quality_score,
            record.execution_state.replan_required,
            record.execution_state.review_inbox_state,
            record.execution_state.follow_on_plan_available,
            record.execution_state.approval_gating_decision_class,
            record.execution_state.continuation_dispatched,
            record.execution_state.continuation_current_state,
            record.execution_state.autonomy_policy_calibration_status,
            record.execution_state.autonomy_policy_rollout_status
        ),
    }
}

fn validate_plan_identity(
    workstream_id: &str,
    packet: &WorkstreamContextPacket,
    plan: &ExecutionPlan,
) -> anyhow::Result<()> {
    if plan.workstream_id != workstream_id || plan.workstream_id != packet.workstream_id {
        return Err(anyhow!("execution plan workstream identity mismatch"));
    }
    if plan.workspace_id != packet.workspace_id {
        return Err(anyhow!("execution plan workspace identity mismatch"));
    }
    if plan.session_id != packet.session_id {
        return Err(anyhow!("execution plan session identity mismatch"));
    }
    Ok(())
}

fn validate_record_identity(
    workstream_id: &str,
    packet: &WorkstreamContextPacket,
    record: &PersistedPlanExecutionRecord,
) -> anyhow::Result<()> {
    validate_plan_identity(workstream_id, packet, &record.execution_plan)
}

fn execution_records_dir(data_dir: &Path) -> PathBuf {
    workspace_plane_dir(data_dir).join("plan-executions")
}

fn execution_record_path(data_dir: &Path, workspace_id: &str) -> PathBuf {
    execution_records_dir(data_dir).join(format!("{}.json", sanitize_component(workspace_id)))
}

fn write_execution_record(
    data_dir: &Path,
    workspace_id: &str,
    record: &PersistedPlanExecutionRecord,
) -> anyhow::Result<()> {
    let dir = execution_records_dir(data_dir);
    fs::create_dir_all(&dir)
        .with_context(|| format!("failed to create plan execution dir {}", dir.display()))?;
    let path = execution_record_path(data_dir, workspace_id);
    let payload = serde_json::to_vec_pretty(record)
        .with_context(|| format!("failed to serialize plan execution record {}", path.display()))?;
    fs::write(&path, payload)
        .with_context(|| format!("failed to write plan execution record {}", path.display()))
}

fn read_execution_record(
    data_dir: &Path,
    workspace_id: &str,
) -> anyhow::Result<Option<PersistedPlanExecutionRecord>> {
    let path = execution_record_path(data_dir, workspace_id);
    if !path.exists() {
        return Ok(None);
    }
    let body = fs::read_to_string(&path)
        .with_context(|| format!("failed to read plan execution record {}", path.display()))?;
    let record = serde_json::from_str::<PersistedPlanExecutionRecord>(&body)
        .with_context(|| format!("failed to parse plan execution record {}", path.display()))?;
    Ok(Some(record))
}

fn read_required_execution_record(
    data_dir: &Path,
    workspace_id: &str,
) -> anyhow::Result<PersistedPlanExecutionRecord> {
    read_execution_record(data_dir, workspace_id)?
        .ok_or_else(|| anyhow!("plan execution record not found for workspace '{}'", workspace_id))
}

fn execution_state_path(workstream_id: &str) -> String {
    format!("{}/{}/plan-execution", PLAN_EXECUTION_API_PREFIX, workstream_id)
}

fn execution_receipt_path(workstream_id: &str) -> String {
    format!(
        "{}/{}/plan-execution/receipt",
        PLAN_EXECUTION_API_PREFIX, workstream_id
    )
}

fn execution_result_links_path(workstream_id: &str) -> String {
    format!(
        "{}/{}/plan-execution/result-links",
        PLAN_EXECUTION_API_PREFIX, workstream_id
    )
}

fn execution_reflection_path(workstream_id: &str) -> String {
    format!(
        "{}/{}/plan-execution/reflection",
        PLAN_EXECUTION_API_PREFIX, workstream_id
    )
}

fn trajectory_eval_path(workstream_id: &str) -> String {
    format!(
        "{}/{}/plan-execution/trajectory-eval",
        PLAN_EXECUTION_API_PREFIX, workstream_id
    )
}

fn replan_suggestion_path(workstream_id: &str) -> String {
    format!(
        "{}/{}/plan-execution/replan-suggestion",
        PLAN_EXECUTION_API_PREFIX, workstream_id
    )
}

fn review_inbox_path(workstream_id: &str) -> String {
    format!("{}/{}/review-inbox", PLAN_EXECUTION_API_PREFIX, workstream_id)
}

fn review_decision_path(workstream_id: &str) -> String {
    format!(
        "{}/{}/review-inbox/decision",
        PLAN_EXECUTION_API_PREFIX, workstream_id
    )
}

fn follow_on_plan_path(workstream_id: &str) -> String {
    format!("{}/{}/follow-on-plan", PLAN_EXECUTION_API_PREFIX, workstream_id)
}

fn autonomy_policy_path(workstream_id: &str) -> String {
    format!("{}/{}/autonomy-policy", PLAN_EXECUTION_API_PREFIX, workstream_id)
}

fn risk_evaluation_path(workstream_id: &str) -> String {
    format!("{}/{}/risk-evaluation", PLAN_EXECUTION_API_PREFIX, workstream_id)
}

fn approval_gating_decision_path(workstream_id: &str) -> String {
    format!(
        "{}/{}/approval-gating-decision",
        PLAN_EXECUTION_API_PREFIX, workstream_id
    )
}

fn autonomy_calibration_dataset_path(workstream_id: &str) -> String {
    format!(
        "{}/{}/autonomy-calibration-dataset",
        PLAN_EXECUTION_API_PREFIX, workstream_id
    )
}

fn autonomy_policy_eval_report_path(workstream_id: &str) -> String {
    format!(
        "{}/{}/autonomy-policy-eval-report",
        PLAN_EXECUTION_API_PREFIX, workstream_id
    )
}

fn escalation_thresholds_path(workstream_id: &str) -> String {
    format!(
        "{}/{}/escalation-thresholds",
        PLAN_EXECUTION_API_PREFIX, workstream_id
    )
}

fn shadow_policy_comparison_path(workstream_id: &str) -> String {
    format!(
        "{}/{}/shadow-policy-comparison",
        PLAN_EXECUTION_API_PREFIX, workstream_id
    )
}

fn updated_policy_recommendation_path(workstream_id: &str) -> String {
    format!(
        "{}/{}/updated-policy-recommendation",
        PLAN_EXECUTION_API_PREFIX, workstream_id
    )
}

fn autonomy_policy_current_path(workstream_id: &str) -> String {
    format!(
        "{}/{}/autonomy-policy-current",
        PLAN_EXECUTION_API_PREFIX, workstream_id
    )
}

fn autonomy_policy_candidate_path(workstream_id: &str) -> String {
    format!(
        "{}/{}/autonomy-policy-candidate",
        PLAN_EXECUTION_API_PREFIX, workstream_id
    )
}

fn rollout_metrics_path(workstream_id: &str) -> String {
    format!("{}/{}/rollout-metrics", PLAN_EXECUTION_API_PREFIX, workstream_id)
}

fn rollout_decision_path(workstream_id: &str) -> String {
    format!(
        "{}/{}/guarded-rollout-decision",
        PLAN_EXECUTION_API_PREFIX, workstream_id
    )
}

fn autonomy_policy_control_path(workstream_id: &str) -> String {
    format!(
        "{}/{}/autonomy-policy-control",
        PLAN_EXECUTION_API_PREFIX, workstream_id
    )
}

fn autonomy_policy_canary_path(workstream_id: &str) -> String {
    format!(
        "{}/{}/autonomy-policy-canary",
        PLAN_EXECUTION_API_PREFIX, workstream_id
    )
}

fn canary_rollout_metrics_path(workstream_id: &str) -> String {
    format!(
        "{}/{}/canary-rollout-metrics",
        PLAN_EXECUTION_API_PREFIX, workstream_id
    )
}

fn canary_rollback_decision_path(workstream_id: &str) -> String {
    format!(
        "{}/{}/canary-rollback-decision",
        PLAN_EXECUTION_API_PREFIX, workstream_id
    )
}

fn autonomy_policy_analysis_candidate_path(workstream_id: &str) -> String {
    format!(
        "{}/{}/autonomy-policy-analysis-candidate",
        PLAN_EXECUTION_API_PREFIX, workstream_id
    )
}

fn analysis_shadow_comparison_path(workstream_id: &str) -> String {
    format!(
        "{}/{}/analysis-shadow-comparison",
        PLAN_EXECUTION_API_PREFIX, workstream_id
    )
}

fn analysis_rollout_metrics_path(workstream_id: &str) -> String {
    format!(
        "{}/{}/analysis-rollout-metrics",
        PLAN_EXECUTION_API_PREFIX, workstream_id
    )
}

fn analysis_rollout_decision_path(workstream_id: &str) -> String {
    format!(
        "{}/{}/analysis-rollout-decision",
        PLAN_EXECUTION_API_PREFIX, workstream_id
    )
}

fn analysis_shadow_history_path(workstream_id: &str) -> String {
    format!(
        "{}/{}/analysis-shadow-history",
        PLAN_EXECUTION_API_PREFIX, workstream_id
    )
}

fn analysis_soak_metrics_path(workstream_id: &str) -> String {
    format!(
        "{}/{}/analysis-soak-metrics",
        PLAN_EXECUTION_API_PREFIX, workstream_id
    )
}

fn analysis_promotion_gate_path(workstream_id: &str) -> String {
    format!(
        "{}/{}/analysis-promotion-gate",
        PLAN_EXECUTION_API_PREFIX, workstream_id
    )
}

fn analysis_sample_accumulation_path(workstream_id: &str) -> String {
    format!(
        "{}/{}/analysis-sample-accumulation",
        PLAN_EXECUTION_API_PREFIX, workstream_id
    )
}

fn analysis_sample_accumulation_metrics_path(workstream_id: &str) -> String {
    format!(
        "{}/{}/analysis-sample-accumulation-metrics",
        PLAN_EXECUTION_API_PREFIX, workstream_id
    )
}

fn analysis_promotion_gate_recheck_path(workstream_id: &str) -> String {
    format!(
        "{}/{}/analysis-promotion-gate-recheck",
        PLAN_EXECUTION_API_PREFIX, workstream_id
    )
}

fn autonomy_policy_analysis_control_path(workstream_id: &str) -> String {
    format!(
        "{}/{}/autonomy-policy-analysis-control",
        PLAN_EXECUTION_API_PREFIX, workstream_id
    )
}

fn autonomy_policy_implementation_canary_path(workstream_id: &str) -> String {
    format!(
        "{}/{}/autonomy-policy-implementation-canary",
        PLAN_EXECUTION_API_PREFIX, workstream_id
    )
}

fn autonomy_policy_analysis_canary_path(workstream_id: &str) -> String {
    format!(
        "{}/{}/autonomy-policy-analysis-canary",
        PLAN_EXECUTION_API_PREFIX, workstream_id
    )
}

fn analysis_canary_metrics_path(workstream_id: &str) -> String {
    format!(
        "{}/{}/analysis-canary-metrics",
        PLAN_EXECUTION_API_PREFIX, workstream_id
    )
}

fn analysis_canary_rollback_decision_path(workstream_id: &str) -> String {
    format!(
        "{}/{}/analysis-canary-rollback-decision",
        PLAN_EXECUTION_API_PREFIX, workstream_id
    )
}

fn autonomy_policy_manuscript_control_path(workstream_id: &str) -> String {
    format!(
        "{}/{}/autonomy-policy-manuscript-control",
        PLAN_EXECUTION_API_PREFIX, workstream_id
    )
}

fn autonomy_policy_manuscript_candidate_path(workstream_id: &str) -> String {
    format!(
        "{}/{}/autonomy-policy-manuscript-candidate",
        PLAN_EXECUTION_API_PREFIX, workstream_id
    )
}

fn manuscript_shadow_comparison_path(workstream_id: &str) -> String {
    format!(
        "{}/{}/manuscript-shadow-comparison",
        PLAN_EXECUTION_API_PREFIX, workstream_id
    )
}

fn manuscript_rollout_metrics_path(workstream_id: &str) -> String {
    format!(
        "{}/{}/manuscript-rollout-metrics",
        PLAN_EXECUTION_API_PREFIX, workstream_id
    )
}

fn manuscript_rollout_decision_path(workstream_id: &str) -> String {
    format!(
        "{}/{}/manuscript-rollout-decision",
        PLAN_EXECUTION_API_PREFIX, workstream_id
    )
}

fn manuscript_shadow_history_path(workstream_id: &str) -> String {
    format!(
        "{}/{}/manuscript-shadow-history",
        PLAN_EXECUTION_API_PREFIX, workstream_id
    )
}

fn manuscript_soak_metrics_path(workstream_id: &str) -> String {
    format!(
        "{}/{}/manuscript-soak-metrics",
        PLAN_EXECUTION_API_PREFIX, workstream_id
    )
}

fn manuscript_alignment_labels_path(workstream_id: &str) -> String {
    format!(
        "{}/{}/manuscript-alignment-labels",
        PLAN_EXECUTION_API_PREFIX, workstream_id
    )
}

fn manuscript_promotion_evidence_path(workstream_id: &str) -> String {
    format!(
        "{}/{}/manuscript-promotion-evidence",
        PLAN_EXECUTION_API_PREFIX, workstream_id
    )
}

fn manuscript_promotion_gate_path(workstream_id: &str) -> String {
    format!(
        "{}/{}/manuscript-promotion-gate",
        PLAN_EXECUTION_API_PREFIX, workstream_id
    )
}

fn manuscript_trajectory_quality_path(workstream_id: &str) -> String {
    format!(
        "{}/{}/manuscript-trajectory-quality",
        PLAN_EXECUTION_API_PREFIX, workstream_id
    )
}

fn manuscript_context_adequacy_path(workstream_id: &str) -> String {
    format!(
        "{}/{}/manuscript-context-adequacy",
        PLAN_EXECUTION_API_PREFIX, workstream_id
    )
}

fn manuscript_tuning_recommendation_path(workstream_id: &str) -> String {
    format!(
        "{}/{}/manuscript-tuning-recommendation",
        PLAN_EXECUTION_API_PREFIX, workstream_id
    )
}

fn continuation_dispatch_path(workstream_id: &str) -> String {
    format!(
        "{}/{}/continuation-dispatch",
        PLAN_EXECUTION_API_PREFIX, workstream_id
    )
}

fn continuation_receipt_path(workstream_id: &str) -> String {
    format!(
        "{}/{}/continuation-receipt",
        PLAN_EXECUTION_API_PREFIX, workstream_id
    )
}

fn continuation_state_path(workstream_id: &str) -> String {
    format!(
        "{}/{}/continuation-state",
        PLAN_EXECUTION_API_PREFIX, workstream_id
    )
}

fn augment_result_links_with_reflection(
    result_links: &mut ExecutionResultLinksDocument,
    execution_id: &str,
    reflection_path: Option<&str>,
    trajectory_eval_path: Option<&str>,
    replan_suggestion_path: Option<&str>,
) {
    if let Some(path) = reflection_path {
        upsert_result_link(result_links, execution_result_link(
            execution_id,
            "execution-reflection",
            path,
            "Execution reflection report linked to the bounded run.",
        ));
    }
    if let Some(path) = trajectory_eval_path {
        upsert_result_link(result_links, execution_result_link(
            execution_id,
            "trajectory-eval",
            path,
            "Trajectory evaluation linked to the bounded run.",
        ));
    }
    if let Some(path) = replan_suggestion_path {
        upsert_result_link(result_links, execution_result_link(
            execution_id,
            "replan-suggestion",
            path,
            "Operator-facing adaptive replan suggestion linked to the bounded run.",
        ));
    }
}

fn sync_receipt_from_review_state(
    receipt: &mut ExecutionReceipt,
    state: &ExecutionStatePlane,
) {
    receipt.review_requested = state.review_requested;
    receipt.review_inbox_state = state.review_inbox_state.clone();
    receipt.review_inbox_item_id = state.latest_review_inbox_item_id.clone();
    receipt.review_decision_id = state.latest_review_decision_id.clone();
    receipt.review_decision_action = state.latest_review_decision_action.clone();
    receipt.follow_on_plan_id = state.latest_follow_on_plan_id.clone();
    receipt.follow_on_plan_available = state.follow_on_plan_available;
    receipt.review_inbox_path = state.review_inbox_path.clone();
    receipt.review_decision_path = state.review_decision_path.clone();
    receipt.follow_on_plan_path = state.follow_on_plan_path.clone();
    receipt.continuation_dispatch_path = state.continuation_dispatch_path.clone();
    receipt.continuation_receipt_path = state.continuation_receipt_path.clone();
    receipt.continuation_state_path = state.continuation_state_path.clone();
}

fn sync_receipt_from_approval_gate_state(
    receipt: &mut ExecutionReceipt,
    state: &ExecutionStatePlane,
) {
    receipt.latest_autonomy_policy_id = state.latest_autonomy_policy_id.clone();
    receipt.latest_risk_evaluation_id = state.latest_risk_evaluation_id.clone();
    receipt.latest_approval_gating_decision_id =
        state.latest_approval_gating_decision_id.clone();
    receipt.approval_gating_decision_class = state.approval_gating_decision_class.clone();
    receipt.approval_gating_risk_level = state.approval_gating_risk_level.clone();
    receipt.approval_gating_dispatch_ready = state.approval_gating_dispatch_ready;
    receipt.approval_gating_blocked = state.approval_gating_blocked;
    receipt.autonomy_policy_path = state.autonomy_policy_path.clone();
    receipt.risk_evaluation_path = state.risk_evaluation_path.clone();
    receipt.approval_gating_decision_path = state.approval_gating_decision_path.clone();
}

fn sync_receipt_from_autonomy_calibration_state(
    receipt: &mut ExecutionReceipt,
    state: &ExecutionStatePlane,
) {
    receipt.latest_autonomy_calibration_dataset_id =
        state.latest_autonomy_calibration_dataset_id.clone();
    receipt.latest_autonomy_policy_eval_report_id =
        state.latest_autonomy_policy_eval_report_id.clone();
    receipt.latest_escalation_thresholds_id = state.latest_escalation_thresholds_id.clone();
    receipt.latest_shadow_policy_comparison_id =
        state.latest_shadow_policy_comparison_id.clone();
    receipt.latest_updated_policy_recommendation_id =
        state.latest_updated_policy_recommendation_id.clone();
    receipt.autonomy_policy_calibration_status =
        state.autonomy_policy_calibration_status.clone();
    receipt.autonomy_calibration_dataset_path =
        state.autonomy_calibration_dataset_path.clone();
    receipt.autonomy_policy_eval_report_path =
        state.autonomy_policy_eval_report_path.clone();
    receipt.escalation_thresholds_path = state.escalation_thresholds_path.clone();
    receipt.shadow_policy_comparison_path = state.shadow_policy_comparison_path.clone();
    receipt.updated_policy_recommendation_path =
        state.updated_policy_recommendation_path.clone();
}

fn sync_receipt_from_guarded_rollout_state(
    receipt: &mut ExecutionReceipt,
    state: &ExecutionStatePlane,
) {
    receipt.latest_autonomy_policy_current_id =
        state.latest_autonomy_policy_current_id.clone();
    receipt.latest_autonomy_policy_candidate_id =
        state.latest_autonomy_policy_candidate_id.clone();
    receipt.latest_rollout_metrics_id = state.latest_rollout_metrics_id.clone();
    receipt.latest_guarded_rollout_decision_id =
        state.latest_guarded_rollout_decision_id.clone();
    receipt.autonomy_policy_rollout_status = state.autonomy_policy_rollout_status.clone();
    receipt.autonomy_policy_current_path = state.autonomy_policy_current_path.clone();
    receipt.autonomy_policy_candidate_path = state.autonomy_policy_candidate_path.clone();
    receipt.rollout_metrics_path = state.rollout_metrics_path.clone();
    receipt.rollout_decision_path = state.rollout_decision_path.clone();
}

fn sync_receipt_from_continuation_state(
    receipt: &mut ExecutionReceipt,
    state: &ExecutionStatePlane,
) {
    receipt.continuation_dispatched = state.continuation_dispatched;
    receipt.latest_continuation_dispatch_id = state.latest_continuation_dispatch_id.clone();
    receipt.latest_continuation_receipt_id = state.latest_continuation_receipt_id.clone();
    receipt.continuation_current_state = state.continuation_current_state.clone();
    receipt.continuation_source_execution_id = state.continuation_source_execution_id.clone();
    receipt.continuation_next_execution_id = state.continuation_next_execution_id.clone();
    receipt.continuation_next_plan_id = state.continuation_next_plan_id.clone();
    receipt.continuation_review_action = state.continuation_review_action.clone();
    receipt.continuation_dispatch_path = state.continuation_dispatch_path.clone();
    receipt.continuation_receipt_path = state.continuation_receipt_path.clone();
    receipt.continuation_state_path = state.continuation_state_path.clone();
}

fn clear_approval_gate_state(state: &mut ExecutionStatePlane) {
    state.latest_autonomy_policy_id = None;
    state.latest_risk_evaluation_id = None;
    state.latest_approval_gating_decision_id = None;
    state.approval_gating_decision_class = None;
    state.approval_gating_risk_level = None;
    state.approval_gating_dispatch_ready = false;
    state.approval_gating_blocked = false;
}

fn clear_autonomy_calibration_state(state: &mut ExecutionStatePlane) {
    state.latest_autonomy_calibration_dataset_id = None;
    state.latest_autonomy_policy_eval_report_id = None;
    state.latest_escalation_thresholds_id = None;
    state.latest_shadow_policy_comparison_id = None;
    state.latest_updated_policy_recommendation_id = None;
    state.autonomy_policy_calibration_status = None;
}

fn clear_guarded_rollout_state(state: &mut ExecutionStatePlane) {
    state.latest_autonomy_policy_current_id = None;
    state.latest_autonomy_policy_candidate_id = None;
    state.latest_rollout_metrics_id = None;
    state.latest_guarded_rollout_decision_id = None;
    state.autonomy_policy_rollout_status = None;
}

fn clear_guarded_rollout_artifacts(record: &mut PersistedPlanExecutionRecord) {
    clear_implementation_canary_artifacts(record);
    clear_guarded_rollout_state(&mut record.execution_state);
    record.autonomy_policy_current = None;
    record.autonomy_policy_candidate = None;
    record.rollout_metrics = None;
    record.rollout_decision = None;
    remove_result_link_kind(&mut record.execution_result_links, "autonomy-policy-current");
    remove_result_link_kind(&mut record.execution_result_links, "autonomy-policy-candidate");
    remove_result_link_kind(&mut record.execution_result_links, "rollout-metrics");
    remove_result_link_kind(&mut record.execution_result_links, "guarded-rollout-decision");
    if let Some(receipt) = record.execution_receipt.as_mut() {
        sync_receipt_from_guarded_rollout_state(receipt, &record.execution_state);
    }
}

fn clear_implementation_canary_artifacts(record: &mut PersistedPlanExecutionRecord) {
    clear_analysis_shadow_artifacts(record);
    record.autonomy_policy_control = None;
    record.autonomy_policy_canary = None;
    record.canary_rollout_metrics = None;
    record.canary_rollback_decision = None;
    remove_result_link_kind(&mut record.execution_result_links, "autonomy-policy-control");
    remove_result_link_kind(&mut record.execution_result_links, "autonomy-policy-canary");
    remove_result_link_kind(&mut record.execution_result_links, "canary-rollout-metrics");
    remove_result_link_kind(&mut record.execution_result_links, "canary-rollback-decision");
}

fn clear_analysis_shadow_artifacts(record: &mut PersistedPlanExecutionRecord) {
    clear_analysis_shadow_soak_artifacts(record);
    record.autonomy_policy_analysis_candidate = None;
    record.analysis_shadow_comparison = None;
    record.analysis_rollout_metrics = None;
    record.analysis_rollout_decision = None;
    remove_result_link_kind(
        &mut record.execution_result_links,
        "autonomy-policy-analysis-candidate",
    );
    remove_result_link_kind(
        &mut record.execution_result_links,
        "analysis-shadow-comparison",
    );
    remove_result_link_kind(
        &mut record.execution_result_links,
        "analysis-rollout-metrics",
    );
    remove_result_link_kind(
        &mut record.execution_result_links,
        "analysis-rollout-decision",
    );
}

fn clear_analysis_shadow_soak_artifacts(record: &mut PersistedPlanExecutionRecord) {
    clear_analysis_sample_accumulation_artifacts(record);
    record.analysis_shadow_history = None;
    record.analysis_soak_metrics = None;
    record.analysis_promotion_gate = None;
    remove_result_link_kind(
        &mut record.execution_result_links,
        "analysis-shadow-history",
    );
    remove_result_link_kind(
        &mut record.execution_result_links,
        "analysis-soak-metrics",
    );
    remove_result_link_kind(
        &mut record.execution_result_links,
        "analysis-promotion-gate",
    );
}

fn clear_analysis_sample_accumulation_artifacts(record: &mut PersistedPlanExecutionRecord) {
    clear_analysis_canary_activation_artifacts(record);
    record.analysis_sample_accumulation = None;
    record.analysis_sample_accumulation_metrics = None;
    record.analysis_promotion_gate_recheck = None;
    remove_result_link_kind(
        &mut record.execution_result_links,
        "analysis-sample-accumulation",
    );
    remove_result_link_kind(
        &mut record.execution_result_links,
        "analysis-sample-accumulation-metrics",
    );
    remove_result_link_kind(
        &mut record.execution_result_links,
        "analysis-promotion-gate-recheck",
    );
}

fn clear_analysis_canary_activation_artifacts(record: &mut PersistedPlanExecutionRecord) {
    clear_manuscript_shadow_artifacts(record);
    record.autonomy_policy_analysis_control = None;
    record.autonomy_policy_implementation_canary_retained = None;
    record.autonomy_policy_analysis_canary = None;
    record.analysis_canary_metrics = None;
    record.analysis_canary_rollback_decision = None;
    remove_result_link_kind(
        &mut record.execution_result_links,
        "autonomy-policy-analysis-control",
    );
    remove_result_link_kind(
        &mut record.execution_result_links,
        "autonomy-policy-implementation-canary",
    );
    remove_result_link_kind(
        &mut record.execution_result_links,
        "autonomy-policy-analysis-canary",
    );
    remove_result_link_kind(
        &mut record.execution_result_links,
        "analysis-canary-metrics",
    );
    remove_result_link_kind(
        &mut record.execution_result_links,
        "analysis-canary-rollback-decision",
    );
}

fn clear_manuscript_shadow_artifacts(record: &mut PersistedPlanExecutionRecord) {
    clear_manuscript_sample_accumulation_artifacts(record);
    record.autonomy_policy_manuscript_candidate = None;
    record.manuscript_shadow_comparison = None;
    record.manuscript_rollout_metrics = None;
    record.manuscript_rollout_decision = None;
    remove_result_link_kind(
        &mut record.execution_result_links,
        "autonomy-policy-manuscript-control",
    );
    remove_result_link_kind(
        &mut record.execution_result_links,
        "autonomy-policy-manuscript-candidate",
    );
    remove_result_link_kind(
        &mut record.execution_result_links,
        "manuscript-shadow-comparison",
    );
    remove_result_link_kind(
        &mut record.execution_result_links,
        "manuscript-rollout-metrics",
    );
    remove_result_link_kind(
        &mut record.execution_result_links,
        "manuscript-rollout-decision",
    );
}

fn clear_manuscript_sample_accumulation_artifacts(record: &mut PersistedPlanExecutionRecord) {
    clear_manuscript_alignment_labeling_artifacts(record);
    record.manuscript_shadow_history = None;
    record.manuscript_soak_metrics = None;
    record.manuscript_promotion_gate = None;
    remove_result_link_kind(
        &mut record.execution_result_links,
        "manuscript-shadow-history",
    );
    remove_result_link_kind(
        &mut record.execution_result_links,
        "manuscript-soak-metrics",
    );
    remove_result_link_kind(
        &mut record.execution_result_links,
        "manuscript-promotion-gate",
    );
}

fn clear_manuscript_alignment_labeling_artifacts(record: &mut PersistedPlanExecutionRecord) {
    clear_manuscript_quality_uplift_artifacts(record);
    record.manuscript_alignment_labels = None;
    record.manuscript_promotion_evidence = None;
    remove_result_link_kind(
        &mut record.execution_result_links,
        "manuscript-alignment-labels",
    );
    remove_result_link_kind(
        &mut record.execution_result_links,
        "manuscript-promotion-evidence",
    );
}

fn clear_manuscript_quality_uplift_artifacts(record: &mut PersistedPlanExecutionRecord) {
    record.manuscript_trajectory_quality = None;
    record.manuscript_context_adequacy = None;
    record.manuscript_tuning_recommendation = None;
    remove_result_link_kind(
        &mut record.execution_result_links,
        "manuscript-trajectory-quality",
    );
    remove_result_link_kind(
        &mut record.execution_result_links,
        "manuscript-context-adequacy",
    );
    remove_result_link_kind(
        &mut record.execution_result_links,
        "manuscript-tuning-recommendation",
    );
}

fn clear_autonomy_calibration_evidence_artifacts(record: &mut PersistedPlanExecutionRecord) {
    clear_analysis_shadow_artifacts(record);
    clear_autonomy_calibration_state(&mut record.execution_state);
    record.autonomy_calibration_dataset = None;
    record.autonomy_policy_eval_report = None;
    record.escalation_thresholds = None;
    record.shadow_policy_comparison = None;
    record.updated_policy_recommendation = None;
    remove_result_link_kind(&mut record.execution_result_links, "autonomy-calibration-dataset");
    remove_result_link_kind(&mut record.execution_result_links, "autonomy-policy-eval-report");
    remove_result_link_kind(&mut record.execution_result_links, "escalation-thresholds");
    remove_result_link_kind(&mut record.execution_result_links, "shadow-policy-comparison");
    remove_result_link_kind(&mut record.execution_result_links, "updated-policy-recommendation");
    if let Some(receipt) = record.execution_receipt.as_mut() {
        sync_receipt_from_autonomy_calibration_state(receipt, &record.execution_state);
    }
}

fn clear_autonomy_calibration_artifacts(record: &mut PersistedPlanExecutionRecord) {
    clear_autonomy_calibration_evidence_artifacts(record);
    clear_guarded_rollout_artifacts(record);
}

fn autonomy_policy_calibration_bundle_from_record(
    record: &PersistedPlanExecutionRecord,
) -> Option<AutonomyPolicyCalibrationBundle> {
    Some(AutonomyPolicyCalibrationBundle {
        calibration_dataset: record.autonomy_calibration_dataset.clone()?,
        policy_eval_report: record.autonomy_policy_eval_report.clone()?,
        escalation_thresholds: record.escalation_thresholds.clone()?,
        shadow_policy_comparison: record.shadow_policy_comparison.clone()?,
        updated_policy_recommendation: record.updated_policy_recommendation.clone()?,
    })
}

fn guarded_policy_rollout_bundle_from_record(
    record: &PersistedPlanExecutionRecord,
) -> Option<GuardedPolicyRolloutBundle> {
    Some(GuardedPolicyRolloutBundle {
        autonomy_policy_current: record.autonomy_policy_current.clone()?,
        autonomy_policy_candidate: record.autonomy_policy_candidate.clone()?,
        rollout_metrics: record.rollout_metrics.clone()?,
        rollout_decision: record.rollout_decision.clone()?,
    })
}

fn implementation_canary_bundle_from_record(
    record: &PersistedPlanExecutionRecord,
) -> Option<ImplementationCanaryAutonomyBundle> {
    Some(ImplementationCanaryAutonomyBundle {
        autonomy_policy_control: record.autonomy_policy_control.clone()?,
        autonomy_policy_canary: record.autonomy_policy_canary.clone()?,
        canary_rollout_metrics: record.canary_rollout_metrics.clone()?,
        canary_rollback_decision: record.canary_rollback_decision.clone()?,
    })
}

fn analysis_shadow_calibration_bundle_from_record(
    record: &PersistedPlanExecutionRecord,
) -> Option<AnalysisShadowCalibrationBundle> {
    Some(AnalysisShadowCalibrationBundle {
        autonomy_policy_control: record.autonomy_policy_control.clone()?,
        autonomy_policy_analysis_candidate: record.autonomy_policy_analysis_candidate.clone()?,
        analysis_shadow_comparison: record.analysis_shadow_comparison.clone()?,
        analysis_rollout_metrics: record.analysis_rollout_metrics.clone()?,
        analysis_rollout_decision: record.analysis_rollout_decision.clone()?,
    })
}

fn analysis_shadow_soak_bundle_from_record(
    record: &PersistedPlanExecutionRecord,
) -> Option<AnalysisShadowSoakBundle> {
    Some(AnalysisShadowSoakBundle {
        analysis_shadow_history: record.analysis_shadow_history.clone()?,
        analysis_soak_metrics: record.analysis_soak_metrics.clone()?,
        analysis_promotion_gate: record.analysis_promotion_gate.clone()?,
    })
}

fn analysis_sample_accumulation_bundle_from_record(
    record: &PersistedPlanExecutionRecord,
) -> Option<AnalysisSampleAccumulationBundle> {
    Some(AnalysisSampleAccumulationBundle {
        analysis_shadow_history: record.analysis_sample_accumulation.clone()?,
        analysis_soak_metrics: record.analysis_sample_accumulation_metrics.clone()?,
        analysis_promotion_gate: record.analysis_promotion_gate_recheck.clone()?,
    })
}

fn analysis_canary_activation_bundle_from_record(
    record: &PersistedPlanExecutionRecord,
) -> Option<AnalysisCanaryActivationBundle> {
    Some(AnalysisCanaryActivationBundle {
        autonomy_policy_control: record.autonomy_policy_analysis_control.clone()?,
        autonomy_policy_implementation_canary: record
            .autonomy_policy_implementation_canary_retained
            .clone()?,
        autonomy_policy_analysis_canary: record.autonomy_policy_analysis_canary.clone()?,
        analysis_canary_metrics: record.analysis_canary_metrics.clone()?,
        analysis_canary_rollback_decision: record
            .analysis_canary_rollback_decision
            .clone()?,
    })
}

fn manuscript_shadow_calibration_bundle_from_record(
    record: &PersistedPlanExecutionRecord,
) -> Option<ManuscriptShadowCalibrationBundle> {
    Some(ManuscriptShadowCalibrationBundle {
        autonomy_policy_control: record.autonomy_policy_analysis_control.clone()?,
        autonomy_policy_manuscript_candidate: record
            .autonomy_policy_manuscript_candidate
            .clone()?,
        manuscript_shadow_comparison: record.manuscript_shadow_comparison.clone()?,
        manuscript_rollout_metrics: record.manuscript_rollout_metrics.clone()?,
        manuscript_rollout_decision: record.manuscript_rollout_decision.clone()?,
    })
}

fn manuscript_sample_accumulation_bundle_from_record(
    record: &PersistedPlanExecutionRecord,
) -> Option<ManuscriptSampleAccumulationBundle> {
    Some(ManuscriptSampleAccumulationBundle {
        manuscript_shadow_history: record.manuscript_shadow_history.clone()?,
        manuscript_soak_metrics: record.manuscript_soak_metrics.clone()?,
        manuscript_promotion_gate: record.manuscript_promotion_gate.clone()?,
    })
}

fn manuscript_alignment_labeling_bundle_from_record(
    record: &PersistedPlanExecutionRecord,
) -> Option<ManuscriptAlignmentLabelingBundle> {
    Some(ManuscriptAlignmentLabelingBundle {
        manuscript_alignment_labels: record.manuscript_alignment_labels.clone()?,
        manuscript_promotion_evidence: record.manuscript_promotion_evidence.clone()?,
        manuscript_promotion_gate: record.manuscript_promotion_gate.clone()?,
    })
}

fn manuscript_alignment_signal_bundle_from_record(
    record: &PersistedPlanExecutionRecord,
) -> Option<ManuscriptAlignmentSignalBundle> {
    let manuscript_alignment_labels = record.manuscript_alignment_labels.clone()?;
    if manuscript_alignment_labels.rollout_stage
        != "implementation-and-analysis-canary-live-manuscript-alignment-signal"
    {
        return None;
    }
    Some(ManuscriptAlignmentSignalBundle {
        manuscript_shadow_history: record.manuscript_shadow_history.clone()?,
        manuscript_soak_metrics: record.manuscript_soak_metrics.clone()?,
        manuscript_alignment_labels,
        manuscript_promotion_evidence: record.manuscript_promotion_evidence.clone()?,
        manuscript_promotion_gate: record.manuscript_promotion_gate.clone()?,
    })
}

fn manuscript_quality_uplift_bundle_from_record(
    record: &PersistedPlanExecutionRecord,
) -> Option<ManuscriptQualityUpliftBundle> {
    let manuscript_trajectory_quality = record.manuscript_trajectory_quality.clone()?;
    if manuscript_trajectory_quality.rollout_stage
        != "implementation-and-analysis-canary-live-manuscript-quality-uplift"
    {
        return None;
    }
    Some(ManuscriptQualityUpliftBundle {
        manuscript_trajectory_quality,
        manuscript_context_adequacy: record.manuscript_context_adequacy.clone()?,
        manuscript_tuning_recommendation: record.manuscript_tuning_recommendation.clone()?,
    })
}

fn manuscript_quality_uplift_state_is_synced(
    record: &PersistedPlanExecutionRecord,
) -> bool {
    if record
        .execution_state
        .autonomy_policy_calibration_status
        .as_deref()
        != Some("manuscript-quality-uplifted")
    {
        return false;
    }
    if record
        .execution_receipt
        .as_ref()
        .and_then(|receipt| receipt.autonomy_policy_calibration_status.as_deref())
        != Some("manuscript-quality-uplifted")
    {
        return false;
    }
    [
        "manuscript-trajectory-quality",
        "manuscript-context-adequacy",
        "manuscript-tuning-recommendation",
    ]
    .iter()
    .all(|link_kind| {
        record
            .execution_result_links
            .links
            .iter()
            .any(|link| link.link_kind == *link_kind)
    })
}

fn persist_autonomy_policy_calibration(
    record: &mut PersistedPlanExecutionRecord,
    workstream_id: &str,
    bundle: &AutonomyPolicyCalibrationBundle,
) {
    record.execution_state.latest_autonomy_calibration_dataset_id =
        Some(bundle.calibration_dataset.dataset_id.clone());
    record.execution_state.latest_autonomy_policy_eval_report_id =
        Some(bundle.policy_eval_report.report_id.clone());
    record.execution_state.latest_escalation_thresholds_id =
        Some(bundle.escalation_thresholds.escalation_thresholds_id.clone());
    record.execution_state.latest_shadow_policy_comparison_id = Some(
        bundle
            .shadow_policy_comparison
            .shadow_policy_comparison_id
            .clone(),
    );
    record.execution_state.latest_updated_policy_recommendation_id = Some(
        bundle
            .updated_policy_recommendation
            .updated_policy_recommendation_id
            .clone(),
    );
    record.execution_state.autonomy_policy_calibration_status =
        Some("shadow-evaluated".to_string());
    record.autonomy_calibration_dataset = Some(bundle.calibration_dataset.clone());
    record.autonomy_policy_eval_report = Some(bundle.policy_eval_report.clone());
    record.escalation_thresholds = Some(bundle.escalation_thresholds.clone());
    record.shadow_policy_comparison = Some(bundle.shadow_policy_comparison.clone());
    record.updated_policy_recommendation = Some(bundle.updated_policy_recommendation.clone());
    if let Some(receipt) = record.execution_receipt.as_mut() {
        sync_receipt_from_autonomy_calibration_state(receipt, &record.execution_state);
    }
    upsert_result_link(
        &mut record.execution_result_links,
        execution_result_link(
            &record.execution_state.execution_id,
            "autonomy-calibration-dataset",
            &autonomy_calibration_dataset_path(workstream_id),
            "Canonical B24.7 replay-plus-shadow calibration dataset linked to the same Beagle-owned execution identity.",
        ),
    );
    upsert_result_link(
        &mut record.execution_result_links,
        execution_result_link(
            &record.execution_state.execution_id,
            "autonomy-policy-eval-report",
            &autonomy_policy_eval_report_path(workstream_id),
            "Shadow-mode policy eval report measuring whether the live gate is too permissive, too conservative, or aligned.",
        ),
    );
    upsert_result_link(
        &mut record.execution_result_links,
        execution_result_link(
            &record.execution_state.execution_id,
            "escalation-thresholds",
            &escalation_thresholds_path(workstream_id),
            "Per-task-family escalation threshold recommendations staged in shadow mode only.",
        ),
    );
    upsert_result_link(
        &mut record.execution_result_links,
        execution_result_link(
            &record.execution_state.execution_id,
            "shadow-policy-comparison",
            &shadow_policy_comparison_path(workstream_id),
            "Comparison of the current live gate against the staged shadow thresholds.",
        ),
    );
    upsert_result_link(
        &mut record.execution_result_links,
        execution_result_link(
            &record.execution_state.execution_id,
            "updated-policy-recommendation",
            &updated_policy_recommendation_path(workstream_id),
            "Bounded, operator-reviewed policy update recommendation that stays shadow-only in B24.7.",
        ),
    );
}

fn persist_guarded_policy_rollout(
    record: &mut PersistedPlanExecutionRecord,
    workstream_id: &str,
    bundle: &GuardedPolicyRolloutBundle,
) {
    record.execution_state.latest_autonomy_policy_current_id =
        Some(bundle.autonomy_policy_current.shadow_threshold_id.clone());
    record.execution_state.latest_autonomy_policy_candidate_id =
        Some(bundle.autonomy_policy_candidate.shadow_threshold_id.clone());
    record.execution_state.latest_rollout_metrics_id =
        Some(bundle.rollout_metrics.rollout_metrics_id.clone());
    record.execution_state.latest_guarded_rollout_decision_id =
        Some(bundle.rollout_decision.guarded_rollout_decision_id.clone());
    record.execution_state.autonomy_policy_rollout_status =
        Some("implementation-canary-staged".to_string());
    record.autonomy_policy_current = Some(bundle.autonomy_policy_current.clone());
    record.autonomy_policy_candidate = Some(bundle.autonomy_policy_candidate.clone());
    record.rollout_metrics = Some(bundle.rollout_metrics.clone());
    record.rollout_decision = Some(bundle.rollout_decision.clone());
    if let Some(receipt) = record.execution_receipt.as_mut() {
        sync_receipt_from_guarded_rollout_state(receipt, &record.execution_state);
    }
    upsert_result_link(
        &mut record.execution_result_links,
        execution_result_link(
            &record.execution_state.execution_id,
            "autonomy-policy-current",
            &autonomy_policy_current_path(workstream_id),
            "Current autonomy policy preserved as the explicit rollout control.",
        ),
    );
    upsert_result_link(
        &mut record.execution_result_links,
        execution_result_link(
            &record.execution_state.execution_id,
            "autonomy-policy-candidate",
            &autonomy_policy_candidate_path(workstream_id),
            "Candidate autonomy policy staged in shadow mode for guarded rollout comparison.",
        ),
    );
    upsert_result_link(
        &mut record.execution_result_links,
        execution_result_link(
            &record.execution_state.execution_id,
            "rollout-metrics",
            &rollout_metrics_path(workstream_id),
            "Rollout metrics comparing the current control policy against the staged candidate policy.",
        ),
    );
    upsert_result_link(
        &mut record.execution_result_links,
        execution_result_link(
            &record.execution_state.execution_id,
            "guarded-rollout-decision",
            &rollout_decision_path(workstream_id),
            "Guarded rollout decision preserving control while staging implementation-only canary readiness and explicit rollback.",
        ),
    );
}

fn persist_implementation_canary_autonomy(
    record: &mut PersistedPlanExecutionRecord,
    workstream_id: &str,
    bundle: &ImplementationCanaryAutonomyBundle,
) {
    record.execution_state.autonomy_policy_rollout_status =
        Some("implementation-canary-live".to_string());
    record.autonomy_policy_control = Some(bundle.autonomy_policy_control.clone());
    record.autonomy_policy_canary = Some(bundle.autonomy_policy_canary.clone());
    record.canary_rollout_metrics = Some(bundle.canary_rollout_metrics.clone());
    record.canary_rollback_decision = Some(bundle.canary_rollback_decision.clone());
    if let Some(receipt) = record.execution_receipt.as_mut() {
        sync_receipt_from_guarded_rollout_state(receipt, &record.execution_state);
    }
    upsert_result_link(
        &mut record.execution_result_links,
        execution_result_link(
            &record.execution_state.execution_id,
            "autonomy-policy-control",
            &autonomy_policy_control_path(workstream_id),
            "Live control autonomy policy preserved while the implementation family runs on guarded canary.",
        ),
    );
    upsert_result_link(
        &mut record.execution_result_links,
        execution_result_link(
            &record.execution_state.execution_id,
            "autonomy-policy-canary",
            &autonomy_policy_canary_path(workstream_id),
            "Implementation-only canary autonomy policy activated live on the same Beagle-owned identity.",
        ),
    );
    upsert_result_link(
        &mut record.execution_result_links,
        execution_result_link(
            &record.execution_state.execution_id,
            "canary-rollout-metrics",
            &canary_rollout_metrics_path(workstream_id),
            "Guarded canary metrics isolating implementation canary health while analysis and manuscript remain on control.",
        ),
    );
    upsert_result_link(
        &mut record.execution_result_links,
        execution_result_link(
            &record.execution_state.execution_id,
            "canary-rollback-decision",
            &canary_rollback_decision_path(workstream_id),
            "Explicit rollback decision for the implementation canary rollout.",
        ),
    );
}

fn persist_analysis_shadow_calibration(
    record: &mut PersistedPlanExecutionRecord,
    workstream_id: &str,
    bundle: &AnalysisShadowCalibrationBundle,
) {
    record.execution_state.autonomy_policy_calibration_status =
        Some("analysis-shadow-evaluated".to_string());
    record.autonomy_policy_analysis_candidate =
        Some(bundle.autonomy_policy_analysis_candidate.clone());
    record.analysis_shadow_comparison = Some(bundle.analysis_shadow_comparison.clone());
    record.analysis_rollout_metrics = Some(bundle.analysis_rollout_metrics.clone());
    record.analysis_rollout_decision = Some(bundle.analysis_rollout_decision.clone());
    if let Some(receipt) = record.execution_receipt.as_mut() {
        sync_receipt_from_autonomy_calibration_state(receipt, &record.execution_state);
    }
    upsert_result_link(
        &mut record.execution_result_links,
        execution_result_link(
            &record.execution_state.execution_id,
            "autonomy-policy-control",
            &autonomy_policy_control_path(workstream_id),
            "Live control autonomy policy preserved while analysis is evaluated in shadow mode.",
        ),
    );
    upsert_result_link(
        &mut record.execution_result_links,
        execution_result_link(
            &record.execution_state.execution_id,
            "autonomy-policy-analysis-candidate",
            &autonomy_policy_analysis_candidate_path(workstream_id),
            "Analysis-only candidate autonomy policy staged in shadow mode.",
        ),
    );
    upsert_result_link(
        &mut record.execution_result_links,
        execution_result_link(
            &record.execution_state.execution_id,
            "analysis-shadow-comparison",
            &analysis_shadow_comparison_path(workstream_id),
            "Shadow comparison of the current control policy against the staged analysis candidate policy.",
        ),
    );
    upsert_result_link(
        &mut record.execution_result_links,
        execution_result_link(
            &record.execution_state.execution_id,
            "analysis-rollout-metrics",
            &analysis_rollout_metrics_path(workstream_id),
            "Analysis-family rollout metrics recorded while implementation stays on live canary and manuscript stays on control.",
        ),
    );
    upsert_result_link(
        &mut record.execution_result_links,
        execution_result_link(
            &record.execution_state.execution_id,
            "analysis-rollout-decision",
            &analysis_rollout_decision_path(workstream_id),
            "Explicit B24.10 analysis rollout decision: keep-shadow, stage-analysis-canary, or rollback-shadow.",
        ),
    );
}

fn persist_analysis_shadow_soak(
    record: &mut PersistedPlanExecutionRecord,
    workstream_id: &str,
    bundle: &AnalysisShadowSoakBundle,
) {
    record.execution_state.autonomy_policy_calibration_status =
        Some("analysis-shadow-soaked".to_string());
    record.analysis_shadow_history = Some(bundle.analysis_shadow_history.clone());
    record.analysis_soak_metrics = Some(bundle.analysis_soak_metrics.clone());
    record.analysis_promotion_gate = Some(bundle.analysis_promotion_gate.clone());
    if let Some(receipt) = record.execution_receipt.as_mut() {
        sync_receipt_from_autonomy_calibration_state(receipt, &record.execution_state);
    }
    upsert_result_link(
        &mut record.execution_result_links,
        execution_result_link(
            &record.execution_state.execution_id,
            "analysis-shadow-history",
            &analysis_shadow_history_path(workstream_id),
            "Bounded analysis shadow history accumulated across the rolling soak window.",
        ),
    );
    upsert_result_link(
        &mut record.execution_result_links,
        execution_result_link(
            &record.execution_state.execution_id,
            "analysis-soak-metrics",
            &analysis_soak_metrics_path(workstream_id),
            "Rolling analysis shadow soak metrics used to decide whether promotion is safe.",
        ),
    );
    upsert_result_link(
        &mut record.execution_result_links,
        execution_result_link(
            &record.execution_state.execution_id,
            "analysis-promotion-gate",
            &analysis_promotion_gate_path(workstream_id),
            "Explicit B24.11 promotion gate deciding keep-shadow, stage-analysis-canary, or rollback-shadow.",
        ),
    );
}

fn persist_analysis_sample_accumulation(
    record: &mut PersistedPlanExecutionRecord,
    workstream_id: &str,
    bundle: &AnalysisSampleAccumulationBundle,
) {
    record.execution_state.autonomy_policy_calibration_status =
        Some("analysis-shadow-rechecked".to_string());
    record.analysis_sample_accumulation = Some(bundle.analysis_shadow_history.clone());
    record.analysis_sample_accumulation_metrics = Some(bundle.analysis_soak_metrics.clone());
    record.analysis_promotion_gate_recheck = Some(bundle.analysis_promotion_gate.clone());
    if let Some(receipt) = record.execution_receipt.as_mut() {
        sync_receipt_from_autonomy_calibration_state(receipt, &record.execution_state);
    }
    upsert_result_link(
        &mut record.execution_result_links,
        execution_result_link(
            &record.execution_state.execution_id,
            "analysis-sample-accumulation",
            &analysis_sample_accumulation_path(workstream_id),
            "B24.12 bounded analysis sample accumulation refresh preserving control-live analysis while accumulating recheck evidence.",
        ),
    );
    upsert_result_link(
        &mut record.execution_result_links,
        execution_result_link(
            &record.execution_state.execution_id,
            "analysis-sample-accumulation-metrics",
            &analysis_sample_accumulation_metrics_path(workstream_id),
            "Updated rolling analysis soak metrics after bounded sample accumulation recheck.",
        ),
    );
    upsert_result_link(
        &mut record.execution_result_links,
        execution_result_link(
            &record.execution_state.execution_id,
            "analysis-promotion-gate-recheck",
            &analysis_promotion_gate_recheck_path(workstream_id),
            "Explicit B24.12 promotion-gate recheck deciding whether analysis stays keep-shadow or can be staged for canary.",
        ),
    );
}

fn persist_analysis_canary_activation(
    record: &mut PersistedPlanExecutionRecord,
    workstream_id: &str,
    bundle: &AnalysisCanaryActivationBundle,
) {
    record.execution_state.autonomy_policy_rollout_status =
        Some("implementation-and-analysis-canary-live".to_string());
    record.autonomy_policy_analysis_control =
        Some(bundle.autonomy_policy_control.clone());
    record.autonomy_policy_implementation_canary_retained =
        Some(bundle.autonomy_policy_implementation_canary.clone());
    record.autonomy_policy_analysis_canary =
        Some(bundle.autonomy_policy_analysis_canary.clone());
    record.analysis_canary_metrics = Some(bundle.analysis_canary_metrics.clone());
    record.analysis_canary_rollback_decision =
        Some(bundle.analysis_canary_rollback_decision.clone());
    if let Some(receipt) = record.execution_receipt.as_mut() {
        sync_receipt_from_guarded_rollout_state(receipt, &record.execution_state);
    }
    upsert_result_link(
        &mut record.execution_result_links,
        execution_result_link(
            &record.execution_state.execution_id,
            "autonomy-policy-analysis-control",
            &autonomy_policy_analysis_control_path(workstream_id),
            "Explicit live control policy retained for manuscript while analysis and implementation canaries remain independently visible.",
        ),
    );
    upsert_result_link(
        &mut record.execution_result_links,
        execution_result_link(
            &record.execution_state.execution_id,
            "autonomy-policy-implementation-canary",
            &autonomy_policy_implementation_canary_path(workstream_id),
            "Existing implementation canary retained live during the guarded analysis canary expansion.",
        ),
    );
    upsert_result_link(
        &mut record.execution_result_links,
        execution_result_link(
            &record.execution_state.execution_id,
            "autonomy-policy-analysis-canary",
            &autonomy_policy_analysis_canary_path(workstream_id),
            "Dedicated analysis canary activated live after the bounded promotion gate cleared it.",
        ),
    );
    upsert_result_link(
        &mut record.execution_result_links,
        execution_result_link(
            &record.execution_state.execution_id,
            "analysis-canary-metrics",
            &analysis_canary_metrics_path(workstream_id),
            "Explicit canary metrics for the guarded analysis rollout while implementation stays on canary and manuscript stays on control.",
        ),
    );
    upsert_result_link(
        &mut record.execution_result_links,
        execution_result_link(
            &record.execution_state.execution_id,
            "analysis-canary-rollback-decision",
            &analysis_canary_rollback_decision_path(workstream_id),
            "Immediate rollback contract for the live analysis canary expansion.",
        ),
    );
}

fn persist_manuscript_shadow_calibration(
    record: &mut PersistedPlanExecutionRecord,
    workstream_id: &str,
    bundle: &ManuscriptShadowCalibrationBundle,
) {
    record.execution_state.autonomy_policy_calibration_status =
        Some("manuscript-shadow-evaluated".to_string());
    record.autonomy_policy_manuscript_candidate =
        Some(bundle.autonomy_policy_manuscript_candidate.clone());
    record.manuscript_shadow_comparison =
        Some(bundle.manuscript_shadow_comparison.clone());
    record.manuscript_rollout_metrics = Some(bundle.manuscript_rollout_metrics.clone());
    record.manuscript_rollout_decision =
        Some(bundle.manuscript_rollout_decision.clone());
    if let Some(receipt) = record.execution_receipt.as_mut() {
        sync_receipt_from_autonomy_calibration_state(receipt, &record.execution_state);
    }
    upsert_result_link(
        &mut record.execution_result_links,
        execution_result_link(
            &record.execution_state.execution_id,
            "autonomy-policy-manuscript-control",
            &autonomy_policy_manuscript_control_path(workstream_id),
            "Explicit live control policy retained for manuscript while implementation and analysis remain on live canaries.",
        ),
    );
    upsert_result_link(
        &mut record.execution_result_links,
        execution_result_link(
            &record.execution_state.execution_id,
            "autonomy-policy-manuscript-candidate",
            &autonomy_policy_manuscript_candidate_path(workstream_id),
            "Manuscript-only candidate autonomy policy staged in shadow mode.",
        ),
    );
    upsert_result_link(
        &mut record.execution_result_links,
        execution_result_link(
            &record.execution_state.execution_id,
            "manuscript-shadow-comparison",
            &manuscript_shadow_comparison_path(workstream_id),
            "Shadow comparison of the current manuscript control policy against the staged manuscript candidate policy.",
        ),
    );
    upsert_result_link(
        &mut record.execution_result_links,
        execution_result_link(
            &record.execution_state.execution_id,
            "manuscript-rollout-metrics",
            &manuscript_rollout_metrics_path(workstream_id),
            "Manuscript-family rollout metrics recorded while implementation and analysis stay on live canaries.",
        ),
    );
    upsert_result_link(
        &mut record.execution_result_links,
        execution_result_link(
            &record.execution_state.execution_id,
            "manuscript-rollout-decision",
            &manuscript_rollout_decision_path(workstream_id),
            "Explicit B24.14 manuscript rollout decision: keep-shadow, stage-manuscript-canary, or rollback-shadow.",
        ),
    );
}

fn persist_manuscript_sample_accumulation(
    record: &mut PersistedPlanExecutionRecord,
    workstream_id: &str,
    bundle: &ManuscriptSampleAccumulationBundle,
) {
    record.execution_state.autonomy_policy_calibration_status =
        Some("manuscript-shadow-rechecked".to_string());
    record.manuscript_shadow_history = Some(bundle.manuscript_shadow_history.clone());
    record.manuscript_soak_metrics = Some(bundle.manuscript_soak_metrics.clone());
    record.manuscript_promotion_gate = Some(bundle.manuscript_promotion_gate.clone());
    if let Some(receipt) = record.execution_receipt.as_mut() {
        sync_receipt_from_autonomy_calibration_state(receipt, &record.execution_state);
    }
    upsert_result_link(
        &mut record.execution_result_links,
        execution_result_link(
            &record.execution_state.execution_id,
            "manuscript-shadow-history",
            &manuscript_shadow_history_path(workstream_id),
            "B24.15 bounded manuscript shadow history accumulated across the rolling recheck window.",
        ),
    );
    upsert_result_link(
        &mut record.execution_result_links,
        execution_result_link(
            &record.execution_state.execution_id,
            "manuscript-soak-metrics",
            &manuscript_soak_metrics_path(workstream_id),
            "Rolling manuscript shadow metrics used to decide whether staged manuscript canary promotion is safe.",
        ),
    );
    upsert_result_link(
        &mut record.execution_result_links,
        execution_result_link(
            &record.execution_state.execution_id,
            "manuscript-promotion-gate",
            &manuscript_promotion_gate_path(workstream_id),
            "Explicit B24.15 manuscript promotion-gate recheck deciding whether manuscript stays keep-shadow or can be staged for canary.",
        ),
    );
}

fn persist_manuscript_alignment_labeling(
    record: &mut PersistedPlanExecutionRecord,
    workstream_id: &str,
    bundle: &ManuscriptAlignmentLabelingBundle,
) {
    record.execution_state.autonomy_policy_calibration_status =
        Some("manuscript-alignment-labeled".to_string());
    record.manuscript_alignment_labels =
        Some(bundle.manuscript_alignment_labels.clone());
    record.manuscript_promotion_evidence =
        Some(bundle.manuscript_promotion_evidence.clone());
    record.manuscript_promotion_gate = Some(bundle.manuscript_promotion_gate.clone());
    if let Some(receipt) = record.execution_receipt.as_mut() {
        sync_receipt_from_autonomy_calibration_state(receipt, &record.execution_state);
    }
    upsert_result_link(
        &mut record.execution_result_links,
        execution_result_link(
            &record.execution_state.execution_id,
            "manuscript-alignment-labels",
            &manuscript_alignment_labels_path(workstream_id),
            "B24.16 explicit manuscript alignment labels linking operator/execution evidence back to the same Beagle-owned identity.",
        ),
    );
    upsert_result_link(
        &mut record.execution_result_links,
        execution_result_link(
            &record.execution_state.execution_id,
            "manuscript-promotion-evidence",
            &manuscript_promotion_evidence_path(workstream_id),
            "Aggregated manuscript promotion evidence derived from explicit alignment labels and bounded review-quality labeling.",
        ),
    );
    upsert_result_link(
        &mut record.execution_result_links,
        execution_result_link(
            &record.execution_state.execution_id,
            "manuscript-promotion-gate",
            &manuscript_promotion_gate_path(workstream_id),
            "Explicit B24.16 manuscript promotion gate consuming aligned, misaligned, and insufficient-evidence labels before any staged canary decision.",
        ),
    );
}

fn persist_manuscript_alignment_signal(
    record: &mut PersistedPlanExecutionRecord,
    workstream_id: &str,
    bundle: &ManuscriptAlignmentSignalBundle,
) {
    record.execution_state.autonomy_policy_calibration_status =
        Some("manuscript-alignment-signal-acquired".to_string());
    record.manuscript_shadow_history = Some(bundle.manuscript_shadow_history.clone());
    record.manuscript_soak_metrics = Some(bundle.manuscript_soak_metrics.clone());
    record.manuscript_alignment_labels = Some(bundle.manuscript_alignment_labels.clone());
    record.manuscript_promotion_evidence =
        Some(bundle.manuscript_promotion_evidence.clone());
    record.manuscript_promotion_gate = Some(bundle.manuscript_promotion_gate.clone());
    if let Some(receipt) = record.execution_receipt.as_mut() {
        sync_receipt_from_autonomy_calibration_state(receipt, &record.execution_state);
    }
    upsert_result_link(
        &mut record.execution_result_links,
        execution_result_link(
            &record.execution_state.execution_id,
            "manuscript-shadow-history",
            &manuscript_shadow_history_path(workstream_id),
            "B24.17 refreshed manuscript shadow history with explicit alignment-signal acquisition while keeping manuscript on shadow.",
        ),
    );
    upsert_result_link(
        &mut record.execution_result_links,
        execution_result_link(
            &record.execution_state.execution_id,
            "manuscript-soak-metrics",
            &manuscript_soak_metrics_path(workstream_id),
            "B24.17 manuscript soak metrics after bounded alignment-signal acquisition and promotion evidence refresh.",
        ),
    );
    upsert_result_link(
        &mut record.execution_result_links,
        execution_result_link(
            &record.execution_state.execution_id,
            "manuscript-alignment-labels",
            &manuscript_alignment_labels_path(workstream_id),
            "B24.17 explicit manuscript alignment labels after bounded signal acquisition.",
        ),
    );
    upsert_result_link(
        &mut record.execution_result_links,
        execution_result_link(
            &record.execution_state.execution_id,
            "manuscript-promotion-evidence",
            &manuscript_promotion_evidence_path(workstream_id),
            "B24.17 aggregated manuscript promotion evidence after explicit signal acquisition.",
        ),
    );
    upsert_result_link(
        &mut record.execution_result_links,
        execution_result_link(
            &record.execution_state.execution_id,
            "manuscript-promotion-gate",
            &manuscript_promotion_gate_path(workstream_id),
            "B24.17 manuscript promotion gate recheck after bounded alignment-signal acquisition.",
        ),
    );
}

fn persist_manuscript_quality_uplift(
    record: &mut PersistedPlanExecutionRecord,
    workstream_id: &str,
    bundle: &ManuscriptQualityUpliftBundle,
) {
    record.execution_state.autonomy_policy_calibration_status =
        Some("manuscript-quality-uplifted".to_string());
    record.manuscript_trajectory_quality =
        Some(bundle.manuscript_trajectory_quality.clone());
    record.manuscript_context_adequacy =
        Some(bundle.manuscript_context_adequacy.clone());
    record.manuscript_tuning_recommendation =
        Some(bundle.manuscript_tuning_recommendation.clone());
    if let Some(receipt) = record.execution_receipt.as_mut() {
        sync_receipt_from_autonomy_calibration_state(receipt, &record.execution_state);
    }
    upsert_result_link(
        &mut record.execution_result_links,
        execution_result_link(
            &record.execution_state.execution_id,
            "manuscript-trajectory-quality",
            &manuscript_trajectory_quality_path(workstream_id),
            "B24.18 explicit manuscript trajectory quality eval explaining whether the editorial lane is promotion-worthy or still needs bounded shadow tuning.",
        ),
    );
    upsert_result_link(
        &mut record.execution_result_links,
        execution_result_link(
            &record.execution_state.execution_id,
            "manuscript-context-adequacy",
            &manuscript_context_adequacy_path(workstream_id),
            "B24.18 manuscript context adequacy eval checking retrieval lane, GraphRAG mode, truth view, compiler profile, task profile, and handoff fit.",
        ),
    );
    upsert_result_link(
        &mut record.execution_result_links,
        execution_result_link(
            &record.execution_state.execution_id,
            "manuscript-tuning-recommendation",
            &manuscript_tuning_recommendation_path(workstream_id),
            "B24.18 bounded manuscript tuning recommendation describing the next shadow-only policy candidate to test before any future canary consideration.",
        ),
    );
}

fn evaluate_follow_on_plan_gate(
    record: &PersistedPlanExecutionRecord,
    workstream_id: &str,
    inbox_item: &ReviewInboxItem,
    review_decision: &ReviewDecision,
    follow_on_plan: &FollowOnPlan,
) -> anyhow::Result<(AutonomyPolicy, RiskEvaluation, ApprovalGatingDecision)> {
    let autonomy_policy = select_effective_autonomy_policy(record, follow_on_plan);
    let risk_evaluation = build_risk_evaluation(
        &autonomy_policy,
        inbox_item,
        review_decision,
        follow_on_plan,
        record.execution_reflection.as_ref(),
        record.trajectory_eval.as_ref(),
        record.replan_suggestion.as_ref(),
    );
    let approval_gating_decision = build_approval_gating_decision(
        &autonomy_policy,
        &risk_evaluation,
        inbox_item,
        review_decision,
        follow_on_plan,
        &review_inbox_path(workstream_id),
        &continuation_dispatch_path(workstream_id),
    );
    Ok((autonomy_policy, risk_evaluation, approval_gating_decision))
}

fn select_effective_autonomy_policy(
    record: &PersistedPlanExecutionRecord,
    follow_on_plan: &FollowOnPlan,
) -> AutonomyPolicy {
    if let Some(bundle) = analysis_canary_activation_bundle_from_record(record) {
        if follow_on_plan.execution_plan.task_family == "implementation"
            && bundle
                .analysis_canary_rollback_decision
                .implementation_canary_retained
        {
            return bundle.autonomy_policy_implementation_canary;
        }
        if follow_on_plan.execution_plan.task_family == "analysis"
            && bundle.analysis_canary_rollback_decision.analysis_canary_live
        {
            return bundle.autonomy_policy_analysis_canary;
        }
        return bundle.autonomy_policy_control;
    }

    if let Some(bundle) = implementation_canary_bundle_from_record(record) {
        if follow_on_plan.execution_plan.task_family == "implementation"
            && bundle.canary_rollout_metrics.implementation_canary_enabled
            && !bundle.canary_rollback_decision.rollback_required
        {
            return bundle.autonomy_policy_canary;
        }
        return bundle.autonomy_policy_control;
    }

    build_autonomy_policy(follow_on_plan)
}

fn upsert_result_link(
    result_links: &mut ExecutionResultLinksDocument,
    link: ExecutionResultLink,
) {
    if let Some(existing) = result_links
        .links
        .iter_mut()
        .find(|existing| existing.link_kind == link.link_kind)
    {
        *existing = link;
    } else {
        result_links.links.push(link);
    }
}

fn remove_result_link_kind(
    result_links: &mut ExecutionResultLinksDocument,
    link_kind: &str,
) {
    result_links
        .links
        .retain(|link| link.link_kind != link_kind);
}

fn normalize_sentence(value: &str) -> String {
    value.trim().split_whitespace().collect::<Vec<_>>().join(" ")
}

fn sanitize_component(value: &str) -> String {
    let sanitized = value
        .chars()
        .map(|ch| {
            if ch.is_ascii_alphanumeric() || matches!(ch, '-' | '_') {
                ch
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
    use crate::execution_plan::{ExecutionRecipeTarget, PlanAcceptanceCriterion};
    use crate::{
        WorkstreamContextPacket, WorkstreamContextPacketExperimentFlags,
        WorkstreamContextPacketHandoff, WorkstreamContextPacketLastResult,
        WorkstreamContextPacketMemoryHit, WorkstreamContextPacketResponse,
        WorkstreamContextPacketRetrievalContext, WorkstreamContextPacketRetrievalFilters,
        WorkstreamContextPacketResultSummary, WorkspaceSessionState,
    };
    use beagle_config::{
        AdvancedModulesConfig, BeagleConfig, ConsumerAccessConfig, GraphConfig, HermesConfig,
        LlmConfig, ObserverThresholds, StorageConfig, ToolBridgeConfig, WorkspaceHabitatConfig,
        WorkspacePlaneConfig,
    };
    use std::{env, path::PathBuf};

    fn packet() -> WorkstreamContextPacketResponse {
        WorkstreamContextPacketResponse {
            status: "ok".to_string(),
            phase: "B18.1".to_string(),
            packet: WorkstreamContextPacket {
                packet_version: "beagle-memory-aware-context-packet-v1".to_string(),
                workstream_id: "beagle-darwin-hpc-governance".to_string(),
                workspace_id: "beagle-cluster-pilot".to_string(),
                session_id: "ws-cluster-workspace-habitat".to_string(),
                repo: "agourakis82/beagle".to_string(),
                branch: "feat/darwin-hpc-governance".to_string(),
                governance_state: "canonical".to_string(),
                handoff: WorkstreamContextPacketHandoff {
                    handoff_required: true,
                    recovery_required: true,
                    handoff_present: true,
                    last_handoff: Some("resume from canonical Beagle workspace state".to_string()),
                },
                last_result: WorkstreamContextPacketLastResult {
                    available: true,
                    reference: None,
                    summary: Some(WorkstreamContextPacketResultSummary {
                        job_id: 42,
                        state: "published".to_string(),
                        run_label: "b241-plan".to_string(),
                        profile_id: "cpu-batch-v1".to_string(),
                        node_list: "t560-proxmox".to_string(),
                        manifest_key: "results/b241-plan/result-42.json".to_string(),
                        source_phase: Some("B24.1".to_string()),
                        source_run_id: Some("b241-intent-planner".to_string()),
                    }),
                    manifest: None,
                    error: None,
                },
                last_successful_task: None,
                latest_physio: None,
                experiment_flags: Some(WorkstreamContextPacketExperimentFlags {
                    hrv_aware: Some(true),
                    observer_enabled: Some(true),
                    serendipity_enabled: Some(false),
                    triad_enabled: Some(false),
                    provider: Some("xai".to_string()),
                    model: Some("grok-4-1-fast-reasoning".to_string()),
                    experiment_id: Some("expedition-002".to_string()),
                    condition: Some("hrv-aware".to_string()),
                }),
                memory_hits: vec![WorkstreamContextPacketMemoryHit {
                    memory_id: Some("memory-1".to_string()),
                    source: "bridge".to_string(),
                    conversation_id: None,
                    turn_index: Some(0),
                    role: Some("assistant".to_string()),
                    snippet: "Keep one workspace identity while executing bounded plans.".to_string(),
                    timestamp: None,
                    relevance: 0.93,
                    tags: vec!["execution".to_string()],
                    domain: Some("darwin-hpc".to_string()),
                    physio_snapshot: None,
                }],
                retrieval_context: Some(WorkstreamContextPacketRetrievalContext {
                    query_text: "run the operator analysis loop".to_string(),
                    query_type: "general".to_string(),
                    retrieval_mode: "hybrid".to_string(),
                    dense_backend: "voyage-4-large".to_string(),
                    sparse_backend: "local-lexical".to_string(),
                    routing_source: "router".to_string(),
                    routing_reason: "analysis query routed to the general lane".to_string(),
                    reranking_applied: false,
                    reranking_profile_id: None,
                    reranker_backend: None,
                    reranker_runtime_state: None,
                    reranking_latency_ms: None,
                    top_k: 4,
                    applied_filters: WorkstreamContextPacketRetrievalFilters::default(),
                    hit_count: 1,
                    top_memory_ids: vec!["memory-1".to_string()],
                    top_domains: vec!["darwin-hpc".to_string()],
                    top_tags: vec!["execution".to_string()],
                    promotion_policy_id: Some("b232-memory-promotion-policy".to_string()),
                    retention_policy_id: Some("b232-memory-retention-policy".to_string()),
                    graphrag_query_mode: Some("global".to_string()),
                    graphrag_query_mode_reason: Some("analysis".to_string()),
                    graphrag_root_entity_type: Some("Campaign".to_string()),
                    graphrag_root_entity_id: Some("expedition-002-hrv-aware".to_string()),
                    graphrag_node_count: 8,
                    graphrag_edge_count: 7,
                    graphrag_node_types: vec!["Campaign".to_string()],
                    graphrag_edge_types: vec!["uses".to_string()],
                    memory_hierarchy_counts: vec![],
                    promoted_memory_count: 0,
                    promoted_target_memory_types: vec![],
                    compiled_context_task_profile: Some("analysis".to_string()),
                    compiled_context_budget_profile_id: Some("b235-budget-analysis".to_string()),
                    compiled_context_retrieval_query_type: Some("general".to_string()),
                    compiled_context_graphrag_query_mode: Some("global".to_string()),
                    compiled_context_selected_memory_tiers: vec![
                        "semantic".to_string(),
                        "episodic".to_string(),
                    ],
                    compiled_context_source_slices: vec![],
                    compiled_context_top_memory_ids: vec![
                        "memory-1".to_string(),
                        "memory-2".to_string(),
                    ],
                    compiled_context_preview: Some("analysis preview".to_string()),
                    planner: None,
                    execution: None,
                    temporal_truth_view: Some("both".to_string()),
                    temporal_subject_refs: vec!["claim:1".to_string()],
                    temporal_current_memory_ids: vec!["memory-1".to_string()],
                    temporal_historical_memory_ids: vec!["memory-0".to_string()],
                    temporal_track_count: 1,
                    temporal_contradiction_count: 0,
                    temporal_contradiction_ids: vec![],
                    temporal_preview: Some("truth_view: both".to_string()),
                    suggested_subagent_id: Some("experiments".to_string()),
                    suggested_work_mode: Some("analysis".to_string()),
                    influence_reason: "analysis retrieval context".to_string(),
                }),
                recommended_recipe: None,
                bounded_study_baseline: None,
            },
        }
    }

    fn test_config(data_dir: &Path) -> BeagleConfig {
        let mut cfg = BeagleConfig {
            profile: "cluster".to_string(),
            safe_mode: true,
            api_token: Some("test-token".to_string()),
            llm: LlmConfig::default(),
            storage: StorageConfig {
                data_dir: data_dir.display().to_string(),
            },
            graph: GraphConfig::default(),
            hermes: HermesConfig::default(),
            tool_bridge: ToolBridgeConfig::default(),
            workspace: WorkspacePlaneConfig {
                canonical_workspace_id: "beagle-cluster-pilot".to_string(),
                canonical_repo: "agourakis82/beagle".to_string(),
                canonical_branch: "feat/darwin-hpc-governance".to_string(),
                canonical_track: "darwin-hpc".to_string(),
                operator_name: Some("test-operator".to_string()),
                default_dev_plane: "beagle-cluster".to_string(),
                vm_fallback_role: "fallback-only".to_string(),
                promotion_scope: "beagle-darwin-hpc-general-noninfra".to_string(),
                cutover_workstream: "beagle-darwin-hpc-governance".to_string(),
                cutover_state: "canonical".to_string(),
                cutover_last_transition: "resume".to_string(),
                cutover_branch_lineage: "feat/darwin-hpc-governance".to_string(),
                cutover_default_profile: "cpu-short-v1".to_string(),
                cutover_batch_profile: "cpu-batch-v1".to_string(),
                cutover_advanced_profile: "gpu-single-v1".to_string(),
                cutover_result_publication: "object-backed".to_string(),
                cutover_result_retrieval: "object-backed".to_string(),
                cutover_result_retention_policy: "active".to_string(),
                cutover_operator_consumer_policy: "full".to_string(),
                cutover_research_consumer_policy: "bounded".to_string(),
                cutover_recovery_required: true,
                cutover_handoff_required: true,
                bootstrap_enabled: true,
                habitat: WorkspaceHabitatConfig::default(),
            },
            consumers: ConsumerAccessConfig::default(),
            advanced: AdvancedModulesConfig::default(),
            observer: ObserverThresholds::default(),
        };
        cfg.workspace.habitat.ssh_enabled = true;
        cfg.workspace.habitat.ssh_service_port = 2222;
        cfg.workspace.habitat.ssh_user = "openvscode-server".to_string();
        cfg
    }

    fn seed_workspace_session(data_dir: &Path, cfg: &BeagleConfig) {
        let state = WorkspaceSessionState::new(
            cfg,
            "beagle-cluster-pilot".to_string(),
            Some("ws-cluster-workspace-habitat".to_string()),
        );
        crate::write_workspace_session(data_dir, &state).unwrap();
    }

    fn temp_data_dir(test_name: &str) -> PathBuf {
        let dir = env::temp_dir().join(format!(
            "beagle-b242-{}-{}",
            test_name,
            Utc::now().timestamp_nanos_opt().unwrap_or_default()
        ));
        fs::create_dir_all(&dir).unwrap();
        dir
    }

    fn analysis_plan() -> ExecutionPlan {
        ExecutionPlan {
            plan_version: "beagle-execution-plan-v1".to_string(),
            plan_id: "ws-cluster-workspace-habitat-analysis".to_string(),
            planner_policy_id: "b241-intent-planner-policy".to_string(),
            workstream_id: "beagle-darwin-hpc-governance".to_string(),
            workspace_id: "beagle-cluster-pilot".to_string(),
            session_id: "ws-cluster-workspace-habitat".to_string(),
            program_id: Some("beagle-physio-symbolic-exocortex".to_string()),
            campaign_id: Some("expedition-002-hrv-aware".to_string()),
            task_family: "analysis".to_string(),
            tool_id: "claude-code".to_string(),
            work_mode: "analysis".to_string(),
            selected_subagent_id: "experiments".to_string(),
            selected_role_tag: "experiment-loop".to_string(),
            selected_specialization: "Operator CPU loop".to_string(),
            retrieval_query_type: "general".to_string(),
            dense_backend: "voyage-4-large".to_string(),
            sparse_backend: "local-lexical".to_string(),
            compiler_profile_id: "b235-budget-analysis".to_string(),
            graphrag_query_mode: "global".to_string(),
            temporal_truth_view: "both".to_string(),
            selected_memory_tiers: vec!["semantic".to_string(), "episodic".to_string()],
            recipe_target: Some(ExecutionRecipeTarget {
                recipe_id: "beagle-darwin-hpc-governance.operator_cpu_loop".to_string(),
                recipe_kind: "operator_cpu_loop".to_string(),
                summary: "Canonical operator CPU batch loop with result resolution and state persistence.".to_string(),
                recovery_points: vec![
                    "session_before_loop".to_string(),
                    "control_before_loop".to_string(),
                    "submitted_job".to_string(),
                    "published_result".to_string(),
                    "session_after_loop".to_string(),
                ],
            }),
            experiment_target: Some(crate::ExecutionExperimentTarget {
                experiment_id: "expedition-002-hrv-aware".to_string(),
                campaign_id: "expedition-002-hrv-aware".to_string(),
                spec_doc: "docs/darwin/hpc/campaigns/expedition-002-hrv-aware.yaml".to_string(),
                results_doc: "docs/darwin/hpc/results/expedition-002-hrv-aware-results.md".to_string(),
                live_batch_id: "batch-42".to_string(),
            }),
            expected_outputs: vec!["published_result".to_string()],
            success_criteria: vec![PlanAcceptanceCriterion {
                criteria_version: "beagle-plan-acceptance-criteria-v1".to_string(),
                criterion_id: "analysis-success".to_string(),
                description: "bounded analysis loop completes".to_string(),
                success_signal: "published_result".to_string(),
                stop_condition: "operator stop".to_string(),
                operator_visibility_required: true,
            }],
            stop_conditions: vec!["operator stop".to_string()],
            context_packet_ref: "/api/darwin/workstreams/beagle-darwin-hpc-governance/context-packet".to_string(),
            program_context_packet_ref: Some("/api/darwin/programs/beagle-physio-symbolic-exocortex/context-packet".to_string()),
            workspace_subagent_route_path: "/api/darwin/workstreams/beagle-darwin-hpc-governance/workspace-subagent-route?tool_id=claude-code&work_mode=analysis".to_string(),
            workspace_subagent_handoff_path: "/api/darwin/workstreams/beagle-darwin-hpc-governance/workspace-subagent-handoff".to_string(),
            tool_launch_path: "/api/darwin/workstreams/beagle-darwin-hpc-governance/tool-dock/claude-code".to_string(),
            compiled_context_top_memory_ids: vec![
                "memory-1".to_string(),
                "memory-2".to_string(),
            ],
            compiled_context_preview: Some("analysis preview".to_string()),
            operator_execution_state: "operator-visible-bounded".to_string(),
            note: "analysis plan".to_string(),
        }
    }

    #[test]
    fn plan_execution_approve_and_start_records_receipt_with_same_identity() {
        let dir = temp_data_dir("approve-start");
        let cfg = test_config(&dir);
        seed_workspace_session(&dir, &cfg);
        let packet = packet();
        let plan = analysis_plan();

        let approval = approve_execution_plan(
            &dir,
            &cfg,
            "beagle-darwin-hpc-governance",
            packet.clone(),
            PlanApprovalRequest {
                execution_plan: &plan,
                approved_by: "beagle-operator",
                approval_note: "Approve bounded analysis execution.",
            },
        )
        .expect("approve execution plan");
        assert_eq!(approval.approval_state, "approved");

        let state = start_execution_plan(
            &dir,
            &cfg,
            "beagle-darwin-hpc-governance",
            packet.clone(),
            PlanExecutionStartRequest {
                plan_id: &plan.plan_id,
                started_by: "beagle-operator",
                start_note: "Run bounded analysis execution.",
            },
        )
        .expect("start execution plan");

        assert_eq!(state.workstream_id, "beagle-darwin-hpc-governance");
        assert_eq!(state.workspace_id, "beagle-cluster-pilot");
        assert_eq!(state.session_id, "ws-cluster-workspace-habitat");
        assert_eq!(state.current_state, "succeeded");
        assert_eq!(state.selected_subagent_id, "experiments");
        assert!(state.latest_receipt_id.is_some());

        let receipt = read_execution_receipt(&dir, "beagle-cluster-pilot")
            .expect("read receipt")
            .expect("receipt present");
        assert_eq!(receipt.final_state, "succeeded");
        assert!(receipt.handoff_updated);
        assert_eq!(
            receipt.handoff_ref.as_deref(),
            Some("/api/darwin/workstreams/beagle-darwin-hpc-governance/workspace-subagent-handoff")
        );

        let summary = execution_status_summary_for_packet(&dir, &packet.packet)
            .expect("summary")
            .expect("summary present");
        assert_eq!(summary.current_state, "succeeded");
        assert_eq!(summary.selected_subagent_id, "experiments");
        assert_eq!(summary.result_link_count, 11);
    }

    #[test]
    fn plan_execution_stop_transitions_approved_record_into_stopped_state() {
        let dir = temp_data_dir("stop");
        let cfg = test_config(&dir);
        seed_workspace_session(&dir, &cfg);
        let packet = packet();
        let plan = analysis_plan();

        approve_execution_plan(
            &dir,
            &cfg,
            "beagle-darwin-hpc-governance",
            packet.clone(),
            PlanApprovalRequest {
                execution_plan: &plan,
                approved_by: "beagle-operator",
                approval_note: "Approve bounded analysis execution.",
            },
        )
        .expect("approve execution plan");

        let state = stop_execution_plan(
            &dir,
            "beagle-darwin-hpc-governance",
            packet,
            PlanExecutionStopRequest {
                plan_id: &plan.plan_id,
                stopped_by: "beagle-operator",
                stop_reason: "Stop requested before operator loop launch.",
            },
        )
        .expect("stop execution plan");

        assert_eq!(state.current_state, "stopped");
        assert_eq!(
            state.stop_reason.as_deref(),
            Some("Stop requested before operator loop launch.")
        );
        assert!(state.latest_receipt_id.is_some());
    }

    #[test]
    fn review_inbox_approve_materializes_follow_on_plan_with_same_identity() {
        let dir = temp_data_dir("review-approve");
        let cfg = test_config(&dir);
        seed_workspace_session(&dir, &cfg);
        let packet = packet();
        let plan = analysis_plan();

        approve_execution_plan(
            &dir,
            &cfg,
            "beagle-darwin-hpc-governance",
            packet.clone(),
            PlanApprovalRequest {
                execution_plan: &plan,
                approved_by: "beagle-operator",
                approval_note: "Approve bounded analysis execution.",
            },
        )
        .expect("approve execution plan");

        start_execution_plan(
            &dir,
            &cfg,
            "beagle-darwin-hpc-governance",
            packet.clone(),
            PlanExecutionStartRequest {
                plan_id: &plan.plan_id,
                started_by: "beagle-operator",
                start_note: "Run bounded analysis execution.",
            },
        )
        .expect("start execution plan");

        let inbox_item = materialize_review_inbox_item(
            &dir,
            "beagle-darwin-hpc-governance",
            packet.clone(),
            ReviewInboxMaterializeRequest {
                created_by: "beagle-operator",
                create_note: "Materialize operator review item.",
            },
        )
        .expect("materialize review inbox");
        assert_eq!(inbox_item.workstream_id, "beagle-darwin-hpc-governance");
        assert_eq!(inbox_item.workspace_id, "beagle-cluster-pilot");
        assert_eq!(inbox_item.session_id, "ws-cluster-workspace-habitat");
        assert_eq!(inbox_item.inbox_state, "pending-review");

        let decision = decide_review_inbox_item(
            &dir,
            &cfg,
            "beagle-darwin-hpc-governance",
            packet.clone(),
            ReviewInboxDecisionRequest {
                inbox_item_id: inbox_item.inbox_item_id.clone(),
                decision_action: "approve".to_string(),
                decided_by: "beagle-operator".to_string(),
                decision_note: "Approve the same bounded next step.".to_string(),
                edit_patch: None,
            },
        )
        .expect("approve review inbox");
        assert_eq!(decision.decision_action, "approved");
        assert!(decision.follow_on_plan_materialized);

        let follow_on_plan = read_follow_on_plan(&dir, "beagle-cluster-pilot")
            .expect("read follow-on plan")
            .expect("follow-on plan present");
        assert_eq!(follow_on_plan.workstream_id, "beagle-darwin-hpc-governance");
        assert_eq!(follow_on_plan.workspace_id, "beagle-cluster-pilot");
        assert_eq!(follow_on_plan.session_id, "ws-cluster-workspace-habitat");
        assert_eq!(follow_on_plan.review_action, "approved");
        assert_eq!(follow_on_plan.follow_on_state, "dispatched");

        let summary = execution_status_summary_for_packet(&dir, &packet.packet)
            .expect("summary")
            .expect("summary present");
        assert!(!summary.review_requested);
        assert_eq!(summary.review_inbox_state.as_deref(), Some("approved"));
        assert_eq!(summary.latest_review_decision_action.as_deref(), Some("approved"));
        assert!(summary.follow_on_plan_available);
        assert!(summary.latest_follow_on_plan_id.is_some());
        assert_eq!(
            summary.approval_gating_decision_class.as_deref(),
            Some("auto-continue")
        );
        assert!(summary.approval_gating_dispatch_ready);
        assert!(summary.continuation_dispatched);
    }

    #[test]
    fn review_inbox_reject_preserves_identity_without_follow_on_plan() {
        let dir = temp_data_dir("review-reject");
        let cfg = test_config(&dir);
        seed_workspace_session(&dir, &cfg);
        let packet = packet();
        let plan = analysis_plan();

        approve_execution_plan(
            &dir,
            &cfg,
            "beagle-darwin-hpc-governance",
            packet.clone(),
            PlanApprovalRequest {
                execution_plan: &plan,
                approved_by: "beagle-operator",
                approval_note: "Approve bounded analysis execution.",
            },
        )
        .expect("approve execution plan");

        start_execution_plan(
            &dir,
            &cfg,
            "beagle-darwin-hpc-governance",
            packet.clone(),
            PlanExecutionStartRequest {
                plan_id: &plan.plan_id,
                started_by: "beagle-operator",
                start_note: "Run bounded analysis execution.",
            },
        )
        .expect("start execution plan");

        let inbox_item = materialize_review_inbox_item(
            &dir,
            "beagle-darwin-hpc-governance",
            packet.clone(),
            ReviewInboxMaterializeRequest {
                created_by: "beagle-operator",
                create_note: "Materialize operator review item.",
            },
        )
        .expect("materialize review inbox");

        let decision = decide_review_inbox_item(
            &dir,
            &cfg,
            "beagle-darwin-hpc-governance",
            packet.clone(),
            ReviewInboxDecisionRequest {
                inbox_item_id: inbox_item.inbox_item_id,
                decision_action: "reject".to_string(),
                decided_by: "beagle-operator".to_string(),
                decision_note: "Reject the next bounded cycle for now.".to_string(),
                edit_patch: None,
            },
        )
        .expect("reject review inbox");
        assert_eq!(decision.decision_action, "rejected");
        assert!(!decision.follow_on_plan_materialized);

        assert!(
            read_follow_on_plan(&dir, "beagle-cluster-pilot")
                .expect("read follow-on plan")
                .is_none()
        );

        let summary = execution_status_summary_for_packet(&dir, &packet.packet)
            .expect("summary")
            .expect("summary present");
        assert_eq!(summary.review_inbox_state.as_deref(), Some("rejected"));
        assert_eq!(summary.latest_review_decision_action.as_deref(), Some("rejected"));
        assert!(!summary.follow_on_plan_available);
        assert_eq!(
            summary.operator_followup_action.as_deref(),
            Some("review-and-plan-again")
        );
    }

    #[test]
    fn review_inbox_edit_materializes_follow_on_plan_with_patch() {
        let dir = temp_data_dir("review-edit");
        let cfg = test_config(&dir);
        seed_workspace_session(&dir, &cfg);
        let packet = packet();
        let plan = analysis_plan();

        approve_execution_plan(
            &dir,
            &cfg,
            "beagle-darwin-hpc-governance",
            packet.clone(),
            PlanApprovalRequest {
                execution_plan: &plan,
                approved_by: "beagle-operator",
                approval_note: "Approve bounded analysis execution.",
            },
        )
        .expect("approve execution plan");

        start_execution_plan(
            &dir,
            &cfg,
            "beagle-darwin-hpc-governance",
            packet.clone(),
            PlanExecutionStartRequest {
                plan_id: &plan.plan_id,
                started_by: "beagle-operator",
                start_note: "Run bounded analysis execution.",
            },
        )
        .expect("start execution plan");

        let inbox_item = materialize_review_inbox_item(
            &dir,
            "beagle-darwin-hpc-governance",
            packet.clone(),
            ReviewInboxMaterializeRequest {
                created_by: "beagle-operator",
                create_note: "Materialize operator review item.",
            },
        )
        .expect("materialize review inbox");

        let decision = decide_review_inbox_item(
            &dir,
            &cfg,
            "beagle-darwin-hpc-governance",
            packet.clone(),
            ReviewInboxDecisionRequest {
                inbox_item_id: inbox_item.inbox_item_id,
                decision_action: "edit".to_string(),
                decided_by: "beagle-operator".to_string(),
                decision_note: "Edit the next step into an implementation-focused follow-on.".to_string(),
                edit_patch: Some(ReviewDecisionEditPatch {
                    task_family: Some("implementation".to_string()),
                    selected_subagent_id: Some("core".to_string()),
                    retrieval_query_type: Some("code".to_string()),
                    compiler_profile_id: Some("b235-budget-implementation".to_string()),
                    graphrag_query_mode: Some("local".to_string()),
                    temporal_truth_view: Some("current".to_string()),
                    recipe_kind: Some("repo_native_dev_loop".to_string()),
                }),
            },
        )
        .expect("edit review inbox");
        assert_eq!(decision.decision_action, "edited");
        assert!(decision.follow_on_plan_materialized);
        assert!(decision.edited_fields.iter().any(|field| field == "task_family"));
        assert!(decision.edited_fields.iter().any(|field| field == "recipe_kind"));

        let follow_on_plan = read_follow_on_plan(&dir, "beagle-cluster-pilot")
            .expect("read follow-on plan")
            .expect("follow-on plan present");
        assert_eq!(follow_on_plan.review_action, "edited");
        assert_eq!(follow_on_plan.execution_plan.task_family, "implementation");
        assert_eq!(follow_on_plan.execution_plan.selected_subagent_id, "core");
        assert_eq!(follow_on_plan.execution_plan.retrieval_query_type, "code");
        assert_eq!(
            follow_on_plan.execution_plan.compiler_profile_id,
            "b235-budget-implementation"
        );
        assert_eq!(follow_on_plan.execution_plan.graphrag_query_mode, "local");
        assert_eq!(follow_on_plan.execution_plan.temporal_truth_view, "current");
        assert_eq!(follow_on_plan.follow_on_state, "review-required");
        assert_eq!(
            follow_on_plan
                .execution_plan
                .recipe_target
                .as_ref()
                .map(|target| target.recipe_kind.as_str()),
            Some("repo_native_dev_loop")
        );
    }

    #[test]
    fn autonomy_policy_calibration_materializes_shadow_bundle_on_same_identity() {
        let dir = temp_data_dir("autonomy-calibration");
        let cfg = test_config(&dir);
        seed_workspace_session(&dir, &cfg);
        let packet = packet();
        let plan = analysis_plan();

        approve_execution_plan(
            &dir,
            &cfg,
            "beagle-darwin-hpc-governance",
            packet.clone(),
            PlanApprovalRequest {
                execution_plan: &plan,
                approved_by: "beagle-operator",
                approval_note: "Approve bounded analysis execution.",
            },
        )
        .expect("approve execution plan");

        start_execution_plan(
            &dir,
            &cfg,
            "beagle-darwin-hpc-governance",
            packet.clone(),
            PlanExecutionStartRequest {
                plan_id: &plan.plan_id,
                started_by: "beagle-operator",
                start_note: "Run bounded analysis execution.",
            },
        )
        .expect("start execution plan");

        let inbox_item = materialize_review_inbox_item(
            &dir,
            "beagle-darwin-hpc-governance",
            packet.clone(),
            ReviewInboxMaterializeRequest {
                created_by: "beagle-operator",
                create_note: "Materialize operator review item.",
            },
        )
        .expect("materialize review inbox");

        decide_review_inbox_item(
            &dir,
            &cfg,
            "beagle-darwin-hpc-governance",
            packet.clone(),
            ReviewInboxDecisionRequest {
                inbox_item_id: inbox_item.inbox_item_id,
                decision_action: "approve".to_string(),
                decided_by: "beagle-operator".to_string(),
                decision_note: "Approve the same bounded next step.".to_string(),
                edit_patch: None,
            },
        )
        .expect("approve review inbox");

        let bundle = ensure_autonomy_policy_calibration(
            &dir,
            "beagle-darwin-hpc-governance",
            "beagle-cluster-pilot",
        )
        .expect("ensure autonomy calibration");

        assert_eq!(bundle.calibration_dataset.sample_count, 4);
        assert_eq!(
            bundle.policy_eval_report.policy_posture,
            "too-conservative"
        );
        assert_eq!(
            bundle.shadow_policy_comparison.improved_alignment_count,
            1
        );
        assert_eq!(
            bundle.updated_policy_recommendation.recommended_action,
            "stage-shadow-threshold-update"
        );
        assert_eq!(
            bundle.calibration_dataset.workstream_id,
            "beagle-darwin-hpc-governance"
        );
        assert_eq!(bundle.calibration_dataset.workspace_id, "beagle-cluster-pilot");
        assert_eq!(
            bundle.calibration_dataset.session_id,
            "ws-cluster-workspace-habitat"
        );

        let summary = execution_status_summary_for_packet(&dir, &packet.packet)
            .expect("summary")
            .expect("summary present");
        assert_eq!(
            summary.autonomy_policy_calibration_status.as_deref(),
            Some("shadow-evaluated")
        );
        assert!(summary.latest_autonomy_policy_eval_report_id.is_some());
        assert!(summary.latest_updated_policy_recommendation_id.is_some());

        let result_links = read_execution_result_links(&dir, "beagle-cluster-pilot")
            .expect("read result links")
            .expect("result links present");
        assert!(
            result_links
                .links
                .iter()
                .any(|link| link.link_kind == "autonomy-calibration-dataset")
        );
        assert!(
            result_links
                .links
                .iter()
                .any(|link| link.link_kind == "autonomy-policy-eval-report")
        );
        assert!(
            result_links
                .links
                .iter()
                .any(|link| link.link_kind == "escalation-thresholds")
        );
        assert!(
            result_links
                .links
                .iter()
                .any(|link| link.link_kind == "shadow-policy-comparison")
        );
        assert!(
            result_links
                .links
                .iter()
                .any(|link| link.link_kind == "updated-policy-recommendation")
        );
    }

    #[test]
    fn guarded_rollout_materializes_control_candidate_and_staged_canary() {
        let dir = temp_data_dir("guarded-rollout");
        let cfg = test_config(&dir);
        seed_workspace_session(&dir, &cfg);
        let packet = packet();
        let plan = analysis_plan();

        approve_execution_plan(
            &dir,
            &cfg,
            "beagle-darwin-hpc-governance",
            packet.clone(),
            PlanApprovalRequest {
                execution_plan: &plan,
                approved_by: "beagle-operator",
                approval_note: "Approve bounded analysis execution.",
            },
        )
        .expect("approve execution plan");

        start_execution_plan(
            &dir,
            &cfg,
            "beagle-darwin-hpc-governance",
            packet.clone(),
            PlanExecutionStartRequest {
                plan_id: &plan.plan_id,
                started_by: "beagle-operator",
                start_note: "Run bounded analysis execution.",
            },
        )
        .expect("start execution plan");

        let inbox_item = materialize_review_inbox_item(
            &dir,
            "beagle-darwin-hpc-governance",
            packet.clone(),
            ReviewInboxMaterializeRequest {
                created_by: "beagle-operator",
                create_note: "Materialize operator review item.",
            },
        )
        .expect("materialize review inbox");

        decide_review_inbox_item(
            &dir,
            &cfg,
            "beagle-darwin-hpc-governance",
            packet.clone(),
            ReviewInboxDecisionRequest {
                inbox_item_id: inbox_item.inbox_item_id,
                decision_action: "approve".to_string(),
                decided_by: "beagle-operator".to_string(),
                decision_note: "Approve the same bounded next step.".to_string(),
                edit_patch: None,
            },
        )
        .expect("approve review inbox");

        let bundle = ensure_guarded_policy_rollout(
            &dir,
            "beagle-darwin-hpc-governance",
            "beagle-cluster-pilot",
        )
        .expect("ensure guarded rollout");

        assert_eq!(
            bundle.autonomy_policy_current.policy_role,
            "current-control"
        );
        assert_eq!(
            bundle.autonomy_policy_candidate.policy_role,
            "candidate-shadow"
        );
        assert_eq!(bundle.rollout_metrics.rollout_stage, "shadow-compared");
        assert_eq!(
            bundle.rollout_decision.recommended_action,
            "stage-guarded-canary-for-implementation"
        );
        assert!(bundle.rollout_decision.guarded_enablement_permitted);
        assert!(!bundle.rollout_decision.guarded_enablement_live);
        assert!(!bundle.rollout_decision.global_policy_update_permitted);
        assert_eq!(
            bundle.rollout_decision.staged_guarded_task_families,
            vec!["implementation".to_string()]
        );

        let summary = execution_status_summary_for_packet(&dir, &packet.packet)
            .expect("summary")
            .expect("summary present");
        assert_eq!(
            summary.autonomy_policy_rollout_status.as_deref(),
            Some("implementation-canary-staged")
        );
        assert!(summary.latest_autonomy_policy_current_id.is_some());
        assert!(summary.latest_autonomy_policy_candidate_id.is_some());
        assert!(summary.latest_rollout_metrics_id.is_some());
        assert!(summary.latest_guarded_rollout_decision_id.is_some());

        let result_links = read_execution_result_links(&dir, "beagle-cluster-pilot")
            .expect("read result links")
            .expect("result links present");
        assert!(
            result_links
                .links
                .iter()
                .any(|link| link.link_kind == "autonomy-policy-current")
        );
        assert!(
            result_links
                .links
                .iter()
                .any(|link| link.link_kind == "autonomy-policy-candidate")
        );
        assert!(
            result_links
                .links
                .iter()
                .any(|link| link.link_kind == "rollout-metrics")
        );
        assert!(
            result_links
                .links
                .iter()
                .any(|link| link.link_kind == "guarded-rollout-decision")
        );
    }

    #[test]
    fn implementation_canary_activation_routes_only_implementation_to_canary() {
        let dir = temp_data_dir("implementation-canary");
        let cfg = test_config(&dir);
        seed_workspace_session(&dir, &cfg);
        let packet = packet();
        let plan = analysis_plan();

        approve_execution_plan(
            &dir,
            &cfg,
            "beagle-darwin-hpc-governance",
            packet.clone(),
            PlanApprovalRequest {
                execution_plan: &plan,
                approved_by: "beagle-operator",
                approval_note: "Approve bounded analysis execution.",
            },
        )
        .expect("approve execution plan");

        start_execution_plan(
            &dir,
            &cfg,
            "beagle-darwin-hpc-governance",
            packet.clone(),
            PlanExecutionStartRequest {
                plan_id: &plan.plan_id,
                started_by: "beagle-operator",
                start_note: "Run bounded analysis execution.",
            },
        )
        .expect("start execution plan");

        let inbox_item = materialize_review_inbox_item(
            &dir,
            "beagle-darwin-hpc-governance",
            packet.clone(),
            ReviewInboxMaterializeRequest {
                created_by: "beagle-operator",
                create_note: "Materialize operator review item.",
            },
        )
        .expect("materialize review inbox");

        decide_review_inbox_item(
            &dir,
            &cfg,
            "beagle-darwin-hpc-governance",
            packet.clone(),
            ReviewInboxDecisionRequest {
                inbox_item_id: inbox_item.inbox_item_id,
                decision_action: "edit".to_string(),
                decided_by: "beagle-operator".to_string(),
                decision_note: "Edit the next step into an implementation-focused follow-on.".to_string(),
                edit_patch: Some(ReviewDecisionEditPatch {
                    task_family: Some("implementation".to_string()),
                    selected_subagent_id: Some("core".to_string()),
                    retrieval_query_type: Some("code".to_string()),
                    compiler_profile_id: Some("b235-budget-implementation".to_string()),
                    graphrag_query_mode: Some("local".to_string()),
                    temporal_truth_view: Some("current".to_string()),
                    recipe_kind: Some("repo_native_dev_loop".to_string()),
                }),
            },
        )
        .expect("edit review inbox");

        let canary_bundle = ensure_implementation_canary_autonomy(
            &dir,
            "beagle-darwin-hpc-governance",
            "beagle-cluster-pilot",
        )
        .expect("ensure implementation canary");
        assert_eq!(
            canary_bundle
                .autonomy_policy_canary
                .policy_role
                .as_deref(),
            Some("implementation-canary-live")
        );
        assert_eq!(
            canary_bundle.canary_rollout_metrics.canary_stage,
            "implementation-family-live-canary"
        );
        assert!(!canary_bundle.canary_rollback_decision.rollback_required);

        let record = read_required_execution_record(&dir, "beagle-cluster-pilot")
            .expect("read execution record");
        let follow_on_plan = record
            .follow_on_plan
            .clone()
            .expect("follow-on plan present");
        let review_inbox_item = record
            .review_inbox_item
            .clone()
            .expect("review inbox item present");
        let review_decision = record
            .review_decision
            .clone()
            .expect("review decision present");
        let (autonomy_policy, _risk_evaluation, approval_gate) = evaluate_follow_on_plan_gate(
            &record,
            "beagle-darwin-hpc-governance",
            &review_inbox_item,
            &review_decision,
            &follow_on_plan,
        )
        .expect("evaluate follow-on plan gate");

        assert_eq!(
            autonomy_policy.policy_role.as_deref(),
            Some("implementation-canary-live")
        );
        assert!(autonomy_policy.guarded_enablement_live);
        assert_eq!(approval_gate.decision_class, "auto-continue");
        assert_eq!(
            approval_gate.matched_policy_rule,
            "guarded-implementation-canary-lane"
        );

        let summary = execution_status_summary_for_packet(&dir, &packet.packet)
            .expect("summary")
            .expect("summary present");
        assert_eq!(
            summary.autonomy_policy_rollout_status.as_deref(),
            Some("implementation-canary-live")
        );

        let result_links = read_execution_result_links(&dir, "beagle-cluster-pilot")
            .expect("read result links")
            .expect("result links present");
        assert!(
            result_links
                .links
                .iter()
                .any(|link| link.link_kind == "autonomy-policy-control")
        );
        assert!(
            result_links
                .links
                .iter()
                .any(|link| link.link_kind == "autonomy-policy-canary")
        );
        assert!(
            result_links
                .links
                .iter()
                .any(|link| link.link_kind == "canary-rollout-metrics")
        );
        assert!(
            result_links
                .links
                .iter()
                .any(|link| link.link_kind == "canary-rollback-decision")
        );
    }

    #[test]
    fn analysis_shadow_calibration_keeps_analysis_on_control_and_retains_canary() {
        let dir = temp_data_dir("analysis-shadow");
        let cfg = test_config(&dir);
        seed_workspace_session(&dir, &cfg);
        let packet = packet();
        let plan = analysis_plan();

        approve_execution_plan(
            &dir,
            &cfg,
            "beagle-darwin-hpc-governance",
            packet.clone(),
            PlanApprovalRequest {
                execution_plan: &plan,
                approved_by: "beagle-operator",
                approval_note: "Approve bounded analysis execution.",
            },
        )
        .expect("approve execution plan");

        start_execution_plan(
            &dir,
            &cfg,
            "beagle-darwin-hpc-governance",
            packet.clone(),
            PlanExecutionStartRequest {
                plan_id: &plan.plan_id,
                started_by: "beagle-operator",
                start_note: "Run bounded analysis execution.",
            },
        )
        .expect("start execution plan");

        let inbox_item = materialize_review_inbox_item(
            &dir,
            "beagle-darwin-hpc-governance",
            packet.clone(),
            ReviewInboxMaterializeRequest {
                created_by: "beagle-operator",
                create_note: "Materialize operator review item.",
            },
        )
        .expect("materialize review inbox");

        decide_review_inbox_item(
            &dir,
            &cfg,
            "beagle-darwin-hpc-governance",
            packet.clone(),
            ReviewInboxDecisionRequest {
                inbox_item_id: inbox_item.inbox_item_id.clone(),
                decision_action: "edit".to_string(),
                decided_by: "beagle-operator".to_string(),
                decision_note: "Edit the next step into an implementation-focused follow-on.".to_string(),
                edit_patch: Some(ReviewDecisionEditPatch {
                    task_family: Some("implementation".to_string()),
                    selected_subagent_id: Some("core".to_string()),
                    retrieval_query_type: Some("code".to_string()),
                    compiler_profile_id: Some("b235-budget-implementation".to_string()),
                    graphrag_query_mode: Some("local".to_string()),
                    temporal_truth_view: Some("current".to_string()),
                    recipe_kind: Some("repo_native_dev_loop".to_string()),
                }),
            },
        )
        .expect("edit review inbox");

        ensure_implementation_canary_autonomy(
            &dir,
            "beagle-darwin-hpc-governance",
            "beagle-cluster-pilot",
        )
        .expect("ensure implementation canary");

        let analysis_bundle = ensure_analysis_shadow_calibration(
            &dir,
            "beagle-darwin-hpc-governance",
            "beagle-cluster-pilot",
        )
        .expect("ensure analysis shadow calibration");
        assert_eq!(
            analysis_bundle.analysis_rollout_decision.decision_output,
            "keep-shadow"
        );
        assert!(analysis_bundle.analysis_rollout_metrics.implementation_canary_retained);
        assert!(analysis_bundle.analysis_rollout_metrics.manuscript_control_retained);

        let record = read_required_execution_record(&dir, "beagle-cluster-pilot")
            .expect("read execution record");
        let review_inbox_item = record
            .review_inbox_item
            .clone()
            .expect("review inbox item present");
        let replan_suggestion = record
            .replan_suggestion
            .clone()
            .expect("replan suggestion present");
        let analysis_follow_on = build_follow_on_plan(
            &record.execution_plan,
            &review_inbox_item,
            &replan_suggestion,
            "approved",
            "beagle-operator",
            None,
        );

        let selected_policy = select_effective_autonomy_policy(&record, &analysis_follow_on);
        assert_eq!(selected_policy.policy_role.as_deref(), Some("control-live"));
        assert!(!selected_policy.guarded_enablement_live);

        let summary = execution_status_summary_for_packet(&dir, &packet.packet)
            .expect("summary")
            .expect("summary present");
        assert_eq!(
            summary.autonomy_policy_rollout_status.as_deref(),
            Some("implementation-canary-live")
        );
        assert_eq!(
            summary.autonomy_policy_calibration_status.as_deref(),
            Some("analysis-shadow-evaluated")
        );

        let result_links = read_execution_result_links(&dir, "beagle-cluster-pilot")
            .expect("read result links")
            .expect("result links present");
        assert!(
            result_links
                .links
                .iter()
                .any(|link| link.link_kind == "autonomy-policy-analysis-candidate")
        );
        assert!(
            result_links
                .links
                .iter()
                .any(|link| link.link_kind == "analysis-shadow-comparison")
        );
        assert!(
            result_links
                .links
                .iter()
                .any(|link| link.link_kind == "analysis-rollout-metrics")
        );
        assert!(
            result_links
                .links
                .iter()
                .any(|link| link.link_kind == "analysis-rollout-decision")
        );
    }

    #[test]
    fn analysis_shadow_soak_keeps_analysis_shadow_only_until_promotion_threshold() {
        let dir = temp_data_dir("analysis-shadow-soak");
        let cfg = test_config(&dir);
        seed_workspace_session(&dir, &cfg);
        let packet = packet();
        let plan = analysis_plan();

        approve_execution_plan(
            &dir,
            &cfg,
            "beagle-darwin-hpc-governance",
            packet.clone(),
            PlanApprovalRequest {
                execution_plan: &plan,
                approved_by: "beagle-operator",
                approval_note: "Approve bounded analysis execution.",
            },
        )
        .expect("approve execution plan");

        start_execution_plan(
            &dir,
            &cfg,
            "beagle-darwin-hpc-governance",
            packet.clone(),
            PlanExecutionStartRequest {
                plan_id: &plan.plan_id,
                started_by: "beagle-operator",
                start_note: "Run bounded analysis execution.",
            },
        )
        .expect("start execution plan");

        let inbox_item = materialize_review_inbox_item(
            &dir,
            "beagle-darwin-hpc-governance",
            packet.clone(),
            ReviewInboxMaterializeRequest {
                created_by: "beagle-operator",
                create_note: "Materialize operator review item.",
            },
        )
        .expect("materialize review inbox");

        decide_review_inbox_item(
            &dir,
            &cfg,
            "beagle-darwin-hpc-governance",
            packet.clone(),
            ReviewInboxDecisionRequest {
                inbox_item_id: inbox_item.inbox_item_id.clone(),
                decision_action: "edit".to_string(),
                decided_by: "beagle-operator".to_string(),
                decision_note: "Edit the next step into an implementation-focused follow-on.".to_string(),
                edit_patch: Some(ReviewDecisionEditPatch {
                    task_family: Some("implementation".to_string()),
                    selected_subagent_id: Some("core".to_string()),
                    retrieval_query_type: Some("code".to_string()),
                    compiler_profile_id: Some("b235-budget-implementation".to_string()),
                    graphrag_query_mode: Some("local".to_string()),
                    temporal_truth_view: Some("current".to_string()),
                    recipe_kind: Some("repo_native_dev_loop".to_string()),
                }),
            },
        )
        .expect("edit review inbox");

        let soak_bundle = ensure_analysis_shadow_soak(
            &dir,
            "beagle-darwin-hpc-governance",
            "beagle-cluster-pilot",
        )
        .expect("ensure analysis shadow soak");
        assert_eq!(
            soak_bundle.analysis_promotion_gate.promotion_gate_decision,
            "keep-shadow"
        );
        assert!(
            soak_bundle.analysis_shadow_history.shadow_sample_count >= 1
        );
        assert_eq!(
            soak_bundle.analysis_shadow_history.shadow_sample_count,
            soak_bundle.analysis_shadow_history.history.len()
        );
        assert!(soak_bundle.analysis_shadow_history.implementation_canary_retained);
        assert!(soak_bundle.analysis_shadow_history.manuscript_control_retained);

        let record = read_required_execution_record(&dir, "beagle-cluster-pilot")
            .expect("read execution record");
        let review_inbox_item = record
            .review_inbox_item
            .clone()
            .expect("review inbox item present");
        let replan_suggestion = record
            .replan_suggestion
            .clone()
            .expect("replan suggestion present");
        let analysis_follow_on = build_follow_on_plan(
            &record.execution_plan,
            &review_inbox_item,
            &replan_suggestion,
            "approved",
            "beagle-operator",
            None,
        );

        let selected_policy = select_effective_autonomy_policy(&record, &analysis_follow_on);
        assert_eq!(selected_policy.policy_role.as_deref(), Some("control-live"));
        assert!(!selected_policy.guarded_enablement_live);

        let summary = execution_status_summary_for_packet(&dir, &packet.packet)
            .expect("summary")
            .expect("summary present");
        assert_eq!(
            summary.autonomy_policy_rollout_status.as_deref(),
            Some("implementation-canary-live")
        );
        assert_eq!(
            summary.autonomy_policy_calibration_status.as_deref(),
            Some("analysis-shadow-soaked")
        );

        let result_links = read_execution_result_links(&dir, "beagle-cluster-pilot")
            .expect("read result links")
            .expect("result links present");
        assert!(
            result_links
                .links
                .iter()
                .any(|link| link.link_kind == "analysis-shadow-history")
        );
        assert!(
            result_links
                .links
                .iter()
                .any(|link| link.link_kind == "analysis-soak-metrics")
        );
        assert!(
            result_links
                .links
                .iter()
                .any(|link| link.link_kind == "analysis-promotion-gate")
        );
    }

    #[test]
    fn analysis_sample_accumulation_rechecks_gate_without_moving_analysis_live() {
        let dir = temp_data_dir("analysis-sample-accumulation");
        let cfg = test_config(&dir);
        seed_workspace_session(&dir, &cfg);
        let packet = packet();
        let plan = analysis_plan();

        approve_execution_plan(
            &dir,
            &cfg,
            "beagle-darwin-hpc-governance",
            packet.clone(),
            PlanApprovalRequest {
                execution_plan: &plan,
                approved_by: "beagle-operator",
                approval_note: "Approve bounded analysis execution.",
            },
        )
        .expect("approve execution plan");

        start_execution_plan(
            &dir,
            &cfg,
            "beagle-darwin-hpc-governance",
            packet.clone(),
            PlanExecutionStartRequest {
                plan_id: &plan.plan_id,
                started_by: "beagle-operator",
                start_note: "Run bounded analysis execution.",
            },
        )
        .expect("start execution plan");

        let inbox_item = materialize_review_inbox_item(
            &dir,
            "beagle-darwin-hpc-governance",
            packet.clone(),
            ReviewInboxMaterializeRequest {
                created_by: "beagle-operator",
                create_note: "Materialize operator review item.",
            },
        )
        .expect("materialize review inbox");

        decide_review_inbox_item(
            &dir,
            &cfg,
            "beagle-darwin-hpc-governance",
            packet.clone(),
            ReviewInboxDecisionRequest {
                inbox_item_id: inbox_item.inbox_item_id.clone(),
                decision_action: "edit".to_string(),
                decided_by: "beagle-operator".to_string(),
                decision_note: "Edit the next step into an implementation-focused follow-on.".to_string(),
                edit_patch: Some(ReviewDecisionEditPatch {
                    task_family: Some("implementation".to_string()),
                    selected_subagent_id: Some("core".to_string()),
                    retrieval_query_type: Some("code".to_string()),
                    compiler_profile_id: Some("b235-budget-implementation".to_string()),
                    graphrag_query_mode: Some("local".to_string()),
                    temporal_truth_view: Some("current".to_string()),
                    recipe_kind: Some("repo_native_dev_loop".to_string()),
                }),
            },
        )
        .expect("edit review inbox");

        let accumulation_bundle = ensure_analysis_sample_accumulation(
            &dir,
            "beagle-darwin-hpc-governance",
            "beagle-cluster-pilot",
        )
        .expect("ensure analysis sample accumulation");
        assert!(matches!(
            accumulation_bundle
                .analysis_promotion_gate
                .promotion_gate_decision
                .as_str(),
            "keep-shadow" | "stage-analysis-canary"
        ));
        assert!(
            accumulation_bundle
                .analysis_shadow_history
                .prior_shadow_sample_count
                >= 1
        );
        assert!(
            accumulation_bundle
                .analysis_shadow_history
                .additional_shadow_sample_count
                >= 1
        );
        assert!(
            accumulation_bundle.analysis_shadow_history.shadow_sample_count
                > accumulation_bundle
                    .analysis_shadow_history
                    .prior_shadow_sample_count
        );

        let record = read_required_execution_record(&dir, "beagle-cluster-pilot")
            .expect("read execution record");
        let review_inbox_item = record
            .review_inbox_item
            .clone()
            .expect("review inbox item present");
        let replan_suggestion = record
            .replan_suggestion
            .clone()
            .expect("replan suggestion present");
        let analysis_follow_on = build_follow_on_plan(
            &record.execution_plan,
            &review_inbox_item,
            &replan_suggestion,
            "approved",
            "beagle-operator",
            None,
        );

        let selected_policy = select_effective_autonomy_policy(&record, &analysis_follow_on);
        assert_eq!(selected_policy.policy_role.as_deref(), Some("control-live"));
        assert!(!selected_policy.guarded_enablement_live);

        let summary = execution_status_summary_for_packet(&dir, &packet.packet)
            .expect("summary")
            .expect("summary present");
        assert_eq!(
            summary.autonomy_policy_rollout_status.as_deref(),
            Some("implementation-canary-live")
        );
        assert_eq!(
            summary.autonomy_policy_calibration_status.as_deref(),
            Some("analysis-shadow-rechecked")
        );

        let result_links = read_execution_result_links(&dir, "beagle-cluster-pilot")
            .expect("read result links")
            .expect("result links present");
        assert!(
            result_links
                .links
                .iter()
                .any(|link| link.link_kind == "analysis-sample-accumulation")
        );
        assert!(
            result_links
                .links
                .iter()
                .any(|link| link.link_kind == "analysis-sample-accumulation-metrics")
        );
        assert!(
            result_links
                .links
                .iter()
                .any(|link| link.link_kind == "analysis-promotion-gate-recheck")
        );
    }

    #[test]
    fn analysis_canary_activation_promotes_analysis_without_moving_manuscript() {
        let dir = temp_data_dir("analysis-canary-activation");
        let cfg = test_config(&dir);
        seed_workspace_session(&dir, &cfg);
        let packet = packet();
        let plan = analysis_plan();

        approve_execution_plan(
            &dir,
            &cfg,
            "beagle-darwin-hpc-governance",
            packet.clone(),
            PlanApprovalRequest {
                execution_plan: &plan,
                approved_by: "beagle-operator",
                approval_note: "Approve bounded analysis execution.",
            },
        )
        .expect("approve execution plan");

        start_execution_plan(
            &dir,
            &cfg,
            "beagle-darwin-hpc-governance",
            packet.clone(),
            PlanExecutionStartRequest {
                plan_id: &plan.plan_id,
                started_by: "beagle-operator",
                start_note: "Run bounded analysis execution.",
            },
        )
        .expect("start execution plan");

        let inbox_item = materialize_review_inbox_item(
            &dir,
            "beagle-darwin-hpc-governance",
            packet.clone(),
            ReviewInboxMaterializeRequest {
                created_by: "beagle-operator",
                create_note: "Materialize operator review item.",
            },
        )
        .expect("materialize review inbox");

        decide_review_inbox_item(
            &dir,
            &cfg,
            "beagle-darwin-hpc-governance",
            packet.clone(),
            ReviewInboxDecisionRequest {
                inbox_item_id: inbox_item.inbox_item_id.clone(),
                decision_action: "edit".to_string(),
                decided_by: "beagle-operator".to_string(),
                decision_note: "Edit the next step into an implementation-focused follow-on.".to_string(),
                edit_patch: Some(ReviewDecisionEditPatch {
                    task_family: Some("implementation".to_string()),
                    selected_subagent_id: Some("core".to_string()),
                    retrieval_query_type: Some("code".to_string()),
                    compiler_profile_id: Some("b235-budget-implementation".to_string()),
                    graphrag_query_mode: Some("local".to_string()),
                    temporal_truth_view: Some("current".to_string()),
                    recipe_kind: Some("repo_native_dev_loop".to_string()),
                }),
            },
        )
        .expect("edit review inbox");

        let analysis_bundle = Box::new(ensure_analysis_shadow_calibration(
            &dir,
            "beagle-darwin-hpc-governance",
            "beagle-cluster-pilot",
        )
        .expect("ensure analysis shadow calibration"));
        let mut record = Box::new(
            read_required_execution_record(&dir, "beagle-cluster-pilot")
                .expect("read execution record"),
        );
        if let Some(dataset) = record.autonomy_calibration_dataset.as_mut() {
            for sample in dataset
                .samples
                .iter_mut()
                .filter(|sample| sample.task_family == "analysis")
            {
                sample.operator_alignment_observed = Some(true);
                sample.execution_alignment_observed = Some(true);
                sample.continued_successfully = Some(true);
            }
        }
        let calibration_bundle = autonomy_policy_calibration_bundle_from_record(&record)
            .expect("autonomy calibration bundle present");
        let initial_soak = Box::new(build_analysis_shadow_soak_bundle(
            &calibration_bundle,
            &analysis_bundle,
            None,
        ));
        let seeded_accumulation = Box::new(build_analysis_sample_accumulation_bundle(
            &calibration_bundle,
            &analysis_bundle,
            &initial_soak.analysis_shadow_history,
        ));
        let staged_shadow_state = Box::new(build_analysis_sample_accumulation_bundle(
            &calibration_bundle,
            &analysis_bundle,
            &seeded_accumulation.analysis_shadow_history,
        ));
        let final_accumulation = Box::new(build_analysis_sample_accumulation_bundle(
            &calibration_bundle,
            &analysis_bundle,
            &staged_shadow_state.analysis_shadow_history,
        ));
        assert_eq!(
            staged_shadow_state.analysis_shadow_history.shadow_sample_count,
            3
        );
        assert_eq!(
            final_accumulation.analysis_promotion_gate.promotion_gate_decision,
            "stage-analysis-canary"
        );
        assert!(
            final_accumulation
                .analysis_promotion_gate
                .promotion_criteria_met
        );
        persist_analysis_shadow_soak(
            &mut record,
            "beagle-darwin-hpc-governance",
            &AnalysisShadowSoakBundle {
                analysis_shadow_history: staged_shadow_state.analysis_shadow_history.clone(),
                analysis_soak_metrics: staged_shadow_state.analysis_soak_metrics.clone(),
                analysis_promotion_gate: staged_shadow_state.analysis_promotion_gate.clone(),
            },
        );
        persist_analysis_sample_accumulation(
            &mut record,
            "beagle-darwin-hpc-governance",
            &final_accumulation,
        );
        write_execution_record(&dir, "beagle-cluster-pilot", &record)
            .expect("persist staged analysis accumulation");

        let analysis_canary_bundle = Box::new(ensure_analysis_canary_activation(
            &dir,
            "beagle-darwin-hpc-governance",
            "beagle-cluster-pilot",
        )
        .expect("ensure analysis canary activation"));
        assert!(
            analysis_canary_bundle
                .analysis_canary_metrics
                .analysis_canary_live
        );
        assert!(
            analysis_canary_bundle
                .analysis_canary_metrics
                .implementation_canary_retained
        );
        assert!(
            !analysis_canary_bundle
                .analysis_canary_rollback_decision
                .rollback_required
        );

        let record = Box::new(
            read_required_execution_record(&dir, "beagle-cluster-pilot")
                .expect("read execution record"),
        );
        let review_inbox_item = record
            .review_inbox_item
            .clone()
            .expect("review inbox item present");
        let review_decision = record
            .review_decision
            .clone()
            .expect("review decision present");
        let replan_suggestion = record
            .replan_suggestion
            .clone()
            .expect("replan suggestion present");
        let analysis_follow_on = build_follow_on_plan(
            &record.execution_plan,
            &review_inbox_item,
            &replan_suggestion,
            "approved",
            "beagle-operator",
            None,
        );
        let implementation_follow_on = record
            .follow_on_plan
            .clone()
            .expect("implementation follow-on present");

        let selected_analysis_policy =
            select_effective_autonomy_policy(&record, &analysis_follow_on);
        let selected_implementation_policy =
            select_effective_autonomy_policy(&record, &implementation_follow_on);

        assert_eq!(
            selected_analysis_policy.policy_role.as_deref(),
            Some("analysis-canary-live")
        );
        assert!(selected_analysis_policy.guarded_enablement_live);
        assert_eq!(
            selected_implementation_policy.policy_role.as_deref(),
            Some("implementation-canary-live")
        );

        let (autonomy_policy, _risk_evaluation, approval_gate) = evaluate_follow_on_plan_gate(
            &record,
            "beagle-darwin-hpc-governance",
            &review_inbox_item,
            &review_decision,
            &analysis_follow_on,
        )
        .expect("evaluate analysis canary gate");
        assert_eq!(
            autonomy_policy.policy_role.as_deref(),
            Some("analysis-canary-live")
        );
        assert_eq!(
            approval_gate.matched_policy_rule,
            "guarded-analysis-canary-lane"
        );

        let summary = execution_status_summary_for_packet(&dir, &packet.packet)
            .expect("summary")
            .expect("summary present");
        assert_eq!(
            summary.autonomy_policy_rollout_status.as_deref(),
            Some("implementation-and-analysis-canary-live")
        );

        let result_links = read_execution_result_links(&dir, "beagle-cluster-pilot")
            .expect("read result links")
            .expect("result links present");
        assert!(
            result_links
                .links
                .iter()
                .any(|link| link.link_kind == "autonomy-policy-analysis-control")
        );
        assert!(
            result_links
                .links
                .iter()
                .any(|link| link.link_kind == "autonomy-policy-implementation-canary")
        );
        assert!(
            result_links
                .links
                .iter()
                .any(|link| link.link_kind == "autonomy-policy-analysis-canary")
        );
        assert!(
            result_links
                .links
                .iter()
                .any(|link| link.link_kind == "analysis-canary-metrics")
        );
        assert!(
            result_links
                .links
                .iter()
                .any(|link| link.link_kind == "analysis-canary-rollback-decision")
        );
    }

    #[test]
    fn manuscript_shadow_calibration_keeps_manuscript_on_control_while_retaining_live_canaries() {
        std::thread::Builder::new()
            .name("manuscript-shadow-calibration-test".to_string())
            .stack_size(32 * 1024 * 1024)
            .spawn(|| {
                let dir = temp_data_dir("manuscript-shadow-calibration");
                let cfg = test_config(&dir);
                seed_workspace_session(&dir, &cfg);
                let packet = packet();
                let plan = analysis_plan();

                approve_execution_plan(
                    &dir,
                    &cfg,
                    "beagle-darwin-hpc-governance",
                    packet.clone(),
                    PlanApprovalRequest {
                        execution_plan: &plan,
                        approved_by: "beagle-operator",
                        approval_note: "Approve bounded analysis execution.",
                    },
                )
                .expect("approve execution plan");

                start_execution_plan(
                    &dir,
                    &cfg,
                    "beagle-darwin-hpc-governance",
                    packet.clone(),
                    PlanExecutionStartRequest {
                        plan_id: &plan.plan_id,
                        started_by: "beagle-operator",
                        start_note: "Run bounded analysis execution.",
                    },
                )
                .expect("start execution plan");

                let inbox_item = materialize_review_inbox_item(
                    &dir,
                    "beagle-darwin-hpc-governance",
                    packet.clone(),
                    ReviewInboxMaterializeRequest {
                        created_by: "beagle-operator",
                        create_note: "Materialize operator review item.",
                    },
                )
                .expect("materialize review inbox");

                decide_review_inbox_item(
                    &dir,
                    &cfg,
                    "beagle-darwin-hpc-governance",
                    packet.clone(),
                    ReviewInboxDecisionRequest {
                        inbox_item_id: inbox_item.inbox_item_id.clone(),
                        decision_action: "edit".to_string(),
                        decided_by: "beagle-operator".to_string(),
                        decision_note:
                            "Edit the next step into an implementation-focused follow-on."
                                .to_string(),
                        edit_patch: Some(ReviewDecisionEditPatch {
                            task_family: Some("implementation".to_string()),
                            selected_subagent_id: Some("core".to_string()),
                            retrieval_query_type: Some("code".to_string()),
                            compiler_profile_id: Some("b235-budget-implementation".to_string()),
                            graphrag_query_mode: Some("local".to_string()),
                            temporal_truth_view: Some("current".to_string()),
                            recipe_kind: Some("repo_native_dev_loop".to_string()),
                        }),
                    },
                )
                .expect("edit review inbox");

                let analysis_bundle = ensure_analysis_shadow_calibration(
                    &dir,
                    "beagle-darwin-hpc-governance",
                    "beagle-cluster-pilot",
                )
                .expect("ensure analysis shadow calibration");
                let mut record = read_required_execution_record(&dir, "beagle-cluster-pilot")
                    .expect("read execution record");
                if let Some(dataset) = record.autonomy_calibration_dataset.as_mut() {
                    for sample in dataset
                        .samples
                        .iter_mut()
                        .filter(|sample| sample.task_family == "analysis")
                    {
                        sample.operator_alignment_observed = Some(true);
                        sample.execution_alignment_observed = Some(true);
                        sample.continued_successfully = Some(true);
                    }
                }
                let calibration_bundle = autonomy_policy_calibration_bundle_from_record(&record)
                    .expect("autonomy calibration bundle present");
                let initial_soak =
                    build_analysis_shadow_soak_bundle(&calibration_bundle, &analysis_bundle, None);
                let seeded_accumulation = build_analysis_sample_accumulation_bundle(
                    &calibration_bundle,
                    &analysis_bundle,
                    &initial_soak.analysis_shadow_history,
                );
                let staged_shadow_state = build_analysis_sample_accumulation_bundle(
                    &calibration_bundle,
                    &analysis_bundle,
                    &seeded_accumulation.analysis_shadow_history,
                );
                let final_accumulation = build_analysis_sample_accumulation_bundle(
                    &calibration_bundle,
                    &analysis_bundle,
                    &staged_shadow_state.analysis_shadow_history,
                );
                persist_analysis_shadow_soak(
                    &mut record,
                    "beagle-darwin-hpc-governance",
                    &AnalysisShadowSoakBundle {
                        analysis_shadow_history: staged_shadow_state.analysis_shadow_history.clone(),
                        analysis_soak_metrics: staged_shadow_state.analysis_soak_metrics.clone(),
                        analysis_promotion_gate: staged_shadow_state
                            .analysis_promotion_gate
                            .clone(),
                    },
                );
                persist_analysis_sample_accumulation(
                    &mut record,
                    "beagle-darwin-hpc-governance",
                    &final_accumulation,
                );
                write_execution_record(&dir, "beagle-cluster-pilot", &record)
                    .expect("persist staged analysis accumulation");

                ensure_analysis_canary_activation(
                    &dir,
                    "beagle-darwin-hpc-governance",
                    "beagle-cluster-pilot",
                )
                .expect("ensure analysis canary activation");

                let manuscript_bundle = ensure_manuscript_shadow_calibration(
                    &dir,
                    "beagle-darwin-hpc-governance",
                    "beagle-cluster-pilot",
                )
                .expect("ensure manuscript shadow calibration");
                assert_eq!(
                    manuscript_bundle
                        .manuscript_rollout_decision
                        .decision_output,
                    "keep-shadow"
                );
                assert!(
                    manuscript_bundle
                        .manuscript_rollout_metrics
                        .implementation_canary_retained
                );
                assert!(
                    manuscript_bundle
                        .manuscript_rollout_metrics
                        .analysis_canary_retained
                );

                let record = read_required_execution_record(&dir, "beagle-cluster-pilot")
                    .expect("read execution record");
                let review_inbox_item = record
                    .review_inbox_item
                    .clone()
                    .expect("review inbox item present");
                let review_decision = record
                    .review_decision
                    .clone()
                    .expect("review decision present");
                let replan_suggestion = record
                    .replan_suggestion
                    .clone()
                    .expect("replan suggestion present");
                let manuscript_follow_on = build_follow_on_plan(
                    &record.execution_plan,
                    &review_inbox_item,
                    &replan_suggestion,
                    "edited",
                    "beagle-operator",
                    Some(&ReviewDecisionEditPatch {
                        task_family: Some("manuscript".to_string()),
                        selected_subagent_id: Some("manuscript".to_string()),
                        retrieval_query_type: Some("general".to_string()),
                        compiler_profile_id: Some("b235-budget-manuscript".to_string()),
                        graphrag_query_mode: Some("global".to_string()),
                        temporal_truth_view: Some("both".to_string()),
                        recipe_kind: Some("manuscript_review".to_string()),
                    }),
                );

                let selected_policy = select_effective_autonomy_policy(&record, &manuscript_follow_on);
                assert_eq!(selected_policy.policy_role.as_deref(), Some("control-live"));
                assert!(!selected_policy.guarded_enablement_live);

                let (autonomy_policy, _risk_evaluation, _approval_gate) = evaluate_follow_on_plan_gate(
                    &record,
                    "beagle-darwin-hpc-governance",
                    &review_inbox_item,
                    &review_decision,
                    &manuscript_follow_on,
                )
                .expect("evaluate manuscript shadow gate");
                assert_eq!(autonomy_policy.policy_role.as_deref(), Some("control-live"));

                let summary = execution_status_summary_for_packet(&dir, &packet.packet)
                    .expect("summary")
                    .expect("summary present");
                assert_eq!(
                    summary.autonomy_policy_rollout_status.as_deref(),
                    Some("implementation-and-analysis-canary-live")
                );
                assert_eq!(
                    summary.autonomy_policy_calibration_status.as_deref(),
                    Some("manuscript-shadow-evaluated")
                );

                let result_links = read_execution_result_links(&dir, "beagle-cluster-pilot")
                    .expect("read result links")
                    .expect("result links present");
                assert!(
                    result_links
                        .links
                        .iter()
                        .any(|link| link.link_kind == "autonomy-policy-manuscript-control")
                );
                assert!(
                    result_links
                        .links
                        .iter()
                        .any(|link| link.link_kind == "autonomy-policy-manuscript-candidate")
                );
                assert!(
                    result_links
                        .links
                        .iter()
                        .any(|link| link.link_kind == "manuscript-shadow-comparison")
                );
                assert!(
                    result_links
                        .links
                        .iter()
                        .any(|link| link.link_kind == "manuscript-rollout-metrics")
                );
                assert!(
                    result_links
                        .links
                        .iter()
                        .any(|link| link.link_kind == "manuscript-rollout-decision")
                );
            })
            .expect("spawn manuscript shadow calibration test")
            .join()
            .expect("join manuscript shadow calibration test");
    }

    #[test]
    fn manuscript_sample_accumulation_rechecks_gate_without_moving_manuscript_live() {
        std::thread::Builder::new()
            .name("manuscript-sample-accumulation-test".to_string())
            .stack_size(32 * 1024 * 1024)
            .spawn(|| {
                let dir = temp_data_dir("manuscript-sample-accumulation");
                let cfg = test_config(&dir);
                seed_workspace_session(&dir, &cfg);
                let packet = packet();
                let plan = analysis_plan();

                approve_execution_plan(
                    &dir,
                    &cfg,
                    "beagle-darwin-hpc-governance",
                    packet.clone(),
                    PlanApprovalRequest {
                        execution_plan: &plan,
                        approved_by: "beagle-operator",
                        approval_note: "Approve bounded analysis execution.",
                    },
                )
                .expect("approve execution plan");

                start_execution_plan(
                    &dir,
                    &cfg,
                    "beagle-darwin-hpc-governance",
                    packet.clone(),
                    PlanExecutionStartRequest {
                        plan_id: &plan.plan_id,
                        started_by: "beagle-operator",
                        start_note: "Run bounded analysis execution.",
                    },
                )
                .expect("start execution plan");

                let inbox_item = materialize_review_inbox_item(
                    &dir,
                    "beagle-darwin-hpc-governance",
                    packet.clone(),
                    ReviewInboxMaterializeRequest {
                        created_by: "beagle-operator",
                        create_note: "Materialize operator review item.",
                    },
                )
                .expect("materialize review inbox");

                decide_review_inbox_item(
                    &dir,
                    &cfg,
                    "beagle-darwin-hpc-governance",
                    packet.clone(),
                    ReviewInboxDecisionRequest {
                        inbox_item_id: inbox_item.inbox_item_id.clone(),
                        decision_action: "edit".to_string(),
                        decided_by: "beagle-operator".to_string(),
                        decision_note:
                            "Edit the next step into an implementation-focused follow-on."
                                .to_string(),
                        edit_patch: Some(ReviewDecisionEditPatch {
                            task_family: Some("implementation".to_string()),
                            selected_subagent_id: Some("core".to_string()),
                            retrieval_query_type: Some("code".to_string()),
                            compiler_profile_id: Some("b235-budget-implementation".to_string()),
                            graphrag_query_mode: Some("local".to_string()),
                            temporal_truth_view: Some("current".to_string()),
                            recipe_kind: Some("repo_native_dev_loop".to_string()),
                        }),
                    },
                )
                .expect("edit review inbox");

                let analysis_bundle = ensure_analysis_shadow_calibration(
                    &dir,
                    "beagle-darwin-hpc-governance",
                    "beagle-cluster-pilot",
                )
                .expect("ensure analysis shadow calibration");
                let mut record = read_required_execution_record(&dir, "beagle-cluster-pilot")
                    .expect("read execution record");
                if let Some(dataset) = record.autonomy_calibration_dataset.as_mut() {
                    for sample in dataset
                        .samples
                        .iter_mut()
                        .filter(|sample| sample.task_family == "analysis")
                    {
                        sample.operator_alignment_observed = Some(true);
                        sample.execution_alignment_observed = Some(true);
                        sample.continued_successfully = Some(true);
                    }
                }
                let calibration_bundle = autonomy_policy_calibration_bundle_from_record(&record)
                    .expect("autonomy calibration bundle present");
                let initial_soak =
                    build_analysis_shadow_soak_bundle(&calibration_bundle, &analysis_bundle, None);
                let seeded_accumulation = build_analysis_sample_accumulation_bundle(
                    &calibration_bundle,
                    &analysis_bundle,
                    &initial_soak.analysis_shadow_history,
                );
                let staged_shadow_state = build_analysis_sample_accumulation_bundle(
                    &calibration_bundle,
                    &analysis_bundle,
                    &seeded_accumulation.analysis_shadow_history,
                );
                let final_accumulation = build_analysis_sample_accumulation_bundle(
                    &calibration_bundle,
                    &analysis_bundle,
                    &staged_shadow_state.analysis_shadow_history,
                );
                persist_analysis_shadow_soak(
                    &mut record,
                    "beagle-darwin-hpc-governance",
                    &AnalysisShadowSoakBundle {
                        analysis_shadow_history: staged_shadow_state.analysis_shadow_history.clone(),
                        analysis_soak_metrics: staged_shadow_state.analysis_soak_metrics.clone(),
                        analysis_promotion_gate: staged_shadow_state
                            .analysis_promotion_gate
                            .clone(),
                    },
                );
                persist_analysis_sample_accumulation(
                    &mut record,
                    "beagle-darwin-hpc-governance",
                    &final_accumulation,
                );
                write_execution_record(&dir, "beagle-cluster-pilot", &record)
                    .expect("persist staged analysis accumulation");

                ensure_analysis_canary_activation(
                    &dir,
                    "beagle-darwin-hpc-governance",
                    "beagle-cluster-pilot",
                )
                .expect("ensure analysis canary activation");

                let accumulation_bundle = Box::new(ensure_manuscript_sample_accumulation(
                    &dir,
                    "beagle-darwin-hpc-governance",
                    "beagle-cluster-pilot",
                )
                .expect("ensure manuscript sample accumulation"));
                assert_eq!(
                    accumulation_bundle
                        .manuscript_promotion_gate
                        .promotion_gate_decision,
                    "keep-shadow"
                );
                assert_eq!(
                    accumulation_bundle
                        .manuscript_shadow_history
                        .prior_shadow_sample_count,
                    1
                );
                assert_eq!(
                    accumulation_bundle
                        .manuscript_shadow_history
                        .additional_shadow_sample_count,
                    3
                );
                assert_eq!(
                    accumulation_bundle
                        .manuscript_shadow_history
                        .shadow_sample_count,
                    4
                );

                let record = Box::new(
                    read_required_execution_record(&dir, "beagle-cluster-pilot")
                        .expect("read execution record"),
                );
                let review_inbox_item = record
                    .review_inbox_item
                    .clone()
                    .expect("review inbox item present");
                let review_decision = record
                    .review_decision
                    .clone()
                    .expect("review decision present");
                let replan_suggestion = record
                    .replan_suggestion
                    .clone()
                    .expect("replan suggestion present");
                let manuscript_follow_on = build_follow_on_plan(
                    &record.execution_plan,
                    &review_inbox_item,
                    &replan_suggestion,
                    "edited",
                    "beagle-operator",
                    Some(&ReviewDecisionEditPatch {
                        task_family: Some("manuscript".to_string()),
                        selected_subagent_id: Some("manuscript".to_string()),
                        retrieval_query_type: Some("general".to_string()),
                        compiler_profile_id: Some("b235-budget-manuscript".to_string()),
                        graphrag_query_mode: Some("global".to_string()),
                        temporal_truth_view: Some("both".to_string()),
                        recipe_kind: Some("manuscript_review".to_string()),
                    }),
                );

                let selected_policy =
                    select_effective_autonomy_policy(&record, &manuscript_follow_on);
                assert_eq!(selected_policy.policy_role.as_deref(), Some("control-live"));
                assert!(!selected_policy.guarded_enablement_live);

                let (autonomy_policy, _risk_evaluation, _approval_gate) =
                    evaluate_follow_on_plan_gate(
                        &record,
                        "beagle-darwin-hpc-governance",
                        &review_inbox_item,
                        &review_decision,
                        &manuscript_follow_on,
                    )
                    .expect("evaluate manuscript accumulation gate");
                assert_eq!(autonomy_policy.policy_role.as_deref(), Some("control-live"));

                let summary = execution_status_summary_for_packet(&dir, &packet.packet)
                    .expect("summary")
                    .expect("summary present");
                assert_eq!(
                    summary.autonomy_policy_rollout_status.as_deref(),
                    Some("implementation-and-analysis-canary-live")
                );
                assert_eq!(
                    summary.autonomy_policy_calibration_status.as_deref(),
                    Some("manuscript-shadow-rechecked")
                );

                let result_links = read_execution_result_links(&dir, "beagle-cluster-pilot")
                    .expect("read result links")
                    .expect("result links present");
                assert!(
                    result_links
                        .links
                        .iter()
                        .any(|link| link.link_kind == "manuscript-shadow-history")
                );
                assert!(
                    result_links
                        .links
                        .iter()
                        .any(|link| link.link_kind == "manuscript-soak-metrics")
                );
                assert!(
                    result_links
                        .links
                        .iter()
                        .any(|link| link.link_kind == "manuscript-promotion-gate")
                );
            })
            .expect("spawn manuscript sample accumulation test")
            .join()
            .expect("join manuscript sample accumulation test");
    }

    #[test]
    fn manuscript_alignment_signal_acquisition_enriches_gate_without_moving_manuscript_live() {
        std::thread::Builder::new()
            .name("manuscript-alignment-labeling-test".to_string())
            .stack_size(32 * 1024 * 1024)
            .spawn(|| {
                let dir = temp_data_dir("manuscript-alignment-labeling");
                let cfg = test_config(&dir);
                seed_workspace_session(&dir, &cfg);
                let packet = packet();
                let plan = analysis_plan();

                approve_execution_plan(
                    &dir,
                    &cfg,
                    "beagle-darwin-hpc-governance",
                    packet.clone(),
                    PlanApprovalRequest {
                        execution_plan: &plan,
                        approved_by: "beagle-operator",
                        approval_note: "Approve bounded analysis execution.",
                    },
                )
                .expect("approve execution plan");

                start_execution_plan(
                    &dir,
                    &cfg,
                    "beagle-darwin-hpc-governance",
                    packet.clone(),
                    PlanExecutionStartRequest {
                        plan_id: &plan.plan_id,
                        started_by: "beagle-operator",
                        start_note: "Run bounded analysis execution.",
                    },
                )
                .expect("start execution plan");

                let inbox_item = materialize_review_inbox_item(
                    &dir,
                    "beagle-darwin-hpc-governance",
                    packet.clone(),
                    ReviewInboxMaterializeRequest {
                        created_by: "beagle-operator",
                        create_note: "Materialize operator review item.",
                    },
                )
                .expect("materialize review inbox");

                decide_review_inbox_item(
                    &dir,
                    &cfg,
                    "beagle-darwin-hpc-governance",
                    packet.clone(),
                    ReviewInboxDecisionRequest {
                        inbox_item_id: inbox_item.inbox_item_id.clone(),
                        decision_action: "edit".to_string(),
                        decided_by: "beagle-operator".to_string(),
                        decision_note:
                            "Edit the next step into an implementation-focused follow-on."
                                .to_string(),
                        edit_patch: Some(ReviewDecisionEditPatch {
                            task_family: Some("implementation".to_string()),
                            selected_subagent_id: Some("core".to_string()),
                            retrieval_query_type: Some("code".to_string()),
                            compiler_profile_id: Some("b235-budget-implementation".to_string()),
                            graphrag_query_mode: Some("local".to_string()),
                            temporal_truth_view: Some("current".to_string()),
                            recipe_kind: Some("repo_native_dev_loop".to_string()),
                        }),
                    },
                )
                .expect("edit review inbox");

                let analysis_bundle = ensure_analysis_shadow_calibration(
                    &dir,
                    "beagle-darwin-hpc-governance",
                    "beagle-cluster-pilot",
                )
                .expect("ensure analysis shadow calibration");
                let mut record = read_required_execution_record(&dir, "beagle-cluster-pilot")
                    .expect("read execution record");
                if let Some(dataset) = record.autonomy_calibration_dataset.as_mut() {
                    for sample in dataset
                        .samples
                        .iter_mut()
                        .filter(|sample| sample.task_family == "analysis")
                    {
                        sample.operator_alignment_observed = Some(true);
                        sample.execution_alignment_observed = Some(true);
                        sample.continued_successfully = Some(true);
                    }
                }
                let calibration_bundle = autonomy_policy_calibration_bundle_from_record(&record)
                    .expect("autonomy calibration bundle present");
                let initial_soak =
                    build_analysis_shadow_soak_bundle(&calibration_bundle, &analysis_bundle, None);
                let seeded_accumulation = build_analysis_sample_accumulation_bundle(
                    &calibration_bundle,
                    &analysis_bundle,
                    &initial_soak.analysis_shadow_history,
                );
                let staged_shadow_state = build_analysis_sample_accumulation_bundle(
                    &calibration_bundle,
                    &analysis_bundle,
                    &seeded_accumulation.analysis_shadow_history,
                );
                let final_accumulation = build_analysis_sample_accumulation_bundle(
                    &calibration_bundle,
                    &analysis_bundle,
                    &staged_shadow_state.analysis_shadow_history,
                );
                persist_analysis_shadow_soak(
                    &mut record,
                    "beagle-darwin-hpc-governance",
                    &AnalysisShadowSoakBundle {
                        analysis_shadow_history: staged_shadow_state.analysis_shadow_history.clone(),
                        analysis_soak_metrics: staged_shadow_state.analysis_soak_metrics.clone(),
                        analysis_promotion_gate: staged_shadow_state
                            .analysis_promotion_gate
                            .clone(),
                    },
                );
                persist_analysis_sample_accumulation(
                    &mut record,
                    "beagle-darwin-hpc-governance",
                    &final_accumulation,
                );
                write_execution_record(&dir, "beagle-cluster-pilot", &record)
                    .expect("persist staged analysis accumulation");

                ensure_analysis_canary_activation(
                    &dir,
                    "beagle-darwin-hpc-governance",
                    "beagle-cluster-pilot",
                )
                .expect("ensure analysis canary activation");

                let bundle = ensure_manuscript_alignment_signal_acquisition(
                    &dir,
                    "beagle-darwin-hpc-governance",
                    "beagle-cluster-pilot",
                )
                .expect("ensure manuscript alignment signal acquisition");

                assert_eq!(
                    bundle.manuscript_promotion_gate.promotion_gate_decision,
                    "keep-shadow"
                );
                assert_eq!(bundle.manuscript_alignment_labels.shadow_sample_count, 6);
                assert_eq!(
                    bundle
                        .manuscript_promotion_evidence
                        .operator_alignment_labeled_count,
                    6
                );
                assert_eq!(
                    bundle
                        .manuscript_promotion_evidence
                        .execution_outcome_alignment_labeled_count,
                    6
                );
                assert_eq!(
                    bundle.manuscript_promotion_evidence.operator_alignment_basis_points,
                    10_000
                );
                assert_eq!(
                    bundle
                        .manuscript_promotion_evidence
                        .execution_outcome_alignment_basis_points,
                    10_000
                );
                assert_eq!(
                    bundle
                        .manuscript_promotion_evidence
                        .promotion_readiness_label,
                    "keep-shadow"
                );
                assert!(
                    !bundle.manuscript_promotion_gate.promotion_evidence_sufficient
                );
                assert_eq!(
                    bundle.manuscript_promotion_gate.review_quality_label,
                    bundle
                        .manuscript_promotion_evidence
                        .review_quality_label
                );

                let summary = execution_status_summary_for_packet(&dir, &packet.packet)
                    .expect("summary")
                    .expect("summary present");
                assert_eq!(
                    summary.autonomy_policy_calibration_status.as_deref(),
                    Some("manuscript-alignment-signal-acquired")
                );
                assert_eq!(
                    summary.autonomy_policy_rollout_status.as_deref(),
                    Some("implementation-and-analysis-canary-live")
                );

                let result_links = read_execution_result_links(&dir, "beagle-cluster-pilot")
                    .expect("read result links")
                    .expect("result links present");
                assert!(
                    result_links
                        .links
                        .iter()
                        .any(|link| link.link_kind == "manuscript-alignment-labels")
                );
                assert!(
                    result_links
                        .links
                        .iter()
                        .any(|link| link.link_kind == "manuscript-promotion-evidence")
                );
                assert!(
                    result_links
                        .links
                        .iter()
                        .any(|link| link.link_kind == "manuscript-shadow-history")
                );
                assert!(
                    result_links
                        .links
                        .iter()
                        .any(|link| link.link_kind == "manuscript-soak-metrics")
                );
            })
            .expect("spawn manuscript alignment signal test")
            .join()
            .expect("join manuscript alignment signal test");
    }

    #[test]
    fn manuscript_quality_uplift_rehydrates_execution_state_when_bundle_already_exists() {
        std::thread::Builder::new()
            .name("manuscript-quality-uplift-test".to_string())
            .stack_size(32 * 1024 * 1024)
            .spawn(|| {
                let dir = temp_data_dir("manuscript-quality-uplift");
                let cfg = test_config(&dir);
                seed_workspace_session(&dir, &cfg);
                let packet = packet();
                let plan = analysis_plan();

                approve_execution_plan(
                    &dir,
                    &cfg,
                    "beagle-darwin-hpc-governance",
                    packet.clone(),
                    PlanApprovalRequest {
                        execution_plan: &plan,
                        approved_by: "beagle-operator",
                        approval_note: "Approve bounded analysis execution.",
                    },
                )
                .expect("approve execution plan");

                start_execution_plan(
                    &dir,
                    &cfg,
                    "beagle-darwin-hpc-governance",
                    packet.clone(),
                    PlanExecutionStartRequest {
                        plan_id: &plan.plan_id,
                        started_by: "beagle-operator",
                        start_note: "Run bounded analysis execution.",
                    },
                )
                .expect("start execution plan");

                let inbox_item = materialize_review_inbox_item(
                    &dir,
                    "beagle-darwin-hpc-governance",
                    packet.clone(),
                    ReviewInboxMaterializeRequest {
                        created_by: "beagle-operator",
                        create_note: "Materialize operator review item.",
                    },
                )
                .expect("materialize review inbox");

                decide_review_inbox_item(
                    &dir,
                    &cfg,
                    "beagle-darwin-hpc-governance",
                    packet.clone(),
                    ReviewInboxDecisionRequest {
                        inbox_item_id: inbox_item.inbox_item_id.clone(),
                        decision_action: "edit".to_string(),
                        decided_by: "beagle-operator".to_string(),
                        decision_note:
                            "Edit the next step into an implementation-focused follow-on."
                                .to_string(),
                        edit_patch: Some(ReviewDecisionEditPatch {
                            task_family: Some("implementation".to_string()),
                            selected_subagent_id: Some("core".to_string()),
                            retrieval_query_type: Some("code".to_string()),
                            compiler_profile_id: Some("b235-budget-implementation".to_string()),
                            graphrag_query_mode: Some("local".to_string()),
                            temporal_truth_view: Some("current".to_string()),
                            recipe_kind: Some("repo_native_dev_loop".to_string()),
                        }),
                    },
                )
                .expect("edit review inbox");

                let analysis_bundle = ensure_analysis_shadow_calibration(
                    &dir,
                    "beagle-darwin-hpc-governance",
                    "beagle-cluster-pilot",
                )
                .expect("ensure analysis shadow calibration");
                let mut record = read_required_execution_record(&dir, "beagle-cluster-pilot")
                    .expect("read execution record");
                if let Some(dataset) = record.autonomy_calibration_dataset.as_mut() {
                    for sample in dataset
                        .samples
                        .iter_mut()
                        .filter(|sample| sample.task_family == "analysis")
                    {
                        sample.operator_alignment_observed = Some(true);
                        sample.execution_alignment_observed = Some(true);
                        sample.continued_successfully = Some(true);
                    }
                }
                let calibration_bundle = autonomy_policy_calibration_bundle_from_record(&record)
                    .expect("autonomy calibration bundle present");
                let initial_soak =
                    build_analysis_shadow_soak_bundle(&calibration_bundle, &analysis_bundle, None);
                let seeded_accumulation = build_analysis_sample_accumulation_bundle(
                    &calibration_bundle,
                    &analysis_bundle,
                    &initial_soak.analysis_shadow_history,
                );
                let staged_shadow_state = build_analysis_sample_accumulation_bundle(
                    &calibration_bundle,
                    &analysis_bundle,
                    &seeded_accumulation.analysis_shadow_history,
                );
                let final_accumulation = build_analysis_sample_accumulation_bundle(
                    &calibration_bundle,
                    &analysis_bundle,
                    &staged_shadow_state.analysis_shadow_history,
                );
                persist_analysis_shadow_soak(
                    &mut record,
                    "beagle-darwin-hpc-governance",
                    &AnalysisShadowSoakBundle {
                        analysis_shadow_history: staged_shadow_state.analysis_shadow_history.clone(),
                        analysis_soak_metrics: staged_shadow_state.analysis_soak_metrics.clone(),
                        analysis_promotion_gate: staged_shadow_state
                            .analysis_promotion_gate
                            .clone(),
                    },
                );
                persist_analysis_sample_accumulation(
                    &mut record,
                    "beagle-darwin-hpc-governance",
                    &final_accumulation,
                );
                write_execution_record(&dir, "beagle-cluster-pilot", &record)
                    .expect("persist staged analysis accumulation");

                ensure_analysis_canary_activation(
                    &dir,
                    "beagle-darwin-hpc-governance",
                    "beagle-cluster-pilot",
                )
                .expect("ensure analysis canary activation");

                let initial_bundle = ensure_manuscript_quality_uplift(
                    &dir,
                    "beagle-darwin-hpc-governance",
                    "beagle-cluster-pilot",
                    &packet.packet,
                )
                .expect("ensure manuscript quality uplift");

                let mut stale_record = read_required_execution_record(&dir, "beagle-cluster-pilot")
                    .expect("read stale execution record");
                stale_record.execution_state.autonomy_policy_calibration_status =
                    Some("manuscript-alignment-signal-acquired".to_string());
                if let Some(receipt) = stale_record.execution_receipt.as_mut() {
                    receipt.autonomy_policy_calibration_status =
                        Some("manuscript-alignment-signal-acquired".to_string());
                }
                remove_result_link_kind(
                    &mut stale_record.execution_result_links,
                    "manuscript-trajectory-quality",
                );
                remove_result_link_kind(
                    &mut stale_record.execution_result_links,
                    "manuscript-context-adequacy",
                );
                remove_result_link_kind(
                    &mut stale_record.execution_result_links,
                    "manuscript-tuning-recommendation",
                );
                write_execution_record(&dir, "beagle-cluster-pilot", &stale_record)
                    .expect("persist stale manuscript quality state");

                let healed_bundle = ensure_manuscript_quality_uplift(
                    &dir,
                    "beagle-darwin-hpc-governance",
                    "beagle-cluster-pilot",
                    &packet.packet,
                )
                .expect("rehydrate manuscript quality uplift");
                assert_eq!(
                    healed_bundle
                        .manuscript_trajectory_quality
                        .manuscript_trajectory_quality_id,
                    initial_bundle
                        .manuscript_trajectory_quality
                        .manuscript_trajectory_quality_id
                );

                let summary = execution_status_summary_for_packet(&dir, &packet.packet)
                    .expect("summary")
                    .expect("summary present");
                assert_eq!(
                    summary.autonomy_policy_calibration_status.as_deref(),
                    Some("manuscript-quality-uplifted")
                );
                assert_eq!(
                    summary.autonomy_policy_rollout_status.as_deref(),
                    Some("implementation-and-analysis-canary-live")
                );

                let receipt = read_execution_receipt(&dir, "beagle-cluster-pilot")
                    .expect("read execution receipt")
                    .expect("execution receipt present");
                assert_eq!(
                    receipt.autonomy_policy_calibration_status.as_deref(),
                    Some("manuscript-quality-uplifted")
                );

                let result_links = read_execution_result_links(&dir, "beagle-cluster-pilot")
                    .expect("read result links")
                    .expect("result links present");
                assert!(
                    result_links
                        .links
                        .iter()
                        .any(|link| link.link_kind == "manuscript-trajectory-quality")
                );
                assert!(
                    result_links
                        .links
                        .iter()
                        .any(|link| link.link_kind == "manuscript-context-adequacy")
                );
                assert!(
                    result_links
                        .links
                        .iter()
                        .any(|link| link.link_kind == "manuscript-tuning-recommendation")
                );
            })
            .expect("spawn manuscript quality uplift test")
            .join()
            .expect("join manuscript quality uplift test");
    }

    #[test]
    fn continuation_dispatch_chains_review_and_next_execution_with_same_identity() {
        let dir = temp_data_dir("continuation-dispatch");
        let cfg = test_config(&dir);
        seed_workspace_session(&dir, &cfg);
        let packet = packet();
        let plan = analysis_plan();

        approve_execution_plan(
            &dir,
            &cfg,
            "beagle-darwin-hpc-governance",
            packet.clone(),
            PlanApprovalRequest {
                execution_plan: &plan,
                approved_by: "beagle-operator",
                approval_note: "Approve bounded analysis execution.",
            },
        )
        .expect("approve execution plan");

        start_execution_plan(
            &dir,
            &cfg,
            "beagle-darwin-hpc-governance",
            packet.clone(),
            PlanExecutionStartRequest {
                plan_id: &plan.plan_id,
                started_by: "beagle-operator",
                start_note: "Run bounded analysis execution.",
            },
        )
        .expect("start execution plan");

        let inbox_item = materialize_review_inbox_item(
            &dir,
            "beagle-darwin-hpc-governance",
            packet.clone(),
            ReviewInboxMaterializeRequest {
                created_by: "beagle-operator",
                create_note: "Materialize operator review item.",
            },
        )
        .expect("materialize review inbox");

        decide_review_inbox_item(
            &dir,
            &cfg,
            "beagle-darwin-hpc-governance",
            packet.clone(),
            ReviewInboxDecisionRequest {
                inbox_item_id: inbox_item.inbox_item_id,
                decision_action: "approve".to_string(),
                decided_by: "beagle-operator".to_string(),
                decision_note: "Approve the same bounded next step.".to_string(),
                edit_patch: None,
            },
        )
        .expect("approve review inbox");

        let continuation_dispatch = dispatch_follow_on_plan(
            &dir,
            &cfg,
            "beagle-darwin-hpc-governance",
            packet.clone(),
            ContinuationDispatchRequest {
                dispatched_by: "beagle-operator",
                dispatch_note: "Dispatch the approved follow-on plan.",
            },
        )
        .expect("dispatch follow-on plan");
        assert_eq!(
            continuation_dispatch.workstream_id,
            "beagle-darwin-hpc-governance"
        );
        assert_eq!(continuation_dispatch.workspace_id, "beagle-cluster-pilot");
        assert_eq!(
            continuation_dispatch.session_id,
            "ws-cluster-workspace-habitat"
        );
        assert_eq!(continuation_dispatch.review_action, "approved");
        assert_eq!(continuation_dispatch.dispatch_state, "dispatched");
        assert_eq!(continuation_dispatch.next_selected_subagent_id, "experiments");

        let continuation_state = read_continuation_state(&dir, "beagle-cluster-pilot")
            .expect("read continuation state")
            .expect("continuation state present");
        assert_eq!(continuation_state.current_state, "succeeded");
        assert_eq!(continuation_state.review_action, "approved");
        assert_eq!(
            continuation_state.next_execution_state.selected_subagent_id,
            "experiments"
        );
        assert_eq!(
            continuation_state.next_execution_state.workspace_id,
            "beagle-cluster-pilot"
        );

        let continuation_receipt = read_continuation_receipt(&dir, "beagle-cluster-pilot")
            .expect("read continuation receipt")
            .expect("continuation receipt present");
        assert_eq!(continuation_receipt.review_action, "approved");
        assert_eq!(continuation_receipt.workstream_id, "beagle-darwin-hpc-governance");
        assert_eq!(continuation_receipt.workspace_id, "beagle-cluster-pilot");
        assert_eq!(
            continuation_receipt.session_id,
            "ws-cluster-workspace-habitat"
        );
        assert_eq!(continuation_receipt.chained_receipt_ids.len(), 2);
        assert!(continuation_receipt.handoff_updated);
        assert_eq!(
            continuation_receipt.next_execution_receipt.final_state,
            "succeeded"
        );

        let summary = execution_status_summary_for_packet(&dir, &packet.packet)
            .expect("summary")
            .expect("summary present");
        assert!(summary.continuation_dispatched);
        assert_eq!(summary.continuation_current_state.as_deref(), Some("succeeded"));
        assert_eq!(
            summary.continuation_source_execution_id.as_deref(),
            Some(continuation_dispatch.source_execution_id.as_str())
        );
        assert!(summary.latest_continuation_dispatch_id.is_some());
        assert!(summary.latest_continuation_receipt_id.is_some());
        assert_eq!(
            summary.operator_followup_action.as_deref(),
            Some("review-dispatched-continuation-results")
        );

        let follow_on_plan = read_follow_on_plan(&dir, "beagle-cluster-pilot")
            .expect("read follow-on plan")
            .expect("follow-on plan present");
        assert_eq!(follow_on_plan.follow_on_state, "dispatched");
    }

    #[test]
    fn continuation_dispatch_is_idempotent_for_same_follow_on_plan() {
        let dir = temp_data_dir("continuation-idempotent");
        let cfg = test_config(&dir);
        seed_workspace_session(&dir, &cfg);
        let packet = packet();
        let plan = analysis_plan();

        approve_execution_plan(
            &dir,
            &cfg,
            "beagle-darwin-hpc-governance",
            packet.clone(),
            PlanApprovalRequest {
                execution_plan: &plan,
                approved_by: "beagle-operator",
                approval_note: "Approve bounded analysis execution.",
            },
        )
        .expect("approve execution plan");
        start_execution_plan(
            &dir,
            &cfg,
            "beagle-darwin-hpc-governance",
            packet.clone(),
            PlanExecutionStartRequest {
                plan_id: &plan.plan_id,
                started_by: "beagle-operator",
                start_note: "Run bounded analysis execution.",
            },
        )
        .expect("start execution plan");
        let inbox_item = materialize_review_inbox_item(
            &dir,
            "beagle-darwin-hpc-governance",
            packet.clone(),
            ReviewInboxMaterializeRequest {
                created_by: "beagle-operator",
                create_note: "Materialize operator review item.",
            },
        )
        .expect("materialize review inbox");
        decide_review_inbox_item(
            &dir,
            &cfg,
            "beagle-darwin-hpc-governance",
            packet.clone(),
            ReviewInboxDecisionRequest {
                inbox_item_id: inbox_item.inbox_item_id,
                decision_action: "approve".to_string(),
                decided_by: "beagle-operator".to_string(),
                decision_note: "Approve the same bounded next step.".to_string(),
                edit_patch: None,
            },
        )
        .expect("approve review inbox");

        let first = dispatch_follow_on_plan(
            &dir,
            &cfg,
            "beagle-darwin-hpc-governance",
            packet.clone(),
            ContinuationDispatchRequest {
                dispatched_by: "beagle-operator",
                dispatch_note: "Dispatch the approved follow-on plan.",
            },
        )
        .expect("first dispatch");
        let second = dispatch_follow_on_plan(
            &dir,
            &cfg,
            "beagle-darwin-hpc-governance",
            packet,
            ContinuationDispatchRequest {
                dispatched_by: "beagle-operator",
                dispatch_note: "Dispatch the approved follow-on plan again.",
            },
        )
        .expect("second dispatch");
        assert_eq!(
            first.continuation_dispatch_id,
            second.continuation_dispatch_id
        );
    }
}
