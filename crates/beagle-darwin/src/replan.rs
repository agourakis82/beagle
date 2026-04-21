use crate::execution_plan::ExecutionPlan;
use crate::execution_reflection::ExecutionReflection;
use crate::trajectory_eval::TrajectoryEval;
use crate::WorkstreamContextPacket;
use serde::{Deserialize, Serialize};

const REPLAN_EVALUATION_MODE: &str = "bounded-adaptive-replan";

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
pub struct ReplanSuggestion {
    pub suggestion_version: String,
    pub suggestion_id: String,
    pub execution_id: String,
    pub plan_id: String,
    pub workstream_id: String,
    pub workspace_id: String,
    pub session_id: String,
    pub evaluation_mode: String,
    pub replan_required: bool,
    pub request_operator_review: bool,
    pub request_operator_approval_again: bool,
    pub requested_operator_action: String,
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
    pub note: String,
}

pub fn build_replan_suggestion(
    plan: &ExecutionPlan,
    context_packet: &WorkstreamContextPacket,
    trajectory_eval: &TrajectoryEval,
    reflection: &ExecutionReflection,
) -> ReplanSuggestion {
    let contradiction_count = context_packet
        .retrieval_context
        .as_ref()
        .map(|context| context.temporal_contradiction_count)
        .unwrap_or_default();
    let replan_required = !reflection.subagent_selection_ok
        || !trajectory_eval.lifecycle_match
        || !trajectory_eval.compiled_context_sufficient
        || !reflection.acceptance_criteria_passed;
    let requested_operator_action = if replan_required {
        "edit-and-reapprove-plan"
    } else {
        "review-and-approve-follow-on-plan"
    }
    .to_string();
    let suggested_temporal_truth_view = if contradiction_count > 0 {
        "both".to_string()
    } else {
        plan.temporal_truth_view.clone()
    };
    let suggested_changes = suggested_changes(
        plan,
        reflection,
        trajectory_eval,
        contradiction_count,
        replan_required,
    );

    ReplanSuggestion {
        suggestion_version: crate::execution_state::REPLAN_SUGGESTION_VERSION.to_string(),
        suggestion_id: format!("{}-replan", reflection.execution_id),
        execution_id: reflection.execution_id.clone(),
        plan_id: plan.plan_id.clone(),
        workstream_id: plan.workstream_id.clone(),
        workspace_id: plan.workspace_id.clone(),
        session_id: plan.session_id.clone(),
        evaluation_mode: REPLAN_EVALUATION_MODE.to_string(),
        replan_required,
        request_operator_review: true,
        request_operator_approval_again: true,
        requested_operator_action,
        suggested_task_family: plan.task_family.clone(),
        suggested_subagent_id: if reflection.subagent_selection_ok {
            plan.selected_subagent_id.clone()
        } else {
            reflection.expected_subagent_id.clone()
        },
        suggested_retrieval_query_type: plan.retrieval_query_type.clone(),
        suggested_compiler_profile_id: plan.compiler_profile_id.clone(),
        suggested_graphrag_query_mode: plan.graphrag_query_mode.clone(),
        suggested_temporal_truth_view,
        suggested_recipe_kind: plan
            .recipe_target
            .as_ref()
            .map(|recipe| recipe.recipe_kind.clone()),
        rationale: rationale(plan, reflection, trajectory_eval, contradiction_count, replan_required),
        suggested_changes,
        note: "B24.3 adaptive replanning stays bounded and operator-facing: emit the next-plan guidance, but require explicit human approval before any new execution begins.".to_string(),
    }
}

fn suggested_changes(
    plan: &ExecutionPlan,
    reflection: &ExecutionReflection,
    trajectory_eval: &TrajectoryEval,
    contradiction_count: usize,
    replan_required: bool,
) -> Vec<String> {
    let mut changes = Vec::new();
    if !reflection.subagent_selection_ok {
        changes.push(format!(
            "Realign subagent from '{}' to '{}'.",
            plan.selected_subagent_id, reflection.expected_subagent_id
        ));
    }
    if !trajectory_eval.compiled_context_sufficient {
        changes.push(format!(
            "Increase compiled-context coverage before rerunning task_family='{}'.",
            plan.task_family
        ));
    }
    if !trajectory_eval.lifecycle_match {
        changes.push("Review trajectory mismatch before any rerun.".to_string());
    }
    if contradiction_count > 0 {
        changes.push(format!(
            "Keep temporal_truth_view='both' while {} contradiction(s) remain explicit.",
            contradiction_count
        ));
    }
    if !replan_required {
        changes.push(format!(
            "Preserve subagent='{}', retrieval='{}', compiler='{}', and graphrag='{}' for the next bounded cycle.",
            plan.selected_subagent_id,
            plan.retrieval_query_type,
            plan.compiler_profile_id,
            plan.graphrag_query_mode
        ));
    }
    changes.push("Request operator approval again before any follow-on plan starts.".to_string());
    changes
}

fn rationale(
    plan: &ExecutionPlan,
    reflection: &ExecutionReflection,
    trajectory_eval: &TrajectoryEval,
    contradiction_count: usize,
    replan_required: bool,
) -> String {
    if replan_required {
        format!(
            "Execution finished with quality_score={} and trajectory_quality='{}'; replan before rerun task_family='{}'.",
            reflection.overall_quality_score, trajectory_eval.trajectory_quality, plan.task_family
        )
    } else {
        format!(
            "Execution stayed bounded-good with quality_score={} and trajectory_quality='{}'; carry the same lane forward under operator approval, keeping {} contradiction(s) visible.",
            reflection.overall_quality_score, trajectory_eval.trajectory_quality, contradiction_count
        )
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::execution_reflection::ExecutionReflection;
    use crate::trajectory_eval::{TrajectoryCriterionEval, TrajectoryEval};
    use crate::{
        WorkstreamContextPacket, WorkstreamContextPacketExperimentFlags,
        WorkstreamContextPacketHandoff, WorkstreamContextPacketLastResult,
        WorkstreamContextPacketRetrievalContext, WorkstreamContextPacketRetrievalFilters,
    };

    fn plan() -> ExecutionPlan {
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
            selected_role_tag: "analysis".to_string(),
            selected_specialization: "analysis".to_string(),
            retrieval_query_type: "general".to_string(),
            dense_backend: "voyage-4-large".to_string(),
            sparse_backend: "local-lexical".to_string(),
            compiler_profile_id: "b235-budget-analysis".to_string(),
            graphrag_query_mode: "global".to_string(),
            temporal_truth_view: "both".to_string(),
            selected_memory_tiers: vec!["semantic".to_string()],
            recipe_target: Some(crate::ExecutionRecipeTarget {
                recipe_id: "recipe".to_string(),
                recipe_kind: "operator_cpu_loop".to_string(),
                summary: "cpu".to_string(),
                recovery_points: vec![],
            }),
            experiment_target: Some(crate::ExecutionExperimentTarget {
                experiment_id: "beagle_exp_002_hrv_aware_vs_blind".to_string(),
                campaign_id: "expedition-002-hrv-aware".to_string(),
                spec_doc: "spec.md".to_string(),
                results_doc: "results.md".to_string(),
                live_batch_id: "batch-1".to_string(),
            }),
            expected_outputs: vec!["results.md".to_string()],
            success_criteria: vec![],
            stop_conditions: vec![],
            context_packet_ref: "/context".to_string(),
            program_context_packet_ref: Some("/program".to_string()),
            workspace_subagent_route_path: "/route".to_string(),
            workspace_subagent_handoff_path: "/handoff".to_string(),
            tool_launch_path: "/tool".to_string(),
            compiled_context_top_memory_ids: vec!["memory-1".to_string(), "memory-2".to_string()],
            compiled_context_preview: Some("analysis".to_string()),
            operator_execution_state: "operator-visible-bounded".to_string(),
            note: "analysis".to_string(),
        }
    }

    fn packet() -> WorkstreamContextPacket {
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
            memory_hits: vec![],
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
                graphrag_query_mode: Some("global".to_string()),
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
                compiled_context_preview: Some("analysis".to_string()),
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
                suggested_subagent_id: Some("experiments".to_string()),
                suggested_work_mode: Some("analysis".to_string()),
                influence_reason: "analysis".to_string(),
            }),
            recommended_recipe: None,
            bounded_study_baseline: None,
        }
    }

    fn trajectory() -> TrajectoryEval {
        TrajectoryEval {
            trajectory_eval_version: "beagle-trajectory-eval-v1".to_string(),
            trajectory_eval_id: "execution-1-trajectory".to_string(),
            execution_id: "execution-1".to_string(),
            plan_id: "plan-analysis".to_string(),
            workstream_id: "beagle-darwin-hpc-governance".to_string(),
            workspace_id: "beagle-cluster-pilot".to_string(),
            session_id: "ws-cluster-workspace-habitat".to_string(),
            evaluation_mode: "deterministic-trajectory-match".to_string(),
            expected_states: vec!["planned".to_string(), "approved".to_string(), "running".to_string(), "succeeded".to_string()],
            observed_states: vec!["planned".to_string(), "approved".to_string(), "running".to_string(), "succeeded".to_string()],
            lifecycle_match: true,
            acceptance_criteria_met_count: 1,
            acceptance_criteria_total: 1,
            result_link_count: 8,
            compiled_context_memory_hit_count: 2,
            compiled_context_sufficient: true,
            context_usefulness: "sufficient".to_string(),
            trajectory_quality: "good".to_string(),
            trajectory_score: 90,
            criteria: vec![TrajectoryCriterionEval {
                criterion_id: "analysis".to_string(),
                met: true,
                success_signal: "results".to_string(),
                stop_condition: "stop".to_string(),
                note: "met".to_string(),
            }],
            note: "trajectory".to_string(),
        }
    }

    fn reflection() -> ExecutionReflection {
        ExecutionReflection {
            reflection_version: "beagle-execution-reflection-v1".to_string(),
            reflection_id: "execution-1-reflection".to_string(),
            trajectory_eval_id: "execution-1-trajectory".to_string(),
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
            compiled_context_reason: "sufficient".to_string(),
            acceptance_criteria_met_count: 1,
            acceptance_criteria_total: 1,
            acceptance_criteria_passed: true,
            evaluation_mode: "deterministic-bounded-reflection".to_string(),
            overall_quality_score: 96,
            operator_followup_action: "review-and-approve-next-plan".to_string(),
            note: "reflection".to_string(),
        }
    }

    #[test]
    fn replan_suggestion_requests_operator_review_for_next_plan() {
        let suggestion = build_replan_suggestion(&plan(), &packet(), &trajectory(), &reflection());

        assert!(!suggestion.replan_required);
        assert!(suggestion.request_operator_review);
        assert!(suggestion.request_operator_approval_again);
        assert_eq!(
            suggestion.requested_operator_action,
            "review-and-approve-follow-on-plan"
        );
        assert_eq!(suggestion.suggested_subagent_id, "experiments");
        assert_eq!(suggestion.suggested_temporal_truth_view, "both");
        assert!(
            suggestion
                .suggested_changes
                .iter()
                .any(|value| value.contains("operator approval again"))
        );
    }
}
