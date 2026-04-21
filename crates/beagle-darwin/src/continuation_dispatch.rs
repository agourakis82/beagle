use chrono::{DateTime, Utc};
use serde::{Deserialize, Serialize};

pub const CONTINUATION_DISPATCH_VERSION: &str = "beagle-continuation-dispatch-v1";

#[derive(Debug, Clone)]
pub struct ContinuationDispatchRequest<'a> {
    pub dispatched_by: &'a str,
    pub dispatch_note: &'a str,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
pub struct ContinuationDispatch {
    pub dispatch_version: String,
    pub continuation_dispatch_id: String,
    pub source_execution_id: String,
    pub source_plan_id: String,
    #[serde(default)]
    pub source_receipt_id: Option<String>,
    pub review_inbox_item_id: String,
    pub review_decision_id: String,
    pub follow_on_plan_id: String,
    pub workstream_id: String,
    pub workspace_id: String,
    pub session_id: String,
    pub review_action: String,
    pub dispatch_state: String,
    pub dispatched_by: String,
    pub dispatch_note: String,
    pub dispatched_at: DateTime<Utc>,
    pub operator_visibility_confirmed: bool,
    pub next_execution_id: String,
    pub next_plan_id: String,
    pub next_task_family: String,
    pub next_selected_subagent_id: String,
    pub next_retrieval_query_type: String,
    pub next_compiler_profile_id: String,
    pub next_graphrag_query_mode: String,
    pub next_temporal_truth_view: String,
    #[serde(default)]
    pub autonomy_policy_id: Option<String>,
    #[serde(default)]
    pub risk_evaluation_id: Option<String>,
    #[serde(default)]
    pub approval_gating_decision_id: Option<String>,
    #[serde(default)]
    pub approval_gating_decision_class: Option<String>,
    #[serde(default)]
    pub approval_gating_risk_level: Option<String>,
    pub continuation_state_path: String,
    pub continuation_receipt_path: String,
    pub note: String,
}
