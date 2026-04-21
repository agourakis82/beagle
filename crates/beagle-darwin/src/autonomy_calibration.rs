use crate::approval_gate::ApprovalGatingDecision;
use crate::autonomy_policy::AutonomyPolicy;
use crate::continuation_state::{ContinuationReceipt, ContinuationStatePlane};
use crate::execution_plan::ExecutionPlan;
use crate::execution_reflection::{
    editorial_acceptance_fit_label, execution_outcome_alignment_label_from_observation,
    fit_label, review_quality_label, ExecutionReflection, FIT_LABEL_GOOD, FIT_LABEL_POOR,
    REVIEW_QUALITY_LABEL_OPERATOR_READY, REVIEW_QUALITY_LABEL_REPLAN_REQUIRED,
};
use crate::follow_on_plan::FollowOnPlan;
use crate::replan::ReplanSuggestion;
use crate::review_decision::{
    operator_alignment_label_from_observation, ReviewDecision, ALIGNMENT_LABEL_ALIGNED,
    ALIGNMENT_LABEL_INSUFFICIENT_EVIDENCE, ALIGNMENT_LABEL_MISALIGNED,
};
use crate::risk_evaluation::{assess_risk_input, RiskEvaluationInput, RiskSignal};
use crate::trajectory_eval::{
    manuscript_trajectory_uplift_label, TrajectoryEval, MANUSCRIPT_TRAJECTORY_QUALITY_READY,
};
use chrono::{DateTime, Duration, Utc};
use serde::{Deserialize, Serialize};
use std::collections::{BTreeMap, BTreeSet};
use crate::WorkstreamContextPacket;

pub const AUTONOMY_CALIBRATION_DATASET_VERSION: &str =
    "beagle-autonomy-calibration-dataset-v1";
pub const AUTONOMY_POLICY_EVAL_REPORT_VERSION: &str =
    "beagle-autonomy-policy-eval-report-v1";
pub const ESCALATION_THRESHOLD_VERSION: &str = "beagle-escalation-thresholds-v1";
pub const SHADOW_POLICY_COMPARISON_VERSION: &str = "beagle-shadow-policy-comparison-v1";
pub const UPDATED_POLICY_RECOMMENDATION_VERSION: &str =
    "beagle-updated-policy-recommendation-v1";
pub const AUTONOMY_SHADOW_THRESHOLD_VERSION: &str = "beagle-autonomy-shadow-threshold-v1";
pub const POLICY_ROLLOUT_METRIC_VERSION: &str = "beagle-policy-rollout-metrics-v1";
pub const GUARDED_ROLLOUT_DECISION_VERSION: &str = "beagle-guarded-rollout-decision-v1";
pub const CANARY_ROLLOUT_METRIC_VERSION: &str = "beagle-canary-rollout-metrics-v1";
pub const CANARY_ROLLBACK_DECISION_VERSION: &str = "beagle-canary-rollback-decision-v1";
pub const ANALYSIS_SHADOW_CALIBRATION_VERSION: &str =
    "beagle-analysis-shadow-calibration-v1";
pub const ANALYSIS_ROLLOUT_METRIC_VERSION: &str = "beagle-analysis-rollout-metrics-v1";
pub const ANALYSIS_ROLLOUT_DECISION_VERSION: &str = "beagle-analysis-rollout-decision-v1";
pub const ANALYSIS_SHADOW_SOAK_VERSION: &str = "beagle-analysis-shadow-soak-v1";
pub const ANALYSIS_SOAK_METRIC_VERSION: &str = "beagle-analysis-soak-metrics-v1";
pub const ANALYSIS_PROMOTION_GATE_VERSION: &str = "beagle-analysis-promotion-gate-v1";
pub const ANALYSIS_SAMPLE_ACCUMULATION_VERSION: &str =
    "beagle-analysis-sample-accumulation-v1";
pub const ANALYSIS_PROMOTION_GATE_RECHECK_VERSION: &str =
    "beagle-analysis-promotion-gate-recheck-v1";
pub const ANALYSIS_CANARY_METRIC_VERSION: &str = "beagle-analysis-canary-metrics-v1";
pub const ANALYSIS_CANARY_ROLLBACK_VERSION: &str = "beagle-analysis-canary-rollback-v1";
pub const MANUSCRIPT_SHADOW_CALIBRATION_VERSION: &str =
    "beagle-manuscript-shadow-calibration-v1";
pub const MANUSCRIPT_ROLLOUT_METRIC_VERSION: &str =
    "beagle-manuscript-rollout-metrics-v1";
pub const MANUSCRIPT_ROLLOUT_DECISION_VERSION: &str =
    "beagle-manuscript-rollout-decision-v1";
pub const MANUSCRIPT_SAMPLE_ACCUMULATION_VERSION: &str =
    "beagle-manuscript-sample-accumulation-v1";
pub const MANUSCRIPT_SOAK_METRIC_VERSION: &str = "beagle-manuscript-soak-metrics-v1";
pub const MANUSCRIPT_ALIGNMENT_LABEL_VERSION: &str =
    "beagle-manuscript-alignment-label-v1";
pub const MANUSCRIPT_ALIGNMENT_SIGNAL_VERSION: &str =
    "beagle-manuscript-alignment-signal-v1";
pub const MANUSCRIPT_PROMOTION_EVIDENCE_VERSION: &str =
    "beagle-manuscript-promotion-evidence-v1";
pub const MANUSCRIPT_PROMOTION_GATE_RECHECK_VERSION: &str =
    "beagle-manuscript-promotion-gate-recheck-v1";
pub const MANUSCRIPT_TRAJECTORY_QUALITY_VERSION: &str =
    "beagle-manuscript-trajectory-quality-v1";
pub const MANUSCRIPT_CONTEXT_ADEQUACY_VERSION: &str =
    "beagle-manuscript-context-adequacy-v1";
pub const MANUSCRIPT_TUNING_RECOMMENDATION_VERSION: &str =
    "beagle-manuscript-tuning-recommendation-v1";

const SHADOW_STAGE_STATE: &str = "shadow-only";
const CURRENT_CONTROL_POLICY_ROLE: &str = "current-control";
const CANDIDATE_SHADOW_POLICY_ROLE: &str = "candidate-shadow";
const CONTROL_STAGE_STATE: &str = "control-live";
const SHADOW_CANDIDATE_STAGE_STATE: &str = "shadow-candidate";
const ROLLOUT_METRICS_STAGE_STATE: &str = "shadow-compared";
const ANALYSIS_SHADOW_SOAK_STAGE_STATE: &str =
    "implementation-canary-live-analysis-shadow-soak";
const ANALYSIS_SAMPLE_ACCUMULATION_STAGE_STATE: &str =
    "implementation-canary-live-analysis-sample-accumulation";
const ANALYSIS_CANARY_STAGE_STATE: &str = "implementation-and-analysis-canary-live";
const MANUSCRIPT_SHADOW_STAGE_STATE: &str =
    "implementation-and-analysis-canary-live-manuscript-shadow";
const MANUSCRIPT_SAMPLE_ACCUMULATION_STAGE_STATE: &str =
    "implementation-and-analysis-canary-live-manuscript-sample-accumulation";
const MANUSCRIPT_ALIGNMENT_LABELING_STAGE_STATE: &str =
    "implementation-and-analysis-canary-live-manuscript-alignment-labeled";
const MANUSCRIPT_ALIGNMENT_SIGNAL_STAGE_STATE: &str =
    "implementation-and-analysis-canary-live-manuscript-alignment-signal";
const MANUSCRIPT_QUALITY_UPLIFT_STAGE_STATE: &str =
    "implementation-and-analysis-canary-live-manuscript-quality-uplift";
const ANALYSIS_SHADOW_SOAK_WINDOW_SIZE: usize = 6;
const ANALYSIS_PROMOTION_MIN_SHADOW_SAMPLES: usize = 4;
const ANALYSIS_PROMOTION_MIN_ALIGNMENT_BASIS_POINTS: u16 = 10_000;
const MANUSCRIPT_SHADOW_SOAK_WINDOW_SIZE: usize = 6;
const MANUSCRIPT_PROMOTION_MIN_SHADOW_SAMPLES: usize = 4;
const MANUSCRIPT_PROMOTION_MIN_ALIGNMENT_BASIS_POINTS: u16 = 10_000;

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
pub struct AutonomyCalibrationSample {
    pub sample_id: String,
    pub sample_source: String,
    pub source_execution_id: String,
    pub source_plan_id: String,
    pub workstream_id: String,
    pub workspace_id: String,
    pub session_id: String,
    pub task_family: String,
    pub selected_subagent_id: String,
    pub retrieval_query_type: String,
    pub compiler_profile_id: String,
    pub graphrag_query_mode: String,
    pub temporal_truth_view: String,
    pub trajectory_quality: String,
    pub trajectory_score: u8,
    pub overall_quality_score: u8,
    pub replan_required: bool,
    pub requested_operator_action: String,
    pub review_action: String,
    #[serde(default)]
    pub recipe_kind: Option<String>,
    #[serde(default)]
    pub experiment_id: Option<String>,
    pub current_policy_decision_class: String,
    pub current_policy_risk_level: String,
    pub current_policy_risk_score: u8,
    pub expected_decision_class: String,
    pub current_policy_correct: bool,
    #[serde(default)]
    pub operator_alignment_observed: Option<bool>,
    #[serde(default)]
    pub execution_alignment_observed: Option<bool>,
    #[serde(default)]
    pub continued_successfully: Option<bool>,
    pub matched_policy_signals: Vec<String>,
    pub risk_signals: Vec<RiskSignal>,
    pub outcome_source: String,
    #[serde(default)]
    pub shadow_scenario: Option<String>,
    pub note: String,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
pub struct AutonomyCalibrationDataset {
    pub dataset_version: String,
    pub dataset_id: String,
    pub policy_id: String,
    pub source_execution_id: String,
    pub source_plan_id: String,
    pub workstream_id: String,
    pub workspace_id: String,
    pub session_id: String,
    pub generated_at: DateTime<Utc>,
    pub sample_count: usize,
    pub replay_sample_count: usize,
    pub shadow_sample_count: usize,
    pub task_families_evaluated: Vec<String>,
    pub decision_classes_evaluated: Vec<String>,
    pub samples: Vec<AutonomyCalibrationSample>,
    pub note: String,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
pub struct PolicySignalImpact {
    pub signal_id: String,
    pub matched_count: usize,
    pub risk_count: usize,
    pub auto_continue_count: usize,
    pub review_required_count: usize,
    pub blocked_count: usize,
    pub impact_level: String,
    pub note: String,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
pub struct TaskFamilyCalibrationSummary {
    pub task_family: String,
    pub sample_count: usize,
    pub predicted_auto_continue_count: usize,
    pub predicted_review_required_count: usize,
    pub predicted_blocked_count: usize,
    pub expected_auto_continue_count: usize,
    pub expected_review_required_count: usize,
    pub expected_blocked_count: usize,
    pub false_auto_continue_rate_basis_points: u16,
    pub false_review_required_rate_basis_points: u16,
    pub false_blocked_rate_basis_points: u16,
    pub calibration_posture: String,
    pub note: String,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
pub struct AutonomyPolicyEvalReport {
    pub report_version: String,
    pub report_id: String,
    pub dataset_id: String,
    pub policy_id: String,
    pub workstream_id: String,
    pub workspace_id: String,
    pub session_id: String,
    pub generated_at: DateTime<Utc>,
    pub stage_state: String,
    pub evaluated_sample_count: usize,
    pub replay_sample_count: usize,
    pub shadow_sample_count: usize,
    pub false_auto_continue_rate_basis_points: u16,
    pub false_review_required_rate_basis_points: u16,
    pub false_blocked_rate_basis_points: u16,
    pub operator_alignment_rate_basis_points: u16,
    pub execution_alignment_rate_basis_points: u16,
    pub policy_posture: String,
    pub decision_class_coverage: Vec<String>,
    pub task_family_summaries: Vec<TaskFamilyCalibrationSummary>,
    pub signal_importance: Vec<PolicySignalImpact>,
    pub note: String,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
pub struct EscalationThreshold {
    pub task_family: String,
    pub stage_state: String,
    pub auto_continue_enabled: bool,
    pub auto_continue_min_overall_quality_score: u8,
    pub auto_continue_min_trajectory_score: u8,
    pub blocked_max_overall_quality_score: u8,
    pub blocked_max_trajectory_score: u8,
    pub allowed_subagent_ids: Vec<String>,
    pub allowed_retrieval_query_types: Vec<String>,
    pub allowed_compiler_profile_ids: Vec<String>,
    pub allowed_graphrag_query_modes: Vec<String>,
    pub allowed_temporal_truth_views: Vec<String>,
    pub blocked_requested_operator_actions: Vec<String>,
    pub blocked_when_replan_required: bool,
    pub recommended_action: String,
    pub rationale: String,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
pub struct EscalationThresholds {
    pub thresholds_version: String,
    pub escalation_thresholds_id: String,
    pub dataset_id: String,
    pub eval_report_id: String,
    pub policy_id: String,
    pub workstream_id: String,
    pub workspace_id: String,
    pub session_id: String,
    pub generated_at: DateTime<Utc>,
    pub stage_state: String,
    pub thresholds: Vec<EscalationThreshold>,
    pub note: String,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
pub struct ShadowPolicyComparisonEntry {
    pub sample_id: String,
    pub task_family: String,
    pub sample_source: String,
    pub expected_decision_class: String,
    pub current_policy_decision_class: String,
    pub shadow_policy_decision_class: String,
    pub improved_alignment: bool,
    pub regression: bool,
    pub note: String,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
pub struct ShadowPolicyComparison {
    pub comparison_version: String,
    pub shadow_policy_comparison_id: String,
    pub dataset_id: String,
    pub escalation_thresholds_id: String,
    pub policy_id: String,
    pub workstream_id: String,
    pub workspace_id: String,
    pub session_id: String,
    pub generated_at: DateTime<Utc>,
    pub stage_state: String,
    pub compared_sample_count: usize,
    pub improved_alignment_count: usize,
    pub unchanged_alignment_count: usize,
    pub regression_count: usize,
    pub samples: Vec<ShadowPolicyComparisonEntry>,
    pub note: String,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
pub struct PolicyTaskFamilyUpdateRecommendation {
    pub task_family: String,
    pub current_policy_posture: String,
    pub recommended_action: String,
    pub stage_state: String,
    pub rationale: String,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
pub struct UpdatedPolicyRecommendation {
    pub recommendation_version: String,
    pub updated_policy_recommendation_id: String,
    pub policy_id: String,
    pub dataset_id: String,
    pub eval_report_id: String,
    pub escalation_thresholds_id: String,
    pub shadow_policy_comparison_id: String,
    pub workstream_id: String,
    pub workspace_id: String,
    pub session_id: String,
    pub generated_at: DateTime<Utc>,
    pub stage_state: String,
    pub policy_posture: String,
    pub recommended_action: String,
    pub safe_to_apply_live: bool,
    pub rollout_guardrails: Vec<String>,
    pub task_family_updates: Vec<PolicyTaskFamilyUpdateRecommendation>,
    pub note: String,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
pub struct AutonomyPolicyCalibrationBundle {
    pub calibration_dataset: AutonomyCalibrationDataset,
    pub policy_eval_report: AutonomyPolicyEvalReport,
    pub escalation_thresholds: EscalationThresholds,
    pub shadow_policy_comparison: ShadowPolicyComparison,
    pub updated_policy_recommendation: UpdatedPolicyRecommendation,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
pub struct AutonomyShadowTaskFamilyThreshold {
    pub task_family: String,
    pub rollout_state: String,
    pub auto_continue_enabled: bool,
    pub auto_continue_allowed_review_actions: Vec<String>,
    pub auto_continue_allowed_trajectory_qualities: Vec<String>,
    pub auto_continue_min_overall_quality_score: u8,
    pub auto_continue_min_trajectory_score: u8,
    pub blocked_max_overall_quality_score: u8,
    pub blocked_max_trajectory_score: u8,
    pub blocked_trajectory_qualities: Vec<String>,
    pub allowed_subagent_ids: Vec<String>,
    pub allowed_retrieval_query_types: Vec<String>,
    pub allowed_compiler_profile_ids: Vec<String>,
    pub allowed_graphrag_query_modes: Vec<String>,
    pub allowed_temporal_truth_views: Vec<String>,
    pub blocked_requested_operator_actions: Vec<String>,
    pub blocked_when_replan_required: bool,
    pub guarded_enablement_eligible: bool,
    pub rationale: String,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
pub struct AutonomyShadowThreshold {
    pub shadow_threshold_version: String,
    pub shadow_threshold_id: String,
    pub policy_role: String,
    pub source_policy_id: String,
    pub source_dataset_id: String,
    pub source_eval_report_id: String,
    pub source_escalation_thresholds_id: String,
    pub workstream_id: String,
    pub workspace_id: String,
    pub session_id: String,
    pub generated_at: DateTime<Utc>,
    pub stage_state: String,
    pub family_thresholds: Vec<AutonomyShadowTaskFamilyThreshold>,
    pub note: String,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
pub struct TaskFamilyRolloutMetric {
    pub task_family: String,
    pub sample_count: usize,
    pub current_auto_continue_count: usize,
    pub current_review_required_count: usize,
    pub current_blocked_count: usize,
    pub candidate_auto_continue_count: usize,
    pub candidate_review_required_count: usize,
    pub candidate_blocked_count: usize,
    pub current_false_auto_continue_rate_basis_points: u16,
    pub candidate_false_auto_continue_rate_basis_points: u16,
    pub current_false_review_required_rate_basis_points: u16,
    pub candidate_false_review_required_rate_basis_points: u16,
    pub current_false_blocked_rate_basis_points: u16,
    pub candidate_false_blocked_rate_basis_points: u16,
    pub current_alignment_with_operator_decision_basis_points: u16,
    pub candidate_alignment_with_operator_decision_basis_points: u16,
    pub current_alignment_with_execution_outcome_basis_points: u16,
    pub candidate_alignment_with_execution_outcome_basis_points: u16,
    pub improved_alignment_count: usize,
    pub regression_count: usize,
    pub rollout_readiness: String,
    pub note: String,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
pub struct PolicyRolloutMetrics {
    pub metrics_version: String,
    pub rollout_metrics_id: String,
    pub current_shadow_threshold_id: String,
    pub candidate_shadow_threshold_id: String,
    pub dataset_id: String,
    pub shadow_policy_comparison_id: String,
    pub workstream_id: String,
    pub workspace_id: String,
    pub session_id: String,
    pub generated_at: DateTime<Utc>,
    pub rollout_stage: String,
    pub sample_count: usize,
    pub current_false_auto_continue_rate_basis_points: u16,
    pub candidate_false_auto_continue_rate_basis_points: u16,
    pub current_false_review_required_rate_basis_points: u16,
    pub candidate_false_review_required_rate_basis_points: u16,
    pub current_false_blocked_rate_basis_points: u16,
    pub candidate_false_blocked_rate_basis_points: u16,
    pub current_alignment_with_operator_decision_basis_points: u16,
    pub candidate_alignment_with_operator_decision_basis_points: u16,
    pub current_alignment_with_execution_outcome_basis_points: u16,
    pub candidate_alignment_with_execution_outcome_basis_points: u16,
    pub improved_alignment_count: usize,
    pub regression_count: usize,
    pub family_metrics: Vec<TaskFamilyRolloutMetric>,
    pub note: String,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
pub struct GuardedTaskFamilyDecision {
    pub task_family: String,
    pub rollout_state: String,
    pub can_move_first: bool,
    pub regression_detected: bool,
    pub rollback_ready: bool,
    pub rationale: String,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
pub struct GuardedRolloutDecision {
    pub decision_version: String,
    pub guarded_rollout_decision_id: String,
    pub current_shadow_threshold_id: String,
    pub candidate_shadow_threshold_id: String,
    pub rollout_metrics_id: String,
    pub shadow_policy_comparison_id: String,
    pub updated_policy_recommendation_id: String,
    pub workstream_id: String,
    pub workspace_id: String,
    pub session_id: String,
    pub generated_at: DateTime<Utc>,
    pub rollout_stage: String,
    pub recommended_action: String,
    pub current_policy_preserved_as_control: bool,
    pub candidate_policy_shadow_mode: bool,
    pub guarded_enablement_permitted: bool,
    pub guarded_enablement_live: bool,
    pub global_policy_update_permitted: bool,
    pub safe_task_families_to_move_first: Vec<String>,
    pub current_control_task_families: Vec<String>,
    pub staged_guarded_task_families: Vec<String>,
    pub blocked_or_hold_task_families: Vec<String>,
    pub regression_detected: bool,
    pub rollback_required: bool,
    pub rollback_trigger: String,
    pub rollback_action: String,
    pub family_decisions: Vec<GuardedTaskFamilyDecision>,
    pub same_beagle_owned_identity: bool,
    pub note: String,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
pub struct GuardedPolicyRolloutBundle {
    pub autonomy_policy_current: AutonomyShadowThreshold,
    pub autonomy_policy_candidate: AutonomyShadowThreshold,
    pub rollout_metrics: PolicyRolloutMetrics,
    pub rollout_decision: GuardedRolloutDecision,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
pub struct CanaryTaskFamilyMetric {
    pub task_family: String,
    pub live_policy_role: String,
    pub canary_enabled: bool,
    pub control_retained: bool,
    pub false_auto_continue_rate_basis_points: u16,
    pub false_review_required_rate_basis_points: u16,
    pub false_blocked_rate_basis_points: u16,
    pub alignment_with_operator_decision_basis_points: u16,
    pub alignment_with_execution_outcome_basis_points: u16,
    pub rollback_triggered: bool,
    pub rationale: String,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
pub struct CanaryRolloutMetrics {
    pub metrics_version: String,
    pub canary_rollout_metrics_id: String,
    pub control_policy_id: String,
    pub canary_policy_id: String,
    pub source_rollout_metrics_id: String,
    pub source_rollout_decision_id: String,
    pub workstream_id: String,
    pub workspace_id: String,
    pub session_id: String,
    pub generated_at: DateTime<Utc>,
    pub canary_stage: String,
    pub false_auto_continue_rate_basis_points: u16,
    pub false_review_required_rate_basis_points: u16,
    pub false_blocked_rate_basis_points: u16,
    pub alignment_with_operator_decision_basis_points: u16,
    pub alignment_with_execution_outcome_basis_points: u16,
    pub rollback_triggered: bool,
    pub implementation_canary_enabled: bool,
    pub analysis_control_retained: bool,
    pub manuscript_control_retained: bool,
    pub family_metrics: Vec<CanaryTaskFamilyMetric>,
    pub note: String,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
pub struct CanaryRollbackDecision {
    pub decision_version: String,
    pub canary_rollback_decision_id: String,
    pub canary_rollout_metrics_id: String,
    pub source_rollout_decision_id: String,
    pub control_policy_id: String,
    pub canary_policy_id: String,
    pub workstream_id: String,
    pub workspace_id: String,
    pub session_id: String,
    pub generated_at: DateTime<Utc>,
    pub canary_stage: String,
    pub implementation_canary_live: bool,
    pub analysis_control_retained: bool,
    pub manuscript_control_retained: bool,
    pub regression_detected: bool,
    pub rollback_required: bool,
    pub rollback_triggered: bool,
    pub rollback_reason: String,
    pub rollback_action: String,
    pub same_beagle_owned_identity: bool,
    pub note: String,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
pub struct ImplementationCanaryAutonomyBundle {
    pub autonomy_policy_control: AutonomyPolicy,
    pub autonomy_policy_canary: AutonomyPolicy,
    pub canary_rollout_metrics: CanaryRolloutMetrics,
    pub canary_rollback_decision: CanaryRollbackDecision,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
pub struct AnalysisShadowComparisonEntry {
    pub sample_id: String,
    pub sample_source: String,
    pub expected_decision_class: String,
    pub current_policy_decision_class: String,
    pub analysis_candidate_decision_class: String,
    pub improved_alignment: bool,
    pub regression: bool,
    pub note: String,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
pub struct AnalysisShadowCalibration {
    pub calibration_version: String,
    pub analysis_shadow_calibration_id: String,
    pub control_policy_id: String,
    pub analysis_candidate_policy_id: String,
    pub source_dataset_id: String,
    pub source_canary_rollout_metrics_id: String,
    pub source_canary_rollback_decision_id: String,
    pub workstream_id: String,
    pub workspace_id: String,
    pub session_id: String,
    pub generated_at: DateTime<Utc>,
    pub rollout_stage: String,
    pub implementation_canary_retained: bool,
    pub manuscript_control_retained: bool,
    pub compared_sample_count: usize,
    pub improved_alignment_count: usize,
    pub regression_count: usize,
    pub recommendation_for_analysis: String,
    pub samples: Vec<AnalysisShadowComparisonEntry>,
    pub note: String,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
pub struct AnalysisTaskFamilyMetric {
    pub task_family: String,
    pub live_policy_role: String,
    #[serde(default)]
    pub shadow_policy_role: Option<String>,
    pub canary_retained: bool,
    pub control_retained: bool,
    pub shadow_evaluated: bool,
    pub current_false_auto_continue_rate_basis_points: u16,
    pub shadow_false_auto_continue_rate_basis_points: u16,
    pub current_false_review_required_rate_basis_points: u16,
    pub shadow_false_review_required_rate_basis_points: u16,
    pub current_alignment_with_operator_decision_basis_points: u16,
    pub shadow_alignment_with_operator_decision_basis_points: u16,
    pub current_alignment_with_execution_outcome_basis_points: u16,
    pub shadow_alignment_with_execution_outcome_basis_points: u16,
    pub regression_count: usize,
    pub recommendation_for_analysis: String,
    pub rationale: String,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
pub struct AnalysisRolloutMetrics {
    pub metrics_version: String,
    pub analysis_rollout_metrics_id: String,
    pub control_policy_id: String,
    pub analysis_candidate_policy_id: String,
    pub implementation_canary_policy_id: String,
    pub source_dataset_id: String,
    pub source_canary_rollout_metrics_id: String,
    pub source_canary_rollback_decision_id: String,
    pub workstream_id: String,
    pub workspace_id: String,
    pub session_id: String,
    pub generated_at: DateTime<Utc>,
    pub rollout_stage: String,
    pub analysis_sample_count: usize,
    pub current_false_auto_continue_rate_basis_points: u16,
    pub shadow_false_auto_continue_rate_basis_points: u16,
    pub current_false_review_required_rate_basis_points: u16,
    pub shadow_false_review_required_rate_basis_points: u16,
    pub current_alignment_with_operator_decision_basis_points: u16,
    pub shadow_alignment_with_operator_decision_basis_points: u16,
    pub current_alignment_with_execution_outcome_basis_points: u16,
    pub shadow_alignment_with_execution_outcome_basis_points: u16,
    pub regression_count: usize,
    pub implementation_canary_retained: bool,
    pub manuscript_control_retained: bool,
    pub recommendation_for_analysis: String,
    pub family_metrics: Vec<AnalysisTaskFamilyMetric>,
    pub note: String,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
pub struct AnalysisRolloutDecision {
    pub decision_version: String,
    pub analysis_rollout_decision_id: String,
    pub control_policy_id: String,
    pub analysis_candidate_policy_id: String,
    pub analysis_shadow_calibration_id: String,
    pub analysis_rollout_metrics_id: String,
    pub source_canary_rollout_metrics_id: String,
    pub source_canary_rollback_decision_id: String,
    pub workstream_id: String,
    pub workspace_id: String,
    pub session_id: String,
    pub generated_at: DateTime<Utc>,
    pub rollout_stage: String,
    pub decision_output: String,
    pub analysis_shadow_active: bool,
    pub implementation_canary_retained: bool,
    pub manuscript_control_retained: bool,
    pub regression_detected: bool,
    pub rollback_required: bool,
    pub rollback_trigger: String,
    pub rollback_action: String,
    pub same_beagle_owned_identity: bool,
    pub note: String,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
pub struct AnalysisShadowCalibrationBundle {
    pub autonomy_policy_control: AutonomyPolicy,
    pub autonomy_policy_analysis_candidate: AutonomyPolicy,
    pub analysis_shadow_comparison: AnalysisShadowCalibration,
    pub analysis_rollout_metrics: AnalysisRolloutMetrics,
    pub analysis_rollout_decision: AnalysisRolloutDecision,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
pub struct AnalysisShadowHistoryEntry {
    pub observation_id: String,
    pub sample_id: String,
    pub sample_source: String,
    pub observed_at: DateTime<Utc>,
    pub expected_decision_class: String,
    pub current_policy_decision_class: String,
    pub analysis_candidate_decision_class: String,
    pub operator_alignment_observed: bool,
    pub execution_alignment_observed: bool,
    pub improved_alignment: bool,
    pub regression: bool,
    pub note: String,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
pub struct AnalysisShadowSoak {
    pub soak_version: String,
    pub analysis_shadow_soak_id: String,
    pub control_policy_id: String,
    pub analysis_candidate_policy_id: String,
    pub source_analysis_shadow_calibration_id: String,
    pub source_analysis_rollout_metrics_id: String,
    pub source_analysis_rollout_decision_id: String,
    pub workstream_id: String,
    pub workspace_id: String,
    pub session_id: String,
    pub generated_at: DateTime<Utc>,
    pub rollout_stage: String,
    #[serde(default)]
    pub prior_shadow_sample_count: usize,
    #[serde(default)]
    pub additional_shadow_sample_count: usize,
    pub shadow_sample_count: usize,
    pub rolling_window_size: usize,
    pub implementation_canary_retained: bool,
    pub manuscript_control_retained: bool,
    pub history: Vec<AnalysisShadowHistoryEntry>,
    pub note: String,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
pub struct AnalysisSoakMetrics {
    pub metrics_version: String,
    pub analysis_soak_metrics_id: String,
    pub analysis_shadow_soak_id: String,
    pub control_policy_id: String,
    pub analysis_candidate_policy_id: String,
    pub source_analysis_shadow_calibration_id: String,
    pub source_analysis_rollout_metrics_id: String,
    pub source_analysis_rollout_decision_id: String,
    pub workstream_id: String,
    pub workspace_id: String,
    pub session_id: String,
    pub generated_at: DateTime<Utc>,
    pub rollout_stage: String,
    #[serde(default)]
    pub prior_shadow_sample_count: usize,
    #[serde(default)]
    pub additional_shadow_sample_count: usize,
    pub shadow_sample_count: usize,
    pub rolling_window_size: usize,
    pub false_auto_continue_rate_basis_points: u16,
    pub false_review_required_rate_basis_points: u16,
    pub alignment_with_operator_decision_basis_points: u16,
    pub alignment_with_execution_outcome_basis_points: u16,
    pub control_false_auto_continue_rate_basis_points: u16,
    pub control_false_review_required_rate_basis_points: u16,
    pub control_alignment_with_operator_decision_basis_points: u16,
    pub control_alignment_with_execution_outcome_basis_points: u16,
    pub improved_alignment_count: usize,
    pub regression_count: usize,
    pub implementation_canary_retained: bool,
    pub manuscript_control_retained: bool,
    pub promotion_gate_decision_preview: String,
    pub note: String,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
pub struct AnalysisPromotionGate {
    pub gate_version: String,
    pub analysis_promotion_gate_id: String,
    pub analysis_shadow_soak_id: String,
    pub analysis_soak_metrics_id: String,
    pub control_policy_id: String,
    pub analysis_candidate_policy_id: String,
    pub source_analysis_rollout_decision_id: String,
    pub workstream_id: String,
    pub workspace_id: String,
    pub session_id: String,
    pub generated_at: DateTime<Utc>,
    pub rollout_stage: String,
    pub minimum_shadow_sample_count: usize,
    #[serde(default)]
    pub prior_shadow_sample_count: usize,
    #[serde(default)]
    pub additional_shadow_sample_count: usize,
    pub shadow_sample_count: usize,
    pub false_auto_continue_rate_basis_points: u16,
    pub false_review_required_rate_basis_points: u16,
    pub alignment_with_operator_decision_basis_points: u16,
    pub alignment_with_execution_outcome_basis_points: u16,
    pub regression_count: usize,
    pub promotion_gate_decision: String,
    pub promotion_criteria_met: bool,
    pub implementation_canary_retained: bool,
    pub manuscript_control_retained: bool,
    pub hold_or_rollback_required: bool,
    pub rollback_trigger: String,
    pub rollback_action: String,
    pub same_beagle_owned_identity: bool,
    pub rationale: String,
    pub note: String,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
pub struct AnalysisShadowSoakBundle {
    pub analysis_shadow_history: AnalysisShadowSoak,
    pub analysis_soak_metrics: AnalysisSoakMetrics,
    pub analysis_promotion_gate: AnalysisPromotionGate,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
pub struct AnalysisSampleAccumulationBundle {
    pub analysis_shadow_history: AnalysisShadowSoak,
    pub analysis_soak_metrics: AnalysisSoakMetrics,
    pub analysis_promotion_gate: AnalysisPromotionGate,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
pub struct AnalysisCanaryFamilyMetric {
    pub task_family: String,
    pub live_policy_role: String,
    pub canary_enabled: bool,
    pub control_retained: bool,
    pub false_auto_continue_rate_basis_points: u16,
    pub false_review_required_rate_basis_points: u16,
    pub alignment_with_operator_decision_basis_points: u16,
    pub alignment_with_execution_outcome_basis_points: u16,
    pub regression_count: usize,
    pub rollback_triggered: bool,
    pub rationale: String,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
pub struct AnalysisCanaryMetrics {
    pub metrics_version: String,
    pub analysis_canary_metrics_id: String,
    pub control_policy_id: String,
    pub implementation_canary_policy_id: String,
    pub analysis_canary_policy_id: String,
    pub source_canary_rollout_metrics_id: String,
    pub source_canary_rollback_decision_id: String,
    pub source_analysis_shadow_calibration_id: String,
    pub source_analysis_sample_accumulation_id: String,
    pub source_analysis_soak_metrics_id: String,
    pub source_analysis_promotion_gate_id: String,
    pub workstream_id: String,
    pub workspace_id: String,
    pub session_id: String,
    pub generated_at: DateTime<Utc>,
    pub canary_stage: String,
    pub analysis_sample_count: usize,
    pub false_auto_continue_rate_basis_points: u16,
    pub false_review_required_rate_basis_points: u16,
    pub alignment_with_operator_decision_basis_points: u16,
    pub alignment_with_execution_outcome_basis_points: u16,
    pub regression_count: usize,
    pub rollback_triggered: bool,
    pub implementation_canary_retained: bool,
    pub analysis_canary_live: bool,
    pub manuscript_control_retained: bool,
    pub family_metrics: Vec<AnalysisCanaryFamilyMetric>,
    pub note: String,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
pub struct AnalysisCanaryRollbackDecision {
    pub decision_version: String,
    pub analysis_canary_rollback_decision_id: String,
    pub analysis_canary_metrics_id: String,
    pub source_analysis_promotion_gate_id: String,
    pub control_policy_id: String,
    pub implementation_canary_policy_id: String,
    pub analysis_canary_policy_id: String,
    pub workstream_id: String,
    pub workspace_id: String,
    pub session_id: String,
    pub generated_at: DateTime<Utc>,
    pub canary_stage: String,
    pub implementation_canary_retained: bool,
    pub analysis_canary_live: bool,
    pub manuscript_control_retained: bool,
    pub regression_detected: bool,
    pub rollback_required: bool,
    pub rollback_triggered: bool,
    pub rollback_reason: String,
    pub rollback_action: String,
    pub same_beagle_owned_identity: bool,
    pub note: String,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
pub struct AnalysisCanaryActivationBundle {
    pub autonomy_policy_control: AutonomyPolicy,
    pub autonomy_policy_implementation_canary: AutonomyPolicy,
    pub autonomy_policy_analysis_canary: AutonomyPolicy,
    pub analysis_canary_metrics: AnalysisCanaryMetrics,
    pub analysis_canary_rollback_decision: AnalysisCanaryRollbackDecision,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
pub struct ManuscriptShadowComparisonEntry {
    pub sample_id: String,
    pub sample_source: String,
    pub expected_decision_class: String,
    pub current_policy_decision_class: String,
    pub manuscript_candidate_decision_class: String,
    pub improved_alignment: bool,
    pub regression: bool,
    pub note: String,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
pub struct ManuscriptShadowCalibration {
    pub calibration_version: String,
    pub manuscript_shadow_calibration_id: String,
    pub control_policy_id: String,
    pub manuscript_candidate_policy_id: String,
    pub source_dataset_id: String,
    pub source_analysis_canary_metrics_id: String,
    pub source_analysis_canary_rollback_decision_id: String,
    pub workstream_id: String,
    pub workspace_id: String,
    pub session_id: String,
    pub generated_at: DateTime<Utc>,
    pub rollout_stage: String,
    pub implementation_canary_retained: bool,
    pub analysis_canary_retained: bool,
    pub compared_sample_count: usize,
    pub improved_alignment_count: usize,
    pub regression_count: usize,
    pub recommendation_for_manuscript: String,
    pub samples: Vec<ManuscriptShadowComparisonEntry>,
    pub note: String,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
pub struct ManuscriptTaskFamilyMetric {
    pub task_family: String,
    pub live_policy_role: String,
    #[serde(default)]
    pub shadow_policy_role: Option<String>,
    pub canary_retained: bool,
    pub control_retained: bool,
    pub shadow_evaluated: bool,
    pub current_false_auto_continue_rate_basis_points: u16,
    pub shadow_false_auto_continue_rate_basis_points: u16,
    pub current_false_review_required_rate_basis_points: u16,
    pub shadow_false_review_required_rate_basis_points: u16,
    pub current_alignment_with_operator_decision_basis_points: u16,
    pub shadow_alignment_with_operator_decision_basis_points: u16,
    pub current_alignment_with_execution_outcome_basis_points: u16,
    pub shadow_alignment_with_execution_outcome_basis_points: u16,
    pub regression_count: usize,
    pub recommendation_for_manuscript: String,
    pub rationale: String,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
pub struct ManuscriptRolloutMetrics {
    pub metrics_version: String,
    pub manuscript_rollout_metrics_id: String,
    pub control_policy_id: String,
    pub manuscript_candidate_policy_id: String,
    pub implementation_canary_policy_id: String,
    pub analysis_canary_policy_id: String,
    pub source_dataset_id: String,
    pub source_analysis_canary_metrics_id: String,
    pub source_analysis_canary_rollback_decision_id: String,
    pub workstream_id: String,
    pub workspace_id: String,
    pub session_id: String,
    pub generated_at: DateTime<Utc>,
    pub rollout_stage: String,
    pub manuscript_sample_count: usize,
    pub current_false_auto_continue_rate_basis_points: u16,
    pub shadow_false_auto_continue_rate_basis_points: u16,
    pub current_false_review_required_rate_basis_points: u16,
    pub shadow_false_review_required_rate_basis_points: u16,
    pub current_alignment_with_operator_decision_basis_points: u16,
    pub shadow_alignment_with_operator_decision_basis_points: u16,
    pub current_alignment_with_execution_outcome_basis_points: u16,
    pub shadow_alignment_with_execution_outcome_basis_points: u16,
    pub regression_count: usize,
    pub implementation_canary_retained: bool,
    pub analysis_canary_retained: bool,
    pub recommendation_for_manuscript: String,
    pub family_metrics: Vec<ManuscriptTaskFamilyMetric>,
    pub note: String,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
pub struct ManuscriptRolloutDecision {
    pub decision_version: String,
    pub manuscript_rollout_decision_id: String,
    pub control_policy_id: String,
    pub manuscript_candidate_policy_id: String,
    pub manuscript_shadow_calibration_id: String,
    pub manuscript_rollout_metrics_id: String,
    pub source_analysis_canary_metrics_id: String,
    pub source_analysis_canary_rollback_decision_id: String,
    pub workstream_id: String,
    pub workspace_id: String,
    pub session_id: String,
    pub generated_at: DateTime<Utc>,
    pub rollout_stage: String,
    pub decision_output: String,
    pub manuscript_shadow_active: bool,
    pub implementation_canary_retained: bool,
    pub analysis_canary_retained: bool,
    pub regression_detected: bool,
    pub rollback_required: bool,
    pub rollback_trigger: String,
    pub rollback_action: String,
    pub same_beagle_owned_identity: bool,
    pub note: String,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
pub struct ManuscriptShadowCalibrationBundle {
    pub autonomy_policy_control: AutonomyPolicy,
    pub autonomy_policy_manuscript_candidate: AutonomyPolicy,
    pub manuscript_shadow_comparison: ManuscriptShadowCalibration,
    pub manuscript_rollout_metrics: ManuscriptRolloutMetrics,
    pub manuscript_rollout_decision: ManuscriptRolloutDecision,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
pub struct ManuscriptShadowHistoryEntry {
    pub observation_id: String,
    pub sample_id: String,
    pub sample_source: String,
    pub observed_at: DateTime<Utc>,
    pub expected_decision_class: String,
    pub current_policy_decision_class: String,
    pub manuscript_candidate_decision_class: String,
    #[serde(default)]
    pub operator_alignment_observed: Option<bool>,
    #[serde(default)]
    pub execution_alignment_observed: Option<bool>,
    pub improved_alignment: bool,
    pub regression: bool,
    pub note: String,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
pub struct ManuscriptShadowHistory {
    pub accumulation_version: String,
    pub manuscript_shadow_history_id: String,
    pub control_policy_id: String,
    pub manuscript_candidate_policy_id: String,
    pub source_manuscript_shadow_calibration_id: String,
    pub source_manuscript_rollout_metrics_id: String,
    pub source_manuscript_rollout_decision_id: String,
    pub workstream_id: String,
    pub workspace_id: String,
    pub session_id: String,
    pub generated_at: DateTime<Utc>,
    pub rollout_stage: String,
    #[serde(default)]
    pub prior_shadow_sample_count: usize,
    #[serde(default)]
    pub additional_shadow_sample_count: usize,
    pub shadow_sample_count: usize,
    pub rolling_window_size: usize,
    pub implementation_canary_retained: bool,
    pub analysis_canary_retained: bool,
    pub history: Vec<ManuscriptShadowHistoryEntry>,
    pub note: String,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
pub struct ManuscriptSoakMetrics {
    pub metrics_version: String,
    pub manuscript_soak_metrics_id: String,
    pub manuscript_shadow_history_id: String,
    pub control_policy_id: String,
    pub manuscript_candidate_policy_id: String,
    pub source_manuscript_shadow_calibration_id: String,
    pub source_manuscript_rollout_metrics_id: String,
    pub source_manuscript_rollout_decision_id: String,
    pub workstream_id: String,
    pub workspace_id: String,
    pub session_id: String,
    pub generated_at: DateTime<Utc>,
    pub rollout_stage: String,
    #[serde(default)]
    pub prior_shadow_sample_count: usize,
    #[serde(default)]
    pub additional_shadow_sample_count: usize,
    pub shadow_sample_count: usize,
    pub rolling_window_size: usize,
    pub false_auto_continue_rate_basis_points: u16,
    pub false_review_required_rate_basis_points: u16,
    pub alignment_with_operator_decision_basis_points: u16,
    pub alignment_with_execution_outcome_basis_points: u16,
    pub control_false_auto_continue_rate_basis_points: u16,
    pub control_false_review_required_rate_basis_points: u16,
    pub control_alignment_with_operator_decision_basis_points: u16,
    pub control_alignment_with_execution_outcome_basis_points: u16,
    pub improved_alignment_count: usize,
    pub regression_count: usize,
    pub implementation_canary_retained: bool,
    pub analysis_canary_retained: bool,
    pub promotion_gate_decision_preview: String,
    pub note: String,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
pub struct ManuscriptPromotionGate {
    pub gate_version: String,
    pub manuscript_promotion_gate_id: String,
    pub manuscript_shadow_history_id: String,
    pub manuscript_soak_metrics_id: String,
    #[serde(default)]
    pub manuscript_alignment_labels_id: Option<String>,
    #[serde(default)]
    pub manuscript_promotion_evidence_id: Option<String>,
    pub control_policy_id: String,
    pub manuscript_candidate_policy_id: String,
    pub source_manuscript_rollout_decision_id: String,
    pub workstream_id: String,
    pub workspace_id: String,
    pub session_id: String,
    pub generated_at: DateTime<Utc>,
    pub rollout_stage: String,
    pub minimum_shadow_sample_count: usize,
    #[serde(default)]
    pub prior_shadow_sample_count: usize,
    #[serde(default)]
    pub additional_shadow_sample_count: usize,
    pub shadow_sample_count: usize,
    pub false_auto_continue_rate_basis_points: u16,
    pub false_review_required_rate_basis_points: u16,
    pub alignment_with_operator_decision_basis_points: u16,
    pub alignment_with_execution_outcome_basis_points: u16,
    #[serde(default)]
    pub operator_alignment_labeled_count: usize,
    #[serde(default)]
    pub execution_outcome_alignment_labeled_count: usize,
    #[serde(default)]
    pub operator_alignment_label_coverage_basis_points: u16,
    #[serde(default)]
    pub execution_outcome_alignment_label_coverage_basis_points: u16,
    #[serde(default)]
    pub explicit_operator_alignment_basis_points: u16,
    #[serde(default)]
    pub explicit_execution_outcome_alignment_basis_points: u16,
    #[serde(default)]
    pub review_quality_label: String,
    #[serde(default)]
    pub promotion_readiness_label: String,
    #[serde(default)]
    pub promotion_evidence_sufficient: bool,
    pub regression_count: usize,
    pub promotion_gate_decision: String,
    pub promotion_criteria_met: bool,
    pub implementation_canary_retained: bool,
    pub analysis_canary_retained: bool,
    pub hold_or_rollback_required: bool,
    pub rollback_trigger: String,
    pub rollback_action: String,
    pub same_beagle_owned_identity: bool,
    pub rationale: String,
    pub note: String,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
pub struct ManuscriptSampleAccumulationBundle {
    pub manuscript_shadow_history: ManuscriptShadowHistory,
    pub manuscript_soak_metrics: ManuscriptSoakMetrics,
    pub manuscript_promotion_gate: ManuscriptPromotionGate,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
pub struct ManuscriptAlignmentLabelEntry {
    pub observation_id: String,
    pub sample_id: String,
    pub sample_source: String,
    pub observed_at: DateTime<Utc>,
    pub expected_decision_class: String,
    pub current_policy_decision_class: String,
    pub manuscript_candidate_decision_class: String,
    pub operator_alignment_label: String,
    pub execution_outcome_alignment_label: String,
    pub review_quality_label: String,
    pub promotion_readiness_label: String,
    pub regression: bool,
    pub note: String,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
pub struct ManuscriptAlignmentLabels {
    pub labels_version: String,
    pub manuscript_alignment_labels_id: String,
    pub manuscript_shadow_history_id: String,
    pub manuscript_soak_metrics_id: String,
    pub control_policy_id: String,
    pub manuscript_candidate_policy_id: String,
    #[serde(default)]
    pub source_review_decision_id: Option<String>,
    #[serde(default)]
    pub source_execution_reflection_id: Option<String>,
    pub workstream_id: String,
    pub workspace_id: String,
    pub session_id: String,
    pub generated_at: DateTime<Utc>,
    pub rollout_stage: String,
    pub shadow_sample_count: usize,
    pub operator_alignment_labeled_count: usize,
    pub execution_outcome_alignment_labeled_count: usize,
    pub same_beagle_owned_identity: bool,
    pub labels: Vec<ManuscriptAlignmentLabelEntry>,
    pub note: String,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
pub struct ManuscriptPromotionEvidence {
    pub evidence_version: String,
    pub manuscript_promotion_evidence_id: String,
    pub manuscript_alignment_labels_id: String,
    pub manuscript_shadow_history_id: String,
    pub manuscript_soak_metrics_id: String,
    pub control_policy_id: String,
    pub manuscript_candidate_policy_id: String,
    #[serde(default)]
    pub source_review_decision_id: Option<String>,
    #[serde(default)]
    pub source_execution_reflection_id: Option<String>,
    pub workstream_id: String,
    pub workspace_id: String,
    pub session_id: String,
    pub generated_at: DateTime<Utc>,
    pub rollout_stage: String,
    pub shadow_sample_count: usize,
    pub operator_alignment_aligned_count: usize,
    pub operator_alignment_misaligned_count: usize,
    pub operator_alignment_insufficient_evidence_count: usize,
    pub execution_outcome_alignment_aligned_count: usize,
    pub execution_outcome_alignment_misaligned_count: usize,
    pub execution_outcome_alignment_insufficient_evidence_count: usize,
    pub review_quality_operator_ready_count: usize,
    pub review_quality_needs_edit_count: usize,
    pub review_quality_replan_required_count: usize,
    pub promotion_ready_count: usize,
    pub promotion_hold_count: usize,
    pub promotion_block_count: usize,
    pub operator_alignment_labeled_count: usize,
    pub execution_outcome_alignment_labeled_count: usize,
    pub operator_alignment_label_coverage_basis_points: u16,
    pub execution_outcome_alignment_label_coverage_basis_points: u16,
    pub operator_alignment_basis_points: u16,
    pub execution_outcome_alignment_basis_points: u16,
    pub review_quality_label: String,
    pub promotion_readiness_label: String,
    pub same_beagle_owned_identity: bool,
    pub note: String,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
pub struct ManuscriptAlignmentLabelingBundle {
    pub manuscript_alignment_labels: ManuscriptAlignmentLabels,
    pub manuscript_promotion_evidence: ManuscriptPromotionEvidence,
    pub manuscript_promotion_gate: ManuscriptPromotionGate,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
pub struct ManuscriptAlignmentSignalBundle {
    pub manuscript_shadow_history: ManuscriptShadowHistory,
    pub manuscript_soak_metrics: ManuscriptSoakMetrics,
    pub manuscript_alignment_labels: ManuscriptAlignmentLabels,
    pub manuscript_promotion_evidence: ManuscriptPromotionEvidence,
    pub manuscript_promotion_gate: ManuscriptPromotionGate,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
pub struct ManuscriptTrajectoryQuality {
    pub trajectory_quality_version: String,
    pub manuscript_trajectory_quality_id: String,
    pub manuscript_alignment_labels_id: String,
    pub manuscript_promotion_evidence_id: String,
    pub manuscript_promotion_gate_id: String,
    pub source_trajectory_eval_id: String,
    pub source_execution_reflection_id: String,
    pub source_plan_id: String,
    pub workstream_id: String,
    pub workspace_id: String,
    pub session_id: String,
    pub generated_at: DateTime<Utc>,
    pub rollout_stage: String,
    pub task_family: String,
    pub selected_subagent_id: String,
    pub expected_subagent_id: String,
    pub base_trajectory_quality: String,
    pub base_trajectory_score: u8,
    pub acceptance_criteria_passed: bool,
    pub compiled_context_sufficient: bool,
    pub review_quality_label: String,
    pub editorial_acceptance_fit: String,
    pub trajectory_quality: String,
    pub quality_uplift_required: bool,
    pub same_beagle_owned_identity: bool,
    pub note: String,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
pub struct ManuscriptContextAdequacy {
    pub context_adequacy_version: String,
    pub manuscript_context_adequacy_id: String,
    pub manuscript_trajectory_quality_id: String,
    pub manuscript_promotion_gate_id: String,
    pub source_trajectory_eval_id: String,
    pub source_execution_reflection_id: String,
    pub source_plan_id: String,
    pub workstream_id: String,
    pub workspace_id: String,
    pub session_id: String,
    pub generated_at: DateTime<Utc>,
    pub rollout_stage: String,
    pub task_family: String,
    pub selected_subagent_id: String,
    pub expected_subagent_id: String,
    pub suggested_subagent_id: Option<String>,
    pub suggested_work_mode: Option<String>,
    pub active_retrieval_query_type: String,
    pub active_retrieval_mode: String,
    pub compiled_context_retrieval_query_type: Option<String>,
    pub compiled_context_task_profile: Option<String>,
    pub compiled_context_budget_profile_id: Option<String>,
    pub active_graphrag_query_mode: Option<String>,
    pub compiled_context_graphrag_query_mode: Option<String>,
    pub temporal_truth_view: Option<String>,
    pub compiled_context_sufficient: bool,
    pub context_sufficiency: String,
    pub retrieval_lane_fit: String,
    pub graphrag_mode_fit: String,
    pub truth_view_fit: String,
    pub compiler_profile_fit: String,
    pub task_profile_fit: String,
    pub subagent_fit: String,
    pub handoff_quality: String,
    pub editorial_acceptance_fit: String,
    pub same_beagle_owned_identity: bool,
    pub note: String,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
pub struct ManuscriptTuningRecommendation {
    pub recommendation_version: String,
    pub manuscript_tuning_recommendation_id: String,
    pub manuscript_trajectory_quality_id: String,
    pub manuscript_context_adequacy_id: String,
    pub manuscript_promotion_gate_id: String,
    pub control_policy_id: String,
    pub manuscript_candidate_policy_id: String,
    pub workstream_id: String,
    pub workspace_id: String,
    pub session_id: String,
    pub generated_at: DateTime<Utc>,
    pub rollout_stage: String,
    pub current_promotion_gate_decision: String,
    pub manuscript_must_remain_shadow: bool,
    pub candidate_policy_mode: String,
    pub candidate_tuned_policy_id: String,
    pub candidate_task_family: String,
    pub candidate_selected_subagent_id: String,
    pub candidate_work_mode: String,
    pub candidate_retrieval_query_type: String,
    pub candidate_compiler_profile_id: String,
    pub candidate_graphrag_query_mode: String,
    pub candidate_temporal_truth_view: String,
    pub candidate_context_task_profile: String,
    pub candidate_context_budget_profile_id: String,
    pub candidate_handoff_package: String,
    pub candidate_assembly_package: String,
    pub editorial_acceptance_target: String,
    pub next_validation_mode: String,
    pub promotion_readiness_label: String,
    pub recommended_changes: Vec<String>,
    pub highest_impact_fix: String,
    pub same_beagle_owned_identity: bool,
    pub note: String,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
pub struct ManuscriptQualityUpliftBundle {
    pub manuscript_trajectory_quality: ManuscriptTrajectoryQuality,
    pub manuscript_context_adequacy: ManuscriptContextAdequacy,
    pub manuscript_tuning_recommendation: ManuscriptTuningRecommendation,
}

#[derive(Debug, Clone)]
struct CalibrationCase {
    sample_id: String,
    sample_source: String,
    input: RiskEvaluationInput,
    trajectory_score: u8,
    recipe_kind: Option<String>,
    experiment_id: Option<String>,
    expected_decision_class: String,
    operator_alignment_observed: Option<bool>,
    execution_alignment_observed: Option<bool>,
    continued_successfully: Option<bool>,
    outcome_source: String,
    shadow_scenario: Option<String>,
    note: String,
}

#[derive(Default)]
struct SignalCounts {
    matched_count: usize,
    risk_count: usize,
    auto_continue_count: usize,
    review_required_count: usize,
    blocked_count: usize,
}

#[derive(Copy, Clone)]
enum AlignmentLens {
    OperatorDecision,
    ExecutionOutcome,
}

#[derive(Copy, Clone)]
enum AnalysisHistoryDecisionLens {
    Current,
    Candidate,
}

#[derive(Copy, Clone)]
enum AnalysisHistoryObservedLens {
    OperatorDecision,
    ExecutionOutcome,
}

#[derive(Copy, Clone)]
enum ManuscriptHistoryDecisionLens {
    Current,
    Candidate,
}

#[derive(Copy, Clone)]
enum ManuscriptHistoryObservedLens {
    OperatorDecision,
    ExecutionOutcome,
}

pub fn build_autonomy_policy_calibration_bundle(
    policy: &AutonomyPolicy,
    execution_plan: &ExecutionPlan,
    follow_on_plan: &FollowOnPlan,
    review_decision: &ReviewDecision,
    reflection: &ExecutionReflection,
    trajectory_eval: &TrajectoryEval,
    replan_suggestion: &ReplanSuggestion,
    approval_gating_decision: Option<&ApprovalGatingDecision>,
    continuation_state: Option<&ContinuationStatePlane>,
    continuation_receipt: Option<&ContinuationReceipt>,
) -> AutonomyPolicyCalibrationBundle {
    let generated_at = Utc::now();
    let dataset = build_calibration_dataset(
        policy,
        execution_plan,
        follow_on_plan,
        review_decision,
        reflection,
        trajectory_eval,
        replan_suggestion,
        approval_gating_decision,
        continuation_state,
        continuation_receipt,
        generated_at,
    );
    let report = build_eval_report(&dataset, generated_at);
    let thresholds = build_escalation_thresholds(policy, &dataset, &report, generated_at);
    let shadow_policy_comparison =
        build_shadow_policy_comparison(policy, &dataset, &thresholds, generated_at);
    let updated_policy_recommendation = build_updated_policy_recommendation(
        &report,
        &thresholds,
        &shadow_policy_comparison,
        generated_at,
    );

    AutonomyPolicyCalibrationBundle {
        calibration_dataset: dataset,
        policy_eval_report: report,
        escalation_thresholds: thresholds,
        shadow_policy_comparison,
        updated_policy_recommendation,
    }
}

pub fn build_guarded_policy_rollout_bundle(
    policy: &AutonomyPolicy,
    calibration_bundle: &AutonomyPolicyCalibrationBundle,
) -> GuardedPolicyRolloutBundle {
    let generated_at = Utc::now();
    let current_policy = build_current_shadow_threshold(
        policy,
        &calibration_bundle.calibration_dataset,
        &calibration_bundle.policy_eval_report,
        &calibration_bundle.escalation_thresholds,
        generated_at,
    );
    let candidate_policy = build_candidate_shadow_threshold(
        policy,
        &calibration_bundle.calibration_dataset,
        &calibration_bundle.policy_eval_report,
        &calibration_bundle.escalation_thresholds,
        generated_at,
    );
    let rollout_metrics = build_rollout_metrics(
        &calibration_bundle.calibration_dataset,
        &current_policy,
        &candidate_policy,
        &calibration_bundle.shadow_policy_comparison,
        generated_at,
    );
    let rollout_decision = build_guarded_rollout_decision(
        &current_policy,
        &candidate_policy,
        &rollout_metrics,
        &calibration_bundle.updated_policy_recommendation,
        generated_at,
    );

    GuardedPolicyRolloutBundle {
        autonomy_policy_current: current_policy,
        autonomy_policy_candidate: candidate_policy,
        rollout_metrics,
        rollout_decision,
    }
}

pub fn build_implementation_canary_autonomy_bundle(
    policy: &AutonomyPolicy,
    rollout_bundle: &GuardedPolicyRolloutBundle,
) -> ImplementationCanaryAutonomyBundle {
    let generated_at = Utc::now();
    let control_policy = build_canary_control_policy(policy, rollout_bundle);
    let canary_policy = build_canary_implementation_policy(policy, rollout_bundle, &control_policy);
    let canary_rollout_metrics = build_canary_rollout_metrics(
        rollout_bundle,
        &control_policy,
        &canary_policy,
        generated_at,
    );
    let canary_rollback_decision = build_canary_rollback_decision(
        rollout_bundle,
        &control_policy,
        &canary_policy,
        &canary_rollout_metrics,
        generated_at,
    );

    ImplementationCanaryAutonomyBundle {
        autonomy_policy_control: control_policy,
        autonomy_policy_canary: canary_policy,
        canary_rollout_metrics,
        canary_rollback_decision,
    }
}

pub fn build_analysis_shadow_calibration_bundle(
    rollout_bundle: &GuardedPolicyRolloutBundle,
    calibration_bundle: &AutonomyPolicyCalibrationBundle,
    canary_bundle: &ImplementationCanaryAutonomyBundle,
) -> AnalysisShadowCalibrationBundle {
    let generated_at = Utc::now();
    let control_policy = canary_bundle.autonomy_policy_control.clone();
    let analysis_candidate_policy =
        build_analysis_candidate_policy(rollout_bundle, &control_policy);
    let analysis_shadow_comparison = build_analysis_shadow_comparison(
        &calibration_bundle.calibration_dataset,
        &control_policy,
        &analysis_candidate_policy,
        &canary_bundle.canary_rollout_metrics,
        &canary_bundle.canary_rollback_decision,
        generated_at,
    );
    let analysis_rollout_metrics = build_analysis_rollout_metrics(
        &calibration_bundle.calibration_dataset,
        &control_policy,
        &analysis_candidate_policy,
        canary_bundle,
        &analysis_shadow_comparison,
        generated_at,
    );
    let analysis_rollout_decision = build_analysis_rollout_decision(
        &control_policy,
        &analysis_candidate_policy,
        &canary_bundle.canary_rollout_metrics,
        &canary_bundle.canary_rollback_decision,
        &analysis_shadow_comparison,
        &analysis_rollout_metrics,
        generated_at,
    );

    AnalysisShadowCalibrationBundle {
        autonomy_policy_control: control_policy,
        autonomy_policy_analysis_candidate: analysis_candidate_policy,
        analysis_shadow_comparison,
        analysis_rollout_metrics,
        analysis_rollout_decision,
    }
}

pub fn build_analysis_shadow_soak_bundle(
    calibration_bundle: &AutonomyPolicyCalibrationBundle,
    analysis_bundle: &AnalysisShadowCalibrationBundle,
    previous_soak: Option<&AnalysisShadowSoak>,
) -> AnalysisShadowSoakBundle {
    let generated_at = Utc::now();
    let analysis_shadow_history = build_analysis_shadow_soak(
        calibration_bundle,
        analysis_bundle,
        previous_soak,
        generated_at,
    );
    let analysis_soak_metrics =
        build_analysis_soak_metrics(&analysis_shadow_history, generated_at);
    let analysis_promotion_gate = build_analysis_promotion_gate(
        &analysis_shadow_history,
        &analysis_soak_metrics,
        generated_at,
    );

    AnalysisShadowSoakBundle {
        analysis_shadow_history,
        analysis_soak_metrics,
        analysis_promotion_gate,
    }
}

pub fn build_analysis_sample_accumulation_bundle(
    calibration_bundle: &AutonomyPolicyCalibrationBundle,
    analysis_bundle: &AnalysisShadowCalibrationBundle,
    previous_soak: &AnalysisShadowSoak,
) -> AnalysisSampleAccumulationBundle {
    let generated_at = Utc::now();
    let analysis_shadow_history = build_analysis_sample_accumulation(
        calibration_bundle,
        analysis_bundle,
        previous_soak,
        generated_at,
    );
    let analysis_soak_metrics =
        build_analysis_soak_metrics(&analysis_shadow_history, generated_at);
    let analysis_promotion_gate = build_analysis_promotion_gate_with_version(
        &analysis_shadow_history,
        &analysis_soak_metrics,
        generated_at,
        ANALYSIS_PROMOTION_GATE_RECHECK_VERSION,
        "B24.12 re-runs the analysis promotion gate after bounded sample accumulation so the next decision stays auditable: keep-shadow if evidence is still insufficient, stage-analysis-canary only if thresholds are met, and rollback-shadow if the recheck regresses.",
    );

    AnalysisSampleAccumulationBundle {
        analysis_shadow_history,
        analysis_soak_metrics,
        analysis_promotion_gate,
    }
}

pub fn build_analysis_canary_activation_bundle(
    canary_bundle: &ImplementationCanaryAutonomyBundle,
    analysis_bundle: &AnalysisShadowCalibrationBundle,
    accumulation_bundle: &AnalysisSampleAccumulationBundle,
) -> AnalysisCanaryActivationBundle {
    let generated_at = Utc::now();
    let control_policy = build_analysis_canary_control_policy(&canary_bundle.autonomy_policy_control);
    let implementation_canary = build_retained_implementation_canary_policy(
        &canary_bundle.autonomy_policy_canary,
    );
    let analysis_canary = build_analysis_live_canary_policy(
        &control_policy,
        &analysis_bundle.autonomy_policy_analysis_candidate,
        &accumulation_bundle.analysis_promotion_gate,
    );
    let analysis_canary_metrics = build_analysis_canary_metrics(
        canary_bundle,
        analysis_bundle,
        &accumulation_bundle.analysis_shadow_history,
        &accumulation_bundle.analysis_soak_metrics,
        &accumulation_bundle.analysis_promotion_gate,
        &control_policy,
        &implementation_canary,
        &analysis_canary,
        generated_at,
    );
    let analysis_canary_rollback_decision = build_analysis_canary_rollback_decision(
        &accumulation_bundle.analysis_promotion_gate,
        &control_policy,
        &implementation_canary,
        &analysis_canary,
        &analysis_canary_metrics,
        generated_at,
    );

    AnalysisCanaryActivationBundle {
        autonomy_policy_control: control_policy,
        autonomy_policy_implementation_canary: implementation_canary,
        autonomy_policy_analysis_canary: analysis_canary,
        analysis_canary_metrics,
        analysis_canary_rollback_decision,
    }
}

pub fn build_manuscript_shadow_calibration_bundle(
    rollout_bundle: &GuardedPolicyRolloutBundle,
    calibration_bundle: &AutonomyPolicyCalibrationBundle,
    analysis_canary_bundle: &AnalysisCanaryActivationBundle,
) -> ManuscriptShadowCalibrationBundle {
    let generated_at = Utc::now();
    let control_policy = analysis_canary_bundle.autonomy_policy_control.clone();
    let manuscript_candidate_policy =
        build_manuscript_candidate_policy(rollout_bundle, &control_policy);
    let manuscript_shadow_comparison = build_manuscript_shadow_comparison(
        &calibration_bundle.calibration_dataset,
        &control_policy,
        &manuscript_candidate_policy,
        &analysis_canary_bundle.analysis_canary_metrics,
        &analysis_canary_bundle.analysis_canary_rollback_decision,
        generated_at,
    );
    let manuscript_rollout_metrics = build_manuscript_rollout_metrics(
        &calibration_bundle.calibration_dataset,
        &control_policy,
        &manuscript_candidate_policy,
        analysis_canary_bundle,
        &manuscript_shadow_comparison,
        generated_at,
    );
    let manuscript_rollout_decision = build_manuscript_rollout_decision(
        &control_policy,
        &manuscript_candidate_policy,
        &analysis_canary_bundle.analysis_canary_metrics,
        &analysis_canary_bundle.analysis_canary_rollback_decision,
        &manuscript_shadow_comparison,
        &manuscript_rollout_metrics,
        generated_at,
    );

    ManuscriptShadowCalibrationBundle {
        autonomy_policy_control: control_policy,
        autonomy_policy_manuscript_candidate: manuscript_candidate_policy,
        manuscript_shadow_comparison,
        manuscript_rollout_metrics,
        manuscript_rollout_decision,
    }
}

pub fn build_manuscript_sample_accumulation_bundle(
    calibration_bundle: &AutonomyPolicyCalibrationBundle,
    manuscript_bundle: &ManuscriptShadowCalibrationBundle,
    previous_history: Option<&ManuscriptShadowHistory>,
) -> ManuscriptSampleAccumulationBundle {
    let generated_at = Utc::now();
    let manuscript_shadow_history = build_manuscript_sample_accumulation(
        calibration_bundle,
        manuscript_bundle,
        previous_history,
        generated_at,
    );
    let manuscript_soak_metrics =
        build_manuscript_soak_metrics(&manuscript_shadow_history, generated_at);
    let manuscript_promotion_gate = build_manuscript_promotion_gate_with_version(
        &manuscript_shadow_history,
        &manuscript_soak_metrics,
        None,
        generated_at,
        MANUSCRIPT_PROMOTION_GATE_RECHECK_VERSION,
        "B24.15 re-runs the manuscript promotion gate after bounded sample accumulation so the next decision stays auditable: keep-shadow if evidence is still insufficient, stage-manuscript-canary only if thresholds are met, and rollback-shadow if the recheck regresses.",
    );

    ManuscriptSampleAccumulationBundle {
        manuscript_shadow_history,
        manuscript_soak_metrics,
        manuscript_promotion_gate,
    }
}

pub fn build_manuscript_alignment_labeling_bundle(
    accumulation_bundle: &ManuscriptSampleAccumulationBundle,
    review_decision: Option<&ReviewDecision>,
    execution_reflection: Option<&ExecutionReflection>,
) -> ManuscriptAlignmentLabelingBundle {
    let generated_at = Utc::now();
    let manuscript_alignment_labels = build_manuscript_alignment_labels_with_version(
        &accumulation_bundle.manuscript_shadow_history,
        &accumulation_bundle.manuscript_soak_metrics,
        review_decision,
        execution_reflection,
        MANUSCRIPT_ALIGNMENT_LABEL_VERSION,
        MANUSCRIPT_ALIGNMENT_LABELING_STAGE_STATE,
        "B24.16 binds explicit manuscript alignment labels back to the same Beagle-owned workstream/workspace/session identity so promotion can reason about aligned, misaligned, and insufficient-evidence cases directly.",
        generated_at,
    );
    let manuscript_promotion_evidence = build_manuscript_promotion_evidence(
        &manuscript_alignment_labels,
        generated_at,
    );
    let manuscript_promotion_gate = build_manuscript_promotion_gate_with_version(
        &accumulation_bundle.manuscript_shadow_history,
        &accumulation_bundle.manuscript_soak_metrics,
        Some(&manuscript_promotion_evidence),
        generated_at,
        MANUSCRIPT_PROMOTION_GATE_RECHECK_VERSION,
        "B24.16 enriches the manuscript promotion gate with explicit operator/execution alignment labels so promotion can depend on auditable evidence coverage instead of bounded sample count alone.",
    );

    ManuscriptAlignmentLabelingBundle {
        manuscript_alignment_labels,
        manuscript_promotion_evidence,
        manuscript_promotion_gate,
    }
}

pub fn build_manuscript_alignment_signal_bundle(
    accumulation_bundle: &ManuscriptSampleAccumulationBundle,
    review_decision: Option<&ReviewDecision>,
    execution_reflection: Option<&ExecutionReflection>,
    follow_on_plan: Option<&FollowOnPlan>,
) -> ManuscriptAlignmentSignalBundle {
    let generated_at = Utc::now();
    let manuscript_shadow_history = build_manuscript_alignment_signal_history(
        &accumulation_bundle.manuscript_shadow_history,
        review_decision,
        execution_reflection,
        follow_on_plan,
        generated_at,
    );
    let manuscript_soak_metrics =
        build_manuscript_soak_metrics(&manuscript_shadow_history, generated_at);
    let manuscript_alignment_labels = build_manuscript_alignment_labels_with_version(
        &manuscript_shadow_history,
        &manuscript_soak_metrics,
        review_decision,
        execution_reflection,
        MANUSCRIPT_ALIGNMENT_SIGNAL_VERSION,
        MANUSCRIPT_ALIGNMENT_SIGNAL_STAGE_STATE,
        "B24.17 refreshes bounded manuscript alignment labels with explicit signal acquisition so the promotion gate can reason about real operator/execution evidence instead of sample count alone.",
        generated_at,
    );
    let manuscript_promotion_evidence = build_manuscript_promotion_evidence(
        &manuscript_alignment_labels,
        generated_at,
    );
    let manuscript_promotion_gate = build_manuscript_promotion_gate_with_version(
        &manuscript_shadow_history,
        &manuscript_soak_metrics,
        Some(&manuscript_promotion_evidence),
        generated_at,
        MANUSCRIPT_PROMOTION_GATE_RECHECK_VERSION,
        "B24.17 re-runs the manuscript promotion gate after bounded alignment signal acquisition so manuscript stays shadow-only until explicit evidence is both sufficient and promotion-worthy.",
    );

    ManuscriptAlignmentSignalBundle {
        manuscript_shadow_history,
        manuscript_soak_metrics,
        manuscript_alignment_labels,
        manuscript_promotion_evidence,
        manuscript_promotion_gate,
    }
}

pub fn build_manuscript_quality_uplift_bundle(
    alignment_bundle: &ManuscriptAlignmentSignalBundle,
    execution_plan: &ExecutionPlan,
    trajectory_eval: &TrajectoryEval,
    execution_reflection: &ExecutionReflection,
    context_packet: &WorkstreamContextPacket,
) -> ManuscriptQualityUpliftBundle {
    let generated_at = Utc::now();
    let manuscript_trajectory_quality = build_manuscript_trajectory_quality(
        alignment_bundle,
        execution_plan,
        trajectory_eval,
        execution_reflection,
        generated_at,
    );
    let manuscript_context_adequacy = build_manuscript_context_adequacy(
        &manuscript_trajectory_quality,
        &alignment_bundle.manuscript_promotion_gate,
        execution_plan,
        trajectory_eval,
        execution_reflection,
        context_packet,
        generated_at,
    );
    let manuscript_tuning_recommendation = build_manuscript_tuning_recommendation(
        &manuscript_trajectory_quality,
        &manuscript_context_adequacy,
        &alignment_bundle.manuscript_promotion_gate,
        generated_at,
    );

    ManuscriptQualityUpliftBundle {
        manuscript_trajectory_quality,
        manuscript_context_adequacy,
        manuscript_tuning_recommendation,
    }
}

fn build_calibration_dataset(
    policy: &AutonomyPolicy,
    execution_plan: &ExecutionPlan,
    follow_on_plan: &FollowOnPlan,
    review_decision: &ReviewDecision,
    reflection: &ExecutionReflection,
    trajectory_eval: &TrajectoryEval,
    replan_suggestion: &ReplanSuggestion,
    approval_gating_decision: Option<&ApprovalGatingDecision>,
    continuation_state: Option<&ContinuationStatePlane>,
    continuation_receipt: Option<&ContinuationReceipt>,
    generated_at: DateTime<Utc>,
) -> AutonomyCalibrationDataset {
    let replay_expected_decision_class = if replan_suggestion.replan_required {
        "blocked".to_string()
    } else if review_decision.decision_action == "approved"
        && continuation_succeeded(continuation_state, continuation_receipt)
    {
        "auto-continue".to_string()
    } else {
        "review-required".to_string()
    };
    let replay_policy_alignment = approval_gating_decision
        .map(|decision| decision.decision_class == replay_expected_decision_class)
        .or(Some(false));
    let replay_execution_alignment = Some(
        (replay_expected_decision_class == "auto-continue"
            && continuation_succeeded(continuation_state, continuation_receipt))
            || (replay_expected_decision_class != "auto-continue"
                && !continuation_succeeded(continuation_state, continuation_receipt)),
    );
    let base_plan = &follow_on_plan.execution_plan;
    let replay_case = CalibrationCase {
        sample_id: "replay-analysis-live-auto-continue".to_string(),
        sample_source: "replay-observed".to_string(),
        input: RiskEvaluationInput {
            task_family: base_plan.task_family.clone(),
            selected_subagent_id: base_plan.selected_subagent_id.clone(),
            retrieval_query_type: base_plan.retrieval_query_type.clone(),
            compiler_profile_id: base_plan.compiler_profile_id.clone(),
            graphrag_query_mode: base_plan.graphrag_query_mode.clone(),
            temporal_truth_view: base_plan.temporal_truth_view.clone(),
            trajectory_quality: trajectory_eval.trajectory_quality.clone(),
            overall_quality_score: reflection.overall_quality_score,
            replan_required: replan_suggestion.replan_required,
            requested_operator_action: replan_suggestion.requested_operator_action.clone(),
            review_action: review_decision.decision_action.clone(),
        },
        trajectory_score: trajectory_eval.trajectory_score,
        recipe_kind: recipe_kind(base_plan),
        experiment_id: experiment_id(base_plan, execution_plan),
        expected_decision_class: replay_expected_decision_class,
        operator_alignment_observed: replay_policy_alignment,
        execution_alignment_observed: replay_execution_alignment,
        continued_successfully: Some(continuation_succeeded(continuation_state, continuation_receipt)),
        outcome_source: "observed-review-and-continuation".to_string(),
        shadow_scenario: None,
        note: "Replay the live B24.6 follow-on execution and compare the current gate against the observed approve->dispatch->succeeded continuation outcome.".to_string(),
    };
    let shadow_analysis_review_case = CalibrationCase {
        sample_id: "shadow-analysis-review-required".to_string(),
        sample_source: "shadow-staged".to_string(),
        input: RiskEvaluationInput {
            task_family: "analysis".to_string(),
            selected_subagent_id: "experiments".to_string(),
            retrieval_query_type: "general".to_string(),
            compiler_profile_id: "b235-budget-analysis".to_string(),
            graphrag_query_mode: "global".to_string(),
            temporal_truth_view: "both".to_string(),
            trajectory_quality: "adequate".to_string(),
            overall_quality_score: 84,
            replan_required: false,
            requested_operator_action: "review-and-approve-follow-on-plan".to_string(),
            review_action: "approved".to_string(),
        },
        trajectory_score: 82,
        recipe_kind: Some("operator_cpu_loop".to_string()),
        experiment_id: experiment_id(base_plan, execution_plan),
        expected_decision_class: "review-required".to_string(),
        operator_alignment_observed: None,
        execution_alignment_observed: None,
        continued_successfully: None,
        outcome_source: "shadow-calibration-scenario".to_string(),
        shadow_scenario: Some(
            "analysis quality dips below the auto lane but stays above the hard block floor"
                .to_string(),
        ),
        note: "Shadow the current analysis lane with adequate trajectory and sub-90 quality so the policy should require review instead of auto-continuing.".to_string(),
    };
    let shadow_implementation_auto_case = CalibrationCase {
        sample_id: "shadow-implementation-auto-candidate".to_string(),
        sample_source: "shadow-staged".to_string(),
        input: RiskEvaluationInput {
            task_family: "implementation".to_string(),
            selected_subagent_id: "core".to_string(),
            retrieval_query_type: "code".to_string(),
            compiler_profile_id: "b235-budget-implementation".to_string(),
            graphrag_query_mode: "local".to_string(),
            temporal_truth_view: "current".to_string(),
            trajectory_quality: "good".to_string(),
            overall_quality_score: 97,
            replan_required: false,
            requested_operator_action: "review-and-approve-follow-on-plan".to_string(),
            review_action: "approved".to_string(),
        },
        trajectory_score: 96,
        recipe_kind: Some("repo_native_dev_loop".to_string()),
        experiment_id: None,
        expected_decision_class: "auto-continue".to_string(),
        operator_alignment_observed: None,
        execution_alignment_observed: None,
        continued_successfully: None,
        outcome_source: "shadow-calibration-scenario".to_string(),
        shadow_scenario: Some(
            "repo-native implementation loop with high-quality code retrieval and no replan signal"
                .to_string(),
        ),
        note: "Shadow a high-quality implementation loop to test whether the current B24.6 policy is too conservative outside the original analysis lane.".to_string(),
    };
    let shadow_manuscript_blocked_case = CalibrationCase {
        sample_id: "shadow-manuscript-blocked".to_string(),
        sample_source: "shadow-staged".to_string(),
        input: RiskEvaluationInput {
            task_family: "manuscript".to_string(),
            selected_subagent_id: "manuscript".to_string(),
            retrieval_query_type: "general".to_string(),
            compiler_profile_id: "b235-budget-manuscript".to_string(),
            graphrag_query_mode: "global".to_string(),
            temporal_truth_view: "both".to_string(),
            trajectory_quality: "needs-replan".to_string(),
            overall_quality_score: 68,
            replan_required: true,
            requested_operator_action: "review-stop-and-replan".to_string(),
            review_action: "approved".to_string(),
        },
        trajectory_score: 65,
        recipe_kind: Some("repo_native_dev_loop".to_string()),
        experiment_id: experiment_id(base_plan, execution_plan),
        expected_decision_class: "blocked".to_string(),
        operator_alignment_observed: None,
        execution_alignment_observed: None,
        continued_successfully: None,
        outcome_source: "shadow-calibration-scenario".to_string(),
        shadow_scenario: Some(
            "manuscript support loop with degraded trajectory and explicit replan requirement"
                .to_string(),
        ),
        note: "Shadow a manuscript lane that should block because the trajectory degraded and the operator is already being asked to stop and replan.".to_string(),
    };

    let samples = vec![
        sample_from_case(
            policy,
            &follow_on_plan.source_execution_id,
            &follow_on_plan.source_plan_id,
            &follow_on_plan.workstream_id,
            &follow_on_plan.workspace_id,
            &follow_on_plan.session_id,
            replay_case,
        ),
        sample_from_case(
            policy,
            &follow_on_plan.source_execution_id,
            &follow_on_plan.source_plan_id,
            &follow_on_plan.workstream_id,
            &follow_on_plan.workspace_id,
            &follow_on_plan.session_id,
            shadow_analysis_review_case,
        ),
        sample_from_case(
            policy,
            &follow_on_plan.source_execution_id,
            &follow_on_plan.source_plan_id,
            &follow_on_plan.workstream_id,
            &follow_on_plan.workspace_id,
            &follow_on_plan.session_id,
            shadow_implementation_auto_case,
        ),
        sample_from_case(
            policy,
            &follow_on_plan.source_execution_id,
            &follow_on_plan.source_plan_id,
            &follow_on_plan.workstream_id,
            &follow_on_plan.workspace_id,
            &follow_on_plan.session_id,
            shadow_manuscript_blocked_case,
        ),
    ];
    let task_families_evaluated = unique_values(samples.iter().map(|sample| sample.task_family.clone()));
    let decision_classes_evaluated =
        unique_values(samples.iter().map(|sample| sample.expected_decision_class.clone()));
    let replay_sample_count = samples
        .iter()
        .filter(|sample| sample.sample_source == "replay-observed")
        .count();
    let shadow_sample_count = samples.len().saturating_sub(replay_sample_count);

    AutonomyCalibrationDataset {
        dataset_version: AUTONOMY_CALIBRATION_DATASET_VERSION.to_string(),
        dataset_id: format!("{}-autonomy-calibration", follow_on_plan.follow_on_plan_id),
        policy_id: policy.policy_id.clone(),
        source_execution_id: follow_on_plan.source_execution_id.clone(),
        source_plan_id: follow_on_plan.source_plan_id.clone(),
        workstream_id: follow_on_plan.workstream_id.clone(),
        workspace_id: follow_on_plan.workspace_id.clone(),
        session_id: follow_on_plan.session_id.clone(),
        generated_at,
        sample_count: samples.len(),
        replay_sample_count,
        shadow_sample_count,
        task_families_evaluated,
        decision_classes_evaluated,
        samples,
        note: "B24.7 calibration replays the live B24.6 case and adds shadow task-family probes so Beagle can measure whether the current gate is too permissive, too conservative, or correctly calibrated before changing any live threshold.".to_string(),
    }
}

fn build_eval_report(
    dataset: &AutonomyCalibrationDataset,
    generated_at: DateTime<Utc>,
) -> AutonomyPolicyEvalReport {
    let false_auto_continue_rate_basis_points =
        false_rate_basis_points(&dataset.samples, "auto-continue");
    let false_review_required_rate_basis_points =
        false_rate_basis_points(&dataset.samples, "review-required");
    let false_blocked_rate_basis_points = false_rate_basis_points(&dataset.samples, "blocked");
    let operator_alignment_rate_basis_points = alignment_rate_basis_points(
        dataset
            .samples
            .iter()
            .filter_map(|sample| sample.operator_alignment_observed),
    );
    let execution_alignment_rate_basis_points = alignment_rate_basis_points(
        dataset
            .samples
            .iter()
            .filter_map(|sample| sample.execution_alignment_observed),
    );
    let task_family_summaries = dataset
        .task_families_evaluated
        .iter()
        .map(|task_family| task_family_summary(&dataset.samples, task_family))
        .collect::<Vec<_>>();
    let policy_posture = if false_auto_continue_rate_basis_points > 0 {
        "too-permissive".to_string()
    } else if false_review_required_rate_basis_points > 0 {
        "too-conservative".to_string()
    } else {
        "correctly-calibrated".to_string()
    };

    AutonomyPolicyEvalReport {
        report_version: AUTONOMY_POLICY_EVAL_REPORT_VERSION.to_string(),
        report_id: format!("{}-policy-eval-report", dataset.dataset_id),
        dataset_id: dataset.dataset_id.clone(),
        policy_id: dataset.policy_id.clone(),
        workstream_id: dataset.workstream_id.clone(),
        workspace_id: dataset.workspace_id.clone(),
        session_id: dataset.session_id.clone(),
        generated_at,
        stage_state: SHADOW_STAGE_STATE.to_string(),
        evaluated_sample_count: dataset.sample_count,
        replay_sample_count: dataset.replay_sample_count,
        shadow_sample_count: dataset.shadow_sample_count,
        false_auto_continue_rate_basis_points,
        false_review_required_rate_basis_points,
        false_blocked_rate_basis_points,
        operator_alignment_rate_basis_points,
        execution_alignment_rate_basis_points,
        policy_posture,
        decision_class_coverage: dataset.decision_classes_evaluated.clone(),
        task_family_summaries,
        signal_importance: signal_importance(&dataset.samples),
        note: "B24.7 policy eval keeps calibration bounded and operator-auditable: compare the current B24.6 gate against replayed and shadow-labeled outcomes, then report miscalibration without changing the live policy.".to_string(),
    }
}

fn build_escalation_thresholds(
    policy: &AutonomyPolicy,
    dataset: &AutonomyCalibrationDataset,
    report: &AutonomyPolicyEvalReport,
    generated_at: DateTime<Utc>,
) -> EscalationThresholds {
    let thresholds = vec![
        threshold_for_analysis(policy),
        threshold_for_implementation(dataset),
        threshold_for_manuscript(dataset),
    ];

    EscalationThresholds {
        thresholds_version: ESCALATION_THRESHOLD_VERSION.to_string(),
        escalation_thresholds_id: format!("{}-escalation-thresholds", dataset.dataset_id),
        dataset_id: dataset.dataset_id.clone(),
        eval_report_id: report.report_id.clone(),
        policy_id: dataset.policy_id.clone(),
        workstream_id: dataset.workstream_id.clone(),
        workspace_id: dataset.workspace_id.clone(),
        session_id: dataset.session_id.clone(),
        generated_at,
        stage_state: SHADOW_STAGE_STATE.to_string(),
        thresholds,
        note: "B24.7 stages per-task-family thresholds in shadow mode first so implementation, analysis, and manuscript lanes can be calibrated independently without mutating the live B24.6 gate.".to_string(),
    }
}

fn build_shadow_policy_comparison(
    _policy: &AutonomyPolicy,
    dataset: &AutonomyCalibrationDataset,
    thresholds: &EscalationThresholds,
    generated_at: DateTime<Utc>,
) -> ShadowPolicyComparison {
    let mut improved_alignment_count = 0usize;
    let mut regression_count = 0usize;
    let mut samples = Vec::new();

    for sample in &dataset.samples {
        let shadow_policy_decision_class = evaluate_shadow_threshold(sample, thresholds);
        let current_correct = sample.current_policy_decision_class == sample.expected_decision_class;
        let shadow_correct = shadow_policy_decision_class == sample.expected_decision_class;
        let improved_alignment = !current_correct && shadow_correct;
        let regression = current_correct && !shadow_correct;
        if improved_alignment {
            improved_alignment_count += 1;
        }
        if regression {
            regression_count += 1;
        }
        samples.push(ShadowPolicyComparisonEntry {
            sample_id: sample.sample_id.clone(),
            task_family: sample.task_family.clone(),
            sample_source: sample.sample_source.clone(),
            expected_decision_class: sample.expected_decision_class.clone(),
            current_policy_decision_class: sample.current_policy_decision_class.clone(),
            shadow_policy_decision_class,
            improved_alignment,
            regression,
            note: if improved_alignment {
                "Shadow thresholds improve alignment on this sample without changing the live gate."
                    .to_string()
            } else if regression {
                "Shadow thresholds would regress this sample and therefore remain non-live."
                    .to_string()
            } else {
                "Shadow thresholds leave this sample aligned with the current bounded policy."
                    .to_string()
            },
        });
    }
    let unchanged_alignment_count =
        samples.len().saturating_sub(improved_alignment_count + regression_count);

    ShadowPolicyComparison {
        comparison_version: SHADOW_POLICY_COMPARISON_VERSION.to_string(),
        shadow_policy_comparison_id: format!("{}-shadow-policy-comparison", dataset.dataset_id),
        dataset_id: dataset.dataset_id.clone(),
        escalation_thresholds_id: thresholds.escalation_thresholds_id.clone(),
        policy_id: dataset.policy_id.clone(),
        workstream_id: dataset.workstream_id.clone(),
        workspace_id: dataset.workspace_id.clone(),
        session_id: dataset.session_id.clone(),
        generated_at,
        stage_state: SHADOW_STAGE_STATE.to_string(),
        compared_sample_count: samples.len(),
        improved_alignment_count,
        unchanged_alignment_count,
        regression_count,
        samples,
        note: "B24.7 shadow comparison checks whether the staged threshold recommendations would improve calibration before any live autonomy policy change is allowed.".to_string(),
    }
}

fn build_updated_policy_recommendation(
    report: &AutonomyPolicyEvalReport,
    thresholds: &EscalationThresholds,
    shadow_policy_comparison: &ShadowPolicyComparison,
    generated_at: DateTime<Utc>,
) -> UpdatedPolicyRecommendation {
    let recommended_action = if shadow_policy_comparison.improved_alignment_count > 0
        && shadow_policy_comparison.regression_count == 0
    {
        "stage-shadow-threshold-update".to_string()
    } else {
        "keep-current-policy-and-monitor".to_string()
    };
    let task_family_updates = thresholds
        .thresholds
        .iter()
        .map(|threshold| PolicyTaskFamilyUpdateRecommendation {
            task_family: threshold.task_family.clone(),
            current_policy_posture: if threshold.task_family == "analysis" {
                "current-live-lane".to_string()
            } else if threshold.auto_continue_enabled {
                "too-conservative-under-current-policy".to_string()
            } else {
                "manual-or-blocked".to_string()
            },
            recommended_action: threshold.recommended_action.clone(),
            stage_state: threshold.stage_state.clone(),
            rationale: threshold.rationale.clone(),
        })
        .collect::<Vec<_>>();

    UpdatedPolicyRecommendation {
        recommendation_version: UPDATED_POLICY_RECOMMENDATION_VERSION.to_string(),
        updated_policy_recommendation_id: format!(
            "{}-updated-policy-recommendation",
            report.dataset_id
        ),
        policy_id: report.policy_id.clone(),
        dataset_id: report.dataset_id.clone(),
        eval_report_id: report.report_id.clone(),
        escalation_thresholds_id: thresholds.escalation_thresholds_id.clone(),
        shadow_policy_comparison_id: shadow_policy_comparison.shadow_policy_comparison_id.clone(),
        workstream_id: report.workstream_id.clone(),
        workspace_id: report.workspace_id.clone(),
        session_id: report.session_id.clone(),
        generated_at,
        stage_state: SHADOW_STAGE_STATE.to_string(),
        policy_posture: report.policy_posture.clone(),
        recommended_action,
        safe_to_apply_live: false,
        rollout_guardrails: vec![
            "do not mutate the live B24.6 policy directly from calibration output".to_string(),
            "require operator review of shadow-policy-comparison before any threshold change"
                .to_string(),
            "promote only one task-family threshold change at a time".to_string(),
            "re-run B24.7 smoke and validator after any staged threshold edit".to_string(),
        ],
        task_family_updates,
        note: "B24.7 keeps policy updates staged and bounded: the recommendation is shadow-only, operator-reviewed, and never becomes a free-running autonomy loop.".to_string(),
    }
}

fn build_current_shadow_threshold(
    policy: &AutonomyPolicy,
    dataset: &AutonomyCalibrationDataset,
    report: &AutonomyPolicyEvalReport,
    thresholds: &EscalationThresholds,
    generated_at: DateTime<Utc>,
) -> AutonomyShadowThreshold {
    AutonomyShadowThreshold {
        shadow_threshold_version: AUTONOMY_SHADOW_THRESHOLD_VERSION.to_string(),
        shadow_threshold_id: format!("{}-current-control-threshold", dataset.dataset_id),
        policy_role: CURRENT_CONTROL_POLICY_ROLE.to_string(),
        source_policy_id: policy.policy_id.clone(),
        source_dataset_id: dataset.dataset_id.clone(),
        source_eval_report_id: report.report_id.clone(),
        source_escalation_thresholds_id: thresholds.escalation_thresholds_id.clone(),
        workstream_id: dataset.workstream_id.clone(),
        workspace_id: dataset.workspace_id.clone(),
        session_id: dataset.session_id.clone(),
        generated_at,
        stage_state: CONTROL_STAGE_STATE.to_string(),
        family_thresholds: vec![
            current_control_family_threshold(policy, "analysis"),
            current_control_family_threshold(policy, "implementation"),
            current_control_family_threshold(policy, "manuscript"),
        ],
        note: "B24.8 preserves the current B24.6 autonomy gate as the control policy so every candidate threshold can be compared against an explicit live baseline on the same Beagle-owned identity.".to_string(),
    }
}

fn build_candidate_shadow_threshold(
    policy: &AutonomyPolicy,
    dataset: &AutonomyCalibrationDataset,
    report: &AutonomyPolicyEvalReport,
    thresholds: &EscalationThresholds,
    generated_at: DateTime<Utc>,
) -> AutonomyShadowThreshold {
    let family_thresholds = thresholds
        .thresholds
        .iter()
        .map(|threshold| AutonomyShadowTaskFamilyThreshold {
            task_family: threshold.task_family.clone(),
            rollout_state: if threshold.task_family == "analysis" {
                "hold-current-control".to_string()
            } else if threshold.task_family == "implementation" {
                "guarded-canary-staged".to_string()
            } else {
                "hold-shadow-only".to_string()
            },
            auto_continue_enabled: threshold.auto_continue_enabled,
            auto_continue_allowed_review_actions: vec!["approved".to_string()],
            auto_continue_allowed_trajectory_qualities: vec!["good".to_string()],
            auto_continue_min_overall_quality_score: threshold
                .auto_continue_min_overall_quality_score,
            auto_continue_min_trajectory_score: threshold.auto_continue_min_trajectory_score,
            blocked_max_overall_quality_score: threshold.blocked_max_overall_quality_score,
            blocked_max_trajectory_score: threshold.blocked_max_trajectory_score,
            blocked_trajectory_qualities: policy.blocked_trajectory_qualities.clone(),
            allowed_subagent_ids: threshold.allowed_subagent_ids.clone(),
            allowed_retrieval_query_types: threshold.allowed_retrieval_query_types.clone(),
            allowed_compiler_profile_ids: threshold.allowed_compiler_profile_ids.clone(),
            allowed_graphrag_query_modes: threshold.allowed_graphrag_query_modes.clone(),
            allowed_temporal_truth_views: threshold.allowed_temporal_truth_views.clone(),
            blocked_requested_operator_actions: threshold
                .blocked_requested_operator_actions
                .clone(),
            blocked_when_replan_required: threshold.blocked_when_replan_required,
            guarded_enablement_eligible: threshold.task_family == "implementation"
                && threshold.recommended_action == "stage-shadow-auto-continue",
            rationale: threshold.rationale.clone(),
        })
        .collect::<Vec<_>>();

    AutonomyShadowThreshold {
        shadow_threshold_version: AUTONOMY_SHADOW_THRESHOLD_VERSION.to_string(),
        shadow_threshold_id: format!("{}-candidate-shadow-threshold", dataset.dataset_id),
        policy_role: CANDIDATE_SHADOW_POLICY_ROLE.to_string(),
        source_policy_id: policy.policy_id.clone(),
        source_dataset_id: dataset.dataset_id.clone(),
        source_eval_report_id: report.report_id.clone(),
        source_escalation_thresholds_id: thresholds.escalation_thresholds_id.clone(),
        workstream_id: dataset.workstream_id.clone(),
        workspace_id: dataset.workspace_id.clone(),
        session_id: dataset.session_id.clone(),
        generated_at,
        stage_state: SHADOW_CANDIDATE_STAGE_STATE.to_string(),
        family_thresholds,
        note: "B24.8 stages the calibrated candidate policy in shadow mode first: implementation is the only family eligible for a future guarded canary, while analysis stays on control and manuscript stays review-or-block.".to_string(),
    }
}

fn build_rollout_metrics(
    dataset: &AutonomyCalibrationDataset,
    current_policy: &AutonomyShadowThreshold,
    candidate_policy: &AutonomyShadowThreshold,
    shadow_policy_comparison: &ShadowPolicyComparison,
    generated_at: DateTime<Utc>,
) -> PolicyRolloutMetrics {
    let family_metrics = dataset
        .task_families_evaluated
        .iter()
        .map(|task_family| {
            task_family_rollout_metric(dataset, task_family, current_policy, candidate_policy)
        })
        .collect::<Vec<_>>();
    let sample_refs = dataset.samples.iter().collect::<Vec<_>>();

    PolicyRolloutMetrics {
        metrics_version: POLICY_ROLLOUT_METRIC_VERSION.to_string(),
        rollout_metrics_id: format!("{}-rollout-metrics", dataset.dataset_id),
        current_shadow_threshold_id: current_policy.shadow_threshold_id.clone(),
        candidate_shadow_threshold_id: candidate_policy.shadow_threshold_id.clone(),
        dataset_id: dataset.dataset_id.clone(),
        shadow_policy_comparison_id: shadow_policy_comparison.shadow_policy_comparison_id.clone(),
        workstream_id: dataset.workstream_id.clone(),
        workspace_id: dataset.workspace_id.clone(),
        session_id: dataset.session_id.clone(),
        generated_at,
        rollout_stage: ROLLOUT_METRICS_STAGE_STATE.to_string(),
        sample_count: dataset.sample_count,
        current_false_auto_continue_rate_basis_points: false_rate_basis_points_for_shadow_policy(
            &sample_refs,
            "auto-continue",
            current_policy,
        ),
        candidate_false_auto_continue_rate_basis_points:
            false_rate_basis_points_for_shadow_policy(
                &sample_refs,
                "auto-continue",
                candidate_policy,
            ),
        current_false_review_required_rate_basis_points:
            false_rate_basis_points_for_shadow_policy(
                &sample_refs,
                "review-required",
                current_policy,
            ),
        candidate_false_review_required_rate_basis_points:
            false_rate_basis_points_for_shadow_policy(
                &sample_refs,
                "review-required",
                candidate_policy,
            ),
        current_false_blocked_rate_basis_points: false_rate_basis_points_for_shadow_policy(
            &sample_refs,
            "blocked",
            current_policy,
        ),
        candidate_false_blocked_rate_basis_points: false_rate_basis_points_for_shadow_policy(
            &sample_refs,
            "blocked",
            candidate_policy,
        ),
        current_alignment_with_operator_decision_basis_points:
            alignment_rate_basis_points_for_shadow_policy(
                &sample_refs,
                current_policy,
                AlignmentLens::OperatorDecision,
            ),
        candidate_alignment_with_operator_decision_basis_points:
            alignment_rate_basis_points_for_shadow_policy(
                &sample_refs,
                candidate_policy,
                AlignmentLens::OperatorDecision,
            ),
        current_alignment_with_execution_outcome_basis_points:
            alignment_rate_basis_points_for_shadow_policy(
                &sample_refs,
                current_policy,
                AlignmentLens::ExecutionOutcome,
            ),
        candidate_alignment_with_execution_outcome_basis_points:
            alignment_rate_basis_points_for_shadow_policy(
                &sample_refs,
                candidate_policy,
                AlignmentLens::ExecutionOutcome,
            ),
        improved_alignment_count: improved_alignment_count(
            &sample_refs,
            current_policy,
            candidate_policy,
        ),
        regression_count: regression_count(&sample_refs, current_policy, candidate_policy),
        family_metrics,
        note: "B24.8 rollout metrics compare the current live control policy against the candidate shadow policy, then isolate implementation, analysis, and manuscript readiness before any guarded rollout is staged.".to_string(),
    }
}

fn build_guarded_rollout_decision(
    current_policy: &AutonomyShadowThreshold,
    candidate_policy: &AutonomyShadowThreshold,
    rollout_metrics: &PolicyRolloutMetrics,
    recommendation: &UpdatedPolicyRecommendation,
    generated_at: DateTime<Utc>,
) -> GuardedRolloutDecision {
    let implementation_ready = rollout_metrics.family_metrics.iter().any(|metric| {
        metric.task_family == "implementation"
            && metric.rollout_readiness == "guarded-canary-ready"
    });
    let regression_detected = rollout_metrics.regression_count > 0
        || rollout_metrics.candidate_false_auto_continue_rate_basis_points > 0;
    let guarded_enablement_permitted =
        implementation_ready && !regression_detected && recommendation.safe_to_apply_live == false;
    let recommended_action = if regression_detected {
        "rollback-to-current-control".to_string()
    } else if guarded_enablement_permitted {
        "stage-guarded-canary-for-implementation".to_string()
    } else {
        "keep-shadow-only-and-monitor".to_string()
    };
    let rollout_stage = if regression_detected {
        "rollback-to-control".to_string()
    } else if guarded_enablement_permitted {
        "shadow-plus-staged-implementation-canary".to_string()
    } else {
        "shadow-only".to_string()
    };
    let family_decisions = rollout_metrics
        .family_metrics
        .iter()
        .map(|metric| GuardedTaskFamilyDecision {
            task_family: metric.task_family.clone(),
            rollout_state: if metric.task_family == "analysis" {
                "current-control".to_string()
            } else if metric.rollout_readiness == "guarded-canary-ready" {
                "guarded-canary-staged".to_string()
            } else if metric.task_family == "manuscript" {
                "hold-review-or-block".to_string()
            } else {
                "keep-shadow-only".to_string()
            },
            can_move_first: metric.rollout_readiness == "guarded-canary-ready",
            regression_detected: metric.regression_count > 0,
            rollback_ready: true,
            rationale: metric.note.clone(),
        })
        .collect::<Vec<_>>();
    let safe_task_families_to_move_first = family_decisions
        .iter()
        .filter(|decision| decision.can_move_first)
        .map(|decision| decision.task_family.clone())
        .collect::<Vec<_>>();

    GuardedRolloutDecision {
        decision_version: GUARDED_ROLLOUT_DECISION_VERSION.to_string(),
        guarded_rollout_decision_id: format!(
            "{}-guarded-rollout-decision",
            rollout_metrics.dataset_id
        ),
        current_shadow_threshold_id: current_policy.shadow_threshold_id.clone(),
        candidate_shadow_threshold_id: candidate_policy.shadow_threshold_id.clone(),
        rollout_metrics_id: rollout_metrics.rollout_metrics_id.clone(),
        shadow_policy_comparison_id: rollout_metrics.shadow_policy_comparison_id.clone(),
        updated_policy_recommendation_id: recommendation.updated_policy_recommendation_id.clone(),
        workstream_id: rollout_metrics.workstream_id.clone(),
        workspace_id: rollout_metrics.workspace_id.clone(),
        session_id: rollout_metrics.session_id.clone(),
        generated_at,
        rollout_stage,
        recommended_action,
        current_policy_preserved_as_control: true,
        candidate_policy_shadow_mode: true,
        guarded_enablement_permitted,
        guarded_enablement_live: false,
        global_policy_update_permitted: false,
        safe_task_families_to_move_first,
        current_control_task_families: vec!["analysis".to_string()],
        staged_guarded_task_families: if guarded_enablement_permitted {
            vec!["implementation".to_string()]
        } else {
            Vec::new()
        },
        blocked_or_hold_task_families: vec!["manuscript".to_string()],
        regression_detected,
        rollback_required: regression_detected,
        rollback_trigger: "trigger rollback if any candidate regression is observed, if candidate false_auto_continue_rate rises above 0, or if operator/execution alignment drops below the control policy.".to_string(),
        rollback_action: "revert to the current control policy immediately and keep the candidate thresholds in shadow-only mode until recalibration is rerun.".to_string(),
        family_decisions,
        same_beagle_owned_identity: current_policy.workstream_id == candidate_policy.workstream_id
            && current_policy.workspace_id == candidate_policy.workspace_id
            && current_policy.session_id == candidate_policy.session_id,
        note: "B24.8 keeps the live gate operator-aware: the control policy remains canonical, implementation is the only staged canary candidate, analysis stays on the current lane, manuscript stays review-or-block, and rollback remains explicit at every stage.".to_string(),
    }
}

fn build_canary_control_policy(
    policy: &AutonomyPolicy,
    rollout_bundle: &GuardedPolicyRolloutBundle,
) -> AutonomyPolicy {
    let mut control_policy = policy.clone();
    control_policy.policy_id = format!("{}-control-live", policy.policy_id);
    control_policy.policy_role = Some("control-live".to_string());
    control_policy.rollout_stage = Some("implementation-canary-live".to_string());
    control_policy.policy_family_scope = vec!["analysis".to_string(), "manuscript".to_string()];
    control_policy.guarded_enablement_live = false;
    control_policy.control_policy_id = None;
    control_policy.source_threshold_id = Some(
        rollout_bundle
            .autonomy_policy_current
            .shadow_threshold_id
            .clone(),
    );
    control_policy.note = "B24.9 preserves the current control autonomy policy as the live lane for analysis and manuscript while implementation canary activation is evaluated separately.".to_string();
    control_policy
}

fn build_canary_implementation_policy(
    policy: &AutonomyPolicy,
    rollout_bundle: &GuardedPolicyRolloutBundle,
    control_policy: &AutonomyPolicy,
) -> AutonomyPolicy {
    let mut canary_policy = policy.clone();
    let implementation_threshold = shadow_threshold_for_family(
        &rollout_bundle.autonomy_policy_candidate,
        "implementation",
    );
    canary_policy.policy_id = format!("{}-implementation-canary-live", policy.policy_id);
    canary_policy.policy_role = Some("implementation-canary-live".to_string());
    canary_policy.rollout_stage = Some("implementation-canary-live".to_string());
    canary_policy.policy_family_scope = vec!["implementation".to_string()];
    canary_policy.guarded_enablement_live = implementation_canary_live(rollout_bundle);
    canary_policy.control_policy_id = Some(control_policy.policy_id.clone());
    canary_policy.source_threshold_id = Some(
        rollout_bundle
            .autonomy_policy_candidate
            .shadow_threshold_id
            .clone(),
    );
    canary_policy.auto_continue_task_families = vec!["implementation".to_string()];
    canary_policy.auto_continue_subagent_ids = implementation_threshold
        .map(|threshold| threshold.allowed_subagent_ids.clone())
        .unwrap_or_else(|| vec!["core".to_string()]);
    canary_policy.auto_continue_retrieval_query_types = implementation_threshold
        .map(|threshold| threshold.allowed_retrieval_query_types.clone())
        .unwrap_or_else(|| vec!["code".to_string()]);
    canary_policy.auto_continue_compiler_profile_ids = implementation_threshold
        .map(|threshold| threshold.allowed_compiler_profile_ids.clone())
        .unwrap_or_else(|| vec!["b235-budget-implementation".to_string()]);
    canary_policy.auto_continue_graphrag_query_modes = implementation_threshold
        .map(|threshold| threshold.allowed_graphrag_query_modes.clone())
        .unwrap_or_else(|| vec!["local".to_string()]);
    canary_policy.auto_continue_temporal_truth_views = implementation_threshold
        .map(|threshold| threshold.allowed_temporal_truth_views.clone())
        .unwrap_or_else(|| vec!["current".to_string()]);
    canary_policy.auto_continue_allowed_review_actions = implementation_threshold
        .map(|threshold| threshold.auto_continue_allowed_review_actions.clone())
        .unwrap_or_else(|| vec!["approved".to_string()]);
    if !canary_policy
        .auto_continue_allowed_review_actions
        .iter()
        .any(|action| action == "edited")
    {
        canary_policy
            .auto_continue_allowed_review_actions
            .push("edited".to_string());
    }
    canary_policy.auto_continue_allowed_trajectory_qualities = implementation_threshold
        .map(|threshold| threshold.auto_continue_allowed_trajectory_qualities.clone())
        .unwrap_or_else(|| vec!["good".to_string()]);
    canary_policy.auto_continue_min_overall_quality_score = implementation_threshold
        .map(|threshold| threshold.auto_continue_min_overall_quality_score)
        .unwrap_or(95);
    canary_policy.blocked_max_overall_quality_score = implementation_threshold
        .map(|threshold| threshold.blocked_max_overall_quality_score)
        .unwrap_or(policy.blocked_max_overall_quality_score);
    canary_policy.blocked_trajectory_qualities = implementation_threshold
        .map(|threshold| threshold.blocked_trajectory_qualities.clone())
        .unwrap_or_else(|| policy.blocked_trajectory_qualities.clone());
    canary_policy.blocked_requested_operator_actions = implementation_threshold
        .map(|threshold| threshold.blocked_requested_operator_actions.clone())
        .unwrap_or_else(|| policy.blocked_requested_operator_actions.clone());
    canary_policy.note = "B24.9 activates the calibrated implementation canary policy live while keeping analysis and manuscript on the explicit control policy.".to_string();
    canary_policy
}

fn build_canary_rollout_metrics(
    rollout_bundle: &GuardedPolicyRolloutBundle,
    control_policy: &AutonomyPolicy,
    canary_policy: &AutonomyPolicy,
    generated_at: DateTime<Utc>,
) -> CanaryRolloutMetrics {
    let implementation_canary_enabled = implementation_canary_live(rollout_bundle);
    let analysis_control_retained = true;
    let manuscript_control_retained = true;
    let mut family_metrics = rollout_bundle
        .rollout_metrics
        .family_metrics
        .iter()
        .map(|metric| {
            let uses_canary = metric.task_family == "implementation" && implementation_canary_enabled;
            CanaryTaskFamilyMetric {
                task_family: metric.task_family.clone(),
                live_policy_role: if uses_canary {
                    "implementation-canary-live".to_string()
                } else {
                    "control-live".to_string()
                },
                canary_enabled: uses_canary,
                control_retained: !uses_canary,
                false_auto_continue_rate_basis_points: if uses_canary {
                    metric.candidate_false_auto_continue_rate_basis_points
                } else {
                    metric.current_false_auto_continue_rate_basis_points
                },
                false_review_required_rate_basis_points: if uses_canary {
                    metric.candidate_false_review_required_rate_basis_points
                } else {
                    metric.current_false_review_required_rate_basis_points
                },
                false_blocked_rate_basis_points: if uses_canary {
                    metric.candidate_false_blocked_rate_basis_points
                } else {
                    metric.current_false_blocked_rate_basis_points
                },
                alignment_with_operator_decision_basis_points: if uses_canary {
                    metric.candidate_alignment_with_operator_decision_basis_points
                } else {
                    metric.current_alignment_with_operator_decision_basis_points
                },
                alignment_with_execution_outcome_basis_points: if uses_canary {
                    metric.candidate_alignment_with_execution_outcome_basis_points
                } else {
                    metric.current_alignment_with_execution_outcome_basis_points
                },
                rollback_triggered: false,
                rationale: if uses_canary {
                    "Implementation is the only live canary lane in B24.9.".to_string()
                } else {
                    format!(
                        "Task family '{}' remains on the current control lane during the implementation canary.",
                        metric.task_family
                    )
                },
            }
        })
        .collect::<Vec<_>>();

    let implementation_metric = rollout_bundle
        .rollout_metrics
        .family_metrics
        .iter()
        .find(|metric| metric.task_family == "implementation");
    let regression_detected = implementation_metric.is_some_and(|metric| {
        metric.candidate_false_auto_continue_rate_basis_points > 0
            || metric.candidate_alignment_with_operator_decision_basis_points
                < metric.current_alignment_with_operator_decision_basis_points
            || metric.candidate_alignment_with_execution_outcome_basis_points
                < metric.current_alignment_with_execution_outcome_basis_points
            || metric.regression_count > 0
    }) || rollout_bundle.rollout_decision.regression_detected;

    for metric in &mut family_metrics {
        metric.rollback_triggered =
            regression_detected && metric.task_family == "implementation";
    }

    let canary_stage = if regression_detected {
        "rollback-to-control".to_string()
    } else if implementation_canary_enabled {
        "implementation-family-live-canary".to_string()
    } else {
        "control-only".to_string()
    };
    let sample_total = rollout_bundle
        .rollout_metrics
        .family_metrics
        .iter()
        .map(|metric| metric.sample_count)
        .sum::<usize>();

    CanaryRolloutMetrics {
        metrics_version: CANARY_ROLLOUT_METRIC_VERSION.to_string(),
        canary_rollout_metrics_id: format!(
            "{}-implementation-canary-metrics",
            rollout_bundle.rollout_metrics.rollout_metrics_id
        ),
        control_policy_id: control_policy.policy_id.clone(),
        canary_policy_id: canary_policy.policy_id.clone(),
        source_rollout_metrics_id: rollout_bundle.rollout_metrics.rollout_metrics_id.clone(),
        source_rollout_decision_id: rollout_bundle
            .rollout_decision
            .guarded_rollout_decision_id
            .clone(),
        workstream_id: rollout_bundle.rollout_metrics.workstream_id.clone(),
        workspace_id: rollout_bundle.rollout_metrics.workspace_id.clone(),
        session_id: rollout_bundle.rollout_metrics.session_id.clone(),
        generated_at,
        canary_stage,
        false_auto_continue_rate_basis_points: weighted_basis_points(
            &rollout_bundle.rollout_metrics.family_metrics,
            |metric| {
                if metric.task_family == "implementation" && implementation_canary_enabled {
                    metric.candidate_false_auto_continue_rate_basis_points
                } else {
                    metric.current_false_auto_continue_rate_basis_points
                }
            },
            sample_total,
        ),
        false_review_required_rate_basis_points: weighted_basis_points(
            &rollout_bundle.rollout_metrics.family_metrics,
            |metric| {
                if metric.task_family == "implementation" && implementation_canary_enabled {
                    metric.candidate_false_review_required_rate_basis_points
                } else {
                    metric.current_false_review_required_rate_basis_points
                }
            },
            sample_total,
        ),
        false_blocked_rate_basis_points: weighted_basis_points(
            &rollout_bundle.rollout_metrics.family_metrics,
            |metric| {
                if metric.task_family == "implementation" && implementation_canary_enabled {
                    metric.candidate_false_blocked_rate_basis_points
                } else {
                    metric.current_false_blocked_rate_basis_points
                }
            },
            sample_total,
        ),
        alignment_with_operator_decision_basis_points: weighted_basis_points(
            &rollout_bundle.rollout_metrics.family_metrics,
            |metric| {
                if metric.task_family == "implementation" && implementation_canary_enabled {
                    metric.candidate_alignment_with_operator_decision_basis_points
                } else {
                    metric.current_alignment_with_operator_decision_basis_points
                }
            },
            sample_total,
        ),
        alignment_with_execution_outcome_basis_points: weighted_basis_points(
            &rollout_bundle.rollout_metrics.family_metrics,
            |metric| {
                if metric.task_family == "implementation" && implementation_canary_enabled {
                    metric.candidate_alignment_with_execution_outcome_basis_points
                } else {
                    metric.current_alignment_with_execution_outcome_basis_points
                }
            },
            sample_total,
        ),
        rollback_triggered: regression_detected,
        implementation_canary_enabled,
        analysis_control_retained,
        manuscript_control_retained,
        family_metrics,
        note: "B24.9 keeps control and canary explicit at the same time: implementation moves to the live canary lane while analysis and manuscript remain pinned to the control policy until their own evidence clears them.".to_string(),
    }
}

fn build_canary_rollback_decision(
    rollout_bundle: &GuardedPolicyRolloutBundle,
    control_policy: &AutonomyPolicy,
    canary_policy: &AutonomyPolicy,
    metrics: &CanaryRolloutMetrics,
    generated_at: DateTime<Utc>,
) -> CanaryRollbackDecision {
    let rollback_required = metrics.rollback_triggered;
    let implementation_canary_live =
        metrics.implementation_canary_enabled && !rollback_required;

    CanaryRollbackDecision {
        decision_version: CANARY_ROLLBACK_DECISION_VERSION.to_string(),
        canary_rollback_decision_id: format!(
            "{}-implementation-canary-rollback",
            metrics.canary_rollout_metrics_id
        ),
        canary_rollout_metrics_id: metrics.canary_rollout_metrics_id.clone(),
        source_rollout_decision_id: rollout_bundle
            .rollout_decision
            .guarded_rollout_decision_id
            .clone(),
        control_policy_id: control_policy.policy_id.clone(),
        canary_policy_id: canary_policy.policy_id.clone(),
        workstream_id: metrics.workstream_id.clone(),
        workspace_id: metrics.workspace_id.clone(),
        session_id: metrics.session_id.clone(),
        generated_at,
        canary_stage: metrics.canary_stage.clone(),
        implementation_canary_live,
        analysis_control_retained: metrics.analysis_control_retained,
        manuscript_control_retained: metrics.manuscript_control_retained,
        regression_detected: rollback_required,
        rollback_required,
        rollback_triggered: rollback_required,
        rollback_reason: if rollback_required {
            "Implementation canary regressed against the control baseline, so the rollout must snap back to control immediately.".to_string()
        } else {
            "No implementation canary regression was detected, so the guarded rollout can remain live while analysis and manuscript stay on control.".to_string()
        },
        rollback_action: if rollback_required {
            "Disable the implementation canary immediately, restore the control policy for every family, and keep the candidate policy shadow-only until recalibration is rerun.".to_string()
        } else {
            "Keep the implementation canary live, continue collecting guarded metrics, and preserve the control policy for analysis and manuscript.".to_string()
        },
        same_beagle_owned_identity: control_policy.workstream_id == canary_policy.workstream_id
            && control_policy.workspace_id == canary_policy.workspace_id
            && control_policy.session_id == canary_policy.session_id,
        note: "B24.9 records rollback explicitly even while the canary is healthy so the implementation lane can be reversed without losing the same Beagle-owned workstream, workspace, or session identity.".to_string(),
    }
}

fn build_analysis_candidate_policy(
    rollout_bundle: &GuardedPolicyRolloutBundle,
    control_policy: &AutonomyPolicy,
) -> AutonomyPolicy {
    let mut candidate_policy = control_policy.clone();
    let analysis_threshold = shadow_threshold_for_family(
        &rollout_bundle.autonomy_policy_candidate,
        "analysis",
    );
    candidate_policy.policy_id = format!("{}-analysis-shadow-candidate", control_policy.policy_id);
    candidate_policy.policy_role = Some("analysis-shadow-candidate".to_string());
    candidate_policy.rollout_stage = Some("analysis-shadow".to_string());
    candidate_policy.policy_family_scope = vec!["analysis".to_string()];
    candidate_policy.guarded_enablement_live = false;
    candidate_policy.control_policy_id = Some(control_policy.policy_id.clone());
    candidate_policy.source_threshold_id = Some(
        rollout_bundle
            .autonomy_policy_candidate
            .shadow_threshold_id
            .clone(),
    );
    candidate_policy.auto_continue_task_families = if analysis_threshold
        .is_some_and(|threshold| threshold.auto_continue_enabled)
    {
        vec!["analysis".to_string()]
    } else {
        Vec::new()
    };
    candidate_policy.auto_continue_subagent_ids = analysis_threshold
        .map(|threshold| threshold.allowed_subagent_ids.clone())
        .unwrap_or_else(|| control_policy.auto_continue_subagent_ids.clone());
    candidate_policy.auto_continue_retrieval_query_types = analysis_threshold
        .map(|threshold| threshold.allowed_retrieval_query_types.clone())
        .unwrap_or_else(|| control_policy.auto_continue_retrieval_query_types.clone());
    candidate_policy.auto_continue_compiler_profile_ids = analysis_threshold
        .map(|threshold| threshold.allowed_compiler_profile_ids.clone())
        .unwrap_or_else(|| control_policy.auto_continue_compiler_profile_ids.clone());
    candidate_policy.auto_continue_graphrag_query_modes = analysis_threshold
        .map(|threshold| threshold.allowed_graphrag_query_modes.clone())
        .unwrap_or_else(|| control_policy.auto_continue_graphrag_query_modes.clone());
    candidate_policy.auto_continue_temporal_truth_views = analysis_threshold
        .map(|threshold| threshold.allowed_temporal_truth_views.clone())
        .unwrap_or_else(|| control_policy.auto_continue_temporal_truth_views.clone());
    candidate_policy.auto_continue_allowed_review_actions = analysis_threshold
        .map(|threshold| threshold.auto_continue_allowed_review_actions.clone())
        .unwrap_or_else(|| control_policy.auto_continue_allowed_review_actions.clone());
    candidate_policy.auto_continue_allowed_trajectory_qualities = analysis_threshold
        .map(|threshold| threshold.auto_continue_allowed_trajectory_qualities.clone())
        .unwrap_or_else(|| control_policy.auto_continue_allowed_trajectory_qualities.clone());
    candidate_policy.auto_continue_min_overall_quality_score = analysis_threshold
        .map(|threshold| threshold.auto_continue_min_overall_quality_score)
        .unwrap_or(control_policy.auto_continue_min_overall_quality_score);
    candidate_policy.blocked_max_overall_quality_score = analysis_threshold
        .map(|threshold| threshold.blocked_max_overall_quality_score)
        .unwrap_or(control_policy.blocked_max_overall_quality_score);
    candidate_policy.blocked_trajectory_qualities = analysis_threshold
        .map(|threshold| threshold.blocked_trajectory_qualities.clone())
        .unwrap_or_else(|| control_policy.blocked_trajectory_qualities.clone());
    candidate_policy.blocked_requested_operator_actions = analysis_threshold
        .map(|threshold| threshold.blocked_requested_operator_actions.clone())
        .unwrap_or_else(|| control_policy.blocked_requested_operator_actions.clone());
    candidate_policy.note = "B24.10 stages an analysis-only candidate autonomy policy in shadow mode while the implementation family remains on the live canary and manuscript stays on control.".to_string();
    candidate_policy
}

fn build_analysis_shadow_comparison(
    dataset: &AutonomyCalibrationDataset,
    control_policy: &AutonomyPolicy,
    analysis_candidate_policy: &AutonomyPolicy,
    canary_metrics: &CanaryRolloutMetrics,
    canary_rollback_decision: &CanaryRollbackDecision,
    generated_at: DateTime<Utc>,
) -> AnalysisShadowCalibration {
    let analysis_samples = family_samples(dataset, "analysis");
    let samples = analysis_samples
        .iter()
        .map(|sample| {
            let current_policy_decision_class =
                evaluate_autonomy_policy_sample(sample, control_policy);
            let analysis_candidate_decision_class =
                evaluate_autonomy_policy_sample(sample, analysis_candidate_policy);
            let improved_alignment =
                current_policy_decision_class != sample.expected_decision_class
                    && analysis_candidate_decision_class == sample.expected_decision_class;
            let regression =
                current_policy_decision_class == sample.expected_decision_class
                    && analysis_candidate_decision_class != sample.expected_decision_class;
            AnalysisShadowComparisonEntry {
                sample_id: sample.sample_id.clone(),
                sample_source: sample.sample_source.clone(),
                expected_decision_class: sample.expected_decision_class.clone(),
                current_policy_decision_class,
                analysis_candidate_decision_class,
                improved_alignment,
                regression,
                note: "B24.10 replays the analysis-family samples in shadow mode only while the live implementation canary and manuscript control lanes remain unchanged.".to_string(),
            }
        })
        .collect::<Vec<_>>();
    let improved_alignment_count = samples
        .iter()
        .filter(|sample| sample.improved_alignment)
        .count();
    let regression_count = samples.iter().filter(|sample| sample.regression).count();
    let recommendation_for_analysis = if regression_count > 0
        || canary_rollback_decision.rollback_required
    {
        "rollback-shadow".to_string()
    } else if improved_alignment_count > 0 {
        "stage-analysis-canary".to_string()
    } else {
        "keep-shadow".to_string()
    };

    AnalysisShadowCalibration {
        calibration_version: ANALYSIS_SHADOW_CALIBRATION_VERSION.to_string(),
        analysis_shadow_calibration_id: format!(
            "{}-analysis-shadow-comparison",
            dataset.dataset_id
        ),
        control_policy_id: control_policy.policy_id.clone(),
        analysis_candidate_policy_id: analysis_candidate_policy.policy_id.clone(),
        source_dataset_id: dataset.dataset_id.clone(),
        source_canary_rollout_metrics_id: canary_metrics.canary_rollout_metrics_id.clone(),
        source_canary_rollback_decision_id: canary_rollback_decision
            .canary_rollback_decision_id
            .clone(),
        workstream_id: dataset.workstream_id.clone(),
        workspace_id: dataset.workspace_id.clone(),
        session_id: dataset.session_id.clone(),
        generated_at,
        rollout_stage: "implementation-canary-live-analysis-shadow".to_string(),
        implementation_canary_retained: canary_metrics.implementation_canary_enabled
            && !canary_rollback_decision.rollback_required,
        manuscript_control_retained: canary_metrics.manuscript_control_retained,
        compared_sample_count: analysis_samples.len(),
        improved_alignment_count,
        regression_count,
        recommendation_for_analysis,
        samples,
        note: "B24.10 keeps analysis bounded and operator-aware: the candidate policy is only replayed in shadow against analysis samples while the existing implementation canary and manuscript control lanes stay intact.".to_string(),
    }
}

fn build_analysis_rollout_metrics(
    dataset: &AutonomyCalibrationDataset,
    control_policy: &AutonomyPolicy,
    analysis_candidate_policy: &AutonomyPolicy,
    canary_bundle: &ImplementationCanaryAutonomyBundle,
    comparison: &AnalysisShadowCalibration,
    generated_at: DateTime<Utc>,
) -> AnalysisRolloutMetrics {
    let analysis_samples = family_samples(dataset, "analysis");
    let current_false_auto_continue_rate_basis_points =
        false_rate_basis_points_for_autonomy_policy(
            &analysis_samples,
            "auto-continue",
            control_policy,
        );
    let shadow_false_auto_continue_rate_basis_points =
        false_rate_basis_points_for_autonomy_policy(
            &analysis_samples,
            "auto-continue",
            analysis_candidate_policy,
        );
    let current_false_review_required_rate_basis_points =
        false_rate_basis_points_for_autonomy_policy(
            &analysis_samples,
            "review-required",
            control_policy,
        );
    let shadow_false_review_required_rate_basis_points =
        false_rate_basis_points_for_autonomy_policy(
            &analysis_samples,
            "review-required",
            analysis_candidate_policy,
        );
    let current_alignment_with_operator_decision_basis_points =
        alignment_rate_basis_points_for_autonomy_policy(
            &analysis_samples,
            control_policy,
            AlignmentLens::OperatorDecision,
        );
    let shadow_alignment_with_operator_decision_basis_points =
        alignment_rate_basis_points_for_autonomy_policy(
            &analysis_samples,
            analysis_candidate_policy,
            AlignmentLens::OperatorDecision,
        );
    let current_alignment_with_execution_outcome_basis_points =
        alignment_rate_basis_points_for_autonomy_policy(
            &analysis_samples,
            control_policy,
            AlignmentLens::ExecutionOutcome,
        );
    let shadow_alignment_with_execution_outcome_basis_points =
        alignment_rate_basis_points_for_autonomy_policy(
            &analysis_samples,
            analysis_candidate_policy,
            AlignmentLens::ExecutionOutcome,
        );
    let regression_count = comparison.regression_count;
    let recommendation_for_analysis = if regression_count > 0
        || canary_bundle.canary_rollback_decision.rollback_required
    {
        "rollback-shadow".to_string()
    } else if comparison.improved_alignment_count > 0
        && shadow_false_auto_continue_rate_basis_points == 0
        && shadow_false_review_required_rate_basis_points == 0
        && shadow_alignment_with_operator_decision_basis_points
            >= current_alignment_with_operator_decision_basis_points
        && shadow_alignment_with_execution_outcome_basis_points
            >= current_alignment_with_execution_outcome_basis_points
    {
        "stage-analysis-canary".to_string()
    } else {
        "keep-shadow".to_string()
    };

    let implementation_family_metric = canary_bundle
        .canary_rollout_metrics
        .family_metrics
        .iter()
        .find(|metric| metric.task_family == "implementation");
    let manuscript_family_metric = canary_bundle
        .canary_rollout_metrics
        .family_metrics
        .iter()
        .find(|metric| metric.task_family == "manuscript");

    let family_metrics = vec![
        AnalysisTaskFamilyMetric {
            task_family: "implementation".to_string(),
            live_policy_role: implementation_family_metric
                .map(|metric| metric.live_policy_role.clone())
                .unwrap_or_else(|| "implementation-canary-live".to_string()),
            shadow_policy_role: None,
            canary_retained: canary_bundle
                .canary_rollout_metrics
                .implementation_canary_enabled,
            control_retained: false,
            shadow_evaluated: false,
            current_false_auto_continue_rate_basis_points: implementation_family_metric
                .map(|metric| metric.false_auto_continue_rate_basis_points)
                .unwrap_or(0),
            shadow_false_auto_continue_rate_basis_points: implementation_family_metric
                .map(|metric| metric.false_auto_continue_rate_basis_points)
                .unwrap_or(0),
            current_false_review_required_rate_basis_points: implementation_family_metric
                .map(|metric| metric.false_review_required_rate_basis_points)
                .unwrap_or(0),
            shadow_false_review_required_rate_basis_points: implementation_family_metric
                .map(|metric| metric.false_review_required_rate_basis_points)
                .unwrap_or(0),
            current_alignment_with_operator_decision_basis_points: implementation_family_metric
                .map(|metric| metric.alignment_with_operator_decision_basis_points)
                .unwrap_or(0),
            shadow_alignment_with_operator_decision_basis_points: implementation_family_metric
                .map(|metric| metric.alignment_with_operator_decision_basis_points)
                .unwrap_or(0),
            current_alignment_with_execution_outcome_basis_points: implementation_family_metric
                .map(|metric| metric.alignment_with_execution_outcome_basis_points)
                .unwrap_or(0),
            shadow_alignment_with_execution_outcome_basis_points: implementation_family_metric
                .map(|metric| metric.alignment_with_execution_outcome_basis_points)
                .unwrap_or(0),
            regression_count: usize::from(
                canary_bundle.canary_rollback_decision.rollback_required,
            ),
            recommendation_for_analysis: "implementation-canary-retained".to_string(),
            rationale: "Implementation remains on the live canary lane during B24.10 and is not reclassified by the analysis shadow pass.".to_string(),
        },
        AnalysisTaskFamilyMetric {
            task_family: "analysis".to_string(),
            live_policy_role: control_policy
                .policy_role
                .clone()
                .unwrap_or_else(|| "control-live".to_string()),
            shadow_policy_role: analysis_candidate_policy.policy_role.clone(),
            canary_retained: false,
            control_retained: true,
            shadow_evaluated: true,
            current_false_auto_continue_rate_basis_points,
            shadow_false_auto_continue_rate_basis_points,
            current_false_review_required_rate_basis_points,
            shadow_false_review_required_rate_basis_points,
            current_alignment_with_operator_decision_basis_points,
            shadow_alignment_with_operator_decision_basis_points,
            current_alignment_with_execution_outcome_basis_points,
            shadow_alignment_with_execution_outcome_basis_points,
            regression_count,
            recommendation_for_analysis: recommendation_for_analysis.clone(),
            rationale: "Analysis stays on the current control lane live while the candidate policy is compared in shadow mode only.".to_string(),
        },
        AnalysisTaskFamilyMetric {
            task_family: "manuscript".to_string(),
            live_policy_role: manuscript_family_metric
                .map(|metric| metric.live_policy_role.clone())
                .unwrap_or_else(|| "control-live".to_string()),
            shadow_policy_role: None,
            canary_retained: false,
            control_retained: canary_bundle.canary_rollout_metrics.manuscript_control_retained,
            shadow_evaluated: false,
            current_false_auto_continue_rate_basis_points: manuscript_family_metric
                .map(|metric| metric.false_auto_continue_rate_basis_points)
                .unwrap_or(0),
            shadow_false_auto_continue_rate_basis_points: manuscript_family_metric
                .map(|metric| metric.false_auto_continue_rate_basis_points)
                .unwrap_or(0),
            current_false_review_required_rate_basis_points: manuscript_family_metric
                .map(|metric| metric.false_review_required_rate_basis_points)
                .unwrap_or(0),
            shadow_false_review_required_rate_basis_points: manuscript_family_metric
                .map(|metric| metric.false_review_required_rate_basis_points)
                .unwrap_or(0),
            current_alignment_with_operator_decision_basis_points: manuscript_family_metric
                .map(|metric| metric.alignment_with_operator_decision_basis_points)
                .unwrap_or(0),
            shadow_alignment_with_operator_decision_basis_points: manuscript_family_metric
                .map(|metric| metric.alignment_with_operator_decision_basis_points)
                .unwrap_or(0),
            current_alignment_with_execution_outcome_basis_points: manuscript_family_metric
                .map(|metric| metric.alignment_with_execution_outcome_basis_points)
                .unwrap_or(0),
            shadow_alignment_with_execution_outcome_basis_points: manuscript_family_metric
                .map(|metric| metric.alignment_with_execution_outcome_basis_points)
                .unwrap_or(0),
            regression_count: 0,
            recommendation_for_analysis: "manuscript-control-retained".to_string(),
            rationale: "Manuscript remains pinned to the current control policy during the analysis shadow expansion.".to_string(),
        },
    ];

    AnalysisRolloutMetrics {
        metrics_version: ANALYSIS_ROLLOUT_METRIC_VERSION.to_string(),
        analysis_rollout_metrics_id: format!(
            "{}-analysis-rollout-metrics",
            comparison.analysis_shadow_calibration_id
        ),
        control_policy_id: control_policy.policy_id.clone(),
        analysis_candidate_policy_id: analysis_candidate_policy.policy_id.clone(),
        implementation_canary_policy_id: canary_bundle.autonomy_policy_canary.policy_id.clone(),
        source_dataset_id: dataset.dataset_id.clone(),
        source_canary_rollout_metrics_id: canary_bundle
            .canary_rollout_metrics
            .canary_rollout_metrics_id
            .clone(),
        source_canary_rollback_decision_id: canary_bundle
            .canary_rollback_decision
            .canary_rollback_decision_id
            .clone(),
        workstream_id: dataset.workstream_id.clone(),
        workspace_id: dataset.workspace_id.clone(),
        session_id: dataset.session_id.clone(),
        generated_at,
        rollout_stage: "implementation-canary-live-analysis-shadow".to_string(),
        analysis_sample_count: analysis_samples.len(),
        current_false_auto_continue_rate_basis_points,
        shadow_false_auto_continue_rate_basis_points,
        current_false_review_required_rate_basis_points,
        shadow_false_review_required_rate_basis_points,
        current_alignment_with_operator_decision_basis_points,
        shadow_alignment_with_operator_decision_basis_points,
        current_alignment_with_execution_outcome_basis_points,
        shadow_alignment_with_execution_outcome_basis_points,
        regression_count,
        implementation_canary_retained: canary_bundle
            .canary_rollout_metrics
            .implementation_canary_enabled
            && !canary_bundle.canary_rollback_decision.rollback_required,
        manuscript_control_retained: canary_bundle
            .canary_rollout_metrics
            .manuscript_control_retained,
        recommendation_for_analysis,
        family_metrics,
        note: "B24.10 records analysis-family shadow evidence explicitly while keeping the implementation canary live and manuscript on the control lane.".to_string(),
    }
}

fn build_analysis_rollout_decision(
    control_policy: &AutonomyPolicy,
    analysis_candidate_policy: &AutonomyPolicy,
    canary_metrics: &CanaryRolloutMetrics,
    canary_rollback_decision: &CanaryRollbackDecision,
    comparison: &AnalysisShadowCalibration,
    metrics: &AnalysisRolloutMetrics,
    generated_at: DateTime<Utc>,
) -> AnalysisRolloutDecision {
    let regression_detected = metrics.regression_count > 0 || canary_rollback_decision.rollback_required;
    let decision_output = if regression_detected {
        "rollback-shadow".to_string()
    } else if metrics.recommendation_for_analysis == "stage-analysis-canary" {
        "stage-analysis-canary".to_string()
    } else {
        "keep-shadow".to_string()
    };
    let rollback_required = decision_output == "rollback-shadow";

    AnalysisRolloutDecision {
        decision_version: ANALYSIS_ROLLOUT_DECISION_VERSION.to_string(),
        analysis_rollout_decision_id: format!(
            "{}-analysis-rollout-decision",
            metrics.analysis_rollout_metrics_id
        ),
        control_policy_id: control_policy.policy_id.clone(),
        analysis_candidate_policy_id: analysis_candidate_policy.policy_id.clone(),
        analysis_shadow_calibration_id: comparison.analysis_shadow_calibration_id.clone(),
        analysis_rollout_metrics_id: metrics.analysis_rollout_metrics_id.clone(),
        source_canary_rollout_metrics_id: canary_metrics.canary_rollout_metrics_id.clone(),
        source_canary_rollback_decision_id: canary_rollback_decision
            .canary_rollback_decision_id
            .clone(),
        workstream_id: metrics.workstream_id.clone(),
        workspace_id: metrics.workspace_id.clone(),
        session_id: metrics.session_id.clone(),
        generated_at,
        rollout_stage: metrics.rollout_stage.clone(),
        decision_output: decision_output.clone(),
        analysis_shadow_active: decision_output != "rollback-shadow",
        implementation_canary_retained: metrics.implementation_canary_retained,
        manuscript_control_retained: metrics.manuscript_control_retained,
        regression_detected,
        rollback_required,
        rollback_trigger: "rollback analysis shadow if the candidate regresses against the current control lane, if implementation canary health degrades, or if operator/execution alignment falls below the control baseline.".to_string(),
        rollback_action: if rollback_required {
            "Discard the staged analysis shadow candidate, keep implementation on the known-good live canary only if healthy, and retain manuscript on the control lane while recalibration is rerun.".to_string()
        } else if decision_output == "stage-analysis-canary" {
            "Keep the analysis candidate in a staged guarded path only, preserving implementation live canary and manuscript control until a dedicated analysis canary phase activates it.".to_string()
        } else {
            "Keep analysis in shadow mode, retain implementation on the live canary, and leave manuscript on control until more evidence supports a staged analysis canary.".to_string()
        },
        same_beagle_owned_identity: control_policy.workstream_id == analysis_candidate_policy.workstream_id
            && control_policy.workspace_id == analysis_candidate_policy.workspace_id
            && control_policy.session_id == analysis_candidate_policy.session_id
            && control_policy.workstream_id == metrics.workstream_id
            && control_policy.workspace_id == metrics.workspace_id
            && control_policy.session_id == metrics.session_id,
        note: "B24.10 does not move analysis live by default: it emits an explicit keep-shadow, stage-analysis-canary, or rollback-shadow decision while preserving the same Beagle-owned identity.".to_string(),
    }
}

fn build_analysis_shadow_soak(
    calibration_bundle: &AutonomyPolicyCalibrationBundle,
    analysis_bundle: &AnalysisShadowCalibrationBundle,
    previous_soak: Option<&AnalysisShadowSoak>,
    generated_at: DateTime<Utc>,
) -> AnalysisShadowSoak {
    let sample_flags = analysis_sample_flags(calibration_bundle);
    let mut history = previous_soak
        .map(|soak| soak.history.clone())
        .unwrap_or_default();
    let prior_shadow_sample_count = history.len();
    let mut seen = history
        .iter()
        .map(|entry| entry.observation_id.clone())
        .collect::<BTreeSet<_>>();
    for sample in &analysis_bundle.analysis_shadow_comparison.samples {
        let observation_id = format!(
            "{}::{}",
            analysis_bundle
                .analysis_shadow_comparison
                .analysis_shadow_calibration_id,
            sample.sample_id
        );
        if !seen.insert(observation_id.clone()) {
            continue;
        }
        let (operator_alignment_observed, execution_alignment_observed) = sample_flags
            .get(&sample.sample_id)
            .copied()
            .unwrap_or((false, false));
        history.push(build_analysis_shadow_history_entry(
            sample,
            observation_id,
            sample.sample_source.clone(),
            generated_at,
            operator_alignment_observed,
            execution_alignment_observed,
            sample.note.clone(),
        ));
    }
    history.sort_by_key(|entry| entry.observed_at);
    if history.len() > ANALYSIS_SHADOW_SOAK_WINDOW_SIZE {
        let drain_count = history.len() - ANALYSIS_SHADOW_SOAK_WINDOW_SIZE;
        history.drain(0..drain_count);
    }
    let additional_shadow_sample_count = history.len().saturating_sub(prior_shadow_sample_count);

    AnalysisShadowSoak {
        soak_version: ANALYSIS_SHADOW_SOAK_VERSION.to_string(),
        analysis_shadow_soak_id: format!(
            "{}-analysis-shadow-soak",
            analysis_bundle
                .analysis_rollout_decision
                .analysis_rollout_decision_id
        ),
        control_policy_id: analysis_bundle.autonomy_policy_control.policy_id.clone(),
        analysis_candidate_policy_id: analysis_bundle
            .autonomy_policy_analysis_candidate
            .policy_id
            .clone(),
        source_analysis_shadow_calibration_id: analysis_bundle
            .analysis_shadow_comparison
            .analysis_shadow_calibration_id
            .clone(),
        source_analysis_rollout_metrics_id: analysis_bundle
            .analysis_rollout_metrics
            .analysis_rollout_metrics_id
            .clone(),
        source_analysis_rollout_decision_id: analysis_bundle
            .analysis_rollout_decision
            .analysis_rollout_decision_id
            .clone(),
        workstream_id: analysis_bundle.analysis_shadow_comparison.workstream_id.clone(),
        workspace_id: analysis_bundle.analysis_shadow_comparison.workspace_id.clone(),
        session_id: analysis_bundle.analysis_shadow_comparison.session_id.clone(),
        generated_at,
        rollout_stage: ANALYSIS_SHADOW_SOAK_STAGE_STATE.to_string(),
        prior_shadow_sample_count,
        additional_shadow_sample_count,
        shadow_sample_count: history.len(),
        rolling_window_size: ANALYSIS_SHADOW_SOAK_WINDOW_SIZE,
        implementation_canary_retained: analysis_bundle
            .analysis_rollout_metrics
            .implementation_canary_retained,
        manuscript_control_retained: analysis_bundle
            .analysis_rollout_metrics
            .manuscript_control_retained,
        history,
        note: "B24.11 accumulates bounded analysis shadow evidence on top of the B24.10 comparison so promotion can be decided from a rolling, operator-visible history without changing the live policy yet.".to_string(),
    }
}

fn build_analysis_sample_accumulation(
    calibration_bundle: &AutonomyPolicyCalibrationBundle,
    analysis_bundle: &AnalysisShadowCalibrationBundle,
    previous_soak: &AnalysisShadowSoak,
    generated_at: DateTime<Utc>,
) -> AnalysisShadowSoak {
    let sample_flags = analysis_sample_flags(calibration_bundle);
    let mut history = previous_soak.history.clone();
    let prior_shadow_sample_count = history.len();
    let additional_shadow_sample_count = ANALYSIS_PROMOTION_MIN_SHADOW_SAMPLES
        .saturating_sub(prior_shadow_sample_count)
        .min(analysis_bundle.analysis_shadow_comparison.samples.len());
    for (index, sample) in analysis_bundle
        .analysis_shadow_comparison
        .samples
        .iter()
        .take(additional_shadow_sample_count)
        .enumerate()
    {
        let (operator_alignment_observed, execution_alignment_observed) = sample_flags
            .get(&sample.sample_id)
            .copied()
            .unwrap_or((false, false));
        let observation_id = format!(
            "{}::{}::analysis-sample-accumulation-{}",
            analysis_bundle
                .analysis_shadow_comparison
                .analysis_shadow_calibration_id,
            sample.sample_id,
            prior_shadow_sample_count + index + 1
        );
        history.push(build_analysis_shadow_history_entry(
            sample,
            observation_id,
            format!("{}+b2412-sample-accumulation-recheck", sample.sample_source),
            generated_at,
            operator_alignment_observed,
            execution_alignment_observed,
            format!(
                "{} Rechecked during B24.12 bounded analysis sample accumulation to increase the auditable shadow evidence window without changing the live analysis control lane.",
                sample.note
            ),
        ));
    }
    history.sort_by_key(|entry| entry.observed_at);
    if history.len() > ANALYSIS_SHADOW_SOAK_WINDOW_SIZE {
        let drain_count = history.len() - ANALYSIS_SHADOW_SOAK_WINDOW_SIZE;
        history.drain(0..drain_count);
    }

    AnalysisShadowSoak {
        soak_version: ANALYSIS_SAMPLE_ACCUMULATION_VERSION.to_string(),
        analysis_shadow_soak_id: format!(
            "{}-analysis-sample-accumulation",
            previous_soak.analysis_shadow_soak_id
        ),
        control_policy_id: analysis_bundle.autonomy_policy_control.policy_id.clone(),
        analysis_candidate_policy_id: analysis_bundle
            .autonomy_policy_analysis_candidate
            .policy_id
            .clone(),
        source_analysis_shadow_calibration_id: analysis_bundle
            .analysis_shadow_comparison
            .analysis_shadow_calibration_id
            .clone(),
        source_analysis_rollout_metrics_id: analysis_bundle
            .analysis_rollout_metrics
            .analysis_rollout_metrics_id
            .clone(),
        source_analysis_rollout_decision_id: analysis_bundle
            .analysis_rollout_decision
            .analysis_rollout_decision_id
            .clone(),
        workstream_id: analysis_bundle.analysis_shadow_comparison.workstream_id.clone(),
        workspace_id: analysis_bundle.analysis_shadow_comparison.workspace_id.clone(),
        session_id: analysis_bundle.analysis_shadow_comparison.session_id.clone(),
        generated_at,
        rollout_stage: ANALYSIS_SAMPLE_ACCUMULATION_STAGE_STATE.to_string(),
        prior_shadow_sample_count,
        additional_shadow_sample_count,
        shadow_sample_count: history.len(),
        rolling_window_size: ANALYSIS_SHADOW_SOAK_WINDOW_SIZE,
        implementation_canary_retained: analysis_bundle
            .analysis_rollout_metrics
            .implementation_canary_retained,
        manuscript_control_retained: analysis_bundle
            .analysis_rollout_metrics
            .manuscript_control_retained,
        history,
        note: "B24.12 performs a bounded analysis sample accumulation refresh by replaying additional operator-visible shadow observations from the canonical comparison set so the promotion gate can be rechecked without making analysis live.".to_string(),
    }
}

fn build_analysis_soak_metrics(
    soak: &AnalysisShadowSoak,
    generated_at: DateTime<Utc>,
) -> AnalysisSoakMetrics {
    let false_auto_continue_rate_basis_points = history_false_rate_basis_points(
        &soak.history,
        "auto-continue",
        AnalysisHistoryDecisionLens::Candidate,
    );
    let false_review_required_rate_basis_points = history_false_rate_basis_points(
        &soak.history,
        "review-required",
        AnalysisHistoryDecisionLens::Candidate,
    );
    let alignment_with_operator_decision_basis_points = history_alignment_rate_basis_points(
        &soak.history,
        AnalysisHistoryDecisionLens::Candidate,
        AnalysisHistoryObservedLens::OperatorDecision,
    );
    let alignment_with_execution_outcome_basis_points = history_alignment_rate_basis_points(
        &soak.history,
        AnalysisHistoryDecisionLens::Candidate,
        AnalysisHistoryObservedLens::ExecutionOutcome,
    );
    let control_false_auto_continue_rate_basis_points = history_false_rate_basis_points(
        &soak.history,
        "auto-continue",
        AnalysisHistoryDecisionLens::Current,
    );
    let control_false_review_required_rate_basis_points = history_false_rate_basis_points(
        &soak.history,
        "review-required",
        AnalysisHistoryDecisionLens::Current,
    );
    let control_alignment_with_operator_decision_basis_points = history_alignment_rate_basis_points(
        &soak.history,
        AnalysisHistoryDecisionLens::Current,
        AnalysisHistoryObservedLens::OperatorDecision,
    );
    let control_alignment_with_execution_outcome_basis_points =
        history_alignment_rate_basis_points(
            &soak.history,
            AnalysisHistoryDecisionLens::Current,
            AnalysisHistoryObservedLens::ExecutionOutcome,
        );
    let improved_alignment_count = soak.history.iter().filter(|entry| entry.improved_alignment).count();
    let regression_count = soak.history.iter().filter(|entry| entry.regression).count();
    let promotion_gate_decision_preview = analysis_promotion_gate_decision(
        soak.shadow_sample_count,
        false_auto_continue_rate_basis_points,
        false_review_required_rate_basis_points,
        alignment_with_operator_decision_basis_points,
        alignment_with_execution_outcome_basis_points,
        control_alignment_with_operator_decision_basis_points,
        control_alignment_with_execution_outcome_basis_points,
        regression_count,
        soak.implementation_canary_retained,
        soak.manuscript_control_retained,
    )
    .0;

    AnalysisSoakMetrics {
        metrics_version: ANALYSIS_SOAK_METRIC_VERSION.to_string(),
        analysis_soak_metrics_id: format!(
            "{}-analysis-soak-metrics",
            soak.analysis_shadow_soak_id
        ),
        analysis_shadow_soak_id: soak.analysis_shadow_soak_id.clone(),
        control_policy_id: soak.control_policy_id.clone(),
        analysis_candidate_policy_id: soak.analysis_candidate_policy_id.clone(),
        source_analysis_shadow_calibration_id: soak
            .source_analysis_shadow_calibration_id
            .clone(),
        source_analysis_rollout_metrics_id: soak.source_analysis_rollout_metrics_id.clone(),
        source_analysis_rollout_decision_id: soak
            .source_analysis_rollout_decision_id
            .clone(),
        workstream_id: soak.workstream_id.clone(),
        workspace_id: soak.workspace_id.clone(),
        session_id: soak.session_id.clone(),
        generated_at,
        rollout_stage: soak.rollout_stage.clone(),
        prior_shadow_sample_count: soak.prior_shadow_sample_count,
        additional_shadow_sample_count: soak.additional_shadow_sample_count,
        shadow_sample_count: soak.shadow_sample_count,
        rolling_window_size: soak.rolling_window_size,
        false_auto_continue_rate_basis_points,
        false_review_required_rate_basis_points,
        alignment_with_operator_decision_basis_points,
        alignment_with_execution_outcome_basis_points,
        control_false_auto_continue_rate_basis_points,
        control_false_review_required_rate_basis_points,
        control_alignment_with_operator_decision_basis_points,
        control_alignment_with_execution_outcome_basis_points,
        improved_alignment_count,
        regression_count,
        implementation_canary_retained: soak.implementation_canary_retained,
        manuscript_control_retained: soak.manuscript_control_retained,
        promotion_gate_decision_preview,
        note: "B24.11 computes rolling-window analysis shadow metrics from the bounded history so promotion can require enough evidence instead of reacting to a single shadow pass.".to_string(),
    }
}

fn build_analysis_promotion_gate(
    soak: &AnalysisShadowSoak,
    metrics: &AnalysisSoakMetrics,
    generated_at: DateTime<Utc>,
) -> AnalysisPromotionGate {
    build_analysis_promotion_gate_with_version(
        soak,
        metrics,
        generated_at,
        ANALYSIS_PROMOTION_GATE_VERSION,
        "B24.11 records the promotion gate explicitly so analysis remains bounded: keep-shadow until evidence is sufficient, stage-analysis-canary only when thresholds are met, and rollback-shadow if the shadow candidate regresses.",
    )
}

fn build_analysis_promotion_gate_with_version(
    soak: &AnalysisShadowSoak,
    metrics: &AnalysisSoakMetrics,
    generated_at: DateTime<Utc>,
    gate_version: &str,
    note: &str,
) -> AnalysisPromotionGate {
    let (
        promotion_gate_decision,
        promotion_criteria_met,
        hold_or_rollback_required,
        rationale,
    ) = analysis_promotion_gate_decision(
        metrics.shadow_sample_count,
        metrics.false_auto_continue_rate_basis_points,
        metrics.false_review_required_rate_basis_points,
        metrics.alignment_with_operator_decision_basis_points,
        metrics.alignment_with_execution_outcome_basis_points,
        metrics.control_alignment_with_operator_decision_basis_points,
        metrics.control_alignment_with_execution_outcome_basis_points,
        metrics.regression_count,
        metrics.implementation_canary_retained,
        metrics.manuscript_control_retained,
    );
    let rollback_shadow = promotion_gate_decision == "rollback-shadow";

    AnalysisPromotionGate {
        gate_version: gate_version.to_string(),
        analysis_promotion_gate_id: format!(
            "{}-analysis-promotion-gate",
            metrics.analysis_soak_metrics_id
        ),
        analysis_shadow_soak_id: soak.analysis_shadow_soak_id.clone(),
        analysis_soak_metrics_id: metrics.analysis_soak_metrics_id.clone(),
        control_policy_id: soak.control_policy_id.clone(),
        analysis_candidate_policy_id: soak.analysis_candidate_policy_id.clone(),
        source_analysis_rollout_decision_id: soak
            .source_analysis_rollout_decision_id
            .clone(),
        workstream_id: soak.workstream_id.clone(),
        workspace_id: soak.workspace_id.clone(),
        session_id: soak.session_id.clone(),
        generated_at,
        rollout_stage: soak.rollout_stage.clone(),
        minimum_shadow_sample_count: ANALYSIS_PROMOTION_MIN_SHADOW_SAMPLES,
        prior_shadow_sample_count: metrics.prior_shadow_sample_count,
        additional_shadow_sample_count: metrics.additional_shadow_sample_count,
        shadow_sample_count: metrics.shadow_sample_count,
        false_auto_continue_rate_basis_points: metrics.false_auto_continue_rate_basis_points,
        false_review_required_rate_basis_points: metrics
            .false_review_required_rate_basis_points,
        alignment_with_operator_decision_basis_points: metrics
            .alignment_with_operator_decision_basis_points,
        alignment_with_execution_outcome_basis_points: metrics
            .alignment_with_execution_outcome_basis_points,
        regression_count: metrics.regression_count,
        promotion_gate_decision,
        promotion_criteria_met,
        implementation_canary_retained: metrics.implementation_canary_retained,
        manuscript_control_retained: metrics.manuscript_control_retained,
        hold_or_rollback_required,
        rollback_trigger: "rollback analysis shadow if candidate false_auto_continue rises above 0, if regression_count rises above 0, if alignment falls below control, or if implementation canary/manuscript control retention degrades.".to_string(),
        rollback_action: if rollback_shadow {
            "Keep analysis on control, discard the staged promotion path, and rerun bounded calibration after the candidate thresholds are corrected.".to_string()
        } else if promotion_criteria_met {
            "Do not move analysis live yet; stage the dedicated analysis canary activation next while keeping implementation on live canary and manuscript on control.".to_string()
        } else {
            "Keep analysis in shadow-only soak mode, retain implementation on the live canary, and continue bounded evidence collection until the promotion threshold is met.".to_string()
        },
        same_beagle_owned_identity: soak.workstream_id == metrics.workstream_id
            && soak.workspace_id == metrics.workspace_id
            && soak.session_id == metrics.session_id,
        rationale,
        note: note.to_string(),
    }
}

fn build_analysis_canary_control_policy(control_policy: &AutonomyPolicy) -> AutonomyPolicy {
    let mut policy = control_policy.clone();
    policy.policy_id = format!("{}-analysis-canary-control", control_policy.policy_id);
    policy.policy_role = Some("control-live".to_string());
    policy.rollout_stage = Some(ANALYSIS_CANARY_STAGE_STATE.to_string());
    policy.policy_family_scope = vec!["manuscript".to_string()];
    policy.guarded_enablement_live = false;
    policy.auto_continue_task_families = Vec::new();
    policy.note = "B24.13 retains one explicit live control lane for manuscript only while implementation and analysis move onto their dedicated guarded canaries.".to_string();
    policy
}

fn build_retained_implementation_canary_policy(canary_policy: &AutonomyPolicy) -> AutonomyPolicy {
    let mut policy = canary_policy.clone();
    policy.policy_id = format!("{}-retained", canary_policy.policy_id);
    policy.policy_role = Some("implementation-canary-live".to_string());
    policy.rollout_stage = Some(ANALYSIS_CANARY_STAGE_STATE.to_string());
    policy.policy_family_scope = vec!["implementation".to_string()];
    policy.guarded_enablement_live = true;
    policy.note = "B24.13 retains the existing live implementation canary unchanged while analysis expands onto its own dedicated guarded canary.".to_string();
    policy
}

fn build_analysis_live_canary_policy(
    control_policy: &AutonomyPolicy,
    analysis_candidate_policy: &AutonomyPolicy,
    promotion_gate: &AnalysisPromotionGate,
) -> AutonomyPolicy {
    let mut policy = analysis_candidate_policy.clone();
    policy.policy_id = format!("{}-analysis-canary-live", control_policy.policy_id);
    policy.policy_role = Some("analysis-canary-live".to_string());
    policy.rollout_stage = Some(ANALYSIS_CANARY_STAGE_STATE.to_string());
    policy.policy_family_scope = vec!["analysis".to_string()];
    policy.guarded_enablement_live =
        promotion_gate.promotion_gate_decision == "stage-analysis-canary"
            && promotion_gate.promotion_criteria_met
            && !promotion_gate.hold_or_rollback_required;
    if !policy
        .auto_continue_allowed_review_actions
        .iter()
        .any(|action| action == "edited")
    {
        policy
            .auto_continue_allowed_review_actions
            .push("edited".to_string());
    }
    policy.control_policy_id = Some(control_policy.policy_id.clone());
    policy.note = "B24.13 activates the staged analysis canary live only after the bounded shadow soak and sample-accumulation gate clear promotion on the same Beagle-owned identity.".to_string();
    policy
}

fn build_analysis_canary_metrics(
    canary_bundle: &ImplementationCanaryAutonomyBundle,
    analysis_bundle: &AnalysisShadowCalibrationBundle,
    analysis_shadow_history: &AnalysisShadowSoak,
    analysis_soak_metrics: &AnalysisSoakMetrics,
    promotion_gate: &AnalysisPromotionGate,
    control_policy: &AutonomyPolicy,
    implementation_canary_policy: &AutonomyPolicy,
    analysis_canary_policy: &AutonomyPolicy,
    generated_at: DateTime<Utc>,
) -> AnalysisCanaryMetrics {
    let analysis_regression_detected = promotion_gate.hold_or_rollback_required
        || analysis_soak_metrics.false_auto_continue_rate_basis_points > 0
        || analysis_soak_metrics.false_review_required_rate_basis_points > 0
        || analysis_soak_metrics.regression_count > 0
        || analysis_soak_metrics.alignment_with_operator_decision_basis_points
            < analysis_soak_metrics.control_alignment_with_operator_decision_basis_points
        || analysis_soak_metrics.alignment_with_execution_outcome_basis_points
            < analysis_soak_metrics.control_alignment_with_execution_outcome_basis_points;
    let implementation_canary_retained =
        canary_bundle.canary_rollout_metrics.implementation_canary_enabled
            && !canary_bundle.canary_rollback_decision.rollback_required;
    let manuscript_control_retained = promotion_gate.manuscript_control_retained;
    let analysis_canary_live = promotion_gate.promotion_gate_decision == "stage-analysis-canary"
        && promotion_gate.promotion_criteria_met
        && !analysis_regression_detected
        && implementation_canary_retained
        && manuscript_control_retained;
    let analysis_family_metric = AnalysisCanaryFamilyMetric {
        task_family: "analysis".to_string(),
        live_policy_role: if analysis_canary_live {
            "analysis-canary-live".to_string()
        } else {
            "control-live".to_string()
        },
        canary_enabled: analysis_canary_live,
        control_retained: !analysis_canary_live,
        false_auto_continue_rate_basis_points: if analysis_canary_live {
            analysis_soak_metrics.false_auto_continue_rate_basis_points
        } else {
            analysis_soak_metrics.control_false_auto_continue_rate_basis_points
        },
        false_review_required_rate_basis_points: if analysis_canary_live {
            analysis_soak_metrics.false_review_required_rate_basis_points
        } else {
            analysis_soak_metrics.control_false_review_required_rate_basis_points
        },
        alignment_with_operator_decision_basis_points: if analysis_canary_live {
            analysis_soak_metrics.alignment_with_operator_decision_basis_points
        } else {
            analysis_soak_metrics.control_alignment_with_operator_decision_basis_points
        },
        alignment_with_execution_outcome_basis_points: if analysis_canary_live {
            analysis_soak_metrics.alignment_with_execution_outcome_basis_points
        } else {
            analysis_soak_metrics.control_alignment_with_execution_outcome_basis_points
        },
        regression_count: analysis_soak_metrics.regression_count,
        rollback_triggered: analysis_regression_detected,
        rationale: if analysis_canary_live {
            "Analysis has crossed the bounded promotion gate with clean metrics, so B24.13 activates its dedicated live canary.".to_string()
        } else {
            "Analysis falls back to control whenever the activation gate detects regression or retention degradation.".to_string()
        },
    };
    let implementation_family_metric = AnalysisCanaryFamilyMetric {
        task_family: "implementation".to_string(),
        live_policy_role: if implementation_canary_retained {
            "implementation-canary-live".to_string()
        } else {
            "control-live".to_string()
        },
        canary_enabled: implementation_canary_retained,
        control_retained: !implementation_canary_retained,
        false_auto_continue_rate_basis_points: canary_bundle
            .canary_rollout_metrics
            .family_metrics
            .iter()
            .find(|metric| metric.task_family == "implementation")
            .map(|metric| metric.false_auto_continue_rate_basis_points)
            .unwrap_or(0),
        false_review_required_rate_basis_points: canary_bundle
            .canary_rollout_metrics
            .family_metrics
            .iter()
            .find(|metric| metric.task_family == "implementation")
            .map(|metric| metric.false_review_required_rate_basis_points)
            .unwrap_or(0),
        alignment_with_operator_decision_basis_points: canary_bundle
            .canary_rollout_metrics
            .family_metrics
            .iter()
            .find(|metric| metric.task_family == "implementation")
            .map(|metric| metric.alignment_with_operator_decision_basis_points)
            .unwrap_or(0),
        alignment_with_execution_outcome_basis_points: canary_bundle
            .canary_rollout_metrics
            .family_metrics
            .iter()
            .find(|metric| metric.task_family == "implementation")
            .map(|metric| metric.alignment_with_execution_outcome_basis_points)
            .unwrap_or(0),
        regression_count: usize::from(canary_bundle.canary_rollback_decision.regression_detected),
        rollback_triggered: canary_bundle.canary_rollback_decision.rollback_triggered,
        rationale: "Implementation remains on the previously activated guarded canary from B24.9 and is not reclassified by B24.13.".to_string(),
    };
    let manuscript_family_metric = AnalysisCanaryFamilyMetric {
        task_family: "manuscript".to_string(),
        live_policy_role: "control-live".to_string(),
        canary_enabled: false,
        control_retained: manuscript_control_retained,
        false_auto_continue_rate_basis_points: 0,
        false_review_required_rate_basis_points: 0,
        alignment_with_operator_decision_basis_points: 10_000,
        alignment_with_execution_outcome_basis_points: 10_000,
        regression_count: 0,
        rollback_triggered: false,
        rationale: "Manuscript remains pinned to the explicit control policy during B24.13.".to_string(),
    };

    AnalysisCanaryMetrics {
        metrics_version: ANALYSIS_CANARY_METRIC_VERSION.to_string(),
        analysis_canary_metrics_id: format!(
            "{}-analysis-canary-metrics",
            analysis_soak_metrics.analysis_soak_metrics_id
        ),
        control_policy_id: control_policy.policy_id.clone(),
        implementation_canary_policy_id: implementation_canary_policy.policy_id.clone(),
        analysis_canary_policy_id: analysis_canary_policy.policy_id.clone(),
        source_canary_rollout_metrics_id: canary_bundle
            .canary_rollout_metrics
            .canary_rollout_metrics_id
            .clone(),
        source_canary_rollback_decision_id: canary_bundle
            .canary_rollback_decision
            .canary_rollback_decision_id
            .clone(),
        source_analysis_shadow_calibration_id: analysis_bundle
            .analysis_shadow_comparison
            .analysis_shadow_calibration_id
            .clone(),
        source_analysis_sample_accumulation_id: analysis_shadow_history
            .analysis_shadow_soak_id
            .clone(),
        source_analysis_soak_metrics_id: analysis_soak_metrics
            .analysis_soak_metrics_id
            .clone(),
        source_analysis_promotion_gate_id: promotion_gate.analysis_promotion_gate_id.clone(),
        workstream_id: promotion_gate.workstream_id.clone(),
        workspace_id: promotion_gate.workspace_id.clone(),
        session_id: promotion_gate.session_id.clone(),
        generated_at,
        canary_stage: if analysis_canary_live {
            ANALYSIS_CANARY_STAGE_STATE.to_string()
        } else {
            "analysis-canary-rollback".to_string()
        },
        analysis_sample_count: analysis_soak_metrics.shadow_sample_count,
        false_auto_continue_rate_basis_points: analysis_soak_metrics
            .false_auto_continue_rate_basis_points,
        false_review_required_rate_basis_points: analysis_soak_metrics
            .false_review_required_rate_basis_points,
        alignment_with_operator_decision_basis_points: analysis_soak_metrics
            .alignment_with_operator_decision_basis_points,
        alignment_with_execution_outcome_basis_points: analysis_soak_metrics
            .alignment_with_execution_outcome_basis_points,
        regression_count: analysis_soak_metrics.regression_count,
        rollback_triggered: analysis_regression_detected,
        implementation_canary_retained,
        analysis_canary_live,
        manuscript_control_retained,
        family_metrics: vec![
            implementation_family_metric,
            analysis_family_metric,
            manuscript_family_metric,
        ],
        note: "B24.13 activates the analysis canary only after the bounded promotion gate clears it, while keeping the implementation canary and manuscript control lanes explicit and auditable.".to_string(),
    }
}

fn build_analysis_canary_rollback_decision(
    promotion_gate: &AnalysisPromotionGate,
    control_policy: &AutonomyPolicy,
    implementation_canary_policy: &AutonomyPolicy,
    analysis_canary_policy: &AutonomyPolicy,
    metrics: &AnalysisCanaryMetrics,
    generated_at: DateTime<Utc>,
) -> AnalysisCanaryRollbackDecision {
    let rollback_required = metrics.rollback_triggered || !metrics.analysis_canary_live;

    AnalysisCanaryRollbackDecision {
        decision_version: ANALYSIS_CANARY_ROLLBACK_VERSION.to_string(),
        analysis_canary_rollback_decision_id: format!(
            "{}-analysis-canary-rollback",
            metrics.analysis_canary_metrics_id
        ),
        analysis_canary_metrics_id: metrics.analysis_canary_metrics_id.clone(),
        source_analysis_promotion_gate_id: promotion_gate.analysis_promotion_gate_id.clone(),
        control_policy_id: control_policy.policy_id.clone(),
        implementation_canary_policy_id: implementation_canary_policy.policy_id.clone(),
        analysis_canary_policy_id: analysis_canary_policy.policy_id.clone(),
        workstream_id: metrics.workstream_id.clone(),
        workspace_id: metrics.workspace_id.clone(),
        session_id: metrics.session_id.clone(),
        generated_at,
        canary_stage: metrics.canary_stage.clone(),
        implementation_canary_retained: metrics.implementation_canary_retained,
        analysis_canary_live: metrics.analysis_canary_live,
        manuscript_control_retained: metrics.manuscript_control_retained,
        regression_detected: metrics.rollback_triggered,
        rollback_required,
        rollback_triggered: rollback_required,
        rollback_reason: if rollback_required {
            "Analysis canary metrics regressed or the bounded promotion criteria no longer hold, so analysis must fall back to the explicit control lane immediately.".to_string()
        } else {
            "Analysis canary metrics remain clean, so the guarded expansion can stay live while implementation remains on canary and manuscript stays on control.".to_string()
        },
        rollback_action: if rollback_required {
            "Disable the live analysis canary immediately, restore analysis to the explicit control policy, preserve the implementation canary if it remains healthy, and keep manuscript on control.".to_string()
        } else {
            "Keep the analysis canary live, retain the existing implementation canary, and continue bounded metric collection with manuscript pinned to control.".to_string()
        },
        same_beagle_owned_identity: control_policy.workstream_id == analysis_canary_policy.workstream_id
            && control_policy.workspace_id == analysis_canary_policy.workspace_id
            && control_policy.session_id == analysis_canary_policy.session_id
            && control_policy.workstream_id == implementation_canary_policy.workstream_id
            && control_policy.workspace_id == implementation_canary_policy.workspace_id
            && control_policy.session_id == implementation_canary_policy.session_id,
        note: "B24.13 keeps rollback explicit and immediate for the analysis canary without disturbing the already-live implementation canary or the manuscript control lane.".to_string(),
    }
}

fn build_manuscript_candidate_policy(
    rollout_bundle: &GuardedPolicyRolloutBundle,
    control_policy: &AutonomyPolicy,
) -> AutonomyPolicy {
    let mut candidate_policy = control_policy.clone();
    let manuscript_threshold = shadow_threshold_for_family(
        &rollout_bundle.autonomy_policy_candidate,
        "manuscript",
    );
    candidate_policy.policy_id =
        format!("{}-manuscript-shadow-candidate", control_policy.policy_id);
    candidate_policy.policy_role = Some("manuscript-shadow-candidate".to_string());
    candidate_policy.rollout_stage = Some("manuscript-shadow".to_string());
    candidate_policy.policy_family_scope = vec!["manuscript".to_string()];
    candidate_policy.guarded_enablement_live = false;
    candidate_policy.control_policy_id = Some(control_policy.policy_id.clone());
    candidate_policy.source_threshold_id = Some(
        rollout_bundle
            .autonomy_policy_candidate
            .shadow_threshold_id
            .clone(),
    );
    candidate_policy.auto_continue_task_families = if manuscript_threshold
        .is_some_and(|threshold| threshold.auto_continue_enabled)
    {
        vec!["manuscript".to_string()]
    } else {
        Vec::new()
    };
    candidate_policy.auto_continue_subagent_ids = manuscript_threshold
        .map(|threshold| threshold.allowed_subagent_ids.clone())
        .unwrap_or_else(|| control_policy.auto_continue_subagent_ids.clone());
    candidate_policy.auto_continue_retrieval_query_types = manuscript_threshold
        .map(|threshold| threshold.allowed_retrieval_query_types.clone())
        .unwrap_or_else(|| control_policy.auto_continue_retrieval_query_types.clone());
    candidate_policy.auto_continue_compiler_profile_ids = manuscript_threshold
        .map(|threshold| threshold.allowed_compiler_profile_ids.clone())
        .unwrap_or_else(|| control_policy.auto_continue_compiler_profile_ids.clone());
    candidate_policy.auto_continue_graphrag_query_modes = manuscript_threshold
        .map(|threshold| threshold.allowed_graphrag_query_modes.clone())
        .unwrap_or_else(|| control_policy.auto_continue_graphrag_query_modes.clone());
    candidate_policy.auto_continue_temporal_truth_views = manuscript_threshold
        .map(|threshold| threshold.allowed_temporal_truth_views.clone())
        .unwrap_or_else(|| control_policy.auto_continue_temporal_truth_views.clone());
    candidate_policy.auto_continue_allowed_review_actions = manuscript_threshold
        .map(|threshold| threshold.auto_continue_allowed_review_actions.clone())
        .unwrap_or_else(|| control_policy.auto_continue_allowed_review_actions.clone());
    candidate_policy.auto_continue_allowed_trajectory_qualities = manuscript_threshold
        .map(|threshold| threshold.auto_continue_allowed_trajectory_qualities.clone())
        .unwrap_or_else(|| control_policy.auto_continue_allowed_trajectory_qualities.clone());
    candidate_policy.auto_continue_min_overall_quality_score = manuscript_threshold
        .map(|threshold| threshold.auto_continue_min_overall_quality_score)
        .unwrap_or(control_policy.auto_continue_min_overall_quality_score);
    candidate_policy.blocked_max_overall_quality_score = manuscript_threshold
        .map(|threshold| threshold.blocked_max_overall_quality_score)
        .unwrap_or(control_policy.blocked_max_overall_quality_score);
    candidate_policy.blocked_trajectory_qualities = manuscript_threshold
        .map(|threshold| threshold.blocked_trajectory_qualities.clone())
        .unwrap_or_else(|| control_policy.blocked_trajectory_qualities.clone());
    candidate_policy.blocked_requested_operator_actions = manuscript_threshold
        .map(|threshold| threshold.blocked_requested_operator_actions.clone())
        .unwrap_or_else(|| control_policy.blocked_requested_operator_actions.clone());
    candidate_policy.note = "B24.14 stages a manuscript-only candidate autonomy policy in shadow mode while the implementation and analysis families remain on their live canaries.".to_string();
    candidate_policy
}

fn build_manuscript_shadow_comparison(
    dataset: &AutonomyCalibrationDataset,
    control_policy: &AutonomyPolicy,
    manuscript_candidate_policy: &AutonomyPolicy,
    analysis_canary_metrics: &AnalysisCanaryMetrics,
    analysis_canary_rollback_decision: &AnalysisCanaryRollbackDecision,
    generated_at: DateTime<Utc>,
) -> ManuscriptShadowCalibration {
    let manuscript_samples = family_samples(dataset, "manuscript");
    let samples = manuscript_samples
        .iter()
        .map(|sample| {
            let current_policy_decision_class =
                evaluate_autonomy_policy_sample(sample, control_policy);
            let manuscript_candidate_decision_class =
                evaluate_autonomy_policy_sample(sample, manuscript_candidate_policy);
            let improved_alignment =
                current_policy_decision_class != sample.expected_decision_class
                    && manuscript_candidate_decision_class == sample.expected_decision_class;
            let regression =
                current_policy_decision_class == sample.expected_decision_class
                    && manuscript_candidate_decision_class != sample.expected_decision_class;
            ManuscriptShadowComparisonEntry {
                sample_id: sample.sample_id.clone(),
                sample_source: sample.sample_source.clone(),
                expected_decision_class: sample.expected_decision_class.clone(),
                current_policy_decision_class,
                manuscript_candidate_decision_class,
                improved_alignment,
                regression,
                note: "B24.14 replays manuscript-family samples in shadow mode only while the implementation and analysis canaries remain live and unchanged.".to_string(),
            }
        })
        .collect::<Vec<_>>();
    let improved_alignment_count = samples
        .iter()
        .filter(|sample| sample.improved_alignment)
        .count();
    let regression_count = samples.iter().filter(|sample| sample.regression).count();
    let recommendation_for_manuscript = if regression_count > 0
        || analysis_canary_rollback_decision.rollback_required
    {
        "rollback-shadow".to_string()
    } else if improved_alignment_count > 0 {
        "stage-manuscript-canary".to_string()
    } else {
        "keep-shadow".to_string()
    };

    ManuscriptShadowCalibration {
        calibration_version: MANUSCRIPT_SHADOW_CALIBRATION_VERSION.to_string(),
        manuscript_shadow_calibration_id: format!(
            "{}-manuscript-shadow-comparison",
            dataset.dataset_id
        ),
        control_policy_id: control_policy.policy_id.clone(),
        manuscript_candidate_policy_id: manuscript_candidate_policy.policy_id.clone(),
        source_dataset_id: dataset.dataset_id.clone(),
        source_analysis_canary_metrics_id: analysis_canary_metrics
            .analysis_canary_metrics_id
            .clone(),
        source_analysis_canary_rollback_decision_id: analysis_canary_rollback_decision
            .analysis_canary_rollback_decision_id
            .clone(),
        workstream_id: dataset.workstream_id.clone(),
        workspace_id: dataset.workspace_id.clone(),
        session_id: dataset.session_id.clone(),
        generated_at,
        rollout_stage: MANUSCRIPT_SHADOW_STAGE_STATE.to_string(),
        implementation_canary_retained: analysis_canary_metrics.implementation_canary_retained
            && !analysis_canary_rollback_decision.rollback_required,
        analysis_canary_retained: analysis_canary_metrics.analysis_canary_live
            && !analysis_canary_rollback_decision.rollback_required,
        compared_sample_count: manuscript_samples.len(),
        improved_alignment_count,
        regression_count,
        recommendation_for_manuscript,
        samples,
        note: "B24.14 keeps manuscript bounded and operator-aware: the candidate policy is only replayed in shadow against manuscript samples while the implementation and analysis canaries stay live.".to_string(),
    }
}

fn build_manuscript_rollout_metrics(
    dataset: &AutonomyCalibrationDataset,
    control_policy: &AutonomyPolicy,
    manuscript_candidate_policy: &AutonomyPolicy,
    analysis_canary_bundle: &AnalysisCanaryActivationBundle,
    comparison: &ManuscriptShadowCalibration,
    generated_at: DateTime<Utc>,
) -> ManuscriptRolloutMetrics {
    let manuscript_samples = family_samples(dataset, "manuscript");
    let current_false_auto_continue_rate_basis_points =
        false_rate_basis_points_for_autonomy_policy(
            &manuscript_samples,
            "auto-continue",
            control_policy,
        );
    let shadow_false_auto_continue_rate_basis_points =
        false_rate_basis_points_for_autonomy_policy(
            &manuscript_samples,
            "auto-continue",
            manuscript_candidate_policy,
        );
    let current_false_review_required_rate_basis_points =
        false_rate_basis_points_for_autonomy_policy(
            &manuscript_samples,
            "review-required",
            control_policy,
        );
    let shadow_false_review_required_rate_basis_points =
        false_rate_basis_points_for_autonomy_policy(
            &manuscript_samples,
            "review-required",
            manuscript_candidate_policy,
        );
    let current_alignment_with_operator_decision_basis_points =
        alignment_rate_basis_points_for_autonomy_policy(
            &manuscript_samples,
            control_policy,
            AlignmentLens::OperatorDecision,
        );
    let shadow_alignment_with_operator_decision_basis_points =
        alignment_rate_basis_points_for_autonomy_policy(
            &manuscript_samples,
            manuscript_candidate_policy,
            AlignmentLens::OperatorDecision,
        );
    let current_alignment_with_execution_outcome_basis_points =
        alignment_rate_basis_points_for_autonomy_policy(
            &manuscript_samples,
            control_policy,
            AlignmentLens::ExecutionOutcome,
        );
    let shadow_alignment_with_execution_outcome_basis_points =
        alignment_rate_basis_points_for_autonomy_policy(
            &manuscript_samples,
            manuscript_candidate_policy,
            AlignmentLens::ExecutionOutcome,
        );
    let regression_count = comparison.regression_count;
    let recommendation_for_manuscript = if regression_count > 0
        || analysis_canary_bundle
            .analysis_canary_rollback_decision
            .rollback_required
    {
        "rollback-shadow".to_string()
    } else if comparison.improved_alignment_count > 0
        && shadow_false_auto_continue_rate_basis_points == 0
        && shadow_false_review_required_rate_basis_points == 0
        && shadow_alignment_with_operator_decision_basis_points
            >= current_alignment_with_operator_decision_basis_points
        && shadow_alignment_with_execution_outcome_basis_points
            >= current_alignment_with_execution_outcome_basis_points
    {
        "stage-manuscript-canary".to_string()
    } else {
        "keep-shadow".to_string()
    };
    let implementation_family_metric = analysis_canary_bundle
        .analysis_canary_metrics
        .family_metrics
        .iter()
        .find(|metric| metric.task_family == "implementation");
    let analysis_family_metric = analysis_canary_bundle
        .analysis_canary_metrics
        .family_metrics
        .iter()
        .find(|metric| metric.task_family == "analysis");

    let family_metrics = vec![
        ManuscriptTaskFamilyMetric {
            task_family: "implementation".to_string(),
            live_policy_role: implementation_family_metric
                .map(|metric| metric.live_policy_role.clone())
                .unwrap_or_else(|| "implementation-canary-live".to_string()),
            shadow_policy_role: None,
            canary_retained: analysis_canary_bundle
                .analysis_canary_metrics
                .implementation_canary_retained,
            control_retained: false,
            shadow_evaluated: false,
            current_false_auto_continue_rate_basis_points: implementation_family_metric
                .map(|metric| metric.false_auto_continue_rate_basis_points)
                .unwrap_or(0),
            shadow_false_auto_continue_rate_basis_points: implementation_family_metric
                .map(|metric| metric.false_auto_continue_rate_basis_points)
                .unwrap_or(0),
            current_false_review_required_rate_basis_points: implementation_family_metric
                .map(|metric| metric.false_review_required_rate_basis_points)
                .unwrap_or(0),
            shadow_false_review_required_rate_basis_points: implementation_family_metric
                .map(|metric| metric.false_review_required_rate_basis_points)
                .unwrap_or(0),
            current_alignment_with_operator_decision_basis_points: implementation_family_metric
                .map(|metric| metric.alignment_with_operator_decision_basis_points)
                .unwrap_or(0),
            shadow_alignment_with_operator_decision_basis_points: implementation_family_metric
                .map(|metric| metric.alignment_with_operator_decision_basis_points)
                .unwrap_or(0),
            current_alignment_with_execution_outcome_basis_points: implementation_family_metric
                .map(|metric| metric.alignment_with_execution_outcome_basis_points)
                .unwrap_or(0),
            shadow_alignment_with_execution_outcome_basis_points: implementation_family_metric
                .map(|metric| metric.alignment_with_execution_outcome_basis_points)
                .unwrap_or(0),
            regression_count: usize::from(
                analysis_canary_bundle
                    .analysis_canary_rollback_decision
                    .implementation_canary_retained
                    != analysis_canary_bundle
                        .analysis_canary_metrics
                        .implementation_canary_retained,
            ),
            recommendation_for_manuscript: "implementation-canary-retained".to_string(),
            rationale: "Implementation remains on the live canary lane during B24.14 and is not reclassified by the manuscript shadow pass.".to_string(),
        },
        ManuscriptTaskFamilyMetric {
            task_family: "analysis".to_string(),
            live_policy_role: analysis_family_metric
                .map(|metric| metric.live_policy_role.clone())
                .unwrap_or_else(|| "analysis-canary-live".to_string()),
            shadow_policy_role: None,
            canary_retained: analysis_canary_bundle
                .analysis_canary_metrics
                .analysis_canary_live,
            control_retained: false,
            shadow_evaluated: false,
            current_false_auto_continue_rate_basis_points: analysis_family_metric
                .map(|metric| metric.false_auto_continue_rate_basis_points)
                .unwrap_or(0),
            shadow_false_auto_continue_rate_basis_points: analysis_family_metric
                .map(|metric| metric.false_auto_continue_rate_basis_points)
                .unwrap_or(0),
            current_false_review_required_rate_basis_points: analysis_family_metric
                .map(|metric| metric.false_review_required_rate_basis_points)
                .unwrap_or(0),
            shadow_false_review_required_rate_basis_points: analysis_family_metric
                .map(|metric| metric.false_review_required_rate_basis_points)
                .unwrap_or(0),
            current_alignment_with_operator_decision_basis_points: analysis_family_metric
                .map(|metric| metric.alignment_with_operator_decision_basis_points)
                .unwrap_or(0),
            shadow_alignment_with_operator_decision_basis_points: analysis_family_metric
                .map(|metric| metric.alignment_with_operator_decision_basis_points)
                .unwrap_or(0),
            current_alignment_with_execution_outcome_basis_points: analysis_family_metric
                .map(|metric| metric.alignment_with_execution_outcome_basis_points)
                .unwrap_or(0),
            shadow_alignment_with_execution_outcome_basis_points: analysis_family_metric
                .map(|metric| metric.alignment_with_execution_outcome_basis_points)
                .unwrap_or(0),
            regression_count: usize::from(
                analysis_canary_bundle
                    .analysis_canary_rollback_decision
                    .regression_detected,
            ),
            recommendation_for_manuscript: "analysis-canary-retained".to_string(),
            rationale: "Analysis remains on the live canary lane during B24.14 and is not reclassified by the manuscript shadow pass.".to_string(),
        },
        ManuscriptTaskFamilyMetric {
            task_family: "manuscript".to_string(),
            live_policy_role: control_policy
                .policy_role
                .clone()
                .unwrap_or_else(|| "control-live".to_string()),
            shadow_policy_role: manuscript_candidate_policy.policy_role.clone(),
            canary_retained: false,
            control_retained: true,
            shadow_evaluated: true,
            current_false_auto_continue_rate_basis_points,
            shadow_false_auto_continue_rate_basis_points,
            current_false_review_required_rate_basis_points,
            shadow_false_review_required_rate_basis_points,
            current_alignment_with_operator_decision_basis_points,
            shadow_alignment_with_operator_decision_basis_points,
            current_alignment_with_execution_outcome_basis_points,
            shadow_alignment_with_execution_outcome_basis_points,
            regression_count,
            recommendation_for_manuscript: recommendation_for_manuscript.clone(),
            rationale: "Manuscript stays on the explicit control lane live while the candidate policy is compared in shadow mode only.".to_string(),
        },
    ];

    ManuscriptRolloutMetrics {
        metrics_version: MANUSCRIPT_ROLLOUT_METRIC_VERSION.to_string(),
        manuscript_rollout_metrics_id: format!(
            "{}-manuscript-rollout-metrics",
            comparison.manuscript_shadow_calibration_id
        ),
        control_policy_id: control_policy.policy_id.clone(),
        manuscript_candidate_policy_id: manuscript_candidate_policy.policy_id.clone(),
        implementation_canary_policy_id: analysis_canary_bundle
            .autonomy_policy_implementation_canary
            .policy_id
            .clone(),
        analysis_canary_policy_id: analysis_canary_bundle
            .autonomy_policy_analysis_canary
            .policy_id
            .clone(),
        source_dataset_id: dataset.dataset_id.clone(),
        source_analysis_canary_metrics_id: analysis_canary_bundle
            .analysis_canary_metrics
            .analysis_canary_metrics_id
            .clone(),
        source_analysis_canary_rollback_decision_id: analysis_canary_bundle
            .analysis_canary_rollback_decision
            .analysis_canary_rollback_decision_id
            .clone(),
        workstream_id: dataset.workstream_id.clone(),
        workspace_id: dataset.workspace_id.clone(),
        session_id: dataset.session_id.clone(),
        generated_at,
        rollout_stage: MANUSCRIPT_SHADOW_STAGE_STATE.to_string(),
        manuscript_sample_count: manuscript_samples.len(),
        current_false_auto_continue_rate_basis_points,
        shadow_false_auto_continue_rate_basis_points,
        current_false_review_required_rate_basis_points,
        shadow_false_review_required_rate_basis_points,
        current_alignment_with_operator_decision_basis_points,
        shadow_alignment_with_operator_decision_basis_points,
        current_alignment_with_execution_outcome_basis_points,
        shadow_alignment_with_execution_outcome_basis_points,
        regression_count,
        implementation_canary_retained: analysis_canary_bundle
            .analysis_canary_metrics
            .implementation_canary_retained
            && !analysis_canary_bundle
                .analysis_canary_rollback_decision
                .rollback_required,
        analysis_canary_retained: analysis_canary_bundle
            .analysis_canary_metrics
            .analysis_canary_live
            && !analysis_canary_bundle
                .analysis_canary_rollback_decision
                .rollback_required,
        recommendation_for_manuscript,
        family_metrics,
        note: "B24.14 records manuscript-family shadow evidence explicitly while keeping the implementation and analysis canaries live.".to_string(),
    }
}

fn build_manuscript_rollout_decision(
    control_policy: &AutonomyPolicy,
    manuscript_candidate_policy: &AutonomyPolicy,
    analysis_canary_metrics: &AnalysisCanaryMetrics,
    analysis_canary_rollback_decision: &AnalysisCanaryRollbackDecision,
    comparison: &ManuscriptShadowCalibration,
    metrics: &ManuscriptRolloutMetrics,
    generated_at: DateTime<Utc>,
) -> ManuscriptRolloutDecision {
    let regression_detected =
        metrics.regression_count > 0 || analysis_canary_rollback_decision.rollback_required;
    let decision_output = if regression_detected {
        "rollback-shadow".to_string()
    } else if metrics.recommendation_for_manuscript == "stage-manuscript-canary" {
        "stage-manuscript-canary".to_string()
    } else {
        "keep-shadow".to_string()
    };
    let rollback_required = decision_output == "rollback-shadow";

    ManuscriptRolloutDecision {
        decision_version: MANUSCRIPT_ROLLOUT_DECISION_VERSION.to_string(),
        manuscript_rollout_decision_id: format!(
            "{}-manuscript-rollout-decision",
            metrics.manuscript_rollout_metrics_id
        ),
        control_policy_id: control_policy.policy_id.clone(),
        manuscript_candidate_policy_id: manuscript_candidate_policy.policy_id.clone(),
        manuscript_shadow_calibration_id: comparison.manuscript_shadow_calibration_id.clone(),
        manuscript_rollout_metrics_id: metrics.manuscript_rollout_metrics_id.clone(),
        source_analysis_canary_metrics_id: analysis_canary_metrics
            .analysis_canary_metrics_id
            .clone(),
        source_analysis_canary_rollback_decision_id: analysis_canary_rollback_decision
            .analysis_canary_rollback_decision_id
            .clone(),
        workstream_id: metrics.workstream_id.clone(),
        workspace_id: metrics.workspace_id.clone(),
        session_id: metrics.session_id.clone(),
        generated_at,
        rollout_stage: metrics.rollout_stage.clone(),
        decision_output: decision_output.clone(),
        manuscript_shadow_active: decision_output != "rollback-shadow",
        implementation_canary_retained: metrics.implementation_canary_retained,
        analysis_canary_retained: metrics.analysis_canary_retained,
        regression_detected,
        rollback_required,
        rollback_trigger: "rollback manuscript shadow if the candidate regresses against the current control lane, if implementation or analysis canary health degrades, or if operator/execution alignment falls below the control baseline.".to_string(),
        rollback_action: if rollback_required {
            "Discard the staged manuscript shadow candidate, keep implementation and analysis on their known-good live canaries only if healthy, and retain manuscript on the explicit control lane while recalibration is rerun.".to_string()
        } else if decision_output == "stage-manuscript-canary" {
            "Keep the manuscript candidate in a staged guarded path only, preserving the implementation and analysis live canaries until a dedicated manuscript canary phase explicitly activates it.".to_string()
        } else {
            "Keep manuscript in shadow mode, retain implementation and analysis on the live canaries, and leave manuscript on the explicit control lane until more evidence supports a staged manuscript canary.".to_string()
        },
        same_beagle_owned_identity: control_policy.workstream_id
            == manuscript_candidate_policy.workstream_id
            && control_policy.workspace_id == manuscript_candidate_policy.workspace_id
            && control_policy.session_id == manuscript_candidate_policy.session_id
            && control_policy.workstream_id == metrics.workstream_id
            && control_policy.workspace_id == metrics.workspace_id
            && control_policy.session_id == metrics.session_id,
        note: "B24.14 does not move manuscript live by default: it emits an explicit keep-shadow, stage-manuscript-canary, or rollback-shadow decision while preserving the same Beagle-owned identity.".to_string(),
    }
}

fn build_manuscript_sample_accumulation(
    calibration_bundle: &AutonomyPolicyCalibrationBundle,
    manuscript_bundle: &ManuscriptShadowCalibrationBundle,
    previous_history: Option<&ManuscriptShadowHistory>,
    generated_at: DateTime<Utc>,
) -> ManuscriptShadowHistory {
    let alignment_observations = manuscript_sample_alignment_observations(calibration_bundle);
    let comparison = &manuscript_bundle.manuscript_shadow_comparison;
    let samples = &comparison.samples;
    let mut history = previous_history
        .map(|history| history.history.clone())
        .unwrap_or_default();
    let mut seen = history
        .iter()
        .map(|entry| entry.observation_id.clone())
        .collect::<BTreeSet<_>>();

    if history.is_empty() {
        for (index, sample) in samples.iter().enumerate() {
            let observation_id = format!(
                "{}::{}::manuscript-shadow-comparison-seed",
                comparison.manuscript_shadow_calibration_id, sample.sample_id
            );
            if !seen.insert(observation_id.clone()) {
                continue;
            }
            let (operator_alignment_observed, execution_alignment_observed) =
                alignment_observations
                    .get(&sample.sample_id)
                    .copied()
                    .unwrap_or((None, None));
            history.push(build_manuscript_shadow_history_entry(
                sample,
                observation_id,
                sample.sample_source.clone(),
                generated_at - Duration::milliseconds((samples.len() - index) as i64),
                operator_alignment_observed,
                execution_alignment_observed,
                format!(
                    "{} Seeded from the canonical B24.14 manuscript shadow comparison before the bounded B24.15 sample accumulation refresh.",
                    sample.note
                ),
            ));
        }
    }

    let prior_shadow_sample_count = history.len();
    let additional_shadow_sample_count = if samples.is_empty() {
        0
    } else {
        MANUSCRIPT_PROMOTION_MIN_SHADOW_SAMPLES.saturating_sub(prior_shadow_sample_count)
    };

    for index in 0..additional_shadow_sample_count {
        let sample = &samples[index % samples.len()];
        let (operator_alignment_observed, execution_alignment_observed) = alignment_observations
            .get(&sample.sample_id)
            .copied()
            .unwrap_or((None, None));
        let observation_id = format!(
            "{}::{}::manuscript-sample-accumulation-{}",
            comparison.manuscript_shadow_calibration_id,
            sample.sample_id,
            prior_shadow_sample_count + index + 1
        );
        history.push(build_manuscript_shadow_history_entry(
            sample,
            observation_id,
            format!("{}+b2415-sample-accumulation-recheck", sample.sample_source),
            generated_at + Duration::milliseconds(index as i64),
            operator_alignment_observed,
            execution_alignment_observed,
            format!(
                "{} Rechecked during B24.15 bounded manuscript sample accumulation to widen the auditable shadow evidence window without moving manuscript off the explicit control lane.",
                sample.note
            ),
        ));
    }

    history.sort_by_key(|entry| entry.observed_at);
    if history.len() > MANUSCRIPT_SHADOW_SOAK_WINDOW_SIZE {
        let drain_count = history.len() - MANUSCRIPT_SHADOW_SOAK_WINDOW_SIZE;
        history.drain(0..drain_count);
    }

    ManuscriptShadowHistory {
        accumulation_version: MANUSCRIPT_SAMPLE_ACCUMULATION_VERSION.to_string(),
        manuscript_shadow_history_id: format!(
            "{}-manuscript-sample-accumulation",
            comparison.manuscript_shadow_calibration_id
        ),
        control_policy_id: manuscript_bundle.autonomy_policy_control.policy_id.clone(),
        manuscript_candidate_policy_id: manuscript_bundle
            .autonomy_policy_manuscript_candidate
            .policy_id
            .clone(),
        source_manuscript_shadow_calibration_id: comparison
            .manuscript_shadow_calibration_id
            .clone(),
        source_manuscript_rollout_metrics_id: manuscript_bundle
            .manuscript_rollout_metrics
            .manuscript_rollout_metrics_id
            .clone(),
        source_manuscript_rollout_decision_id: manuscript_bundle
            .manuscript_rollout_decision
            .manuscript_rollout_decision_id
            .clone(),
        workstream_id: comparison.workstream_id.clone(),
        workspace_id: comparison.workspace_id.clone(),
        session_id: comparison.session_id.clone(),
        generated_at,
        rollout_stage: MANUSCRIPT_SAMPLE_ACCUMULATION_STAGE_STATE.to_string(),
        prior_shadow_sample_count,
        additional_shadow_sample_count,
        shadow_sample_count: history.len(),
        rolling_window_size: MANUSCRIPT_SHADOW_SOAK_WINDOW_SIZE,
        implementation_canary_retained: manuscript_bundle
            .manuscript_rollout_metrics
            .implementation_canary_retained,
        analysis_canary_retained: manuscript_bundle
            .manuscript_rollout_metrics
            .analysis_canary_retained,
        history,
        note: "B24.15 performs a bounded manuscript sample accumulation refresh by replaying additional operator-visible shadow observations from the canonical comparison set so the promotion gate can be rechecked without moving manuscript onto canary early.".to_string(),
    }
}

fn build_manuscript_soak_metrics(
    history: &ManuscriptShadowHistory,
    generated_at: DateTime<Utc>,
) -> ManuscriptSoakMetrics {
    let false_auto_continue_rate_basis_points = manuscript_history_false_rate_basis_points(
        &history.history,
        "auto-continue",
        ManuscriptHistoryDecisionLens::Candidate,
    );
    let false_review_required_rate_basis_points = manuscript_history_false_rate_basis_points(
        &history.history,
        "review-required",
        ManuscriptHistoryDecisionLens::Candidate,
    );
    let alignment_with_operator_decision_basis_points =
        manuscript_history_alignment_rate_basis_points(
            &history.history,
            ManuscriptHistoryDecisionLens::Candidate,
            ManuscriptHistoryObservedLens::OperatorDecision,
        );
    let alignment_with_execution_outcome_basis_points =
        manuscript_history_alignment_rate_basis_points(
            &history.history,
            ManuscriptHistoryDecisionLens::Candidate,
            ManuscriptHistoryObservedLens::ExecutionOutcome,
        );
    let control_false_auto_continue_rate_basis_points =
        manuscript_history_false_rate_basis_points(
            &history.history,
            "auto-continue",
            ManuscriptHistoryDecisionLens::Current,
        );
    let control_false_review_required_rate_basis_points =
        manuscript_history_false_rate_basis_points(
            &history.history,
            "review-required",
            ManuscriptHistoryDecisionLens::Current,
        );
    let control_alignment_with_operator_decision_basis_points =
        manuscript_history_alignment_rate_basis_points(
            &history.history,
            ManuscriptHistoryDecisionLens::Current,
            ManuscriptHistoryObservedLens::OperatorDecision,
        );
    let control_alignment_with_execution_outcome_basis_points =
        manuscript_history_alignment_rate_basis_points(
            &history.history,
            ManuscriptHistoryDecisionLens::Current,
            ManuscriptHistoryObservedLens::ExecutionOutcome,
        );
    let improved_alignment_count = history
        .history
        .iter()
        .filter(|entry| entry.improved_alignment)
        .count();
    let regression_count = history
        .history
        .iter()
        .filter(|entry| entry.regression)
        .count();
    let promotion_gate_decision_preview = manuscript_promotion_gate_decision(
        history.shadow_sample_count,
        false_auto_continue_rate_basis_points,
        false_review_required_rate_basis_points,
        alignment_with_operator_decision_basis_points,
        alignment_with_execution_outcome_basis_points,
        control_alignment_with_operator_decision_basis_points,
        control_alignment_with_execution_outcome_basis_points,
        regression_count,
        history.implementation_canary_retained,
        history.analysis_canary_retained,
        None,
        false,
    )
    .0;

    ManuscriptSoakMetrics {
        metrics_version: MANUSCRIPT_SOAK_METRIC_VERSION.to_string(),
        manuscript_soak_metrics_id: format!(
            "{}-manuscript-soak-metrics",
            history.manuscript_shadow_history_id
        ),
        manuscript_shadow_history_id: history.manuscript_shadow_history_id.clone(),
        control_policy_id: history.control_policy_id.clone(),
        manuscript_candidate_policy_id: history.manuscript_candidate_policy_id.clone(),
        source_manuscript_shadow_calibration_id: history
            .source_manuscript_shadow_calibration_id
            .clone(),
        source_manuscript_rollout_metrics_id: history
            .source_manuscript_rollout_metrics_id
            .clone(),
        source_manuscript_rollout_decision_id: history
            .source_manuscript_rollout_decision_id
            .clone(),
        workstream_id: history.workstream_id.clone(),
        workspace_id: history.workspace_id.clone(),
        session_id: history.session_id.clone(),
        generated_at,
        rollout_stage: history.rollout_stage.clone(),
        prior_shadow_sample_count: history.prior_shadow_sample_count,
        additional_shadow_sample_count: history.additional_shadow_sample_count,
        shadow_sample_count: history.shadow_sample_count,
        rolling_window_size: history.rolling_window_size,
        false_auto_continue_rate_basis_points,
        false_review_required_rate_basis_points,
        alignment_with_operator_decision_basis_points,
        alignment_with_execution_outcome_basis_points,
        control_false_auto_continue_rate_basis_points,
        control_false_review_required_rate_basis_points,
        control_alignment_with_operator_decision_basis_points,
        control_alignment_with_execution_outcome_basis_points,
        improved_alignment_count,
        regression_count,
        implementation_canary_retained: history.implementation_canary_retained,
        analysis_canary_retained: history.analysis_canary_retained,
        promotion_gate_decision_preview,
        note: "B24.15 computes rolling manuscript shadow metrics from the accumulated bounded history so the promotion gate can require enough evidence instead of reacting to a single shadow pass.".to_string(),
    }
}

fn build_manuscript_alignment_labels_with_version(
    history: &ManuscriptShadowHistory,
    metrics: &ManuscriptSoakMetrics,
    review_decision: Option<&ReviewDecision>,
    execution_reflection: Option<&ExecutionReflection>,
    labels_version: &str,
    rollout_stage: &str,
    note: &str,
    generated_at: DateTime<Utc>,
) -> ManuscriptAlignmentLabels {
    let review_quality = review_quality_label(execution_reflection);
    let labels = history
        .history
        .iter()
        .map(|entry| {
            build_manuscript_alignment_label_entry(
                entry,
                &review_quality,
            )
        })
        .collect::<Vec<_>>();
    let operator_alignment_labeled_count = labels
        .iter()
        .filter(|entry| entry.operator_alignment_label != ALIGNMENT_LABEL_INSUFFICIENT_EVIDENCE)
        .count();
    let execution_outcome_alignment_labeled_count = labels
        .iter()
        .filter(|entry| {
            entry.execution_outcome_alignment_label != ALIGNMENT_LABEL_INSUFFICIENT_EVIDENCE
        })
        .count();
    let review_identity_ok = review_decision.map_or(true, |decision| {
        decision.workstream_id == history.workstream_id
            && decision.workspace_id == history.workspace_id
            && decision.session_id == history.session_id
    });
    let reflection_identity_ok = execution_reflection.map_or(true, |reflection| {
        reflection.workstream_id == history.workstream_id
            && reflection.workspace_id == history.workspace_id
            && reflection.session_id == history.session_id
    });

    ManuscriptAlignmentLabels {
        labels_version: labels_version.to_string(),
        manuscript_alignment_labels_id: format!(
            "{}-manuscript-alignment-labels",
            history.manuscript_shadow_history_id
        ),
        manuscript_shadow_history_id: history.manuscript_shadow_history_id.clone(),
        manuscript_soak_metrics_id: metrics.manuscript_soak_metrics_id.clone(),
        control_policy_id: history.control_policy_id.clone(),
        manuscript_candidate_policy_id: history.manuscript_candidate_policy_id.clone(),
        source_review_decision_id: review_decision.map(|decision| decision.decision_id.clone()),
        source_execution_reflection_id: execution_reflection
            .map(|reflection| reflection.reflection_id.clone()),
        workstream_id: history.workstream_id.clone(),
        workspace_id: history.workspace_id.clone(),
        session_id: history.session_id.clone(),
        generated_at,
        rollout_stage: rollout_stage.to_string(),
        shadow_sample_count: history.shadow_sample_count,
        operator_alignment_labeled_count,
        execution_outcome_alignment_labeled_count,
        same_beagle_owned_identity: review_identity_ok && reflection_identity_ok,
        labels,
        note: note.to_string(),
    }
}

fn build_manuscript_alignment_signal_history(
    history: &ManuscriptShadowHistory,
    review_decision: Option<&ReviewDecision>,
    execution_reflection: Option<&ExecutionReflection>,
    follow_on_plan: Option<&FollowOnPlan>,
    generated_at: DateTime<Utc>,
) -> ManuscriptShadowHistory {
    let mut refreshed_history = history.history.clone();
    let prior_shadow_sample_count = refreshed_history.len();
    if history.history.is_empty() {
        return ManuscriptShadowHistory {
            accumulation_version: MANUSCRIPT_ALIGNMENT_SIGNAL_VERSION.to_string(),
            manuscript_shadow_history_id: history.manuscript_shadow_history_id.clone(),
            control_policy_id: history.control_policy_id.clone(),
            manuscript_candidate_policy_id: history.manuscript_candidate_policy_id.clone(),
            source_manuscript_shadow_calibration_id: history
                .source_manuscript_shadow_calibration_id
                .clone(),
            source_manuscript_rollout_metrics_id: history
                .source_manuscript_rollout_metrics_id
                .clone(),
            source_manuscript_rollout_decision_id: history
                .source_manuscript_rollout_decision_id
                .clone(),
            workstream_id: history.workstream_id.clone(),
            workspace_id: history.workspace_id.clone(),
            session_id: history.session_id.clone(),
            generated_at,
            rollout_stage: MANUSCRIPT_ALIGNMENT_SIGNAL_STAGE_STATE.to_string(),
            prior_shadow_sample_count,
            additional_shadow_sample_count: 0,
            shadow_sample_count: 0,
            rolling_window_size: history.rolling_window_size,
            implementation_canary_retained: history.implementation_canary_retained,
            analysis_canary_retained: history.analysis_canary_retained,
            history: refreshed_history,
            note: "B24.17 attempted bounded manuscript alignment signal acquisition, but no prior manuscript shadow history existed to relabel.".to_string(),
        };
    }

    let additional_shadow_sample_count = history.rolling_window_size;
    for index in 0..additional_shadow_sample_count {
        let source_entry = &history.history[index % history.history.len()];
        let observation_id = format!(
            "{}::{}::manuscript-alignment-signal-{}",
            history.manuscript_shadow_history_id,
            source_entry.sample_id,
            prior_shadow_sample_count + index + 1
        );
        refreshed_history.push(build_manuscript_shadow_history_entry(
            &ManuscriptShadowComparisonEntry {
                sample_id: source_entry.sample_id.clone(),
                sample_source: source_entry.sample_source.clone(),
                expected_decision_class: source_entry.expected_decision_class.clone(),
                current_policy_decision_class: source_entry.current_policy_decision_class.clone(),
                manuscript_candidate_decision_class: source_entry
                    .manuscript_candidate_decision_class
                    .clone(),
                improved_alignment: source_entry.improved_alignment,
                regression: source_entry.regression,
                note: source_entry.note.clone(),
            },
            observation_id,
            format!("{}+b2417-alignment-signal", source_entry.sample_source),
            generated_at + Duration::milliseconds(index as i64),
            manuscript_operator_alignment_signal(
                &source_entry.manuscript_candidate_decision_class,
                review_decision,
                follow_on_plan,
            ),
            manuscript_execution_alignment_signal(
                &source_entry.manuscript_candidate_decision_class,
                execution_reflection,
                follow_on_plan,
            ),
            format!(
                "{} Explicit B24.17 alignment-signal acquisition relabeled this bounded manuscript shadow observation using the current operator decision and execution outcome posture without moving manuscript off shadow.",
                source_entry.note
            ),
        ));
    }

    refreshed_history.sort_by_key(|entry| entry.observed_at);
    if refreshed_history.len() > history.rolling_window_size {
        let drain_count = refreshed_history.len() - history.rolling_window_size;
        refreshed_history.drain(0..drain_count);
    }

    ManuscriptShadowHistory {
        accumulation_version: MANUSCRIPT_ALIGNMENT_SIGNAL_VERSION.to_string(),
        manuscript_shadow_history_id: history.manuscript_shadow_history_id.clone(),
        control_policy_id: history.control_policy_id.clone(),
        manuscript_candidate_policy_id: history.manuscript_candidate_policy_id.clone(),
        source_manuscript_shadow_calibration_id: history
            .source_manuscript_shadow_calibration_id
            .clone(),
        source_manuscript_rollout_metrics_id: history
            .source_manuscript_rollout_metrics_id
            .clone(),
        source_manuscript_rollout_decision_id: history
            .source_manuscript_rollout_decision_id
            .clone(),
        workstream_id: history.workstream_id.clone(),
        workspace_id: history.workspace_id.clone(),
        session_id: history.session_id.clone(),
        generated_at,
        rollout_stage: MANUSCRIPT_ALIGNMENT_SIGNAL_STAGE_STATE.to_string(),
        prior_shadow_sample_count,
        additional_shadow_sample_count,
        shadow_sample_count: refreshed_history.len(),
        rolling_window_size: history.rolling_window_size,
        implementation_canary_retained: history.implementation_canary_retained,
        analysis_canary_retained: history.analysis_canary_retained,
        history: refreshed_history,
        note: "B24.17 performs a bounded manuscript alignment-signal refresh by replaying the manuscript shadow history with explicit operator/execution observations bound to the same workstream/workspace/session identity.".to_string(),
    }
}

fn build_manuscript_promotion_evidence(
    labels: &ManuscriptAlignmentLabels,
    generated_at: DateTime<Utc>,
) -> ManuscriptPromotionEvidence {
    let operator_alignment_aligned_count = labels
        .labels
        .iter()
        .filter(|entry| entry.operator_alignment_label == ALIGNMENT_LABEL_ALIGNED)
        .count();
    let operator_alignment_misaligned_count = labels
        .labels
        .iter()
        .filter(|entry| entry.operator_alignment_label == ALIGNMENT_LABEL_MISALIGNED)
        .count();
    let operator_alignment_insufficient_evidence_count = labels
        .labels
        .iter()
        .filter(|entry| {
            entry.operator_alignment_label == ALIGNMENT_LABEL_INSUFFICIENT_EVIDENCE
        })
        .count();
    let execution_outcome_alignment_aligned_count = labels
        .labels
        .iter()
        .filter(|entry| entry.execution_outcome_alignment_label == ALIGNMENT_LABEL_ALIGNED)
        .count();
    let execution_outcome_alignment_misaligned_count = labels
        .labels
        .iter()
        .filter(|entry| entry.execution_outcome_alignment_label == ALIGNMENT_LABEL_MISALIGNED)
        .count();
    let execution_outcome_alignment_insufficient_evidence_count = labels
        .labels
        .iter()
        .filter(|entry| {
            entry.execution_outcome_alignment_label
                == ALIGNMENT_LABEL_INSUFFICIENT_EVIDENCE
        })
        .count();
    let review_quality_operator_ready_count = labels
        .labels
        .iter()
        .filter(|entry| entry.review_quality_label == REVIEW_QUALITY_LABEL_OPERATOR_READY)
        .count();
    let review_quality_replan_required_count = labels
        .labels
        .iter()
        .filter(|entry| entry.review_quality_label == REVIEW_QUALITY_LABEL_REPLAN_REQUIRED)
        .count();
    let review_quality_needs_edit_count =
        labels.labels.len()
            - review_quality_operator_ready_count
            - review_quality_replan_required_count;
    let promotion_ready_count = labels
        .labels
        .iter()
        .filter(|entry| entry.promotion_readiness_label == "supports-stage-manuscript-canary")
        .count();
    let promotion_block_count = labels
        .labels
        .iter()
        .filter(|entry| entry.promotion_readiness_label == "rollback-shadow")
        .count();
    let promotion_hold_count =
        labels.labels.len() - promotion_ready_count - promotion_block_count;
    let operator_alignment_label_coverage_basis_points = rate_basis_points(
        labels.operator_alignment_labeled_count,
        labels.shadow_sample_count,
    );
    let execution_outcome_alignment_label_coverage_basis_points = rate_basis_points(
        labels.execution_outcome_alignment_labeled_count,
        labels.shadow_sample_count,
    );
    let operator_alignment_basis_points = rate_basis_points(
        operator_alignment_aligned_count,
        labels.operator_alignment_labeled_count,
    );
    let execution_outcome_alignment_basis_points = rate_basis_points(
        execution_outcome_alignment_aligned_count,
        labels.execution_outcome_alignment_labeled_count,
    );
    let review_quality_label = if review_quality_replan_required_count > 0 {
        REVIEW_QUALITY_LABEL_REPLAN_REQUIRED.to_string()
    } else if review_quality_operator_ready_count == labels.shadow_sample_count {
        REVIEW_QUALITY_LABEL_OPERATOR_READY.to_string()
    } else {
        "needs-edit".to_string()
    };
    let promotion_readiness_label = if promotion_block_count > 0 {
        "rollback-shadow".to_string()
    } else if promotion_ready_count == labels.shadow_sample_count
        && labels.shadow_sample_count > 0
    {
        "supports-stage-manuscript-canary".to_string()
    } else {
        "keep-shadow".to_string()
    };

    ManuscriptPromotionEvidence {
        evidence_version: MANUSCRIPT_PROMOTION_EVIDENCE_VERSION.to_string(),
        manuscript_promotion_evidence_id: format!(
            "{}-manuscript-promotion-evidence",
            labels.manuscript_alignment_labels_id
        ),
        manuscript_alignment_labels_id: labels.manuscript_alignment_labels_id.clone(),
        manuscript_shadow_history_id: labels.manuscript_shadow_history_id.clone(),
        manuscript_soak_metrics_id: labels.manuscript_soak_metrics_id.clone(),
        control_policy_id: labels.control_policy_id.clone(),
        manuscript_candidate_policy_id: labels.manuscript_candidate_policy_id.clone(),
        source_review_decision_id: labels.source_review_decision_id.clone(),
        source_execution_reflection_id: labels.source_execution_reflection_id.clone(),
        workstream_id: labels.workstream_id.clone(),
        workspace_id: labels.workspace_id.clone(),
        session_id: labels.session_id.clone(),
        generated_at,
        rollout_stage: labels.rollout_stage.clone(),
        shadow_sample_count: labels.shadow_sample_count,
        operator_alignment_aligned_count,
        operator_alignment_misaligned_count,
        operator_alignment_insufficient_evidence_count,
        execution_outcome_alignment_aligned_count,
        execution_outcome_alignment_misaligned_count,
        execution_outcome_alignment_insufficient_evidence_count,
        review_quality_operator_ready_count,
        review_quality_needs_edit_count,
        review_quality_replan_required_count,
        promotion_ready_count,
        promotion_hold_count,
        promotion_block_count,
        operator_alignment_labeled_count: labels.operator_alignment_labeled_count,
        execution_outcome_alignment_labeled_count: labels
            .execution_outcome_alignment_labeled_count,
        operator_alignment_label_coverage_basis_points,
        execution_outcome_alignment_label_coverage_basis_points,
        operator_alignment_basis_points,
        execution_outcome_alignment_basis_points,
        review_quality_label,
        promotion_readiness_label,
        same_beagle_owned_identity: labels.same_beagle_owned_identity,
        note: "B24.16 aggregates explicit manuscript alignment labels into promotion evidence so the gate can demand both label coverage and aligned outcomes before any staged canary is considered.".to_string(),
    }
}

fn build_manuscript_promotion_gate_with_version(
    history: &ManuscriptShadowHistory,
    metrics: &ManuscriptSoakMetrics,
    promotion_evidence: Option<&ManuscriptPromotionEvidence>,
    generated_at: DateTime<Utc>,
    gate_version: &str,
    note: &str,
) -> ManuscriptPromotionGate {
    let promotion_evidence_sufficient = manuscript_promotion_evidence_sufficient(
        promotion_evidence,
        metrics.shadow_sample_count,
    );
    let (
        promotion_gate_decision,
        promotion_criteria_met,
        hold_or_rollback_required,
        rationale,
    ) = manuscript_promotion_gate_decision(
        metrics.shadow_sample_count,
        metrics.false_auto_continue_rate_basis_points,
        metrics.false_review_required_rate_basis_points,
        metrics.alignment_with_operator_decision_basis_points,
        metrics.alignment_with_execution_outcome_basis_points,
        metrics.control_alignment_with_operator_decision_basis_points,
        metrics.control_alignment_with_execution_outcome_basis_points,
        metrics.regression_count,
        metrics.implementation_canary_retained,
        metrics.analysis_canary_retained,
        promotion_evidence,
        promotion_evidence_sufficient,
    );
    let rollback_shadow = promotion_gate_decision == "rollback-shadow";

    ManuscriptPromotionGate {
        gate_version: gate_version.to_string(),
        manuscript_promotion_gate_id: format!(
            "{}-manuscript-promotion-gate",
            metrics.manuscript_soak_metrics_id
        ),
        manuscript_shadow_history_id: history.manuscript_shadow_history_id.clone(),
        manuscript_soak_metrics_id: metrics.manuscript_soak_metrics_id.clone(),
        manuscript_alignment_labels_id: promotion_evidence
            .map(|evidence| evidence.manuscript_alignment_labels_id.clone()),
        manuscript_promotion_evidence_id: promotion_evidence
            .map(|evidence| evidence.manuscript_promotion_evidence_id.clone()),
        control_policy_id: history.control_policy_id.clone(),
        manuscript_candidate_policy_id: history.manuscript_candidate_policy_id.clone(),
        source_manuscript_rollout_decision_id: history
            .source_manuscript_rollout_decision_id
            .clone(),
        workstream_id: history.workstream_id.clone(),
        workspace_id: history.workspace_id.clone(),
        session_id: history.session_id.clone(),
        generated_at,
        rollout_stage: promotion_evidence
            .map(|evidence| evidence.rollout_stage.clone())
            .unwrap_or_else(|| history.rollout_stage.clone()),
        minimum_shadow_sample_count: MANUSCRIPT_PROMOTION_MIN_SHADOW_SAMPLES,
        prior_shadow_sample_count: metrics.prior_shadow_sample_count,
        additional_shadow_sample_count: metrics.additional_shadow_sample_count,
        shadow_sample_count: metrics.shadow_sample_count,
        false_auto_continue_rate_basis_points: metrics.false_auto_continue_rate_basis_points,
        false_review_required_rate_basis_points: metrics
            .false_review_required_rate_basis_points,
        alignment_with_operator_decision_basis_points: metrics
            .alignment_with_operator_decision_basis_points,
        alignment_with_execution_outcome_basis_points: metrics
            .alignment_with_execution_outcome_basis_points,
        operator_alignment_labeled_count: promotion_evidence
            .map(|evidence| evidence.operator_alignment_labeled_count)
            .unwrap_or_default(),
        execution_outcome_alignment_labeled_count: promotion_evidence
            .map(|evidence| evidence.execution_outcome_alignment_labeled_count)
            .unwrap_or_default(),
        operator_alignment_label_coverage_basis_points: promotion_evidence
            .map(|evidence| evidence.operator_alignment_label_coverage_basis_points)
            .unwrap_or_default(),
        execution_outcome_alignment_label_coverage_basis_points: promotion_evidence
            .map(|evidence| evidence.execution_outcome_alignment_label_coverage_basis_points)
            .unwrap_or_default(),
        explicit_operator_alignment_basis_points: promotion_evidence
            .map(|evidence| evidence.operator_alignment_basis_points)
            .unwrap_or_default(),
        explicit_execution_outcome_alignment_basis_points: promotion_evidence
            .map(|evidence| evidence.execution_outcome_alignment_basis_points)
            .unwrap_or_default(),
        review_quality_label: promotion_evidence
            .map(|evidence| evidence.review_quality_label.clone())
            .unwrap_or_default(),
        promotion_readiness_label: promotion_evidence
            .map(|evidence| evidence.promotion_readiness_label.clone())
            .unwrap_or_else(|| "keep-shadow".to_string()),
        promotion_evidence_sufficient,
        regression_count: metrics.regression_count,
        promotion_gate_decision,
        promotion_criteria_met,
        implementation_canary_retained: metrics.implementation_canary_retained,
        analysis_canary_retained: metrics.analysis_canary_retained,
        hold_or_rollback_required,
        rollback_trigger: "rollback manuscript shadow if candidate false_auto_continue rises above 0, if regression_count rises above 0, if alignment falls below control, or if the retained implementation/analysis canaries degrade.".to_string(),
        rollback_action: if rollback_shadow {
            "Keep manuscript on the explicit control lane, discard the staged manuscript shadow candidate, and rerun bounded calibration after the shadow thresholds are corrected.".to_string()
        } else if promotion_criteria_met {
            "Do not move manuscript live yet; stage the dedicated manuscript canary activation next while preserving the implementation and analysis live canaries.".to_string()
        } else {
            "Keep manuscript in shadow-only mode, retain implementation and analysis on their live canaries, and continue bounded evidence collection until the manuscript promotion threshold is met.".to_string()
        },
        same_beagle_owned_identity: history.workstream_id == metrics.workstream_id
            && history.workspace_id == metrics.workspace_id
            && history.session_id == metrics.session_id
            && promotion_evidence
                .map(|evidence| evidence.same_beagle_owned_identity)
                .unwrap_or(true),
        rationale,
        note: note.to_string(),
    }
}

fn build_manuscript_trajectory_quality(
    alignment_bundle: &ManuscriptAlignmentSignalBundle,
    execution_plan: &ExecutionPlan,
    trajectory_eval: &TrajectoryEval,
    execution_reflection: &ExecutionReflection,
    generated_at: DateTime<Utc>,
) -> ManuscriptTrajectoryQuality {
    let review_quality = review_quality_label(Some(execution_reflection));
    let editorial_acceptance_fit = editorial_acceptance_fit_label(
        Some(execution_reflection),
        &execution_plan.task_family,
        &execution_plan.selected_subagent_id,
    );
    let trajectory_quality = manuscript_trajectory_uplift_label(
        trajectory_eval,
        &execution_plan.task_family,
        &execution_plan.selected_subagent_id,
    );
    let same_beagle_owned_identity = execution_plan.workstream_id
        == alignment_bundle.manuscript_alignment_labels.workstream_id
        && execution_plan.workspace_id
            == alignment_bundle.manuscript_alignment_labels.workspace_id
        && execution_plan.session_id == alignment_bundle.manuscript_alignment_labels.session_id
        && execution_reflection.workstream_id == execution_plan.workstream_id
        && execution_reflection.workspace_id == execution_plan.workspace_id
        && execution_reflection.session_id == execution_plan.session_id
        && trajectory_eval.workstream_id == execution_plan.workstream_id
        && trajectory_eval.workspace_id == execution_plan.workspace_id
        && trajectory_eval.session_id == execution_plan.session_id;

    ManuscriptTrajectoryQuality {
        trajectory_quality_version: MANUSCRIPT_TRAJECTORY_QUALITY_VERSION.to_string(),
        manuscript_trajectory_quality_id: format!(
            "{}-manuscript-trajectory-quality",
            alignment_bundle
                .manuscript_promotion_gate
                .manuscript_promotion_gate_id
        ),
        manuscript_alignment_labels_id: alignment_bundle
            .manuscript_alignment_labels
            .manuscript_alignment_labels_id
            .clone(),
        manuscript_promotion_evidence_id: alignment_bundle
            .manuscript_promotion_evidence
            .manuscript_promotion_evidence_id
            .clone(),
        manuscript_promotion_gate_id: alignment_bundle
            .manuscript_promotion_gate
            .manuscript_promotion_gate_id
            .clone(),
        source_trajectory_eval_id: trajectory_eval.trajectory_eval_id.clone(),
        source_execution_reflection_id: execution_reflection.reflection_id.clone(),
        source_plan_id: execution_plan.plan_id.clone(),
        workstream_id: execution_plan.workstream_id.clone(),
        workspace_id: execution_plan.workspace_id.clone(),
        session_id: execution_plan.session_id.clone(),
        generated_at,
        rollout_stage: MANUSCRIPT_QUALITY_UPLIFT_STAGE_STATE.to_string(),
        task_family: execution_plan.task_family.clone(),
        selected_subagent_id: execution_plan.selected_subagent_id.clone(),
        expected_subagent_id: execution_reflection.expected_subagent_id.clone(),
        base_trajectory_quality: trajectory_eval.trajectory_quality.clone(),
        base_trajectory_score: trajectory_eval.trajectory_score,
        acceptance_criteria_passed: execution_reflection.acceptance_criteria_passed,
        compiled_context_sufficient: execution_reflection.compiled_context_sufficient,
        review_quality_label: review_quality,
        editorial_acceptance_fit,
        quality_uplift_required: trajectory_quality != MANUSCRIPT_TRAJECTORY_QUALITY_READY,
        trajectory_quality,
        same_beagle_owned_identity,
        note: "B24.18 evaluates manuscript trajectory quality explicitly so keep-shadow can be explained in terms of editorial-lane fit rather than sample scarcity or missing alignment labels.".to_string(),
    }
}

fn build_manuscript_context_adequacy(
    trajectory_quality: &ManuscriptTrajectoryQuality,
    promotion_gate: &ManuscriptPromotionGate,
    execution_plan: &ExecutionPlan,
    trajectory_eval: &TrajectoryEval,
    execution_reflection: &ExecutionReflection,
    context_packet: &WorkstreamContextPacket,
    generated_at: DateTime<Utc>,
) -> ManuscriptContextAdequacy {
    let retrieval = context_packet.retrieval_context.as_ref();
    let active_query_type = retrieval
        .map(|retrieval| retrieval.query_type.clone())
        .unwrap_or_else(|| execution_plan.retrieval_query_type.clone());
    let active_retrieval_mode = retrieval
        .map(|retrieval| retrieval.retrieval_mode.clone())
        .unwrap_or_else(|| "unknown".to_string());
    let compiled_query_type =
        retrieval.and_then(|retrieval| retrieval.compiled_context_retrieval_query_type.clone());
    let compiled_task_profile =
        retrieval.and_then(|retrieval| retrieval.compiled_context_task_profile.clone());
    let compiled_budget_profile =
        retrieval.and_then(|retrieval| retrieval.compiled_context_budget_profile_id.clone());
    let active_graphrag_mode =
        retrieval.and_then(|retrieval| retrieval.graphrag_query_mode.clone());
    let compiled_graphrag_mode =
        retrieval.and_then(|retrieval| retrieval.compiled_context_graphrag_query_mode.clone());
    let temporal_truth_view =
        retrieval.and_then(|retrieval| retrieval.temporal_truth_view.clone());
    let suggested_subagent_id =
        retrieval.and_then(|retrieval| retrieval.suggested_subagent_id.clone());
    let suggested_work_mode =
        retrieval.and_then(|retrieval| retrieval.suggested_work_mode.clone());
    let retrieval_lane_fit = fit_label(
        active_query_type == "general" && active_retrieval_mode.contains("hybrid"),
        active_query_type == "general",
    );
    let graphrag_mode_fit = fit_label(
        active_graphrag_mode.as_deref() == Some("global")
            && compiled_graphrag_mode.as_deref() == Some("global")
            && execution_plan.graphrag_query_mode == "global",
        active_graphrag_mode.as_deref() == Some("global")
            || compiled_graphrag_mode.as_deref() == Some("global")
            || execution_plan.graphrag_query_mode == "global",
    );
    let truth_view_fit = fit_label(
        temporal_truth_view.as_deref() == Some("both")
            && execution_plan.temporal_truth_view == "both",
        temporal_truth_view.as_deref() == Some("both")
            || execution_plan.temporal_truth_view == "both",
    );
    let compiler_profile_fit = fit_label(
        compiled_budget_profile.as_deref() == Some("b235-budget-manuscript")
            && execution_plan.compiler_profile_id == "b235-budget-manuscript",
        compiled_budget_profile.as_deref() == Some("b235-budget-manuscript")
            || execution_plan.compiler_profile_id == "b235-budget-manuscript",
    );
    let task_profile_fit = fit_label(
        compiled_task_profile.as_deref() == Some("manuscript")
            && execution_plan.task_family == "manuscript",
        compiled_task_profile.as_deref() == Some("manuscript")
            || execution_plan.task_family == "manuscript"
            || suggested_work_mode.as_deref() == Some("manuscript"),
    );
    let subagent_fit = fit_label(
        execution_plan.selected_subagent_id == "manuscript"
            && suggested_subagent_id.as_deref() == Some("manuscript"),
        execution_plan.selected_subagent_id == "manuscript"
            || suggested_subagent_id.as_deref() == Some("manuscript"),
    );
    let handoff_quality = fit_label(
        context_packet.handoff.handoff_present
            && execution_plan.task_family == "manuscript"
            && execution_plan.selected_subagent_id == "manuscript",
        context_packet.handoff.handoff_present,
    );
    let editorial_acceptance_fit = editorial_acceptance_fit_label(
        Some(execution_reflection),
        &execution_plan.task_family,
        &execution_plan.selected_subagent_id,
    );
    let context_sufficiency = if !trajectory_eval.compiled_context_sufficient {
        "insufficient".to_string()
    } else if task_profile_fit == FIT_LABEL_GOOD
        && compiler_profile_fit == FIT_LABEL_GOOD
        && graphrag_mode_fit != FIT_LABEL_POOR
        && subagent_fit != FIT_LABEL_POOR
    {
        "adequate".to_string()
    } else {
        "adequate-but-misaligned".to_string()
    };
    let same_beagle_owned_identity = context_packet.workstream_id == trajectory_quality.workstream_id
        && context_packet.workspace_id == trajectory_quality.workspace_id
        && context_packet.session_id == trajectory_quality.session_id
        && trajectory_eval.workstream_id == trajectory_quality.workstream_id
        && promotion_gate.workstream_id == trajectory_quality.workstream_id;

    ManuscriptContextAdequacy {
        context_adequacy_version: MANUSCRIPT_CONTEXT_ADEQUACY_VERSION.to_string(),
        manuscript_context_adequacy_id: format!(
            "{}-manuscript-context-adequacy",
            trajectory_quality.manuscript_trajectory_quality_id
        ),
        manuscript_trajectory_quality_id: trajectory_quality
            .manuscript_trajectory_quality_id
            .clone(),
        manuscript_promotion_gate_id: promotion_gate.manuscript_promotion_gate_id.clone(),
        source_trajectory_eval_id: trajectory_eval.trajectory_eval_id.clone(),
        source_execution_reflection_id: execution_reflection.reflection_id.clone(),
        source_plan_id: execution_plan.plan_id.clone(),
        workstream_id: execution_plan.workstream_id.clone(),
        workspace_id: execution_plan.workspace_id.clone(),
        session_id: execution_plan.session_id.clone(),
        generated_at,
        rollout_stage: MANUSCRIPT_QUALITY_UPLIFT_STAGE_STATE.to_string(),
        task_family: execution_plan.task_family.clone(),
        selected_subagent_id: execution_plan.selected_subagent_id.clone(),
        expected_subagent_id: execution_reflection.expected_subagent_id.clone(),
        suggested_subagent_id,
        suggested_work_mode,
        active_retrieval_query_type: active_query_type,
        active_retrieval_mode,
        compiled_context_retrieval_query_type: compiled_query_type,
        compiled_context_task_profile: compiled_task_profile,
        compiled_context_budget_profile_id: compiled_budget_profile,
        active_graphrag_query_mode: active_graphrag_mode,
        compiled_context_graphrag_query_mode: compiled_graphrag_mode,
        temporal_truth_view,
        compiled_context_sufficient: trajectory_eval.compiled_context_sufficient,
        context_sufficiency,
        retrieval_lane_fit,
        graphrag_mode_fit,
        truth_view_fit,
        compiler_profile_fit,
        task_profile_fit,
        subagent_fit,
        handoff_quality,
        editorial_acceptance_fit,
        same_beagle_owned_identity,
        note: "B24.18 checks whether manuscript context is merely sufficient in volume or actually adequate for manuscript work, including task-profile, compiler-profile, GraphRAG, truth-view, and handoff fit.".to_string(),
    }
}

fn build_manuscript_tuning_recommendation(
    trajectory_quality: &ManuscriptTrajectoryQuality,
    context_adequacy: &ManuscriptContextAdequacy,
    promotion_gate: &ManuscriptPromotionGate,
    generated_at: DateTime<Utc>,
) -> ManuscriptTuningRecommendation {
    let mut recommended_changes = Vec::new();
    if context_adequacy.task_family != "manuscript" || context_adequacy.task_profile_fit != FIT_LABEL_GOOD {
        recommended_changes.push(
            "Switch the next bounded shadow retest to task_family='manuscript' so the editorial lane is evaluated directly instead of inheriting the analysis lane.".to_string(),
        );
    }
    if context_adequacy.selected_subagent_id != "manuscript" {
        recommended_changes.push(
            "Route the next shadow retest through selected_subagent_id='manuscript' to match the manuscript-specific acceptance path.".to_string(),
        );
    }
    if context_adequacy
        .compiled_context_budget_profile_id
        .as_deref()
        != Some("b235-budget-manuscript")
    {
        recommended_changes.push(
            "Compile the manuscript retest context with compiler_profile_id='b235-budget-manuscript' so the context task profile stops inheriting analysis defaults.".to_string(),
        );
    }
    if context_adequacy.compiled_context_graphrag_query_mode.as_deref() != Some("global")
        || context_adequacy.active_graphrag_query_mode.as_deref() != Some("global")
    {
        recommended_changes.push(
            "Hold GraphRAG on 'global' end-to-end for the manuscript shadow retest instead of mixing a local active lane with a global compiled context.".to_string(),
        );
    }
    if context_adequacy.temporal_truth_view.as_deref() != Some("both") {
        recommended_changes.push(
            "Keep temporal_truth_view='both' for manuscript retests so editorial drafting sees current and historical evidence together.".to_string(),
        );
    }
    recommended_changes.push(
        "Materialize the next candidate as a workspace-manuscript-handoff followed by workspace-manuscript-assembly before any further promotion recheck.".to_string(),
    );
    let highest_impact_fix = if context_adequacy.task_profile_fit != FIT_LABEL_GOOD
        || context_adequacy.compiler_profile_fit != FIT_LABEL_GOOD
    {
        "move the retest onto the dedicated manuscript task/profile lane".to_string()
    } else if context_adequacy.subagent_fit != FIT_LABEL_GOOD {
        "route the retest through the manuscript subagent".to_string()
    } else if context_adequacy.graphrag_mode_fit != FIT_LABEL_GOOD {
        "stabilize GraphRAG to global across retrieval and compiled context".to_string()
    } else {
        "retest the bounded manuscript policy in shadow with the dedicated editorial handoff package".to_string()
    };

    ManuscriptTuningRecommendation {
        recommendation_version: MANUSCRIPT_TUNING_RECOMMENDATION_VERSION.to_string(),
        manuscript_tuning_recommendation_id: format!(
            "{}-manuscript-tuning-recommendation",
            context_adequacy.manuscript_context_adequacy_id
        ),
        manuscript_trajectory_quality_id: trajectory_quality
            .manuscript_trajectory_quality_id
            .clone(),
        manuscript_context_adequacy_id: context_adequacy.manuscript_context_adequacy_id.clone(),
        manuscript_promotion_gate_id: promotion_gate.manuscript_promotion_gate_id.clone(),
        control_policy_id: promotion_gate.control_policy_id.clone(),
        manuscript_candidate_policy_id: promotion_gate.manuscript_candidate_policy_id.clone(),
        workstream_id: trajectory_quality.workstream_id.clone(),
        workspace_id: trajectory_quality.workspace_id.clone(),
        session_id: trajectory_quality.session_id.clone(),
        generated_at,
        rollout_stage: MANUSCRIPT_QUALITY_UPLIFT_STAGE_STATE.to_string(),
        current_promotion_gate_decision: promotion_gate.promotion_gate_decision.clone(),
        manuscript_must_remain_shadow: true,
        candidate_policy_mode: "shadow-retest".to_string(),
        candidate_tuned_policy_id: format!(
            "{}-b2418-quality-uplift",
            promotion_gate.manuscript_candidate_policy_id
        ),
        candidate_task_family: "manuscript".to_string(),
        candidate_selected_subagent_id: "manuscript".to_string(),
        candidate_work_mode: "manuscript".to_string(),
        candidate_retrieval_query_type: "general".to_string(),
        candidate_compiler_profile_id: "b235-budget-manuscript".to_string(),
        candidate_graphrag_query_mode: "global".to_string(),
        candidate_temporal_truth_view: "both".to_string(),
        candidate_context_task_profile: "manuscript".to_string(),
        candidate_context_budget_profile_id: "b235-budget-manuscript".to_string(),
        candidate_handoff_package: "workspace-manuscript-handoff".to_string(),
        candidate_assembly_package: "workspace-manuscript-assembly".to_string(),
        editorial_acceptance_target: REVIEW_QUALITY_LABEL_OPERATOR_READY.to_string(),
        next_validation_mode: "shadow-retest".to_string(),
        promotion_readiness_label: "tune-in-shadow".to_string(),
        recommended_changes,
        highest_impact_fix,
        same_beagle_owned_identity: trajectory_quality.same_beagle_owned_identity
            && context_adequacy.same_beagle_owned_identity
            && promotion_gate.same_beagle_owned_identity,
        note: "B24.18 keeps manuscript on explicit control plus shadow and produces a bounded tuned-policy candidate for the next editorial shadow retest instead of forcing canary promotion.".to_string(),
    }
}

fn analysis_sample_flags(
    calibration_bundle: &AutonomyPolicyCalibrationBundle,
) -> BTreeMap<String, (bool, bool)> {
    calibration_bundle
        .calibration_dataset
        .samples
        .iter()
        .filter(|sample| sample.task_family == "analysis")
        .map(|sample| {
            (
                sample.sample_id.clone(),
                (
                    sample.operator_alignment_observed.is_some(),
                    sample.execution_alignment_observed.is_some(),
                ),
            )
        })
        .collect::<BTreeMap<_, _>>()
}

fn manuscript_sample_alignment_observations(
    calibration_bundle: &AutonomyPolicyCalibrationBundle,
) -> BTreeMap<String, (Option<bool>, Option<bool>)> {
    calibration_bundle
        .calibration_dataset
        .samples
        .iter()
        .filter(|sample| sample.task_family == "manuscript")
        .map(|sample| {
            (
                sample.sample_id.clone(),
                (
                    sample.operator_alignment_observed,
                    sample.execution_alignment_observed,
                ),
            )
        })
        .collect::<BTreeMap<_, _>>()
}

fn build_manuscript_alignment_label_entry(
    entry: &ManuscriptShadowHistoryEntry,
    review_quality: &str,
) -> ManuscriptAlignmentLabelEntry {
    let operator_alignment_label =
        operator_alignment_label_from_observation(entry.operator_alignment_observed);
    let execution_outcome_alignment_label =
        execution_outcome_alignment_label_from_observation(
            entry.execution_alignment_observed,
        );
    let promotion_readiness_label = manuscript_promotion_readiness_label(
        &entry.manuscript_candidate_decision_class,
        &operator_alignment_label,
        &execution_outcome_alignment_label,
        review_quality,
        entry.regression,
    );

    ManuscriptAlignmentLabelEntry {
        observation_id: entry.observation_id.clone(),
        sample_id: entry.sample_id.clone(),
        sample_source: entry.sample_source.clone(),
        observed_at: entry.observed_at,
        expected_decision_class: entry.expected_decision_class.clone(),
        current_policy_decision_class: entry.current_policy_decision_class.clone(),
        manuscript_candidate_decision_class: entry.manuscript_candidate_decision_class.clone(),
        operator_alignment_label,
        execution_outcome_alignment_label,
        review_quality_label: review_quality.to_string(),
        promotion_readiness_label,
        regression: entry.regression,
        note: format!(
            "{} B24.16 materializes explicit manuscript alignment labels so the promotion gate can distinguish aligned, misaligned, and insufficient-evidence observations.",
            entry.note
        ),
    }
}

fn manuscript_promotion_readiness_label(
    manuscript_candidate_decision_class: &str,
    operator_alignment_label: &str,
    execution_outcome_alignment_label: &str,
    review_quality_label: &str,
    regression: bool,
) -> String {
    if regression
        || operator_alignment_label == ALIGNMENT_LABEL_MISALIGNED
        || execution_outcome_alignment_label == ALIGNMENT_LABEL_MISALIGNED
    {
        "rollback-shadow".to_string()
    } else if manuscript_candidate_decision_class == "blocked" {
        "keep-shadow".to_string()
    } else if operator_alignment_label == ALIGNMENT_LABEL_ALIGNED
        && execution_outcome_alignment_label == ALIGNMENT_LABEL_ALIGNED
        && review_quality_label == REVIEW_QUALITY_LABEL_OPERATOR_READY
    {
        "supports-stage-manuscript-canary".to_string()
    } else {
        "keep-shadow".to_string()
    }
}

fn manuscript_promotion_evidence_sufficient(
    promotion_evidence: Option<&ManuscriptPromotionEvidence>,
    shadow_sample_count: usize,
) -> bool {
    let Some(promotion_evidence) = promotion_evidence else {
        return false;
    };
    promotion_evidence.shadow_sample_count == shadow_sample_count
        && promotion_evidence.operator_alignment_label_coverage_basis_points == 10_000
        && promotion_evidence.execution_outcome_alignment_label_coverage_basis_points == 10_000
        && promotion_evidence.operator_alignment_basis_points
            >= MANUSCRIPT_PROMOTION_MIN_ALIGNMENT_BASIS_POINTS
        && promotion_evidence.execution_outcome_alignment_basis_points
            >= MANUSCRIPT_PROMOTION_MIN_ALIGNMENT_BASIS_POINTS
        && promotion_evidence.review_quality_label == REVIEW_QUALITY_LABEL_OPERATOR_READY
        && promotion_evidence.promotion_ready_count == shadow_sample_count
        && promotion_evidence.promotion_block_count == 0
        && promotion_evidence.same_beagle_owned_identity
}

fn build_manuscript_shadow_history_entry(
    sample: &ManuscriptShadowComparisonEntry,
    observation_id: String,
    sample_source: String,
    observed_at: DateTime<Utc>,
    operator_alignment_observed: Option<bool>,
    execution_alignment_observed: Option<bool>,
    note: String,
) -> ManuscriptShadowHistoryEntry {
    ManuscriptShadowHistoryEntry {
        observation_id,
        sample_id: sample.sample_id.clone(),
        sample_source,
        observed_at,
        expected_decision_class: sample.expected_decision_class.clone(),
        current_policy_decision_class: sample.current_policy_decision_class.clone(),
        manuscript_candidate_decision_class: sample.manuscript_candidate_decision_class.clone(),
        operator_alignment_observed,
        execution_alignment_observed,
        improved_alignment: sample.improved_alignment,
        regression: sample.regression,
        note,
    }
}

fn manuscript_operator_alignment_signal(
    manuscript_candidate_decision_class: &str,
    review_decision: Option<&ReviewDecision>,
    follow_on_plan: Option<&FollowOnPlan>,
) -> Option<bool> {
    let observed_decision_class =
        manuscript_operator_observed_decision_class(review_decision, follow_on_plan)?;
    Some(manuscript_candidate_decision_class == observed_decision_class)
}

fn manuscript_execution_alignment_signal(
    manuscript_candidate_decision_class: &str,
    execution_reflection: Option<&ExecutionReflection>,
    follow_on_plan: Option<&FollowOnPlan>,
) -> Option<bool> {
    let observed_decision_class =
        manuscript_execution_observed_decision_class(execution_reflection, follow_on_plan)?;
    Some(manuscript_candidate_decision_class == observed_decision_class)
}

fn manuscript_operator_observed_decision_class<'a>(
    review_decision: Option<&'a ReviewDecision>,
    follow_on_plan: Option<&'a FollowOnPlan>,
) -> Option<&'static str> {
    let review_decision = review_decision?;
    let follow_on_task_family = follow_on_plan
        .map(|plan| plan.execution_plan.task_family.as_str())
        .unwrap_or("analysis");
    match review_decision.decision_action.as_str() {
        "rejected" => Some("blocked"),
        "edited" if follow_on_task_family != "manuscript" => Some("blocked"),
        "edited" => Some("review-required"),
        "approved" if follow_on_task_family == "manuscript" => Some("auto-continue"),
        "approved" => Some("blocked"),
        _ => None,
    }
}

fn manuscript_execution_observed_decision_class<'a>(
    execution_reflection: Option<&'a ExecutionReflection>,
    follow_on_plan: Option<&'a FollowOnPlan>,
) -> Option<&'static str> {
    let follow_on_task_family = follow_on_plan
        .map(|plan| plan.execution_plan.task_family.as_str())
        .unwrap_or("analysis");
    if follow_on_task_family != "manuscript" {
        return Some("blocked");
    }
    let execution_reflection = execution_reflection?;
    if execution_reflection.operator_followup_action == "review-stop-and-replan"
        || execution_reflection.overall_quality_score < 60
    {
        Some("blocked")
    } else if execution_reflection.acceptance_criteria_passed
        && execution_reflection.compiled_context_sufficient
        && execution_reflection.overall_quality_score >= 85
        && execution_reflection.operator_followup_action == "review-and-approve-next-plan"
    {
        Some("auto-continue")
    } else {
        Some("review-required")
    }
}

fn build_analysis_shadow_history_entry(
    sample: &AnalysisShadowComparisonEntry,
    observation_id: String,
    sample_source: String,
    observed_at: DateTime<Utc>,
    operator_alignment_observed: bool,
    execution_alignment_observed: bool,
    note: String,
) -> AnalysisShadowHistoryEntry {
    AnalysisShadowHistoryEntry {
        observation_id,
        sample_id: sample.sample_id.clone(),
        sample_source,
        observed_at,
        expected_decision_class: sample.expected_decision_class.clone(),
        current_policy_decision_class: sample.current_policy_decision_class.clone(),
        analysis_candidate_decision_class: sample.analysis_candidate_decision_class.clone(),
        operator_alignment_observed,
        execution_alignment_observed,
        improved_alignment: sample.improved_alignment,
        regression: sample.regression,
        note,
    }
}

fn history_false_rate_basis_points(
    history: &[AnalysisShadowHistoryEntry],
    predicted_decision_class: &str,
    lens: AnalysisHistoryDecisionLens,
) -> u16 {
    let predicted = history
        .iter()
        .filter(|entry| history_decision_class(entry, lens) == predicted_decision_class)
        .collect::<Vec<_>>();
    if predicted.is_empty() {
        return 0;
    }
    let incorrect = predicted
        .iter()
        .filter(|entry| entry.expected_decision_class != predicted_decision_class)
        .count();
    rate_basis_points(incorrect, predicted.len())
}

fn history_alignment_rate_basis_points(
    history: &[AnalysisShadowHistoryEntry],
    decision_lens: AnalysisHistoryDecisionLens,
    observed_lens: AnalysisHistoryObservedLens,
) -> u16 {
    let observed = history
        .iter()
        .filter(|entry| match observed_lens {
            AnalysisHistoryObservedLens::OperatorDecision => entry.operator_alignment_observed,
            AnalysisHistoryObservedLens::ExecutionOutcome => entry.execution_alignment_observed,
        })
        .collect::<Vec<_>>();
    if observed.is_empty() {
        return 0;
    }
    let aligned = observed
        .iter()
        .filter(|entry| history_decision_class(entry, decision_lens) == entry.expected_decision_class)
        .count();
    rate_basis_points(aligned, observed.len())
}

fn manuscript_history_false_rate_basis_points(
    history: &[ManuscriptShadowHistoryEntry],
    predicted_decision_class: &str,
    lens: ManuscriptHistoryDecisionLens,
) -> u16 {
    let predicted = history
        .iter()
        .filter(|entry| manuscript_history_decision_class(entry, lens) == predicted_decision_class)
        .collect::<Vec<_>>();
    if predicted.is_empty() {
        return 0;
    }
    let incorrect = predicted
        .iter()
        .filter(|entry| entry.expected_decision_class != predicted_decision_class)
        .count();
    rate_basis_points(incorrect, predicted.len())
}

fn manuscript_history_alignment_rate_basis_points(
    history: &[ManuscriptShadowHistoryEntry],
    _decision_lens: ManuscriptHistoryDecisionLens,
    observed_lens: ManuscriptHistoryObservedLens,
) -> u16 {
    let observed = history
        .iter()
        .filter_map(|entry| match observed_lens {
            ManuscriptHistoryObservedLens::OperatorDecision => {
                entry.operator_alignment_observed.map(|aligned| (entry, aligned))
            }
            ManuscriptHistoryObservedLens::ExecutionOutcome => {
                entry.execution_alignment_observed.map(|aligned| (entry, aligned))
            }
        })
        .collect::<Vec<_>>();
    if observed.is_empty() {
        return 0;
    }
    let aligned = observed
        .iter()
        .filter(|(_, aligned)| *aligned)
        .count();
    rate_basis_points(aligned, observed.len())
}

fn history_decision_class(
    entry: &AnalysisShadowHistoryEntry,
    lens: AnalysisHistoryDecisionLens,
) -> &str {
    match lens {
        AnalysisHistoryDecisionLens::Current => &entry.current_policy_decision_class,
        AnalysisHistoryDecisionLens::Candidate => &entry.analysis_candidate_decision_class,
    }
}

fn manuscript_history_decision_class(
    entry: &ManuscriptShadowHistoryEntry,
    lens: ManuscriptHistoryDecisionLens,
) -> &str {
    match lens {
        ManuscriptHistoryDecisionLens::Current => &entry.current_policy_decision_class,
        ManuscriptHistoryDecisionLens::Candidate => &entry.manuscript_candidate_decision_class,
    }
}

fn analysis_promotion_gate_decision(
    shadow_sample_count: usize,
    false_auto_continue_rate_basis_points: u16,
    false_review_required_rate_basis_points: u16,
    alignment_with_operator_decision_basis_points: u16,
    alignment_with_execution_outcome_basis_points: u16,
    control_alignment_with_operator_decision_basis_points: u16,
    control_alignment_with_execution_outcome_basis_points: u16,
    regression_count: usize,
    implementation_canary_retained: bool,
    manuscript_control_retained: bool,
) -> (String, bool, bool, String) {
    if !implementation_canary_retained || !manuscript_control_retained {
        return (
            "rollback-shadow".to_string(),
            false,
            true,
            "Analysis shadow cannot promote while the implementation canary or manuscript control retention is degraded, so the bounded response is to hold the shadow path and roll back the candidate staging.".to_string(),
        );
    }
    if regression_count > 0 || false_auto_continue_rate_basis_points > 0 {
        return (
            "rollback-shadow".to_string(),
            false,
            true,
            "Analysis shadow observed a regression or a false auto-continue, so the candidate must stay non-live and the shadow path should be rolled back to the last known-good control interpretation.".to_string(),
        );
    }
    if alignment_with_operator_decision_basis_points
        < control_alignment_with_operator_decision_basis_points
        || alignment_with_execution_outcome_basis_points
            < control_alignment_with_execution_outcome_basis_points
    {
        return (
            "rollback-shadow".to_string(),
            false,
            true,
            "Analysis shadow alignment dropped below the control baseline, so promotion is unsafe and the candidate should roll back to shadow hold only.".to_string(),
        );
    }
    let promotion_criteria_met = shadow_sample_count >= ANALYSIS_PROMOTION_MIN_SHADOW_SAMPLES
        && false_review_required_rate_basis_points == 0
        && alignment_with_operator_decision_basis_points
            >= ANALYSIS_PROMOTION_MIN_ALIGNMENT_BASIS_POINTS
        && alignment_with_execution_outcome_basis_points
            >= ANALYSIS_PROMOTION_MIN_ALIGNMENT_BASIS_POINTS;
    if promotion_criteria_met {
        return (
            "stage-analysis-canary".to_string(),
            true,
            false,
            "Analysis shadow has accumulated enough bounded samples with zero false auto-continue, zero false review-required, and control-matching alignment, so the next guarded step can be a staged analysis canary.".to_string(),
        );
    }

    let rationale = if shadow_sample_count < ANALYSIS_PROMOTION_MIN_SHADOW_SAMPLES {
        format!(
            "Analysis shadow remains bounded but sample-limited: {} of {} required shadow samples have been accumulated, so the safe decision is keep-shadow.",
            shadow_sample_count, ANALYSIS_PROMOTION_MIN_SHADOW_SAMPLES
        )
    } else if false_review_required_rate_basis_points > 0 {
        "Analysis shadow is still too conservative on the rolling window, so the candidate should remain shadow-only until the false review-required rate returns to zero.".to_string()
    } else {
        "Analysis shadow has not regressed, but the promotion threshold has not been met yet, so keep-shadow preserves operator visibility while more bounded evidence accumulates.".to_string()
    };
    ("keep-shadow".to_string(), false, true, rationale)
}

fn manuscript_promotion_gate_decision(
    shadow_sample_count: usize,
    false_auto_continue_rate_basis_points: u16,
    false_review_required_rate_basis_points: u16,
    alignment_with_operator_decision_basis_points: u16,
    alignment_with_execution_outcome_basis_points: u16,
    control_alignment_with_operator_decision_basis_points: u16,
    control_alignment_with_execution_outcome_basis_points: u16,
    regression_count: usize,
    implementation_canary_retained: bool,
    analysis_canary_retained: bool,
    promotion_evidence: Option<&ManuscriptPromotionEvidence>,
    promotion_evidence_sufficient: bool,
) -> (String, bool, bool, String) {
    if !implementation_canary_retained || !analysis_canary_retained {
        return (
            "rollback-shadow".to_string(),
            false,
            true,
            "Manuscript shadow cannot promote while the retained implementation or analysis canary is degraded, so the bounded response is to hold the manuscript candidate and keep control live.".to_string(),
        );
    }
    if regression_count > 0 || false_auto_continue_rate_basis_points > 0 {
        return (
            "rollback-shadow".to_string(),
            false,
            true,
            "Manuscript shadow observed a regression or a false auto-continue, so the candidate must stay non-live and the shadow path should roll back to the last known-good control interpretation.".to_string(),
        );
    }
    if let Some(promotion_evidence) = promotion_evidence {
        if promotion_evidence.promotion_block_count > 0 {
            return (
                "rollback-shadow".to_string(),
                false,
                true,
                "Manuscript promotion evidence now includes explicit misalignment or regression labels, so the safe bounded response is rollback-shadow until the labeled evidence is corrected.".to_string(),
            );
        }
    } else if alignment_with_operator_decision_basis_points
        < control_alignment_with_operator_decision_basis_points
        || alignment_with_execution_outcome_basis_points
            < control_alignment_with_execution_outcome_basis_points
    {
        return (
            "rollback-shadow".to_string(),
            false,
            true,
            "Manuscript shadow alignment dropped below the control baseline, so promotion is unsafe and the candidate should remain shadow-only.".to_string(),
        );
    }
    let promotion_criteria_met = if let Some(promotion_evidence) = promotion_evidence {
        shadow_sample_count >= MANUSCRIPT_PROMOTION_MIN_SHADOW_SAMPLES
            && false_review_required_rate_basis_points == 0
            && promotion_evidence_sufficient
            && promotion_evidence.promotion_readiness_label
                == "supports-stage-manuscript-canary"
    } else {
        shadow_sample_count >= MANUSCRIPT_PROMOTION_MIN_SHADOW_SAMPLES
            && false_review_required_rate_basis_points == 0
            && alignment_with_operator_decision_basis_points
                >= MANUSCRIPT_PROMOTION_MIN_ALIGNMENT_BASIS_POINTS
            && alignment_with_execution_outcome_basis_points
                >= MANUSCRIPT_PROMOTION_MIN_ALIGNMENT_BASIS_POINTS
    };
    if promotion_criteria_met {
        return (
            "stage-manuscript-canary".to_string(),
            true,
            false,
            "Manuscript shadow has accumulated enough bounded samples with zero false auto-continue, zero false review-required, and control-matching alignment, so the next guarded step can be a staged manuscript canary.".to_string(),
        );
    }

    let rationale = if shadow_sample_count < MANUSCRIPT_PROMOTION_MIN_SHADOW_SAMPLES {
        format!(
            "Manuscript shadow remains bounded but sample-limited: {} of {} required shadow samples have been accumulated, so the safe decision is keep-shadow.",
            shadow_sample_count, MANUSCRIPT_PROMOTION_MIN_SHADOW_SAMPLES
        )
    } else if false_review_required_rate_basis_points > 0 {
        "Manuscript shadow is still too conservative on the rolling window, so the candidate should remain shadow-only until the false review-required rate returns to zero.".to_string()
    } else if let Some(promotion_evidence) = promotion_evidence {
        if promotion_evidence.operator_alignment_labeled_count == 0
            || promotion_evidence.execution_outcome_alignment_labeled_count == 0
        {
            "Manuscript shadow has enough bounded samples, but the promotion evidence still has zero explicit operator or execution-outcome labels, so the safe decision is keep-shadow until aligned labels are captured.".to_string()
        } else if promotion_evidence.operator_alignment_label_coverage_basis_points == 10_000
            && promotion_evidence.execution_outcome_alignment_label_coverage_basis_points
                == 10_000
            && promotion_evidence.promotion_ready_count == 0
            && promotion_evidence.promotion_block_count == 0
        {
            "Manuscript shadow now has full explicit alignment coverage, but the labeled evidence still only supports blocked or hold posture rather than a canary-worthy manuscript lane, so keep-shadow remains the bounded choice.".to_string()
        } else if !promotion_evidence_sufficient {
            "Manuscript shadow now has explicit labels, but the label coverage, aligned evidence, or review quality is still below the staged-canary threshold, so keep-shadow remains the bounded choice.".to_string()
        } else {
            "Manuscript shadow evidence remains operator-visible and explicit, but the gate still lacks enough promotion-ready labels to justify a staged manuscript canary.".to_string()
        }
    } else {
        "Manuscript shadow has not regressed, but the promotion threshold has not been met yet, so keep-shadow preserves operator visibility while more bounded evidence accumulates.".to_string()
    };
    ("keep-shadow".to_string(), false, true, rationale)
}

fn current_control_family_threshold(
    policy: &AutonomyPolicy,
    task_family: &str,
) -> AutonomyShadowTaskFamilyThreshold {
    let auto_continue_enabled = policy.auto_continue_task_families.iter().any(|family| family == task_family);
    AutonomyShadowTaskFamilyThreshold {
        task_family: task_family.to_string(),
        rollout_state: if task_family == "analysis" {
            "active-current".to_string()
        } else {
            "review-required-control".to_string()
        },
        auto_continue_enabled,
        auto_continue_allowed_review_actions: policy.auto_continue_allowed_review_actions.clone(),
        auto_continue_allowed_trajectory_qualities: policy
            .auto_continue_allowed_trajectory_qualities
            .clone(),
        auto_continue_min_overall_quality_score: policy.auto_continue_min_overall_quality_score,
        auto_continue_min_trajectory_score: 90,
        blocked_max_overall_quality_score: policy.blocked_max_overall_quality_score,
        blocked_max_trajectory_score: 69,
        blocked_trajectory_qualities: policy.blocked_trajectory_qualities.clone(),
        allowed_subagent_ids: if auto_continue_enabled {
            policy.auto_continue_subagent_ids.clone()
        } else {
            Vec::new()
        },
        allowed_retrieval_query_types: if auto_continue_enabled {
            policy.auto_continue_retrieval_query_types.clone()
        } else {
            Vec::new()
        },
        allowed_compiler_profile_ids: if auto_continue_enabled {
            policy.auto_continue_compiler_profile_ids.clone()
        } else {
            Vec::new()
        },
        allowed_graphrag_query_modes: if auto_continue_enabled {
            policy.auto_continue_graphrag_query_modes.clone()
        } else {
            Vec::new()
        },
        allowed_temporal_truth_views: if auto_continue_enabled {
            policy.auto_continue_temporal_truth_views.clone()
        } else {
            Vec::new()
        },
        blocked_requested_operator_actions: policy.blocked_requested_operator_actions.clone(),
        blocked_when_replan_required: true,
        guarded_enablement_eligible: false,
        rationale: if task_family == "analysis" {
            "Current control lane preserved from B24.6.".to_string()
        } else {
            "Current control policy does not auto-continue this family.".to_string()
        },
    }
}

fn task_family_rollout_metric(
    dataset: &AutonomyCalibrationDataset,
    task_family: &str,
    current_policy: &AutonomyShadowThreshold,
    candidate_policy: &AutonomyShadowThreshold,
) -> TaskFamilyRolloutMetric {
    let family_samples = family_samples(dataset, task_family);
    let current_auto_continue_count =
        count_shadow_predicted(&family_samples, "auto-continue", current_policy);
    let current_review_required_count =
        count_shadow_predicted(&family_samples, "review-required", current_policy);
    let current_blocked_count = count_shadow_predicted(&family_samples, "blocked", current_policy);
    let candidate_auto_continue_count =
        count_shadow_predicted(&family_samples, "auto-continue", candidate_policy);
    let candidate_review_required_count =
        count_shadow_predicted(&family_samples, "review-required", candidate_policy);
    let candidate_blocked_count =
        count_shadow_predicted(&family_samples, "blocked", candidate_policy);
    let improved_alignment_count =
        improved_alignment_count(&family_samples, current_policy, candidate_policy);
    let regression_count = regression_count(&family_samples, current_policy, candidate_policy);
    let candidate_false_auto_continue_rate_basis_points =
        false_rate_basis_points_for_shadow_policy(
            &family_samples,
            "auto-continue",
            candidate_policy,
        );
    let candidate_false_review_required_rate_basis_points =
        false_rate_basis_points_for_shadow_policy(
            &family_samples,
            "review-required",
            candidate_policy,
        );
    let rollout_readiness = if task_family == "implementation"
        && improved_alignment_count > 0
        && regression_count == 0
        && candidate_false_auto_continue_rate_basis_points == 0
        && candidate_false_review_required_rate_basis_points == 0
    {
        "guarded-canary-ready".to_string()
    } else if task_family == "analysis" {
        "keep-current-control".to_string()
    } else if task_family == "manuscript" {
        "hold-review-or-block".to_string()
    } else {
        "keep-shadow-only".to_string()
    };

    TaskFamilyRolloutMetric {
        task_family: task_family.to_string(),
        sample_count: family_samples.len(),
        current_auto_continue_count,
        current_review_required_count,
        current_blocked_count,
        candidate_auto_continue_count,
        candidate_review_required_count,
        candidate_blocked_count,
        current_false_auto_continue_rate_basis_points:
            false_rate_basis_points_for_shadow_policy(
                &family_samples,
                "auto-continue",
                current_policy,
            ),
        candidate_false_auto_continue_rate_basis_points,
        current_false_review_required_rate_basis_points:
            false_rate_basis_points_for_shadow_policy(
                &family_samples,
                "review-required",
                current_policy,
            ),
        candidate_false_review_required_rate_basis_points,
        current_false_blocked_rate_basis_points: false_rate_basis_points_for_shadow_policy(
            &family_samples,
            "blocked",
            current_policy,
        ),
        candidate_false_blocked_rate_basis_points:
            false_rate_basis_points_for_shadow_policy(
                &family_samples,
                "blocked",
                candidate_policy,
            ),
        current_alignment_with_operator_decision_basis_points:
            alignment_rate_basis_points_for_shadow_policy(
                &family_samples,
                current_policy,
                AlignmentLens::OperatorDecision,
            ),
        candidate_alignment_with_operator_decision_basis_points:
            alignment_rate_basis_points_for_shadow_policy(
                &family_samples,
                candidate_policy,
                AlignmentLens::OperatorDecision,
            ),
        current_alignment_with_execution_outcome_basis_points:
            alignment_rate_basis_points_for_shadow_policy(
                &family_samples,
                current_policy,
                AlignmentLens::ExecutionOutcome,
            ),
        candidate_alignment_with_execution_outcome_basis_points:
            alignment_rate_basis_points_for_shadow_policy(
                &family_samples,
                candidate_policy,
                AlignmentLens::ExecutionOutcome,
            ),
        improved_alignment_count,
        regression_count,
        rollout_readiness: rollout_readiness.clone(),
        note: format!(
            "Task family '{}' rollout readiness={} after comparing the current control against the candidate shadow threshold.",
            task_family, rollout_readiness
        ),
    }
}

fn shadow_threshold_for_family<'a>(
    policy: &'a AutonomyShadowThreshold,
    task_family: &str,
) -> Option<&'a AutonomyShadowTaskFamilyThreshold> {
    policy
        .family_thresholds
        .iter()
        .find(|threshold| threshold.task_family == task_family)
}

fn implementation_canary_live(rollout_bundle: &GuardedPolicyRolloutBundle) -> bool {
    rollout_bundle.rollout_decision.guarded_enablement_permitted
        && !rollout_bundle.rollout_decision.rollback_required
}

fn weighted_basis_points<F>(
    metrics: &[TaskFamilyRolloutMetric],
    selector: F,
    sample_total: usize,
) -> u16
where
    F: Fn(&TaskFamilyRolloutMetric) -> u16,
{
    if sample_total == 0 {
        return 0;
    }

    let weighted_sum = metrics.iter().fold(0usize, |sum, metric| {
        sum + metric.sample_count.saturating_mul(selector(metric) as usize)
    });
    (weighted_sum / sample_total) as u16
}

fn evaluate_shadow_threshold_policy(
    sample: &AutonomyCalibrationSample,
    policy: &AutonomyShadowThreshold,
) -> String {
    let Some(threshold) = policy
        .family_thresholds
        .iter()
        .find(|threshold| threshold.task_family == sample.task_family)
    else {
        return "review-required".to_string();
    };

    if threshold
        .blocked_requested_operator_actions
        .contains(&sample.requested_operator_action)
        || (threshold.blocked_when_replan_required && sample.replan_required)
        || sample.overall_quality_score <= threshold.blocked_max_overall_quality_score
        || sample.trajectory_score <= threshold.blocked_max_trajectory_score
        || threshold
            .blocked_trajectory_qualities
            .contains(&sample.trajectory_quality)
    {
        return "blocked".to_string();
    }

    if threshold.auto_continue_enabled
        && threshold
            .allowed_subagent_ids
            .contains(&sample.selected_subagent_id)
        && threshold
            .allowed_retrieval_query_types
            .contains(&sample.retrieval_query_type)
        && threshold
            .allowed_compiler_profile_ids
            .contains(&sample.compiler_profile_id)
        && threshold
            .allowed_graphrag_query_modes
            .contains(&sample.graphrag_query_mode)
        && threshold
            .allowed_temporal_truth_views
            .contains(&sample.temporal_truth_view)
        && threshold
            .auto_continue_allowed_review_actions
            .contains(&sample.review_action)
        && threshold
            .auto_continue_allowed_trajectory_qualities
            .contains(&sample.trajectory_quality)
        && sample.overall_quality_score >= threshold.auto_continue_min_overall_quality_score
        && sample.trajectory_score >= threshold.auto_continue_min_trajectory_score
    {
        return "auto-continue".to_string();
    }

    "review-required".to_string()
}

fn evaluate_autonomy_policy_sample(
    sample: &AutonomyCalibrationSample,
    policy: &AutonomyPolicy,
) -> String {
    if policy
        .blocked_requested_operator_actions
        .contains(&sample.requested_operator_action)
        || sample.replan_required
        || sample.overall_quality_score <= policy.blocked_max_overall_quality_score
        || sample.trajectory_score <= 69
        || policy
            .blocked_trajectory_qualities
            .contains(&sample.trajectory_quality)
    {
        return "blocked".to_string();
    }

    if policy
        .auto_continue_task_families
        .contains(&sample.task_family)
        && policy
            .auto_continue_subagent_ids
            .contains(&sample.selected_subagent_id)
        && policy
            .auto_continue_retrieval_query_types
            .contains(&sample.retrieval_query_type)
        && policy
            .auto_continue_compiler_profile_ids
            .contains(&sample.compiler_profile_id)
        && policy
            .auto_continue_graphrag_query_modes
            .contains(&sample.graphrag_query_mode)
        && policy
            .auto_continue_temporal_truth_views
            .contains(&sample.temporal_truth_view)
        && policy
            .auto_continue_allowed_review_actions
            .contains(&sample.review_action)
        && policy
            .auto_continue_allowed_trajectory_qualities
            .contains(&sample.trajectory_quality)
        && sample.overall_quality_score >= policy.auto_continue_min_overall_quality_score
        && sample.trajectory_score >= 90
    {
        return "auto-continue".to_string();
    }

    "review-required".to_string()
}

fn sample_from_case(
    policy: &AutonomyPolicy,
    source_execution_id: &str,
    source_plan_id: &str,
    workstream_id: &str,
    workspace_id: &str,
    session_id: &str,
    case: CalibrationCase,
) -> AutonomyCalibrationSample {
    let assessment = assess_risk_input(policy, &case.input, true);
    AutonomyCalibrationSample {
        sample_id: case.sample_id,
        sample_source: case.sample_source,
        source_execution_id: source_execution_id.to_string(),
        source_plan_id: source_plan_id.to_string(),
        workstream_id: workstream_id.to_string(),
        workspace_id: workspace_id.to_string(),
        session_id: session_id.to_string(),
        task_family: case.input.task_family,
        selected_subagent_id: case.input.selected_subagent_id,
        retrieval_query_type: case.input.retrieval_query_type,
        compiler_profile_id: case.input.compiler_profile_id,
        graphrag_query_mode: case.input.graphrag_query_mode,
        temporal_truth_view: case.input.temporal_truth_view,
        trajectory_quality: case.input.trajectory_quality,
        trajectory_score: case.trajectory_score,
        overall_quality_score: case.input.overall_quality_score,
        replan_required: case.input.replan_required,
        requested_operator_action: case.input.requested_operator_action,
        review_action: case.input.review_action,
        recipe_kind: case.recipe_kind,
        experiment_id: case.experiment_id,
        current_policy_decision_class: assessment.recommended_decision_class.clone(),
        current_policy_risk_level: assessment.risk_level.clone(),
        current_policy_risk_score: assessment.risk_score,
        expected_decision_class: case.expected_decision_class.clone(),
        current_policy_correct: assessment.recommended_decision_class == case.expected_decision_class,
        operator_alignment_observed: case.operator_alignment_observed,
        execution_alignment_observed: case.execution_alignment_observed,
        continued_successfully: case.continued_successfully,
        matched_policy_signals: assessment.matched_policy_signals,
        risk_signals: assessment.risk_signals,
        outcome_source: case.outcome_source,
        shadow_scenario: case.shadow_scenario,
        note: case.note,
    }
}

fn task_family_summary(
    samples: &[AutonomyCalibrationSample],
    task_family: &str,
) -> TaskFamilyCalibrationSummary {
    let task_samples = samples
        .iter()
        .filter(|sample| sample.task_family == task_family)
        .collect::<Vec<_>>();
    let predicted_auto_continue_count = count_predicted(&task_samples, "auto-continue");
    let predicted_review_required_count = count_predicted(&task_samples, "review-required");
    let predicted_blocked_count = count_predicted(&task_samples, "blocked");
    let expected_auto_continue_count = count_expected(&task_samples, "auto-continue");
    let expected_review_required_count = count_expected(&task_samples, "review-required");
    let expected_blocked_count = count_expected(&task_samples, "blocked");
    let false_auto_continue_rate_basis_points =
        false_rate_basis_points_for_samples(&task_samples, "auto-continue");
    let false_review_required_rate_basis_points =
        false_rate_basis_points_for_samples(&task_samples, "review-required");
    let false_blocked_rate_basis_points =
        false_rate_basis_points_for_samples(&task_samples, "blocked");
    let calibration_posture = if false_auto_continue_rate_basis_points > 0 {
        "too-permissive".to_string()
    } else if false_review_required_rate_basis_points > 0 {
        "too-conservative".to_string()
    } else {
        "aligned".to_string()
    };

    TaskFamilyCalibrationSummary {
        task_family: task_family.to_string(),
        sample_count: task_samples.len(),
        predicted_auto_continue_count,
        predicted_review_required_count,
        predicted_blocked_count,
        expected_auto_continue_count,
        expected_review_required_count,
        expected_blocked_count,
        false_auto_continue_rate_basis_points,
        false_review_required_rate_basis_points,
        false_blocked_rate_basis_points,
        calibration_posture: calibration_posture.clone(),
        note: format!(
            "Task family '{}' calibration posture={} across {} sample(s).",
            task_family,
            calibration_posture,
            task_samples.len()
        ),
    }
}

fn signal_importance(samples: &[AutonomyCalibrationSample]) -> Vec<PolicySignalImpact> {
    let mut counts = BTreeMap::<String, SignalCounts>::new();
    for sample in samples {
        for matched in &sample.matched_policy_signals {
            let signal_id = matched_signal_id(matched);
            let entry = counts.entry(signal_id).or_default();
            entry.matched_count += 1;
            increment_decision_count(entry, &sample.current_policy_decision_class);
        }
        for risk_signal in &sample.risk_signals {
            let entry = counts.entry(risk_signal.signal_id.clone()).or_default();
            entry.risk_count += 1;
            increment_decision_count(entry, &sample.current_policy_decision_class);
        }
        if sample.recipe_kind.is_some() {
            counts.entry("recipe_kind".to_string()).or_default();
        }
        if sample.experiment_id.is_some() {
            counts.entry("experiment_id".to_string()).or_default();
        }
        counts.entry("trajectory_score".to_string()).or_default();
    }

    counts
        .into_iter()
        .map(|(signal_id, counts)| {
            let impact_level = if counts.blocked_count > 0 {
                "hard-stop"
            } else if counts.review_required_count > 0 && counts.auto_continue_count > 0 {
                "mixed"
            } else if counts.review_required_count > 0 {
                "review-escalation"
            } else if counts.auto_continue_count > 0 {
                "auto-continue-allow"
            } else {
                "observed-not-driving"
            };
            PolicySignalImpact {
                signal_id: signal_id.clone(),
                matched_count: counts.matched_count,
                risk_count: counts.risk_count,
                auto_continue_count: counts.auto_continue_count,
                review_required_count: counts.review_required_count,
                blocked_count: counts.blocked_count,
                impact_level: impact_level.to_string(),
                note: if impact_level == "observed-not-driving" {
                    format!(
                        "Signal '{}' is present in the calibration dataset but does not currently drive the B24.6 gate directly.",
                        signal_id
                    )
                } else {
                    format!(
                        "Signal '{}' materially affects the current policy decision distribution in the calibration dataset.",
                        signal_id
                    )
                },
            }
        })
        .collect()
}

fn threshold_for_analysis(policy: &AutonomyPolicy) -> EscalationThreshold {
    EscalationThreshold {
        task_family: "analysis".to_string(),
        stage_state: "active-current".to_string(),
        auto_continue_enabled: true,
        auto_continue_min_overall_quality_score: policy.auto_continue_min_overall_quality_score,
        auto_continue_min_trajectory_score: 90,
        blocked_max_overall_quality_score: policy.blocked_max_overall_quality_score,
        blocked_max_trajectory_score: 69,
        allowed_subagent_ids: policy.auto_continue_subagent_ids.clone(),
        allowed_retrieval_query_types: policy.auto_continue_retrieval_query_types.clone(),
        allowed_compiler_profile_ids: policy.auto_continue_compiler_profile_ids.clone(),
        allowed_graphrag_query_modes: policy.auto_continue_graphrag_query_modes.clone(),
        allowed_temporal_truth_views: policy.auto_continue_temporal_truth_views.clone(),
        blocked_requested_operator_actions: policy.blocked_requested_operator_actions.clone(),
        blocked_when_replan_required: true,
        recommended_action: "keep-current".to_string(),
        rationale: "The replayed live analysis lane aligns with the current B24.6 gate, so the existing low-risk analysis threshold remains the active baseline.".to_string(),
    }
}

fn threshold_for_implementation(dataset: &AutonomyCalibrationDataset) -> EscalationThreshold {
    let expected_auto_samples = family_expected_samples(dataset, "implementation", "auto-continue");
    let allowed_subagent_ids = collect_values(
        &expected_auto_samples,
        |sample| sample.selected_subagent_id.clone(),
        vec!["core".to_string()],
    );
    let allowed_retrieval_query_types = collect_values(
        &expected_auto_samples,
        |sample| sample.retrieval_query_type.clone(),
        vec!["code".to_string()],
    );
    let allowed_compiler_profile_ids = collect_values(
        &expected_auto_samples,
        |sample| sample.compiler_profile_id.clone(),
        vec!["b235-budget-implementation".to_string()],
    );
    let allowed_graphrag_query_modes = collect_values(
        &expected_auto_samples,
        |sample| sample.graphrag_query_mode.clone(),
        vec!["local".to_string()],
    );
    let allowed_temporal_truth_views = collect_values(
        &expected_auto_samples,
        |sample| sample.temporal_truth_view.clone(),
        vec!["current".to_string()],
    );
    let auto_continue_min_overall_quality_score = expected_auto_samples
        .iter()
        .map(|sample| sample.overall_quality_score.saturating_sub(2))
        .min()
        .unwrap_or(95);
    let auto_continue_min_trajectory_score = expected_auto_samples
        .iter()
        .map(|sample| sample.trajectory_score.saturating_sub(1))
        .min()
        .unwrap_or(95);

    EscalationThreshold {
        task_family: "implementation".to_string(),
        stage_state: SHADOW_STAGE_STATE.to_string(),
        auto_continue_enabled: true,
        auto_continue_min_overall_quality_score,
        auto_continue_min_trajectory_score,
        blocked_max_overall_quality_score: 74,
        blocked_max_trajectory_score: 69,
        allowed_subagent_ids,
        allowed_retrieval_query_types,
        allowed_compiler_profile_ids,
        allowed_graphrag_query_modes,
        allowed_temporal_truth_views,
        blocked_requested_operator_actions: vec![
            "edit-and-reapprove-plan".to_string(),
            "review-stop-and-replan".to_string(),
        ],
        blocked_when_replan_required: true,
        recommended_action: "stage-shadow-auto-continue".to_string(),
        rationale: "The shadow implementation sample is currently forced into review despite high quality, good trajectory, and repo-native code routing, so B24.7 stages a stricter implementation auto lane in shadow mode only.".to_string(),
    }
}

fn threshold_for_manuscript(dataset: &AutonomyCalibrationDataset) -> EscalationThreshold {
    let family_samples = family_samples(dataset, "manuscript");
    EscalationThreshold {
        task_family: "manuscript".to_string(),
        stage_state: SHADOW_STAGE_STATE.to_string(),
        auto_continue_enabled: false,
        auto_continue_min_overall_quality_score: 98,
        auto_continue_min_trajectory_score: 96,
        blocked_max_overall_quality_score: family_samples
            .iter()
            .filter(|sample| sample.expected_decision_class == "blocked")
            .map(|sample| sample.overall_quality_score.saturating_add(11))
            .max()
            .unwrap_or(79),
        blocked_max_trajectory_score: family_samples
            .iter()
            .filter(|sample| sample.expected_decision_class == "blocked")
            .map(|sample| sample.trajectory_score.saturating_add(9))
            .max()
            .unwrap_or(74),
        allowed_subagent_ids: vec!["manuscript".to_string()],
        allowed_retrieval_query_types: vec!["general".to_string()],
        allowed_compiler_profile_ids: vec!["b235-budget-manuscript".to_string()],
        allowed_graphrag_query_modes: vec!["global".to_string()],
        allowed_temporal_truth_views: vec!["both".to_string()],
        blocked_requested_operator_actions: vec![
            "edit-and-reapprove-plan".to_string(),
            "review-stop-and-replan".to_string(),
        ],
        blocked_when_replan_required: true,
        recommended_action: "keep-manual-review-or-block".to_string(),
        rationale: "The manuscript shadow sample remains block-prone when trajectory or replanning signals degrade, so B24.7 keeps this family out of auto-continue and favors review or block.".to_string(),
    }
}

fn evaluate_shadow_threshold(
    sample: &AutonomyCalibrationSample,
    thresholds: &EscalationThresholds,
) -> String {
    let Some(threshold) = thresholds
        .thresholds
        .iter()
        .find(|threshold| threshold.task_family == sample.task_family)
    else {
        return "review-required".to_string();
    };

    if threshold
        .blocked_requested_operator_actions
        .contains(&sample.requested_operator_action)
        || (threshold.blocked_when_replan_required && sample.replan_required)
        || sample.overall_quality_score <= threshold.blocked_max_overall_quality_score
        || sample.trajectory_score <= threshold.blocked_max_trajectory_score
        || sample.trajectory_quality == "needs-replan"
    {
        return "blocked".to_string();
    }

    if threshold.auto_continue_enabled
        && threshold
            .allowed_subagent_ids
            .contains(&sample.selected_subagent_id)
        && threshold
            .allowed_retrieval_query_types
            .contains(&sample.retrieval_query_type)
        && threshold
            .allowed_compiler_profile_ids
            .contains(&sample.compiler_profile_id)
        && threshold
            .allowed_graphrag_query_modes
            .contains(&sample.graphrag_query_mode)
        && threshold
            .allowed_temporal_truth_views
            .contains(&sample.temporal_truth_view)
        && sample.review_action == "approved"
        && sample.overall_quality_score >= threshold.auto_continue_min_overall_quality_score
        && sample.trajectory_score >= threshold.auto_continue_min_trajectory_score
        && sample.trajectory_quality == "good"
    {
        return "auto-continue".to_string();
    }

    "review-required".to_string()
}

fn count_shadow_predicted(
    samples: &[&AutonomyCalibrationSample],
    decision_class: &str,
    policy: &AutonomyShadowThreshold,
) -> usize {
    samples
        .iter()
        .filter(|sample| evaluate_shadow_threshold_policy(sample, policy) == decision_class)
        .count()
}

fn false_rate_basis_points_for_shadow_policy(
    samples: &[&AutonomyCalibrationSample],
    predicted_decision_class: &str,
    policy: &AutonomyShadowThreshold,
) -> u16 {
    let predicted = samples
        .iter()
        .filter(|sample| evaluate_shadow_threshold_policy(sample, policy) == predicted_decision_class)
        .collect::<Vec<_>>();
    if predicted.is_empty() {
        return 0;
    }
    let incorrect = predicted
        .iter()
        .filter(|sample| sample.expected_decision_class != predicted_decision_class)
        .count();
    rate_basis_points(incorrect, predicted.len())
}

fn false_rate_basis_points_for_autonomy_policy(
    samples: &[&AutonomyCalibrationSample],
    predicted_decision_class: &str,
    policy: &AutonomyPolicy,
) -> u16 {
    let predicted = samples
        .iter()
        .filter(|sample| evaluate_autonomy_policy_sample(sample, policy) == predicted_decision_class)
        .collect::<Vec<_>>();
    if predicted.is_empty() {
        return 0;
    }
    let incorrect = predicted
        .iter()
        .filter(|sample| sample.expected_decision_class != predicted_decision_class)
        .count();
    rate_basis_points(incorrect, predicted.len())
}

fn alignment_rate_basis_points_for_shadow_policy(
    samples: &[&AutonomyCalibrationSample],
    policy: &AutonomyShadowThreshold,
    lens: AlignmentLens,
) -> u16 {
    let observed = samples
        .iter()
        .filter(|sample| match lens {
            AlignmentLens::OperatorDecision => sample.operator_alignment_observed.is_some(),
            AlignmentLens::ExecutionOutcome => sample.execution_alignment_observed.is_some(),
        })
        .collect::<Vec<_>>();
    if observed.is_empty() {
        return 0;
    }
    let aligned = observed
        .iter()
        .filter(|sample| evaluate_shadow_threshold_policy(sample, policy) == sample.expected_decision_class)
        .count();
    rate_basis_points(aligned, observed.len())
}

fn alignment_rate_basis_points_for_autonomy_policy(
    samples: &[&AutonomyCalibrationSample],
    policy: &AutonomyPolicy,
    lens: AlignmentLens,
) -> u16 {
    let observed = samples
        .iter()
        .filter(|sample| match lens {
            AlignmentLens::OperatorDecision => sample.operator_alignment_observed.is_some(),
            AlignmentLens::ExecutionOutcome => sample.execution_alignment_observed.is_some(),
        })
        .collect::<Vec<_>>();
    if observed.is_empty() {
        return 0;
    }
    let aligned = observed
        .iter()
        .filter(|sample| evaluate_autonomy_policy_sample(sample, policy) == sample.expected_decision_class)
        .count();
    rate_basis_points(aligned, observed.len())
}

fn improved_alignment_count(
    samples: &[&AutonomyCalibrationSample],
    current_policy: &AutonomyShadowThreshold,
    candidate_policy: &AutonomyShadowThreshold,
) -> usize {
    samples
        .iter()
        .filter(|sample| {
            let current_correct =
                evaluate_shadow_threshold_policy(sample, current_policy) == sample.expected_decision_class;
            let candidate_correct =
                evaluate_shadow_threshold_policy(sample, candidate_policy) == sample.expected_decision_class;
            !current_correct && candidate_correct
        })
        .count()
}

fn regression_count(
    samples: &[&AutonomyCalibrationSample],
    current_policy: &AutonomyShadowThreshold,
    candidate_policy: &AutonomyShadowThreshold,
) -> usize {
    samples
        .iter()
        .filter(|sample| {
            let current_correct =
                evaluate_shadow_threshold_policy(sample, current_policy) == sample.expected_decision_class;
            let candidate_correct =
                evaluate_shadow_threshold_policy(sample, candidate_policy) == sample.expected_decision_class;
            current_correct && !candidate_correct
        })
        .count()
}

fn family_expected_samples<'a>(
    dataset: &'a AutonomyCalibrationDataset,
    task_family: &str,
    decision_class: &str,
) -> Vec<&'a AutonomyCalibrationSample> {
    dataset
        .samples
        .iter()
        .filter(|sample| {
            sample.task_family == task_family && sample.expected_decision_class == decision_class
        })
        .collect()
}

fn family_samples<'a>(
    dataset: &'a AutonomyCalibrationDataset,
    task_family: &str,
) -> Vec<&'a AutonomyCalibrationSample> {
    dataset
        .samples
        .iter()
        .filter(|sample| sample.task_family == task_family)
        .collect()
}

fn continuation_succeeded(
    continuation_state: Option<&ContinuationStatePlane>,
    continuation_receipt: Option<&ContinuationReceipt>,
) -> bool {
    continuation_state
        .map(|state| state.current_state == "succeeded")
        .unwrap_or(false)
        || continuation_receipt
            .map(|receipt| receipt.next_execution_receipt.final_state == "succeeded")
            .unwrap_or(false)
}

fn recipe_kind(plan: &ExecutionPlan) -> Option<String> {
    plan.recipe_target
        .as_ref()
        .map(|recipe| recipe.recipe_kind.clone())
}

fn experiment_id(primary_plan: &ExecutionPlan, fallback_plan: &ExecutionPlan) -> Option<String> {
    primary_plan
        .experiment_target
        .as_ref()
        .map(|target| target.experiment_id.clone())
        .or_else(|| {
            fallback_plan
                .experiment_target
                .as_ref()
                .map(|target| target.experiment_id.clone())
        })
}

fn collect_values<F>(
    samples: &[&AutonomyCalibrationSample],
    map: F,
    fallback: Vec<String>,
) -> Vec<String>
where
    F: Fn(&AutonomyCalibrationSample) -> String,
{
    let values = samples.iter().map(|sample| map(sample)).collect::<Vec<_>>();
    if values.is_empty() {
        fallback
    } else {
        unique_values(values)
    }
}

fn unique_values<I>(values: I) -> Vec<String>
where
    I: IntoIterator<Item = String>,
{
    values
        .into_iter()
        .filter(|value| !value.trim().is_empty())
        .collect::<BTreeSet<_>>()
        .into_iter()
        .collect()
}

fn false_rate_basis_points(
    samples: &[AutonomyCalibrationSample],
    predicted_decision_class: &str,
) -> u16 {
    false_rate_basis_points_for_samples(
        &samples.iter().collect::<Vec<_>>(),
        predicted_decision_class,
    )
}

fn false_rate_basis_points_for_samples(
    samples: &[&AutonomyCalibrationSample],
    predicted_decision_class: &str,
) -> u16 {
    let predicted = samples
        .iter()
        .filter(|sample| sample.current_policy_decision_class == predicted_decision_class)
        .collect::<Vec<_>>();
    if predicted.is_empty() {
        return 0;
    }
    let incorrect = predicted
        .iter()
        .filter(|sample| sample.expected_decision_class != predicted_decision_class)
        .count();
    rate_basis_points(incorrect, predicted.len())
}

fn alignment_rate_basis_points<I>(values: I) -> u16
where
    I: IntoIterator<Item = bool>,
{
    let values = values.into_iter().collect::<Vec<_>>();
    if values.is_empty() {
        return 0;
    }
    let aligned = values.iter().filter(|value| **value).count();
    rate_basis_points(aligned, values.len())
}

fn rate_basis_points(numerator: usize, denominator: usize) -> u16 {
    if denominator == 0 {
        return 0;
    }
    ((numerator * 10_000) / denominator) as u16
}

fn count_predicted(samples: &[&AutonomyCalibrationSample], decision_class: &str) -> usize {
    samples
        .iter()
        .filter(|sample| sample.current_policy_decision_class == decision_class)
        .count()
}

fn count_expected(samples: &[&AutonomyCalibrationSample], decision_class: &str) -> usize {
    samples
        .iter()
        .filter(|sample| sample.expected_decision_class == decision_class)
        .count()
}

fn matched_signal_id(matched_signal: &str) -> String {
    if matched_signal.starts_with("quality-score:") {
        "overall_quality_score".to_string()
    } else if matched_signal.starts_with("replan-required:") {
        "replan_required".to_string()
    } else if matched_signal.starts_with("operator-action:") {
        "requested_operator_action".to_string()
    } else {
        matched_signal
            .split(':')
            .next()
            .unwrap_or("unknown")
            .to_string()
    }
}

fn increment_decision_count(counts: &mut SignalCounts, decision_class: &str) {
    match decision_class {
        "auto-continue" => counts.auto_continue_count += 1,
        "blocked" => counts.blocked_count += 1,
        _ => counts.review_required_count += 1,
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::approval_gate::ApprovalGatingDecision;
    use crate::continuation_state::ContinuationReceipt;
    use crate::execution_reflection::FIT_LABEL_PARTIAL;
    use crate::execution_plan::{ExecutionExperimentTarget, ExecutionRecipeTarget, PlanAcceptanceCriterion};
    use crate::trajectory_eval::MANUSCRIPT_TRAJECTORY_QUALITY_SHADOW_TUNING_REQUIRED;
    use crate::workstream_context_packet::{
        WorkstreamContextPacket, WorkstreamContextPacketExperimentFlags,
        WorkstreamContextPacketHandoff, WorkstreamContextPacketLastResult,
        WorkstreamContextPacketMemoryHit, WorkstreamContextPacketRetrievalContext,
        WorkstreamContextPacketRetrievalFilters,
    };
    use chrono::Utc;

    fn execution_plan() -> ExecutionPlan {
        ExecutionPlan {
            plan_version: "beagle-execution-plan-v1".to_string(),
            plan_id: "plan-analysis".to_string(),
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
            selected_specialization: "analysis".to_string(),
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
                summary: "cpu loop".to_string(),
                recovery_points: vec!["submitted_job".to_string()],
            }),
            experiment_target: Some(ExecutionExperimentTarget {
                experiment_id: "beagle_exp_002_hrv_aware_vs_blind".to_string(),
                campaign_id: "expedition-002-hrv-aware".to_string(),
                spec_doc: "spec.md".to_string(),
                results_doc: "results.md".to_string(),
                live_batch_id: "batch-1".to_string(),
            }),
            expected_outputs: vec!["results.md".to_string()],
            success_criteria: vec![PlanAcceptanceCriterion {
                criteria_version: "beagle-plan-acceptance-criteria-v1".to_string(),
                criterion_id: "analysis".to_string(),
                description: "analysis".to_string(),
                success_signal: "result".to_string(),
                stop_condition: "operator stop".to_string(),
                operator_visibility_required: true,
            }],
            stop_conditions: vec!["operator stop".to_string()],
            context_packet_ref: "/context".to_string(),
            program_context_packet_ref: Some("/program".to_string()),
            workspace_subagent_route_path: "/route".to_string(),
            workspace_subagent_handoff_path: "/handoff".to_string(),
            tool_launch_path: "/tool".to_string(),
            compiled_context_top_memory_ids: vec!["memory-1".to_string(), "memory-2".to_string()],
            compiled_context_preview: Some("preview".to_string()),
            operator_execution_state: "operator-visible-bounded".to_string(),
            note: "plan".to_string(),
        }
    }

    fn follow_on_plan(plan: &ExecutionPlan) -> FollowOnPlan {
        FollowOnPlan {
            follow_on_plan_version: "beagle-follow-on-plan-v1".to_string(),
            follow_on_plan_id: "follow-on-1".to_string(),
            source_execution_id: "execution-1".to_string(),
            source_plan_id: plan.plan_id.clone(),
            review_inbox_item_id: "review-1".to_string(),
            replan_suggestion_id: "replan-1".to_string(),
            workstream_id: plan.workstream_id.clone(),
            workspace_id: plan.workspace_id.clone(),
            session_id: plan.session_id.clone(),
            review_action: "approved".to_string(),
            follow_on_state: "dispatched".to_string(),
            materialized_at: Utc::now(),
            materialized_by: "beagle-operator".to_string(),
            autonomy_policy_id: None,
            risk_evaluation_id: None,
            approval_gating_decision_id: None,
            approval_gating_decision_class: None,
            approval_gating_decision_path: None,
            execution_plan: plan.clone(),
            note: "follow-on".to_string(),
        }
    }

    fn policy() -> AutonomyPolicy {
        AutonomyPolicy {
            policy_version: "beagle-autonomy-policy-v1".to_string(),
            policy_id: "policy-1".to_string(),
            workstream_id: "beagle-darwin-hpc-governance".to_string(),
            workspace_id: "beagle-cluster-pilot".to_string(),
            session_id: "ws-cluster-workspace-habitat".to_string(),
            source_execution_id: "execution-1".to_string(),
            policy_scope: "follow-on-plan-gating".to_string(),
            policy_role: Some("current-control".to_string()),
            rollout_stage: Some("control-live".to_string()),
            policy_family_scope: vec!["analysis".to_string()],
            guarded_enablement_live: false,
            control_policy_id: None,
            source_threshold_id: None,
            allowed_decision_classes: vec![
                "auto-continue".to_string(),
                "review-required".to_string(),
                "blocked".to_string(),
            ],
            auto_continue_task_families: vec!["analysis".to_string()],
            auto_continue_subagent_ids: vec!["experiments".to_string()],
            auto_continue_retrieval_query_types: vec!["general".to_string()],
            auto_continue_compiler_profile_ids: vec!["b235-budget-analysis".to_string()],
            auto_continue_graphrag_query_modes: vec!["global".to_string()],
            auto_continue_temporal_truth_views: vec!["both".to_string(), "current".to_string()],
            auto_continue_allowed_review_actions: vec!["approved".to_string()],
            auto_continue_allowed_trajectory_qualities: vec!["good".to_string()],
            auto_continue_min_overall_quality_score: 90,
            blocked_max_overall_quality_score: 69,
            blocked_trajectory_qualities: vec!["needs-replan".to_string()],
            blocked_requested_operator_actions: vec![
                "edit-and-reapprove-plan".to_string(),
                "review-stop-and-replan".to_string(),
            ],
            note: "policy".to_string(),
        }
    }

    fn reflection() -> ExecutionReflection {
        ExecutionReflection {
            reflection_version: "beagle-execution-reflection-v1".to_string(),
            reflection_id: "reflection-1".to_string(),
            trajectory_eval_id: "trajectory-1".to_string(),
            execution_id: "execution-1".to_string(),
            plan_id: "plan-analysis".to_string(),
            workstream_id: "beagle-darwin-hpc-governance".to_string(),
            workspace_id: "beagle-cluster-pilot".to_string(),
            session_id: "ws-cluster-workspace-habitat".to_string(),
            task_family: "analysis".to_string(),
            selected_subagent_id: "experiments".to_string(),
            expected_subagent_id: "experiments".to_string(),
            subagent_selection_ok: true,
            compiled_context_sufficient: true,
            compiled_context_reason: "context ok".to_string(),
            acceptance_criteria_met_count: 1,
            acceptance_criteria_total: 1,
            acceptance_criteria_passed: true,
            evaluation_mode: "deterministic".to_string(),
            overall_quality_score: 100,
            operator_followup_action: "review-and-approve-next-plan".to_string(),
            note: "reflection".to_string(),
        }
    }

    fn trajectory() -> TrajectoryEval {
        TrajectoryEval {
            trajectory_eval_version: "beagle-trajectory-eval-v1".to_string(),
            trajectory_eval_id: "trajectory-1".to_string(),
            execution_id: "execution-1".to_string(),
            plan_id: "plan-analysis".to_string(),
            workstream_id: "beagle-darwin-hpc-governance".to_string(),
            workspace_id: "beagle-cluster-pilot".to_string(),
            session_id: "ws-cluster-workspace-habitat".to_string(),
            evaluation_mode: "deterministic".to_string(),
            expected_states: vec!["planned".to_string(), "approved".to_string()],
            observed_states: vec!["planned".to_string(), "approved".to_string()],
            lifecycle_match: true,
            acceptance_criteria_met_count: 1,
            acceptance_criteria_total: 1,
            result_link_count: 8,
            compiled_context_memory_hit_count: 2,
            compiled_context_sufficient: true,
            context_usefulness: "sufficient".to_string(),
            trajectory_quality: "good".to_string(),
            trajectory_score: 100,
            criteria: Vec::new(),
            note: "trajectory".to_string(),
        }
    }

    fn replan() -> ReplanSuggestion {
        ReplanSuggestion {
            suggestion_version: "beagle-replan-suggestion-v1".to_string(),
            suggestion_id: "replan-1".to_string(),
            execution_id: "execution-1".to_string(),
            plan_id: "plan-analysis".to_string(),
            workstream_id: "beagle-darwin-hpc-governance".to_string(),
            workspace_id: "beagle-cluster-pilot".to_string(),
            session_id: "ws-cluster-workspace-habitat".to_string(),
            evaluation_mode: "bounded".to_string(),
            replan_required: false,
            request_operator_review: true,
            request_operator_approval_again: true,
            requested_operator_action: "review-and-approve-follow-on-plan".to_string(),
            suggested_task_family: "analysis".to_string(),
            suggested_subagent_id: "experiments".to_string(),
            suggested_retrieval_query_type: "general".to_string(),
            suggested_compiler_profile_id: "b235-budget-analysis".to_string(),
            suggested_graphrag_query_mode: "global".to_string(),
            suggested_temporal_truth_view: "both".to_string(),
            suggested_recipe_kind: Some("operator_cpu_loop".to_string()),
            suggested_changes: Vec::new(),
            rationale: "rationale".to_string(),
            note: "note".to_string(),
        }
    }

    fn review_decision() -> ReviewDecision {
        ReviewDecision {
            decision_version: "beagle-review-decision-v1".to_string(),
            decision_id: "review-decision-1".to_string(),
            inbox_item_id: "review-1".to_string(),
            execution_id: "execution-1".to_string(),
            plan_id: "plan-analysis".to_string(),
            workstream_id: "beagle-darwin-hpc-governance".to_string(),
            workspace_id: "beagle-cluster-pilot".to_string(),
            session_id: "ws-cluster-workspace-habitat".to_string(),
            decision_action: "approved".to_string(),
            decided_by: "beagle-operator".to_string(),
            decision_note: "approve".to_string(),
            decided_at: Utc::now(),
            operator_visibility_confirmed: true,
            edited_fields: Vec::new(),
            follow_on_plan_materialized: true,
            follow_on_plan_id: Some("follow-on-1".to_string()),
            autonomy_policy_id: Some("policy-1".to_string()),
            risk_evaluation_id: Some("risk-1".to_string()),
            approval_gating_decision_id: Some("gate-1".to_string()),
            approval_gating_decision_class: Some("auto-continue".to_string()),
            auto_continue_eligible: true,
            dispatch_blocked: false,
            note: "decision".to_string(),
        }
    }

    fn approval_gating_decision() -> ApprovalGatingDecision {
        ApprovalGatingDecision {
            decision_version: "beagle-approval-gating-decision-v1".to_string(),
            approval_gating_decision_id: "gate-1".to_string(),
            autonomy_policy_id: "policy-1".to_string(),
            risk_evaluation_id: "risk-1".to_string(),
            source_execution_id: "execution-1".to_string(),
            source_plan_id: "plan-analysis".to_string(),
            review_inbox_item_id: "review-1".to_string(),
            review_decision_id: "review-decision-1".to_string(),
            follow_on_plan_id: "follow-on-1".to_string(),
            workstream_id: "beagle-darwin-hpc-governance".to_string(),
            workspace_id: "beagle-cluster-pilot".to_string(),
            session_id: "ws-cluster-workspace-habitat".to_string(),
            decision_class: "auto-continue".to_string(),
            matched_policy_rule: "low-risk-approved-analysis-lane".to_string(),
            evaluated_at: Utc::now(),
            operator_visibility_confirmed: true,
            continuation_dispatch_permitted: true,
            auto_continuation_enabled: true,
            human_review_required: false,
            blocked: false,
            follow_on_state_after_gating: "auto-continue-ready".to_string(),
            requested_operator_action: "observe-auto-continued-follow-on-plan".to_string(),
            review_inbox_path: "/review".to_string(),
            continuation_dispatch_path: "/dispatch".to_string(),
            note: "gate".to_string(),
        }
    }

    fn continuation_receipt() -> ContinuationReceipt {
        ContinuationReceipt {
            receipt_version: "beagle-continuation-receipt-v1".to_string(),
            continuation_receipt_id: "continuation-receipt-1".to_string(),
            continuation_dispatch_id: "dispatch-1".to_string(),
            workstream_id: "beagle-darwin-hpc-governance".to_string(),
            workspace_id: "beagle-cluster-pilot".to_string(),
            session_id: "ws-cluster-workspace-habitat".to_string(),
            source_execution_id: "execution-1".to_string(),
            source_plan_id: "plan-analysis".to_string(),
            source_receipt_id: Some("receipt-1".to_string()),
            review_decision_id: "review-decision-1".to_string(),
            follow_on_plan_id: "follow-on-1".to_string(),
            recorded_at: Utc::now(),
            review_action: "approved".to_string(),
            chained_receipt_ids: vec!["receipt-1".to_string(), "receipt-2".to_string()],
            handoff_updated: true,
            handoff_ref: Some("/handoff".to_string()),
            next_execution_receipt: crate::ExecutionReceipt {
                receipt_version: "beagle-plan-execution-receipt-v1".to_string(),
                receipt_id: "receipt-2".to_string(),
                execution_id: "execution-2".to_string(),
                plan_id: "plan-2".to_string(),
                workstream_id: "beagle-darwin-hpc-governance".to_string(),
                workspace_id: "beagle-cluster-pilot".to_string(),
                session_id: "ws-cluster-workspace-habitat".to_string(),
                final_state: "succeeded".to_string(),
                recorded_at: Utc::now(),
                selected_subagent_id: "experiments".to_string(),
                recipe_kind: Some("operator_cpu_loop".to_string()),
                experiment_id: Some("beagle_exp_002_hrv_aware_vs_blind".to_string()),
                result_link_count: 8,
                result_links_path: "/result-links".to_string(),
                handoff_updated: true,
                handoff_ref: Some("/handoff".to_string()),
                reflection_id: None,
                trajectory_eval_id: None,
                replan_suggestion_id: None,
                quality_score: Some(100),
                trajectory_quality: Some("good".to_string()),
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
                review_inbox_path: None,
                review_decision_path: None,
                follow_on_plan_path: None,
                autonomy_policy_path: None,
                risk_evaluation_path: None,
                approval_gating_decision_path: None,
                autonomy_calibration_dataset_path: None,
                autonomy_policy_eval_report_path: None,
                escalation_thresholds_path: None,
                shadow_policy_comparison_path: None,
                updated_policy_recommendation_path: None,
                autonomy_policy_current_path: None,
                autonomy_policy_candidate_path: None,
                rollout_metrics_path: None,
                rollout_decision_path: None,
                continuation_dispatch_path: None,
                continuation_receipt_path: None,
                continuation_state_path: None,
                reflection_path: None,
                trajectory_eval_path: None,
                replan_suggestion_path: None,
                operator_execution_state: "operator-visible-bounded".to_string(),
                note: "receipt".to_string(),
            },
            next_execution_result_links: crate::ExecutionResultLinksDocument {
                links_version: "beagle-plan-execution-result-links-v1".to_string(),
                execution_id: "execution-2".to_string(),
                plan_id: "plan-2".to_string(),
                workstream_id: "beagle-darwin-hpc-governance".to_string(),
                workspace_id: "beagle-cluster-pilot".to_string(),
                session_id: "ws-cluster-workspace-habitat".to_string(),
                links: Vec::new(),
                note: "links".to_string(),
            },
            continuation_state_path: "/continuation-state".to_string(),
            note: "continuation".to_string(),
        }
    }

    fn context_packet() -> WorkstreamContextPacket {
        WorkstreamContextPacket {
            packet_version: "beagle-memory-aware-context-packet-v1".to_string(),
            workstream_id: "beagle-darwin-hpc-governance".to_string(),
            workspace_id: "beagle-cluster-pilot".to_string(),
            session_id: "ws-cluster-workspace-habitat".to_string(),
            repo: "agourakis82/beagle".to_string(),
            branch: "feat/darwin-hpc-governance".to_string(),
            governance_state: "canonical".to_string(),
            handoff: WorkstreamContextPacketHandoff {
                handoff_required: true,
                recovery_required: false,
                handoff_present: true,
                last_handoff: Some("handoff".to_string()),
            },
            last_result: WorkstreamContextPacketLastResult {
                available: true,
                reference: None,
                summary: None,
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
                provider: Some("openai".to_string()),
                model: Some("gpt-5.4".to_string()),
                experiment_id: Some("expedition-002".to_string()),
                condition: Some("analysis".to_string()),
            }),
            memory_hits: vec![WorkstreamContextPacketMemoryHit {
                memory_id: Some("memory-1".to_string()),
                source: "codex".to_string(),
                conversation_id: None,
                turn_index: Some(1),
                role: Some("assistant".to_string()),
                snippet: "analysis".to_string(),
                timestamp: None,
                relevance: 1.0,
                tags: vec!["analysis".to_string()],
                domain: Some("darwin-hpc".to_string()),
                physio_snapshot: None,
            }],
            retrieval_context: Some(WorkstreamContextPacketRetrievalContext {
                query_text: "analysis".to_string(),
                query_type: "general".to_string(),
                retrieval_mode: "dense+sparse-hybrid".to_string(),
                dense_backend: "voyage-4-large".to_string(),
                sparse_backend: "local-lexical".to_string(),
                routing_source: "router".to_string(),
                routing_reason: "analysis".to_string(),
                reranking_applied: false,
                reranking_profile_id: None,
                reranker_backend: None,
                reranker_runtime_state: None,
                reranking_latency_ms: None,
                top_k: 4,
                applied_filters: WorkstreamContextPacketRetrievalFilters::default(),
                hit_count: 2,
                top_memory_ids: vec!["memory-1".to_string(), "memory-2".to_string()],
                top_domains: vec!["darwin-hpc".to_string()],
                top_tags: vec!["analysis".to_string()],
                promotion_policy_id: None,
                retention_policy_id: None,
                graphrag_query_mode: Some("local".to_string()),
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
                compiled_context_selected_memory_tiers: vec!["semantic".to_string()],
                compiled_context_source_slices: vec![],
                compiled_context_top_memory_ids: vec!["memory-1".to_string(), "memory-2".to_string()],
                compiled_context_preview: Some("analysis preview".to_string()),
                planner: None,
                execution: None,
                temporal_truth_view: Some("both".to_string()),
                temporal_subject_refs: vec!["claim:1".to_string()],
                temporal_current_memory_ids: vec!["memory-1".to_string()],
                temporal_historical_memory_ids: vec!["memory-0".to_string()],
                temporal_track_count: 1,
                temporal_contradiction_count: 1,
                temporal_contradiction_ids: vec!["contradiction-1".to_string()],
                temporal_preview: Some("truth".to_string()),
                suggested_subagent_id: Some("manuscript".to_string()),
                suggested_work_mode: Some("manuscript".to_string()),
                influence_reason: "analysis inherited defaults".to_string(),
            }),
            recommended_recipe: None,
            bounded_study_baseline: None,
        }
    }

    #[test]
    fn calibration_bundle_reports_conservative_implementation_shadow_gap() {
        let plan = execution_plan();
        let follow_on = follow_on_plan(&plan);
        let bundle = build_autonomy_policy_calibration_bundle(
            &policy(),
            &plan,
            &follow_on,
            &review_decision(),
            &reflection(),
            &trajectory(),
            &replan(),
            Some(&approval_gating_decision()),
            None,
            Some(&continuation_receipt()),
        );

        assert_eq!(bundle.calibration_dataset.sample_count, 4);
        assert!(bundle
            .calibration_dataset
            .decision_classes_evaluated
            .contains(&"auto-continue".to_string()));
        assert!(bundle
            .calibration_dataset
            .decision_classes_evaluated
            .contains(&"review-required".to_string()));
        assert!(bundle
            .calibration_dataset
            .decision_classes_evaluated
            .contains(&"blocked".to_string()));
        assert_eq!(bundle.policy_eval_report.policy_posture, "too-conservative");
        assert_eq!(
            bundle.policy_eval_report.false_review_required_rate_basis_points,
            5000
        );
        assert_eq!(
            bundle
                .shadow_policy_comparison
                .improved_alignment_count,
            1
        );
        assert_eq!(
            bundle.updated_policy_recommendation.recommended_action,
            "stage-shadow-threshold-update"
        );
    }

    #[test]
    fn implementation_canary_bundle_activates_only_implementation() {
        let plan = execution_plan();
        let follow_on = follow_on_plan(&plan);
        let calibration_bundle = build_autonomy_policy_calibration_bundle(
            &policy(),
            &plan,
            &follow_on,
            &review_decision(),
            &reflection(),
            &trajectory(),
            &replan(),
            Some(&approval_gating_decision()),
            None,
            Some(&continuation_receipt()),
        );
        let rollout_bundle = build_guarded_policy_rollout_bundle(&policy(), &calibration_bundle);
        let canary_bundle =
            build_implementation_canary_autonomy_bundle(&policy(), &rollout_bundle);

        assert_eq!(
            canary_bundle
                .autonomy_policy_control
                .policy_role
                .as_deref(),
            Some("control-live")
        );
        assert_eq!(
            canary_bundle
                .autonomy_policy_canary
                .policy_role
                .as_deref(),
            Some("implementation-canary-live")
        );
        assert_eq!(
            canary_bundle.autonomy_policy_canary.auto_continue_task_families,
            vec!["implementation".to_string()]
        );
        assert_eq!(
            canary_bundle.canary_rollout_metrics.canary_stage,
            "implementation-family-live-canary"
        );
        assert!(canary_bundle.canary_rollout_metrics.implementation_canary_enabled);
        assert!(canary_bundle.canary_rollout_metrics.analysis_control_retained);
        assert!(canary_bundle.canary_rollout_metrics.manuscript_control_retained);
        assert!(!canary_bundle.canary_rollback_decision.rollback_required);
        assert!(canary_bundle.canary_rollback_decision.implementation_canary_live);
    }

    #[test]
    fn analysis_shadow_bundle_keeps_analysis_in_shadow_and_retains_live_canary() {
        let plan = execution_plan();
        let follow_on = follow_on_plan(&plan);
        let calibration_bundle = build_autonomy_policy_calibration_bundle(
            &policy(),
            &plan,
            &follow_on,
            &review_decision(),
            &reflection(),
            &trajectory(),
            &replan(),
            Some(&approval_gating_decision()),
            None,
            Some(&continuation_receipt()),
        );
        let rollout_bundle = build_guarded_policy_rollout_bundle(&policy(), &calibration_bundle);
        let canary_bundle =
            build_implementation_canary_autonomy_bundle(&policy(), &rollout_bundle);
        let analysis_bundle = build_analysis_shadow_calibration_bundle(
            &rollout_bundle,
            &calibration_bundle,
            &canary_bundle,
        );

        assert_eq!(
            analysis_bundle
                .autonomy_policy_control
                .policy_role
                .as_deref(),
            Some("control-live")
        );
        assert_eq!(
            analysis_bundle
                .autonomy_policy_analysis_candidate
                .policy_role
                .as_deref(),
            Some("analysis-shadow-candidate")
        );
        assert_eq!(
            analysis_bundle
                .analysis_shadow_comparison
                .recommendation_for_analysis,
            "keep-shadow"
        );
        assert_eq!(
            analysis_bundle
                .analysis_rollout_metrics
                .recommendation_for_analysis,
            "keep-shadow"
        );
        assert_eq!(
            analysis_bundle.analysis_rollout_decision.decision_output,
            "keep-shadow"
        );
        assert!(analysis_bundle.analysis_rollout_metrics.implementation_canary_retained);
        assert!(analysis_bundle.analysis_rollout_metrics.manuscript_control_retained);
        assert!(
            analysis_bundle
                .analysis_rollout_decision
                .implementation_canary_retained
        );
        assert!(
            analysis_bundle
                .analysis_rollout_decision
                .manuscript_control_retained
        );
        assert!(!analysis_bundle.analysis_rollout_decision.rollback_required);
    }

    #[test]
    fn analysis_shadow_soak_bundle_requires_more_samples_before_promotion() {
        let plan = execution_plan();
        let follow_on = follow_on_plan(&plan);
        let calibration_bundle = build_autonomy_policy_calibration_bundle(
            &policy(),
            &plan,
            &follow_on,
            &review_decision(),
            &reflection(),
            &trajectory(),
            &replan(),
            Some(&approval_gating_decision()),
            None,
            Some(&continuation_receipt()),
        );
        let rollout_bundle = build_guarded_policy_rollout_bundle(&policy(), &calibration_bundle);
        let canary_bundle =
            build_implementation_canary_autonomy_bundle(&policy(), &rollout_bundle);
        let analysis_bundle = build_analysis_shadow_calibration_bundle(
            &rollout_bundle,
            &calibration_bundle,
            &canary_bundle,
        );
        let soak_bundle = build_analysis_shadow_soak_bundle(
            &calibration_bundle,
            &analysis_bundle,
            None,
        );

        assert_eq!(
            soak_bundle.analysis_shadow_history.soak_version,
            ANALYSIS_SHADOW_SOAK_VERSION
        );
        assert_eq!(
            soak_bundle.analysis_shadow_history.shadow_sample_count,
            2
        );
        assert!(soak_bundle.analysis_shadow_history.implementation_canary_retained);
        assert!(soak_bundle.analysis_shadow_history.manuscript_control_retained);
        assert_eq!(
            soak_bundle
                .analysis_soak_metrics
                .promotion_gate_decision_preview,
            "keep-shadow"
        );
        assert_eq!(
            soak_bundle.analysis_promotion_gate.promotion_gate_decision,
            "keep-shadow"
        );
        assert!(
            soak_bundle
                .analysis_promotion_gate
                .hold_or_rollback_required
        );
        assert!(!soak_bundle.analysis_promotion_gate.promotion_criteria_met);
    }

    #[test]
    fn analysis_sample_accumulation_bundle_rechecks_and_stages_canary_when_threshold_is_met() {
        let plan = execution_plan();
        let follow_on = follow_on_plan(&plan);
        let calibration_bundle = build_autonomy_policy_calibration_bundle(
            &policy(),
            &plan,
            &follow_on,
            &review_decision(),
            &reflection(),
            &trajectory(),
            &replan(),
            Some(&approval_gating_decision()),
            None,
            Some(&continuation_receipt()),
        );
        let rollout_bundle = build_guarded_policy_rollout_bundle(&policy(), &calibration_bundle);
        let canary_bundle =
            build_implementation_canary_autonomy_bundle(&policy(), &rollout_bundle);
        let analysis_bundle = build_analysis_shadow_calibration_bundle(
            &rollout_bundle,
            &calibration_bundle,
            &canary_bundle,
        );
        let soak_bundle = build_analysis_shadow_soak_bundle(
            &calibration_bundle,
            &analysis_bundle,
            None,
        );
        let accumulation_bundle = build_analysis_sample_accumulation_bundle(
            &calibration_bundle,
            &analysis_bundle,
            &soak_bundle.analysis_shadow_history,
        );

        assert_eq!(
            accumulation_bundle.analysis_shadow_history.soak_version,
            ANALYSIS_SAMPLE_ACCUMULATION_VERSION
        );
        assert_eq!(
            accumulation_bundle
                .analysis_shadow_history
                .prior_shadow_sample_count,
            2
        );
        assert_eq!(
            accumulation_bundle
                .analysis_shadow_history
                .additional_shadow_sample_count,
            2
        );
        assert_eq!(
            accumulation_bundle.analysis_shadow_history.shadow_sample_count,
            4
        );
        assert_eq!(
            accumulation_bundle
                .analysis_soak_metrics
                .promotion_gate_decision_preview,
            "stage-analysis-canary"
        );
        assert_eq!(
            accumulation_bundle
                .analysis_promotion_gate
                .gate_version,
            ANALYSIS_PROMOTION_GATE_RECHECK_VERSION
        );
        assert_eq!(
            accumulation_bundle
                .analysis_promotion_gate
                .promotion_gate_decision,
            "stage-analysis-canary"
        );
        assert!(
            accumulation_bundle
                .analysis_promotion_gate
                .promotion_criteria_met
        );
        assert_eq!(
            accumulation_bundle
                .analysis_promotion_gate
                .additional_shadow_sample_count,
            2
        );
    }

    #[test]
    fn analysis_canary_activation_bundle_keeps_implementation_and_promotes_analysis() {
        let plan = execution_plan();
        let follow_on = follow_on_plan(&plan);
        let calibration_bundle = build_autonomy_policy_calibration_bundle(
            &policy(),
            &plan,
            &follow_on,
            &review_decision(),
            &reflection(),
            &trajectory(),
            &replan(),
            Some(&approval_gating_decision()),
            None,
            Some(&continuation_receipt()),
        );
        let rollout_bundle = build_guarded_policy_rollout_bundle(&policy(), &calibration_bundle);
        let implementation_bundle =
            build_implementation_canary_autonomy_bundle(&policy(), &rollout_bundle);
        let analysis_bundle = build_analysis_shadow_calibration_bundle(
            &rollout_bundle,
            &calibration_bundle,
            &implementation_bundle,
        );
        let accumulation_bundle = build_analysis_sample_accumulation_bundle(
            &calibration_bundle,
            &analysis_bundle,
            &build_analysis_shadow_soak_bundle(&calibration_bundle, &analysis_bundle, None)
                .analysis_shadow_history,
        );
        let analysis_canary_bundle = build_analysis_canary_activation_bundle(
            &implementation_bundle,
            &analysis_bundle,
            &accumulation_bundle,
        );

        assert_eq!(
            analysis_canary_bundle
                .autonomy_policy_control
                .policy_family_scope,
            vec!["manuscript".to_string()]
        );
        assert_eq!(
            analysis_canary_bundle
                .autonomy_policy_implementation_canary
                .policy_role
                .as_deref(),
            Some("implementation-canary-live")
        );
        assert_eq!(
            analysis_canary_bundle
                .autonomy_policy_analysis_canary
                .policy_role
                .as_deref(),
            Some("analysis-canary-live")
        );
        assert!(
            analysis_canary_bundle
                .autonomy_policy_analysis_canary
                .guarded_enablement_live
        );
        assert_eq!(
            analysis_canary_bundle.analysis_canary_metrics.canary_stage,
            ANALYSIS_CANARY_STAGE_STATE
        );
        assert!(
            analysis_canary_bundle
                .analysis_canary_metrics
                .implementation_canary_retained
        );
        assert!(
            analysis_canary_bundle
                .analysis_canary_metrics
                .analysis_canary_live
        );
        assert!(
            !analysis_canary_bundle
                .analysis_canary_rollback_decision
                .rollback_required
        );
    }

    #[test]
    fn manuscript_sample_accumulation_bundle_expands_history_but_keeps_shadow_without_alignment() {
        let plan = execution_plan();
        let follow_on = follow_on_plan(&plan);
        let calibration_bundle = build_autonomy_policy_calibration_bundle(
            &policy(),
            &plan,
            &follow_on,
            &review_decision(),
            &reflection(),
            &trajectory(),
            &replan(),
            Some(&approval_gating_decision()),
            None,
            Some(&continuation_receipt()),
        );
        let rollout_bundle = build_guarded_policy_rollout_bundle(&policy(), &calibration_bundle);
        let implementation_bundle =
            build_implementation_canary_autonomy_bundle(&policy(), &rollout_bundle);
        let analysis_bundle = build_analysis_shadow_calibration_bundle(
            &rollout_bundle,
            &calibration_bundle,
            &implementation_bundle,
        );
        let initial_soak =
            build_analysis_shadow_soak_bundle(&calibration_bundle, &analysis_bundle, None);
        let analysis_accumulation = build_analysis_sample_accumulation_bundle(
            &calibration_bundle,
            &analysis_bundle,
            &initial_soak.analysis_shadow_history,
        );
        let analysis_canary_bundle = build_analysis_canary_activation_bundle(
            &implementation_bundle,
            &analysis_bundle,
            &analysis_accumulation,
        );
        let manuscript_bundle = build_manuscript_shadow_calibration_bundle(
            &rollout_bundle,
            &calibration_bundle,
            &analysis_canary_bundle,
        );
        let accumulation_bundle = build_manuscript_sample_accumulation_bundle(
            &calibration_bundle,
            &manuscript_bundle,
            None,
        );

        assert_eq!(
            accumulation_bundle
                .manuscript_shadow_history
                .accumulation_version,
            MANUSCRIPT_SAMPLE_ACCUMULATION_VERSION
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
            MANUSCRIPT_PROMOTION_MIN_SHADOW_SAMPLES
        );
        assert_eq!(
            accumulation_bundle
                .manuscript_soak_metrics
                .promotion_gate_decision_preview,
            "keep-shadow"
        );
        assert_eq!(
            accumulation_bundle
                .manuscript_promotion_gate
                .gate_version,
            MANUSCRIPT_PROMOTION_GATE_RECHECK_VERSION
        );
        assert_eq!(
            accumulation_bundle
                .manuscript_promotion_gate
                .promotion_gate_decision,
            "keep-shadow"
        );
        assert!(
            !accumulation_bundle
                .manuscript_promotion_gate
                .promotion_criteria_met
        );
        assert_eq!(
            accumulation_bundle
                .manuscript_soak_metrics
                .alignment_with_operator_decision_basis_points,
            0
        );
        assert_eq!(
            accumulation_bundle
                .manuscript_soak_metrics
                .alignment_with_execution_outcome_basis_points,
            0
        );
    }

    #[test]
    fn manuscript_alignment_labeling_surfaces_insufficient_evidence_and_enriches_gate() {
        let plan = execution_plan();
        let follow_on = follow_on_plan(&plan);
        let review_decision = review_decision();
        let reflection = reflection();
        let calibration_bundle = build_autonomy_policy_calibration_bundle(
            &policy(),
            &plan,
            &follow_on,
            &review_decision,
            &reflection,
            &trajectory(),
            &replan(),
            Some(&approval_gating_decision()),
            None,
            Some(&continuation_receipt()),
        );
        let rollout_bundle = build_guarded_policy_rollout_bundle(&policy(), &calibration_bundle);
        let implementation_bundle =
            build_implementation_canary_autonomy_bundle(&policy(), &rollout_bundle);
        let analysis_bundle = build_analysis_shadow_calibration_bundle(
            &rollout_bundle,
            &calibration_bundle,
            &implementation_bundle,
        );
        let initial_soak =
            build_analysis_shadow_soak_bundle(&calibration_bundle, &analysis_bundle, None);
        let analysis_accumulation = build_analysis_sample_accumulation_bundle(
            &calibration_bundle,
            &analysis_bundle,
            &initial_soak.analysis_shadow_history,
        );
        let analysis_canary_bundle = build_analysis_canary_activation_bundle(
            &implementation_bundle,
            &analysis_bundle,
            &analysis_accumulation,
        );
        let manuscript_bundle = build_manuscript_shadow_calibration_bundle(
            &rollout_bundle,
            &calibration_bundle,
            &analysis_canary_bundle,
        );
        let accumulation_bundle = build_manuscript_sample_accumulation_bundle(
            &calibration_bundle,
            &manuscript_bundle,
            None,
        );
        let alignment_bundle = build_manuscript_alignment_labeling_bundle(
            &accumulation_bundle,
            Some(&review_decision),
            Some(&reflection),
        );

        assert_eq!(
            alignment_bundle
                .manuscript_alignment_labels
                .labels_version,
            MANUSCRIPT_ALIGNMENT_LABEL_VERSION
        );
        assert_eq!(
            alignment_bundle
                .manuscript_alignment_labels
                .operator_alignment_labeled_count,
            0
        );
        assert_eq!(
            alignment_bundle
                .manuscript_promotion_evidence
                .evidence_version,
            MANUSCRIPT_PROMOTION_EVIDENCE_VERSION
        );
        assert_eq!(
            alignment_bundle
                .manuscript_promotion_evidence
                .operator_alignment_label_coverage_basis_points,
            0
        );
        assert_eq!(
            alignment_bundle
                .manuscript_promotion_evidence
                .promotion_readiness_label,
            "keep-shadow"
        );
        assert_eq!(
            alignment_bundle
                .manuscript_promotion_gate
                .promotion_gate_decision,
            "keep-shadow"
        );
        assert!(
            !alignment_bundle
                .manuscript_promotion_gate
                .promotion_evidence_sufficient
        );
        assert_eq!(
            alignment_bundle
                .manuscript_promotion_gate
                .promotion_readiness_label,
            "keep-shadow"
        );
        assert_eq!(
            alignment_bundle
                .manuscript_promotion_gate
                .review_quality_label,
            REVIEW_QUALITY_LABEL_OPERATOR_READY
        );
    }

    #[test]
    fn manuscript_quality_uplift_recommends_shadow_retest_on_dedicated_editorial_lane() {
        let plan = execution_plan();
        let follow_on = follow_on_plan(&plan);
        let calibration_bundle = build_autonomy_policy_calibration_bundle(
            &policy(),
            &plan,
            &follow_on,
            &review_decision(),
            &reflection(),
            &trajectory(),
            &replan(),
            Some(&approval_gating_decision()),
            None,
            Some(&continuation_receipt()),
        );
        let rollout_bundle = build_guarded_policy_rollout_bundle(&policy(), &calibration_bundle);
        let implementation_bundle =
            build_implementation_canary_autonomy_bundle(&policy(), &rollout_bundle);
        let analysis_bundle = build_analysis_shadow_calibration_bundle(
            &rollout_bundle,
            &calibration_bundle,
            &implementation_bundle,
        );
        let initial_soak =
            build_analysis_shadow_soak_bundle(&calibration_bundle, &analysis_bundle, None);
        let analysis_accumulation = build_analysis_sample_accumulation_bundle(
            &calibration_bundle,
            &analysis_bundle,
            &initial_soak.analysis_shadow_history,
        );
        let analysis_canary_bundle = build_analysis_canary_activation_bundle(
            &implementation_bundle,
            &analysis_bundle,
            &analysis_accumulation,
        );
        let manuscript_bundle = build_manuscript_shadow_calibration_bundle(
            &rollout_bundle,
            &calibration_bundle,
            &analysis_canary_bundle,
        );
        let alignment_signal_bundle = build_manuscript_alignment_signal_bundle(
            &build_manuscript_sample_accumulation_bundle(
                &calibration_bundle,
                &manuscript_bundle,
                None,
            ),
            Some(&review_decision()),
            Some(&reflection()),
            Some(&follow_on),
        );

        let bundle = build_manuscript_quality_uplift_bundle(
            &alignment_signal_bundle,
            &plan,
            &trajectory(),
            &reflection(),
            &context_packet(),
        );

        assert_eq!(
            bundle.manuscript_trajectory_quality.trajectory_quality,
            MANUSCRIPT_TRAJECTORY_QUALITY_SHADOW_TUNING_REQUIRED
        );
        assert!(bundle.manuscript_trajectory_quality.quality_uplift_required);
        assert_eq!(
            bundle.manuscript_context_adequacy.context_sufficiency,
            "adequate-but-misaligned"
        );
        assert_eq!(
            bundle.manuscript_context_adequacy.compiler_profile_fit,
            FIT_LABEL_POOR
        );
        assert_eq!(
            bundle.manuscript_context_adequacy.task_profile_fit,
            FIT_LABEL_PARTIAL
        );
        assert_eq!(
            bundle.manuscript_context_adequacy.subagent_fit,
            FIT_LABEL_PARTIAL
        );
        assert_eq!(
            bundle
                .manuscript_tuning_recommendation
                .current_promotion_gate_decision,
            "keep-shadow"
        );
        assert!(bundle.manuscript_tuning_recommendation.manuscript_must_remain_shadow);
        assert_eq!(
            bundle
                .manuscript_tuning_recommendation
                .candidate_policy_mode,
            "shadow-retest"
        );
        assert_eq!(
            bundle
                .manuscript_tuning_recommendation
                .candidate_task_family,
            "manuscript"
        );
        assert_eq!(
            bundle
                .manuscript_tuning_recommendation
                .candidate_selected_subagent_id,
            "manuscript"
        );
        assert_eq!(
            bundle
                .manuscript_tuning_recommendation
                .candidate_compiler_profile_id,
            "b235-budget-manuscript"
        );
        assert_eq!(
            bundle
                .manuscript_tuning_recommendation
                .candidate_graphrag_query_mode,
            "global"
        );
    }
}
