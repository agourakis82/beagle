use crate::autonomy_policy::AutonomyPolicy;
use crate::follow_on_plan::FollowOnPlan;
use crate::review_decision::ReviewDecision;
use crate::review_inbox::ReviewInboxItem;
use crate::risk_evaluation::RiskEvaluation;
use chrono::{DateTime, Utc};
use serde::{Deserialize, Serialize};

pub const APPROVAL_GATING_DECISION_VERSION: &str = "beagle-approval-gating-decision-v1";

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
pub struct ApprovalGatingDecision {
    pub decision_version: String,
    pub approval_gating_decision_id: String,
    pub autonomy_policy_id: String,
    pub risk_evaluation_id: String,
    pub source_execution_id: String,
    pub source_plan_id: String,
    pub review_inbox_item_id: String,
    pub review_decision_id: String,
    pub follow_on_plan_id: String,
    pub workstream_id: String,
    pub workspace_id: String,
    pub session_id: String,
    pub decision_class: String,
    pub matched_policy_rule: String,
    pub evaluated_at: DateTime<Utc>,
    pub operator_visibility_confirmed: bool,
    pub continuation_dispatch_permitted: bool,
    pub auto_continuation_enabled: bool,
    pub human_review_required: bool,
    pub blocked: bool,
    pub follow_on_state_after_gating: String,
    pub requested_operator_action: String,
    pub review_inbox_path: String,
    pub continuation_dispatch_path: String,
    pub note: String,
}

pub fn build_approval_gating_decision(
    policy: &AutonomyPolicy,
    risk_evaluation: &RiskEvaluation,
    inbox_item: &ReviewInboxItem,
    review_decision: &ReviewDecision,
    follow_on_plan: &FollowOnPlan,
    review_inbox_path: &str,
    continuation_dispatch_path: &str,
) -> ApprovalGatingDecision {
    let evaluated_at = Utc::now();
    let implementation_canary_live = policy
        .policy_role
        .as_deref()
        .is_some_and(|role| role == "implementation-canary-live")
        && policy.guarded_enablement_live
        && follow_on_plan.execution_plan.task_family == "implementation";
    let analysis_canary_live = policy
        .policy_role
        .as_deref()
        .is_some_and(|role| role == "analysis-canary-live")
        && policy.guarded_enablement_live
        && follow_on_plan.execution_plan.task_family == "analysis";
    let (matched_policy_rule, continuation_dispatch_permitted, auto_continuation_enabled, human_review_required, blocked, follow_on_state_after_gating, requested_operator_action) =
        match risk_evaluation.recommended_decision_class.as_str() {
            "auto-continue" => (
                if implementation_canary_live {
                    "guarded-implementation-canary-lane".to_string()
                } else if analysis_canary_live {
                    "guarded-analysis-canary-lane".to_string()
                } else {
                    "low-risk-approved-analysis-lane".to_string()
                },
                true,
                true,
                false,
                false,
                "auto-continue-ready".to_string(),
                "observe-auto-continued-follow-on-plan".to_string(),
            ),
            "blocked" => (
                "hard-stop-replan-required".to_string(),
                false,
                false,
                false,
                true,
                "blocked".to_string(),
                "replan-before-any-continuation".to_string(),
            ),
            _ => (
                "operator-reviewed-dispatch-required".to_string(),
                true,
                false,
                true,
                false,
                "review-required".to_string(),
                "review-and-dispatch-follow-on-plan".to_string(),
            ),
        };

    ApprovalGatingDecision {
        decision_version: APPROVAL_GATING_DECISION_VERSION.to_string(),
        approval_gating_decision_id: format!(
            "{}-approval-gate",
            follow_on_plan.follow_on_plan_id
        ),
        autonomy_policy_id: policy.policy_id.clone(),
        risk_evaluation_id: risk_evaluation.risk_evaluation_id.clone(),
        source_execution_id: follow_on_plan.source_execution_id.clone(),
        source_plan_id: follow_on_plan.source_plan_id.clone(),
        review_inbox_item_id: inbox_item.inbox_item_id.clone(),
        review_decision_id: review_decision.decision_id.clone(),
        follow_on_plan_id: follow_on_plan.follow_on_plan_id.clone(),
        workstream_id: follow_on_plan.workstream_id.clone(),
        workspace_id: follow_on_plan.workspace_id.clone(),
        session_id: follow_on_plan.session_id.clone(),
        decision_class: risk_evaluation.recommended_decision_class.clone(),
        matched_policy_rule,
        evaluated_at,
        operator_visibility_confirmed: true,
        continuation_dispatch_permitted,
        auto_continuation_enabled,
        human_review_required,
        blocked,
        follow_on_state_after_gating,
        requested_operator_action,
        review_inbox_path: review_inbox_path.to_string(),
        continuation_dispatch_path: continuation_dispatch_path.to_string(),
        note: format!(
            "B24 approval gating keeps follow-on autonomy bounded on the same Beagle-owned identity: review_action={} decision_class={} policy_role={}.",
            review_decision.decision_action,
            risk_evaluation.recommended_decision_class,
            policy
                .policy_role
                .clone()
                .unwrap_or_else(|| "unspecified".to_string())
        ),
    }
}
