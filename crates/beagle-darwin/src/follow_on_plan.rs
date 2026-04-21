use crate::execution_plan::{
    ExecutionExperimentTarget, ExecutionPlan, ExecutionRecipeTarget, PlanAcceptanceCriterion,
};
use crate::intent_planner::planner_policy_for_workstream;
use crate::review_decision::ReviewDecisionEditPatch;
use crate::review_inbox::ReviewInboxItem;
use crate::replan::ReplanSuggestion;
use chrono::{DateTime, Utc};
use serde::{Deserialize, Serialize};

pub const FOLLOW_ON_PLAN_VERSION: &str = "beagle-follow-on-plan-v1";

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
pub struct FollowOnPlan {
    pub follow_on_plan_version: String,
    pub follow_on_plan_id: String,
    pub source_execution_id: String,
    pub source_plan_id: String,
    pub review_inbox_item_id: String,
    pub replan_suggestion_id: String,
    pub workstream_id: String,
    pub workspace_id: String,
    pub session_id: String,
    pub review_action: String,
    pub follow_on_state: String,
    pub materialized_at: DateTime<Utc>,
    pub materialized_by: String,
    #[serde(default)]
    pub autonomy_policy_id: Option<String>,
    #[serde(default)]
    pub risk_evaluation_id: Option<String>,
    #[serde(default)]
    pub approval_gating_decision_id: Option<String>,
    #[serde(default)]
    pub approval_gating_decision_class: Option<String>,
    #[serde(default)]
    pub approval_gating_decision_path: Option<String>,
    pub execution_plan: ExecutionPlan,
    pub note: String,
}

pub fn build_follow_on_plan(
    source_plan: &ExecutionPlan,
    inbox_item: &ReviewInboxItem,
    replan_suggestion: &ReplanSuggestion,
    decision_action: &str,
    decided_by: &str,
    edit_patch: Option<&ReviewDecisionEditPatch>,
) -> FollowOnPlan {
    let materialized_at = Utc::now();
    let task_family = edit_patch
        .and_then(|patch| patch.task_family.as_deref())
        .map(normalize_task_family)
        .unwrap_or_else(|| normalize_task_family(&replan_suggestion.suggested_task_family));
    let profile = planner_policy_for_workstream(&source_plan.workstream_id)
        .profiles
        .into_iter()
        .find(|profile| profile.task_family == task_family)
        .unwrap_or_else(|| planner_policy_for_workstream(&source_plan.workstream_id).profiles[0].clone());
    let selected_subagent_id = normalized_selector_or_default(
        edit_patch.and_then(|patch| patch.selected_subagent_id.as_deref()),
        &replan_suggestion.suggested_subagent_id,
    );
    let retrieval_query_type = trimmed_or_default(
        edit_patch.and_then(|patch| patch.retrieval_query_type.as_deref()),
        &replan_suggestion.suggested_retrieval_query_type,
    );
    let compiler_profile_id = trimmed_or_default(
        edit_patch.and_then(|patch| patch.compiler_profile_id.as_deref()),
        &replan_suggestion.suggested_compiler_profile_id,
    );
    let graphrag_query_mode = trimmed_or_default(
        edit_patch.and_then(|patch| patch.graphrag_query_mode.as_deref()),
        &replan_suggestion.suggested_graphrag_query_mode,
    );
    let temporal_truth_view = trimmed_or_default(
        edit_patch.and_then(|patch| patch.temporal_truth_view.as_deref()),
        &replan_suggestion.suggested_temporal_truth_view,
    );
    let recipe_kind = edit_patch
        .and_then(|patch| patch.recipe_kind.as_deref())
        .map(trimmed_value)
        .or_else(|| {
            replan_suggestion
                .suggested_recipe_kind
                .as_deref()
                .map(trimmed_value)
        })
        .unwrap_or_else(|| profile.preferred_recipe_kind.clone());
    let follow_on_plan_id = format!(
        "{}-follow-on-{}",
        sanitize_component(&source_plan.plan_id),
        materialized_at.timestamp_millis()
    );
    let execution_plan = ExecutionPlan {
        plan_version: source_plan.plan_version.clone(),
        plan_id: follow_on_plan_id.clone(),
        planner_policy_id: source_plan.planner_policy_id.clone(),
        workstream_id: source_plan.workstream_id.clone(),
        workspace_id: source_plan.workspace_id.clone(),
        session_id: source_plan.session_id.clone(),
        program_id: source_plan.program_id.clone(),
        campaign_id: source_plan.campaign_id.clone(),
        task_family: task_family.clone(),
        tool_id: profile.tool_id.clone(),
        work_mode: profile.work_mode.clone(),
        selected_subagent_id: selected_subagent_id.clone(),
        selected_role_tag: role_tag_for_subagent(&task_family, &selected_subagent_id),
        selected_specialization: specialization_for_subagent(&task_family, &selected_subagent_id),
        retrieval_query_type: retrieval_query_type.clone(),
        dense_backend: dense_backend_for_query_type(&retrieval_query_type),
        sparse_backend: source_plan.sparse_backend.clone(),
        compiler_profile_id: compiler_profile_id.clone(),
        graphrag_query_mode: graphrag_query_mode.clone(),
        temporal_truth_view: temporal_truth_view.clone(),
        selected_memory_tiers: memory_tiers_for_task_family(&task_family),
        recipe_target: Some(recipe_target_for_kind(
            source_plan.recipe_target.as_ref(),
            &source_plan.workstream_id,
            &recipe_kind,
        )),
        experiment_target: experiment_target_for_task_family(&task_family, source_plan.experiment_target.as_ref()),
        expected_outputs: expected_outputs_for_task_family(&task_family, source_plan.experiment_target.as_ref()),
        success_criteria: success_criteria_for_task_family(&task_family),
        stop_conditions: stop_conditions_for_follow_on(&task_family),
        context_packet_ref: source_plan.context_packet_ref.clone(),
        program_context_packet_ref: source_plan.program_context_packet_ref.clone(),
        workspace_subagent_route_path: format!(
            "/api/darwin/workstreams/{}/workspace-subagent-route?tool_id={}&work_mode={}",
            source_plan.workstream_id, profile.tool_id, profile.work_mode
        ),
        workspace_subagent_handoff_path: source_plan.workspace_subagent_handoff_path.clone(),
        tool_launch_path: format!(
            "/api/darwin/workstreams/{}/tool-dock/{}",
            source_plan.workstream_id, profile.tool_id
        ),
        compiled_context_top_memory_ids: source_plan.compiled_context_top_memory_ids.clone(),
        compiled_context_preview: Some(format!(
            "follow_on_plan_id: {}\ntask_family: {}\nreview_action: {}",
            follow_on_plan_id, task_family, decision_action
        )),
        operator_execution_state: source_plan.operator_execution_state.clone(),
        note: format!(
            "B24.4 follow-on plan materialized from inbox_item={} with review_action={} and task_family={}.",
            inbox_item.inbox_item_id, decision_action, task_family
        ),
    };

    FollowOnPlan {
        follow_on_plan_version: FOLLOW_ON_PLAN_VERSION.to_string(),
        follow_on_plan_id: follow_on_plan_id.clone(),
        source_execution_id: inbox_item.execution_id.clone(),
        source_plan_id: source_plan.plan_id.clone(),
        review_inbox_item_id: inbox_item.inbox_item_id.clone(),
        replan_suggestion_id: replan_suggestion.suggestion_id.clone(),
        workstream_id: source_plan.workstream_id.clone(),
        workspace_id: source_plan.workspace_id.clone(),
        session_id: source_plan.session_id.clone(),
        review_action: decision_action.to_string(),
        follow_on_state: "queued-for-approval".to_string(),
        materialized_at,
        materialized_by: decided_by.to_string(),
        autonomy_policy_id: None,
        risk_evaluation_id: None,
        approval_gating_decision_id: None,
        approval_gating_decision_class: None,
        approval_gating_decision_path: None,
        execution_plan,
        note: "B24.4 follow-on plans stay bounded and operator-visible: they materialize the next candidate execution plan, but still require explicit approval before any start step.".to_string(),
    }
}

fn normalized_selector_or_default(value: Option<&str>, fallback: &str) -> String {
    value
        .map(normalize_selector)
        .unwrap_or_else(|| fallback.to_string())
}

fn trimmed_or_default(value: Option<&str>, fallback: &str) -> String {
    value.map(trimmed_value).unwrap_or_else(|| fallback.to_string())
}

fn normalize_task_family(value: &str) -> String {
    match value.trim().to_ascii_lowercase().replace('_', "-").as_str() {
        "implementation" | "impl" | "code" | "codex" => "implementation".to_string(),
        "interactive" | "interactive-editing" | "editing" | "cursor" => {
            "interactive-editing".to_string()
        }
        "manuscript" | "editorial" => "manuscript".to_string(),
        _ => "analysis".to_string(),
    }
}

fn normalize_selector(value: &str) -> String {
    value.trim().to_ascii_lowercase().replace('_', "-")
}

fn trimmed_value(value: &str) -> String {
    value.trim().to_string()
}

fn dense_backend_for_query_type(query_type: &str) -> String {
    match query_type.trim().to_ascii_lowercase().as_str() {
        "code" => "voyage-code-3".to_string(),
        "sovereign" | "multilingual" | "privacy-sensitive" => "bge-m3".to_string(),
        _ => "voyage-4-large".to_string(),
    }
}

fn memory_tiers_for_task_family(task_family: &str) -> Vec<String> {
    match normalize_task_family(task_family).as_str() {
        "implementation" => vec![
            "procedural".to_string(),
            "semantic".to_string(),
            "episodic".to_string(),
        ],
        "interactive-editing" => vec![
            "procedural".to_string(),
            "episodic".to_string(),
            "semantic".to_string(),
        ],
        "manuscript" => vec![
            "semantic".to_string(),
            "episodic".to_string(),
            "procedural".to_string(),
        ],
        _ => vec![
            "semantic".to_string(),
            "episodic".to_string(),
            "procedural".to_string(),
        ],
    }
}

fn role_tag_for_subagent(task_family: &str, subagent_id: &str) -> String {
    match (normalize_task_family(task_family).as_str(), subagent_id.trim().to_ascii_lowercase().as_str()) {
        (_, "manuscript") => "manuscript-assembly".to_string(),
        ("implementation", _) | ("interactive-editing", _) | (_, "core") => {
            "implementation-core".to_string()
        }
        _ => "experiment-loop".to_string(),
    }
}

fn specialization_for_subagent(task_family: &str, subagent_id: &str) -> String {
    match (normalize_task_family(task_family).as_str(), subagent_id.trim().to_ascii_lowercase().as_str()) {
        (_, "manuscript") => "Manuscript assembly follow-on".to_string(),
        ("implementation", _) | ("interactive-editing", _) | (_, "core") => {
            "Repo-native implementation follow-on".to_string()
        }
        _ => "Operator analysis follow-on".to_string(),
    }
}

fn recipe_target_for_kind(
    existing: Option<&ExecutionRecipeTarget>,
    workstream_id: &str,
    recipe_kind: &str,
) -> ExecutionRecipeTarget {
    if let Some(existing) = existing.filter(|existing| existing.recipe_kind == recipe_kind) {
        return existing.clone();
    }
    ExecutionRecipeTarget {
        recipe_id: format!("{workstream_id}.{recipe_kind}"),
        recipe_kind: recipe_kind.to_string(),
        summary: format!("Follow-on bounded recipe target '{}'.", recipe_kind),
        recovery_points: vec![
            "session_before_follow_on".to_string(),
            "follow_on_plan_materialized".to_string(),
            "follow_on_plan_approved".to_string(),
        ],
    }
}

fn experiment_target_for_task_family(
    task_family: &str,
    existing: Option<&ExecutionExperimentTarget>,
) -> Option<ExecutionExperimentTarget> {
    match normalize_task_family(task_family).as_str() {
        "implementation" | "interactive-editing" => None,
        _ => existing.cloned(),
    }
}

fn expected_outputs_for_task_family(
    task_family: &str,
    experiment_target: Option<&ExecutionExperimentTarget>,
) -> Vec<String> {
    match normalize_task_family(task_family).as_str() {
        "implementation" | "interactive-editing" => vec![
            "tool_return".to_string(),
            "repo_validation".to_string(),
        ],
        "manuscript" => vec![
            "manuscript_update".to_string(),
            "claim_review_note".to_string(),
        ],
        _ => experiment_target
            .map(|target| vec![target.results_doc.clone()])
            .unwrap_or_else(|| vec!["analysis_result".to_string()]),
    }
}

fn success_criteria_for_task_family(task_family: &str) -> Vec<PlanAcceptanceCriterion> {
    let normalized = normalize_task_family(task_family);
    vec![PlanAcceptanceCriterion {
        criteria_version: crate::execution_plan::PLAN_ACCEPTANCE_CRITERIA_VERSION.to_string(),
        criterion_id: format!("{normalized}-follow-on-success"),
        description: format!("bounded follow-on {} plan completes with operator visibility", normalized),
        success_signal: "bounded-result-linked".to_string(),
        stop_condition: "operator stop".to_string(),
        operator_visibility_required: true,
    }]
}

fn stop_conditions_for_follow_on(task_family: &str) -> Vec<String> {
    vec![
        "operator stop".to_string(),
        format!(
            "review contradiction before rerun task_family={}",
            normalize_task_family(task_family)
        ),
    ]
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
    use crate::review_decision::ReviewDecisionEditPatch;

    fn source_plan() -> ExecutionPlan {
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
            selected_specialization: "Operator analysis".to_string(),
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
                summary: "cpu".to_string(),
                recovery_points: vec![],
            }),
            experiment_target: Some(ExecutionExperimentTarget {
                experiment_id: "beagle_exp_002_hrv_aware_vs_blind".to_string(),
                campaign_id: "expedition-002-hrv-aware".to_string(),
                spec_doc: "spec.md".to_string(),
                results_doc: "results.md".to_string(),
                live_batch_id: "batch-1".to_string(),
            }),
            expected_outputs: vec!["results.md".to_string()],
            success_criteria: vec![],
            stop_conditions: vec!["operator stop".to_string()],
            context_packet_ref: "/context".to_string(),
            program_context_packet_ref: Some("/program".to_string()),
            workspace_subagent_route_path: "/route".to_string(),
            workspace_subagent_handoff_path: "/handoff".to_string(),
            tool_launch_path: "/tool".to_string(),
            compiled_context_top_memory_ids: vec!["memory-1".to_string()],
            compiled_context_preview: Some("analysis".to_string()),
            operator_execution_state: "operator-visible-bounded".to_string(),
            note: "analysis".to_string(),
        }
    }

    fn inbox() -> ReviewInboxItem {
        ReviewInboxItem {
            inbox_version: "beagle-review-inbox-item-v1".to_string(),
            inbox_item_id: "execution-1-review".to_string(),
            execution_id: "execution-1".to_string(),
            plan_id: "plan-analysis".to_string(),
            workstream_id: "beagle-darwin-hpc-governance".to_string(),
            workspace_id: "beagle-cluster-pilot".to_string(),
            session_id: "ws-cluster-workspace-habitat".to_string(),
            reflection_id: Some("execution-1-reflection".to_string()),
            trajectory_eval_id: Some("execution-1-trajectory".to_string()),
            replan_suggestion_id: "execution-1-replan".to_string(),
            requested_operator_action: "review-and-approve-follow-on-plan".to_string(),
            replan_required: false,
            inbox_state: "pending-review".to_string(),
            created_by: "beagle-operator".to_string(),
            created_at: Utc::now(),
            create_note: "materialize".to_string(),
            suggested_task_family: "analysis".to_string(),
            suggested_subagent_id: "experiments".to_string(),
            suggested_retrieval_query_type: "general".to_string(),
            suggested_compiler_profile_id: "b235-budget-analysis".to_string(),
            suggested_graphrag_query_mode: "global".to_string(),
            suggested_temporal_truth_view: "both".to_string(),
            suggested_recipe_kind: Some("operator_cpu_loop".to_string()),
            suggested_changes: vec![],
            rationale: "keep lane".to_string(),
            autonomy_policy_id: None,
            risk_evaluation_id: None,
            approval_gating_decision_id: None,
            approval_gating_decision_class: None,
            review_decision_path: "/decision".to_string(),
            follow_on_plan_path: "/follow-on".to_string(),
            autonomy_policy_path: None,
            risk_evaluation_path: None,
            approval_gating_decision_path: None,
            note: "note".to_string(),
        }
    }

    fn replan() -> ReplanSuggestion {
        ReplanSuggestion {
            suggestion_version: "beagle-replan-suggestion-v1".to_string(),
            suggestion_id: "execution-1-replan".to_string(),
            execution_id: "execution-1".to_string(),
            plan_id: "plan-analysis".to_string(),
            workstream_id: "beagle-darwin-hpc-governance".to_string(),
            workspace_id: "beagle-cluster-pilot".to_string(),
            session_id: "ws-cluster-workspace-habitat".to_string(),
            evaluation_mode: "bounded-adaptive-replan".to_string(),
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
            suggested_changes: vec!["keep lane".to_string()],
            rationale: "keep lane".to_string(),
            note: "note".to_string(),
        }
    }

    #[test]
    fn follow_on_plan_edit_patch_can_shift_task_family_and_lane() {
        let follow_on = build_follow_on_plan(
            &source_plan(),
            &inbox(),
            &replan(),
            "edited",
            "beagle-operator",
            Some(&ReviewDecisionEditPatch {
                task_family: Some("implementation".to_string()),
                selected_subagent_id: Some("core".to_string()),
                retrieval_query_type: Some("code".to_string()),
                compiler_profile_id: Some("b235-budget-implementation".to_string()),
                graphrag_query_mode: Some("local".to_string()),
                temporal_truth_view: Some("current".to_string()),
                recipe_kind: Some("repo_native_dev_loop".to_string()),
            }),
        );

        assert_eq!(follow_on.execution_plan.task_family, "implementation");
        assert_eq!(follow_on.execution_plan.tool_id, "codex");
        assert_eq!(follow_on.execution_plan.selected_subagent_id, "core");
        assert_eq!(follow_on.execution_plan.retrieval_query_type, "code");
        assert_eq!(follow_on.execution_plan.dense_backend, "voyage-code-3");
        assert_eq!(follow_on.execution_plan.graphrag_query_mode, "local");
        assert_eq!(follow_on.execution_plan.temporal_truth_view, "current");
        assert_eq!(
            follow_on
                .execution_plan
                .recipe_target
                .as_ref()
                .map(|target| target.recipe_kind.as_str()),
            Some("repo_native_dev_loop")
        );
    }
}
