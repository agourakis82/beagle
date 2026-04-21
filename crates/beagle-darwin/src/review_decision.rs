use chrono::{DateTime, Utc};
use serde::{Deserialize, Serialize};

pub const REVIEW_DECISION_VERSION: &str = "beagle-review-decision-v1";
pub const ALIGNMENT_LABEL_ALIGNED: &str = "aligned";
pub const ALIGNMENT_LABEL_MISALIGNED: &str = "misaligned";
pub const ALIGNMENT_LABEL_INSUFFICIENT_EVIDENCE: &str = "insufficient-evidence";

#[derive(Debug, Clone, Default, Serialize, Deserialize, PartialEq, Eq)]
pub struct ReviewDecisionEditPatch {
    #[serde(default)]
    pub task_family: Option<String>,
    #[serde(default)]
    pub selected_subagent_id: Option<String>,
    #[serde(default)]
    pub retrieval_query_type: Option<String>,
    #[serde(default)]
    pub compiler_profile_id: Option<String>,
    #[serde(default)]
    pub graphrag_query_mode: Option<String>,
    #[serde(default)]
    pub temporal_truth_view: Option<String>,
    #[serde(default)]
    pub recipe_kind: Option<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
pub struct ReviewDecision {
    pub decision_version: String,
    pub decision_id: String,
    pub inbox_item_id: String,
    pub execution_id: String,
    pub plan_id: String,
    pub workstream_id: String,
    pub workspace_id: String,
    pub session_id: String,
    pub decision_action: String,
    pub decided_by: String,
    pub decision_note: String,
    pub decided_at: DateTime<Utc>,
    pub operator_visibility_confirmed: bool,
    pub edited_fields: Vec<String>,
    pub follow_on_plan_materialized: bool,
    #[serde(default)]
    pub follow_on_plan_id: Option<String>,
    #[serde(default)]
    pub autonomy_policy_id: Option<String>,
    #[serde(default)]
    pub risk_evaluation_id: Option<String>,
    #[serde(default)]
    pub approval_gating_decision_id: Option<String>,
    #[serde(default)]
    pub approval_gating_decision_class: Option<String>,
    #[serde(default)]
    pub auto_continue_eligible: bool,
    #[serde(default)]
    pub dispatch_blocked: bool,
    pub note: String,
}

pub fn normalize_review_decision_action(value: &str) -> String {
    match value.trim().to_ascii_lowercase().as_str() {
        "approve" | "approved" => "approved".to_string(),
        "edit" | "edited" => "edited".to_string(),
        "reject" | "rejected" => "rejected".to_string(),
        _ => value.trim().to_ascii_lowercase(),
    }
}

pub fn operator_alignment_label_from_observation(observed_alignment: Option<bool>) -> String {
    match observed_alignment {
        Some(true) => ALIGNMENT_LABEL_ALIGNED.to_string(),
        Some(false) => ALIGNMENT_LABEL_MISALIGNED.to_string(),
        None => ALIGNMENT_LABEL_INSUFFICIENT_EVIDENCE.to_string(),
    }
}

pub fn edited_fields(edit_patch: Option<&ReviewDecisionEditPatch>) -> Vec<String> {
    let Some(edit_patch) = edit_patch else {
        return Vec::new();
    };
    let mut fields = Vec::new();
    if edit_patch.task_family.is_some() {
        fields.push("task_family".to_string());
    }
    if edit_patch.selected_subagent_id.is_some() {
        fields.push("selected_subagent_id".to_string());
    }
    if edit_patch.retrieval_query_type.is_some() {
        fields.push("retrieval_query_type".to_string());
    }
    if edit_patch.compiler_profile_id.is_some() {
        fields.push("compiler_profile_id".to_string());
    }
    if edit_patch.graphrag_query_mode.is_some() {
        fields.push("graphrag_query_mode".to_string());
    }
    if edit_patch.temporal_truth_view.is_some() {
        fields.push("temporal_truth_view".to_string());
    }
    if edit_patch.recipe_kind.is_some() {
        fields.push("recipe_kind".to_string());
    }
    fields
}

pub fn build_review_decision(
    inbox_item_id: &str,
    execution_id: &str,
    plan_id: &str,
    workstream_id: &str,
    workspace_id: &str,
    session_id: &str,
    decision_action: &str,
    decided_by: &str,
    decision_note: &str,
    edit_patch: Option<&ReviewDecisionEditPatch>,
    follow_on_plan_id: Option<String>,
) -> ReviewDecision {
    let normalized_action = normalize_review_decision_action(decision_action);
    ReviewDecision {
        decision_version: REVIEW_DECISION_VERSION.to_string(),
        decision_id: format!("{execution_id}-review-decision"),
        inbox_item_id: inbox_item_id.to_string(),
        execution_id: execution_id.to_string(),
        plan_id: plan_id.to_string(),
        workstream_id: workstream_id.to_string(),
        workspace_id: workspace_id.to_string(),
        session_id: session_id.to_string(),
        decision_action: normalized_action.clone(),
        decided_by: decided_by.to_string(),
        decision_note: decision_note.to_string(),
        decided_at: Utc::now(),
        operator_visibility_confirmed: true,
        edited_fields: edited_fields(edit_patch),
        follow_on_plan_materialized: follow_on_plan_id.is_some(),
        follow_on_plan_id,
        autonomy_policy_id: None,
        risk_evaluation_id: None,
        approval_gating_decision_id: None,
        approval_gating_decision_class: None,
        auto_continue_eligible: false,
        dispatch_blocked: false,
        note: format!(
            "B24.4 keeps operator review bounded and explicit: decision_action={} with no autonomous continuation.",
            normalized_action
        ),
    }
}
