use serde::{Deserialize, Serialize};

pub const INTENT_PLAN_VERSION: &str = "beagle-intent-plan-v1";
pub const EXECUTION_PLAN_VERSION: &str = "beagle-execution-plan-v1";
pub const PLAN_ACCEPTANCE_CRITERIA_VERSION: &str = "beagle-plan-acceptance-criteria-v1";
pub const PLANNER_POLICY_VERSION: &str = "beagle-intent-planner-policy-v1";
pub const PLANNER_AVAILABILITY_VERSION: &str = "beagle-intent-planner-availability-v1";

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
pub struct IntentPlan {
    pub intent_version: String,
    pub intent_id: String,
    pub workstream_id: String,
    pub workspace_id: String,
    pub session_id: String,
    #[serde(default)]
    pub program_id: Option<String>,
    #[serde(default)]
    pub campaign_id: Option<String>,
    pub task_family: String,
    pub tool_id: String,
    pub work_mode: String,
    pub intent_text: String,
    pub query_text: String,
    pub operator_execution_state: String,
    pub note: String,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
pub struct PlanAcceptanceCriterion {
    pub criteria_version: String,
    pub criterion_id: String,
    pub description: String,
    pub success_signal: String,
    pub stop_condition: String,
    pub operator_visibility_required: bool,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
pub struct ExecutionRecipeTarget {
    pub recipe_id: String,
    pub recipe_kind: String,
    pub summary: String,
    pub recovery_points: Vec<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
pub struct ExecutionExperimentTarget {
    pub experiment_id: String,
    pub campaign_id: String,
    pub spec_doc: String,
    pub results_doc: String,
    pub live_batch_id: String,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
pub struct PlannerCompiledContextSelection {
    pub task_profile: String,
    pub budget_profile_id: String,
    pub retrieval_query_type: String,
    pub dense_backend: String,
    pub sparse_backend: String,
    pub graphrag_query_mode: String,
    pub temporal_truth_view: String,
    pub selected_memory_tiers: Vec<String>,
    pub top_memory_ids: Vec<String>,
    #[serde(default)]
    pub preview: Option<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
pub struct ExecutionPlan {
    pub plan_version: String,
    pub plan_id: String,
    pub planner_policy_id: String,
    pub workstream_id: String,
    pub workspace_id: String,
    pub session_id: String,
    #[serde(default)]
    pub program_id: Option<String>,
    #[serde(default)]
    pub campaign_id: Option<String>,
    pub task_family: String,
    pub tool_id: String,
    pub work_mode: String,
    pub selected_subagent_id: String,
    pub selected_role_tag: String,
    pub selected_specialization: String,
    pub retrieval_query_type: String,
    pub dense_backend: String,
    pub sparse_backend: String,
    pub compiler_profile_id: String,
    pub graphrag_query_mode: String,
    pub temporal_truth_view: String,
    pub selected_memory_tiers: Vec<String>,
    #[serde(default)]
    pub recipe_target: Option<ExecutionRecipeTarget>,
    #[serde(default)]
    pub experiment_target: Option<ExecutionExperimentTarget>,
    pub expected_outputs: Vec<String>,
    pub success_criteria: Vec<PlanAcceptanceCriterion>,
    pub stop_conditions: Vec<String>,
    pub context_packet_ref: String,
    #[serde(default)]
    pub program_context_packet_ref: Option<String>,
    pub workspace_subagent_route_path: String,
    pub workspace_subagent_handoff_path: String,
    pub tool_launch_path: String,
    pub compiled_context_top_memory_ids: Vec<String>,
    #[serde(default)]
    pub compiled_context_preview: Option<String>,
    pub operator_execution_state: String,
    pub note: String,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
pub struct PlannerPolicyProfile {
    pub task_family: String,
    pub tool_id: String,
    pub work_mode: String,
    pub recommended_subagent_id: String,
    pub retrieval_query_type: String,
    pub compiler_profile_id: String,
    pub graphrag_query_mode: String,
    pub temporal_truth_view: String,
    pub preferred_recipe_kind: String,
    pub compiler_policy_basis_id: String,
    pub current_state: String,
    pub recommended_when: String,
    pub note: String,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
pub struct PlannerPolicy {
    pub policy_version: String,
    pub policy_id: String,
    pub workstream_id: String,
    pub supported_task_families: Vec<String>,
    pub profiles: Vec<PlannerPolicyProfile>,
    pub note: String,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
pub struct IntentPlannerAvailability {
    pub availability_version: String,
    pub planner_policy_id: String,
    pub planner_policy_path: String,
    pub intent_planner_path: String,
    pub supported_task_families: Vec<String>,
    pub task_family_hint: String,
    pub tool_id_hint: String,
    pub work_mode_hint: String,
    pub retrieval_query_type: String,
    pub compiler_profile_id: String,
    pub graphrag_query_mode: String,
    pub temporal_truth_view: String,
    #[serde(default)]
    pub recommended_subagent_id: Option<String>,
    #[serde(default)]
    pub recommended_recipe_id: Option<String>,
    pub operator_execution_state: String,
    pub note: String,
}
