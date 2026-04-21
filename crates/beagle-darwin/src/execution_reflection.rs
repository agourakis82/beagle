use crate::execution_plan::ExecutionPlan;
use crate::execution_state::ExecutionStatePlane;
use crate::trajectory_eval::TrajectoryEval;
use crate::WorkstreamContextPacket;
use serde::{Deserialize, Serialize};

const EXECUTION_REFLECTION_MODE: &str = "deterministic-bounded-reflection";
pub const REVIEW_QUALITY_LABEL_OPERATOR_READY: &str = "operator-ready";
pub const REVIEW_QUALITY_LABEL_NEEDS_EDIT: &str = "needs-edit";
pub const REVIEW_QUALITY_LABEL_REPLAN_REQUIRED: &str = "replan-required";
pub const ALIGNMENT_LABEL_ALIGNED: &str = "aligned";
pub const ALIGNMENT_LABEL_MISALIGNED: &str = "misaligned";
pub const ALIGNMENT_LABEL_INSUFFICIENT_EVIDENCE: &str = "insufficient-evidence";
pub const FIT_LABEL_GOOD: &str = "good-fit";
pub const FIT_LABEL_PARTIAL: &str = "partial-fit";
pub const FIT_LABEL_POOR: &str = "poor-fit";

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
pub struct ExecutionReflection {
    pub reflection_version: String,
    pub reflection_id: String,
    pub trajectory_eval_id: String,
    pub execution_id: String,
    pub plan_id: String,
    pub workstream_id: String,
    pub workspace_id: String,
    pub session_id: String,
    pub task_family: String,
    pub selected_subagent_id: String,
    pub expected_subagent_id: String,
    pub subagent_selection_ok: bool,
    pub compiled_context_sufficient: bool,
    pub compiled_context_reason: String,
    pub acceptance_criteria_met_count: usize,
    pub acceptance_criteria_total: usize,
    pub acceptance_criteria_passed: bool,
    pub evaluation_mode: String,
    pub overall_quality_score: u8,
    pub operator_followup_action: String,
    pub note: String,
}

pub fn build_execution_reflection(
    plan: &ExecutionPlan,
    state: &ExecutionStatePlane,
    context_packet: &WorkstreamContextPacket,
    trajectory_eval: &TrajectoryEval,
) -> ExecutionReflection {
    let expected_subagent_id = expected_subagent_for_task_family(&plan.task_family).to_string();
    let subagent_selection_ok = plan.selected_subagent_id == expected_subagent_id;
    let compiled_context_reason = compiled_context_reason(plan, context_packet, trajectory_eval);
    let acceptance_criteria_passed =
        trajectory_eval.acceptance_criteria_met_count == trajectory_eval.acceptance_criteria_total;
    let overall_quality_score = compute_overall_quality_score(
        subagent_selection_ok,
        trajectory_eval.compiled_context_sufficient,
        acceptance_criteria_passed,
        trajectory_eval.trajectory_score,
    );
    let operator_followup_action = if state.current_state == "succeeded" && overall_quality_score >= 85 {
        "review-and-approve-next-plan"
    } else if state.current_state == "succeeded" {
        "edit-and-reapprove-next-plan"
    } else {
        "review-stop-and-replan"
    }
    .to_string();

    ExecutionReflection {
        reflection_version: crate::execution_state::EXECUTION_REFLECTION_VERSION.to_string(),
        reflection_id: format!("{}-reflection", state.execution_id),
        trajectory_eval_id: trajectory_eval.trajectory_eval_id.clone(),
        execution_id: state.execution_id.clone(),
        plan_id: plan.plan_id.clone(),
        workstream_id: plan.workstream_id.clone(),
        workspace_id: plan.workspace_id.clone(),
        session_id: plan.session_id.clone(),
        task_family: plan.task_family.clone(),
        selected_subagent_id: plan.selected_subagent_id.clone(),
        expected_subagent_id,
        subagent_selection_ok,
        compiled_context_sufficient: trajectory_eval.compiled_context_sufficient,
        compiled_context_reason,
        acceptance_criteria_met_count: trajectory_eval.acceptance_criteria_met_count,
        acceptance_criteria_total: trajectory_eval.acceptance_criteria_total,
        acceptance_criteria_passed,
        evaluation_mode: EXECUTION_REFLECTION_MODE.to_string(),
        overall_quality_score,
        operator_followup_action,
        note: "B24.3 reflection keeps execution evaluation bounded: compare chosen subagent and compiled context against the canonical task family, score the run, and surface the next operator-visible action without auto-executing it.".to_string(),
    }
}

pub fn execution_outcome_alignment_label_from_observation(
    observed_alignment: Option<bool>,
) -> String {
    match observed_alignment {
        Some(true) => ALIGNMENT_LABEL_ALIGNED.to_string(),
        Some(false) => ALIGNMENT_LABEL_MISALIGNED.to_string(),
        None => ALIGNMENT_LABEL_INSUFFICIENT_EVIDENCE.to_string(),
    }
}

pub fn review_quality_label(reflection: Option<&ExecutionReflection>) -> String {
    let Some(reflection) = reflection else {
        return REVIEW_QUALITY_LABEL_REPLAN_REQUIRED.to_string();
    };
    if reflection.acceptance_criteria_passed
        && reflection.compiled_context_sufficient
        && reflection.overall_quality_score >= 85
        && reflection.operator_followup_action == "review-and-approve-next-plan"
    {
        REVIEW_QUALITY_LABEL_OPERATOR_READY.to_string()
    } else if reflection.operator_followup_action == "review-stop-and-replan"
        || reflection.overall_quality_score < 60
    {
        REVIEW_QUALITY_LABEL_REPLAN_REQUIRED.to_string()
    } else {
        REVIEW_QUALITY_LABEL_NEEDS_EDIT.to_string()
    }
}

pub fn fit_label(full_match: bool, partial_match: bool) -> String {
    if full_match {
        FIT_LABEL_GOOD.to_string()
    } else if partial_match {
        FIT_LABEL_PARTIAL.to_string()
    } else {
        FIT_LABEL_POOR.to_string()
    }
}

pub fn editorial_acceptance_fit_label(
    reflection: Option<&ExecutionReflection>,
    task_family: &str,
    selected_subagent_id: &str,
) -> String {
    let Some(reflection) = reflection else {
        return FIT_LABEL_POOR.to_string();
    };
    if reflection.operator_followup_action == "review-stop-and-replan"
        || reflection.overall_quality_score < 60
    {
        return FIT_LABEL_POOR.to_string();
    }
    if reflection.acceptance_criteria_passed
        && reflection.compiled_context_sufficient
        && reflection.overall_quality_score >= 85
        && task_family == "manuscript"
        && selected_subagent_id == "manuscript"
    {
        FIT_LABEL_GOOD.to_string()
    } else {
        FIT_LABEL_PARTIAL.to_string()
    }
}

fn expected_subagent_for_task_family(task_family: &str) -> &'static str {
    match task_family.trim().to_ascii_lowercase().as_str() {
        "implementation" | "interactive-editing" => "core",
        "manuscript" => "manuscript",
        _ => "experiments",
    }
}

fn compiled_context_reason(
    plan: &ExecutionPlan,
    context_packet: &WorkstreamContextPacket,
    trajectory_eval: &TrajectoryEval,
) -> String {
    let contradiction_count = context_packet
        .retrieval_context
        .as_ref()
        .map(|context| context.temporal_contradiction_count)
        .unwrap_or_default();
    if trajectory_eval.compiled_context_sufficient {
        format!(
            "Compiled context stayed sufficient for task_family={} with {} top memory ids and {} temporal contradictions still carried explicitly.",
            plan.task_family,
            plan.compiled_context_top_memory_ids.len(),
            contradiction_count
        )
    } else {
        format!(
            "Compiled context was thin for task_family={} and should be reviewed before the next bounded plan.",
            plan.task_family
        )
    }
}

fn compute_overall_quality_score(
    subagent_selection_ok: bool,
    compiled_context_sufficient: bool,
    acceptance_criteria_passed: bool,
    trajectory_score: u8,
) -> u8 {
    let trajectory_component = ((trajectory_score as u16 * 40) / 100) as u8;
    let subagent_component = if subagent_selection_ok { 25 } else { 0 };
    let criteria_component = if acceptance_criteria_passed { 20 } else { 0 };
    let context_component = if compiled_context_sufficient { 15 } else { 0 };
    trajectory_component + subagent_component + criteria_component + context_component
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::execution_plan::{ExecutionExperimentTarget, ExecutionRecipeTarget, PlanAcceptanceCriterion};
    use crate::execution_state::{ExecutionResultLink, ExecutionResultLinksDocument, ExecutionStatePlane, ExecutionStateTransition};
    use crate::trajectory_eval::build_trajectory_eval;
    use crate::{
        WorkstreamContextPacket, WorkstreamContextPacketExperimentFlags,
        WorkstreamContextPacketHandoff, WorkstreamContextPacketLastResult,
        WorkstreamContextPacketMemoryHit, WorkstreamContextPacketRetrievalContext,
        WorkstreamContextPacketRetrievalFilters,
    };
    use chrono::Utc;

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
                snippet: "analysis".to_string(),
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
            selected_memory_tiers: vec!["semantic".to_string(), "episodic".to_string()],
            recipe_target: Some(ExecutionRecipeTarget {
                recipe_id: "recipe".to_string(),
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
            success_criteria: vec![PlanAcceptanceCriterion {
                criteria_version: "beagle-plan-acceptance-criteria-v1".to_string(),
                criterion_id: "analysis".to_string(),
                description: "analysis".to_string(),
                success_signal: "results".to_string(),
                stop_condition: "stop".to_string(),
                operator_visibility_required: true,
            }],
            stop_conditions: vec!["stop".to_string()],
            context_packet_ref: "/context".to_string(),
            program_context_packet_ref: Some("/program".to_string()),
            workspace_subagent_route_path: "/route".to_string(),
            workspace_subagent_handoff_path: "/handoff".to_string(),
            tool_launch_path: "/tool".to_string(),
            compiled_context_top_memory_ids: vec!["memory-1".to_string(), "memory-2".to_string()],
            compiled_context_preview: Some("analysis".to_string()),
            operator_execution_state: "operator-visible-bounded".to_string(),
            note: "note".to_string(),
        }
    }

    fn state() -> ExecutionStatePlane {
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
            recipe_id: Some("recipe".to_string()),
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
                .map(|idx| ExecutionResultLink {
                    link_id: format!("link-{idx}"),
                    link_kind: "artifact".to_string(),
                    path: format!("/artifact/{idx}"),
                    summary: "artifact".to_string(),
                })
                .collect(),
            note: "links".to_string(),
        }
    }

    #[test]
    fn execution_reflection_scores_succeeded_analysis_as_operator_visible() {
        let trajectory = build_trajectory_eval(&plan(), &state(), &result_links(), &packet());
        let reflection = build_execution_reflection(&plan(), &state(), &packet(), &trajectory);

        assert!(reflection.subagent_selection_ok);
        assert!(reflection.compiled_context_sufficient);
        assert!(reflection.acceptance_criteria_passed);
        assert!(reflection.overall_quality_score >= 85);
        assert_eq!(reflection.operator_followup_action, "review-and-approve-next-plan");
    }

    #[test]
    fn editorial_acceptance_fit_requires_manuscript_lane() {
        let trajectory = build_trajectory_eval(&plan(), &state(), &result_links(), &packet());
        let reflection = build_execution_reflection(&plan(), &state(), &packet(), &trajectory);

        assert_eq!(
            editorial_acceptance_fit_label(Some(&reflection), "analysis", "experiments"),
            FIT_LABEL_PARTIAL
        );
        assert_eq!(
            editorial_acceptance_fit_label(Some(&reflection), "manuscript", "manuscript"),
            FIT_LABEL_GOOD
        );
    }
}
