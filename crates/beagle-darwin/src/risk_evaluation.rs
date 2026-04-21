use crate::autonomy_policy::AutonomyPolicy;
use crate::execution_reflection::ExecutionReflection;
use crate::follow_on_plan::FollowOnPlan;
use crate::replan::ReplanSuggestion;
use crate::review_decision::ReviewDecision;
use crate::review_inbox::ReviewInboxItem;
use crate::trajectory_eval::TrajectoryEval;
use serde::{Deserialize, Serialize};

pub const RISK_EVALUATION_VERSION: &str = "beagle-risk-evaluation-v1";

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
pub struct RiskSignal {
    pub signal_id: String,
    pub severity: String,
    pub policy_effect: String,
    pub observed_value: String,
    pub note: String,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
pub struct RiskEvaluationInput {
    pub task_family: String,
    pub selected_subagent_id: String,
    pub retrieval_query_type: String,
    pub compiler_profile_id: String,
    pub graphrag_query_mode: String,
    pub temporal_truth_view: String,
    pub trajectory_quality: String,
    pub overall_quality_score: u8,
    pub replan_required: bool,
    pub requested_operator_action: String,
    pub review_action: String,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
pub struct RiskEvaluationAssessment {
    pub matched_policy_signals: Vec<String>,
    pub risk_signals: Vec<RiskSignal>,
    pub risk_score: u8,
    pub risk_level: String,
    pub recommended_decision_class: String,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
pub struct RiskEvaluation {
    pub risk_evaluation_version: String,
    pub risk_evaluation_id: String,
    pub autonomy_policy_id: String,
    pub source_execution_id: String,
    pub source_plan_id: String,
    pub review_inbox_item_id: String,
    pub review_decision_id: String,
    pub follow_on_plan_id: String,
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
    pub overall_quality_score: u8,
    pub replan_required: bool,
    pub requested_operator_action: String,
    pub review_action: String,
    pub matched_policy_signals: Vec<String>,
    pub risk_signals: Vec<RiskSignal>,
    pub risk_score: u8,
    pub risk_level: String,
    pub recommended_decision_class: String,
    pub note: String,
}

pub fn build_risk_evaluation(
    policy: &AutonomyPolicy,
    inbox_item: &ReviewInboxItem,
    review_decision: &ReviewDecision,
    follow_on_plan: &FollowOnPlan,
    reflection: Option<&ExecutionReflection>,
    trajectory_eval: Option<&TrajectoryEval>,
    replan_suggestion: Option<&ReplanSuggestion>,
) -> RiskEvaluation {
    let execution_plan = &follow_on_plan.execution_plan;
    let input = RiskEvaluationInput {
        task_family: execution_plan.task_family.clone(),
        selected_subagent_id: execution_plan.selected_subagent_id.clone(),
        retrieval_query_type: execution_plan.retrieval_query_type.clone(),
        compiler_profile_id: execution_plan.compiler_profile_id.clone(),
        graphrag_query_mode: execution_plan.graphrag_query_mode.clone(),
        temporal_truth_view: execution_plan.temporal_truth_view.clone(),
        trajectory_quality: trajectory_eval
        .map(|trajectory| trajectory.trajectory_quality.clone())
        .unwrap_or_else(|| "unknown".to_string()),
        overall_quality_score: reflection
            .map(|reflection| reflection.overall_quality_score)
            .unwrap_or(0),
        replan_required: replan_suggestion
            .map(|suggestion| suggestion.replan_required)
            .unwrap_or(true),
        requested_operator_action: replan_suggestion
        .map(|suggestion| suggestion.requested_operator_action.clone())
        .unwrap_or_else(|| "review-and-plan-again".to_string()),
        review_action: review_decision.decision_action.clone(),
    };
    let assessment = assess_risk_input(
        policy,
        &input,
        reflection.is_some() && trajectory_eval.is_some() && replan_suggestion.is_some(),
    );

    RiskEvaluation {
        risk_evaluation_version: RISK_EVALUATION_VERSION.to_string(),
        risk_evaluation_id: format!("{}-risk-evaluation", follow_on_plan.follow_on_plan_id),
        autonomy_policy_id: policy.policy_id.clone(),
        source_execution_id: follow_on_plan.source_execution_id.clone(),
        source_plan_id: follow_on_plan.source_plan_id.clone(),
        review_inbox_item_id: inbox_item.inbox_item_id.clone(),
        review_decision_id: review_decision.decision_id.clone(),
        follow_on_plan_id: follow_on_plan.follow_on_plan_id.clone(),
        workstream_id: follow_on_plan.workstream_id.clone(),
        workspace_id: follow_on_plan.workspace_id.clone(),
        session_id: follow_on_plan.session_id.clone(),
        task_family: input.task_family.clone(),
        selected_subagent_id: input.selected_subagent_id.clone(),
        retrieval_query_type: input.retrieval_query_type.clone(),
        compiler_profile_id: input.compiler_profile_id.clone(),
        graphrag_query_mode: input.graphrag_query_mode.clone(),
        temporal_truth_view: input.temporal_truth_view.clone(),
        trajectory_quality: input.trajectory_quality.clone(),
        overall_quality_score: input.overall_quality_score,
        replan_required: input.replan_required,
        requested_operator_action: input.requested_operator_action.clone(),
        review_action: review_decision.decision_action.clone(),
        matched_policy_signals: assessment.matched_policy_signals,
        risk_signals: assessment.risk_signals,
        risk_score: assessment.risk_score,
        risk_level: assessment.risk_level,
        recommended_decision_class: assessment.recommended_decision_class,
        note: "B24.6 risk evaluation keeps continuation autonomy bounded: score the actual follow-on plan against reflection, trajectory, and replan signals before deciding whether to auto-continue, request review, or block.".to_string(),
    }
}

pub fn assess_risk_input(
    policy: &AutonomyPolicy,
    input: &RiskEvaluationInput,
    signals_present: bool,
) -> RiskEvaluationAssessment {
    let mut matched_policy_signals = Vec::new();
    let mut risk_signals = Vec::new();
    let mut risk_score: u8 = 0;
    let mut auto_continue_eligible = true;
    let mut blocked = false;

    evaluate_auto_signal(
        &mut matched_policy_signals,
        &mut risk_signals,
        &mut risk_score,
        &mut auto_continue_eligible,
        policy.auto_continue_task_families.contains(&input.task_family),
        "task_family",
        &input.task_family,
        "task-family",
    );
    evaluate_auto_signal(
        &mut matched_policy_signals,
        &mut risk_signals,
        &mut risk_score,
        &mut auto_continue_eligible,
        policy
            .auto_continue_subagent_ids
            .contains(&input.selected_subagent_id),
        "selected_subagent_id",
        &input.selected_subagent_id,
        "subagent",
    );
    evaluate_auto_signal(
        &mut matched_policy_signals,
        &mut risk_signals,
        &mut risk_score,
        &mut auto_continue_eligible,
        policy
            .auto_continue_retrieval_query_types
            .contains(&input.retrieval_query_type),
        "retrieval_query_type",
        &input.retrieval_query_type,
        "retrieval",
    );
    evaluate_auto_signal(
        &mut matched_policy_signals,
        &mut risk_signals,
        &mut risk_score,
        &mut auto_continue_eligible,
        policy
            .auto_continue_compiler_profile_ids
            .contains(&input.compiler_profile_id),
        "compiler_profile_id",
        &input.compiler_profile_id,
        "compiler",
    );
    evaluate_auto_signal(
        &mut matched_policy_signals,
        &mut risk_signals,
        &mut risk_score,
        &mut auto_continue_eligible,
        policy
            .auto_continue_graphrag_query_modes
            .contains(&input.graphrag_query_mode),
        "graphrag_query_mode",
        &input.graphrag_query_mode,
        "graphrag",
    );
    evaluate_auto_signal(
        &mut matched_policy_signals,
        &mut risk_signals,
        &mut risk_score,
        &mut auto_continue_eligible,
        policy
            .auto_continue_temporal_truth_views
            .contains(&input.temporal_truth_view),
        "temporal_truth_view",
        &input.temporal_truth_view,
        "temporal",
    );
    evaluate_auto_signal(
        &mut matched_policy_signals,
        &mut risk_signals,
        &mut risk_score,
        &mut auto_continue_eligible,
        policy
            .auto_continue_allowed_review_actions
            .contains(&input.review_action),
        "review_action",
        &input.review_action,
        "review-action",
    );
    evaluate_auto_signal(
        &mut matched_policy_signals,
        &mut risk_signals,
        &mut risk_score,
        &mut auto_continue_eligible,
        policy
            .auto_continue_allowed_trajectory_qualities
            .contains(&input.trajectory_quality),
        "trajectory_quality",
        &input.trajectory_quality,
        "trajectory",
    );

    if !signals_present {
        auto_continue_eligible = false;
        risk_score = risk_score.saturating_add(35);
        risk_signals.push(RiskSignal {
            signal_id: "missing_b24_3_signals".to_string(),
            severity: "high".to_string(),
            policy_effect: "review-required".to_string(),
            observed_value: "one-or-more-missing".to_string(),
            note: "B24.6 will not auto-continue when reflection, trajectory, or replan signals are missing from the same bounded execution identity.".to_string(),
        });
    }

    if input.overall_quality_score < policy.auto_continue_min_overall_quality_score {
        auto_continue_eligible = false;
        if input.overall_quality_score <= policy.blocked_max_overall_quality_score {
            blocked = true;
            risk_score = risk_score.saturating_add(60);
            risk_signals.push(RiskSignal {
                signal_id: "overall_quality_score".to_string(),
                severity: "high".to_string(),
                policy_effect: "blocked".to_string(),
                observed_value: input.overall_quality_score.to_string(),
                note: "Low overall quality hard-stops bounded continuation until the operator replans.".to_string(),
            });
        } else {
            risk_score = risk_score.saturating_add(20);
            risk_signals.push(RiskSignal {
                signal_id: "overall_quality_score".to_string(),
                severity: "medium".to_string(),
                policy_effect: "review-required".to_string(),
                observed_value: input.overall_quality_score.to_string(),
                note: "Quality below the auto-continue floor remains operator-visible and requires manual review before dispatch.".to_string(),
            });
        }
    } else {
        matched_policy_signals.push(format!(
            "quality-score:{}>={}",
            input.overall_quality_score, policy.auto_continue_min_overall_quality_score
        ));
    }

    if policy
        .blocked_trajectory_qualities
        .contains(&input.trajectory_quality)
    {
        blocked = true;
        auto_continue_eligible = false;
        risk_score = risk_score.saturating_add(60);
        risk_signals.push(RiskSignal {
            signal_id: "blocked_trajectory_quality".to_string(),
            severity: "high".to_string(),
            policy_effect: "blocked".to_string(),
            observed_value: input.trajectory_quality.clone(),
            note: "A degraded trajectory remains bounded-visible but cannot auto-continue into the next cycle.".to_string(),
        });
    }

    if input.replan_required {
        blocked = true;
        auto_continue_eligible = false;
        risk_score = risk_score.saturating_add(60);
        risk_signals.push(RiskSignal {
            signal_id: "replan_required".to_string(),
            severity: "high".to_string(),
            policy_effect: "blocked".to_string(),
            observed_value: input.replan_required.to_string(),
            note: "Explicit replan requirements block continuation dispatch until a new bounded plan is reviewed.".to_string(),
        });
    } else {
        matched_policy_signals.push("replan-required:false".to_string());
    }

    if policy
        .blocked_requested_operator_actions
        .contains(&input.requested_operator_action)
    {
        blocked = true;
        auto_continue_eligible = false;
        risk_score = risk_score.saturating_add(50);
        risk_signals.push(RiskSignal {
            signal_id: "requested_operator_action".to_string(),
            severity: "high".to_string(),
            policy_effect: "blocked".to_string(),
            observed_value: input.requested_operator_action.clone(),
            note: "Operator stop-or-replan actions are treated as a hard continuation block in B24.6.".to_string(),
        });
    } else {
        matched_policy_signals.push(format!(
            "operator-action:{}",
            input.requested_operator_action
        ));
    }

    let recommended_decision_class = if blocked {
        "blocked".to_string()
    } else if auto_continue_eligible {
        "auto-continue".to_string()
    } else {
        "review-required".to_string()
    };
    let risk_level = if blocked || risk_score >= 80 {
        "high".to_string()
    } else if risk_score >= 30 {
        "moderate".to_string()
    } else {
        "low".to_string()
    };

    RiskEvaluationAssessment {
        matched_policy_signals,
        risk_signals,
        risk_score,
        risk_level,
        recommended_decision_class,
    }
}

fn evaluate_auto_signal(
    matched_policy_signals: &mut Vec<String>,
    risk_signals: &mut Vec<RiskSignal>,
    risk_score: &mut u8,
    auto_continue_eligible: &mut bool,
    allowed: bool,
    signal_id: &str,
    observed_value: &str,
    label: &str,
) {
    if allowed {
        matched_policy_signals.push(format!("{label}:{observed_value}"));
    } else {
        *auto_continue_eligible = false;
        *risk_score = risk_score.saturating_add(10);
        risk_signals.push(RiskSignal {
            signal_id: signal_id.to_string(),
            severity: "medium".to_string(),
            policy_effect: "review-required".to_string(),
            observed_value: observed_value.to_string(),
            note: format!(
                "Observed {}='{}' falls outside the first auto-continue lane and therefore stays operator-reviewed.",
                label, observed_value
            ),
        });
    }
}
