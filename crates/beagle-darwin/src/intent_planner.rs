use crate::execution_plan::{
    ExecutionExperimentTarget, ExecutionPlan, ExecutionRecipeTarget, IntentPlan,
    IntentPlannerAvailability, PlanAcceptanceCriterion, PlannerCompiledContextSelection,
    PlannerPolicy, PlannerPolicyProfile, EXECUTION_PLAN_VERSION, INTENT_PLAN_VERSION,
    PLAN_ACCEPTANCE_CRITERIA_VERSION, PLANNER_AVAILABILITY_VERSION, PLANNER_POLICY_VERSION,
};
use crate::program_context_packet::ProgramCampaignBinding;
use crate::workspace_subagent_routing::WorkspaceSubAgentRouteResponse;
use crate::{WorkstreamContextPacket, WorkstreamControlRoomDetailResponse, WorkstreamRecipeDocument};
use chrono::Utc;
use serde::{Deserialize, Serialize};
use serde_json::Value;
use std::collections::BTreeSet;

const INTENT_PLANNER_PHASE: &str = "B24.1";
const INTENT_PLANNER_API_PREFIX: &str = "/api/darwin/workstreams";
const COMPILER_POLICY_BASIS_ID: &str = "b236-evidence-backed-compiler-policy";
const PLANNER_POLICY_ID: &str = "b241-intent-planner-policy";
const OPERATOR_EXECUTION_STATE: &str = "operator-visible-bounded";

#[derive(Debug, Clone, Deserialize)]
pub struct IntentPlanRequest {
    pub task_family: String,
    pub intent_text: String,
    #[serde(default)]
    pub query_text: Option<String>,
    #[serde(default)]
    pub tool_id: Option<String>,
    #[serde(default)]
    pub work_mode: Option<String>,
}

#[derive(Debug, Clone, Serialize)]
pub struct IntentPlannerResponse {
    pub status: String,
    pub phase: String,
    pub intent: IntentPlan,
    pub execution_plan: ExecutionPlan,
    pub planner_policy: PlannerPolicy,
    pub route: crate::WorkspaceSubAgentRoutePlane,
    pub context_packet: WorkstreamContextPacket,
}

pub fn planner_policy_for_workstream(workstream_id: &str) -> PlannerPolicy {
    let supported = supported_task_families();
    let profiles = supported
        .iter()
        .map(|task_family| planner_policy_profile(task_family))
        .collect::<Vec<_>>();

    PlannerPolicy {
        policy_version: PLANNER_POLICY_VERSION.to_string(),
        policy_id: PLANNER_POLICY_ID.to_string(),
        workstream_id: workstream_id.to_string(),
        supported_task_families: supported.into_iter().map(|value| value.to_string()).collect(),
        profiles,
        note: "B24.1 keeps planning bounded and operator-aware by reusing the existing retrieval, compiler, GraphRAG, and subagent layers rather than creating a parallel autonomous executor.".to_string(),
    }
}

pub fn planner_availability_from_packet(
    workstream_id: &str,
    context_packet: &WorkstreamContextPacket,
) -> Option<IntentPlannerAvailability> {
    let retrieval = context_packet.retrieval_context.as_ref()?;
    let compiled_task_profile = retrieval.compiled_context_task_profile.as_deref();
    let task_family = task_family_hint(
        compiled_task_profile,
        retrieval.suggested_work_mode.as_deref(),
        Some(&retrieval.query_type),
    );
    let policy = planner_policy_for_workstream(workstream_id);
    let profile = policy_profile(&policy, &task_family)?;
    let retrieval_query_type = retrieval
        .compiled_context_retrieval_query_type
        .clone()
        .unwrap_or_else(|| profile.retrieval_query_type.clone());
    let compiler_profile_id = retrieval
        .compiled_context_budget_profile_id
        .clone()
        .unwrap_or_else(|| profile.compiler_profile_id.clone());
    let graphrag_query_mode = retrieval
        .compiled_context_graphrag_query_mode
        .clone()
        .or_else(|| retrieval.graphrag_query_mode.clone())
        .unwrap_or_else(|| profile.graphrag_query_mode.clone());
    let temporal_truth_view = if compiled_task_profile.is_some() {
        profile.temporal_truth_view.clone()
    } else {
        retrieval
            .temporal_truth_view
            .clone()
            .unwrap_or_else(|| profile.temporal_truth_view.clone())
    };
    Some(intent_planner_availability(
        workstream_id,
        &policy,
        &task_family,
        profile.tool_id.clone(),
        profile.work_mode.clone(),
        retrieval_query_type,
        compiler_profile_id,
        graphrag_query_mode,
        temporal_truth_view,
        Some(profile.recommended_subagent_id.clone()),
        planner_recipe_id_for_profile(workstream_id, context_packet, profile),
    ))
}

pub fn build_intent_execution_plan(
    detail: &WorkstreamControlRoomDetailResponse,
    context_packet: &WorkstreamContextPacket,
    route_response: &WorkspaceSubAgentRouteResponse,
    compiled_context: &PlannerCompiledContextSelection,
    binding: Option<&ProgramCampaignBinding>,
    request: &IntentPlanRequest,
) -> anyhow::Result<IntentPlannerResponse> {
    let task_family = normalize_task_family(&request.task_family);
    let policy = planner_policy_for_workstream(&detail.registry_entry.id);
    let policy_profile = policy_profile(&policy, &task_family)
        .ok_or_else(|| anyhow::anyhow!("unsupported task_family '{}'", task_family))?;
    let tool_id = request
        .tool_id
        .as_deref()
        .map(normalize_tool_id)
        .unwrap_or_else(|| policy_profile.tool_id.clone());
    let work_mode = request
        .work_mode
        .as_deref()
        .map(normalize_work_mode)
        .unwrap_or_else(|| policy_profile.work_mode.clone());
    let intent_text = normalize_sentence(&request.intent_text);
    if intent_text.is_empty() {
        return Err(anyhow::anyhow!("intent_text must not be empty"));
    }
    let query_text = request
        .query_text
        .as_deref()
        .map(normalize_sentence)
        .filter(|value| !value.is_empty())
        .unwrap_or_else(|| intent_text.clone());
    let intent_id = format!(
        "{}-{}-{}",
        sanitize_component(&context_packet.session_id),
        sanitize_component(&task_family),
        Utc::now().timestamp_millis()
    );

    let intent = IntentPlan {
        intent_version: INTENT_PLAN_VERSION.to_string(),
        intent_id: intent_id.clone(),
        workstream_id: context_packet.workstream_id.clone(),
        workspace_id: context_packet.workspace_id.clone(),
        session_id: context_packet.session_id.clone(),
        program_id: binding.map(|value| value.program.id.clone()),
        campaign_id: binding.map(|value| value.campaign.id.clone()),
        task_family: task_family.clone(),
        tool_id: tool_id.clone(),
        work_mode: work_mode.clone(),
        intent_text,
        query_text,
        operator_execution_state: OPERATOR_EXECUTION_STATE.to_string(),
        note: "B24.1 records one bounded operator-visible intent that can be resolved into a canonical execution plan without starting autonomous execution.".to_string(),
    };

    let recipe_doc = select_recipe_document(detail, context_packet, &task_family);
    let recipe = recipe_doc.map(recipe_target_from_document);
    let experiment = select_experiment_target(binding, context_packet, &task_family);
    let expected_outputs =
        expected_outputs_for_plan(recipe_doc, experiment.as_ref(), &task_family);
    let success_criteria = plan_acceptance_criteria(recipe_doc, &task_family);
    let mut stop_conditions =
        stop_conditions_for_plan(context_packet, &task_family, experiment.is_some());
    if let Some(baseline) = context_packet.bounded_study_baseline.as_ref() {
        stop_conditions.push(format!(
            "B26.6 bounded baseline active (adoption_id={}; variant={}); rollback only via operator baseline-rollback-plan API",
            baseline.adoption_id, baseline.promoted_variant_id
        ));
    }
    let execution_plan = ExecutionPlan {
        plan_version: EXECUTION_PLAN_VERSION.to_string(),
        plan_id: format!("{}-execution", intent_id),
        planner_policy_id: policy.policy_id.clone(),
        workstream_id: context_packet.workstream_id.clone(),
        workspace_id: context_packet.workspace_id.clone(),
        session_id: context_packet.session_id.clone(),
        program_id: binding.map(|value| value.program.id.clone()),
        campaign_id: binding.map(|value| value.campaign.id.clone()),
        task_family: task_family.clone(),
        tool_id,
        work_mode,
        selected_subagent_id: route_response.route.selection.selected_subagent_id.clone(),
        selected_role_tag: route_response.route.selection.selected_role_tag.clone(),
        selected_specialization: route_response.route.selection.selected_specialization.clone(),
        retrieval_query_type: compiled_context.retrieval_query_type.clone(),
        dense_backend: compiled_context.dense_backend.clone(),
        sparse_backend: compiled_context.sparse_backend.clone(),
        compiler_profile_id: compiled_context.budget_profile_id.clone(),
        graphrag_query_mode: compiled_context.graphrag_query_mode.clone(),
        temporal_truth_view: compiled_context.temporal_truth_view.clone(),
        selected_memory_tiers: compiled_context.selected_memory_tiers.clone(),
        recipe_target: recipe,
        experiment_target: experiment,
        expected_outputs,
        success_criteria,
        stop_conditions,
        context_packet_ref: format!(
            "{}/{}/context-packet",
            INTENT_PLANNER_API_PREFIX, context_packet.workstream_id
        ),
        program_context_packet_ref: binding.map(|value| {
            format!("/api/darwin/programs/{}/context-packet", value.program.id)
        }),
        workspace_subagent_route_path: route_response.route.workspace_subagent_route_path.clone(),
        workspace_subagent_handoff_path: route_response.route.attach_metadata.subagent_handoff_path.clone(),
        tool_launch_path: format!(
            "{}/{}/tool-dock/{}",
            INTENT_PLANNER_API_PREFIX, context_packet.workstream_id, route_response.route.selection.requested_tool_id.as_deref().unwrap_or(policy_profile.tool_id.as_str())
        ),
        compiled_context_top_memory_ids: compiled_context.top_memory_ids.clone(),
        compiled_context_preview: compiled_context.preview.clone(),
        operator_execution_state: OPERATOR_EXECUTION_STATE.to_string(),
        note: {
            let base = format!(
                "B24.1 keeps planning bounded: choose subagent={}, retrieval={}, compiler={}, graphrag={}, recipe_target={} and stop before autonomous execution.",
                route_response.route.selection.selected_subagent_id,
                compiled_context.retrieval_query_type,
                compiled_context.budget_profile_id,
                compiled_context.graphrag_query_mode,
                execution_recipe_note(detail, context_packet, &task_family),
            );
            match context_packet.bounded_study_baseline.as_ref() {
                Some(baseline) => format!(
                    "{} B26.6 baseline adoption {} binds promoted variant {}.",
                    base, baseline.adoption_id, baseline.promoted_variant_id
                ),
                None => base,
            }
        },
    };

    Ok(IntentPlannerResponse {
        status: "ok".to_string(),
        phase: INTENT_PLANNER_PHASE.to_string(),
        intent,
        execution_plan,
        planner_policy: policy,
        route: route_response.route.clone(),
        context_packet: context_packet.clone(),
    })
}

pub fn planner_compiled_context_selection_from_packet(
    packet: &WorkstreamContextPacket,
) -> Option<PlannerCompiledContextSelection> {
    let retrieval = packet.retrieval_context.as_ref()?;
    let task_profile = retrieval.compiled_context_task_profile.clone()?;
    let profile = planner_policy_profile(&task_profile);
    let retrieval_query_type = retrieval
        .compiled_context_retrieval_query_type
        .clone()
        .unwrap_or_else(|| profile.retrieval_query_type.clone());
    let graphrag_query_mode = retrieval
        .compiled_context_graphrag_query_mode
        .clone()
        .or_else(|| retrieval.graphrag_query_mode.clone())
        .unwrap_or_else(|| profile.graphrag_query_mode.clone());
    let temporal_truth_view = retrieval
        .compiled_context_preview
        .as_deref()
        .and_then(parse_temporal_truth_view_from_preview)
        .or_else(|| retrieval.temporal_truth_view.clone())
        .unwrap_or_else(|| profile.temporal_truth_view.clone());
    let temporal_truth_view = if temporal_truth_view.trim().is_empty() {
        profile.temporal_truth_view.clone()
    } else {
        temporal_truth_view
    };
    Some(PlannerCompiledContextSelection {
        task_profile,
        budget_profile_id: retrieval.compiled_context_budget_profile_id.clone()?,
        retrieval_query_type: retrieval_query_type.clone(),
        dense_backend: dense_backend_for_query_type(&retrieval_query_type),
        sparse_backend: retrieval.sparse_backend.clone(),
        graphrag_query_mode,
        temporal_truth_view,
        selected_memory_tiers: retrieval.compiled_context_selected_memory_tiers.clone(),
        top_memory_ids: retrieval.compiled_context_top_memory_ids.clone(),
        preview: retrieval.compiled_context_preview.clone(),
    })
}

fn dense_backend_for_query_type(query_type: &str) -> String {
    match query_type.trim().to_ascii_lowercase().as_str() {
        "code" => "voyage-code-3".to_string(),
        "sovereign" | "multilingual" | "privacy-sensitive" => "bge-m3".to_string(),
        _ => "voyage-4-large".to_string(),
    }
}

fn planner_recipe_id_for_profile(
    workstream_id: &str,
    context_packet: &WorkstreamContextPacket,
    profile: &PlannerPolicyProfile,
) -> Option<String> {
    context_packet
        .recommended_recipe
        .as_ref()
        .filter(|recipe| recipe.kind == profile.preferred_recipe_kind)
        .map(|recipe| recipe.id.clone())
        .or_else(|| Some(format!("{}.{}", workstream_id, profile.preferred_recipe_kind)))
}

fn parse_temporal_truth_view_from_preview(preview: &str) -> Option<String> {
    preview
        .lines()
        .map(str::trim)
        .find_map(|line| line.strip_prefix("temporal_truth_view: "))
        .map(|value| value.trim().to_string())
}

pub fn task_family_hint(
    compiled_task_profile: Option<&str>,
    suggested_work_mode: Option<&str>,
    query_type: Option<&str>,
) -> String {
    if let Some(profile) = compiled_task_profile {
        return normalize_task_family(profile);
    }
    if let Some(work_mode) = suggested_work_mode {
        return normalize_task_family(work_mode);
    }
    match query_type.unwrap_or("general").trim().to_ascii_lowercase().as_str() {
        "code" => "implementation".to_string(),
        _ => "analysis".to_string(),
    }
}

fn intent_planner_availability(
    workstream_id: &str,
    policy: &PlannerPolicy,
    task_family: &str,
    tool_id: String,
    work_mode: String,
    retrieval_query_type: String,
    compiler_profile_id: String,
    graphrag_query_mode: String,
    temporal_truth_view: String,
    recommended_subagent_id: Option<String>,
    recommended_recipe_id: Option<String>,
) -> IntentPlannerAvailability {
    IntentPlannerAvailability {
        availability_version: PLANNER_AVAILABILITY_VERSION.to_string(),
        planner_policy_id: policy.policy_id.clone(),
        planner_policy_path: format!(
            "{}/{}/planner-policy",
            INTENT_PLANNER_API_PREFIX, workstream_id
        ),
        intent_planner_path: format!(
            "{}/{}/intent-plan",
            INTENT_PLANNER_API_PREFIX, workstream_id
        ),
        supported_task_families: policy.supported_task_families.clone(),
        task_family_hint: task_family.to_string(),
        tool_id_hint: tool_id,
        work_mode_hint: work_mode,
        retrieval_query_type,
        compiler_profile_id,
        graphrag_query_mode,
        temporal_truth_view,
        recommended_subagent_id,
        recommended_recipe_id,
        operator_execution_state: OPERATOR_EXECUTION_STATE.to_string(),
        note: "Intent planning remains bounded and operator-aware: the planner resolves the next executable lane without auto-running it.".to_string(),
    }
}

fn planner_policy_profile(task_family: &str) -> PlannerPolicyProfile {
    let normalized = normalize_task_family(task_family);
    let (tool_id, work_mode, recommended_subagent_id, retrieval_query_type, compiler_profile_id, graphrag_query_mode, temporal_truth_view, preferred_recipe_kind, note) =
        match normalized.as_str() {
            "implementation" => (
                "codex",
                "implementation",
                "core",
                "code",
                "b235-budget-implementation",
                "local",
                "current",
                "repo_native_dev_loop",
                "Implementation planning stays code-routed, procedural-first, and local to the current repo lane.",
            ),
            "interactive-editing" => (
                "cursor",
                "interactive-editing",
                "core",
                "code",
                "b235-budget-interactive-editing",
                "local",
                "current",
                "repo_native_dev_loop",
                "Interactive editing keeps Cursor on the local repo lane with a tight current-truth budget.",
            ),
            "manuscript" => (
                "claude-code",
                "manuscript",
                "manuscript",
                "general",
                "b235-budget-manuscript",
                "global",
                "both",
                "repo_native_dev_loop",
                "Manuscript planning stays semantic-heavy, globally scoped, and explicit about current versus historical truth.",
            ),
            _ => (
                "claude-code",
                "analysis",
                "experiments",
                "general",
                "b235-budget-analysis",
                "global",
                "both",
                "operator_cpu_loop",
                "Analysis planning stays experiment-aware, globally scoped, and operator-visible.",
            ),
        };

    PlannerPolicyProfile {
        task_family: normalized.clone(),
        tool_id: tool_id.to_string(),
        work_mode: work_mode.to_string(),
        recommended_subagent_id: recommended_subagent_id.to_string(),
        retrieval_query_type: retrieval_query_type.to_string(),
        compiler_profile_id: compiler_profile_id.to_string(),
        graphrag_query_mode: graphrag_query_mode.to_string(),
        temporal_truth_view: temporal_truth_view.to_string(),
        preferred_recipe_kind: preferred_recipe_kind.to_string(),
        compiler_policy_basis_id: COMPILER_POLICY_BASIS_ID.to_string(),
        current_state: OPERATOR_EXECUTION_STATE.to_string(),
        recommended_when: format!(
            "Use {} when task_family={} and bounded planning should stay on the {} lane with compiler profile {}.",
            compiler_profile_id, normalized, recommended_subagent_id, compiler_profile_id
        ),
        note: note.to_string(),
    }
}

fn policy_profile<'a>(
    policy: &'a PlannerPolicy,
    task_family: &str,
) -> Option<&'a PlannerPolicyProfile> {
    let normalized = normalize_task_family(task_family);
    policy.profiles.iter().find(|profile| profile.task_family == normalized)
}

fn normalize_task_family(value: &str) -> String {
    let normalized = value.trim().to_ascii_lowercase().replace('_', "-");
    match normalized.as_str() {
        "interactive-editing" | "interactive" | "editing" | "cursor" => {
            "interactive-editing".to_string()
        }
        "manuscript" | "editorial" => "manuscript".to_string(),
        "implementation" | "impl" | "codex" | "code" => "implementation".to_string(),
        _ => "analysis".to_string(),
    }
}

fn normalize_tool_id(value: &str) -> String {
    value.trim().to_ascii_lowercase().replace('_', "-")
}

fn normalize_work_mode(value: &str) -> String {
    value.trim().to_ascii_lowercase().replace('_', "-")
}

fn supported_task_families() -> Vec<&'static str> {
    vec!["implementation", "analysis", "interactive-editing", "manuscript"]
}

fn select_recipe_document<'a>(
    detail: &'a WorkstreamControlRoomDetailResponse,
    context_packet: &WorkstreamContextPacket,
    task_family: &str,
) -> Option<&'a WorkstreamRecipeDocument> {
    let preferred_kind = match normalize_task_family(task_family).as_str() {
        "analysis" => "operator_cpu_loop",
        "manuscript" | "interactive-editing" | "implementation" => "repo_native_dev_loop",
        _ => "operator_cpu_loop",
    };
    detail
        .recipes
        .iter()
        .find(|recipe| recipe.kind == preferred_kind)
        .or_else(|| {
            context_packet.recommended_recipe.as_ref().and_then(|recommended| {
                detail
                    .recipes
                    .iter()
                    .find(|recipe| recipe.id == recommended.id || recipe.kind == recommended.kind)
            })
        })
        .or_else(|| detail.recipes.first())
}

fn recipe_target_from_document(recipe: &WorkstreamRecipeDocument) -> ExecutionRecipeTarget {
    ExecutionRecipeTarget {
        recipe_id: recipe.id.clone(),
        recipe_kind: recipe.kind.clone(),
        summary: recipe.summary.clone(),
        recovery_points: recipe.recovery_points.clone(),
    }
}

fn select_recipe_target(
    detail: &WorkstreamControlRoomDetailResponse,
    context_packet: &WorkstreamContextPacket,
    task_family: &str,
) -> Option<ExecutionRecipeTarget> {
    select_recipe_document(detail, context_packet, task_family).map(recipe_target_from_document)
}

fn select_experiment_target(
    binding: Option<&ProgramCampaignBinding>,
    context_packet: &WorkstreamContextPacket,
    task_family: &str,
) -> Option<ExecutionExperimentTarget> {
    let binding = binding?;
    let normalized = normalize_task_family(task_family);
    if normalized == "implementation" || normalized == "interactive-editing" {
        return None;
    }
    let preferred_experiment_id = context_packet
        .experiment_flags
        .as_ref()
        .and_then(|flags| flags.experiment_id.as_ref());
    let experiment = preferred_experiment_id
        .and_then(|experiment_id| {
            binding
                .campaign
                .experiments
                .iter()
                .find(|experiment| experiment.id == *experiment_id)
        })
        .or_else(|| binding.campaign.experiments.first())?;
    Some(ExecutionExperimentTarget {
        experiment_id: experiment.id.clone(),
        campaign_id: binding.campaign.id.clone(),
        spec_doc: experiment.spec_doc.clone(),
        results_doc: experiment.results_doc.clone(),
        live_batch_id: experiment.live_batch_id.clone(),
    })
}

fn expected_outputs_for_plan(
    recipe: Option<&WorkstreamRecipeDocument>,
    experiment: Option<&ExecutionExperimentTarget>,
    task_family: &str,
) -> Vec<String> {
    let mut outputs = BTreeSet::new();

    if let Some(recipe) = recipe {
        outputs.insert(format!("recipe_target:{}", recipe.id));
        outputs.insert(format!("recipe_kind:{}", recipe.kind));
        for output in flatten_recipe_outputs(recipe) {
            outputs.insert(output);
        }
    }
    if let Some(experiment) = experiment {
        outputs.insert(format!("experiment:{}", experiment.experiment_id));
        if !experiment.results_doc.trim().is_empty() {
            outputs.insert(experiment.results_doc.clone());
        }
    }

    match normalize_task_family(task_family).as_str() {
        "implementation" => {
            outputs.insert("repo-native delta preserved".to_string());
            outputs.insert("bounded compile/deploy validation path".to_string());
        }
        "manuscript" => {
            outputs.insert("manuscript support context stays claim/evidence-linked".to_string());
            outputs.insert("readiness-state limits remain explicit".to_string());
        }
        "interactive-editing" => {
            outputs.insert("interactive editor lane stays on the canonical workspace/session".to_string());
        }
        _ => {
            outputs.insert("experiment workbench plan remains result-aware".to_string());
            outputs.insert("operator-visible experiment target remains bounded".to_string());
        }
    }

    outputs.into_iter().collect()
}

fn plan_acceptance_criteria(
    recipe: Option<&WorkstreamRecipeDocument>,
    task_family: &str,
) -> Vec<PlanAcceptanceCriterion> {
    let default_steps = match normalize_task_family(task_family).as_str() {
        "implementation" => vec![
            ("inspect", "repo-native delta is real"),
            ("validate", "compiled context and route stay aligned to implementation"),
        ],
        "manuscript" => vec![
            ("compile", "manuscript support context stays semantic-heavy and globally scoped"),
            ("guardrails", "readiness-state limits remain explicit"),
        ],
        "interactive-editing" => vec![
            ("open", "interactive editing stays attached to the canonical workspace"),
            ("bound", "current-truth local context remains bounded"),
        ],
        _ => vec![
            ("analyze", "analysis stays result-aware and experiment-targeted"),
            ("bound", "global graph context remains operator-visible and bounded"),
        ],
    };

    let mut criteria = default_steps
        .into_iter()
        .enumerate()
        .map(|(index, (criterion_id, success_signal))| PlanAcceptanceCriterion {
            criteria_version: PLAN_ACCEPTANCE_CRITERIA_VERSION.to_string(),
            criterion_id: format!("{}-{}", normalize_task_family(task_family), criterion_id),
            description: format!(
                "Bounded {} plan criterion {}",
                normalize_task_family(task_family),
                index + 1
            ),
            success_signal: success_signal.to_string(),
            stop_condition: format!(
                "stop if {} cannot be demonstrated within the bounded operator loop",
                success_signal
            ),
            operator_visibility_required: true,
        })
        .collect::<Vec<_>>();

    if let Some(recipe) = recipe {
        for step in &recipe.steps {
            criteria.push(PlanAcceptanceCriterion {
                criteria_version: PLAN_ACCEPTANCE_CRITERIA_VERSION.to_string(),
                criterion_id: format!("{}-{}", recipe.kind, step.id),
                description: step.action.clone(),
                success_signal: step.success_condition.clone(),
                stop_condition: format!(
                    "stop if step {} cannot reach '{}'",
                    step.id, step.success_condition
                ),
                operator_visibility_required: true,
            });
        }
    }

    criteria
}

fn stop_conditions_for_plan(
    context_packet: &WorkstreamContextPacket,
    task_family: &str,
    has_experiment_target: bool,
) -> Vec<String> {
    let mut stop_conditions = vec![
        "stop if operator visibility is lost".to_string(),
        "stop if the Beagle-owned workspace/session identity changes unexpectedly".to_string(),
    ];

    if context_packet.handoff.recovery_required {
        stop_conditions.push(
            "stop and switch to recovery_resume_loop if the workstream still requires recovery".to_string(),
        );
    }

    match normalize_task_family(task_family).as_str() {
        "implementation" => stop_conditions.push(
            "stop if repo-native delta, build validation, or bounded rollout validation fail".to_string(),
        ),
        "manuscript" => stop_conditions.push(
            "stop before any public release action while claim-linked-human-eval-pending remains explicit".to_string(),
        ),
        "interactive-editing" => stop_conditions.push(
            "stop if editing would leave the canonical workspace folder or current-truth lane".to_string(),
        ),
        _ => stop_conditions.push(
            "stop if the experiment/result target cannot be resolved or Slurm leaves the green path".to_string(),
        ),
    }

    if has_experiment_target {
        stop_conditions.push(
            "stop if the selected experiment target drifts away from the active campaign binding".to_string(),
        );
    }

    stop_conditions
}

fn execution_recipe_note(
    detail: &WorkstreamControlRoomDetailResponse,
    context_packet: &WorkstreamContextPacket,
    task_family: &str,
) -> String {
    select_recipe_target(detail, context_packet, task_family)
        .map(|recipe| recipe.recipe_id)
        .unwrap_or_else(|| "none".to_string())
}

fn normalize_sentence(value: &str) -> String {
    value.split_whitespace().collect::<Vec<_>>().join(" ")
}

fn sanitize_component(value: &str) -> String {
    value.chars()
        .map(|ch| match ch {
            'a'..='z' | 'A'..='Z' | '0'..='9' => ch.to_ascii_lowercase(),
            _ => '-',
        })
        .collect::<String>()
        .trim_matches('-')
        .to_string()
}

pub fn flatten_recipe_outputs(recipe: &WorkstreamRecipeDocument) -> Vec<String> {
    let mut outputs = BTreeSet::new();
    flatten_value("outputs", &recipe.outputs, &mut outputs);
    outputs.into_iter().collect()
}

fn flatten_value(prefix: &str, value: &Value, outputs: &mut BTreeSet<String>) {
    match value {
        Value::Null => {}
        Value::Bool(flag) => {
            outputs.insert(format!("{}={}", prefix, flag));
        }
        Value::Number(number) => {
            outputs.insert(format!("{}={}", prefix, number));
        }
        Value::String(text) => {
            outputs.insert(text.to_string());
        }
        Value::Array(items) => {
            for item in items {
                flatten_value(prefix, item, outputs);
            }
        }
        Value::Object(map) => {
            for (key, value) in map {
                let child_prefix = if prefix.is_empty() {
                    key.to_string()
                } else {
                    format!("{}.{}", prefix, key)
                };
                flatten_value(&child_prefix, value, outputs);
            }
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::{
        WorkstreamContextPacketHandoff, WorkstreamContextPacketLastResult,
        WorkstreamContextPacketRecipe, WorkstreamContextPacketRetrievalContext,
        WorkstreamContextPacketRetrievalFilters,
    };

    #[test]
    fn planner_policy_exposes_canonical_task_families() {
        let policy = planner_policy_for_workstream("beagle-darwin-hpc-governance");
        assert_eq!(policy.policy_id, "b241-intent-planner-policy");
        assert_eq!(
            policy.supported_task_families,
            vec![
                "implementation".to_string(),
                "analysis".to_string(),
                "interactive-editing".to_string(),
                "manuscript".to_string()
            ]
        );
        assert!(policy
            .profiles
            .iter()
            .any(|profile| profile.task_family == "manuscript"
                && profile.recommended_subagent_id == "manuscript"));
    }

    #[test]
    fn planner_availability_uses_compiled_context_hint() {
        let packet = WorkstreamContextPacket {
            packet_version: "test".to_string(),
            workstream_id: "beagle-darwin-hpc-governance".to_string(),
            workspace_id: "beagle-cluster-pilot".to_string(),
            session_id: "ws-cluster-workspace-habitat".to_string(),
            repo: "agourakis82/beagle".to_string(),
            branch: "feat/darwin-hpc-governance".to_string(),
            governance_state: "live".to_string(),
            handoff: WorkstreamContextPacketHandoff {
                handoff_required: false,
                recovery_required: false,
                handoff_present: true,
                last_handoff: None,
            },
            last_result: WorkstreamContextPacketLastResult {
                available: false,
                reference: None,
                summary: None,
                manifest: None,
                error: None,
            },
            last_successful_task: None,
            latest_physio: None,
            experiment_flags: None,
            memory_hits: Vec::new(),
            retrieval_context: Some(WorkstreamContextPacketRetrievalContext {
                query_text: "compile manuscript support context".to_string(),
                query_type: "general".to_string(),
                retrieval_mode: "dense+sparse-hybrid".to_string(),
                dense_backend: "voyage-4-large".to_string(),
                sparse_backend: "local-lexical".to_string(),
                routing_source: "explicit-hint".to_string(),
                routing_reason: "test".to_string(),
                reranking_applied: false,
                reranking_profile_id: None,
                reranker_backend: None,
                reranker_runtime_state: None,
                reranking_latency_ms: None,
                top_k: 3,
                applied_filters: WorkstreamContextPacketRetrievalFilters::default(),
                hit_count: 0,
                top_memory_ids: Vec::new(),
                top_domains: Vec::new(),
                top_tags: Vec::new(),
                promotion_policy_id: None,
                retention_policy_id: None,
                graphrag_query_mode: Some("global".to_string()),
                graphrag_query_mode_reason: None,
                graphrag_root_entity_type: None,
                graphrag_root_entity_id: None,
                graphrag_node_count: 0,
                graphrag_edge_count: 0,
                graphrag_node_types: Vec::new(),
                graphrag_edge_types: Vec::new(),
                memory_hierarchy_counts: Vec::new(),
                promoted_memory_count: 0,
                promoted_target_memory_types: Vec::new(),
                compiled_context_task_profile: Some("manuscript".to_string()),
                compiled_context_budget_profile_id: Some("b235-budget-manuscript".to_string()),
                compiled_context_retrieval_query_type: Some("general".to_string()),
                compiled_context_graphrag_query_mode: Some("global".to_string()),
                compiled_context_selected_memory_tiers: vec![
                    "semantic".to_string(),
                    "episodic".to_string(),
                    "procedural".to_string(),
                ],
                compiled_context_source_slices: Vec::new(),
                compiled_context_top_memory_ids: Vec::new(),
                compiled_context_preview: None,
                planner: None,
                execution: None,
                temporal_truth_view: Some("both".to_string()),
                temporal_subject_refs: Vec::new(),
                temporal_current_memory_ids: Vec::new(),
                temporal_historical_memory_ids: Vec::new(),
                temporal_track_count: 0,
                temporal_contradiction_count: 0,
                temporal_contradiction_ids: Vec::new(),
                temporal_preview: None,
                suggested_subagent_id: Some("manuscript".to_string()),
                suggested_work_mode: Some("manuscript".to_string()),
                influence_reason: "test".to_string(),
            }),
            recommended_recipe: Some(WorkstreamContextPacketRecipe {
                id: "beagle-darwin-hpc-governance.repo_native_dev_loop".to_string(),
                kind: "repo_native_dev_loop".to_string(),
                summary: "Canonical repo-native edit/build/deploy/validate/handoff loop.".to_string(),
            }),
            bounded_study_baseline: None,
        };

        let availability = planner_availability_from_packet(
            "beagle-darwin-hpc-governance",
            &packet,
        )
        .expect("planner availability");

        assert_eq!(availability.task_family_hint, "manuscript");
        assert_eq!(availability.compiler_profile_id, "b235-budget-manuscript");
        assert_eq!(availability.recommended_subagent_id.as_deref(), Some("manuscript"));
    }

    #[test]
    fn planner_compiled_context_selection_prefers_task_specific_lane() {
        let packet = WorkstreamContextPacket {
            packet_version: "test".to_string(),
            workstream_id: "beagle-darwin-hpc-governance".to_string(),
            workspace_id: "beagle-cluster-pilot".to_string(),
            session_id: "ws-cluster-workspace-habitat".to_string(),
            repo: "agourakis82/beagle".to_string(),
            branch: "feat/darwin-hpc-governance".to_string(),
            governance_state: "live".to_string(),
            handoff: WorkstreamContextPacketHandoff {
                handoff_required: false,
                recovery_required: false,
                handoff_present: true,
                last_handoff: None,
            },
            last_result: WorkstreamContextPacketLastResult {
                available: false,
                reference: None,
                summary: None,
                manifest: None,
                error: None,
            },
            last_successful_task: None,
            latest_physio: None,
            experiment_flags: None,
            memory_hits: Vec::new(),
            retrieval_context: Some(WorkstreamContextPacketRetrievalContext {
                query_text: "implementation workstream context".to_string(),
                query_type: "general".to_string(),
                retrieval_mode: "dense+sparse-hybrid".to_string(),
                dense_backend: "voyage-4-large".to_string(),
                sparse_backend: "local-lexical".to_string(),
                routing_source: "explicit-hint".to_string(),
                routing_reason: "test".to_string(),
                reranking_applied: false,
                reranking_profile_id: None,
                reranker_backend: None,
                reranker_runtime_state: None,
                reranking_latency_ms: None,
                top_k: 3,
                applied_filters: WorkstreamContextPacketRetrievalFilters::default(),
                hit_count: 0,
                top_memory_ids: Vec::new(),
                top_domains: Vec::new(),
                top_tags: Vec::new(),
                promotion_policy_id: None,
                retention_policy_id: None,
                graphrag_query_mode: Some("global".to_string()),
                graphrag_query_mode_reason: None,
                graphrag_root_entity_type: None,
                graphrag_root_entity_id: None,
                graphrag_node_count: 0,
                graphrag_edge_count: 0,
                graphrag_node_types: Vec::new(),
                graphrag_edge_types: Vec::new(),
                memory_hierarchy_counts: Vec::new(),
                promoted_memory_count: 0,
                promoted_target_memory_types: Vec::new(),
                compiled_context_task_profile: Some("implementation".to_string()),
                compiled_context_budget_profile_id: Some("b235-budget-implementation".to_string()),
                compiled_context_retrieval_query_type: Some("code".to_string()),
                compiled_context_graphrag_query_mode: Some("local".to_string()),
                compiled_context_selected_memory_tiers: vec![
                    "procedural".to_string(),
                    "semantic".to_string(),
                    "episodic".to_string(),
                ],
                compiled_context_source_slices: Vec::new(),
                compiled_context_top_memory_ids: Vec::new(),
                compiled_context_preview: Some(
                    "task_profile: implementation\nretrieval_query_type: code\ndense_backend: voyage-code-3\ntemporal_truth_view: current".to_string(),
                ),
                planner: None,
                execution: None,
                temporal_truth_view: Some("both".to_string()),
                temporal_subject_refs: Vec::new(),
                temporal_current_memory_ids: Vec::new(),
                temporal_historical_memory_ids: Vec::new(),
                temporal_track_count: 0,
                temporal_contradiction_count: 0,
                temporal_contradiction_ids: Vec::new(),
                temporal_preview: None,
                suggested_subagent_id: Some("manuscript".to_string()),
                suggested_work_mode: Some("manuscript".to_string()),
                influence_reason: "test".to_string(),
            }),
            recommended_recipe: Some(WorkstreamContextPacketRecipe {
                id: "beagle-darwin-hpc-governance.operator_cpu_loop".to_string(),
                kind: "operator_cpu_loop".to_string(),
                summary: "Canonical operator loop.".to_string(),
            }),
            bounded_study_baseline: None,
        };

        let selection = planner_compiled_context_selection_from_packet(&packet)
            .expect("compiled planner selection");
        let availability = planner_availability_from_packet(
            "beagle-darwin-hpc-governance",
            &packet,
        )
        .expect("planner availability");

        assert_eq!(selection.retrieval_query_type, "code");
        assert_eq!(selection.dense_backend, "voyage-code-3");
        assert_eq!(selection.temporal_truth_view, "current");
        assert_eq!(availability.recommended_subagent_id.as_deref(), Some("core"));
        assert_eq!(
            availability.recommended_recipe_id.as_deref(),
            Some("beagle-darwin-hpc-governance.repo_native_dev_loop")
        );
        assert_eq!(availability.temporal_truth_view, "current");
    }
}
