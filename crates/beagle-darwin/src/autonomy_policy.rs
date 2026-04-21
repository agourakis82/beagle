use crate::follow_on_plan::FollowOnPlan;
use serde::{Deserialize, Serialize};

pub const AUTONOMY_POLICY_VERSION: &str = "beagle-autonomy-policy-v1";
const AUTONOMY_POLICY_SCOPE: &str = "follow-on-plan-gating";

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
pub struct AutonomyPolicy {
    pub policy_version: String,
    pub policy_id: String,
    pub workstream_id: String,
    pub workspace_id: String,
    pub session_id: String,
    pub source_execution_id: String,
    pub policy_scope: String,
    #[serde(default)]
    pub policy_role: Option<String>,
    #[serde(default)]
    pub rollout_stage: Option<String>,
    #[serde(default)]
    pub policy_family_scope: Vec<String>,
    #[serde(default)]
    pub guarded_enablement_live: bool,
    #[serde(default)]
    pub control_policy_id: Option<String>,
    #[serde(default)]
    pub source_threshold_id: Option<String>,
    pub allowed_decision_classes: Vec<String>,
    pub auto_continue_task_families: Vec<String>,
    pub auto_continue_subagent_ids: Vec<String>,
    pub auto_continue_retrieval_query_types: Vec<String>,
    pub auto_continue_compiler_profile_ids: Vec<String>,
    pub auto_continue_graphrag_query_modes: Vec<String>,
    pub auto_continue_temporal_truth_views: Vec<String>,
    pub auto_continue_allowed_review_actions: Vec<String>,
    pub auto_continue_allowed_trajectory_qualities: Vec<String>,
    pub auto_continue_min_overall_quality_score: u8,
    pub blocked_max_overall_quality_score: u8,
    pub blocked_trajectory_qualities: Vec<String>,
    pub blocked_requested_operator_actions: Vec<String>,
    pub note: String,
}

pub fn build_autonomy_policy(follow_on_plan: &FollowOnPlan) -> AutonomyPolicy {
    AutonomyPolicy {
        policy_version: AUTONOMY_POLICY_VERSION.to_string(),
        policy_id: format!(
            "{}-autonomy-policy-v1",
            sanitize_component(&follow_on_plan.workstream_id)
        ),
        workstream_id: follow_on_plan.workstream_id.clone(),
        workspace_id: follow_on_plan.workspace_id.clone(),
        session_id: follow_on_plan.session_id.clone(),
        source_execution_id: follow_on_plan.source_execution_id.clone(),
        policy_scope: AUTONOMY_POLICY_SCOPE.to_string(),
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
        note: "B24.6 keeps autonomy bounded: only the low-risk approved analysis lane may auto-continue, while all other follow-on plans stay review-required or blocked on the same Beagle-owned identity.".to_string(),
    }
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
