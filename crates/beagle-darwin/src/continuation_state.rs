use crate::execution_state::{
    ExecutionReceipt, ExecutionResultLinksDocument, ExecutionStatePlane,
};
use chrono::{DateTime, Utc};
use serde::{Deserialize, Serialize};

pub const CONTINUATION_STATE_VERSION: &str = "beagle-continuation-state-v1";
pub const CONTINUATION_RECEIPT_VERSION: &str = "beagle-continuation-receipt-v1";

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
pub struct ContinuationStateTransition {
    pub state: String,
    pub transitioned_at: DateTime<Utc>,
    pub note: String,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
pub struct ContinuationStatePlane {
    pub state_version: String,
    pub continuation_dispatch_id: String,
    pub workstream_id: String,
    pub workspace_id: String,
    pub session_id: String,
    pub source_execution_id: String,
    pub source_plan_id: String,
    #[serde(default)]
    pub source_receipt_id: Option<String>,
    pub review_inbox_item_id: String,
    pub review_decision_id: String,
    pub follow_on_plan_id: String,
    pub review_action: String,
    pub continuation_depth: usize,
    pub current_state: String,
    pub dispatched_at: DateTime<Utc>,
    #[serde(default)]
    pub latest_continuation_receipt_id: Option<String>,
    pub continuation_state_path: String,
    pub continuation_receipt_path: String,
    pub chained_receipt_ids: Vec<String>,
    pub state_transitions: Vec<ContinuationStateTransition>,
    pub next_execution_state: ExecutionStatePlane,
    pub note: String,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
pub struct ContinuationReceipt {
    pub receipt_version: String,
    pub continuation_receipt_id: String,
    pub continuation_dispatch_id: String,
    pub workstream_id: String,
    pub workspace_id: String,
    pub session_id: String,
    pub source_execution_id: String,
    pub source_plan_id: String,
    #[serde(default)]
    pub source_receipt_id: Option<String>,
    pub review_decision_id: String,
    pub follow_on_plan_id: String,
    pub recorded_at: DateTime<Utc>,
    pub review_action: String,
    pub chained_receipt_ids: Vec<String>,
    pub handoff_updated: bool,
    #[serde(default)]
    pub handoff_ref: Option<String>,
    pub next_execution_receipt: ExecutionReceipt,
    pub next_execution_result_links: ExecutionResultLinksDocument,
    pub continuation_state_path: String,
    pub note: String,
}
