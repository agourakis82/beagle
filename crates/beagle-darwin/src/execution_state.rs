use chrono::{DateTime, Utc};
use serde::{Deserialize, Serialize};

pub const PLAN_APPROVAL_VERSION: &str = "beagle-plan-approval-v1";
pub const EXECUTION_STATE_VERSION: &str = "beagle-plan-execution-state-v1";
pub const EXECUTION_RECEIPT_VERSION: &str = "beagle-plan-execution-receipt-v1";
pub const EXECUTION_RESULT_LINKS_VERSION: &str = "beagle-plan-execution-result-links-v1";
pub const EXECUTION_REFLECTION_VERSION: &str = "beagle-execution-reflection-v1";
pub const TRAJECTORY_EVAL_VERSION: &str = "beagle-trajectory-eval-v1";
pub const REPLAN_SUGGESTION_VERSION: &str = "beagle-replan-suggestion-v1";
pub const REVIEW_INBOX_ITEM_VERSION: &str = "beagle-review-inbox-item-v1";
pub const REVIEW_DECISION_VERSION: &str = "beagle-review-decision-v1";
pub const FOLLOW_ON_PLAN_VERSION: &str = "beagle-follow-on-plan-v1";
pub const AUTONOMY_POLICY_VERSION: &str = "beagle-autonomy-policy-v1";
pub const RISK_EVALUATION_VERSION: &str = "beagle-risk-evaluation-v1";
pub const APPROVAL_GATING_DECISION_VERSION: &str = "beagle-approval-gating-decision-v1";
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

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
pub struct PlanApproval {
    pub approval_version: String,
    pub approval_id: String,
    pub plan_id: String,
    pub workstream_id: String,
    pub workspace_id: String,
    pub session_id: String,
    pub approved_by: String,
    pub approval_note: String,
    pub approval_state: String,
    pub operator_visibility_confirmed: bool,
    pub approved_at: DateTime<Utc>,
    pub operator_execution_state: String,
    pub note: String,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
pub struct ExecutionStateTransition {
    pub state: String,
    pub transitioned_at: DateTime<Utc>,
    pub note: String,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
pub struct PlanExecutionStatusSummary {
    pub state_version: String,
    pub execution_id: String,
    pub plan_id: String,
    pub current_state: String,
    pub selected_subagent_id: String,
    pub retrieval_query_type: String,
    pub compiler_profile_id: String,
    pub graphrag_query_mode: String,
    pub temporal_truth_view: String,
    pub approved_at: DateTime<Utc>,
    #[serde(default)]
    pub started_at: Option<DateTime<Utc>>,
    #[serde(default)]
    pub finished_at: Option<DateTime<Utc>>,
    #[serde(default)]
    pub latest_receipt_id: Option<String>,
    #[serde(default)]
    pub recipe_kind: Option<String>,
    #[serde(default)]
    pub experiment_id: Option<String>,
    pub result_link_count: usize,
    pub handoff_updated: bool,
    #[serde(default)]
    pub handoff_ref: Option<String>,
    #[serde(default)]
    pub reflection_available: bool,
    #[serde(default)]
    pub latest_reflection_id: Option<String>,
    #[serde(default)]
    pub latest_trajectory_eval_id: Option<String>,
    #[serde(default)]
    pub latest_replan_suggestion_id: Option<String>,
    #[serde(default)]
    pub latest_quality_score: Option<u8>,
    #[serde(default)]
    pub latest_trajectory_quality: Option<String>,
    #[serde(default)]
    pub replan_required: bool,
    #[serde(default)]
    pub operator_followup_action: Option<String>,
    #[serde(default)]
    pub review_requested: bool,
    #[serde(default)]
    pub review_inbox_state: Option<String>,
    #[serde(default)]
    pub latest_review_inbox_item_id: Option<String>,
    #[serde(default)]
    pub latest_review_decision_id: Option<String>,
    #[serde(default)]
    pub latest_review_decision_action: Option<String>,
    #[serde(default)]
    pub latest_follow_on_plan_id: Option<String>,
    #[serde(default)]
    pub follow_on_plan_available: bool,
    #[serde(default)]
    pub latest_autonomy_policy_id: Option<String>,
    #[serde(default)]
    pub latest_risk_evaluation_id: Option<String>,
    #[serde(default)]
    pub latest_approval_gating_decision_id: Option<String>,
    #[serde(default)]
    pub latest_autonomy_calibration_dataset_id: Option<String>,
    #[serde(default)]
    pub latest_autonomy_policy_eval_report_id: Option<String>,
    #[serde(default)]
    pub latest_escalation_thresholds_id: Option<String>,
    #[serde(default)]
    pub latest_shadow_policy_comparison_id: Option<String>,
    #[serde(default)]
    pub latest_updated_policy_recommendation_id: Option<String>,
    #[serde(default)]
    pub latest_autonomy_policy_current_id: Option<String>,
    #[serde(default)]
    pub latest_autonomy_policy_candidate_id: Option<String>,
    #[serde(default)]
    pub latest_rollout_metrics_id: Option<String>,
    #[serde(default)]
    pub latest_guarded_rollout_decision_id: Option<String>,
    #[serde(default)]
    pub approval_gating_decision_class: Option<String>,
    #[serde(default)]
    pub approval_gating_risk_level: Option<String>,
    #[serde(default)]
    pub approval_gating_dispatch_ready: bool,
    #[serde(default)]
    pub approval_gating_blocked: bool,
    #[serde(default)]
    pub continuation_dispatched: bool,
    #[serde(default)]
    pub latest_continuation_dispatch_id: Option<String>,
    #[serde(default)]
    pub latest_continuation_receipt_id: Option<String>,
    #[serde(default)]
    pub continuation_current_state: Option<String>,
    #[serde(default)]
    pub continuation_source_execution_id: Option<String>,
    #[serde(default)]
    pub continuation_next_execution_id: Option<String>,
    #[serde(default)]
    pub continuation_next_plan_id: Option<String>,
    #[serde(default)]
    pub continuation_review_action: Option<String>,
    #[serde(default)]
    pub autonomy_policy_calibration_status: Option<String>,
    #[serde(default)]
    pub autonomy_policy_rollout_status: Option<String>,
    #[serde(default)]
    pub review_inbox_path: Option<String>,
    #[serde(default)]
    pub review_decision_path: Option<String>,
    #[serde(default)]
    pub follow_on_plan_path: Option<String>,
    #[serde(default)]
    pub autonomy_policy_path: Option<String>,
    #[serde(default)]
    pub risk_evaluation_path: Option<String>,
    #[serde(default)]
    pub approval_gating_decision_path: Option<String>,
    #[serde(default)]
    pub autonomy_calibration_dataset_path: Option<String>,
    #[serde(default)]
    pub autonomy_policy_eval_report_path: Option<String>,
    #[serde(default)]
    pub escalation_thresholds_path: Option<String>,
    #[serde(default)]
    pub shadow_policy_comparison_path: Option<String>,
    #[serde(default)]
    pub updated_policy_recommendation_path: Option<String>,
    #[serde(default)]
    pub autonomy_policy_current_path: Option<String>,
    #[serde(default)]
    pub autonomy_policy_candidate_path: Option<String>,
    #[serde(default)]
    pub rollout_metrics_path: Option<String>,
    #[serde(default)]
    pub rollout_decision_path: Option<String>,
    #[serde(default)]
    pub continuation_dispatch_path: Option<String>,
    #[serde(default)]
    pub continuation_receipt_path: Option<String>,
    #[serde(default)]
    pub continuation_state_path: Option<String>,
    #[serde(default)]
    pub reflection_path: Option<String>,
    #[serde(default)]
    pub trajectory_eval_path: Option<String>,
    #[serde(default)]
    pub replan_suggestion_path: Option<String>,
    pub execution_state_path: String,
    pub execution_receipt_path: String,
    pub execution_result_links_path: String,
    pub operator_execution_state: String,
    pub note: String,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
pub struct ExecutionStatePlane {
    pub state_version: String,
    pub execution_id: String,
    pub planner_policy_id: String,
    pub plan_id: String,
    pub workstream_id: String,
    pub workspace_id: String,
    pub session_id: String,
    #[serde(default)]
    pub program_id: Option<String>,
    #[serde(default)]
    pub campaign_id: Option<String>,
    pub task_family: String,
    pub tool_id: String,
    pub work_mode: String,
    pub current_state: String,
    pub selected_subagent_id: String,
    pub retrieval_query_type: String,
    pub dense_backend: String,
    pub sparse_backend: String,
    pub compiler_profile_id: String,
    pub graphrag_query_mode: String,
    pub temporal_truth_view: String,
    pub approved_by: String,
    pub approved_at: DateTime<Utc>,
    #[serde(default)]
    pub started_at: Option<DateTime<Utc>>,
    #[serde(default)]
    pub finished_at: Option<DateTime<Utc>>,
    #[serde(default)]
    pub stop_requested_at: Option<DateTime<Utc>>,
    #[serde(default)]
    pub stop_reason: Option<String>,
    #[serde(default)]
    pub latest_receipt_id: Option<String>,
    #[serde(default)]
    pub latest_reflection_id: Option<String>,
    #[serde(default)]
    pub latest_trajectory_eval_id: Option<String>,
    #[serde(default)]
    pub latest_replan_suggestion_id: Option<String>,
    #[serde(default)]
    pub recipe_id: Option<String>,
    #[serde(default)]
    pub recipe_kind: Option<String>,
    #[serde(default)]
    pub experiment_id: Option<String>,
    #[serde(default)]
    pub context_packet_ref: Option<String>,
    #[serde(default)]
    pub program_context_packet_ref: Option<String>,
    pub tool_launch_path: String,
    pub workspace_subagent_route_path: String,
    pub workspace_subagent_handoff_path: String,
    #[serde(default)]
    pub reflection_path: Option<String>,
    #[serde(default)]
    pub trajectory_eval_path: Option<String>,
    #[serde(default)]
    pub replan_suggestion_path: Option<String>,
    pub execution_state_path: String,
    pub execution_receipt_path: String,
    pub execution_result_links_path: String,
    pub state_transitions: Vec<ExecutionStateTransition>,
    #[serde(default)]
    pub latest_quality_score: Option<u8>,
    #[serde(default)]
    pub latest_trajectory_quality: Option<String>,
    #[serde(default)]
    pub replan_required: bool,
    #[serde(default)]
    pub operator_followup_action: Option<String>,
    #[serde(default)]
    pub review_requested: bool,
    #[serde(default)]
    pub review_inbox_state: Option<String>,
    #[serde(default)]
    pub latest_review_inbox_item_id: Option<String>,
    #[serde(default)]
    pub latest_review_decision_id: Option<String>,
    #[serde(default)]
    pub latest_review_decision_action: Option<String>,
    #[serde(default)]
    pub latest_follow_on_plan_id: Option<String>,
    #[serde(default)]
    pub follow_on_plan_available: bool,
    #[serde(default)]
    pub latest_autonomy_policy_id: Option<String>,
    #[serde(default)]
    pub latest_risk_evaluation_id: Option<String>,
    #[serde(default)]
    pub latest_approval_gating_decision_id: Option<String>,
    #[serde(default)]
    pub latest_autonomy_calibration_dataset_id: Option<String>,
    #[serde(default)]
    pub latest_autonomy_policy_eval_report_id: Option<String>,
    #[serde(default)]
    pub latest_escalation_thresholds_id: Option<String>,
    #[serde(default)]
    pub latest_shadow_policy_comparison_id: Option<String>,
    #[serde(default)]
    pub latest_updated_policy_recommendation_id: Option<String>,
    #[serde(default)]
    pub latest_autonomy_policy_current_id: Option<String>,
    #[serde(default)]
    pub latest_autonomy_policy_candidate_id: Option<String>,
    #[serde(default)]
    pub latest_rollout_metrics_id: Option<String>,
    #[serde(default)]
    pub latest_guarded_rollout_decision_id: Option<String>,
    #[serde(default)]
    pub approval_gating_decision_class: Option<String>,
    #[serde(default)]
    pub approval_gating_risk_level: Option<String>,
    #[serde(default)]
    pub approval_gating_dispatch_ready: bool,
    #[serde(default)]
    pub approval_gating_blocked: bool,
    #[serde(default)]
    pub continuation_dispatched: bool,
    #[serde(default)]
    pub latest_continuation_dispatch_id: Option<String>,
    #[serde(default)]
    pub latest_continuation_receipt_id: Option<String>,
    #[serde(default)]
    pub continuation_current_state: Option<String>,
    #[serde(default)]
    pub continuation_source_execution_id: Option<String>,
    #[serde(default)]
    pub continuation_next_execution_id: Option<String>,
    #[serde(default)]
    pub continuation_next_plan_id: Option<String>,
    #[serde(default)]
    pub continuation_review_action: Option<String>,
    #[serde(default)]
    pub autonomy_policy_calibration_status: Option<String>,
    #[serde(default)]
    pub autonomy_policy_rollout_status: Option<String>,
    #[serde(default)]
    pub review_inbox_path: Option<String>,
    #[serde(default)]
    pub review_decision_path: Option<String>,
    #[serde(default)]
    pub follow_on_plan_path: Option<String>,
    #[serde(default)]
    pub autonomy_policy_path: Option<String>,
    #[serde(default)]
    pub risk_evaluation_path: Option<String>,
    #[serde(default)]
    pub approval_gating_decision_path: Option<String>,
    #[serde(default)]
    pub autonomy_calibration_dataset_path: Option<String>,
    #[serde(default)]
    pub autonomy_policy_eval_report_path: Option<String>,
    #[serde(default)]
    pub escalation_thresholds_path: Option<String>,
    #[serde(default)]
    pub shadow_policy_comparison_path: Option<String>,
    #[serde(default)]
    pub updated_policy_recommendation_path: Option<String>,
    #[serde(default)]
    pub autonomy_policy_current_path: Option<String>,
    #[serde(default)]
    pub autonomy_policy_candidate_path: Option<String>,
    #[serde(default)]
    pub rollout_metrics_path: Option<String>,
    #[serde(default)]
    pub rollout_decision_path: Option<String>,
    #[serde(default)]
    pub continuation_dispatch_path: Option<String>,
    #[serde(default)]
    pub continuation_receipt_path: Option<String>,
    #[serde(default)]
    pub continuation_state_path: Option<String>,
    pub operator_execution_state: String,
    pub note: String,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
pub struct ExecutionResultLink {
    pub link_id: String,
    pub link_kind: String,
    pub path: String,
    pub summary: String,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
pub struct ExecutionResultLinksDocument {
    pub links_version: String,
    pub execution_id: String,
    pub plan_id: String,
    pub workstream_id: String,
    pub workspace_id: String,
    pub session_id: String,
    pub links: Vec<ExecutionResultLink>,
    pub note: String,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
pub struct ExecutionReceipt {
    pub receipt_version: String,
    pub receipt_id: String,
    pub execution_id: String,
    pub plan_id: String,
    pub workstream_id: String,
    pub workspace_id: String,
    pub session_id: String,
    pub final_state: String,
    pub recorded_at: DateTime<Utc>,
    pub selected_subagent_id: String,
    #[serde(default)]
    pub recipe_kind: Option<String>,
    #[serde(default)]
    pub experiment_id: Option<String>,
    pub result_link_count: usize,
    pub result_links_path: String,
    pub handoff_updated: bool,
    #[serde(default)]
    pub handoff_ref: Option<String>,
    #[serde(default)]
    pub reflection_id: Option<String>,
    #[serde(default)]
    pub trajectory_eval_id: Option<String>,
    #[serde(default)]
    pub replan_suggestion_id: Option<String>,
    #[serde(default)]
    pub quality_score: Option<u8>,
    #[serde(default)]
    pub trajectory_quality: Option<String>,
    #[serde(default)]
    pub replan_required: bool,
    #[serde(default)]
    pub operator_followup_action: Option<String>,
    #[serde(default)]
    pub review_requested: bool,
    #[serde(default)]
    pub review_inbox_state: Option<String>,
    #[serde(default)]
    pub review_inbox_item_id: Option<String>,
    #[serde(default)]
    pub review_decision_id: Option<String>,
    #[serde(default)]
    pub review_decision_action: Option<String>,
    #[serde(default)]
    pub follow_on_plan_id: Option<String>,
    #[serde(default)]
    pub follow_on_plan_available: bool,
    #[serde(default)]
    pub latest_autonomy_policy_id: Option<String>,
    #[serde(default)]
    pub latest_risk_evaluation_id: Option<String>,
    #[serde(default)]
    pub latest_approval_gating_decision_id: Option<String>,
    #[serde(default)]
    pub latest_autonomy_calibration_dataset_id: Option<String>,
    #[serde(default)]
    pub latest_autonomy_policy_eval_report_id: Option<String>,
    #[serde(default)]
    pub latest_escalation_thresholds_id: Option<String>,
    #[serde(default)]
    pub latest_shadow_policy_comparison_id: Option<String>,
    #[serde(default)]
    pub latest_updated_policy_recommendation_id: Option<String>,
    #[serde(default)]
    pub latest_autonomy_policy_current_id: Option<String>,
    #[serde(default)]
    pub latest_autonomy_policy_candidate_id: Option<String>,
    #[serde(default)]
    pub latest_rollout_metrics_id: Option<String>,
    #[serde(default)]
    pub latest_guarded_rollout_decision_id: Option<String>,
    #[serde(default)]
    pub approval_gating_decision_class: Option<String>,
    #[serde(default)]
    pub approval_gating_risk_level: Option<String>,
    #[serde(default)]
    pub approval_gating_dispatch_ready: bool,
    #[serde(default)]
    pub approval_gating_blocked: bool,
    #[serde(default)]
    pub continuation_dispatched: bool,
    #[serde(default)]
    pub latest_continuation_dispatch_id: Option<String>,
    #[serde(default)]
    pub latest_continuation_receipt_id: Option<String>,
    #[serde(default)]
    pub continuation_current_state: Option<String>,
    #[serde(default)]
    pub continuation_source_execution_id: Option<String>,
    #[serde(default)]
    pub continuation_next_execution_id: Option<String>,
    #[serde(default)]
    pub continuation_next_plan_id: Option<String>,
    #[serde(default)]
    pub continuation_review_action: Option<String>,
    #[serde(default)]
    pub autonomy_policy_calibration_status: Option<String>,
    #[serde(default)]
    pub autonomy_policy_rollout_status: Option<String>,
    #[serde(default)]
    pub review_inbox_path: Option<String>,
    #[serde(default)]
    pub review_decision_path: Option<String>,
    #[serde(default)]
    pub follow_on_plan_path: Option<String>,
    #[serde(default)]
    pub autonomy_policy_path: Option<String>,
    #[serde(default)]
    pub risk_evaluation_path: Option<String>,
    #[serde(default)]
    pub approval_gating_decision_path: Option<String>,
    #[serde(default)]
    pub autonomy_calibration_dataset_path: Option<String>,
    #[serde(default)]
    pub autonomy_policy_eval_report_path: Option<String>,
    #[serde(default)]
    pub escalation_thresholds_path: Option<String>,
    #[serde(default)]
    pub shadow_policy_comparison_path: Option<String>,
    #[serde(default)]
    pub updated_policy_recommendation_path: Option<String>,
    #[serde(default)]
    pub autonomy_policy_current_path: Option<String>,
    #[serde(default)]
    pub autonomy_policy_candidate_path: Option<String>,
    #[serde(default)]
    pub rollout_metrics_path: Option<String>,
    #[serde(default)]
    pub rollout_decision_path: Option<String>,
    #[serde(default)]
    pub continuation_dispatch_path: Option<String>,
    #[serde(default)]
    pub continuation_receipt_path: Option<String>,
    #[serde(default)]
    pub continuation_state_path: Option<String>,
    #[serde(default)]
    pub reflection_path: Option<String>,
    #[serde(default)]
    pub trajectory_eval_path: Option<String>,
    #[serde(default)]
    pub replan_suggestion_path: Option<String>,
    pub operator_execution_state: String,
    pub note: String,
}
