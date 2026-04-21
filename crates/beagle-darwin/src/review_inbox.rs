use crate::execution_state::ExecutionStatePlane;
use crate::replan::ReplanSuggestion;
use chrono::{DateTime, Utc};
use serde::{Deserialize, Serialize};

pub const REVIEW_INBOX_ITEM_VERSION: &str = "beagle-review-inbox-item-v1";

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
pub struct ReviewInboxItem {
    pub inbox_version: String,
    pub inbox_item_id: String,
    pub execution_id: String,
    pub plan_id: String,
    pub workstream_id: String,
    pub workspace_id: String,
    pub session_id: String,
    #[serde(default)]
    pub reflection_id: Option<String>,
    #[serde(default)]
    pub trajectory_eval_id: Option<String>,
    pub replan_suggestion_id: String,
    pub requested_operator_action: String,
    pub replan_required: bool,
    pub inbox_state: String,
    pub created_by: String,
    pub created_at: DateTime<Utc>,
    pub create_note: String,
    pub suggested_task_family: String,
    pub suggested_subagent_id: String,
    pub suggested_retrieval_query_type: String,
    pub suggested_compiler_profile_id: String,
    pub suggested_graphrag_query_mode: String,
    pub suggested_temporal_truth_view: String,
    #[serde(default)]
    pub suggested_recipe_kind: Option<String>,
    pub suggested_changes: Vec<String>,
    pub rationale: String,
    #[serde(default)]
    pub autonomy_policy_id: Option<String>,
    #[serde(default)]
    pub risk_evaluation_id: Option<String>,
    #[serde(default)]
    pub approval_gating_decision_id: Option<String>,
    #[serde(default)]
    pub approval_gating_decision_class: Option<String>,
    pub review_decision_path: String,
    pub follow_on_plan_path: String,
    #[serde(default)]
    pub autonomy_policy_path: Option<String>,
    #[serde(default)]
    pub risk_evaluation_path: Option<String>,
    #[serde(default)]
    pub approval_gating_decision_path: Option<String>,
    pub note: String,
}

pub fn build_review_inbox_item(
    state: &ExecutionStatePlane,
    replan_suggestion: &ReplanSuggestion,
    created_by: &str,
    create_note: &str,
    review_decision_path: &str,
    follow_on_plan_path: &str,
) -> ReviewInboxItem {
    let created_at = Utc::now();
    ReviewInboxItem {
        inbox_version: REVIEW_INBOX_ITEM_VERSION.to_string(),
        inbox_item_id: format!("{}-review", state.execution_id),
        execution_id: state.execution_id.clone(),
        plan_id: state.plan_id.clone(),
        workstream_id: state.workstream_id.clone(),
        workspace_id: state.workspace_id.clone(),
        session_id: state.session_id.clone(),
        reflection_id: state.latest_reflection_id.clone(),
        trajectory_eval_id: state.latest_trajectory_eval_id.clone(),
        replan_suggestion_id: replan_suggestion.suggestion_id.clone(),
        requested_operator_action: replan_suggestion.requested_operator_action.clone(),
        replan_required: replan_suggestion.replan_required,
        inbox_state: "pending-review".to_string(),
        created_by: created_by.to_string(),
        created_at,
        create_note: create_note.to_string(),
        suggested_task_family: replan_suggestion.suggested_task_family.clone(),
        suggested_subagent_id: replan_suggestion.suggested_subagent_id.clone(),
        suggested_retrieval_query_type: replan_suggestion.suggested_retrieval_query_type.clone(),
        suggested_compiler_profile_id: replan_suggestion.suggested_compiler_profile_id.clone(),
        suggested_graphrag_query_mode: replan_suggestion.suggested_graphrag_query_mode.clone(),
        suggested_temporal_truth_view: replan_suggestion.suggested_temporal_truth_view.clone(),
        suggested_recipe_kind: replan_suggestion.suggested_recipe_kind.clone(),
        suggested_changes: replan_suggestion.suggested_changes.clone(),
        rationale: replan_suggestion.rationale.clone(),
        autonomy_policy_id: None,
        risk_evaluation_id: None,
        approval_gating_decision_id: None,
        approval_gating_decision_class: None,
        review_decision_path: review_decision_path.to_string(),
        follow_on_plan_path: follow_on_plan_path.to_string(),
        autonomy_policy_path: None,
        risk_evaluation_path: None,
        approval_gating_decision_path: None,
        note: "B24.4 turns a bounded replan suggestion into one operator-visible inbox item on the same Beagle-owned execution identity, without auto-continuing execution.".to_string(),
    }
}
