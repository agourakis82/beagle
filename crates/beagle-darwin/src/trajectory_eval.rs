use crate::execution_plan::{ExecutionPlan, PlanAcceptanceCriterion};
use crate::execution_state::{ExecutionResultLinksDocument, ExecutionStatePlane};
use crate::WorkstreamContextPacket;
use serde::{Deserialize, Serialize};

const TRAJECTORY_EVAL_MODE: &str = "deterministic-trajectory-match";
pub const MANUSCRIPT_TRAJECTORY_QUALITY_READY: &str = "manuscript-ready";
pub const MANUSCRIPT_TRAJECTORY_QUALITY_SHADOW_TUNING_REQUIRED: &str =
    "shadow-tuning-required";
pub const MANUSCRIPT_TRAJECTORY_QUALITY_NEEDS_REPLAN: &str = "needs-replan";

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
pub struct TrajectoryCriterionEval {
    pub criterion_id: String,
    pub met: bool,
    pub success_signal: String,
    pub stop_condition: String,
    pub note: String,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
pub struct TrajectoryEval {
    pub trajectory_eval_version: String,
    pub trajectory_eval_id: String,
    pub execution_id: String,
    pub plan_id: String,
    pub workstream_id: String,
    pub workspace_id: String,
    pub session_id: String,
    pub evaluation_mode: String,
    pub expected_states: Vec<String>,
    pub observed_states: Vec<String>,
    pub lifecycle_match: bool,
    pub acceptance_criteria_met_count: usize,
    pub acceptance_criteria_total: usize,
    pub result_link_count: usize,
    pub compiled_context_memory_hit_count: usize,
    pub compiled_context_sufficient: bool,
    pub context_usefulness: String,
    pub trajectory_quality: String,
    pub trajectory_score: u8,
    pub criteria: Vec<TrajectoryCriterionEval>,
    pub note: String,
}

pub fn build_trajectory_eval(
    plan: &ExecutionPlan,
    state: &ExecutionStatePlane,
    result_links: &ExecutionResultLinksDocument,
    context_packet: &WorkstreamContextPacket,
) -> TrajectoryEval {
    let expected_states = expected_states_for_final_state(&state.current_state);
    let observed_states = state
        .state_transitions
        .iter()
        .map(|transition| transition.state.clone())
        .collect::<Vec<_>>();
    let lifecycle_match = observed_states == expected_states;
    let criteria = evaluate_acceptance_criteria(&plan.success_criteria, &state.current_state);
    let acceptance_criteria_met_count = criteria.iter().filter(|criterion| criterion.met).count();
    let acceptance_criteria_total = criteria.len();
    let compiled_context_memory_hit_count = compiled_context_memory_hit_count(plan, context_packet);
    let compiled_context_sufficient =
        compiled_context_memory_hit_count >= minimum_context_hits(&plan.task_family);
    let context_usefulness = if compiled_context_sufficient {
        "sufficient"
    } else if compiled_context_memory_hit_count > 0 {
        "thin"
    } else {
        "insufficient"
    }
    .to_string();
    let trajectory_score = compute_trajectory_score(
        lifecycle_match,
        acceptance_criteria_met_count,
        acceptance_criteria_total,
        result_links.links.len(),
        compiled_context_sufficient,
    );
    let trajectory_quality = if trajectory_score >= 90 {
        "good"
    } else if trajectory_score >= 70 {
        "adequate"
    } else {
        "needs-replan"
    }
    .to_string();

    TrajectoryEval {
        trajectory_eval_version: crate::execution_state::TRAJECTORY_EVAL_VERSION.to_string(),
        trajectory_eval_id: format!("{}-trajectory", state.execution_id),
        execution_id: state.execution_id.clone(),
        plan_id: plan.plan_id.clone(),
        workstream_id: plan.workstream_id.clone(),
        workspace_id: plan.workspace_id.clone(),
        session_id: plan.session_id.clone(),
        evaluation_mode: TRAJECTORY_EVAL_MODE.to_string(),
        expected_states,
        observed_states,
        lifecycle_match,
        acceptance_criteria_met_count,
        acceptance_criteria_total,
        result_link_count: result_links.links.len(),
        compiled_context_memory_hit_count,
        compiled_context_sufficient,
        context_usefulness,
        trajectory_quality,
        trajectory_score,
        criteria,
        note: "B24.3 keeps trajectory evaluation bounded and auditable: compare the observed lifecycle with the expected bounded execution path, score acceptance-criteria closure, and avoid turning this into an autonomous controller.".to_string(),
    }
}

pub fn manuscript_trajectory_uplift_label(
    trajectory_eval: &TrajectoryEval,
    task_family: &str,
    selected_subagent_id: &str,
) -> String {
    if trajectory_eval.trajectory_quality == "needs-replan"
        || !trajectory_eval.compiled_context_sufficient
    {
        return MANUSCRIPT_TRAJECTORY_QUALITY_NEEDS_REPLAN.to_string();
    }
    if task_family == "manuscript"
        && selected_subagent_id == "manuscript"
        && trajectory_eval.trajectory_quality == "good"
    {
        MANUSCRIPT_TRAJECTORY_QUALITY_READY.to_string()
    } else {
        MANUSCRIPT_TRAJECTORY_QUALITY_SHADOW_TUNING_REQUIRED.to_string()
    }
}

fn evaluate_acceptance_criteria(
    criteria: &[PlanAcceptanceCriterion],
    current_state: &str,
) -> Vec<TrajectoryCriterionEval> {
    criteria
        .iter()
        .map(|criterion| {
            let met = current_state == "succeeded";
            TrajectoryCriterionEval {
                criterion_id: criterion.criterion_id.clone(),
                met,
                success_signal: criterion.success_signal.clone(),
                stop_condition: criterion.stop_condition.clone(),
                note: if met {
                    format!(
                        "Succeeded execution is treated as satisfying the bounded acceptance signal '{}'.",
                        criterion.success_signal
                    )
                } else {
                    format!(
                        "Execution finished as '{}', so the bounded acceptance signal '{}' still needs operator review.",
                        current_state, criterion.success_signal
                    )
                },
            }
        })
        .collect()
}

fn expected_states_for_final_state(current_state: &str) -> Vec<String> {
    match current_state {
        "stopped" => vec![
            "planned".to_string(),
            "approved".to_string(),
            "stopped".to_string(),
        ],
        "failed" => vec![
            "planned".to_string(),
            "approved".to_string(),
            "running".to_string(),
            "failed".to_string(),
        ],
        _ => vec![
            "planned".to_string(),
            "approved".to_string(),
            "running".to_string(),
            "succeeded".to_string(),
        ],
    }
}

fn compiled_context_memory_hit_count(
    plan: &ExecutionPlan,
    context_packet: &WorkstreamContextPacket,
) -> usize {
    let from_plan = plan.compiled_context_top_memory_ids.len();
    let from_packet = context_packet
        .retrieval_context
        .as_ref()
        .map(|context| context.compiled_context_top_memory_ids.len())
        .unwrap_or_default();
    from_plan.max(from_packet)
}

fn minimum_context_hits(task_family: &str) -> usize {
    match task_family.trim().to_ascii_lowercase().as_str() {
        "implementation" | "interactive-editing" => 1,
        "analysis" => 2,
        "manuscript" => 3,
        _ => 1,
    }
}

fn compute_trajectory_score(
    lifecycle_match: bool,
    acceptance_criteria_met_count: usize,
    acceptance_criteria_total: usize,
    result_link_count: usize,
    compiled_context_sufficient: bool,
) -> u8 {
    let lifecycle_score = if lifecycle_match { 40 } else { 20 };
    let criteria_score = if acceptance_criteria_total == 0 {
        20
    } else {
        ((20 * acceptance_criteria_met_count) / acceptance_criteria_total) as u8
    };
    let result_link_score = ((20 * result_link_count.min(8)) / 8) as u8;
    let context_score = if compiled_context_sufficient { 20 } else { 0 };
    lifecycle_score + criteria_score + result_link_score + context_score
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::execution_plan::{ExecutionExperimentTarget, ExecutionRecipeTarget};
    use crate::execution_state::ExecutionStateTransition;
    use crate::{
        WorkstreamContextPacket, WorkstreamContextPacketExperimentFlags,
        WorkstreamContextPacketHandoff, WorkstreamContextPacketLastResult,
        WorkstreamContextPacketMemoryHit, WorkstreamContextPacketRetrievalContext,
        WorkstreamContextPacketRetrievalFilters,
    };
    use chrono::Utc;

    fn analysis_plan() -> ExecutionPlan {
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
            selected_role_tag: "experiments-analysis".to_string(),
            selected_specialization: "analysis".to_string(),
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
                summary: "cpu loop".to_string(),
                recovery_points: vec!["submitted_job".to_string()],
            }),
            experiment_target: Some(ExecutionExperimentTarget {
                experiment_id: "beagle_exp_002_hrv_aware_vs_blind".to_string(),
                campaign_id: "expedition-002-hrv-aware".to_string(),
                spec_doc: "spec.md".to_string(),
                results_doc: "results.md".to_string(),
                live_batch_id: "batch-1".to_string(),
            }),
            expected_outputs: vec!["results.md".to_string()],
            success_criteria: vec![PlanAcceptanceCriterion {
                criteria_version: "beagle-plan-acceptance-criteria-v1".to_string(),
                criterion_id: "analysis-complete".to_string(),
                description: "analysis completes".to_string(),
                success_signal: "results published".to_string(),
                stop_condition: "operator stop".to_string(),
                operator_visibility_required: true,
            }],
            stop_conditions: vec!["operator stop".to_string()],
            context_packet_ref: "/api/darwin/workstreams/beagle-darwin-hpc-governance/context-packet".to_string(),
            program_context_packet_ref: Some("/api/darwin/programs/beagle-physio-symbolic-exocortex/context-packet".to_string()),
            workspace_subagent_route_path: "/route".to_string(),
            workspace_subagent_handoff_path: "/handoff".to_string(),
            tool_launch_path: "/tool".to_string(),
            compiled_context_top_memory_ids: vec!["memory-1".to_string(), "memory-2".to_string()],
            compiled_context_preview: Some("analysis preview".to_string()),
            operator_execution_state: "operator-visible-bounded".to_string(),
            note: "analysis".to_string(),
        }
    }

    fn execution_state() -> ExecutionStatePlane {
        let now = Utc::now();
        ExecutionStatePlane {
            state_version: "beagle-plan-execution-state-v1".to_string(),
            execution_id: "execution-1".to_string(),
            planner_policy_id: "b241-intent-planner-policy".to_string(),
            plan_id: "plan-analysis".to_string(),
            workstream_id: "beagle-darwin-hpc-governance".to_string(),
            workspace_id: "beagle-cluster-pilot".to_string(),
            session_id: "ws-cluster-workspace-habitat".to_string(),
            program_id: Some("beagle-physio-symbolic-exocortex".to_string()),
            campaign_id: Some("expedition-002-hrv-aware".to_string()),
            task_family: "analysis".to_string(),
            tool_id: "claude-code".to_string(),
            work_mode: "analysis".to_string(),
            current_state: "succeeded".to_string(),
            selected_subagent_id: "experiments".to_string(),
            retrieval_query_type: "general".to_string(),
            dense_backend: "voyage-4-large".to_string(),
            sparse_backend: "local-lexical".to_string(),
            compiler_profile_id: "b235-budget-analysis".to_string(),
            graphrag_query_mode: "global".to_string(),
            temporal_truth_view: "both".to_string(),
            approved_by: "beagle-operator".to_string(),
            approved_at: now,
            started_at: Some(now),
            finished_at: Some(now),
            stop_requested_at: None,
            stop_reason: None,
            latest_receipt_id: None,
            latest_reflection_id: None,
            latest_trajectory_eval_id: None,
            latest_replan_suggestion_id: None,
            recipe_id: Some("beagle-darwin-hpc-governance.operator_cpu_loop".to_string()),
            recipe_kind: Some("operator_cpu_loop".to_string()),
            experiment_id: Some("beagle_exp_002_hrv_aware_vs_blind".to_string()),
            context_packet_ref: Some("/context".to_string()),
            program_context_packet_ref: Some("/program".to_string()),
            tool_launch_path: "/tool".to_string(),
            workspace_subagent_route_path: "/route".to_string(),
            workspace_subagent_handoff_path: "/handoff".to_string(),
            reflection_path: Some("/reflection".to_string()),
            trajectory_eval_path: Some("/trajectory".to_string()),
            replan_suggestion_path: Some("/replan".to_string()),
            execution_state_path: "/state".to_string(),
            execution_receipt_path: "/receipt".to_string(),
            execution_result_links_path: "/links".to_string(),
            state_transitions: vec![
                ExecutionStateTransition {
                    state: "planned".to_string(),
                    transitioned_at: now,
                    note: "planned".to_string(),
                },
                ExecutionStateTransition {
                    state: "approved".to_string(),
                    transitioned_at: now,
                    note: "approved".to_string(),
                },
                ExecutionStateTransition {
                    state: "running".to_string(),
                    transitioned_at: now,
                    note: "running".to_string(),
                },
                ExecutionStateTransition {
                    state: "succeeded".to_string(),
                    transitioned_at: now,
                    note: "succeeded".to_string(),
                },
            ],
            latest_quality_score: None,
            latest_trajectory_quality: None,
            replan_required: false,
            operator_followup_action: None,
            review_requested: false,
            review_inbox_state: None,
            latest_review_inbox_item_id: None,
            latest_review_decision_id: None,
            latest_review_decision_action: None,
            latest_follow_on_plan_id: None,
            follow_on_plan_available: false,
            latest_autonomy_policy_id: None,
            latest_risk_evaluation_id: None,
            latest_approval_gating_decision_id: None,
            latest_autonomy_calibration_dataset_id: None,
            latest_autonomy_policy_eval_report_id: None,
            latest_escalation_thresholds_id: None,
            latest_shadow_policy_comparison_id: None,
            latest_updated_policy_recommendation_id: None,
            latest_autonomy_policy_current_id: None,
            latest_autonomy_policy_candidate_id: None,
            latest_rollout_metrics_id: None,
            latest_guarded_rollout_decision_id: None,
            approval_gating_decision_class: None,
            approval_gating_risk_level: None,
            approval_gating_dispatch_ready: false,
            approval_gating_blocked: false,
            continuation_dispatched: false,
            latest_continuation_dispatch_id: None,
            latest_continuation_receipt_id: None,
            continuation_current_state: None,
            continuation_source_execution_id: None,
            continuation_next_execution_id: None,
            continuation_next_plan_id: None,
            continuation_review_action: None,
            autonomy_policy_calibration_status: None,
            autonomy_policy_rollout_status: None,
            review_inbox_path: Some("/review-inbox".to_string()),
            review_decision_path: Some("/review-decision".to_string()),
            follow_on_plan_path: Some("/follow-on-plan".to_string()),
            autonomy_policy_path: Some("/autonomy-policy".to_string()),
            risk_evaluation_path: Some("/risk-evaluation".to_string()),
            approval_gating_decision_path: Some("/approval-gating-decision".to_string()),
            autonomy_calibration_dataset_path: Some("/autonomy-calibration-dataset".to_string()),
            autonomy_policy_eval_report_path: Some("/autonomy-policy-eval-report".to_string()),
            escalation_thresholds_path: Some("/escalation-thresholds".to_string()),
            shadow_policy_comparison_path: Some("/shadow-policy-comparison".to_string()),
            updated_policy_recommendation_path: Some("/updated-policy-recommendation".to_string()),
            autonomy_policy_current_path: Some("/autonomy-policy-current".to_string()),
            autonomy_policy_candidate_path: Some("/autonomy-policy-candidate".to_string()),
            rollout_metrics_path: Some("/rollout-metrics".to_string()),
            rollout_decision_path: Some("/guarded-rollout-decision".to_string()),
            continuation_dispatch_path: Some("/continuation-dispatch".to_string()),
            continuation_receipt_path: Some("/continuation-receipt".to_string()),
            continuation_state_path: Some("/continuation-state".to_string()),
            operator_execution_state: "operator-visible-bounded".to_string(),
            note: "state".to_string(),
        }
    }

    fn result_links() -> ExecutionResultLinksDocument {
        ExecutionResultLinksDocument {
            links_version: "beagle-plan-execution-result-links-v1".to_string(),
            execution_id: "execution-1".to_string(),
            plan_id: "plan-analysis".to_string(),
            workstream_id: "beagle-darwin-hpc-governance".to_string(),
            workspace_id: "beagle-cluster-pilot".to_string(),
            session_id: "ws-cluster-workspace-habitat".to_string(),
            links: (0..8)
                .map(|idx| crate::ExecutionResultLink {
                    link_id: format!("link-{idx}"),
                    link_kind: "artifact".to_string(),
                    path: format!("/artifact/{idx}"),
                    summary: "artifact".to_string(),
                })
                .collect(),
            note: "links".to_string(),
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
            memory_hits: vec![WorkstreamContextPacketMemoryHit {
                memory_id: Some("memory-1".to_string()),
                source: "codex".to_string(),
                conversation_id: None,
                turn_index: Some(1),
                role: Some("assistant".to_string()),
                snippet: "analysis memory".to_string(),
                timestamp: None,
                relevance: 1.0,
                tags: vec!["analysis".to_string()],
                domain: Some("darwin-hpc".to_string()),
                physio_snapshot: None,
            }],
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
                hit_count: 1,
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
                compiled_context_selected_memory_tiers: vec![
                    "semantic".to_string(),
                    "episodic".to_string(),
                ],
                compiled_context_source_slices: vec![],
                compiled_context_top_memory_ids: vec![
                    "memory-1".to_string(),
                    "memory-2".to_string(),
                ],
                compiled_context_preview: Some("analysis preview".to_string()),
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

    #[test]
    fn trajectory_eval_matches_canonical_succeeded_path() {
        let eval = build_trajectory_eval(
            &analysis_plan(),
            &execution_state(),
            &result_links(),
            &packet(),
        );

        assert!(eval.lifecycle_match);
        assert_eq!(eval.acceptance_criteria_met_count, 1);
        assert_eq!(eval.acceptance_criteria_total, 1);
        assert!(eval.compiled_context_sufficient);
        assert_eq!(eval.trajectory_quality, "good");
        assert!(eval.trajectory_score >= 90);
    }

    #[test]
    fn manuscript_uplift_label_requires_manuscript_lane() {
        let eval = build_trajectory_eval(
            &analysis_plan(),
            &execution_state(),
            &result_links(),
            &packet(),
        );

        assert_eq!(
            manuscript_trajectory_uplift_label(&eval, "analysis", "experiments"),
            MANUSCRIPT_TRAJECTORY_QUALITY_SHADOW_TUNING_REQUIRED
        );
        assert_eq!(
            manuscript_trajectory_uplift_label(&eval, "manuscript", "manuscript"),
            MANUSCRIPT_TRAJECTORY_QUALITY_READY
        );
    }
}
