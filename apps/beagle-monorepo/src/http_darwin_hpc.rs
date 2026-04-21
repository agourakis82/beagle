use crate::http::AppState;
use crate::http_memory::latest_physio_snapshot;
use axum::{
    extract::{Extension, Path, Query, State},
    http::StatusCode,
    response::Html,
    routing::{get, post},
    Json, Router,
};
use beagle_darwin::{
    available_consumers, ConsumerIdentity,
    apply_workstream_tool_return,
    approve_execution_plan,
    build_intent_execution_plan,
    bootstrap_workspace_session, bootstrap_workspace_session_for_workstream,
    load_workspace_session, read_recent_ledger_entries,
    build_program_context_packet, resolve_campaign_context_binding,
    execution_status_summary_for_packet,
    planner_availability_from_packet,
    planner_compiled_context_selection_from_packet,
    planner_policy_for_workstream,
    materialize_review_inbox_item,
    dispatch_follow_on_plan,
    decide_review_inbox_item,
    read_approval_gating_decision,
    ensure_autonomy_policy_calibration,
    ensure_analysis_shadow_calibration,
    ensure_analysis_canary_activation,
    ensure_analysis_sample_accumulation,
    ensure_analysis_shadow_soak,
    ensure_guarded_policy_rollout,
    ensure_implementation_canary_autonomy,
    ensure_manuscript_alignment_signal_acquisition,
    ensure_manuscript_quality_uplift,
    ensure_manuscript_sample_accumulation,
    ensure_manuscript_shadow_calibration,
    read_autonomy_policy,
    read_continuation_dispatch,
    read_continuation_receipt,
    read_continuation_state,
    read_execution_receipt,
    read_execution_reflection,
    read_execution_result_links,
    read_execution_state,
    read_follow_on_plan,
    read_replan_suggestion,
    read_review_decision,
    read_review_inbox_item,
    read_risk_evaluation,
    read_latest_run_capsule,
    read_latest_replay_execution,
    read_prior_run_capsule,
    read_code_provenance,
    read_replay_request,
    read_source_fingerprint,
    ensure_study_registry_sweep,
    ensure_study_decision_engine,
    ensure_study_convergence,
    ensure_study_promotion_execution,
    ensure_baseline_adoption,
    ensure_study_proposal_dispatch,
    read_next_run_proposal,
    read_study_decision,
    read_study_decision_basis,
    StudyConvergenceBundle,
    StudyPromotionExecutionBundle,
    BaselineAdoptionBundle,
    BaselineRollbackPlan,
    NextStudySeed,
    bounded_study_baseline_summary_from_plane,
    read_baseline_rollback_plan,
    read_next_study_seed,
    read_study_proposal_dispatch,
    read_study_run_update,
    read_study_continuation_state,
    read_run_diff,
    read_workspace_snapshot,
    read_trajectory_eval,
    resolve_program_campaign_binding_for_workstream, resolve_program_context_binding,
    start_execution_plan,
    stop_execution_plan,
    build_campaign_claims, build_campaign_manuscript_pack,
    build_campaign_jats_manuscript_pack,
    build_campaign_evidence_pack, build_campaign_review_bundle,
    build_collaborative_compute_experiment_workbench,
    execute_replay_request,
    orchestrate_workbench_run,
    build_workstream_cursor_remote_lane, build_workstream_managed_attach,
    build_workstream_workspace_launch_resume,
    read_workspace_external_registry_staging,
    read_workspace_sandbox_deposit_handshake,
    read_workspace_manuscript_assembly,
    read_workspace_scholarly_release,
    read_workspace_publication_package,
    read_workspace_manuscript_handoff,
    record_workspace_external_registry_staging,
    record_workspace_sandbox_deposit_handshake,
    record_workspace_manuscript_assembly,
    record_workspace_publication_package,
    record_workspace_scholarly_release,
    record_workspace_manuscript_handoff,
    WorkspaceManuscriptAssemblyRequest,
    WorkspaceManuscriptAssemblyResponse,
    WorkspaceManuscriptHandoffRequest,
    WorkspaceManuscriptHandoffResponse,
    WorkspaceExternalRegistryStagingRequest,
    WorkspaceExternalRegistryStagingResponse,
    WorkspaceSandboxDepositHandshakeRequest,
    WorkspaceSandboxDepositHandshakeResponse,
    WorkspaceScholarlyReleaseRequest,
    WorkspaceScholarlyReleaseResponse,
    WorkspacePublicationPackageRequest,
    WorkspacePublicationPackageResponse,
    build_workstream_workspace_subagent_list,
    read_workspace_subagent_handoff,
    record_workspace_subagent_handoff,
    WorkspaceSubAgentHandoffRequest,
    WorkspaceSubAgentHandoffResponse,
    build_workstream_workspace_subagent_route,
    build_workstream_workspace_subagents,
    build_workstream_workspace_template,
    build_multi_user_gpu_workspace_tenancy_bundle,
    build_workstream_workspace_attach,
    build_workstream_workspace_habitat, render_workspace_habitat_context_env,
    get_premium_tool_launch_surface_with_context_packet, get_workstream_context_packet,
    get_workstream_cockpit_with_context_packet,
    get_workstream_portfolio_control_room,
    get_workstream_control_room_detail, get_workstream_control_room_handoff,
    get_workstream_control_room_last_result, get_workstream_control_room_recipes,
    get_workstream_control_room_status, list_workstream_control_room,
    get_workstream_timeline, get_workstream_timeline_event,
    run_workstream_control_room_action,
    record_workspace_fallback_return, record_workspace_fallback_start, run_workspace_pilot,
    render_workstream_cockpit_page,
    BridgeHealth, BridgeLedgerEntry, BridgeProviderInfo, BridgeRequest, BridgeResponse,
    BridgeStatus, DarwinHpcGatewayClient, DarwinHpcGatewayError, HpcJobStatus, HpcProfile,
    HpcProfileCatalog, HpcSubmitRequest, HpcSubmitResponse, HpcTextArtifact,
    JobArtifactManifest, ObjectResultManifest, ResultCatalogEntry, ResultCatalogQuery,
    ResultCatalogResponse, ToolBridge, WorkspaceBootstrapResponse, WorkspaceFallbackDrillRequest,
    WorkspaceFallbackDrillResponse, WorkspacePilotRequest, WorkspacePilotResponse, WorkspaceSessionState,
    WorkstreamCockpitResponse, WorkstreamContextPacketAugmentation,
    WorkstreamContextPacketExperimentFlags, WorkstreamContextPacketMemoryHierarchyCount,
    WorkstreamContextPacketMemoryHit,
    WorkstreamContextPacketPhysioSnapshot, WorkstreamContextPacket,
    WorkstreamContextPacketResponse,
    WorkstreamContextPacketRetrievalContext, WorkstreamContextPacketRetrievalFilters,
    ClusterWorkspaceHabitatResponse,
    CursorRemoteLaneResponse,
    CampaignClaimsResponse, EvidencePackResponse,
    ManuscriptPackResponse,
    JatsManuscriptPackResponse,
    IntentPlanRequest,
    IntentPlannerResponse,
    ContinuationDispatch,
    ContinuationDispatchRequest,
    ContinuationReceipt,
    ContinuationStatePlane,
    ExecutionPlan,
    ExecutionReflection,
    ExecutionReceipt,
    ExecutionResultLinksDocument,
    ExecutionStatePlane,
    PlanApproval,
    PlanApprovalRequest,
    PlanExecutionStartRequest,
    PlanExecutionStopRequest,
    PlannerPolicy,
    ReplayRequest,
    ReplayExecutionBundle,
    ReplayExecutionReceipt,
    ReplanSuggestion,
    ReviewDecision,
    ReviewDecisionEditPatch,
    ReviewInboxItem,
    ReviewInboxDecisionRequest,
    ReviewInboxMaterializeRequest,
    FollowOnPlan,
    ReviewBundleResponse,
    ProgramContextPacketResponse,
    WorkspaceAttachResponse,
    WorkspaceLaunchResumeResponse,
    WorkspaceSubAgentListResponse,
    WorkspaceSubAgentRouteRequest,
    WorkspaceSubAgentRouteResponse,
    WorkspaceSubAgentsResponse,
    CollaborativeComputeExperimentWorkbench,
    CollaborativeWorkbenchCollaborationContract,
    CollaborativeWorkbenchComputeSelectionContract,
    CollaborativeWorkbenchRunContract,
    CollaborativeWorkbenchSessionContract,
    CodeProvenance,
    CodeProvenanceCaptureRequest,
    WorkbenchReservation,
    RunCapsule,
    RunDiff,
    RunResultIdentityReceipt,
    RunScopedPublication,
    DeterministicResultBinding,
    WorkbenchResultBinding,
    WorkbenchRun,
    WorkbenchRunDispatchRequest,
    WorkbenchRunOrchestrationBundle,
    WorkspaceSnapshot,
    SourceFingerprint,
    StudyDag,
    StudyDecision,
    StudyDecisionBasis,
    NextRunProposal,
    StudyProposalDispatch,
    StudyProposalDispatchBundle,
    StudyProposalDispatchRequest,
    StudyContinuationState,
    StudyRunUpdate,
    StudyRegistry,
    StudySweep,
    ComparativeResultSummary,
    WorkspaceTenancyContract,
    ComputeTenancyContract,
    PartnerAccessContract,
    WorkspaceTemplateResponse,
    WorkstreamPremiumToolLaunchResponse, WorkstreamControlRoomActionResponse,
    WorkstreamControlRoomDetailResponse, WorkstreamControlRoomHandoffResponse,
    WorkstreamControlRoomLastResultResponse, WorkstreamControlRoomListResponse,
    WorkstreamPortfolioResponse,
    WorkstreamControlRoomRecipeSetResponse, WorkstreamControlRoomStatusResponse,
    WorkstreamToolReturnPayload, WorkstreamToolReturnResponse,
    WorkstreamTimelineEventDetailResponse, WorkstreamTimelineResponse,
    TrajectoryEval,
    ApprovalGatingDecision,
    AnalysisPromotionGate,
    AnalysisCanaryMetrics,
    AnalysisCanaryRollbackDecision,
    AnalysisRolloutDecision,
    AnalysisRolloutMetrics,
    AnalysisShadowCalibration,
    AnalysisShadowSoak,
    AnalysisSoakMetrics,
    ManuscriptAlignmentLabels,
    ManuscriptContextAdequacy,
    ManuscriptPromotionEvidence,
    ManuscriptPromotionGate,
    ManuscriptRolloutDecision,
    ManuscriptRolloutMetrics,
    ManuscriptShadowHistory,
    ManuscriptShadowCalibration,
    ManuscriptSoakMetrics,
    ManuscriptTrajectoryQuality,
    ManuscriptTuningRecommendation,
    AutonomyCalibrationDataset,
    AutonomyPolicyEvalReport,
    AutonomyPolicy,
    AutonomyShadowThreshold,
    CanaryRollbackDecision,
    CanaryRolloutMetrics,
    EscalationThresholds,
    GuardedRolloutDecision,
    PolicyRolloutMetrics,
    RiskEvaluation,
    ShadowPolicyComparison,
    UpdatedPolicyRecommendation,
};
use chrono::Utc;
use serde::{Deserialize, Serialize};
use serde_json::{json, Value};
use std::collections::BTreeSet;
use std::path::Path as FsPath;
use tracing::error;

type JsonError = (StatusCode, Json<Value>);

#[derive(Debug, Deserialize, Default)]
struct WorkstreamCompiledContextQuery {
    task_profile: Option<String>,
    tool_id: Option<String>,
    work_mode: Option<String>,
    query_text: Option<String>,
}

#[derive(Debug, Deserialize)]
struct IntentPlanRequestBody {
    task_family: String,
    intent_text: String,
    tool_id: Option<String>,
    work_mode: Option<String>,
    query_text: Option<String>,
}

#[derive(Debug, Deserialize)]
struct PlanExecutionApprovalRequestBody {
    execution_plan: ExecutionPlan,
    approved_by: String,
    approval_note: String,
}

#[derive(Debug, Deserialize)]
struct PlanExecutionStartRequestBody {
    plan_id: String,
    started_by: String,
    start_note: Option<String>,
}

#[derive(Debug, Deserialize)]
struct PlanExecutionStopRequestBody {
    plan_id: String,
    stopped_by: String,
    stop_reason: String,
}

#[derive(Debug, Deserialize)]
struct WorkbenchRunOrchestrationRequestBody {
    requested_by: String,
    requester_role_id: String,
    selected_subagent_id: String,
    task_family: String,
    intent_text: String,
    compute_profile_id: String,
    #[serde(default)]
    run_label: Option<String>,
    #[serde(default)]
    recipe_kind: Option<String>,
    #[serde(default)]
    experiment_id: Option<String>,
    reservation_note: String,
    dispatch_note: String,
    #[serde(default)]
    poll_interval_seconds: Option<u64>,
    #[serde(default)]
    timeout_seconds: Option<u64>,
    #[serde(default)]
    code_provenance_capture: Option<CodeProvenanceCaptureRequest>,
}

#[derive(Debug, Deserialize)]
struct ReplayExecutionRequestBody {
    requested_by: String,
    requester_role_id: String,
    execution_mode: String,
    #[serde(default)]
    run_label: Option<String>,
    reservation_note: String,
    dispatch_note: String,
    #[serde(default)]
    poll_interval_seconds: Option<u64>,
    #[serde(default)]
    timeout_seconds: Option<u64>,
    #[serde(default)]
    code_provenance_capture: Option<CodeProvenanceCaptureRequest>,
}

#[derive(Debug, Deserialize)]
struct ReviewInboxMaterializeRequestBody {
    created_by: String,
    create_note: Option<String>,
}

#[derive(Debug, Deserialize, Default)]
struct ReviewDecisionEditPatchBody {
    task_family: Option<String>,
    selected_subagent_id: Option<String>,
    retrieval_query_type: Option<String>,
    compiler_profile_id: Option<String>,
    graphrag_query_mode: Option<String>,
    temporal_truth_view: Option<String>,
    recipe_kind: Option<String>,
}

#[derive(Debug, Deserialize)]
struct ReviewDecisionRequestBody {
    inbox_item_id: String,
    decision_action: String,
    decided_by: String,
    decision_note: String,
    #[serde(default)]
    edit_patch: Option<ReviewDecisionEditPatchBody>,
}

#[derive(Debug, Deserialize)]
struct ContinuationDispatchRequestBody {
    dispatched_by: String,
    dispatch_note: Option<String>,
}

#[derive(Debug, Deserialize)]
struct StudyProposalDispatchRequestBody {
    approved_by: String,
    #[serde(default)]
    dispatch_note: Option<String>,
    #[serde(default)]
    proposed_run_label_override: Option<String>,
    #[serde(default)]
    proposed_compute_profile_id_override: Option<String>,
}

pub fn darwin_hpc_routes() -> Router<AppState> {
    Router::new()
        .route("/api/darwin/workspace/bootstrap", get(workspace_bootstrap_handler))
        .route("/api/darwin/workspace/session", get(workspace_session_handler))
        .route(
            "/api/darwin/workspace/fallback/start",
            post(workspace_fallback_start_handler),
        )
        .route(
            "/api/darwin/workspace/fallback/return",
            post(workspace_fallback_return_handler),
        )
        .route(
            "/api/darwin/workspace/pilot/execute",
            post(workspace_pilot_execute_handler),
        )
        .route(
            "/api/darwin/portfolio/workstreams",
            get(workstream_portfolio_control_room_handler),
        )
        .route(
            "/api/darwin/programs/:program_id/context-packet",
            get(program_context_packet_handler),
        )
        .route(
            "/api/darwin/campaigns/:campaign_id/context-packet",
            get(campaign_context_packet_handler),
        )
        .route(
            "/api/darwin/campaigns/:campaign_id/evidence-pack",
            get(campaign_evidence_pack_handler),
        )
        .route(
            "/api/darwin/campaigns/:campaign_id/claims",
            get(campaign_claims_handler),
        )
        .route(
            "/api/darwin/campaigns/:campaign_id/manuscript-pack",
            get(campaign_manuscript_pack_handler),
        )
        .route(
            "/api/darwin/campaigns/:campaign_id/jats-manuscript-pack",
            get(campaign_jats_manuscript_pack_handler),
        )
        .route(
            "/api/darwin/campaigns/:campaign_id/review-bundle",
            get(campaign_review_bundle_handler),
        )
        .route("/api/darwin/workstreams", get(workstream_control_room_list_handler))
        .route(
            "/api/darwin/workstreams/:workstream_id/cockpit",
            get(workstream_cockpit_handler),
        )
        .route(
            "/api/darwin/workstreams/:workstream_id/context-packet",
            get(workstream_context_packet_handler),
        )
        .route(
            "/api/darwin/workstreams/:workstream_id/compiled-context",
            post(workstream_compiled_context_handler),
        )
        .route(
            "/api/darwin/workstreams/:workstream_id/planner-policy",
            get(workstream_planner_policy_handler),
        )
        .route(
            "/api/darwin/workstreams/:workstream_id/intent-plan",
            post(workstream_intent_plan_handler),
        )
        .route(
            "/api/darwin/workstreams/:workstream_id/plan-execution",
            get(workstream_plan_execution_state_handler),
        )
        .route(
            "/api/darwin/workstreams/:workstream_id/plan-execution/approve",
            post(workstream_plan_execution_approve_handler),
        )
        .route(
            "/api/darwin/workstreams/:workstream_id/plan-execution/start",
            post(workstream_plan_execution_start_handler),
        )
        .route(
            "/api/darwin/workstreams/:workstream_id/plan-execution/stop",
            post(workstream_plan_execution_stop_handler),
        )
        .route(
            "/api/darwin/workstreams/:workstream_id/plan-execution/receipt",
            get(workstream_plan_execution_receipt_handler),
        )
        .route(
            "/api/darwin/workstreams/:workstream_id/plan-execution/result-links",
            get(workstream_plan_execution_result_links_handler),
        )
        .route(
            "/api/darwin/workstreams/:workstream_id/plan-execution/reflection",
            get(workstream_plan_execution_reflection_handler),
        )
        .route(
            "/api/darwin/workstreams/:workstream_id/plan-execution/trajectory-eval",
            get(workstream_plan_execution_trajectory_eval_handler),
        )
        .route(
            "/api/darwin/workstreams/:workstream_id/plan-execution/replan-suggestion",
            get(workstream_plan_execution_replan_suggestion_handler),
        )
        .route(
            "/api/darwin/workstreams/:workstream_id/review-inbox",
            get(workstream_review_inbox_handler)
                .post(workstream_review_inbox_materialize_handler),
        )
        .route(
            "/api/darwin/workstreams/:workstream_id/review-inbox/decision",
            get(workstream_review_decision_handler)
                .post(workstream_review_inbox_decision_handler),
        )
        .route(
            "/api/darwin/workstreams/:workstream_id/follow-on-plan",
            get(workstream_follow_on_plan_handler),
        )
        .route(
            "/api/darwin/workstreams/:workstream_id/autonomy-policy",
            get(workstream_autonomy_policy_handler),
        )
        .route(
            "/api/darwin/workstreams/:workstream_id/risk-evaluation",
            get(workstream_risk_evaluation_handler),
        )
        .route(
            "/api/darwin/workstreams/:workstream_id/approval-gating-decision",
            get(workstream_approval_gating_decision_handler),
        )
        .route(
            "/api/darwin/workstreams/:workstream_id/autonomy-calibration-dataset",
            get(workstream_autonomy_calibration_dataset_handler),
        )
        .route(
            "/api/darwin/workstreams/:workstream_id/autonomy-policy-eval-report",
            get(workstream_autonomy_policy_eval_report_handler),
        )
        .route(
            "/api/darwin/workstreams/:workstream_id/escalation-thresholds",
            get(workstream_escalation_thresholds_handler),
        )
        .route(
            "/api/darwin/workstreams/:workstream_id/shadow-policy-comparison",
            get(workstream_shadow_policy_comparison_handler),
        )
        .route(
            "/api/darwin/workstreams/:workstream_id/updated-policy-recommendation",
            get(workstream_updated_policy_recommendation_handler),
        )
        .route(
            "/api/darwin/workstreams/:workstream_id/autonomy-policy-current",
            get(workstream_autonomy_policy_current_handler),
        )
        .route(
            "/api/darwin/workstreams/:workstream_id/autonomy-policy-candidate",
            get(workstream_autonomy_policy_candidate_handler),
        )
        .route(
            "/api/darwin/workstreams/:workstream_id/rollout-metrics",
            get(workstream_rollout_metrics_handler),
        )
        .route(
            "/api/darwin/workstreams/:workstream_id/guarded-rollout-decision",
            get(workstream_guarded_rollout_decision_handler),
        )
        .route(
            "/api/darwin/workstreams/:workstream_id/autonomy-policy-control",
            get(workstream_autonomy_policy_control_handler),
        )
        .route(
            "/api/darwin/workstreams/:workstream_id/autonomy-policy-canary",
            get(workstream_autonomy_policy_canary_handler),
        )
        .route(
            "/api/darwin/workstreams/:workstream_id/canary-rollout-metrics",
            get(workstream_canary_rollout_metrics_handler),
        )
        .route(
            "/api/darwin/workstreams/:workstream_id/canary-rollback-decision",
            get(workstream_canary_rollback_decision_handler),
        )
        .route(
            "/api/darwin/workstreams/:workstream_id/autonomy-policy-analysis-candidate",
            get(workstream_autonomy_policy_analysis_candidate_handler),
        )
        .route(
            "/api/darwin/workstreams/:workstream_id/analysis-shadow-comparison",
            get(workstream_analysis_shadow_comparison_handler),
        )
        .route(
            "/api/darwin/workstreams/:workstream_id/analysis-rollout-metrics",
            get(workstream_analysis_rollout_metrics_handler),
        )
        .route(
            "/api/darwin/workstreams/:workstream_id/analysis-rollout-decision",
            get(workstream_analysis_rollout_decision_handler),
        )
        .route(
            "/api/darwin/workstreams/:workstream_id/analysis-shadow-history",
            get(workstream_analysis_shadow_history_handler),
        )
        .route(
            "/api/darwin/workstreams/:workstream_id/analysis-soak-metrics",
            get(workstream_analysis_soak_metrics_handler),
        )
        .route(
            "/api/darwin/workstreams/:workstream_id/analysis-promotion-gate",
            get(workstream_analysis_promotion_gate_handler),
        )
        .route(
            "/api/darwin/workstreams/:workstream_id/analysis-sample-accumulation",
            get(workstream_analysis_sample_accumulation_handler),
        )
        .route(
            "/api/darwin/workstreams/:workstream_id/analysis-sample-accumulation-metrics",
            get(workstream_analysis_sample_accumulation_metrics_handler),
        )
        .route(
            "/api/darwin/workstreams/:workstream_id/analysis-promotion-gate-recheck",
            get(workstream_analysis_promotion_gate_recheck_handler),
        )
        .route(
            "/api/darwin/workstreams/:workstream_id/autonomy-policy-analysis-control",
            get(workstream_autonomy_policy_analysis_control_handler),
        )
        .route(
            "/api/darwin/workstreams/:workstream_id/autonomy-policy-implementation-canary",
            get(workstream_autonomy_policy_implementation_canary_handler),
        )
        .route(
            "/api/darwin/workstreams/:workstream_id/autonomy-policy-analysis-canary",
            get(workstream_autonomy_policy_analysis_canary_handler),
        )
        .route(
            "/api/darwin/workstreams/:workstream_id/analysis-canary-metrics",
            get(workstream_analysis_canary_metrics_handler),
        )
        .route(
            "/api/darwin/workstreams/:workstream_id/analysis-canary-rollback-decision",
            get(workstream_analysis_canary_rollback_decision_handler),
        )
        .route(
            "/api/darwin/workstreams/:workstream_id/autonomy-policy-manuscript-control",
            get(workstream_autonomy_policy_manuscript_control_handler),
        )
        .route(
            "/api/darwin/workstreams/:workstream_id/autonomy-policy-manuscript-candidate",
            get(workstream_autonomy_policy_manuscript_candidate_handler),
        )
        .route(
            "/api/darwin/workstreams/:workstream_id/manuscript-shadow-comparison",
            get(workstream_manuscript_shadow_comparison_handler),
        )
        .route(
            "/api/darwin/workstreams/:workstream_id/manuscript-rollout-metrics",
            get(workstream_manuscript_rollout_metrics_handler),
        )
        .route(
            "/api/darwin/workstreams/:workstream_id/manuscript-rollout-decision",
            get(workstream_manuscript_rollout_decision_handler),
        )
        .route(
            "/api/darwin/workstreams/:workstream_id/manuscript-shadow-history",
            get(workstream_manuscript_shadow_history_handler),
        )
        .route(
            "/api/darwin/workstreams/:workstream_id/manuscript-soak-metrics",
            get(workstream_manuscript_soak_metrics_handler),
        )
        .route(
            "/api/darwin/workstreams/:workstream_id/manuscript-alignment-labels",
            get(workstream_manuscript_alignment_labels_handler),
        )
        .route(
            "/api/darwin/workstreams/:workstream_id/manuscript-promotion-evidence",
            get(workstream_manuscript_promotion_evidence_handler),
        )
        .route(
            "/api/darwin/workstreams/:workstream_id/manuscript-promotion-gate",
            get(workstream_manuscript_promotion_gate_handler),
        )
        .route(
            "/api/darwin/workstreams/:workstream_id/manuscript-trajectory-quality",
            get(workstream_manuscript_trajectory_quality_handler),
        )
        .route(
            "/api/darwin/workstreams/:workstream_id/manuscript-context-adequacy",
            get(workstream_manuscript_context_adequacy_handler),
        )
        .route(
            "/api/darwin/workstreams/:workstream_id/manuscript-tuning-recommendation",
            get(workstream_manuscript_tuning_recommendation_handler),
        )
        .route(
            "/api/darwin/workstreams/:workstream_id/continuation-dispatch",
            get(workstream_continuation_dispatch_handler)
                .post(workstream_continuation_dispatch_post_handler),
        )
        .route(
            "/api/darwin/workstreams/:workstream_id/continuation-receipt",
            get(workstream_continuation_receipt_handler),
        )
        .route(
            "/api/darwin/workstreams/:workstream_id/continuation-state",
            get(workstream_continuation_state_handler),
        )
        .route(
            "/api/darwin/workstreams/:workstream_id/workspace-habitat",
            get(workstream_workspace_habitat_handler),
        )
        .route(
            "/api/darwin/workstreams/:workstream_id/workspace-habitat/context.env",
            get(workstream_workspace_habitat_env_handler),
        )
        .route(
            "/api/darwin/workstreams/:workstream_id/workspace-attach",
            get(workstream_workspace_attach_handler),
        )
        .route(
            "/api/darwin/workstreams/:workstream_id/managed-attach",
            get(workstream_managed_attach_handler),
        )
        .route(
            "/api/darwin/workstreams/:workstream_id/workspace-launch-resume",
            get(workstream_workspace_launch_resume_handler),
        )
        .route(
            "/api/darwin/workstreams/:workstream_id/workspace-template",
            get(workstream_workspace_template_handler),
        )
        .route(
            "/api/darwin/workstreams/:workstream_id/collaborative-workbench",
            get(workstream_collaborative_workbench_handler),
        )
        .route(
            "/api/darwin/workstreams/:workstream_id/workbench-session",
            get(workstream_workbench_session_handler),
        )
        .route(
            "/api/darwin/workstreams/:workstream_id/compute-selection",
            get(workstream_compute_selection_handler),
        )
        .route(
            "/api/darwin/workstreams/:workstream_id/collaboration-access",
            get(workstream_collaboration_access_handler),
        )
        .route(
            "/api/darwin/workstreams/:workstream_id/workbench-run",
            get(workstream_workbench_run_handler)
                .post(workstream_workbench_run_orchestrate_handler),
        )
        .route(
            "/api/darwin/workstreams/:workstream_id/workbench-reservation",
            get(workstream_workbench_reservation_handler),
        )
        .route(
            "/api/darwin/workstreams/:workstream_id/workbench-run-orchestration",
            get(workstream_workbench_run_orchestration_handler),
        )
        .route(
            "/api/darwin/workstreams/:workstream_id/workbench-result-binding",
            get(workstream_workbench_result_binding_handler),
        )
        .route(
            "/api/darwin/workstreams/:workstream_id/run-result-identity-receipt",
            get(workstream_run_result_identity_receipt_handler),
        )
        .route(
            "/api/darwin/workstreams/:workstream_id/run-scoped-publication",
            get(workstream_run_scoped_publication_handler),
        )
        .route(
            "/api/darwin/workstreams/:workstream_id/deterministic-result-binding",
            get(workstream_deterministic_result_binding_handler),
        )
        .route(
            "/api/darwin/workstreams/:workstream_id/run-capsule",
            get(workstream_run_capsule_handler),
        )
        .route(
            "/api/darwin/workstreams/:workstream_id/prior-run-capsule",
            get(workstream_prior_run_capsule_handler),
        )
        .route(
            "/api/darwin/workstreams/:workstream_id/run-diff",
            get(workstream_run_diff_handler),
        )
        .route(
            "/api/darwin/workstreams/:workstream_id/replay-request",
            get(workstream_replay_request_handler),
        )
        .route(
            "/api/darwin/workstreams/:workstream_id/replay-execution",
            get(workstream_replay_execution_handler)
                .post(workstream_replay_execution_dispatch_handler),
        )
        .route(
            "/api/darwin/workstreams/:workstream_id/study-registry",
            get(workstream_study_registry_handler),
        )
        .route(
            "/api/darwin/workstreams/:workstream_id/study-dag",
            get(workstream_study_dag_handler),
        )
        .route(
            "/api/darwin/workstreams/:workstream_id/study-sweep",
            get(workstream_study_sweep_handler),
        )
        .route(
            "/api/darwin/workstreams/:workstream_id/comparative-result-summary",
            get(workstream_comparative_result_summary_handler),
        )
        .route(
            "/api/darwin/workstreams/:workstream_id/study-decision",
            get(workstream_study_decision_handler),
        )
        .route(
            "/api/darwin/workstreams/:workstream_id/study-decision-basis",
            get(workstream_study_decision_basis_handler),
        )
        .route(
            "/api/darwin/workstreams/:workstream_id/next-run-proposal",
            get(workstream_next_run_proposal_handler),
        )
        .route(
            "/api/darwin/workstreams/:workstream_id/study-proposal-dispatch",
            get(workstream_study_proposal_dispatch_handler)
                .post(workstream_study_proposal_dispatch_post_handler),
        )
        .route(
            "/api/darwin/workstreams/:workstream_id/study-run-update",
            get(workstream_study_run_update_handler),
        )
        .route(
            "/api/darwin/workstreams/:workstream_id/study-continuation-state",
            get(workstream_study_continuation_state_handler),
        )
        .route(
            "/api/darwin/workstreams/:workstream_id/study-convergence",
            get(workstream_study_convergence_handler),
        )
        .route(
            "/api/darwin/workstreams/:workstream_id/study-promotion-execution",
            get(workstream_study_promotion_execution_handler),
        )
        .route(
            "/api/darwin/workstreams/:workstream_id/baseline-adoption",
            get(workstream_baseline_adoption_handler),
        )
        .route(
            "/api/darwin/workstreams/:workstream_id/baseline-rollback-plan",
            get(workstream_baseline_rollback_plan_handler),
        )
        .route(
            "/api/darwin/workstreams/:workstream_id/next-study-seed",
            get(workstream_next_study_seed_handler),
        )
        .route(
            "/api/darwin/workstreams/:workstream_id/study-continuation",
            get(workstream_study_continuation_handler),
        )
        .route(
            "/api/darwin/workstreams/:workstream_id/code-provenance",
            get(workstream_code_provenance_handler),
        )
        .route(
            "/api/darwin/workstreams/:workstream_id/workspace-snapshot",
            get(workstream_workspace_snapshot_handler),
        )
        .route(
            "/api/darwin/workstreams/:workstream_id/source-fingerprint",
            get(workstream_source_fingerprint_handler),
        )
        .route(
            "/api/darwin/workstreams/:workstream_id/workspace-tenancy",
            get(workstream_workspace_tenancy_handler),
        )
        .route(
            "/api/darwin/workstreams/:workstream_id/compute-tenancy",
            get(workstream_compute_tenancy_handler),
        )
        .route(
            "/api/darwin/workstreams/:workstream_id/partner-access",
            get(workstream_partner_access_handler),
        )
        .route(
            "/api/darwin/workstreams/:workstream_id/workspace-subagents",
            get(workstream_workspace_subagents_handler),
        )
        .route(
            "/api/darwin/workstreams/:workstream_id/workspace-subagent-list",
            get(workstream_workspace_subagent_list_handler),
        )
        .route(
            "/api/darwin/workstreams/:workstream_id/workspace-subagent-route",
            get(workstream_workspace_subagent_route_handler),
        )
        .route(
            "/api/darwin/workstreams/:workstream_id/workspace-subagent-handoff",
            get(workstream_workspace_subagent_handoff_handler)
                .post(workstream_workspace_subagent_handoff_record_handler),
        )
        .route(
            "/api/darwin/workstreams/:workstream_id/workspace-manuscript-handoff",
            get(workstream_workspace_manuscript_handoff_handler)
                .post(workstream_workspace_manuscript_handoff_record_handler),
        )
        .route(
            "/api/darwin/workstreams/:workstream_id/workspace-manuscript-assembly",
            get(workstream_workspace_manuscript_assembly_handler)
                .post(workstream_workspace_manuscript_assembly_record_handler),
        )
        .route(
            "/api/darwin/workstreams/:workstream_id/workspace-scholarly-release",
            get(workstream_workspace_scholarly_release_handler)
                .post(workstream_workspace_scholarly_release_record_handler),
        )
        .route(
            "/api/darwin/workstreams/:workstream_id/workspace-publication-package",
            get(workstream_workspace_publication_package_handler)
                .post(workstream_workspace_publication_package_record_handler),
        )
        .route(
            "/api/darwin/workstreams/:workstream_id/workspace-external-staging",
            get(workstream_workspace_external_staging_handler)
                .post(workstream_workspace_external_staging_record_handler),
        )
        .route(
            "/api/darwin/workstreams/:workstream_id/workspace-sandbox-deposit",
            get(workstream_workspace_sandbox_deposit_handler)
                .post(workstream_workspace_sandbox_deposit_record_handler),
        )
        .route(
            "/api/darwin/workstreams/:workstream_id/cursor-remote-lane",
            get(workstream_cursor_remote_lane_handler),
        )
        .route(
            "/api/darwin/workstreams/:workstream_id/cursor-native-attach",
            get(workstream_cursor_remote_lane_handler),
        )
        .route(
            "/api/darwin/workstreams/:workstream_id/tool-dock/:tool_id",
            get(workstream_tool_launch_handler),
        )
        .route(
            "/api/darwin/workstreams/:workstream_id/tool-return",
            post(workstream_tool_return_handler),
        )
        .route(
            "/api/darwin/workstreams/:workstream_id/recipes",
            get(workstream_control_room_recipes_handler),
        )
        .route(
            "/api/darwin/workstreams/:workstream_id/status",
            get(workstream_control_room_status_handler),
        )
        .route(
            "/api/darwin/workstreams/:workstream_id/last-result",
            get(workstream_control_room_last_result_handler),
        )
        .route(
            "/api/darwin/workstreams/:workstream_id/timeline/:event_id",
            get(workstream_timeline_event_handler),
        )
        .route(
            "/api/darwin/workstreams/:workstream_id/timeline",
            get(workstream_timeline_handler),
        )
        .route(
            "/api/darwin/workstreams/:workstream_id/handoff",
            get(workstream_control_room_handoff_handler),
        )
        .route(
            "/api/darwin/workstreams/:workstream_id/hold",
            post(workstream_control_room_hold_handler),
        )
        .route(
            "/api/darwin/workstreams/:workstream_id/resume",
            post(workstream_control_room_resume_handler),
        )
        .route(
            "/api/darwin/workstreams/:workstream_id",
            get(workstream_control_room_detail_handler),
        )
        .route(
            "/darwin/workstreams/:workstream_id/cockpit",
            get(workstream_cockpit_page_handler),
        )
        .route("/api/darwin/consumers/self", get(consumer_self_handler))
        .route("/api/darwin/hpc/control", get(hpc_control_handler))
        .route("/api/darwin/hpc/profiles", get(hpc_profiles_handler))
        .route("/api/darwin/hpc/jobs/submit", post(hpc_job_submit_handler))
        .route("/api/darwin/hpc/jobs/:job_id", get(hpc_job_status_handler))
        .route(
            "/api/darwin/hpc/jobs/:job_id/artifact-manifest",
            get(hpc_job_manifest_handler),
        )
        .route("/api/darwin/hpc/jobs/:job_id/stdout", get(hpc_job_stdout_handler))
        .route("/api/darwin/hpc/jobs/:job_id/stderr", get(hpc_job_stderr_handler))
        .route("/api/darwin/hpc/results", get(hpc_results_handler))
        .route("/api/darwin/hpc/results/:job_id", get(hpc_result_lookup_handler))
        .route(
            "/api/darwin/hpc/results/:job_id/manifest",
            get(hpc_result_manifest_handler),
        )
        .route("/api/darwin/bridge/execute", post(bridge_execute_handler))
        .route("/api/darwin/bridge/health", get(bridge_health_handler))
        .route("/api/darwin/bridge/providers", get(bridge_providers_handler))
}

#[derive(Debug, Deserialize)]
struct ResultsQueryParams {
    #[serde(default)]
    profile_id: Option<String>,
    #[serde(default)]
    run_label: Option<String>,
    #[serde(default)]
    state: Option<String>,
    #[serde(default)]
    node_list: Option<String>,
}

#[derive(Debug, Deserialize)]
struct WorkspaceQueryParams {
    #[serde(default)]
    workstream_id: Option<String>,
    #[serde(default)]
    workspace_id: Option<String>,
    #[serde(default)]
    session_id: Option<String>,
}

#[derive(Debug, Deserialize)]
struct WorkspaceSubAgentRouteQueryParams {
    #[serde(default)]
    tool_id: Option<String>,
    #[serde(default)]
    work_mode: Option<String>,
    #[serde(default)]
    preferred_subagent: Option<String>,
}

#[derive(Debug, Deserialize)]
struct WorkspaceSubAgentHandoffRequestBody {
    source_subagent_id: String,
    target_subagent_id: String,
    intent: String,
    summary: String,
    #[serde(default)]
    requested_work_mode: Option<String>,
    #[serde(default)]
    requested_tool_id: Option<String>,
}

#[derive(Debug, Deserialize)]
struct WorkspaceManuscriptHandoffRequestBody {
    source_subagent_id: String,
    intent: String,
    summary: String,
    manuscript_goal: String,
    #[serde(default)]
    requested_work_mode: Option<String>,
    #[serde(default)]
    requested_tool_id: Option<String>,
}

#[derive(Debug, Deserialize)]
struct WorkspaceManuscriptAssemblyRequestBody {
    source_subagent_id: String,
    intent: String,
    summary: String,
    assembly_goal: String,
    #[serde(default)]
    requested_tool_id: Option<String>,
    #[serde(default)]
    section_profile: Option<String>,
}

#[derive(Debug, Deserialize)]
struct WorkspaceScholarlyReleaseRequestBody {
    source_subagent_id: String,
    summary: String,
    release_goal: String,
    release_notes: String,
    #[serde(default)]
    requested_tool_id: Option<String>,
}

#[derive(Debug, Deserialize)]
struct WorkspacePublicationPackageRequestBody {
    source_subagent_id: String,
    summary: String,
    publication_goal: String,
    staging_notes: String,
    #[serde(default)]
    requested_tool_id: Option<String>,
}

#[derive(Debug, Deserialize)]
struct WorkspaceExternalRegistryStagingRequestBody {
    source_subagent_id: String,
    summary: String,
    staging_goal: String,
    dry_run_notes: String,
    #[serde(default)]
    requested_tool_id: Option<String>,
}

#[derive(Debug, Deserialize)]
struct WorkspaceSandboxDepositHandshakeRequestBody {
    source_subagent_id: String,
    summary: String,
    handshake_goal: String,
    handshake_notes: String,
    #[serde(default)]
    requested_tool_id: Option<String>,
}

#[derive(Debug, Deserialize)]
struct TimelineQueryParams {
    #[serde(default)]
    limit: Option<usize>,
}

#[derive(Debug, Serialize)]
struct HpcControlSurfaceSummary {
    status: String,
    gateway_base_url: String,
    profiles: Vec<HpcProfile>,
    recent_results: Vec<ResultCatalogEntry>,
    bridge_health: BridgeHealth,
    bridge_providers: Vec<BridgeProviderInfo>,
    recent_bridge_ledger: Vec<BridgeLedgerEntry>,
}

async fn workspace_bootstrap_handler(
    State(state): State<AppState>,
    Extension(consumer): Extension<ConsumerIdentity>,
    Query(query): Query<WorkspaceQueryParams>,
) -> Result<Json<WorkspaceBootstrapResponse>, JsonError> {
    ensure_allowed(consumer.ensure_workspace_plane())?;
    let cfg = current_cfg(&state).await;
    let data_dir = FsPath::new(&cfg.storage.data_dir);

    let response = if let Some(workstream_id) = query
        .workstream_id
        .as_deref()
        .map(str::trim)
        .filter(|value| !value.is_empty())
    {
        let binding = beagle_config::resolve_workspace_habitat_binding(&cfg, workstream_id)
            .ok_or_else(|| {
                internal_error_response(
                    "workspace_bootstrap_binding_not_found",
                    format!("no workspace habitat binding found for workstream {}", workstream_id),
                )
            })?;
        let override_payload = beagle_darwin::WorkspacePilotWorkstreamOverride {
            workstream_id: binding.workstream_id.clone(),
            canonical_repo: Some(binding.canonical_repo.clone()),
            default_branch: binding.canonical_branch.clone(),
            canonical_track: Some(binding.canonical_track.clone()),
            branch_lineage: Some(binding.branch_lineage.clone()),
            governance_state: Some(binding.governance_state.clone()),
            governance_last_transition: Some(binding.governance_last_transition.clone()),
            default_dev_plane: Some(binding.default_dev_plane.clone()),
            vm_fallback_role: Some(binding.vm_fallback_role.clone()),
            promotion_scope: Some(binding.promotion_scope.clone()),
        };
        bootstrap_workspace_session_for_workstream(
            data_dir,
            &cfg,
            query
                .workspace_id
                .as_deref()
                .or(Some(binding.workspace_id.as_str())),
            query
                .session_id
                .as_deref()
                .or(Some(binding.session_id.as_str())),
            &override_payload,
        )
    } else {
        bootstrap_workspace_session(
            data_dir,
            &cfg,
            query.workspace_id.as_deref(),
            query.session_id.as_deref(),
        )
    }
    .map_err(|error| internal_error_response("workspace_bootstrap_failed", error.to_string()))?;

    Ok(Json(response))
}

async fn workspace_session_handler(
    State(state): State<AppState>,
    Extension(consumer): Extension<ConsumerIdentity>,
    Query(query): Query<WorkspaceQueryParams>,
) -> Result<Json<WorkspaceSessionState>, JsonError> {
    ensure_allowed(consumer.ensure_workspace_plane())?;
    let cfg = current_cfg(&state).await;
    let data_dir = FsPath::new(&cfg.storage.data_dir);
    let resolved_binding = query
        .workstream_id
        .as_deref()
        .and_then(|workstream_id| beagle_config::resolve_workspace_habitat_binding(&cfg, workstream_id));
    let workspace_id = query
        .workspace_id
        .as_deref()
        .or_else(|| resolved_binding.as_ref().map(|binding| binding.workspace_id.as_str()))
        .unwrap_or(&cfg.workspace.canonical_workspace_id);

    match load_workspace_session(data_dir, &cfg, workspace_id)
        .map_err(|error| internal_error_response("workspace_session_read_failed", error.to_string()))?
    {
        Some(session) => Ok(Json(session)),
        None => Err(not_found_response(
            "workspace_session_not_found",
            format!("no session recorded for workspace {}", workspace_id),
        )),
    }
}

async fn workspace_fallback_start_handler(
    State(state): State<AppState>,
    Extension(consumer): Extension<ConsumerIdentity>,
    Json(request): Json<WorkspaceFallbackDrillRequest>,
) -> Result<Json<WorkspaceFallbackDrillResponse>, JsonError> {
    ensure_allowed(consumer.ensure_workspace_plane())?;
    let cfg = current_cfg(&state).await;
    let data_dir = FsPath::new(&cfg.storage.data_dir);

    let response = record_workspace_fallback_start(data_dir, &cfg, &request).map_err(|error| {
        internal_error_response("workspace_fallback_start_failed", error.to_string())
    })?;

    Ok(Json(response))
}

async fn workspace_fallback_return_handler(
    State(state): State<AppState>,
    Extension(consumer): Extension<ConsumerIdentity>,
    Json(request): Json<WorkspaceFallbackDrillRequest>,
) -> Result<Json<WorkspaceFallbackDrillResponse>, JsonError> {
    ensure_allowed(consumer.ensure_workspace_plane())?;
    let cfg = current_cfg(&state).await;
    let data_dir = FsPath::new(&cfg.storage.data_dir);

    let response = record_workspace_fallback_return(data_dir, &cfg, &request).map_err(|error| {
        internal_error_response("workspace_fallback_return_failed", error.to_string())
    })?;

    Ok(Json(response))
}

async fn workspace_pilot_execute_handler(
    State(state): State<AppState>,
    Extension(consumer): Extension<ConsumerIdentity>,
    Json(request): Json<WorkspacePilotRequest>,
) -> Result<Json<WorkspacePilotResponse>, JsonError> {
    ensure_allowed(consumer.ensure_workspace_plane())?;
    if let Some(profile_id) = request.profile_id.as_deref() {
        ensure_allowed(consumer.ensure_hpc_submit(profile_id))?;
    }
    let cfg = current_cfg(&state).await;
    let data_dir = FsPath::new(&cfg.storage.data_dir);
    let gateway = gateway_client()?;
    let bridge = tool_bridge_from_cfg(&cfg)?;

    let response = run_workspace_pilot(data_dir, &cfg, &gateway, &bridge, &request)
        .await
        .map_err(|error| internal_error_response("workspace_pilot_failed", error.to_string()))?;

    Ok(Json(response))
}

async fn workstream_control_room_list_handler(
    State(state): State<AppState>,
    Extension(consumer): Extension<ConsumerIdentity>,
) -> Result<Json<WorkstreamControlRoomListResponse>, JsonError> {
    ensure_allowed(consumer.ensure_workspace_plane())?;
    let cfg = current_cfg(&state).await;
    let data_dir = FsPath::new(&cfg.storage.data_dir);

    let response = list_workstream_control_room(data_dir, &cfg).map_err(|error| {
        internal_error_response("workstream_control_room_list_failed", error.to_string())
    })?;

    Ok(Json(response))
}

async fn workstream_portfolio_control_room_handler(
    State(state): State<AppState>,
    Extension(consumer): Extension<ConsumerIdentity>,
) -> Result<Json<WorkstreamPortfolioResponse>, JsonError> {
    ensure_allowed(consumer.ensure_workspace_plane())?;
    ensure_allowed(consumer.ensure_hpc_read())?;
    let cfg = current_cfg(&state).await;
    let data_dir = FsPath::new(&cfg.storage.data_dir);
    let gateway = gateway_client()?;

    let response = get_workstream_portfolio_control_room(data_dir, &cfg, &gateway)
        .await
        .map_err(|error| internal_error_response("workstream_portfolio_control_room_failed", error.to_string()))?;

    Ok(Json(response))
}

async fn program_context_packet_handler(
    State(state): State<AppState>,
    Extension(consumer): Extension<ConsumerIdentity>,
    Path(program_id): Path<String>,
) -> Result<Json<ProgramContextPacketResponse>, JsonError> {
    ensure_allowed(consumer.ensure_workspace_plane())?;
    ensure_allowed(consumer.ensure_hpc_read())?;
    let cfg = current_cfg(&state).await;
    let data_dir = FsPath::new(&cfg.storage.data_dir);
    let gateway = gateway_client()?;

    let response =
        resolve_program_context_packet(&state, data_dir, &cfg, &gateway, &program_id).await?;

    Ok(Json(response))
}

async fn campaign_context_packet_handler(
    State(state): State<AppState>,
    Extension(consumer): Extension<ConsumerIdentity>,
    Path(campaign_id): Path<String>,
) -> Result<Json<ProgramContextPacketResponse>, JsonError> {
    ensure_allowed(consumer.ensure_workspace_plane())?;
    ensure_allowed(consumer.ensure_hpc_read())?;
    let cfg = current_cfg(&state).await;
    let data_dir = FsPath::new(&cfg.storage.data_dir);
    let gateway = gateway_client()?;

    let response =
        resolve_campaign_context_packet(&state, data_dir, &cfg, &gateway, &campaign_id).await?;

    Ok(Json(response))
}

async fn campaign_evidence_pack_handler(
    State(state): State<AppState>,
    Extension(consumer): Extension<ConsumerIdentity>,
    Path(campaign_id): Path<String>,
) -> Result<Json<EvidencePackResponse>, JsonError> {
    ensure_allowed(consumer.ensure_workspace_plane())?;
    ensure_allowed(consumer.ensure_hpc_read())?;
    let cfg = current_cfg(&state).await;
    let data_dir = FsPath::new(&cfg.storage.data_dir);
    let gateway = gateway_client()?;

    let response =
        resolve_campaign_evidence_pack(&state, data_dir, &cfg, &gateway, &campaign_id).await?;

    Ok(Json(response))
}

async fn campaign_claims_handler(
    State(state): State<AppState>,
    Extension(consumer): Extension<ConsumerIdentity>,
    Path(campaign_id): Path<String>,
) -> Result<Json<CampaignClaimsResponse>, JsonError> {
    ensure_allowed(consumer.ensure_workspace_plane())?;
    ensure_allowed(consumer.ensure_hpc_read())?;
    let cfg = current_cfg(&state).await;
    let data_dir = FsPath::new(&cfg.storage.data_dir);
    let gateway = gateway_client()?;

    let response = resolve_campaign_claims(&state, data_dir, &cfg, &gateway, &campaign_id).await?;

    Ok(Json(response))
}

async fn campaign_manuscript_pack_handler(
    State(state): State<AppState>,
    Extension(consumer): Extension<ConsumerIdentity>,
    Path(campaign_id): Path<String>,
) -> Result<Json<ManuscriptPackResponse>, JsonError> {
    ensure_allowed(consumer.ensure_workspace_plane())?;
    ensure_allowed(consumer.ensure_hpc_read())?;
    let cfg = current_cfg(&state).await;
    let data_dir = FsPath::new(&cfg.storage.data_dir);
    let gateway = gateway_client()?;

    let response =
        resolve_campaign_manuscript_pack(&state, data_dir, &cfg, &gateway, &campaign_id).await?;

    Ok(Json(response))
}

async fn campaign_review_bundle_handler(
    State(state): State<AppState>,
    Extension(consumer): Extension<ConsumerIdentity>,
    Path(campaign_id): Path<String>,
) -> Result<Json<ReviewBundleResponse>, JsonError> {
    ensure_allowed(consumer.ensure_workspace_plane())?;
    ensure_allowed(consumer.ensure_hpc_read())?;
    let cfg = current_cfg(&state).await;
    let data_dir = FsPath::new(&cfg.storage.data_dir);
    let gateway = gateway_client()?;

    let response =
        resolve_campaign_review_bundle(&state, data_dir, &cfg, &gateway, &campaign_id).await?;

    Ok(Json(response))
}

async fn campaign_jats_manuscript_pack_handler(
    State(state): State<AppState>,
    Extension(consumer): Extension<ConsumerIdentity>,
    Path(campaign_id): Path<String>,
) -> Result<Json<JatsManuscriptPackResponse>, JsonError> {
    ensure_allowed(consumer.ensure_workspace_plane())?;
    ensure_allowed(consumer.ensure_hpc_read())?;
    let cfg = current_cfg(&state).await;
    let data_dir = FsPath::new(&cfg.storage.data_dir);
    let gateway = gateway_client()?;

    let response =
        resolve_campaign_jats_manuscript_pack(&state, data_dir, &cfg, &gateway, &campaign_id)
            .await?;

    Ok(Json(response))
}

async fn workstream_control_room_detail_handler(
    State(state): State<AppState>,
    Extension(consumer): Extension<ConsumerIdentity>,
    Path(workstream_id): Path<String>,
) -> Result<Json<WorkstreamControlRoomDetailResponse>, JsonError> {
    ensure_allowed(consumer.ensure_workspace_plane())?;
    let cfg = current_cfg(&state).await;
    let data_dir = FsPath::new(&cfg.storage.data_dir);

    let response = get_workstream_control_room_detail(data_dir, &cfg, &workstream_id)
        .map_err(|error| workstream_control_room_error(&workstream_id, error.to_string()))?;

    Ok(Json(response))
}

async fn workstream_cockpit_handler(
    State(state): State<AppState>,
    Extension(consumer): Extension<ConsumerIdentity>,
    Path(workstream_id): Path<String>,
) -> Result<Json<WorkstreamCockpitResponse>, JsonError> {
    ensure_allowed(consumer.ensure_workspace_plane())?;
    ensure_allowed(consumer.ensure_hpc_read())?;
    let cfg = current_cfg(&state).await;
    let data_dir = FsPath::new(&cfg.storage.data_dir);
    let gateway = gateway_client()?;
    let context_packet =
        resolve_workstream_context_packet(&state, data_dir, &cfg, &gateway, &workstream_id).await?;

    let response = get_workstream_cockpit_with_context_packet(
        data_dir,
        &cfg,
        &gateway,
        &workstream_id,
        context_packet,
    )
        .await
        .map_err(|error| workstream_control_room_error(&workstream_id, error.to_string()))?;

    Ok(Json(response))
}

async fn workstream_context_packet_handler(
    State(state): State<AppState>,
    Extension(consumer): Extension<ConsumerIdentity>,
    Path(workstream_id): Path<String>,
) -> Result<Json<WorkstreamContextPacketResponse>, JsonError> {
    ensure_allowed(consumer.ensure_workspace_plane())?;
    ensure_allowed(consumer.ensure_hpc_read())?;
    let cfg = current_cfg(&state).await;
    let data_dir = FsPath::new(&cfg.storage.data_dir);
    let gateway = gateway_client()?;

    let response = resolve_workstream_context_packet_with_manuscript_quality_sync(
        &state,
        data_dir,
        &cfg,
        &gateway,
        &workstream_id,
    )
    .await?;

    Ok(Json(response))
}

async fn workstream_tool_launch_handler(
    State(state): State<AppState>,
    Extension(consumer): Extension<ConsumerIdentity>,
    Path((workstream_id, tool_id)): Path<(String, String)>,
) -> Result<Json<WorkstreamPremiumToolLaunchResponse>, JsonError> {
    ensure_allowed(consumer.ensure_workspace_plane())?;
    ensure_allowed(consumer.ensure_hpc_read())?;
    let cfg = current_cfg(&state).await;
    let data_dir = FsPath::new(&cfg.storage.data_dir);
    let gateway = gateway_client()?;
    let mut context_packet =
        resolve_workstream_context_packet(&state, data_dir, &cfg, &gateway, &workstream_id).await?;
    let detail = get_workstream_control_room_detail(data_dir, &cfg, &workstream_id)
        .map_err(|error| workstream_control_room_error(&workstream_id, error.to_string()))?;
    let suggested_work_mode = context_packet
        .packet
        .retrieval_context
        .as_ref()
        .and_then(|context| context.suggested_work_mode.as_deref());
    if let Ok(compiled) = resolve_workstream_compiled_context(
        &state,
        &detail,
        None,
        Some(&tool_id),
        suggested_work_mode,
        None,
    )
    .await
    {
        apply_compiled_context_to_packet(&mut context_packet.packet, &compiled);
    }
    apply_intent_planner_to_packet(&mut context_packet.packet);

    let response = get_premium_tool_launch_surface_with_context_packet(
        data_dir,
        &cfg,
        &gateway,
        &workstream_id,
        &tool_id,
        context_packet,
    )
        .await
        .map_err(|error| workstream_control_room_error(&workstream_id, error.to_string()))?;

    Ok(Json(response))
}

async fn workstream_compiled_context_handler(
    State(state): State<AppState>,
    Extension(consumer): Extension<ConsumerIdentity>,
    Path(workstream_id): Path<String>,
    Json(req): Json<WorkstreamCompiledContextQuery>,
) -> Result<Json<beagle_memory::CompiledContextPacket>, JsonError> {
    ensure_allowed(consumer.ensure_workspace_plane())?;
    ensure_allowed(consumer.ensure_hpc_read())?;
    let cfg = current_cfg(&state).await;
    let data_dir = FsPath::new(&cfg.storage.data_dir);
    let detail = get_workstream_control_room_detail(data_dir, &cfg, &workstream_id)
        .map_err(|error| workstream_control_room_error(&workstream_id, error.to_string()))?;
    let compiled = resolve_workstream_compiled_context(
        &state,
        &detail,
        req.task_profile.as_deref(),
        req.tool_id.as_deref(),
        req.work_mode.as_deref(),
        req.query_text.as_deref(),
    )
    .await
    .map_err(|error| workstream_control_room_error(&workstream_id, error.to_string()))?;

    Ok(Json(compiled))
}

async fn workstream_planner_policy_handler(
    State(state): State<AppState>,
    Extension(consumer): Extension<ConsumerIdentity>,
    Path(workstream_id): Path<String>,
) -> Result<Json<PlannerPolicy>, JsonError> {
    ensure_allowed(consumer.ensure_workspace_plane())?;
    ensure_allowed(consumer.ensure_hpc_read())?;
    let _cfg = current_cfg(&state).await;
    Ok(Json(planner_policy_for_workstream(&workstream_id)))
}

async fn workstream_intent_plan_handler(
    State(state): State<AppState>,
    Extension(consumer): Extension<ConsumerIdentity>,
    Path(workstream_id): Path<String>,
    Json(body): Json<IntentPlanRequestBody>,
) -> Result<Json<IntentPlannerResponse>, JsonError> {
    ensure_allowed(consumer.ensure_workspace_plane())?;
    ensure_allowed(consumer.ensure_hpc_read())?;
    let cfg = current_cfg(&state).await;
    let data_dir = FsPath::new(&cfg.storage.data_dir);
    let gateway = gateway_client()?;
    let detail = get_workstream_control_room_detail(data_dir, &cfg, &workstream_id)
        .map_err(|error| workstream_control_room_error(&workstream_id, error.to_string()))?;
    let mut context_packet =
        resolve_workstream_context_packet(&state, data_dir, &cfg, &gateway, &workstream_id).await?;
    let planner_policy = planner_policy_for_workstream(&workstream_id);
    let task_family = body.task_family.trim().to_ascii_lowercase().replace('_', "-");
    let planner_profile = planner_policy
        .profiles
        .iter()
        .find(|profile| profile.task_family == task_family || (task_family == "analysis" && profile.task_family == "analysis"))
        .ok_or_else(|| {
            bad_request_response(
                "unsupported_task_family",
                format!("unsupported task_family '{}'", body.task_family),
            )
        })?;
    let tool_id = body
        .tool_id
        .as_deref()
        .unwrap_or(planner_profile.tool_id.as_str());
    let work_mode = body
        .work_mode
        .as_deref()
        .unwrap_or(planner_profile.work_mode.as_str());
    let compiled = resolve_workstream_compiled_context(
        &state,
        &detail,
        Some(&planner_profile.task_family),
        Some(tool_id),
        Some(work_mode),
        body.query_text.as_deref().or(Some(body.intent_text.as_str())),
    )
    .await
    .map_err(|error| workstream_control_room_error(&workstream_id, error.to_string()))?;
    apply_compiled_context_to_packet(&mut context_packet.packet, &compiled);
    apply_intent_planner_to_packet(&mut context_packet.packet);

    let route_response = build_workstream_workspace_subagent_route(
        &cfg,
        &workstream_id,
        context_packet.clone(),
        WorkspaceSubAgentRouteRequest {
            tool_id: Some(tool_id),
            work_mode: Some(work_mode),
            preferred_subagent: None,
        },
    )
    .map_err(|error| workstream_control_room_error(&workstream_id, error.to_string()))?;
    let binding = resolve_program_campaign_binding_for_workstream(&workstream_id)
        .map_err(|error| workstream_control_room_error(&workstream_id, error.to_string()))?;
    let compiled_selection = planner_compiled_context_selection_from_packet(&context_packet.packet)
        .ok_or_else(|| {
            internal_error_response(
                "intent_plan_compiled_context_missing",
                "compiled context metadata was not present after planner resolution".to_string(),
            )
        })?;
    let planner_request = IntentPlanRequest {
        task_family: planner_profile.task_family.clone(),
        intent_text: body.intent_text.clone(),
        tool_id: Some(tool_id.to_string()),
        work_mode: Some(work_mode.to_string()),
        query_text: body.query_text.clone(),
    };
    let response = build_intent_execution_plan(
        &detail,
        &context_packet.packet,
        &route_response,
        &compiled_selection,
        binding.as_ref(),
        &planner_request,
    )
    .map_err(|error| workstream_control_room_error(&workstream_id, error.to_string()))?;

    Ok(Json(response))
}

async fn workstream_plan_execution_state_handler(
    State(state): State<AppState>,
    Extension(consumer): Extension<ConsumerIdentity>,
    Path(workstream_id): Path<String>,
) -> Result<Json<ExecutionStatePlane>, JsonError> {
    ensure_allowed(consumer.ensure_workspace_plane())?;
    ensure_allowed(consumer.ensure_hpc_read())?;
    let cfg = current_cfg(&state).await;
    let data_dir = FsPath::new(&cfg.storage.data_dir);
    let gateway = gateway_client()?;
    let context_packet = resolve_workstream_context_packet_with_manuscript_quality_sync(
        &state,
        data_dir,
        &cfg,
        &gateway,
        &workstream_id,
    )
    .await?;
    let state = read_execution_state(data_dir, &context_packet.packet.workspace_id)
        .map_err(|error| workstream_control_room_error(&workstream_id, error.to_string()))?
        .ok_or_else(|| {
            not_found_response(
                "plan_execution_not_found",
                format!("no plan execution found for workstream {}", workstream_id),
            )
        })?;
    Ok(Json(state))
}

async fn workstream_plan_execution_approve_handler(
    State(state): State<AppState>,
    Extension(consumer): Extension<ConsumerIdentity>,
    Path(workstream_id): Path<String>,
    Json(body): Json<PlanExecutionApprovalRequestBody>,
) -> Result<Json<PlanApproval>, JsonError> {
    ensure_allowed(consumer.ensure_workspace_plane())?;
    ensure_allowed(consumer.ensure_hpc_read())?;
    let cfg = current_cfg(&state).await;
    let data_dir = FsPath::new(&cfg.storage.data_dir);
    let gateway = gateway_client()?;
    let context_packet =
        resolve_workstream_context_packet(&state, data_dir, &cfg, &gateway, &workstream_id).await?;
    let approval = approve_execution_plan(
        data_dir,
        &cfg,
        &workstream_id,
        context_packet,
        PlanApprovalRequest {
            execution_plan: &body.execution_plan,
            approved_by: &body.approved_by,
            approval_note: &body.approval_note,
        },
    )
    .map_err(|error| workstream_control_room_error(&workstream_id, error.to_string()))?;
    Ok(Json(approval))
}

async fn workstream_plan_execution_start_handler(
    State(state): State<AppState>,
    Extension(consumer): Extension<ConsumerIdentity>,
    Path(workstream_id): Path<String>,
    Json(body): Json<PlanExecutionStartRequestBody>,
) -> Result<Json<ExecutionStatePlane>, JsonError> {
    ensure_allowed(consumer.ensure_workspace_plane())?;
    ensure_allowed(consumer.ensure_hpc_read())?;
    let cfg = current_cfg(&state).await;
    let data_dir = FsPath::new(&cfg.storage.data_dir);
    let gateway = gateway_client()?;
    let context_packet =
        resolve_workstream_context_packet(&state, data_dir, &cfg, &gateway, &workstream_id).await?;
    let execution_state = start_execution_plan(
        data_dir,
        &cfg,
        &workstream_id,
        context_packet,
        PlanExecutionStartRequest {
            plan_id: &body.plan_id,
            started_by: &body.started_by,
            start_note: body
                .start_note
                .as_deref()
                .unwrap_or("Start bounded execution."),
        },
    )
    .map_err(|error| workstream_control_room_error(&workstream_id, error.to_string()))?;
    Ok(Json(execution_state))
}

async fn workstream_plan_execution_stop_handler(
    State(state): State<AppState>,
    Extension(consumer): Extension<ConsumerIdentity>,
    Path(workstream_id): Path<String>,
    Json(body): Json<PlanExecutionStopRequestBody>,
) -> Result<Json<ExecutionStatePlane>, JsonError> {
    ensure_allowed(consumer.ensure_workspace_plane())?;
    ensure_allowed(consumer.ensure_hpc_read())?;
    let cfg = current_cfg(&state).await;
    let data_dir = FsPath::new(&cfg.storage.data_dir);
    let gateway = gateway_client()?;
    let context_packet =
        resolve_workstream_context_packet(&state, data_dir, &cfg, &gateway, &workstream_id).await?;
    let execution_state = stop_execution_plan(
        data_dir,
        &workstream_id,
        context_packet,
        PlanExecutionStopRequest {
            plan_id: &body.plan_id,
            stopped_by: &body.stopped_by,
            stop_reason: &body.stop_reason,
        },
    )
    .map_err(|error| workstream_control_room_error(&workstream_id, error.to_string()))?;
    Ok(Json(execution_state))
}

async fn workstream_plan_execution_receipt_handler(
    State(state): State<AppState>,
    Extension(consumer): Extension<ConsumerIdentity>,
    Path(workstream_id): Path<String>,
) -> Result<Json<ExecutionReceipt>, JsonError> {
    ensure_allowed(consumer.ensure_workspace_plane())?;
    ensure_allowed(consumer.ensure_hpc_read())?;
    let cfg = current_cfg(&state).await;
    let data_dir = FsPath::new(&cfg.storage.data_dir);
    let gateway = gateway_client()?;
    let context_packet = resolve_workstream_context_packet_with_manuscript_quality_sync(
        &state,
        data_dir,
        &cfg,
        &gateway,
        &workstream_id,
    )
    .await?;
    let receipt = read_execution_receipt(data_dir, &context_packet.packet.workspace_id)
        .map_err(|error| workstream_control_room_error(&workstream_id, error.to_string()))?
        .ok_or_else(|| {
            not_found_response(
                "plan_execution_receipt_not_found",
                format!("no plan execution receipt found for workstream {}", workstream_id),
            )
        })?;
    Ok(Json(receipt))
}

async fn workstream_plan_execution_result_links_handler(
    State(state): State<AppState>,
    Extension(consumer): Extension<ConsumerIdentity>,
    Path(workstream_id): Path<String>,
) -> Result<Json<ExecutionResultLinksDocument>, JsonError> {
    ensure_allowed(consumer.ensure_workspace_plane())?;
    ensure_allowed(consumer.ensure_hpc_read())?;
    let cfg = current_cfg(&state).await;
    let data_dir = FsPath::new(&cfg.storage.data_dir);
    let gateway = gateway_client()?;
    let context_packet = resolve_workstream_context_packet_with_manuscript_quality_sync(
        &state,
        data_dir,
        &cfg,
        &gateway,
        &workstream_id,
    )
    .await?;
    let links = read_execution_result_links(data_dir, &context_packet.packet.workspace_id)
        .map_err(|error| workstream_control_room_error(&workstream_id, error.to_string()))?
        .ok_or_else(|| {
            not_found_response(
                "plan_execution_result_links_not_found",
                format!("no plan execution result links found for workstream {}", workstream_id),
            )
        })?;
    Ok(Json(links))
}

async fn workstream_plan_execution_reflection_handler(
    State(state): State<AppState>,
    Extension(consumer): Extension<ConsumerIdentity>,
    Path(workstream_id): Path<String>,
) -> Result<Json<ExecutionReflection>, JsonError> {
    ensure_allowed(consumer.ensure_workspace_plane())?;
    ensure_allowed(consumer.ensure_hpc_read())?;
    let cfg = current_cfg(&state).await;
    let data_dir = FsPath::new(&cfg.storage.data_dir);
    let gateway = gateway_client()?;
    let context_packet =
        resolve_workstream_context_packet(&state, data_dir, &cfg, &gateway, &workstream_id).await?;
    let reflection = read_execution_reflection(data_dir, &context_packet.packet.workspace_id)
        .map_err(|error| workstream_control_room_error(&workstream_id, error.to_string()))?
        .ok_or_else(|| {
            not_found_response(
                "plan_execution_reflection_not_found",
                format!("no execution reflection found for workstream {}", workstream_id),
            )
        })?;
    Ok(Json(reflection))
}

async fn workstream_plan_execution_trajectory_eval_handler(
    State(state): State<AppState>,
    Extension(consumer): Extension<ConsumerIdentity>,
    Path(workstream_id): Path<String>,
) -> Result<Json<TrajectoryEval>, JsonError> {
    ensure_allowed(consumer.ensure_workspace_plane())?;
    ensure_allowed(consumer.ensure_hpc_read())?;
    let cfg = current_cfg(&state).await;
    let data_dir = FsPath::new(&cfg.storage.data_dir);
    let gateway = gateway_client()?;
    let context_packet =
        resolve_workstream_context_packet(&state, data_dir, &cfg, &gateway, &workstream_id).await?;
    let trajectory_eval = read_trajectory_eval(data_dir, &context_packet.packet.workspace_id)
        .map_err(|error| workstream_control_room_error(&workstream_id, error.to_string()))?
        .ok_or_else(|| {
            not_found_response(
                "plan_execution_trajectory_eval_not_found",
                format!("no trajectory eval found for workstream {}", workstream_id),
            )
        })?;
    Ok(Json(trajectory_eval))
}

async fn workstream_plan_execution_replan_suggestion_handler(
    State(state): State<AppState>,
    Extension(consumer): Extension<ConsumerIdentity>,
    Path(workstream_id): Path<String>,
) -> Result<Json<ReplanSuggestion>, JsonError> {
    ensure_allowed(consumer.ensure_workspace_plane())?;
    ensure_allowed(consumer.ensure_hpc_read())?;
    let cfg = current_cfg(&state).await;
    let data_dir = FsPath::new(&cfg.storage.data_dir);
    let gateway = gateway_client()?;
    let context_packet =
        resolve_workstream_context_packet(&state, data_dir, &cfg, &gateway, &workstream_id).await?;
    let replan_suggestion =
        read_replan_suggestion(data_dir, &context_packet.packet.workspace_id)
            .map_err(|error| workstream_control_room_error(&workstream_id, error.to_string()))?
            .ok_or_else(|| {
                not_found_response(
                    "plan_execution_replan_suggestion_not_found",
                    format!("no replan suggestion found for workstream {}", workstream_id),
                )
            })?;
    Ok(Json(replan_suggestion))
}

async fn workstream_review_inbox_handler(
    State(state): State<AppState>,
    Extension(consumer): Extension<ConsumerIdentity>,
    Path(workstream_id): Path<String>,
) -> Result<Json<ReviewInboxItem>, JsonError> {
    ensure_allowed(consumer.ensure_workspace_plane())?;
    ensure_allowed(consumer.ensure_hpc_read())?;
    let cfg = current_cfg(&state).await;
    let data_dir = FsPath::new(&cfg.storage.data_dir);
    let gateway = gateway_client()?;
    let context_packet =
        resolve_workstream_context_packet(&state, data_dir, &cfg, &gateway, &workstream_id).await?;
    let inbox_item = read_review_inbox_item(data_dir, &context_packet.packet.workspace_id)
        .map_err(|error| workstream_control_room_error(&workstream_id, error.to_string()))?
        .ok_or_else(|| {
            not_found_response(
                "review_inbox_not_found",
                format!("no review inbox item found for workstream {}", workstream_id),
            )
        })?;
    Ok(Json(inbox_item))
}

async fn workstream_review_inbox_materialize_handler(
    State(state): State<AppState>,
    Extension(consumer): Extension<ConsumerIdentity>,
    Path(workstream_id): Path<String>,
    Json(body): Json<ReviewInboxMaterializeRequestBody>,
) -> Result<Json<ReviewInboxItem>, JsonError> {
    ensure_allowed(consumer.ensure_workspace_plane())?;
    ensure_allowed(consumer.ensure_hpc_read())?;
    let cfg = current_cfg(&state).await;
    let data_dir = FsPath::new(&cfg.storage.data_dir);
    let gateway = gateway_client()?;
    let context_packet =
        resolve_workstream_context_packet(&state, data_dir, &cfg, &gateway, &workstream_id).await?;
    let inbox_item = materialize_review_inbox_item(
        data_dir,
        &workstream_id,
        context_packet,
        ReviewInboxMaterializeRequest {
            created_by: &body.created_by,
            create_note: body
                .create_note
                .as_deref()
                .unwrap_or("Materialize operator-visible review inbox item."),
        },
    )
    .map_err(|error| workstream_control_room_error(&workstream_id, error.to_string()))?;
    Ok(Json(inbox_item))
}

async fn workstream_review_inbox_decision_handler(
    State(state): State<AppState>,
    Extension(consumer): Extension<ConsumerIdentity>,
    Path(workstream_id): Path<String>,
    Json(body): Json<ReviewDecisionRequestBody>,
) -> Result<Json<ReviewDecision>, JsonError> {
    ensure_allowed(consumer.ensure_workspace_plane())?;
    ensure_allowed(consumer.ensure_hpc_read())?;
    let cfg = current_cfg(&state).await;
    let data_dir = FsPath::new(&cfg.storage.data_dir);
    let gateway = gateway_client()?;
    let context_packet =
        resolve_workstream_context_packet(&state, data_dir, &cfg, &gateway, &workstream_id).await?;
    let decision = decide_review_inbox_item(
        data_dir,
        &cfg,
        &workstream_id,
        context_packet,
        ReviewInboxDecisionRequest {
            inbox_item_id: body.inbox_item_id,
            decision_action: body.decision_action,
            decided_by: body.decided_by,
            decision_note: body.decision_note,
            edit_patch: body.edit_patch.map(|patch| ReviewDecisionEditPatch {
                task_family: patch.task_family,
                selected_subagent_id: patch.selected_subagent_id,
                retrieval_query_type: patch.retrieval_query_type,
                compiler_profile_id: patch.compiler_profile_id,
                graphrag_query_mode: patch.graphrag_query_mode,
                temporal_truth_view: patch.temporal_truth_view,
                recipe_kind: patch.recipe_kind,
            }),
        },
    )
    .map_err(|error| workstream_control_room_error(&workstream_id, error.to_string()))?;
    Ok(Json(decision))
}

async fn workstream_review_decision_handler(
    State(state): State<AppState>,
    Extension(consumer): Extension<ConsumerIdentity>,
    Path(workstream_id): Path<String>,
) -> Result<Json<ReviewDecision>, JsonError> {
    ensure_allowed(consumer.ensure_workspace_plane())?;
    ensure_allowed(consumer.ensure_hpc_read())?;
    let cfg = current_cfg(&state).await;
    let data_dir = FsPath::new(&cfg.storage.data_dir);
    let gateway = gateway_client()?;
    let context_packet =
        resolve_workstream_context_packet(&state, data_dir, &cfg, &gateway, &workstream_id).await?;
    let decision = read_review_decision(data_dir, &context_packet.packet.workspace_id)
        .map_err(|error| workstream_control_room_error(&workstream_id, error.to_string()))?
        .ok_or_else(|| {
            not_found_response(
                "review_decision_not_found",
                format!("no review decision found for workstream {}", workstream_id),
            )
        })?;
    Ok(Json(decision))
}

async fn workstream_follow_on_plan_handler(
    State(state): State<AppState>,
    Extension(consumer): Extension<ConsumerIdentity>,
    Path(workstream_id): Path<String>,
) -> Result<Json<FollowOnPlan>, JsonError> {
    ensure_allowed(consumer.ensure_workspace_plane())?;
    ensure_allowed(consumer.ensure_hpc_read())?;
    let cfg = current_cfg(&state).await;
    let data_dir = FsPath::new(&cfg.storage.data_dir);
    let gateway = gateway_client()?;
    let context_packet =
        resolve_workstream_context_packet(&state, data_dir, &cfg, &gateway, &workstream_id).await?;
    let follow_on_plan = read_follow_on_plan(data_dir, &context_packet.packet.workspace_id)
        .map_err(|error| workstream_control_room_error(&workstream_id, error.to_string()))?
        .ok_or_else(|| {
            not_found_response(
                "follow_on_plan_not_found",
                format!("no follow-on plan found for workstream {}", workstream_id),
            )
    })?;
    Ok(Json(follow_on_plan))
}

async fn workstream_autonomy_policy_handler(
    State(state): State<AppState>,
    Extension(consumer): Extension<ConsumerIdentity>,
    Path(workstream_id): Path<String>,
) -> Result<Json<AutonomyPolicy>, JsonError> {
    ensure_allowed(consumer.ensure_workspace_plane())?;
    ensure_allowed(consumer.ensure_hpc_read())?;
    let cfg = current_cfg(&state).await;
    let data_dir = FsPath::new(&cfg.storage.data_dir);
    let gateway = gateway_client()?;
    let context_packet =
        resolve_workstream_context_packet(&state, data_dir, &cfg, &gateway, &workstream_id).await?;
    let autonomy_policy = read_autonomy_policy(data_dir, &context_packet.packet.workspace_id)
        .map_err(|error| workstream_control_room_error(&workstream_id, error.to_string()))?
        .ok_or_else(|| {
            not_found_response(
                "autonomy_policy_not_found",
                format!("no autonomy policy found for workstream {}", workstream_id),
            )
        })?;
    Ok(Json(autonomy_policy))
}

async fn workstream_risk_evaluation_handler(
    State(state): State<AppState>,
    Extension(consumer): Extension<ConsumerIdentity>,
    Path(workstream_id): Path<String>,
) -> Result<Json<RiskEvaluation>, JsonError> {
    ensure_allowed(consumer.ensure_workspace_plane())?;
    ensure_allowed(consumer.ensure_hpc_read())?;
    let cfg = current_cfg(&state).await;
    let data_dir = FsPath::new(&cfg.storage.data_dir);
    let gateway = gateway_client()?;
    let context_packet =
        resolve_workstream_context_packet(&state, data_dir, &cfg, &gateway, &workstream_id).await?;
    let risk_evaluation = read_risk_evaluation(data_dir, &context_packet.packet.workspace_id)
        .map_err(|error| workstream_control_room_error(&workstream_id, error.to_string()))?
        .ok_or_else(|| {
            not_found_response(
                "risk_evaluation_not_found",
                format!("no risk evaluation found for workstream {}", workstream_id),
            )
        })?;
    Ok(Json(risk_evaluation))
}

async fn workstream_approval_gating_decision_handler(
    State(state): State<AppState>,
    Extension(consumer): Extension<ConsumerIdentity>,
    Path(workstream_id): Path<String>,
) -> Result<Json<ApprovalGatingDecision>, JsonError> {
    ensure_allowed(consumer.ensure_workspace_plane())?;
    ensure_allowed(consumer.ensure_hpc_read())?;
    let cfg = current_cfg(&state).await;
    let data_dir = FsPath::new(&cfg.storage.data_dir);
    let gateway = gateway_client()?;
    let context_packet =
        resolve_workstream_context_packet(&state, data_dir, &cfg, &gateway, &workstream_id).await?;
    let approval_gating_decision =
        read_approval_gating_decision(data_dir, &context_packet.packet.workspace_id)
            .map_err(|error| workstream_control_room_error(&workstream_id, error.to_string()))?
            .ok_or_else(|| {
                not_found_response(
                    "approval_gating_decision_not_found",
                    format!(
                        "no approval gating decision found for workstream {}",
                        workstream_id
                    ),
                )
            })?;
    Ok(Json(approval_gating_decision))
}

async fn workstream_autonomy_calibration_dataset_handler(
    State(state): State<AppState>,
    Extension(consumer): Extension<ConsumerIdentity>,
    Path(workstream_id): Path<String>,
) -> Result<Json<AutonomyCalibrationDataset>, JsonError> {
    ensure_allowed(consumer.ensure_workspace_plane())?;
    ensure_allowed(consumer.ensure_hpc_read())?;
    let cfg = current_cfg(&state).await;
    let data_dir = FsPath::new(&cfg.storage.data_dir);
    let gateway = gateway_client()?;
    let context_packet =
        resolve_workstream_context_packet(&state, data_dir, &cfg, &gateway, &workstream_id).await?;
    let bundle = ensure_autonomy_policy_calibration(
        data_dir,
        &workstream_id,
        &context_packet.packet.workspace_id,
    )
    .map_err(|error| workstream_control_room_error(&workstream_id, error.to_string()))?;
    Ok(Json(bundle.calibration_dataset))
}

async fn workstream_autonomy_policy_eval_report_handler(
    State(state): State<AppState>,
    Extension(consumer): Extension<ConsumerIdentity>,
    Path(workstream_id): Path<String>,
) -> Result<Json<AutonomyPolicyEvalReport>, JsonError> {
    ensure_allowed(consumer.ensure_workspace_plane())?;
    ensure_allowed(consumer.ensure_hpc_read())?;
    let cfg = current_cfg(&state).await;
    let data_dir = FsPath::new(&cfg.storage.data_dir);
    let gateway = gateway_client()?;
    let context_packet =
        resolve_workstream_context_packet(&state, data_dir, &cfg, &gateway, &workstream_id).await?;
    let bundle = ensure_autonomy_policy_calibration(
        data_dir,
        &workstream_id,
        &context_packet.packet.workspace_id,
    )
    .map_err(|error| workstream_control_room_error(&workstream_id, error.to_string()))?;
    Ok(Json(bundle.policy_eval_report))
}

async fn workstream_escalation_thresholds_handler(
    State(state): State<AppState>,
    Extension(consumer): Extension<ConsumerIdentity>,
    Path(workstream_id): Path<String>,
) -> Result<Json<EscalationThresholds>, JsonError> {
    ensure_allowed(consumer.ensure_workspace_plane())?;
    ensure_allowed(consumer.ensure_hpc_read())?;
    let cfg = current_cfg(&state).await;
    let data_dir = FsPath::new(&cfg.storage.data_dir);
    let gateway = gateway_client()?;
    let context_packet =
        resolve_workstream_context_packet(&state, data_dir, &cfg, &gateway, &workstream_id).await?;
    let bundle = ensure_autonomy_policy_calibration(
        data_dir,
        &workstream_id,
        &context_packet.packet.workspace_id,
    )
    .map_err(|error| workstream_control_room_error(&workstream_id, error.to_string()))?;
    Ok(Json(bundle.escalation_thresholds))
}

async fn workstream_shadow_policy_comparison_handler(
    State(state): State<AppState>,
    Extension(consumer): Extension<ConsumerIdentity>,
    Path(workstream_id): Path<String>,
) -> Result<Json<ShadowPolicyComparison>, JsonError> {
    ensure_allowed(consumer.ensure_workspace_plane())?;
    ensure_allowed(consumer.ensure_hpc_read())?;
    let cfg = current_cfg(&state).await;
    let data_dir = FsPath::new(&cfg.storage.data_dir);
    let gateway = gateway_client()?;
    let context_packet =
        resolve_workstream_context_packet(&state, data_dir, &cfg, &gateway, &workstream_id).await?;
    let bundle = ensure_autonomy_policy_calibration(
        data_dir,
        &workstream_id,
        &context_packet.packet.workspace_id,
    )
    .map_err(|error| workstream_control_room_error(&workstream_id, error.to_string()))?;
    Ok(Json(bundle.shadow_policy_comparison))
}

async fn workstream_updated_policy_recommendation_handler(
    State(state): State<AppState>,
    Extension(consumer): Extension<ConsumerIdentity>,
    Path(workstream_id): Path<String>,
) -> Result<Json<UpdatedPolicyRecommendation>, JsonError> {
    ensure_allowed(consumer.ensure_workspace_plane())?;
    ensure_allowed(consumer.ensure_hpc_read())?;
    let cfg = current_cfg(&state).await;
    let data_dir = FsPath::new(&cfg.storage.data_dir);
    let gateway = gateway_client()?;
    let context_packet =
        resolve_workstream_context_packet(&state, data_dir, &cfg, &gateway, &workstream_id).await?;
    let bundle = ensure_autonomy_policy_calibration(
        data_dir,
        &workstream_id,
        &context_packet.packet.workspace_id,
    )
    .map_err(|error| workstream_control_room_error(&workstream_id, error.to_string()))?;
    Ok(Json(bundle.updated_policy_recommendation))
}

async fn workstream_autonomy_policy_current_handler(
    State(state): State<AppState>,
    Extension(consumer): Extension<ConsumerIdentity>,
    Path(workstream_id): Path<String>,
) -> Result<Json<AutonomyShadowThreshold>, JsonError> {
    ensure_allowed(consumer.ensure_workspace_plane())?;
    ensure_allowed(consumer.ensure_hpc_read())?;
    let cfg = current_cfg(&state).await;
    let data_dir = FsPath::new(&cfg.storage.data_dir);
    let gateway = gateway_client()?;
    let context_packet =
        resolve_workstream_context_packet(&state, data_dir, &cfg, &gateway, &workstream_id).await?;
    let bundle = ensure_guarded_policy_rollout(
        data_dir,
        &workstream_id,
        &context_packet.packet.workspace_id,
    )
    .map_err(|error| workstream_control_room_error(&workstream_id, error.to_string()))?;
    Ok(Json(bundle.autonomy_policy_current))
}

async fn workstream_autonomy_policy_candidate_handler(
    State(state): State<AppState>,
    Extension(consumer): Extension<ConsumerIdentity>,
    Path(workstream_id): Path<String>,
) -> Result<Json<AutonomyShadowThreshold>, JsonError> {
    ensure_allowed(consumer.ensure_workspace_plane())?;
    ensure_allowed(consumer.ensure_hpc_read())?;
    let cfg = current_cfg(&state).await;
    let data_dir = FsPath::new(&cfg.storage.data_dir);
    let gateway = gateway_client()?;
    let context_packet =
        resolve_workstream_context_packet(&state, data_dir, &cfg, &gateway, &workstream_id).await?;
    let bundle = ensure_guarded_policy_rollout(
        data_dir,
        &workstream_id,
        &context_packet.packet.workspace_id,
    )
    .map_err(|error| workstream_control_room_error(&workstream_id, error.to_string()))?;
    Ok(Json(bundle.autonomy_policy_candidate))
}

async fn workstream_rollout_metrics_handler(
    State(state): State<AppState>,
    Extension(consumer): Extension<ConsumerIdentity>,
    Path(workstream_id): Path<String>,
) -> Result<Json<PolicyRolloutMetrics>, JsonError> {
    ensure_allowed(consumer.ensure_workspace_plane())?;
    ensure_allowed(consumer.ensure_hpc_read())?;
    let cfg = current_cfg(&state).await;
    let data_dir = FsPath::new(&cfg.storage.data_dir);
    let gateway = gateway_client()?;
    let context_packet =
        resolve_workstream_context_packet(&state, data_dir, &cfg, &gateway, &workstream_id).await?;
    let bundle = ensure_guarded_policy_rollout(
        data_dir,
        &workstream_id,
        &context_packet.packet.workspace_id,
    )
    .map_err(|error| workstream_control_room_error(&workstream_id, error.to_string()))?;
    Ok(Json(bundle.rollout_metrics))
}

async fn workstream_guarded_rollout_decision_handler(
    State(state): State<AppState>,
    Extension(consumer): Extension<ConsumerIdentity>,
    Path(workstream_id): Path<String>,
) -> Result<Json<GuardedRolloutDecision>, JsonError> {
    ensure_allowed(consumer.ensure_workspace_plane())?;
    ensure_allowed(consumer.ensure_hpc_read())?;
    let cfg = current_cfg(&state).await;
    let data_dir = FsPath::new(&cfg.storage.data_dir);
    let gateway = gateway_client()?;
    let context_packet =
        resolve_workstream_context_packet(&state, data_dir, &cfg, &gateway, &workstream_id).await?;
    let bundle = ensure_guarded_policy_rollout(
        data_dir,
        &workstream_id,
        &context_packet.packet.workspace_id,
    )
    .map_err(|error| workstream_control_room_error(&workstream_id, error.to_string()))?;
    Ok(Json(bundle.rollout_decision))
}

async fn workstream_autonomy_policy_control_handler(
    State(state): State<AppState>,
    Extension(consumer): Extension<ConsumerIdentity>,
    Path(workstream_id): Path<String>,
) -> Result<Json<AutonomyPolicy>, JsonError> {
    ensure_allowed(consumer.ensure_workspace_plane())?;
    ensure_allowed(consumer.ensure_hpc_read())?;
    let cfg = current_cfg(&state).await;
    let data_dir = FsPath::new(&cfg.storage.data_dir);
    let gateway = gateway_client()?;
    let context_packet =
        resolve_workstream_context_packet(&state, data_dir, &cfg, &gateway, &workstream_id).await?;
    let bundle = ensure_implementation_canary_autonomy(
        data_dir,
        &workstream_id,
        &context_packet.packet.workspace_id,
    )
    .map_err(|error| workstream_control_room_error(&workstream_id, error.to_string()))?;
    Ok(Json(bundle.autonomy_policy_control))
}

async fn workstream_autonomy_policy_canary_handler(
    State(state): State<AppState>,
    Extension(consumer): Extension<ConsumerIdentity>,
    Path(workstream_id): Path<String>,
) -> Result<Json<AutonomyPolicy>, JsonError> {
    ensure_allowed(consumer.ensure_workspace_plane())?;
    ensure_allowed(consumer.ensure_hpc_read())?;
    let cfg = current_cfg(&state).await;
    let data_dir = FsPath::new(&cfg.storage.data_dir);
    let gateway = gateway_client()?;
    let context_packet =
        resolve_workstream_context_packet(&state, data_dir, &cfg, &gateway, &workstream_id).await?;
    let bundle = ensure_implementation_canary_autonomy(
        data_dir,
        &workstream_id,
        &context_packet.packet.workspace_id,
    )
    .map_err(|error| workstream_control_room_error(&workstream_id, error.to_string()))?;
    Ok(Json(bundle.autonomy_policy_canary))
}

async fn workstream_canary_rollout_metrics_handler(
    State(state): State<AppState>,
    Extension(consumer): Extension<ConsumerIdentity>,
    Path(workstream_id): Path<String>,
) -> Result<Json<CanaryRolloutMetrics>, JsonError> {
    ensure_allowed(consumer.ensure_workspace_plane())?;
    ensure_allowed(consumer.ensure_hpc_read())?;
    let cfg = current_cfg(&state).await;
    let data_dir = FsPath::new(&cfg.storage.data_dir);
    let gateway = gateway_client()?;
    let context_packet =
        resolve_workstream_context_packet(&state, data_dir, &cfg, &gateway, &workstream_id).await?;
    let bundle = ensure_implementation_canary_autonomy(
        data_dir,
        &workstream_id,
        &context_packet.packet.workspace_id,
    )
    .map_err(|error| workstream_control_room_error(&workstream_id, error.to_string()))?;
    Ok(Json(bundle.canary_rollout_metrics))
}

async fn workstream_canary_rollback_decision_handler(
    State(state): State<AppState>,
    Extension(consumer): Extension<ConsumerIdentity>,
    Path(workstream_id): Path<String>,
) -> Result<Json<CanaryRollbackDecision>, JsonError> {
    ensure_allowed(consumer.ensure_workspace_plane())?;
    ensure_allowed(consumer.ensure_hpc_read())?;
    let cfg = current_cfg(&state).await;
    let data_dir = FsPath::new(&cfg.storage.data_dir);
    let gateway = gateway_client()?;
    let context_packet =
        resolve_workstream_context_packet(&state, data_dir, &cfg, &gateway, &workstream_id).await?;
    let bundle = ensure_implementation_canary_autonomy(
        data_dir,
        &workstream_id,
        &context_packet.packet.workspace_id,
    )
    .map_err(|error| workstream_control_room_error(&workstream_id, error.to_string()))?;
    Ok(Json(bundle.canary_rollback_decision))
}

async fn workstream_autonomy_policy_analysis_candidate_handler(
    State(state): State<AppState>,
    Extension(consumer): Extension<ConsumerIdentity>,
    Path(workstream_id): Path<String>,
) -> Result<Json<AutonomyPolicy>, JsonError> {
    ensure_allowed(consumer.ensure_workspace_plane())?;
    ensure_allowed(consumer.ensure_hpc_read())?;
    let cfg = current_cfg(&state).await;
    let data_dir = FsPath::new(&cfg.storage.data_dir);
    let gateway = gateway_client()?;
    let context_packet =
        resolve_workstream_context_packet(&state, data_dir, &cfg, &gateway, &workstream_id).await?;
    let bundle = ensure_analysis_shadow_calibration(
        data_dir,
        &workstream_id,
        &context_packet.packet.workspace_id,
    )
    .map_err(|error| workstream_control_room_error(&workstream_id, error.to_string()))?;
    Ok(Json(bundle.autonomy_policy_analysis_candidate))
}

async fn workstream_analysis_shadow_comparison_handler(
    State(state): State<AppState>,
    Extension(consumer): Extension<ConsumerIdentity>,
    Path(workstream_id): Path<String>,
) -> Result<Json<AnalysisShadowCalibration>, JsonError> {
    ensure_allowed(consumer.ensure_workspace_plane())?;
    ensure_allowed(consumer.ensure_hpc_read())?;
    let cfg = current_cfg(&state).await;
    let data_dir = FsPath::new(&cfg.storage.data_dir);
    let gateway = gateway_client()?;
    let context_packet =
        resolve_workstream_context_packet(&state, data_dir, &cfg, &gateway, &workstream_id).await?;
    let bundle = ensure_analysis_shadow_calibration(
        data_dir,
        &workstream_id,
        &context_packet.packet.workspace_id,
    )
    .map_err(|error| workstream_control_room_error(&workstream_id, error.to_string()))?;
    Ok(Json(bundle.analysis_shadow_comparison))
}

async fn workstream_analysis_rollout_metrics_handler(
    State(state): State<AppState>,
    Extension(consumer): Extension<ConsumerIdentity>,
    Path(workstream_id): Path<String>,
) -> Result<Json<AnalysisRolloutMetrics>, JsonError> {
    ensure_allowed(consumer.ensure_workspace_plane())?;
    ensure_allowed(consumer.ensure_hpc_read())?;
    let cfg = current_cfg(&state).await;
    let data_dir = FsPath::new(&cfg.storage.data_dir);
    let gateway = gateway_client()?;
    let context_packet =
        resolve_workstream_context_packet(&state, data_dir, &cfg, &gateway, &workstream_id).await?;
    let bundle = ensure_analysis_shadow_calibration(
        data_dir,
        &workstream_id,
        &context_packet.packet.workspace_id,
    )
    .map_err(|error| workstream_control_room_error(&workstream_id, error.to_string()))?;
    Ok(Json(bundle.analysis_rollout_metrics))
}

async fn workstream_analysis_rollout_decision_handler(
    State(state): State<AppState>,
    Extension(consumer): Extension<ConsumerIdentity>,
    Path(workstream_id): Path<String>,
) -> Result<Json<AnalysisRolloutDecision>, JsonError> {
    ensure_allowed(consumer.ensure_workspace_plane())?;
    ensure_allowed(consumer.ensure_hpc_read())?;
    let cfg = current_cfg(&state).await;
    let data_dir = FsPath::new(&cfg.storage.data_dir);
    let gateway = gateway_client()?;
    let context_packet =
        resolve_workstream_context_packet(&state, data_dir, &cfg, &gateway, &workstream_id).await?;
    let bundle = ensure_analysis_shadow_calibration(
        data_dir,
        &workstream_id,
        &context_packet.packet.workspace_id,
    )
    .map_err(|error| workstream_control_room_error(&workstream_id, error.to_string()))?;
    Ok(Json(bundle.analysis_rollout_decision))
}

async fn workstream_analysis_shadow_history_handler(
    State(state): State<AppState>,
    Extension(consumer): Extension<ConsumerIdentity>,
    Path(workstream_id): Path<String>,
) -> Result<Json<AnalysisShadowSoak>, JsonError> {
    ensure_allowed(consumer.ensure_workspace_plane())?;
    ensure_allowed(consumer.ensure_hpc_read())?;
    let cfg = current_cfg(&state).await;
    let data_dir = FsPath::new(&cfg.storage.data_dir);
    let gateway = gateway_client()?;
    let context_packet =
        resolve_workstream_context_packet(&state, data_dir, &cfg, &gateway, &workstream_id).await?;
    let bundle = ensure_analysis_shadow_soak(
        data_dir,
        &workstream_id,
        &context_packet.packet.workspace_id,
    )
    .map_err(|error| workstream_control_room_error(&workstream_id, error.to_string()))?;
    Ok(Json(bundle.analysis_shadow_history))
}

async fn workstream_analysis_soak_metrics_handler(
    State(state): State<AppState>,
    Extension(consumer): Extension<ConsumerIdentity>,
    Path(workstream_id): Path<String>,
) -> Result<Json<AnalysisSoakMetrics>, JsonError> {
    ensure_allowed(consumer.ensure_workspace_plane())?;
    ensure_allowed(consumer.ensure_hpc_read())?;
    let cfg = current_cfg(&state).await;
    let data_dir = FsPath::new(&cfg.storage.data_dir);
    let gateway = gateway_client()?;
    let context_packet =
        resolve_workstream_context_packet(&state, data_dir, &cfg, &gateway, &workstream_id).await?;
    let bundle = ensure_analysis_shadow_soak(
        data_dir,
        &workstream_id,
        &context_packet.packet.workspace_id,
    )
    .map_err(|error| workstream_control_room_error(&workstream_id, error.to_string()))?;
    Ok(Json(bundle.analysis_soak_metrics))
}

async fn workstream_analysis_promotion_gate_handler(
    State(state): State<AppState>,
    Extension(consumer): Extension<ConsumerIdentity>,
    Path(workstream_id): Path<String>,
) -> Result<Json<AnalysisPromotionGate>, JsonError> {
    ensure_allowed(consumer.ensure_workspace_plane())?;
    ensure_allowed(consumer.ensure_hpc_read())?;
    let cfg = current_cfg(&state).await;
    let data_dir = FsPath::new(&cfg.storage.data_dir);
    let gateway = gateway_client()?;
    let context_packet =
        resolve_workstream_context_packet(&state, data_dir, &cfg, &gateway, &workstream_id).await?;
    let bundle = ensure_analysis_shadow_soak(
        data_dir,
        &workstream_id,
        &context_packet.packet.workspace_id,
    )
    .map_err(|error| workstream_control_room_error(&workstream_id, error.to_string()))?;
    Ok(Json(bundle.analysis_promotion_gate))
}

async fn workstream_analysis_sample_accumulation_handler(
    State(state): State<AppState>,
    Extension(consumer): Extension<ConsumerIdentity>,
    Path(workstream_id): Path<String>,
) -> Result<Json<AnalysisShadowSoak>, JsonError> {
    ensure_allowed(consumer.ensure_workspace_plane())?;
    ensure_allowed(consumer.ensure_hpc_read())?;
    let cfg = current_cfg(&state).await;
    let data_dir = FsPath::new(&cfg.storage.data_dir);
    let gateway = gateway_client()?;
    let context_packet =
        resolve_workstream_context_packet(&state, data_dir, &cfg, &gateway, &workstream_id).await?;
    let bundle = ensure_analysis_sample_accumulation(
        data_dir,
        &workstream_id,
        &context_packet.packet.workspace_id,
    )
    .map_err(|error| workstream_control_room_error(&workstream_id, error.to_string()))?;
    Ok(Json(bundle.analysis_shadow_history))
}

async fn workstream_analysis_sample_accumulation_metrics_handler(
    State(state): State<AppState>,
    Extension(consumer): Extension<ConsumerIdentity>,
    Path(workstream_id): Path<String>,
) -> Result<Json<AnalysisSoakMetrics>, JsonError> {
    ensure_allowed(consumer.ensure_workspace_plane())?;
    ensure_allowed(consumer.ensure_hpc_read())?;
    let cfg = current_cfg(&state).await;
    let data_dir = FsPath::new(&cfg.storage.data_dir);
    let gateway = gateway_client()?;
    let context_packet =
        resolve_workstream_context_packet(&state, data_dir, &cfg, &gateway, &workstream_id).await?;
    let bundle = ensure_analysis_sample_accumulation(
        data_dir,
        &workstream_id,
        &context_packet.packet.workspace_id,
    )
    .map_err(|error| workstream_control_room_error(&workstream_id, error.to_string()))?;
    Ok(Json(bundle.analysis_soak_metrics))
}

async fn workstream_analysis_promotion_gate_recheck_handler(
    State(state): State<AppState>,
    Extension(consumer): Extension<ConsumerIdentity>,
    Path(workstream_id): Path<String>,
) -> Result<Json<AnalysisPromotionGate>, JsonError> {
    ensure_allowed(consumer.ensure_workspace_plane())?;
    ensure_allowed(consumer.ensure_hpc_read())?;
    let cfg = current_cfg(&state).await;
    let data_dir = FsPath::new(&cfg.storage.data_dir);
    let gateway = gateway_client()?;
    let context_packet =
        resolve_workstream_context_packet(&state, data_dir, &cfg, &gateway, &workstream_id).await?;
    let bundle = ensure_analysis_sample_accumulation(
        data_dir,
        &workstream_id,
        &context_packet.packet.workspace_id,
    )
    .map_err(|error| workstream_control_room_error(&workstream_id, error.to_string()))?;
    Ok(Json(bundle.analysis_promotion_gate))
}

async fn workstream_autonomy_policy_analysis_control_handler(
    State(state): State<AppState>,
    Extension(consumer): Extension<ConsumerIdentity>,
    Path(workstream_id): Path<String>,
) -> Result<Json<AutonomyPolicy>, JsonError> {
    ensure_allowed(consumer.ensure_workspace_plane())?;
    ensure_allowed(consumer.ensure_hpc_read())?;
    let cfg = current_cfg(&state).await;
    let data_dir = FsPath::new(&cfg.storage.data_dir);
    let gateway = gateway_client()?;
    let context_packet =
        resolve_workstream_context_packet(&state, data_dir, &cfg, &gateway, &workstream_id).await?;
    let bundle = ensure_analysis_canary_activation(
        data_dir,
        &workstream_id,
        &context_packet.packet.workspace_id,
    )
    .map_err(|error| workstream_control_room_error(&workstream_id, error.to_string()))?;
    Ok(Json(bundle.autonomy_policy_control))
}

async fn workstream_autonomy_policy_implementation_canary_handler(
    State(state): State<AppState>,
    Extension(consumer): Extension<ConsumerIdentity>,
    Path(workstream_id): Path<String>,
) -> Result<Json<AutonomyPolicy>, JsonError> {
    ensure_allowed(consumer.ensure_workspace_plane())?;
    ensure_allowed(consumer.ensure_hpc_read())?;
    let cfg = current_cfg(&state).await;
    let data_dir = FsPath::new(&cfg.storage.data_dir);
    let gateway = gateway_client()?;
    let context_packet =
        resolve_workstream_context_packet(&state, data_dir, &cfg, &gateway, &workstream_id).await?;
    let bundle = ensure_analysis_canary_activation(
        data_dir,
        &workstream_id,
        &context_packet.packet.workspace_id,
    )
    .map_err(|error| workstream_control_room_error(&workstream_id, error.to_string()))?;
    Ok(Json(bundle.autonomy_policy_implementation_canary))
}

async fn workstream_autonomy_policy_analysis_canary_handler(
    State(state): State<AppState>,
    Extension(consumer): Extension<ConsumerIdentity>,
    Path(workstream_id): Path<String>,
) -> Result<Json<AutonomyPolicy>, JsonError> {
    ensure_allowed(consumer.ensure_workspace_plane())?;
    ensure_allowed(consumer.ensure_hpc_read())?;
    let cfg = current_cfg(&state).await;
    let data_dir = FsPath::new(&cfg.storage.data_dir);
    let gateway = gateway_client()?;
    let context_packet =
        resolve_workstream_context_packet(&state, data_dir, &cfg, &gateway, &workstream_id).await?;
    let bundle = ensure_analysis_canary_activation(
        data_dir,
        &workstream_id,
        &context_packet.packet.workspace_id,
    )
    .map_err(|error| workstream_control_room_error(&workstream_id, error.to_string()))?;
    Ok(Json(bundle.autonomy_policy_analysis_canary))
}

async fn workstream_analysis_canary_metrics_handler(
    State(state): State<AppState>,
    Extension(consumer): Extension<ConsumerIdentity>,
    Path(workstream_id): Path<String>,
) -> Result<Json<AnalysisCanaryMetrics>, JsonError> {
    ensure_allowed(consumer.ensure_workspace_plane())?;
    ensure_allowed(consumer.ensure_hpc_read())?;
    let cfg = current_cfg(&state).await;
    let data_dir = FsPath::new(&cfg.storage.data_dir);
    let gateway = gateway_client()?;
    let context_packet =
        resolve_workstream_context_packet(&state, data_dir, &cfg, &gateway, &workstream_id).await?;
    let bundle = ensure_analysis_canary_activation(
        data_dir,
        &workstream_id,
        &context_packet.packet.workspace_id,
    )
    .map_err(|error| workstream_control_room_error(&workstream_id, error.to_string()))?;
    Ok(Json(bundle.analysis_canary_metrics))
}

async fn workstream_analysis_canary_rollback_decision_handler(
    State(state): State<AppState>,
    Extension(consumer): Extension<ConsumerIdentity>,
    Path(workstream_id): Path<String>,
) -> Result<Json<AnalysisCanaryRollbackDecision>, JsonError> {
    ensure_allowed(consumer.ensure_workspace_plane())?;
    ensure_allowed(consumer.ensure_hpc_read())?;
    let cfg = current_cfg(&state).await;
    let data_dir = FsPath::new(&cfg.storage.data_dir);
    let gateway = gateway_client()?;
    let context_packet =
        resolve_workstream_context_packet(&state, data_dir, &cfg, &gateway, &workstream_id).await?;
    let bundle = ensure_analysis_canary_activation(
        data_dir,
        &workstream_id,
        &context_packet.packet.workspace_id,
    )
    .map_err(|error| workstream_control_room_error(&workstream_id, error.to_string()))?;
    Ok(Json(bundle.analysis_canary_rollback_decision))
}

async fn workstream_autonomy_policy_manuscript_control_handler(
    State(state): State<AppState>,
    Extension(consumer): Extension<ConsumerIdentity>,
    Path(workstream_id): Path<String>,
) -> Result<Json<AutonomyPolicy>, JsonError> {
    ensure_allowed(consumer.ensure_workspace_plane())?;
    ensure_allowed(consumer.ensure_hpc_read())?;
    let cfg = current_cfg(&state).await;
    let data_dir = FsPath::new(&cfg.storage.data_dir);
    let gateway = gateway_client()?;
    let context_packet =
        resolve_workstream_context_packet(&state, data_dir, &cfg, &gateway, &workstream_id).await?;
    let bundle = ensure_manuscript_shadow_calibration(
        data_dir,
        &workstream_id,
        &context_packet.packet.workspace_id,
    )
    .map_err(|error| workstream_control_room_error(&workstream_id, error.to_string()))?;
    Ok(Json(bundle.autonomy_policy_control))
}

async fn workstream_autonomy_policy_manuscript_candidate_handler(
    State(state): State<AppState>,
    Extension(consumer): Extension<ConsumerIdentity>,
    Path(workstream_id): Path<String>,
) -> Result<Json<AutonomyPolicy>, JsonError> {
    ensure_allowed(consumer.ensure_workspace_plane())?;
    ensure_allowed(consumer.ensure_hpc_read())?;
    let cfg = current_cfg(&state).await;
    let data_dir = FsPath::new(&cfg.storage.data_dir);
    let gateway = gateway_client()?;
    let context_packet =
        resolve_workstream_context_packet(&state, data_dir, &cfg, &gateway, &workstream_id).await?;
    let bundle = ensure_manuscript_shadow_calibration(
        data_dir,
        &workstream_id,
        &context_packet.packet.workspace_id,
    )
    .map_err(|error| workstream_control_room_error(&workstream_id, error.to_string()))?;
    Ok(Json(bundle.autonomy_policy_manuscript_candidate))
}

async fn workstream_manuscript_shadow_comparison_handler(
    State(state): State<AppState>,
    Extension(consumer): Extension<ConsumerIdentity>,
    Path(workstream_id): Path<String>,
) -> Result<Json<ManuscriptShadowCalibration>, JsonError> {
    ensure_allowed(consumer.ensure_workspace_plane())?;
    ensure_allowed(consumer.ensure_hpc_read())?;
    let cfg = current_cfg(&state).await;
    let data_dir = FsPath::new(&cfg.storage.data_dir);
    let gateway = gateway_client()?;
    let context_packet =
        resolve_workstream_context_packet(&state, data_dir, &cfg, &gateway, &workstream_id).await?;
    let bundle = ensure_manuscript_shadow_calibration(
        data_dir,
        &workstream_id,
        &context_packet.packet.workspace_id,
    )
    .map_err(|error| workstream_control_room_error(&workstream_id, error.to_string()))?;
    Ok(Json(bundle.manuscript_shadow_comparison))
}

async fn workstream_manuscript_rollout_metrics_handler(
    State(state): State<AppState>,
    Extension(consumer): Extension<ConsumerIdentity>,
    Path(workstream_id): Path<String>,
) -> Result<Json<ManuscriptRolloutMetrics>, JsonError> {
    ensure_allowed(consumer.ensure_workspace_plane())?;
    ensure_allowed(consumer.ensure_hpc_read())?;
    let cfg = current_cfg(&state).await;
    let data_dir = FsPath::new(&cfg.storage.data_dir);
    let gateway = gateway_client()?;
    let context_packet =
        resolve_workstream_context_packet(&state, data_dir, &cfg, &gateway, &workstream_id).await?;
    let bundle = ensure_manuscript_shadow_calibration(
        data_dir,
        &workstream_id,
        &context_packet.packet.workspace_id,
    )
    .map_err(|error| workstream_control_room_error(&workstream_id, error.to_string()))?;
    Ok(Json(bundle.manuscript_rollout_metrics))
}

async fn workstream_manuscript_rollout_decision_handler(
    State(state): State<AppState>,
    Extension(consumer): Extension<ConsumerIdentity>,
    Path(workstream_id): Path<String>,
) -> Result<Json<ManuscriptRolloutDecision>, JsonError> {
    ensure_allowed(consumer.ensure_workspace_plane())?;
    ensure_allowed(consumer.ensure_hpc_read())?;
    let cfg = current_cfg(&state).await;
    let data_dir = FsPath::new(&cfg.storage.data_dir);
    let gateway = gateway_client()?;
    let context_packet =
        resolve_workstream_context_packet(&state, data_dir, &cfg, &gateway, &workstream_id).await?;
    let bundle = ensure_manuscript_shadow_calibration(
        data_dir,
        &workstream_id,
        &context_packet.packet.workspace_id,
    )
    .map_err(|error| workstream_control_room_error(&workstream_id, error.to_string()))?;
    Ok(Json(bundle.manuscript_rollout_decision))
}

async fn workstream_manuscript_shadow_history_handler(
    State(state): State<AppState>,
    Extension(consumer): Extension<ConsumerIdentity>,
    Path(workstream_id): Path<String>,
) -> Result<Json<ManuscriptShadowHistory>, JsonError> {
    ensure_allowed(consumer.ensure_workspace_plane())?;
    ensure_allowed(consumer.ensure_hpc_read())?;
    let cfg = current_cfg(&state).await;
    let data_dir = FsPath::new(&cfg.storage.data_dir);
    let gateway = gateway_client()?;
    let context_packet =
        resolve_workstream_context_packet(&state, data_dir, &cfg, &gateway, &workstream_id).await?;
    let bundle = ensure_manuscript_sample_accumulation(
        data_dir,
        &workstream_id,
        &context_packet.packet.workspace_id,
    )
    .map_err(|error| workstream_control_room_error(&workstream_id, error.to_string()))?;
    Ok(Json(bundle.manuscript_shadow_history))
}

async fn workstream_manuscript_soak_metrics_handler(
    State(state): State<AppState>,
    Extension(consumer): Extension<ConsumerIdentity>,
    Path(workstream_id): Path<String>,
) -> Result<Json<ManuscriptSoakMetrics>, JsonError> {
    ensure_allowed(consumer.ensure_workspace_plane())?;
    ensure_allowed(consumer.ensure_hpc_read())?;
    let cfg = current_cfg(&state).await;
    let data_dir = FsPath::new(&cfg.storage.data_dir);
    let gateway = gateway_client()?;
    let context_packet =
        resolve_workstream_context_packet(&state, data_dir, &cfg, &gateway, &workstream_id).await?;
    let bundle = ensure_manuscript_sample_accumulation(
        data_dir,
        &workstream_id,
        &context_packet.packet.workspace_id,
    )
    .map_err(|error| workstream_control_room_error(&workstream_id, error.to_string()))?;
    Ok(Json(bundle.manuscript_soak_metrics))
}

async fn workstream_manuscript_alignment_labels_handler(
    State(state): State<AppState>,
    Extension(consumer): Extension<ConsumerIdentity>,
    Path(workstream_id): Path<String>,
) -> Result<Json<ManuscriptAlignmentLabels>, JsonError> {
    ensure_allowed(consumer.ensure_workspace_plane())?;
    ensure_allowed(consumer.ensure_hpc_read())?;
    let cfg = current_cfg(&state).await;
    let data_dir = FsPath::new(&cfg.storage.data_dir);
    let gateway = gateway_client()?;
    let context_packet =
        resolve_workstream_context_packet(&state, data_dir, &cfg, &gateway, &workstream_id).await?;
    let bundle = ensure_manuscript_alignment_signal_acquisition(
        data_dir,
        &workstream_id,
        &context_packet.packet.workspace_id,
    )
    .map_err(|error| workstream_control_room_error(&workstream_id, error.to_string()))?;
    Ok(Json(bundle.manuscript_alignment_labels))
}

async fn workstream_manuscript_promotion_evidence_handler(
    State(state): State<AppState>,
    Extension(consumer): Extension<ConsumerIdentity>,
    Path(workstream_id): Path<String>,
) -> Result<Json<ManuscriptPromotionEvidence>, JsonError> {
    ensure_allowed(consumer.ensure_workspace_plane())?;
    ensure_allowed(consumer.ensure_hpc_read())?;
    let cfg = current_cfg(&state).await;
    let data_dir = FsPath::new(&cfg.storage.data_dir);
    let gateway = gateway_client()?;
    let context_packet =
        resolve_workstream_context_packet(&state, data_dir, &cfg, &gateway, &workstream_id).await?;
    let bundle = ensure_manuscript_alignment_signal_acquisition(
        data_dir,
        &workstream_id,
        &context_packet.packet.workspace_id,
    )
    .map_err(|error| workstream_control_room_error(&workstream_id, error.to_string()))?;
    Ok(Json(bundle.manuscript_promotion_evidence))
}

async fn workstream_manuscript_promotion_gate_handler(
    State(state): State<AppState>,
    Extension(consumer): Extension<ConsumerIdentity>,
    Path(workstream_id): Path<String>,
) -> Result<Json<ManuscriptPromotionGate>, JsonError> {
    ensure_allowed(consumer.ensure_workspace_plane())?;
    ensure_allowed(consumer.ensure_hpc_read())?;
    let cfg = current_cfg(&state).await;
    let data_dir = FsPath::new(&cfg.storage.data_dir);
    let gateway = gateway_client()?;
    let context_packet =
        resolve_workstream_context_packet(&state, data_dir, &cfg, &gateway, &workstream_id).await?;
    let bundle = ensure_manuscript_alignment_signal_acquisition(
        data_dir,
        &workstream_id,
        &context_packet.packet.workspace_id,
    )
    .map_err(|error| workstream_control_room_error(&workstream_id, error.to_string()))?;
    Ok(Json(bundle.manuscript_promotion_gate))
}

async fn workstream_manuscript_trajectory_quality_handler(
    State(state): State<AppState>,
    Extension(consumer): Extension<ConsumerIdentity>,
    Path(workstream_id): Path<String>,
) -> Result<Json<ManuscriptTrajectoryQuality>, JsonError> {
    ensure_allowed(consumer.ensure_workspace_plane())?;
    ensure_allowed(consumer.ensure_hpc_read())?;
    let cfg = current_cfg(&state).await;
    let data_dir = FsPath::new(&cfg.storage.data_dir);
    let gateway = gateway_client()?;
    let context_packet =
        resolve_workstream_context_packet(&state, data_dir, &cfg, &gateway, &workstream_id).await?;
    let bundle = ensure_manuscript_quality_uplift(
        data_dir,
        &workstream_id,
        &context_packet.packet.workspace_id,
        &context_packet.packet,
    )
    .map_err(|error| workstream_control_room_error(&workstream_id, error.to_string()))?;
    Ok(Json(bundle.manuscript_trajectory_quality))
}

async fn workstream_manuscript_context_adequacy_handler(
    State(state): State<AppState>,
    Extension(consumer): Extension<ConsumerIdentity>,
    Path(workstream_id): Path<String>,
) -> Result<Json<ManuscriptContextAdequacy>, JsonError> {
    ensure_allowed(consumer.ensure_workspace_plane())?;
    ensure_allowed(consumer.ensure_hpc_read())?;
    let cfg = current_cfg(&state).await;
    let data_dir = FsPath::new(&cfg.storage.data_dir);
    let gateway = gateway_client()?;
    let context_packet =
        resolve_workstream_context_packet(&state, data_dir, &cfg, &gateway, &workstream_id).await?;
    let bundle = ensure_manuscript_quality_uplift(
        data_dir,
        &workstream_id,
        &context_packet.packet.workspace_id,
        &context_packet.packet,
    )
    .map_err(|error| workstream_control_room_error(&workstream_id, error.to_string()))?;
    Ok(Json(bundle.manuscript_context_adequacy))
}

async fn workstream_manuscript_tuning_recommendation_handler(
    State(state): State<AppState>,
    Extension(consumer): Extension<ConsumerIdentity>,
    Path(workstream_id): Path<String>,
) -> Result<Json<ManuscriptTuningRecommendation>, JsonError> {
    ensure_allowed(consumer.ensure_workspace_plane())?;
    ensure_allowed(consumer.ensure_hpc_read())?;
    let cfg = current_cfg(&state).await;
    let data_dir = FsPath::new(&cfg.storage.data_dir);
    let gateway = gateway_client()?;
    let context_packet =
        resolve_workstream_context_packet(&state, data_dir, &cfg, &gateway, &workstream_id).await?;
    let bundle = ensure_manuscript_quality_uplift(
        data_dir,
        &workstream_id,
        &context_packet.packet.workspace_id,
        &context_packet.packet,
    )
    .map_err(|error| workstream_control_room_error(&workstream_id, error.to_string()))?;
    Ok(Json(bundle.manuscript_tuning_recommendation))
}

async fn workstream_continuation_dispatch_handler(
    State(state): State<AppState>,
    Extension(consumer): Extension<ConsumerIdentity>,
    Path(workstream_id): Path<String>,
) -> Result<Json<ContinuationDispatch>, JsonError> {
    ensure_allowed(consumer.ensure_workspace_plane())?;
    ensure_allowed(consumer.ensure_hpc_read())?;
    let cfg = current_cfg(&state).await;
    let data_dir = FsPath::new(&cfg.storage.data_dir);
    let gateway = gateway_client()?;
    let context_packet =
        resolve_workstream_context_packet(&state, data_dir, &cfg, &gateway, &workstream_id).await?;
    let continuation_dispatch =
        read_continuation_dispatch(data_dir, &context_packet.packet.workspace_id)
            .map_err(|error| workstream_control_room_error(&workstream_id, error.to_string()))?
            .ok_or_else(|| {
                not_found_response(
                    "continuation_dispatch_not_found",
                    format!("no continuation dispatch found for workstream {}", workstream_id),
                )
            })?;
    Ok(Json(continuation_dispatch))
}

async fn workstream_continuation_dispatch_post_handler(
    State(state): State<AppState>,
    Extension(consumer): Extension<ConsumerIdentity>,
    Path(workstream_id): Path<String>,
    Json(body): Json<ContinuationDispatchRequestBody>,
) -> Result<Json<ContinuationDispatch>, JsonError> {
    ensure_allowed(consumer.ensure_workspace_plane())?;
    ensure_allowed(consumer.ensure_hpc_read())?;
    let cfg = current_cfg(&state).await;
    let data_dir = FsPath::new(&cfg.storage.data_dir);
    let gateway = gateway_client()?;
    let context_packet =
        resolve_workstream_context_packet(&state, data_dir, &cfg, &gateway, &workstream_id).await?;
    let continuation_dispatch = dispatch_follow_on_plan(
        data_dir,
        &cfg,
        &workstream_id,
        context_packet,
        ContinuationDispatchRequest {
            dispatched_by: &body.dispatched_by,
            dispatch_note: body
                .dispatch_note
                .as_deref()
                .unwrap_or("Dispatch the approved follow-on plan into the next bounded execution cycle."),
        },
    )
    .map_err(|error| workstream_control_room_error(&workstream_id, error.to_string()))?;
    Ok(Json(continuation_dispatch))
}

async fn workstream_continuation_receipt_handler(
    State(state): State<AppState>,
    Extension(consumer): Extension<ConsumerIdentity>,
    Path(workstream_id): Path<String>,
) -> Result<Json<ContinuationReceipt>, JsonError> {
    ensure_allowed(consumer.ensure_workspace_plane())?;
    ensure_allowed(consumer.ensure_hpc_read())?;
    let cfg = current_cfg(&state).await;
    let data_dir = FsPath::new(&cfg.storage.data_dir);
    let gateway = gateway_client()?;
    let context_packet =
        resolve_workstream_context_packet(&state, data_dir, &cfg, &gateway, &workstream_id).await?;
    let continuation_receipt =
        read_continuation_receipt(data_dir, &context_packet.packet.workspace_id)
            .map_err(|error| workstream_control_room_error(&workstream_id, error.to_string()))?
            .ok_or_else(|| {
                not_found_response(
                    "continuation_receipt_not_found",
                    format!("no continuation receipt found for workstream {}", workstream_id),
                )
            })?;
    Ok(Json(continuation_receipt))
}

async fn workstream_continuation_state_handler(
    State(state): State<AppState>,
    Extension(consumer): Extension<ConsumerIdentity>,
    Path(workstream_id): Path<String>,
) -> Result<Json<ContinuationStatePlane>, JsonError> {
    ensure_allowed(consumer.ensure_workspace_plane())?;
    ensure_allowed(consumer.ensure_hpc_read())?;
    let cfg = current_cfg(&state).await;
    let data_dir = FsPath::new(&cfg.storage.data_dir);
    let gateway = gateway_client()?;
    let context_packet =
        resolve_workstream_context_packet(&state, data_dir, &cfg, &gateway, &workstream_id).await?;
    let continuation_state =
        read_continuation_state(data_dir, &context_packet.packet.workspace_id)
            .map_err(|error| workstream_control_room_error(&workstream_id, error.to_string()))?
            .ok_or_else(|| {
                not_found_response(
                    "continuation_state_not_found",
                    format!("no continuation state found for workstream {}", workstream_id),
                )
            })?;
    Ok(Json(continuation_state))
}

async fn workstream_workspace_habitat_handler(
    State(state): State<AppState>,
    Extension(consumer): Extension<ConsumerIdentity>,
    Path(workstream_id): Path<String>,
) -> Result<Json<ClusterWorkspaceHabitatResponse>, JsonError> {
    ensure_allowed(consumer.ensure_workspace_plane())?;
    ensure_allowed(consumer.ensure_hpc_read())?;
    let cfg = current_cfg(&state).await;
    let data_dir = FsPath::new(&cfg.storage.data_dir);
    let gateway = gateway_client()?;
    let context_packet =
        resolve_workstream_context_packet(&state, data_dir, &cfg, &gateway, &workstream_id).await?;

    let response = build_workstream_workspace_habitat(&cfg, &workstream_id, context_packet)
        .map_err(|error| workstream_control_room_error(&workstream_id, error.to_string()))?;

    Ok(Json(response))
}

async fn workstream_workspace_habitat_env_handler(
    State(state): State<AppState>,
    Extension(consumer): Extension<ConsumerIdentity>,
    Path(workstream_id): Path<String>,
) -> Result<String, JsonError> {
    ensure_allowed(consumer.ensure_workspace_plane())?;
    ensure_allowed(consumer.ensure_hpc_read())?;
    let cfg = current_cfg(&state).await;
    let data_dir = FsPath::new(&cfg.storage.data_dir);
    let gateway = gateway_client()?;
    let context_packet =
        resolve_workstream_context_packet(&state, data_dir, &cfg, &gateway, &workstream_id).await?;

    let response = build_workstream_workspace_habitat(&cfg, &workstream_id, context_packet)
        .map_err(|error| workstream_control_room_error(&workstream_id, error.to_string()))?;

    Ok(render_workspace_habitat_context_env(&response))
}

async fn workstream_cursor_remote_lane_handler(
    State(state): State<AppState>,
    Extension(consumer): Extension<ConsumerIdentity>,
    Path(workstream_id): Path<String>,
) -> Result<Json<CursorRemoteLaneResponse>, JsonError> {
    ensure_allowed(consumer.ensure_workspace_plane())?;
    ensure_allowed(consumer.ensure_hpc_read())?;
    let cfg = current_cfg(&state).await;
    let data_dir = FsPath::new(&cfg.storage.data_dir);
    let gateway = gateway_client()?;
    let context_packet =
        resolve_workstream_context_packet(&state, data_dir, &cfg, &gateway, &workstream_id).await?;

    let response = build_workstream_cursor_remote_lane(&cfg, &workstream_id, context_packet)
        .map_err(|error| workstream_control_room_error(&workstream_id, error.to_string()))?;

    Ok(Json(response))
}

async fn workstream_workspace_attach_handler(
    State(state): State<AppState>,
    Extension(consumer): Extension<ConsumerIdentity>,
    Path(workstream_id): Path<String>,
) -> Result<Json<WorkspaceAttachResponse>, JsonError> {
    ensure_allowed(consumer.ensure_workspace_plane())?;
    ensure_allowed(consumer.ensure_hpc_read())?;
    let cfg = current_cfg(&state).await;
    let data_dir = FsPath::new(&cfg.storage.data_dir);
    let gateway = gateway_client()?;

    let context_packet =
        resolve_workstream_context_packet(&state, data_dir, &cfg, &gateway, &workstream_id).await?;

    let response = build_workstream_workspace_attach(&cfg, &workstream_id, context_packet)
        .map_err(|error| workstream_control_room_error(&workstream_id, error.to_string()))?;

    Ok(Json(response))
}

async fn workstream_managed_attach_handler(
    State(state): State<AppState>,
    Extension(consumer): Extension<ConsumerIdentity>,
    Path(workstream_id): Path<String>,
) -> Result<Json<WorkspaceAttachResponse>, JsonError> {
    ensure_allowed(consumer.ensure_workspace_plane())?;
    ensure_allowed(consumer.ensure_hpc_read())?;
    let cfg = current_cfg(&state).await;
    let data_dir = FsPath::new(&cfg.storage.data_dir);
    let gateway = gateway_client()?;

    let context_packet =
        resolve_workstream_context_packet(&state, data_dir, &cfg, &gateway, &workstream_id).await?;

    let response = build_workstream_managed_attach(&cfg, &workstream_id, context_packet)
        .map_err(|error| workstream_control_room_error(&workstream_id, error.to_string()))?;

    Ok(Json(response))
}

async fn workstream_workspace_launch_resume_handler(
    State(state): State<AppState>,
    Extension(consumer): Extension<ConsumerIdentity>,
    Path(workstream_id): Path<String>,
) -> Result<Json<WorkspaceLaunchResumeResponse>, JsonError> {
    ensure_allowed(consumer.ensure_workspace_plane())?;
    ensure_allowed(consumer.ensure_hpc_read())?;
    let cfg = current_cfg(&state).await;
    let data_dir = FsPath::new(&cfg.storage.data_dir);
    let gateway = gateway_client()?;

    let context_packet =
        resolve_workstream_context_packet(&state, data_dir, &cfg, &gateway, &workstream_id).await?;

    let response = build_workstream_workspace_launch_resume(&cfg, &workstream_id, context_packet)
        .map_err(|error| workstream_control_room_error(&workstream_id, error.to_string()))?;

    Ok(Json(response))
}

async fn workstream_workspace_template_handler(
    State(state): State<AppState>,
    Extension(consumer): Extension<ConsumerIdentity>,
    Path(workstream_id): Path<String>,
) -> Result<Json<WorkspaceTemplateResponse>, JsonError> {
    ensure_allowed(consumer.ensure_workspace_plane())?;
    ensure_allowed(consumer.ensure_hpc_read())?;
    let cfg = current_cfg(&state).await;
    let data_dir = FsPath::new(&cfg.storage.data_dir);
    let gateway = gateway_client()?;

    let context_packet =
        resolve_workstream_context_packet(&state, data_dir, &cfg, &gateway, &workstream_id).await?;

    let response = build_workstream_workspace_template(&cfg, &workstream_id, context_packet)
        .map_err(|error| workstream_control_room_error(&workstream_id, error.to_string()))?;

    Ok(Json(response))
}

async fn multi_user_gpu_workspace_tenancy_bundle_for_workstream(
    state: &AppState,
    workstream_id: &str,
) -> Result<beagle_darwin::MultiUserGpuWorkspaceTenancyBundle, JsonError> {
    let cfg = current_cfg(state).await;
    let data_dir = FsPath::new(&cfg.storage.data_dir);
    let gateway = gateway_client()?;
    let context_packet =
        resolve_workstream_context_packet(state, data_dir, &cfg, &gateway, workstream_id).await?;
    let workspace_session = load_workspace_session(data_dir, &cfg, &context_packet.packet.workspace_id)
        .map_err(|error| workstream_control_room_error(workstream_id, error.to_string()))?
        .unwrap_or_else(|| {
            WorkspaceSessionState::new(
                &cfg,
                context_packet.packet.workspace_id.clone(),
                Some(context_packet.packet.session_id.clone()),
            )
        });
    let profile_catalog = gateway
        .profiles()
        .await
        .map_err(gateway_error_response)?;
    build_multi_user_gpu_workspace_tenancy_bundle(
        &cfg,
        workstream_id,
        context_packet,
        &workspace_session,
        &profile_catalog,
    )
    .map_err(|error| workstream_control_room_error(workstream_id, error.to_string()))
}

async fn collaborative_workbench_bundle_for_workstream(
    state: &AppState,
    workstream_id: &str,
) -> Result<beagle_darwin::CollaborativeComputeExperimentWorkbenchBundle, JsonError> {
    let cfg = current_cfg(state).await;
    let data_dir = FsPath::new(&cfg.storage.data_dir);
    let gateway = gateway_client()?;
    let context_packet =
        resolve_workstream_context_packet(state, data_dir, &cfg, &gateway, workstream_id).await?;
    let workspace_session = load_workspace_session(data_dir, &cfg, &context_packet.packet.workspace_id)
        .map_err(|error| workstream_control_room_error(workstream_id, error.to_string()))?
        .unwrap_or_else(|| {
            WorkspaceSessionState::new(
                &cfg,
                context_packet.packet.workspace_id.clone(),
                Some(context_packet.packet.session_id.clone()),
            )
        });
    let profile_catalog = gateway
        .profiles()
        .await
        .map_err(gateway_error_response)?;
    build_collaborative_compute_experiment_workbench(
        &cfg,
        workstream_id,
        context_packet,
        &workspace_session,
        &profile_catalog,
    )
    .map_err(|error| workstream_control_room_error(workstream_id, error.to_string()))
}

async fn workstream_collaborative_workbench_handler(
    State(state): State<AppState>,
    Extension(consumer): Extension<ConsumerIdentity>,
    Path(workstream_id): Path<String>,
) -> Result<Json<CollaborativeComputeExperimentWorkbench>, JsonError> {
    ensure_allowed(consumer.ensure_workspace_plane())?;
    ensure_allowed(consumer.ensure_hpc_read())?;
    let bundle = collaborative_workbench_bundle_for_workstream(&state, &workstream_id).await?;
    Ok(Json(bundle.collaborative_workbench))
}

async fn workstream_workbench_session_handler(
    State(state): State<AppState>,
    Extension(consumer): Extension<ConsumerIdentity>,
    Path(workstream_id): Path<String>,
) -> Result<Json<CollaborativeWorkbenchSessionContract>, JsonError> {
    ensure_allowed(consumer.ensure_workspace_plane())?;
    ensure_allowed(consumer.ensure_hpc_read())?;
    let bundle = collaborative_workbench_bundle_for_workstream(&state, &workstream_id).await?;
    Ok(Json(bundle.workbench_session))
}

async fn workstream_compute_selection_handler(
    State(state): State<AppState>,
    Extension(consumer): Extension<ConsumerIdentity>,
    Path(workstream_id): Path<String>,
) -> Result<Json<CollaborativeWorkbenchComputeSelectionContract>, JsonError> {
    ensure_allowed(consumer.ensure_workspace_plane())?;
    ensure_allowed(consumer.ensure_hpc_read())?;
    let bundle = collaborative_workbench_bundle_for_workstream(&state, &workstream_id).await?;
    Ok(Json(bundle.compute_selection))
}

async fn workstream_collaboration_access_handler(
    State(state): State<AppState>,
    Extension(consumer): Extension<ConsumerIdentity>,
    Path(workstream_id): Path<String>,
) -> Result<Json<CollaborativeWorkbenchCollaborationContract>, JsonError> {
    ensure_allowed(consumer.ensure_workspace_plane())?;
    ensure_allowed(consumer.ensure_hpc_read())?;
    let bundle = collaborative_workbench_bundle_for_workstream(&state, &workstream_id).await?;
    Ok(Json(bundle.collaboration_access))
}

async fn workstream_workbench_run_handler(
    State(state): State<AppState>,
    Extension(consumer): Extension<ConsumerIdentity>,
    Path(workstream_id): Path<String>,
) -> Result<Json<CollaborativeWorkbenchRunContract>, JsonError> {
    ensure_allowed(consumer.ensure_workspace_plane())?;
    ensure_allowed(consumer.ensure_hpc_read())?;
    let bundle = collaborative_workbench_bundle_for_workstream(&state, &workstream_id).await?;
    Ok(Json(bundle.workbench_run))
}

async fn workstream_workbench_reservation_handler(
    State(state): State<AppState>,
    Extension(consumer): Extension<ConsumerIdentity>,
    Path(workstream_id): Path<String>,
) -> Result<Json<WorkbenchReservation>, JsonError> {
    ensure_allowed(consumer.ensure_workspace_plane())?;
    ensure_allowed(consumer.ensure_hpc_read())?;
    let cfg = current_cfg(&state).await;
    let data_dir = FsPath::new(&cfg.storage.data_dir);
    let bundle = collaborative_workbench_bundle_for_workstream(&state, &workstream_id).await?;
    let reservation = beagle_darwin::read_workbench_reservation(data_dir, &bundle)
        .map_err(|error| workstream_control_room_error(&workstream_id, error.to_string()))?
        .ok_or_else(|| {
            not_found_response(
                "workbench_reservation_not_found",
                format!("no workbench reservation found for workstream {}", workstream_id),
            )
        })?;
    Ok(Json(reservation))
}

async fn workstream_workbench_run_orchestration_handler(
    State(state): State<AppState>,
    Extension(consumer): Extension<ConsumerIdentity>,
    Path(workstream_id): Path<String>,
) -> Result<Json<WorkbenchRun>, JsonError> {
    ensure_allowed(consumer.ensure_workspace_plane())?;
    ensure_allowed(consumer.ensure_hpc_read())?;
    let cfg = current_cfg(&state).await;
    let data_dir = FsPath::new(&cfg.storage.data_dir);
    let bundle = collaborative_workbench_bundle_for_workstream(&state, &workstream_id).await?;
    let run = beagle_darwin::read_workbench_run(data_dir, &bundle.workbench_session.workspace_id)
        .map_err(|error| workstream_control_room_error(&workstream_id, error.to_string()))?
        .ok_or_else(|| {
            not_found_response(
                "workbench_run_not_found",
                format!("no workbench run found for workstream {}", workstream_id),
            )
        })?;
    Ok(Json(run))
}

async fn workstream_workbench_result_binding_handler(
    State(state): State<AppState>,
    Extension(consumer): Extension<ConsumerIdentity>,
    Path(workstream_id): Path<String>,
) -> Result<Json<WorkbenchResultBinding>, JsonError> {
    ensure_allowed(consumer.ensure_workspace_plane())?;
    ensure_allowed(consumer.ensure_hpc_read())?;
    let cfg = current_cfg(&state).await;
    let data_dir = FsPath::new(&cfg.storage.data_dir);
    let bundle = collaborative_workbench_bundle_for_workstream(&state, &workstream_id).await?;
    let result_binding = beagle_darwin::read_workbench_result_binding(
        data_dir,
        &workstream_id,
        &bundle.workbench_session.workspace_id,
    )
    .map_err(|error| workstream_control_room_error(&workstream_id, error.to_string()))?
    .ok_or_else(|| {
        not_found_response(
            "workbench_result_binding_not_found",
            format!("no workbench result binding found for workstream {}", workstream_id),
        )
    })?;
    Ok(Json(result_binding))
}

async fn workstream_run_result_identity_receipt_handler(
    State(state): State<AppState>,
    Extension(consumer): Extension<ConsumerIdentity>,
    Path(workstream_id): Path<String>,
) -> Result<Json<RunResultIdentityReceipt>, JsonError> {
    ensure_allowed(consumer.ensure_workspace_plane())?;
    ensure_allowed(consumer.ensure_hpc_read())?;
    let cfg = current_cfg(&state).await;
    let data_dir = FsPath::new(&cfg.storage.data_dir);
    let bundle = collaborative_workbench_bundle_for_workstream(&state, &workstream_id).await?;
    let receipt = beagle_darwin::read_run_result_identity_receipt(
        data_dir,
        &workstream_id,
        &bundle.workbench_session.workspace_id,
    )
    .map_err(|error| workstream_control_room_error(&workstream_id, error.to_string()))?
    .ok_or_else(|| {
        not_found_response(
            "run_result_identity_receipt_not_found",
            format!(
                "no run result identity receipt found for workstream {}",
                workstream_id
            ),
        )
    })?;
    Ok(Json(receipt))
}

async fn workstream_run_scoped_publication_handler(
    State(state): State<AppState>,
    Extension(consumer): Extension<ConsumerIdentity>,
    Path(workstream_id): Path<String>,
) -> Result<Json<RunScopedPublication>, JsonError> {
    ensure_allowed(consumer.ensure_workspace_plane())?;
    ensure_allowed(consumer.ensure_hpc_read())?;
    let cfg = current_cfg(&state).await;
    let data_dir = FsPath::new(&cfg.storage.data_dir);
    let bundle = collaborative_workbench_bundle_for_workstream(&state, &workstream_id).await?;
    let publication = beagle_darwin::read_run_scoped_publication(
        data_dir,
        &workstream_id,
        &bundle.workbench_session.workspace_id,
    )
    .map_err(|error| workstream_control_room_error(&workstream_id, error.to_string()))?
    .ok_or_else(|| {
        not_found_response(
            "run_scoped_publication_not_found",
            format!(
                "no run scoped publication found for workstream {}",
                workstream_id
            ),
        )
    })?;
    Ok(Json(publication))
}

async fn workstream_deterministic_result_binding_handler(
    State(state): State<AppState>,
    Extension(consumer): Extension<ConsumerIdentity>,
    Path(workstream_id): Path<String>,
) -> Result<Json<DeterministicResultBinding>, JsonError> {
    ensure_allowed(consumer.ensure_workspace_plane())?;
    ensure_allowed(consumer.ensure_hpc_read())?;
    let cfg = current_cfg(&state).await;
    let data_dir = FsPath::new(&cfg.storage.data_dir);
    let bundle = collaborative_workbench_bundle_for_workstream(&state, &workstream_id).await?;
    let binding = beagle_darwin::read_deterministic_result_binding(
        data_dir,
        &workstream_id,
        &bundle.workbench_session.workspace_id,
    )
    .map_err(|error| workstream_control_room_error(&workstream_id, error.to_string()))?
    .ok_or_else(|| {
        not_found_response(
            "deterministic_result_binding_not_found",
            format!(
                "no deterministic result binding found for workstream {}",
                workstream_id
            ),
        )
    })?;
    Ok(Json(binding))
}

async fn workstream_run_capsule_handler(
    State(state): State<AppState>,
    Extension(consumer): Extension<ConsumerIdentity>,
    Path(workstream_id): Path<String>,
) -> Result<Json<RunCapsule>, JsonError> {
    ensure_allowed(consumer.ensure_workspace_plane())?;
    ensure_allowed(consumer.ensure_hpc_read())?;
    let cfg = current_cfg(&state).await;
    let data_dir = FsPath::new(&cfg.storage.data_dir);
    let bundle = collaborative_workbench_bundle_for_workstream(&state, &workstream_id).await?;
    let capsule = read_latest_run_capsule(data_dir, &bundle.workbench_session.workspace_id)
        .map_err(|error| workstream_control_room_error(&workstream_id, error.to_string()))?
        .ok_or_else(|| {
            not_found_response(
                "run_capsule_not_found",
                format!("no run capsule found for workstream {}", workstream_id),
            )
        })?;
    Ok(Json(capsule))
}

async fn workstream_prior_run_capsule_handler(
    State(state): State<AppState>,
    Extension(consumer): Extension<ConsumerIdentity>,
    Path(workstream_id): Path<String>,
) -> Result<Json<RunCapsule>, JsonError> {
    ensure_allowed(consumer.ensure_workspace_plane())?;
    ensure_allowed(consumer.ensure_hpc_read())?;
    let cfg = current_cfg(&state).await;
    let data_dir = FsPath::new(&cfg.storage.data_dir);
    let bundle = collaborative_workbench_bundle_for_workstream(&state, &workstream_id).await?;
    let capsule = read_prior_run_capsule(data_dir, &bundle.workbench_session.workspace_id)
        .map_err(|error| workstream_control_room_error(&workstream_id, error.to_string()))?
        .ok_or_else(|| {
            not_found_response(
                "prior_run_capsule_not_found",
                format!("no prior run capsule found for workstream {}", workstream_id),
            )
        })?;
    Ok(Json(capsule))
}

async fn workstream_run_diff_handler(
    State(state): State<AppState>,
    Extension(consumer): Extension<ConsumerIdentity>,
    Path(workstream_id): Path<String>,
) -> Result<Json<RunDiff>, JsonError> {
    ensure_allowed(consumer.ensure_workspace_plane())?;
    ensure_allowed(consumer.ensure_hpc_read())?;
    let cfg = current_cfg(&state).await;
    let data_dir = FsPath::new(&cfg.storage.data_dir);
    let bundle = collaborative_workbench_bundle_for_workstream(&state, &workstream_id).await?;
    let diff = read_run_diff(data_dir, &bundle.workbench_session.workspace_id)
        .map_err(|error| workstream_control_room_error(&workstream_id, error.to_string()))?
        .ok_or_else(|| {
            not_found_response(
                "run_diff_not_found",
                format!("no reproducibility diff found for workstream {}", workstream_id),
            )
        })?;
    Ok(Json(diff))
}

async fn workstream_replay_request_handler(
    State(state): State<AppState>,
    Extension(consumer): Extension<ConsumerIdentity>,
    Path(workstream_id): Path<String>,
) -> Result<Json<ReplayRequest>, JsonError> {
    ensure_allowed(consumer.ensure_workspace_plane())?;
    ensure_allowed(consumer.ensure_hpc_read())?;
    let cfg = current_cfg(&state).await;
    let data_dir = FsPath::new(&cfg.storage.data_dir);
    let bundle = collaborative_workbench_bundle_for_workstream(&state, &workstream_id).await?;
    let replay_request = read_replay_request(
        data_dir,
        &workstream_id,
        &bundle.workbench_session.workspace_id,
    )
    .map_err(|error| workstream_control_room_error(&workstream_id, error.to_string()))?
    .ok_or_else(|| {
        not_found_response(
            "replay_request_not_found",
            format!("no replay request found for workstream {}", workstream_id),
        )
    })?;
    Ok(Json(replay_request))
}

async fn workstream_replay_execution_handler(
    State(state): State<AppState>,
    Extension(consumer): Extension<ConsumerIdentity>,
    Path(workstream_id): Path<String>,
) -> Result<Json<ReplayExecutionReceipt>, JsonError> {
    ensure_allowed(consumer.ensure_workspace_plane())?;
    ensure_allowed(consumer.ensure_hpc_read())?;
    let cfg = current_cfg(&state).await;
    let data_dir = FsPath::new(&cfg.storage.data_dir);
    let bundle = collaborative_workbench_bundle_for_workstream(&state, &workstream_id).await?;
    let replay_execution =
        read_latest_replay_execution(data_dir, &bundle.workbench_session.workspace_id)
            .map_err(|error| workstream_control_room_error(&workstream_id, error.to_string()))?
            .ok_or_else(|| {
                not_found_response(
                    "replay_execution_not_found",
                    format!("no replay execution found for workstream {}", workstream_id),
                )
            })?;
    Ok(Json(replay_execution))
}

async fn workstream_replay_execution_dispatch_handler(
    State(state): State<AppState>,
    Extension(consumer): Extension<ConsumerIdentity>,
    Path(workstream_id): Path<String>,
    Json(body): Json<ReplayExecutionRequestBody>,
) -> Result<Json<ReplayExecutionBundle>, JsonError> {
    ensure_allowed(consumer.ensure_workspace_plane())?;
    let cfg = current_cfg(&state).await;
    let data_dir = FsPath::new(&cfg.storage.data_dir);
    let gateway = gateway_client()?;
    let bridge = tool_bridge_from_cfg(&cfg)?;
    let detail = get_workstream_control_room_detail(data_dir, &cfg, &workstream_id)
        .map_err(|error| workstream_control_room_error(&workstream_id, error.to_string()))?;
    let workbench_bundle = collaborative_workbench_bundle_for_workstream(&state, &workstream_id).await?;
    let replay_request = read_replay_request(
        data_dir,
        &workstream_id,
        &workbench_bundle.workbench_session.workspace_id,
    )
    .map_err(|error| workstream_control_room_error(&workstream_id, error.to_string()))?
    .ok_or_else(|| {
        not_found_response(
            "replay_request_not_found",
            format!("no replay request found for workstream {}", workstream_id),
        )
    })?;
    ensure_allowed(consumer.ensure_hpc_submit(&replay_request.compute_profile_id))?;
    let response = execute_replay_request(
        data_dir,
        &cfg,
        &gateway,
        &bridge,
        &detail,
        &workbench_bundle,
        &replay_request,
        &beagle_darwin::ReplayExecutionRequest {
            requested_by: &body.requested_by,
            requester_role_id: &body.requester_role_id,
            execution_mode: &body.execution_mode,
            run_label: body.run_label.as_deref(),
            reservation_note: &body.reservation_note,
            dispatch_note: &body.dispatch_note,
            poll_interval_seconds: body.poll_interval_seconds,
            timeout_seconds: body.timeout_seconds,
            code_provenance_capture: body.code_provenance_capture.as_ref(),
        },
    )
    .await
    .map_err(|error| workstream_control_room_error(&workstream_id, error.to_string()))?;
    Ok(Json(response))
}

async fn workstream_study_registry_handler(
    State(state): State<AppState>,
    Extension(consumer): Extension<ConsumerIdentity>,
    Path(workstream_id): Path<String>,
) -> Result<Json<StudyRegistry>, JsonError> {
    ensure_allowed(consumer.ensure_workspace_plane())?;
    ensure_allowed(consumer.ensure_hpc_read())?;
    let cfg = current_cfg(&state).await;
    let data_dir = FsPath::new(&cfg.storage.data_dir);
    let workbench_bundle = collaborative_workbench_bundle_for_workstream(&state, &workstream_id).await?;
    let bundle = ensure_study_registry_sweep(
        data_dir,
        &workstream_id,
        &workbench_bundle.workbench_session.workspace_id,
    )
    .map_err(|error| workstream_control_room_error(&workstream_id, error.to_string()))?;
    Ok(Json(bundle.study_registry))
}

async fn workstream_study_dag_handler(
    State(state): State<AppState>,
    Extension(consumer): Extension<ConsumerIdentity>,
    Path(workstream_id): Path<String>,
) -> Result<Json<StudyDag>, JsonError> {
    ensure_allowed(consumer.ensure_workspace_plane())?;
    ensure_allowed(consumer.ensure_hpc_read())?;
    let cfg = current_cfg(&state).await;
    let data_dir = FsPath::new(&cfg.storage.data_dir);
    let workbench_bundle = collaborative_workbench_bundle_for_workstream(&state, &workstream_id).await?;
    let bundle = ensure_study_registry_sweep(
        data_dir,
        &workstream_id,
        &workbench_bundle.workbench_session.workspace_id,
    )
    .map_err(|error| workstream_control_room_error(&workstream_id, error.to_string()))?;
    Ok(Json(bundle.study_dag))
}

async fn workstream_study_sweep_handler(
    State(state): State<AppState>,
    Extension(consumer): Extension<ConsumerIdentity>,
    Path(workstream_id): Path<String>,
) -> Result<Json<StudySweep>, JsonError> {
    ensure_allowed(consumer.ensure_workspace_plane())?;
    ensure_allowed(consumer.ensure_hpc_read())?;
    let cfg = current_cfg(&state).await;
    let data_dir = FsPath::new(&cfg.storage.data_dir);
    let workbench_bundle = collaborative_workbench_bundle_for_workstream(&state, &workstream_id).await?;
    let bundle = ensure_study_registry_sweep(
        data_dir,
        &workstream_id,
        &workbench_bundle.workbench_session.workspace_id,
    )
    .map_err(|error| workstream_control_room_error(&workstream_id, error.to_string()))?;
    Ok(Json(bundle.study_sweep))
}

async fn workstream_comparative_result_summary_handler(
    State(state): State<AppState>,
    Extension(consumer): Extension<ConsumerIdentity>,
    Path(workstream_id): Path<String>,
) -> Result<Json<ComparativeResultSummary>, JsonError> {
    ensure_allowed(consumer.ensure_workspace_plane())?;
    ensure_allowed(consumer.ensure_hpc_read())?;
    let cfg = current_cfg(&state).await;
    let data_dir = FsPath::new(&cfg.storage.data_dir);
    let workbench_bundle = collaborative_workbench_bundle_for_workstream(&state, &workstream_id).await?;
    let bundle = ensure_study_registry_sweep(
        data_dir,
        &workstream_id,
        &workbench_bundle.workbench_session.workspace_id,
    )
    .map_err(|error| workstream_control_room_error(&workstream_id, error.to_string()))?;
    Ok(Json(bundle.comparative_result_summary))
}

async fn workstream_study_decision_handler(
    State(state): State<AppState>,
    Extension(consumer): Extension<ConsumerIdentity>,
    Path(workstream_id): Path<String>,
) -> Result<Json<StudyDecision>, JsonError> {
    ensure_allowed(consumer.ensure_workspace_plane())?;
    ensure_allowed(consumer.ensure_hpc_read())?;
    let cfg = current_cfg(&state).await;
    let data_dir = FsPath::new(&cfg.storage.data_dir);
    let workbench_bundle = collaborative_workbench_bundle_for_workstream(&state, &workstream_id).await?;
    let bundle = ensure_study_decision_engine(
        data_dir,
        &workstream_id,
        &workbench_bundle.workbench_session.workspace_id,
    )
    .map_err(|error| workstream_control_room_error(&workstream_id, error.to_string()))?;
    Ok(Json(bundle.study_decision))
}

async fn workstream_study_decision_basis_handler(
    State(state): State<AppState>,
    Extension(consumer): Extension<ConsumerIdentity>,
    Path(workstream_id): Path<String>,
) -> Result<Json<StudyDecisionBasis>, JsonError> {
    ensure_allowed(consumer.ensure_workspace_plane())?;
    ensure_allowed(consumer.ensure_hpc_read())?;
    let cfg = current_cfg(&state).await;
    let data_dir = FsPath::new(&cfg.storage.data_dir);
    let workbench_bundle = collaborative_workbench_bundle_for_workstream(&state, &workstream_id).await?;
    let bundle = ensure_study_decision_engine(
        data_dir,
        &workstream_id,
        &workbench_bundle.workbench_session.workspace_id,
    )
    .map_err(|error| workstream_control_room_error(&workstream_id, error.to_string()))?;
    Ok(Json(bundle.study_decision_basis))
}

async fn workstream_next_run_proposal_handler(
    State(state): State<AppState>,
    Extension(consumer): Extension<ConsumerIdentity>,
    Path(workstream_id): Path<String>,
) -> Result<Json<NextRunProposal>, JsonError> {
    ensure_allowed(consumer.ensure_workspace_plane())?;
    ensure_allowed(consumer.ensure_hpc_read())?;
    let cfg = current_cfg(&state).await;
    let data_dir = FsPath::new(&cfg.storage.data_dir);
    let workbench_bundle = collaborative_workbench_bundle_for_workstream(&state, &workstream_id).await?;
    let bundle = ensure_study_decision_engine(
        data_dir,
        &workstream_id,
        &workbench_bundle.workbench_session.workspace_id,
    )
    .map_err(|error| workstream_control_room_error(&workstream_id, error.to_string()))?;
    Ok(Json(bundle.next_run_proposal))
}

async fn workstream_study_proposal_dispatch_handler(
    State(state): State<AppState>,
    Extension(consumer): Extension<ConsumerIdentity>,
    Path(workstream_id): Path<String>,
) -> Result<Json<StudyProposalDispatch>, JsonError> {
    ensure_allowed(consumer.ensure_workspace_plane())?;
    ensure_allowed(consumer.ensure_hpc_read())?;
    let cfg = current_cfg(&state).await;
    let data_dir = FsPath::new(&cfg.storage.data_dir);
    let workbench_bundle = collaborative_workbench_bundle_for_workstream(&state, &workstream_id).await?;
    let dispatch = read_study_proposal_dispatch(
        data_dir,
        &workbench_bundle.workbench_session.workspace_id,
    )
    .map_err(|error| workstream_control_room_error(&workstream_id, error.to_string()))?
    .ok_or_else(|| {
        not_found_response(
            "study_proposal_dispatch_not_found",
            format!(
                "no study proposal dispatch found for workstream {}",
                workstream_id
            ),
        )
    })?;
    Ok(Json(dispatch))
}

async fn workstream_study_proposal_dispatch_post_handler(
    State(state): State<AppState>,
    Extension(consumer): Extension<ConsumerIdentity>,
    Path(workstream_id): Path<String>,
    Json(body): Json<StudyProposalDispatchRequestBody>,
) -> Result<Json<StudyProposalDispatchBundle>, JsonError> {
    ensure_allowed(consumer.ensure_workspace_plane())?;
    let cfg = current_cfg(&state).await;
    let data_dir = FsPath::new(&cfg.storage.data_dir);
    let gateway = gateway_client()?;
    let bridge = tool_bridge_from_cfg(&cfg)?;
    let workbench_bundle = collaborative_workbench_bundle_for_workstream(&state, &workstream_id).await?;
    let detail = get_workstream_control_room_detail(data_dir, &cfg, &workstream_id)
        .map_err(|error| workstream_control_room_error(&workstream_id, error.to_string()))?;
    let decision_bundle = ensure_study_decision_engine(
        data_dir,
        &workstream_id,
        &workbench_bundle.workbench_session.workspace_id,
    )
    .map_err(|error| workstream_control_room_error(&workstream_id, error.to_string()))?;
    let approved_compute_profile_id = body
        .proposed_compute_profile_id_override
        .clone()
        .unwrap_or_else(|| {
            decision_bundle
                .next_run_proposal
                .proposed_compute_profile_id
                .clone()
        });
    ensure_allowed(consumer.ensure_hpc_submit(&approved_compute_profile_id))?;
    let dispatch_bundle = ensure_study_proposal_dispatch(
        data_dir,
        &cfg,
        &gateway,
        &bridge,
        &detail,
        &workbench_bundle,
        &workstream_id,
        &StudyProposalDispatchRequest {
            approved_by: &body.approved_by,
            dispatch_note: body.dispatch_note.as_deref(),
            proposed_run_label_override: body.proposed_run_label_override.as_deref(),
            proposed_compute_profile_id_override: Some(approved_compute_profile_id.as_str()),
        },
    )
    .await
    .map_err(|error| workstream_control_room_error(&workstream_id, error.to_string()))?;
    Ok(Json(dispatch_bundle))
}

async fn workstream_study_run_update_handler(
    State(state): State<AppState>,
    Extension(consumer): Extension<ConsumerIdentity>,
    Path(workstream_id): Path<String>,
) -> Result<Json<StudyRunUpdate>, JsonError> {
    ensure_allowed(consumer.ensure_workspace_plane())?;
    ensure_allowed(consumer.ensure_hpc_read())?;
    let cfg = current_cfg(&state).await;
    let data_dir = FsPath::new(&cfg.storage.data_dir);
    let workbench_bundle = collaborative_workbench_bundle_for_workstream(&state, &workstream_id).await?;
    let update = read_study_run_update(data_dir, &workbench_bundle.workbench_session.workspace_id)
        .map_err(|error| workstream_control_room_error(&workstream_id, error.to_string()))?
        .ok_or_else(|| {
            not_found_response(
                "study_run_update_not_found",
                format!("no study run update found for workstream {}", workstream_id),
            )
        })?;
    Ok(Json(update))
}

async fn workstream_study_continuation_state_handler(
    State(state): State<AppState>,
    Extension(consumer): Extension<ConsumerIdentity>,
    Path(workstream_id): Path<String>,
) -> Result<Json<StudyContinuationState>, JsonError> {
    ensure_allowed(consumer.ensure_workspace_plane())?;
    ensure_allowed(consumer.ensure_hpc_read())?;
    let cfg = current_cfg(&state).await;
    let data_dir = FsPath::new(&cfg.storage.data_dir);
    let workbench_bundle = collaborative_workbench_bundle_for_workstream(&state, &workstream_id).await?;
    let continuation_state = read_study_continuation_state(
        data_dir,
        &workbench_bundle.workbench_session.workspace_id,
    )
    .map_err(|error| workstream_control_room_error(&workstream_id, error.to_string()))?
    .ok_or_else(|| {
        not_found_response(
            "study_continuation_state_not_found",
            format!(
                "no study continuation state found for workstream {}",
                workstream_id
            ),
        )
    })?;
    Ok(Json(continuation_state))
}

async fn workstream_study_convergence_handler(
    State(state): State<AppState>,
    Extension(consumer): Extension<ConsumerIdentity>,
    Path(workstream_id): Path<String>,
) -> Result<Json<StudyConvergenceBundle>, JsonError> {
    ensure_allowed(consumer.ensure_workspace_plane())?;
    ensure_allowed(consumer.ensure_hpc_read())?;
    let cfg = current_cfg(&state).await;
    let data_dir = FsPath::new(&cfg.storage.data_dir);
    let workbench_bundle = collaborative_workbench_bundle_for_workstream(&state, &workstream_id).await?;
    let convergence = ensure_study_convergence(
        data_dir,
        &workstream_id,
        &workbench_bundle.workbench_session.workspace_id,
    )
    .map_err(|error| workstream_control_room_error(&workstream_id, error.to_string()))?;
    Ok(Json(convergence))
}

async fn workstream_study_promotion_execution_handler(
    State(state): State<AppState>,
    Extension(consumer): Extension<ConsumerIdentity>,
    Path(workstream_id): Path<String>,
) -> Result<Json<StudyPromotionExecutionBundle>, JsonError> {
    ensure_allowed(consumer.ensure_workspace_plane())?;
    ensure_allowed(consumer.ensure_hpc_read())?;
    let cfg = current_cfg(&state).await;
    let data_dir = FsPath::new(&cfg.storage.data_dir);
    let workbench_bundle = collaborative_workbench_bundle_for_workstream(&state, &workstream_id).await?;
    let execution = ensure_study_promotion_execution(
        data_dir,
        &workstream_id,
        &workbench_bundle.workbench_session.workspace_id,
    )
    .map_err(|error| workstream_control_room_error(&workstream_id, error.to_string()))?;
    Ok(Json(execution))
}

async fn workstream_baseline_adoption_handler(
    State(state): State<AppState>,
    Extension(consumer): Extension<ConsumerIdentity>,
    Path(workstream_id): Path<String>,
) -> Result<Json<BaselineAdoptionBundle>, JsonError> {
    ensure_allowed(consumer.ensure_workspace_plane())?;
    ensure_allowed(consumer.ensure_hpc_read())?;

    let cfg = current_cfg(&state).await;
    let data_dir = FsPath::new(&cfg.storage.data_dir);
    let workbench_bundle = collaborative_workbench_bundle_for_workstream(&state, &workstream_id).await?;

    tracing::info!(
        workstream_id = %workstream_id,
        workspace_id = %workbench_bundle.workbench_session.workspace_id,
        "executing baseline adoption (B26.6)"
    );

    let bundle = ensure_baseline_adoption(
        data_dir,
        &workstream_id,
        &workbench_bundle.workbench_session.workspace_id,
    )
    .map_err(|error| workstream_control_room_error(&workstream_id, error.to_string()))?;

    tracing::info!(
        workstream_id = %workstream_id,
        adoption_id = %bundle.baseline_adoption.adoption_id,
        "baseline adoption completed successfully"
    );

    Ok(Json(bundle))
}

async fn workstream_baseline_rollback_plan_handler(
    State(state): State<AppState>,
    Extension(consumer): Extension<ConsumerIdentity>,
    Path(workstream_id): Path<String>,
) -> Result<Json<BaselineRollbackPlan>, JsonError> {
    ensure_allowed(consumer.ensure_workspace_plane())?;
    ensure_allowed(consumer.ensure_hpc_read())?;
    let cfg = current_cfg(&state).await;
    let data_dir = FsPath::new(&cfg.storage.data_dir);
    let workbench_bundle = collaborative_workbench_bundle_for_workstream(&state, &workstream_id).await?;
    let workspace_id = workbench_bundle.workbench_session.workspace_id.clone();
    let plan = read_baseline_rollback_plan(data_dir, &workspace_id)
        .map_err(|error| workstream_control_room_error(&workstream_id, error.to_string()))?
        .ok_or_else(|| {
            not_found_response(
                "baseline_rollback_plan_not_found",
                format!(
                    "no baseline rollback plan found for workstream {} (run baseline-adoption first)",
                    workstream_id
                ),
            )
        })?;
    Ok(Json(plan))
}

async fn workstream_next_study_seed_handler(
    State(state): State<AppState>,
    Extension(consumer): Extension<ConsumerIdentity>,
    Path(workstream_id): Path<String>,
) -> Result<Json<NextStudySeed>, JsonError> {
    ensure_allowed(consumer.ensure_workspace_plane())?;
    ensure_allowed(consumer.ensure_hpc_read())?;
    let cfg = current_cfg(&state).await;
    let data_dir = FsPath::new(&cfg.storage.data_dir);
    let workbench_bundle = collaborative_workbench_bundle_for_workstream(&state, &workstream_id).await?;
    let workspace_id = workbench_bundle.workbench_session.workspace_id.clone();
    let seed = read_next_study_seed(data_dir, &workspace_id)
        .map_err(|error| workstream_control_room_error(&workstream_id, error.to_string()))?
        .ok_or_else(|| {
            not_found_response(
                "next_study_seed_not_found",
                format!(
                    "no next-study seed found for workstream {} (run baseline-adoption first)",
                    workstream_id
                ),
            )
        })?;
    Ok(Json(seed))
}

/// B27.1 — Study Continuation from Bounded Baseline
async fn workstream_study_continuation_handler(
    State(state): State<AppState>,
    Extension(consumer): Extension<ConsumerIdentity>,
    Path(workstream_id): Path<String>,
) -> Result<Json<StudyContinuationState>, JsonError> {
    use beagle_darwin::read_study_continuation_state;

    ensure_allowed(consumer.ensure_workspace_plane())?;
    ensure_allowed(consumer.ensure_hpc_read())?;

    let cfg = current_cfg(&state).await;
    let data_dir = FsPath::new(&cfg.storage.data_dir);
    let workbench_bundle = collaborative_workbench_bundle_for_workstream(&state, &workstream_id).await?;
    let workspace_id = workbench_bundle.workbench_session.workspace_id.clone();

    tracing::info!(
        workstream_id = %workstream_id,
        workspace_id = %workspace_id,
        "fetching study continuation state (B27.1)"
    );

    let continuation = read_study_continuation_state(data_dir, &workspace_id)
        .map_err(|error| workstream_control_room_error(&workstream_id, error.to_string()))?
        .ok_or_else(|| {
            not_found_response(
                "study_continuation_not_found",
                format!(
                    "no study continuation state found for workstream {} (run study proposal dispatch first)",
                    workstream_id
                ),
            )
        })?;

    tracing::info!(
        workstream_id = %workstream_id,
        continuation_state_id = %continuation.continuation_state_id,
        "study continuation state retrieved"
    );

    Ok(Json(continuation))
}

async fn workstream_code_provenance_handler(
    State(state): State<AppState>,
    Extension(consumer): Extension<ConsumerIdentity>,
    Path(workstream_id): Path<String>,
) -> Result<Json<CodeProvenance>, JsonError> {
    ensure_allowed(consumer.ensure_workspace_plane())?;
    ensure_allowed(consumer.ensure_hpc_read())?;
    let cfg = current_cfg(&state).await;
    let data_dir = FsPath::new(&cfg.storage.data_dir);
    let bundle = collaborative_workbench_bundle_for_workstream(&state, &workstream_id).await?;
    let code_provenance = read_code_provenance(data_dir, &bundle.workbench_session.workspace_id)
        .map_err(|error| workstream_control_room_error(&workstream_id, error.to_string()))?
        .ok_or_else(|| {
            not_found_response(
                "code_provenance_not_found",
                format!("no code provenance found for workstream {}", workstream_id),
            )
        })?;
    Ok(Json(code_provenance))
}

async fn workstream_workspace_snapshot_handler(
    State(state): State<AppState>,
    Extension(consumer): Extension<ConsumerIdentity>,
    Path(workstream_id): Path<String>,
) -> Result<Json<WorkspaceSnapshot>, JsonError> {
    ensure_allowed(consumer.ensure_workspace_plane())?;
    ensure_allowed(consumer.ensure_hpc_read())?;
    let cfg = current_cfg(&state).await;
    let data_dir = FsPath::new(&cfg.storage.data_dir);
    let bundle = collaborative_workbench_bundle_for_workstream(&state, &workstream_id).await?;
    let workspace_snapshot =
        read_workspace_snapshot(data_dir, &bundle.workbench_session.workspace_id)
            .map_err(|error| workstream_control_room_error(&workstream_id, error.to_string()))?
            .ok_or_else(|| {
                not_found_response(
                    "workspace_snapshot_not_found",
                    format!("no workspace snapshot found for workstream {}", workstream_id),
                )
            })?;
    Ok(Json(workspace_snapshot))
}

async fn workstream_source_fingerprint_handler(
    State(state): State<AppState>,
    Extension(consumer): Extension<ConsumerIdentity>,
    Path(workstream_id): Path<String>,
) -> Result<Json<SourceFingerprint>, JsonError> {
    ensure_allowed(consumer.ensure_workspace_plane())?;
    ensure_allowed(consumer.ensure_hpc_read())?;
    let cfg = current_cfg(&state).await;
    let data_dir = FsPath::new(&cfg.storage.data_dir);
    let bundle = collaborative_workbench_bundle_for_workstream(&state, &workstream_id).await?;
    let source_fingerprint =
        read_source_fingerprint(data_dir, &bundle.workbench_session.workspace_id)
            .map_err(|error| workstream_control_room_error(&workstream_id, error.to_string()))?
            .ok_or_else(|| {
                not_found_response(
                    "source_fingerprint_not_found",
                    format!("no source fingerprint found for workstream {}", workstream_id),
                )
            })?;
    Ok(Json(source_fingerprint))
}

async fn workstream_workbench_run_orchestrate_handler(
    State(state): State<AppState>,
    Extension(consumer): Extension<ConsumerIdentity>,
    Path(workstream_id): Path<String>,
    Json(body): Json<WorkbenchRunOrchestrationRequestBody>,
) -> Result<Json<WorkbenchRunOrchestrationBundle>, JsonError> {
    ensure_allowed(consumer.ensure_workspace_plane())?;
    ensure_allowed(consumer.ensure_hpc_submit(&body.compute_profile_id))?;
    let cfg = current_cfg(&state).await;
    let data_dir = FsPath::new(&cfg.storage.data_dir);
    let gateway = gateway_client()?;
    let bridge = tool_bridge_from_cfg(&cfg)?;
    let detail = get_workstream_control_room_detail(data_dir, &cfg, &workstream_id)
        .map_err(|error| workstream_control_room_error(&workstream_id, error.to_string()))?;
    let workbench_bundle = collaborative_workbench_bundle_for_workstream(&state, &workstream_id).await?;
    let response = orchestrate_workbench_run(
        data_dir,
        &cfg,
        &gateway,
        &bridge,
        &detail,
        &workbench_bundle,
        &WorkbenchRunDispatchRequest {
            requested_by: &body.requested_by,
            requester_role_id: &body.requester_role_id,
            selected_subagent_id: &body.selected_subagent_id,
            task_family: &body.task_family,
            intent_text: &body.intent_text,
            compute_profile_id: &body.compute_profile_id,
            run_label: body.run_label.as_deref(),
            recipe_kind: body.recipe_kind.as_deref(),
            experiment_id: body.experiment_id.as_deref(),
            reservation_note: &body.reservation_note,
            dispatch_note: &body.dispatch_note,
            poll_interval_seconds: body.poll_interval_seconds,
            timeout_seconds: body.timeout_seconds,
            code_provenance_capture: body.code_provenance_capture.as_ref(),
        },
    )
    .await
    .map_err(|error| workstream_control_room_error(&workstream_id, error.to_string()))?;
    Ok(Json(response))
}

async fn workstream_workspace_tenancy_handler(
    State(state): State<AppState>,
    Extension(consumer): Extension<ConsumerIdentity>,
    Path(workstream_id): Path<String>,
) -> Result<Json<WorkspaceTenancyContract>, JsonError> {
    ensure_allowed(consumer.ensure_workspace_plane())?;
    ensure_allowed(consumer.ensure_hpc_read())?;
    let bundle = multi_user_gpu_workspace_tenancy_bundle_for_workstream(&state, &workstream_id).await?;
    Ok(Json(bundle.workspace_tenancy))
}

async fn workstream_compute_tenancy_handler(
    State(state): State<AppState>,
    Extension(consumer): Extension<ConsumerIdentity>,
    Path(workstream_id): Path<String>,
) -> Result<Json<ComputeTenancyContract>, JsonError> {
    ensure_allowed(consumer.ensure_workspace_plane())?;
    ensure_allowed(consumer.ensure_hpc_read())?;
    let bundle = multi_user_gpu_workspace_tenancy_bundle_for_workstream(&state, &workstream_id).await?;
    Ok(Json(bundle.compute_tenancy))
}

async fn workstream_partner_access_handler(
    State(state): State<AppState>,
    Extension(consumer): Extension<ConsumerIdentity>,
    Path(workstream_id): Path<String>,
) -> Result<Json<PartnerAccessContract>, JsonError> {
    ensure_allowed(consumer.ensure_workspace_plane())?;
    ensure_allowed(consumer.ensure_hpc_read())?;
    let bundle = multi_user_gpu_workspace_tenancy_bundle_for_workstream(&state, &workstream_id).await?;
    Ok(Json(bundle.partner_access))
}

async fn workstream_workspace_subagents_handler(
    State(state): State<AppState>,
    Extension(consumer): Extension<ConsumerIdentity>,
    Path(workstream_id): Path<String>,
) -> Result<Json<WorkspaceSubAgentsResponse>, JsonError> {
    ensure_allowed(consumer.ensure_workspace_plane())?;
    ensure_allowed(consumer.ensure_hpc_read())?;
    let cfg = current_cfg(&state).await;
    let data_dir = FsPath::new(&cfg.storage.data_dir);
    let gateway = gateway_client()?;

    let context_packet =
        resolve_workstream_context_packet(&state, data_dir, &cfg, &gateway, &workstream_id).await?;

    let response = build_workstream_workspace_subagents(&cfg, &workstream_id, context_packet)
        .map_err(|error| workstream_control_room_error(&workstream_id, error.to_string()))?;

    Ok(Json(response))
}

async fn workstream_workspace_subagent_list_handler(
    State(state): State<AppState>,
    Extension(consumer): Extension<ConsumerIdentity>,
    Path(workstream_id): Path<String>,
) -> Result<Json<WorkspaceSubAgentListResponse>, JsonError> {
    ensure_allowed(consumer.ensure_workspace_plane())?;
    ensure_allowed(consumer.ensure_hpc_read())?;
    let cfg = current_cfg(&state).await;
    let data_dir = FsPath::new(&cfg.storage.data_dir);
    let gateway = gateway_client()?;

    let context_packet =
        resolve_workstream_context_packet(&state, data_dir, &cfg, &gateway, &workstream_id).await?;

    let response = build_workstream_workspace_subagent_list(&cfg, &workstream_id, context_packet)
        .map_err(|error| workstream_control_room_error(&workstream_id, error.to_string()))?;

    Ok(Json(response))
}

async fn workstream_workspace_subagent_route_handler(
    State(state): State<AppState>,
    Extension(consumer): Extension<ConsumerIdentity>,
    Path(workstream_id): Path<String>,
    Query(params): Query<WorkspaceSubAgentRouteQueryParams>,
) -> Result<Json<WorkspaceSubAgentRouteResponse>, JsonError> {
    ensure_allowed(consumer.ensure_workspace_plane())?;
    ensure_allowed(consumer.ensure_hpc_read())?;
    let cfg = current_cfg(&state).await;
    let data_dir = FsPath::new(&cfg.storage.data_dir);
    let gateway = gateway_client()?;

    let mut context_packet =
        resolve_workstream_context_packet(&state, data_dir, &cfg, &gateway, &workstream_id).await?;
    let detail = get_workstream_control_room_detail(data_dir, &cfg, &workstream_id)
        .map_err(|error| workstream_control_room_error(&workstream_id, error.to_string()))?;
    if params.tool_id.is_some() || params.work_mode.is_some() {
        if let Ok(compiled) = resolve_workstream_compiled_context(
            &state,
            &detail,
            None,
            params.tool_id.as_deref(),
            params.work_mode.as_deref(),
            None,
        )
        .await
        {
            apply_compiled_context_to_packet(&mut context_packet.packet, &compiled);
        }
    }
    apply_intent_planner_to_packet(&mut context_packet.packet);

    let request = WorkspaceSubAgentRouteRequest {
        tool_id: params.tool_id.as_deref(),
        work_mode: params.work_mode.as_deref(),
        preferred_subagent: params.preferred_subagent.as_deref(),
    };
    let response = build_workstream_workspace_subagent_route(
        &cfg,
        &workstream_id,
        context_packet,
        request,
    )
    .map_err(|error| workstream_control_room_error(&workstream_id, error.to_string()))?;

    Ok(Json(response))
}

async fn workstream_workspace_subagent_handoff_handler(
    State(state): State<AppState>,
    Extension(consumer): Extension<ConsumerIdentity>,
    Path(workstream_id): Path<String>,
) -> Result<Json<WorkspaceSubAgentHandoffResponse>, JsonError> {
    ensure_allowed(consumer.ensure_workspace_plane())?;
    ensure_allowed(consumer.ensure_hpc_read())?;
    let cfg = current_cfg(&state).await;
    let data_dir = FsPath::new(&cfg.storage.data_dir);
    let gateway = gateway_client()?;

    let context_packet =
        resolve_workstream_context_packet(&state, data_dir, &cfg, &gateway, &workstream_id).await?;

    let response = read_workspace_subagent_handoff(data_dir, &cfg, &workstream_id, context_packet)
        .map_err(|error| workstream_control_room_error(&workstream_id, error.to_string()))?
        .ok_or_else(|| {
            (
                StatusCode::NOT_FOUND,
                Json(json!({
                    "status": "error",
                    "error": "workspace_subagent_handoff_not_found",
                    "message": format!(
                        "no cross-subagent handoff recorded yet for '{}'",
                        workstream_id
                    )
                })),
            )
        })?;

    Ok(Json(response))
}

async fn workstream_workspace_subagent_handoff_record_handler(
    State(state): State<AppState>,
    Extension(consumer): Extension<ConsumerIdentity>,
    Path(workstream_id): Path<String>,
    Json(body): Json<WorkspaceSubAgentHandoffRequestBody>,
) -> Result<Json<WorkspaceSubAgentHandoffResponse>, JsonError> {
    ensure_allowed(consumer.ensure_workspace_plane())?;
    ensure_allowed(consumer.ensure_hpc_read())?;
    let cfg = current_cfg(&state).await;
    let data_dir = FsPath::new(&cfg.storage.data_dir);
    let gateway = gateway_client()?;

    let context_packet =
        resolve_workstream_context_packet(&state, data_dir, &cfg, &gateway, &workstream_id).await?;

    let response = record_workspace_subagent_handoff(
        data_dir,
        &cfg,
        &workstream_id,
        context_packet,
        WorkspaceSubAgentHandoffRequest {
            source_subagent_id: &body.source_subagent_id,
            target_subagent_id: &body.target_subagent_id,
            requested_work_mode: body.requested_work_mode.as_deref(),
            requested_tool_id: body.requested_tool_id.as_deref(),
            intent: &body.intent,
            summary: &body.summary,
        },
    )
    .map_err(|error| workstream_control_room_error(&workstream_id, error.to_string()))?;

    Ok(Json(response))
}

async fn workstream_workspace_manuscript_handoff_handler(
    State(state): State<AppState>,
    Extension(consumer): Extension<ConsumerIdentity>,
    Path(workstream_id): Path<String>,
) -> Result<Json<WorkspaceManuscriptHandoffResponse>, JsonError> {
    ensure_allowed(consumer.ensure_workspace_plane())?;
    ensure_allowed(consumer.ensure_hpc_read())?;
    let cfg = current_cfg(&state).await;
    let data_dir = FsPath::new(&cfg.storage.data_dir);
    let gateway = gateway_client()?;

    let context_packet =
        resolve_workstream_context_packet(&state, data_dir, &cfg, &gateway, &workstream_id).await?;

    let response =
        read_workspace_manuscript_handoff(data_dir, &cfg, &workstream_id, context_packet)
            .map_err(|error| workstream_control_room_error(&workstream_id, error.to_string()))?
            .ok_or_else(|| {
                (
                    StatusCode::NOT_FOUND,
                    Json(json!({
                        "status": "error",
                        "error": "workspace_manuscript_handoff_not_found",
                        "message": format!(
                            "no manuscript handoff recorded yet for '{}'",
                            workstream_id
                        )
                    })),
                )
            })?;

    Ok(Json(response))
}

async fn workstream_workspace_manuscript_handoff_record_handler(
    State(state): State<AppState>,
    Extension(consumer): Extension<ConsumerIdentity>,
    Path(workstream_id): Path<String>,
    Json(body): Json<WorkspaceManuscriptHandoffRequestBody>,
) -> Result<Json<WorkspaceManuscriptHandoffResponse>, JsonError> {
    ensure_allowed(consumer.ensure_workspace_plane())?;
    ensure_allowed(consumer.ensure_hpc_read())?;
    let cfg = current_cfg(&state).await;
    let data_dir = FsPath::new(&cfg.storage.data_dir);
    let gateway = gateway_client()?;

    let context_packet =
        resolve_workstream_context_packet(&state, data_dir, &cfg, &gateway, &workstream_id).await?;

    let response = record_workspace_manuscript_handoff(
        data_dir,
        &cfg,
        &workstream_id,
        context_packet,
        WorkspaceManuscriptHandoffRequest {
            source_subagent_id: &body.source_subagent_id,
            requested_work_mode: body.requested_work_mode.as_deref(),
            requested_tool_id: body.requested_tool_id.as_deref(),
            intent: &body.intent,
            summary: &body.summary,
            manuscript_goal: &body.manuscript_goal,
        },
    )
    .map_err(|error| workstream_control_room_error(&workstream_id, error.to_string()))?;

    Ok(Json(response))
}

async fn workstream_workspace_manuscript_assembly_handler(
    State(state): State<AppState>,
    Extension(consumer): Extension<ConsumerIdentity>,
    Path(workstream_id): Path<String>,
) -> Result<Json<WorkspaceManuscriptAssemblyResponse>, JsonError> {
    ensure_allowed(consumer.ensure_workspace_plane())?;
    ensure_allowed(consumer.ensure_hpc_read())?;
    let cfg = current_cfg(&state).await;
    let data_dir = FsPath::new(&cfg.storage.data_dir);
    let gateway = gateway_client()?;

    let context_packet =
        resolve_workstream_context_packet(&state, data_dir, &cfg, &gateway, &workstream_id).await?;

    let response =
        read_workspace_manuscript_assembly(data_dir, &cfg, &workstream_id, context_packet)
            .map_err(|error| workstream_control_room_error(&workstream_id, error.to_string()))?
            .ok_or_else(|| {
                (
                    StatusCode::NOT_FOUND,
                    Json(json!({
                        "status": "error",
                        "error": "workspace_manuscript_assembly_not_found",
                        "message": format!(
                            "no manuscript assembly recorded yet for '{}'",
                            workstream_id
                        )
                    })),
                )
            })?;

    Ok(Json(response))
}

async fn workstream_workspace_manuscript_assembly_record_handler(
    State(state): State<AppState>,
    Extension(consumer): Extension<ConsumerIdentity>,
    Path(workstream_id): Path<String>,
    Json(body): Json<WorkspaceManuscriptAssemblyRequestBody>,
) -> Result<Json<WorkspaceManuscriptAssemblyResponse>, JsonError> {
    ensure_allowed(consumer.ensure_workspace_plane())?;
    ensure_allowed(consumer.ensure_hpc_read())?;
    let cfg = current_cfg(&state).await;
    let data_dir = FsPath::new(&cfg.storage.data_dir);
    let gateway = gateway_client()?;

    let context_packet =
        resolve_workstream_context_packet(&state, data_dir, &cfg, &gateway, &workstream_id).await?;

    let response = record_workspace_manuscript_assembly(
        data_dir,
        &cfg,
        &workstream_id,
        context_packet,
        WorkspaceManuscriptAssemblyRequest {
            source_subagent_id: &body.source_subagent_id,
            requested_tool_id: body.requested_tool_id.as_deref(),
            section_profile: body.section_profile.as_deref(),
            intent: &body.intent,
            summary: &body.summary,
            assembly_goal: &body.assembly_goal,
        },
    )
    .map_err(|error| workstream_control_room_error(&workstream_id, error.to_string()))?;

    Ok(Json(response))
}

async fn workstream_workspace_scholarly_release_handler(
    State(state): State<AppState>,
    Extension(consumer): Extension<ConsumerIdentity>,
    Path(workstream_id): Path<String>,
) -> Result<Json<WorkspaceScholarlyReleaseResponse>, JsonError> {
    ensure_allowed(consumer.ensure_workspace_plane())?;
    ensure_allowed(consumer.ensure_hpc_read())?;
    let cfg = current_cfg(&state).await;
    let data_dir = FsPath::new(&cfg.storage.data_dir);
    let gateway = gateway_client()?;

    let context_packet =
        resolve_workstream_context_packet(&state, data_dir, &cfg, &gateway, &workstream_id).await?;

    let response =
        read_workspace_scholarly_release(data_dir, &cfg, &workstream_id, context_packet)
            .map_err(|error| workstream_control_room_error(&workstream_id, error.to_string()))?
            .ok_or_else(|| {
                (
                    StatusCode::NOT_FOUND,
                    Json(json!({
                        "status": "error",
                        "error": "workspace_scholarly_release_not_found",
                        "message": format!(
                            "no scholarly release recorded yet for '{}'",
                            workstream_id
                        )
                    })),
                )
            })?;

    Ok(Json(response))
}

async fn workstream_workspace_scholarly_release_record_handler(
    State(state): State<AppState>,
    Extension(consumer): Extension<ConsumerIdentity>,
    Path(workstream_id): Path<String>,
    Json(body): Json<WorkspaceScholarlyReleaseRequestBody>,
) -> Result<Json<WorkspaceScholarlyReleaseResponse>, JsonError> {
    ensure_allowed(consumer.ensure_workspace_plane())?;
    ensure_allowed(consumer.ensure_hpc_read())?;
    let cfg = current_cfg(&state).await;
    let data_dir = FsPath::new(&cfg.storage.data_dir);
    let gateway = gateway_client()?;

    let context_packet =
        resolve_workstream_context_packet(&state, data_dir, &cfg, &gateway, &workstream_id).await?;

    let response = record_workspace_scholarly_release(
        data_dir,
        &cfg,
        &workstream_id,
        context_packet,
        WorkspaceScholarlyReleaseRequest {
            source_subagent_id: &body.source_subagent_id,
            requested_tool_id: body.requested_tool_id.as_deref(),
            release_goal: &body.release_goal,
            summary: &body.summary,
            release_notes: &body.release_notes,
        },
    )
    .map_err(|error| workstream_control_room_error(&workstream_id, error.to_string()))?;

    Ok(Json(response))
}

async fn workstream_workspace_publication_package_handler(
    State(state): State<AppState>,
    Extension(consumer): Extension<ConsumerIdentity>,
    Path(workstream_id): Path<String>,
) -> Result<Json<WorkspacePublicationPackageResponse>, JsonError> {
    ensure_allowed(consumer.ensure_workspace_plane())?;
    ensure_allowed(consumer.ensure_hpc_read())?;
    let cfg = current_cfg(&state).await;
    let data_dir = FsPath::new(&cfg.storage.data_dir);
    let gateway = gateway_client()?;

    let context_packet =
        resolve_workstream_context_packet(&state, data_dir, &cfg, &gateway, &workstream_id).await?;

    let response =
        read_workspace_publication_package(data_dir, &cfg, &workstream_id, context_packet)
            .map_err(|error| workstream_control_room_error(&workstream_id, error.to_string()))?
            .ok_or_else(|| {
                (
                    StatusCode::NOT_FOUND,
                    Json(json!({
                        "status": "error",
                        "error": "workspace_publication_package_not_found",
                        "message": format!(
                            "no publication package recorded yet for '{}'",
                            workstream_id
                        )
                    })),
                )
            })?;

    Ok(Json(response))
}

async fn workstream_workspace_publication_package_record_handler(
    State(state): State<AppState>,
    Extension(consumer): Extension<ConsumerIdentity>,
    Path(workstream_id): Path<String>,
    Json(body): Json<WorkspacePublicationPackageRequestBody>,
) -> Result<Json<WorkspacePublicationPackageResponse>, JsonError> {
    ensure_allowed(consumer.ensure_workspace_plane())?;
    ensure_allowed(consumer.ensure_hpc_read())?;
    let cfg = current_cfg(&state).await;
    let data_dir = FsPath::new(&cfg.storage.data_dir);
    let gateway = gateway_client()?;

    let context_packet =
        resolve_workstream_context_packet(&state, data_dir, &cfg, &gateway, &workstream_id).await?;

    let response = record_workspace_publication_package(
        data_dir,
        &cfg,
        &workstream_id,
        context_packet,
        WorkspacePublicationPackageRequest {
            source_subagent_id: &body.source_subagent_id,
            requested_tool_id: body.requested_tool_id.as_deref(),
            publication_goal: &body.publication_goal,
            summary: &body.summary,
            staging_notes: &body.staging_notes,
        },
    )
    .map_err(|error| workstream_control_room_error(&workstream_id, error.to_string()))?;

    Ok(Json(response))
}

async fn workstream_workspace_external_staging_handler(
    State(state): State<AppState>,
    Extension(consumer): Extension<ConsumerIdentity>,
    Path(workstream_id): Path<String>,
) -> Result<Json<WorkspaceExternalRegistryStagingResponse>, JsonError> {
    ensure_allowed(consumer.ensure_workspace_plane())?;
    ensure_allowed(consumer.ensure_hpc_read())?;
    let cfg = current_cfg(&state).await;
    let data_dir = FsPath::new(&cfg.storage.data_dir);
    let gateway = gateway_client()?;

    let context_packet =
        resolve_workstream_context_packet(&state, data_dir, &cfg, &gateway, &workstream_id).await?;

    let response =
        read_workspace_external_registry_staging(data_dir, &cfg, &workstream_id, context_packet)
            .map_err(|error| workstream_control_room_error(&workstream_id, error.to_string()))?
            .ok_or_else(|| {
                (
                    StatusCode::NOT_FOUND,
                    Json(json!({
                        "status": "error",
                        "error": "workspace_external_staging_not_found",
                        "message": format!(
                            "no external registry staging recorded yet for '{}'",
                            workstream_id
                        )
                    })),
                )
            })?;

    Ok(Json(response))
}

async fn workstream_workspace_external_staging_record_handler(
    State(state): State<AppState>,
    Extension(consumer): Extension<ConsumerIdentity>,
    Path(workstream_id): Path<String>,
    Json(body): Json<WorkspaceExternalRegistryStagingRequestBody>,
) -> Result<Json<WorkspaceExternalRegistryStagingResponse>, JsonError> {
    ensure_allowed(consumer.ensure_workspace_plane())?;
    ensure_allowed(consumer.ensure_hpc_read())?;
    let cfg = current_cfg(&state).await;
    let data_dir = FsPath::new(&cfg.storage.data_dir);
    let gateway = gateway_client()?;

    let context_packet =
        resolve_workstream_context_packet(&state, data_dir, &cfg, &gateway, &workstream_id).await?;

    let response = record_workspace_external_registry_staging(
        data_dir,
        &cfg,
        &workstream_id,
        context_packet,
        WorkspaceExternalRegistryStagingRequest {
            source_subagent_id: &body.source_subagent_id,
            requested_tool_id: body.requested_tool_id.as_deref(),
            staging_goal: &body.staging_goal,
            summary: &body.summary,
            dry_run_notes: &body.dry_run_notes,
        },
    )
    .map_err(|error| workstream_control_room_error(&workstream_id, error.to_string()))?;

    Ok(Json(response))
}

async fn workstream_workspace_sandbox_deposit_handler(
    State(state): State<AppState>,
    Extension(consumer): Extension<ConsumerIdentity>,
    Path(workstream_id): Path<String>,
) -> Result<Json<WorkspaceSandboxDepositHandshakeResponse>, JsonError> {
    ensure_allowed(consumer.ensure_workspace_plane())?;
    ensure_allowed(consumer.ensure_hpc_read())?;
    let cfg = current_cfg(&state).await;
    let data_dir = FsPath::new(&cfg.storage.data_dir);
    let gateway = gateway_client()?;

    let context_packet =
        resolve_workstream_context_packet(&state, data_dir, &cfg, &gateway, &workstream_id).await?;

    let response = read_workspace_sandbox_deposit_handshake(
        data_dir,
        &cfg,
        &workstream_id,
        context_packet,
    )
    .map_err(|error| workstream_control_room_error(&workstream_id, error.to_string()))?
    .ok_or_else(|| {
        (
            StatusCode::NOT_FOUND,
            Json(json!({
                "status": "error",
                "error": "workspace_sandbox_deposit_not_found",
                "message": format!(
                    "no sandbox deposit handshake recorded yet for '{}'",
                    workstream_id
                )
            })),
        )
    })?;

    Ok(Json(response))
}

async fn workstream_workspace_sandbox_deposit_record_handler(
    State(state): State<AppState>,
    Extension(consumer): Extension<ConsumerIdentity>,
    Path(workstream_id): Path<String>,
    Json(body): Json<WorkspaceSandboxDepositHandshakeRequestBody>,
) -> Result<Json<WorkspaceSandboxDepositHandshakeResponse>, JsonError> {
    ensure_allowed(consumer.ensure_workspace_plane())?;
    ensure_allowed(consumer.ensure_hpc_read())?;
    let cfg = current_cfg(&state).await;
    let data_dir = FsPath::new(&cfg.storage.data_dir);
    let gateway = gateway_client()?;

    let context_packet =
        resolve_workstream_context_packet(&state, data_dir, &cfg, &gateway, &workstream_id).await?;

    let response = record_workspace_sandbox_deposit_handshake(
        data_dir,
        &cfg,
        &workstream_id,
        context_packet,
        WorkspaceSandboxDepositHandshakeRequest {
            source_subagent_id: &body.source_subagent_id,
            requested_tool_id: body.requested_tool_id.as_deref(),
            handshake_goal: &body.handshake_goal,
            summary: &body.summary,
            handshake_notes: &body.handshake_notes,
        },
    )
    .map_err(|error| workstream_control_room_error(&workstream_id, error.to_string()))?;

    Ok(Json(response))
}

async fn workstream_tool_return_handler(
    State(state): State<AppState>,
    Extension(consumer): Extension<ConsumerIdentity>,
    Path(workstream_id): Path<String>,
    Json(payload): Json<WorkstreamToolReturnPayload>,
) -> Result<Json<WorkstreamToolReturnResponse>, JsonError> {
    ensure_allowed(consumer.ensure_workspace_plane())?;
    let cfg = current_cfg(&state).await;
    let data_dir = FsPath::new(&cfg.storage.data_dir);
    let gateway = gateway_client()?;
    let context_packet =
        resolve_workstream_context_packet(&state, data_dir, &cfg, &gateway, &workstream_id).await?;
    let memory_id = ingest_workstream_tool_return_memory(&state, &context_packet, &payload).await?;

    let response = apply_workstream_tool_return(
        data_dir,
        &cfg,
        &workstream_id,
        &payload,
        memory_id,
    )
    .map_err(|error| workstream_tool_return_error(&workstream_id, error.to_string()))?;

    Ok(Json(response))
}

async fn workstream_control_room_recipes_handler(
    Extension(consumer): Extension<ConsumerIdentity>,
    Path(workstream_id): Path<String>,
) -> Result<Json<WorkstreamControlRoomRecipeSetResponse>, JsonError> {
    ensure_allowed(consumer.ensure_workspace_plane())?;

    let response = get_workstream_control_room_recipes(&workstream_id)
        .map_err(|error| workstream_control_room_error(&workstream_id, error.to_string()))?;

    Ok(Json(response))
}

async fn workstream_control_room_status_handler(
    State(state): State<AppState>,
    Extension(consumer): Extension<ConsumerIdentity>,
    Path(workstream_id): Path<String>,
) -> Result<Json<WorkstreamControlRoomStatusResponse>, JsonError> {
    ensure_allowed(consumer.ensure_workspace_plane())?;
    let cfg = current_cfg(&state).await;
    let data_dir = FsPath::new(&cfg.storage.data_dir);

    let response = get_workstream_control_room_status(data_dir, &cfg, &workstream_id)
        .map_err(|error| workstream_control_room_error(&workstream_id, error.to_string()))?;

    Ok(Json(response))
}

async fn workstream_cockpit_page_handler(
    State(state): State<AppState>,
    Extension(consumer): Extension<ConsumerIdentity>,
    Path(workstream_id): Path<String>,
) -> Result<Html<String>, JsonError> {
    ensure_allowed(consumer.ensure_workspace_plane())?;
    ensure_allowed(consumer.ensure_hpc_read())?;
    let cfg = current_cfg(&state).await;
    let data_dir = FsPath::new(&cfg.storage.data_dir);
    let gateway = gateway_client()?;
    let context_packet =
        resolve_workstream_context_packet(&state, data_dir, &cfg, &gateway, &workstream_id).await?;

    let response = get_workstream_cockpit_with_context_packet(
        data_dir,
        &cfg,
        &gateway,
        &workstream_id,
        context_packet,
    )
        .await
        .map_err(|error| workstream_control_room_error(&workstream_id, error.to_string()))?;

    Ok(Html(render_workstream_cockpit_page(&response)))
}

async fn workstream_control_room_last_result_handler(
    State(state): State<AppState>,
    Extension(consumer): Extension<ConsumerIdentity>,
    Path(workstream_id): Path<String>,
) -> Result<Json<WorkstreamControlRoomLastResultResponse>, JsonError> {
    ensure_allowed(consumer.ensure_workspace_plane())?;
    ensure_allowed(consumer.ensure_hpc_read())?;
    let cfg = current_cfg(&state).await;
    let data_dir = FsPath::new(&cfg.storage.data_dir);
    let gateway = gateway_client()?;

    let response =
        get_workstream_control_room_last_result(data_dir, &cfg, &gateway, &workstream_id)
            .await
            .map_err(|error| {
                workstream_control_room_error(&workstream_id, error.to_string())
            })?;

    Ok(Json(response))
}

async fn workstream_control_room_handoff_handler(
    State(state): State<AppState>,
    Extension(consumer): Extension<ConsumerIdentity>,
    Path(workstream_id): Path<String>,
) -> Result<Json<WorkstreamControlRoomHandoffResponse>, JsonError> {
    ensure_allowed(consumer.ensure_workspace_plane())?;
    let cfg = current_cfg(&state).await;
    let data_dir = FsPath::new(&cfg.storage.data_dir);

    let response = get_workstream_control_room_handoff(data_dir, &cfg, &workstream_id)
        .map_err(|error| workstream_control_room_error(&workstream_id, error.to_string()))?;

    Ok(Json(response))
}

async fn workstream_timeline_handler(
    State(state): State<AppState>,
    Extension(consumer): Extension<ConsumerIdentity>,
    Path(workstream_id): Path<String>,
    Query(query): Query<TimelineQueryParams>,
) -> Result<Json<WorkstreamTimelineResponse>, JsonError> {
    ensure_allowed(consumer.ensure_workspace_plane())?;
    let cfg = current_cfg(&state).await;
    let data_dir = FsPath::new(&cfg.storage.data_dir);

    let response = get_workstream_timeline(data_dir, &cfg, &workstream_id, query.limit)
        .map_err(|error| workstream_timeline_error(&workstream_id, error.to_string()))?;

    Ok(Json(response))
}

async fn workstream_timeline_event_handler(
    State(state): State<AppState>,
    Extension(consumer): Extension<ConsumerIdentity>,
    Path((workstream_id, event_id)): Path<(String, String)>,
) -> Result<Json<WorkstreamTimelineEventDetailResponse>, JsonError> {
    ensure_allowed(consumer.ensure_workspace_plane())?;
    let cfg = current_cfg(&state).await;
    let data_dir = FsPath::new(&cfg.storage.data_dir);

    let response = get_workstream_timeline_event(data_dir, &cfg, &workstream_id, &event_id)
        .map_err(|error| workstream_timeline_error(&workstream_id, error.to_string()))?;

    Ok(Json(response))
}

async fn workstream_control_room_hold_handler(
    State(state): State<AppState>,
    Extension(consumer): Extension<ConsumerIdentity>,
    Path(workstream_id): Path<String>,
) -> Result<Json<WorkstreamControlRoomActionResponse>, JsonError> {
    ensure_allowed(consumer.ensure_workspace_plane())?;
    let cfg = current_cfg(&state).await;
    let data_dir = FsPath::new(&cfg.storage.data_dir);

    let response = run_workstream_control_room_action(data_dir, &cfg, &workstream_id, "hold")
        .map_err(|error| workstream_control_room_action_error(&workstream_id, error.to_string()))?;

    Ok(Json(response))
}

async fn workstream_control_room_resume_handler(
    State(state): State<AppState>,
    Extension(consumer): Extension<ConsumerIdentity>,
    Path(workstream_id): Path<String>,
) -> Result<Json<WorkstreamControlRoomActionResponse>, JsonError> {
    ensure_allowed(consumer.ensure_workspace_plane())?;
    let cfg = current_cfg(&state).await;
    let data_dir = FsPath::new(&cfg.storage.data_dir);

    let response = run_workstream_control_room_action(data_dir, &cfg, &workstream_id, "resume")
        .map_err(|error| workstream_control_room_action_error(&workstream_id, error.to_string()))?;

    Ok(Json(response))
}

async fn consumer_self_handler(
    Extension(consumer): Extension<ConsumerIdentity>,
) -> Json<ConsumerIdentity> {
    Json(consumer)
}

async fn hpc_control_handler(
    State(state): State<AppState>,
    Extension(consumer): Extension<ConsumerIdentity>,
) -> Result<Json<HpcControlSurfaceSummary>, JsonError> {
    ensure_allowed(consumer.ensure_hpc_control())?;
    let cfg = current_cfg(&state).await;
    let data_dir = FsPath::new(&cfg.storage.data_dir);

    let gateway = gateway_client()?;
    let bridge = tool_bridge_from_cfg(&cfg)?;

    let profiles = gateway
        .profiles()
        .await
        .map_err(gateway_error_response)?
        .profiles;

    let results = gateway
        .results(&ResultCatalogQuery::default())
        .await
        .map_err(gateway_error_response)?;

    let recent_bridge_ledger = read_recent_ledger_entries(data_dir, 10).map_err(|error| {
        internal_error_response("bridge_ledger_read_failed", error.to_string())
    })?;

    Ok(Json(HpcControlSurfaceSummary {
        status: "ok".to_string(),
        gateway_base_url: gateway.base_url().to_string(),
        profiles,
        recent_results: results.results.into_iter().take(5).collect(),
        bridge_health: bridge.health(),
        bridge_providers: bridge.providers(),
        recent_bridge_ledger,
    }))
}

async fn hpc_profiles_handler(
    State(_state): State<AppState>,
    Extension(consumer): Extension<ConsumerIdentity>,
) -> Result<Json<HpcProfileCatalog>, JsonError> {
    ensure_allowed(consumer.ensure_hpc_read())?;
    let gateway = gateway_client()?;
    gateway
        .profiles()
        .await
        .map(Json)
        .map_err(gateway_error_response)
}

async fn hpc_job_submit_handler(
    State(_state): State<AppState>,
    Extension(consumer): Extension<ConsumerIdentity>,
    Json(request): Json<HpcSubmitRequest>,
) -> Result<Json<HpcSubmitResponse>, JsonError> {
    ensure_allowed(consumer.ensure_hpc_submit(&request.profile_id))?;
    let gateway = gateway_client()?;
    gateway
        .submit_job(&request)
        .await
        .map(Json)
        .map_err(gateway_error_response)
}

async fn hpc_job_status_handler(
    State(_state): State<AppState>,
    Extension(consumer): Extension<ConsumerIdentity>,
    Path(job_id): Path<u64>,
) -> Result<Json<HpcJobStatus>, JsonError> {
    ensure_allowed(consumer.ensure_hpc_read())?;
    let gateway = gateway_client()?;
    gateway
        .job_status(job_id)
        .await
        .map(Json)
        .map_err(gateway_error_response)
}

async fn hpc_job_manifest_handler(
    State(_state): State<AppState>,
    Extension(consumer): Extension<ConsumerIdentity>,
    Path(job_id): Path<u64>,
) -> Result<Json<JobArtifactManifest>, JsonError> {
    ensure_allowed(consumer.ensure_hpc_read())?;
    let gateway = gateway_client()?;
    gateway
        .job_artifact_manifest(job_id)
        .await
        .map(Json)
        .map_err(gateway_error_response)
}

async fn hpc_job_stdout_handler(
    State(_state): State<AppState>,
    Extension(consumer): Extension<ConsumerIdentity>,
    Path(job_id): Path<u64>,
) -> Result<Json<HpcTextArtifact>, JsonError> {
    ensure_allowed(consumer.ensure_hpc_read())?;
    let gateway = gateway_client()?;
    gateway
        .job_stdout(job_id)
        .await
        .map(Json)
        .map_err(gateway_error_response)
}

async fn hpc_job_stderr_handler(
    State(_state): State<AppState>,
    Extension(consumer): Extension<ConsumerIdentity>,
    Path(job_id): Path<u64>,
) -> Result<Json<HpcTextArtifact>, JsonError> {
    ensure_allowed(consumer.ensure_hpc_read())?;
    let gateway = gateway_client()?;
    gateway
        .job_stderr(job_id)
        .await
        .map(Json)
        .map_err(gateway_error_response)
}

async fn hpc_results_handler(
    State(_state): State<AppState>,
    Extension(consumer): Extension<ConsumerIdentity>,
    Query(query): Query<ResultsQueryParams>,
) -> Result<Json<ResultCatalogResponse>, JsonError> {
    ensure_allowed(consumer.ensure_hpc_read())?;
    let gateway = gateway_client()?;
    let query = ResultCatalogQuery {
        profile_id: query.profile_id,
        run_label: query.run_label,
        state: query.state,
        node_list: query.node_list,
    };

    gateway
        .results(&query)
        .await
        .map(Json)
        .map_err(gateway_error_response)
}

async fn hpc_result_lookup_handler(
    State(_state): State<AppState>,
    Extension(consumer): Extension<ConsumerIdentity>,
    Path(job_id): Path<u64>,
) -> Result<Json<ResultCatalogEntry>, JsonError> {
    ensure_allowed(consumer.ensure_hpc_read())?;
    let gateway = gateway_client()?;
    gateway
        .result_by_job(job_id)
        .await
        .map(Json)
        .map_err(gateway_error_response)
}

async fn hpc_result_manifest_handler(
    State(_state): State<AppState>,
    Extension(consumer): Extension<ConsumerIdentity>,
    Path(job_id): Path<u64>,
) -> Result<Json<ObjectResultManifest>, JsonError> {
    ensure_allowed(consumer.ensure_hpc_read())?;
    let gateway = gateway_client()?;
    gateway
        .result_manifest(job_id)
        .await
        .map(Json)
        .map_err(gateway_error_response)
}

async fn bridge_health_handler(
    State(state): State<AppState>,
    Extension(consumer): Extension<ConsumerIdentity>,
) -> Result<Json<BridgeHealth>, JsonError> {
    ensure_allowed(consumer.ensure_bridge_read())?;
    let cfg = current_cfg(&state).await;

    match ToolBridge::from_config(&cfg) {
        Ok(bridge) => Ok(Json(bridge.health())),
        Err(error) => {
            error!("failed to initialize tool bridge for health: {}", error);
            Ok(Json(BridgeHealth {
                status: "error".to_string(),
                safe_mode: cfg.safe_mode,
                dry_run: cfg.tool_bridge.dry_run,
                ledger_enabled: cfg.tool_bridge.ledger_enabled,
                data_dir: cfg.storage.data_dir,
                implemented_providers: 0,
                configured_providers: 0,
            }))
        }
    }
}

async fn bridge_providers_handler(
    State(state): State<AppState>,
    Extension(consumer): Extension<ConsumerIdentity>,
) -> Result<Json<Vec<BridgeProviderInfo>>, JsonError> {
    ensure_allowed(consumer.ensure_bridge_read())?;
    let cfg = current_cfg(&state).await;

    match ToolBridge::from_config(&cfg) {
        Ok(bridge) => Ok(Json(bridge.providers())),
        Err(error) => {
            error!("failed to initialize tool bridge for providers: {}", error);
            Ok(Json(Vec::new()))
        }
    }
}

async fn bridge_execute_handler(
    State(state): State<AppState>,
    Extension(consumer): Extension<ConsumerIdentity>,
    Json(request): Json<BridgeRequest>,
) -> Result<Json<BridgeResponse>, JsonError> {
    ensure_allowed(consumer.ensure_bridge_execute())?;
    let cfg = current_cfg(&state).await;

    match ToolBridge::from_config(&cfg) {
        Ok(bridge) => Ok(Json(bridge.execute(request).await)),
        Err(error) => {
            error!("failed to initialize tool bridge for execute: {}", error);
            Ok(Json(BridgeResponse {
                request_id: request.request_id,
                provider: request.provider,
                model: request.model,
                status: BridgeStatus::Error,
                latency_ms: 0,
                token_usage: None,
                estimated_cost_usd: None,
                output: json!({}),
                error: Some(format!("tool bridge init failed: {}", error)),
                warnings: vec![],
            }))
        }
    }
}

async fn resolve_program_context_packet(
    state: &AppState,
    data_dir: &FsPath,
    cfg: &beagle_config::BeagleConfig,
    gateway: &DarwinHpcGatewayClient,
    program_id: &str,
) -> Result<ProgramContextPacketResponse, JsonError> {
    let binding = resolve_program_context_binding(program_id)
        .map_err(|error| not_found_response("program_context_not_found", error.to_string()))?;
    let workstream_packets =
        resolve_bound_workstream_context_packets(state, data_dir, cfg, gateway, &binding.campaign)
            .await?;

    build_program_context_packet(&binding, &workstream_packets)
        .map_err(|error| internal_error_response("program_context_packet_failed", error.to_string()))
}

async fn resolve_campaign_context_packet(
    state: &AppState,
    data_dir: &FsPath,
    cfg: &beagle_config::BeagleConfig,
    gateway: &DarwinHpcGatewayClient,
    campaign_id: &str,
) -> Result<ProgramContextPacketResponse, JsonError> {
    let binding = resolve_campaign_context_binding(campaign_id)
        .map_err(|error| not_found_response("campaign_context_not_found", error.to_string()))?;
    let workstream_packets =
        resolve_bound_workstream_context_packets(state, data_dir, cfg, gateway, &binding.campaign)
            .await?;

    build_program_context_packet(&binding, &workstream_packets)
        .map_err(|error| internal_error_response("campaign_context_packet_failed", error.to_string()))
}

async fn resolve_campaign_evidence_pack(
    state: &AppState,
    data_dir: &FsPath,
    cfg: &beagle_config::BeagleConfig,
    gateway: &DarwinHpcGatewayClient,
    campaign_id: &str,
) -> Result<EvidencePackResponse, JsonError> {
    let (_, _, evidence_pack) =
        resolve_campaign_runtime_bundle(state, data_dir, cfg, gateway, campaign_id).await?;

    Ok(evidence_pack)
}

async fn resolve_campaign_claims(
    state: &AppState,
    data_dir: &FsPath,
    cfg: &beagle_config::BeagleConfig,
    gateway: &DarwinHpcGatewayClient,
    campaign_id: &str,
) -> Result<CampaignClaimsResponse, JsonError> {
    let (binding, context_packet, evidence_pack) =
        resolve_campaign_runtime_bundle(state, data_dir, cfg, gateway, campaign_id).await?;

    build_campaign_claims(&binding, &context_packet.packet, &evidence_pack)
        .map_err(|error| internal_error_response("campaign_claims_failed", error.to_string()))
}

async fn resolve_campaign_manuscript_pack(
    state: &AppState,
    data_dir: &FsPath,
    cfg: &beagle_config::BeagleConfig,
    gateway: &DarwinHpcGatewayClient,
    campaign_id: &str,
) -> Result<ManuscriptPackResponse, JsonError> {
    let (binding, context_packet, evidence_pack) =
        resolve_campaign_runtime_bundle(state, data_dir, cfg, gateway, campaign_id).await?;

    build_campaign_manuscript_pack(&binding, &context_packet.packet, &evidence_pack)
        .map_err(|error| internal_error_response("campaign_manuscript_pack_failed", error.to_string()))
}

async fn resolve_campaign_review_bundle(
    state: &AppState,
    data_dir: &FsPath,
    cfg: &beagle_config::BeagleConfig,
    gateway: &DarwinHpcGatewayClient,
    campaign_id: &str,
) -> Result<ReviewBundleResponse, JsonError> {
    let (binding, context_packet, evidence_pack) =
        resolve_campaign_runtime_bundle(state, data_dir, cfg, gateway, campaign_id).await?;
    let claims = build_campaign_claims(&binding, &context_packet.packet, &evidence_pack)
        .map_err(|error| internal_error_response("campaign_claims_failed", error.to_string()))?;
    let manuscript = build_campaign_manuscript_pack(&binding, &context_packet.packet, &evidence_pack)
        .map_err(|error| internal_error_response("campaign_manuscript_pack_failed", error.to_string()))?;

    build_campaign_review_bundle(
        &binding,
        &context_packet.packet,
        &evidence_pack,
        &claims,
        &manuscript,
    )
    .map_err(|error| internal_error_response("campaign_review_bundle_failed", error.to_string()))
}

async fn resolve_campaign_jats_manuscript_pack(
    state: &AppState,
    data_dir: &FsPath,
    cfg: &beagle_config::BeagleConfig,
    gateway: &DarwinHpcGatewayClient,
    campaign_id: &str,
) -> Result<JatsManuscriptPackResponse, JsonError> {
    let (binding, context_packet, evidence_pack) =
        resolve_campaign_runtime_bundle(state, data_dir, cfg, gateway, campaign_id).await?;
    let claims = build_campaign_claims(&binding, &context_packet.packet, &evidence_pack)
        .map_err(|error| internal_error_response("campaign_claims_failed", error.to_string()))?;
    let manuscript = build_campaign_manuscript_pack(&binding, &context_packet.packet, &evidence_pack)
        .map_err(|error| internal_error_response("campaign_manuscript_pack_failed", error.to_string()))?;
    let review_bundle = build_campaign_review_bundle(
        &binding,
        &context_packet.packet,
        &evidence_pack,
        &claims,
        &manuscript,
    )
    .map_err(|error| internal_error_response("campaign_review_bundle_failed", error.to_string()))?;

    build_campaign_jats_manuscript_pack(
        &binding,
        &context_packet.packet,
        &evidence_pack,
        &claims,
        &manuscript,
        &review_bundle,
    )
    .map_err(|error| {
        internal_error_response("campaign_jats_manuscript_pack_failed", error.to_string())
    })
}

async fn resolve_campaign_runtime_bundle(
    state: &AppState,
    data_dir: &FsPath,
    cfg: &beagle_config::BeagleConfig,
    gateway: &DarwinHpcGatewayClient,
    campaign_id: &str,
) -> Result<
    (
        beagle_darwin::ProgramCampaignBinding,
        ProgramContextPacketResponse,
        EvidencePackResponse,
    ),
    JsonError,
> {
    let binding = resolve_campaign_context_binding(campaign_id)
        .map_err(|error| not_found_response("campaign_context_not_found", error.to_string()))?;
    let workstream_packets =
        resolve_bound_workstream_context_packets(state, data_dir, cfg, gateway, &binding.campaign)
            .await?;
    let context_packet = build_program_context_packet(&binding, &workstream_packets).map_err(
        |error| internal_error_response("campaign_context_packet_failed", error.to_string()),
    )?;
    let evidence_pack = build_campaign_evidence_pack(&binding, &context_packet.packet)
        .map_err(|error| internal_error_response("campaign_evidence_pack_failed", error.to_string()))
        ?;

    Ok((binding, context_packet, evidence_pack))
}

async fn resolve_bound_workstream_context_packets(
    state: &AppState,
    data_dir: &FsPath,
    cfg: &beagle_config::BeagleConfig,
    gateway: &DarwinHpcGatewayClient,
    campaign: &beagle_darwin::CampaignDocument,
) -> Result<Vec<beagle_darwin::WorkstreamContextPacket>, JsonError> {
    let mut packets = Vec::new();

    for workstream in &campaign.workstreams {
        let response =
            resolve_workstream_context_packet(state, data_dir, cfg, gateway, &workstream.id).await?;
        packets.push(response.packet);
    }

    Ok(packets)
}

async fn resolve_workstream_context_packet(
    state: &AppState,
    data_dir: &FsPath,
    cfg: &beagle_config::BeagleConfig,
    gateway: &DarwinHpcGatewayClient,
    workstream_id: &str,
) -> Result<WorkstreamContextPacketResponse, JsonError> {
    let detail = get_workstream_control_room_detail(data_dir, cfg, workstream_id)
        .map_err(|error| workstream_control_room_error(workstream_id, error.to_string()))?;
    let last_result = get_workstream_control_room_last_result(data_dir, cfg, gateway, workstream_id)
        .await
        .ok();
    let latest_physio = latest_physio_snapshot(state)
        .await
        .map(context_packet_physio_from_memory_snapshot);
    let (memory_hits, memory_experiment_flags, retrieval_context) =
        resolve_workstream_memory_context(state, &detail).await?;
    let experiment_flags = resolve_workstream_experiment_flags(
        data_dir,
        last_result.as_ref(),
        memory_experiment_flags,
    );

    get_workstream_context_packet(
        data_dir,
        cfg,
        gateway,
        workstream_id,
        WorkstreamContextPacketAugmentation {
            latest_physio,
            experiment_flags,
            memory_hits,
            retrieval_context,
        },
    )
    .await
    .map_err(|error| workstream_control_room_error(workstream_id, error.to_string()))
    .map(|mut response| {
        apply_intent_planner_to_packet(&mut response.packet);
        apply_plan_execution_to_packet(data_dir, &mut response.packet);
        apply_baseline_adoption_to_packet(data_dir, &mut response.packet);
        response
    })
}

async fn resolve_workstream_context_packet_with_manuscript_quality_sync(
    state: &AppState,
    data_dir: &FsPath,
    cfg: &beagle_config::BeagleConfig,
    gateway: &DarwinHpcGatewayClient,
    workstream_id: &str,
) -> Result<WorkstreamContextPacketResponse, JsonError> {
    let response = resolve_workstream_context_packet(state, data_dir, cfg, gateway, workstream_id)
        .await?;

    if ensure_manuscript_quality_uplift(
        data_dir,
        workstream_id,
        &response.packet.workspace_id,
        &response.packet,
    )
    .is_ok()
    {
        return resolve_workstream_context_packet(state, data_dir, cfg, gateway, workstream_id)
            .await;
    }

    Ok(response)
}

async fn resolve_workstream_memory_context(
    state: &AppState,
    detail: &WorkstreamControlRoomDetailResponse,
) -> Result<
    (
        Vec<WorkstreamContextPacketMemoryHit>,
        Option<WorkstreamContextPacketExperimentFlags>,
        Option<WorkstreamContextPacketRetrievalContext>,
    ),
    JsonError,
> {
    #[cfg(feature = "memory")]
    {
        let binding =
            resolve_program_campaign_binding_for_workstream(&detail.registry_entry.id).ok().flatten();
        let live_session_id = detail
            .status_view
            .live_session
            .as_ref()
            .map(|session| session.session_id.clone());
        let query = beagle_memory::RoutedRetrievalQuery {
            query_version: beagle_memory::ROUTED_RETRIEVAL_QUERY_VERSION.to_string(),
            query_text: workstream_memory_query_text(detail),
            top_k: 3,
            dense_enabled: true,
            sparse_enabled: true,
            dense_weight: 0.65,
            sparse_weight: 0.35,
            filters: beagle_memory::RetrievalFilters {
                workstream_id: Some(detail.registry_entry.id.clone()),
                campaign_id: binding.as_ref().map(|value| value.campaign.id.clone()),
                session_id: None,
                source: None,
                role: None,
                domain: None,
                repo_path: None,
                file_type: None,
                tags: vec![detail.registry_entry.id.clone()],
            },
            query_type_hint: Some("general".to_string()),
            compare_against_general: false,
            rerank_hint: Some("workstream-context-packet".to_string()),
        };

        let ctx = state.ctx.lock().await;
        match ctx.memory_reranked_routed_retrieve(query.clone()).await {
            Ok(result) => {
                let graphrag_query = beagle_memory::GraphRagQuery {
                    query_version: beagle_memory::GRAPHRAG_QUERY_VERSION.to_string(),
                    query_text: query.query_text.clone(),
                    top_k: query.top_k,
                    max_hops: 2,
                    dense_enabled: query.dense_enabled,
                    sparse_enabled: query.sparse_enabled,
                    dense_weight: query.dense_weight,
                    sparse_weight: query.sparse_weight,
                    filters: beagle_memory::RetrievalFilters {
                        workstream_id: query.filters.workstream_id.clone(),
                        campaign_id: query.filters.campaign_id.clone(),
                        session_id: live_session_id,
                        source: query.filters.source.clone(),
                        role: query.filters.role.clone(),
                        domain: query.filters.domain.clone(),
                        repo_path: query.filters.repo_path.clone(),
                        file_type: query.filters.file_type.clone(),
                        tags: query.filters.tags.clone(),
                    },
                    root_entity_type: Some("workstream".to_string()),
                    root_entity_id: Some(detail.registry_entry.id.clone()),
                    program_id: binding.as_ref().map(|value| value.program.id.clone()),
                    include_memory_hierarchy: true,
                    query_type_hint: Some("general".to_string()),
                    query_mode_hint: None,
                    rerank_hint: Some("workstream-context-graphrag".to_string()),
                };
                let graphrag_result = match ctx.memory_graph_rag_query(graphrag_query).await {
                    Ok(result) => Some(result),
                    Err(memory_error) => {
                        error!(
                            "failed to resolve bounded graphrag context for workstream {}: {}",
                            detail.registry_entry.id, memory_error
                        );
                        None
                    }
                };
                let temporal_result = match ctx
                    .memory_temporal_query(temporal_query_for_workstream(detail, &query))
                    .await
                {
                    Ok(result) => Some(result),
                    Err(memory_error) => {
                        error!(
                            "failed to resolve bounded temporal memory context for workstream {}: {}",
                            detail.registry_entry.id, memory_error
                        );
                        None
                    }
                };
                let mut retrieval_context = Some(context_packet_retrieval_context_from_result(
                    &query,
                    &result,
                    graphrag_result.as_ref(),
                    temporal_result.as_ref(),
                ));
                if let Ok(compiled) = ctx
                    .memory_compile_context(compiled_context_request_for_workstream(
                        detail,
                        "analysis",
                        Some("claude-code"),
                        Some("analysis"),
                        None,
                    ))
                    .await
                {
                    if let Some(retrieval) = retrieval_context.as_mut() {
                        apply_compiled_context_to_retrieval_context(retrieval, &compiled);
                    }
                }
                let experiment_flags = result
                    .hits
                    .iter()
                    .find_map(|hit| hit.point.payload.experiment_flags.as_ref())
                    .map(context_packet_experiment_flags_from_memory);
                let hits = result
                    .hits
                    .into_iter()
                    .take(3)
                    .map(context_packet_memory_hit_from_reranked_hit)
                    .collect::<Vec<_>>();
                Ok((hits, experiment_flags, retrieval_context))
            }
            Err(memory_error) => {
                error!(
                    "failed to resolve bounded memory context for workstream {}: {}",
                    detail.registry_entry.id, memory_error
                );
                Ok((Vec::new(), None, None))
            }
        }
    }

    #[cfg(not(feature = "memory"))]
    {
        let _ = state;
        let _ = detail;
        Ok((Vec::new(), None, None))
    }
}

fn context_packet_retrieval_context_from_result(
    query: &beagle_memory::RoutedRetrievalQuery,
    result: &beagle_memory::RerankedResult,
    graphrag_result: Option<&beagle_memory::GraphRagResult>,
    temporal_result: Option<&beagle_memory::TemporalQueryResult>,
) -> WorkstreamContextPacketRetrievalContext {
    let top_memory_ids = result
        .hits
        .iter()
        .map(|hit| hit.point.payload.memory_id.clone())
        .take(5)
        .collect::<Vec<_>>();
    let top_domains = unique_values(
        result
            .hits
            .iter()
            .filter_map(|hit| hit.point.payload.domain.clone()),
        5,
    );
    let top_tags = unique_values(
        result
            .hits
            .iter()
            .flat_map(|hit| hit.point.payload.tags.iter().cloned()),
        8,
    );
    let graphrag_node_types = graphrag_result
        .map(|result| unique_values(result.nodes.iter().map(|node| node.node_type.clone()), 8))
        .unwrap_or_default();
    let graphrag_edge_types = graphrag_result
        .map(|result| unique_values(result.edges.iter().map(|edge| edge.edge_type.clone()), 8))
        .unwrap_or_default();
    let memory_hierarchy_counts = graphrag_result
        .and_then(|result| result.memory_hierarchy.as_ref())
        .map(|hierarchy| {
            hierarchy
                .buckets
                .iter()
                .map(|bucket| WorkstreamContextPacketMemoryHierarchyCount {
                    memory_type: bucket.memory_type.clone(),
                    count: bucket.count,
                })
                .collect::<Vec<_>>()
        })
        .unwrap_or_default();
    let promoted_target_memory_types = graphrag_result
        .map(|result| {
            unique_values(
                result
                    .promoted_memories
                    .iter()
                    .map(|promotion| promotion.target_memory_type.clone()),
                4,
            )
        })
        .unwrap_or_default();
    let temporal_contradiction_ids = temporal_result
        .map(|result| {
            result
                .contradictions
                .iter()
                .map(|contradiction| contradiction.contradiction_id.clone())
                .take(4)
                .collect::<Vec<_>>()
        })
        .unwrap_or_default();
    let temporal_preview = temporal_result.and_then(temporal_preview_from_result);
    let (suggested_subagent_id, suggested_work_mode, influence_reason) =
        retrieval_guidance_from_reranked_hits(&result.hits);

    WorkstreamContextPacketRetrievalContext {
        query_text: query.query_text.clone(),
        query_type: result.query_type.clone(),
        retrieval_mode: result.postrank_retrieval_mode.clone(),
        dense_backend: result.dense_backend.clone(),
        sparse_backend: result.sparse_backend.clone(),
        routing_source: result.routing_decision.routing_source.clone(),
        routing_reason: result.routing_decision.routing_reason.clone(),
        reranking_applied: result.reranking_applied,
        reranking_profile_id: Some(result.profile_id.clone()),
        reranker_backend: Some(result.reranker_backend.clone()),
        reranker_runtime_state: Some(result.reranker_runtime_state.clone()),
        reranking_latency_ms: Some(result.latency.rerank_latency_ms),
        top_k: result.top_k,
        applied_filters: WorkstreamContextPacketRetrievalFilters {
            workstream_id: query.filters.workstream_id.clone(),
            campaign_id: query.filters.campaign_id.clone(),
            session_id: query.filters.session_id.clone(),
            source: query.filters.source.clone(),
            role: query.filters.role.clone(),
            domain: query.filters.domain.clone(),
            tags: query.filters.tags.clone(),
        },
        hit_count: result.hits.len(),
        top_memory_ids,
        top_domains,
        top_tags,
        promotion_policy_id: graphrag_result.map(|result| result.promotion_policy_id.clone()),
        retention_policy_id: graphrag_result.map(|result| result.retention_policy_id.clone()),
        graphrag_query_mode: graphrag_result.map(|result| result.query_mode.clone()),
        graphrag_query_mode_reason: graphrag_result.map(|result| result.query_mode_reason.clone()),
        graphrag_root_entity_type: graphrag_result.and_then(|result| result.root_entity_type.clone()),
        graphrag_root_entity_id: graphrag_result.and_then(|result| result.root_entity_id.clone()),
        graphrag_node_count: graphrag_result.map(|result| result.node_count).unwrap_or(0),
        graphrag_edge_count: graphrag_result.map(|result| result.edge_count).unwrap_or(0),
        graphrag_node_types,
        graphrag_edge_types,
        memory_hierarchy_counts,
        promoted_memory_count: graphrag_result
            .map(|result| result.promoted_memories.len())
            .unwrap_or(0),
        promoted_target_memory_types,
        compiled_context_task_profile: None,
        compiled_context_budget_profile_id: None,
        compiled_context_retrieval_query_type: None,
        compiled_context_graphrag_query_mode: None,
        compiled_context_selected_memory_tiers: Vec::new(),
        compiled_context_source_slices: Vec::new(),
        compiled_context_top_memory_ids: Vec::new(),
        compiled_context_preview: None,
        planner: None,
        execution: None,
        temporal_truth_view: temporal_result.map(|result| result.truth_view.clone()),
        temporal_subject_refs: temporal_result
            .map(|result| result.subject_refs.clone())
            .unwrap_or_default(),
        temporal_current_memory_ids: temporal_result
            .map(|result| result.top_current_memory_ids.clone())
            .unwrap_or_default(),
        temporal_historical_memory_ids: temporal_result
            .map(|result| result.top_historical_memory_ids.clone())
            .unwrap_or_default(),
        temporal_track_count: temporal_result.map(|result| result.track_count).unwrap_or(0),
        temporal_contradiction_count: temporal_result
            .map(|result| result.contradiction_count)
            .unwrap_or(0),
        temporal_contradiction_ids,
        temporal_preview,
        suggested_subagent_id,
        suggested_work_mode,
        influence_reason: format!(
            "{}; router={}:{}; reranker={}; graphrag_mode={}; temporal_view={}; temporal_contradictions={}; promoted_memories={}; graphrag_nodes={}; graphrag_edges={}",
            influence_reason,
            result.routing_decision.query_type,
            result.routing_decision.selected_dense_backend,
            result.reranker_backend,
            graphrag_result
                .map(|result| result.query_mode.clone())
                .unwrap_or_else(|| "none".to_string()),
            temporal_result
                .map(|result| result.truth_view.clone())
                .unwrap_or_else(|| "none".to_string()),
            temporal_result
                .map(|result| result.contradiction_count)
                .unwrap_or(0),
            graphrag_result
                .map(|result| result.promoted_memories.len())
                .unwrap_or(0),
            graphrag_result.map(|result| result.node_count).unwrap_or(0),
            graphrag_result.map(|result| result.edge_count).unwrap_or(0)
        ),
    }
}

fn temporal_query_for_workstream(
    detail: &WorkstreamControlRoomDetailResponse,
    query: &beagle_memory::RoutedRetrievalQuery,
) -> beagle_memory::TemporalQuery {
    beagle_memory::TemporalQuery {
        query_version: beagle_memory::TEMPORAL_QUERY_VERSION.to_string(),
        query_text: query.query_text.clone(),
        truth_view: "both".to_string(),
        top_k: query.top_k.max(3),
        dense_enabled: query.dense_enabled,
        sparse_enabled: query.sparse_enabled,
        dense_weight: query.dense_weight,
        sparse_weight: query.sparse_weight,
        filters: query.filters.clone(),
        root_entity_type: Some("workstream".to_string()),
        root_entity_id: Some(detail.registry_entry.id.clone()),
        subject_refs: Vec::new(),
        include_contradictions: true,
        query_type_hint: query.query_type_hint.clone(),
        query_mode_hint: None,
        rerank_hint: Some("workstream-temporal-memory".to_string()),
    }
}

fn compiled_context_request_for_workstream(
    detail: &WorkstreamControlRoomDetailResponse,
    task_profile: &str,
    tool_id: Option<&str>,
    _work_mode: Option<&str>,
    query_text: Option<&str>,
) -> beagle_memory::CompiledContextRequest {
    let binding =
        resolve_program_campaign_binding_for_workstream(&detail.registry_entry.id).ok().flatten();
    let workspace_id = detail
        .status_view
        .live_session
        .as_ref()
        .map(|session| session.workspace_id.clone())
        .or_else(|| non_empty_string(&detail.registry_entry.latest_governance_validation_workspace_id))
        .or_else(|| non_empty_string(&detail.registry_entry.latest_validation_workspace_id))
        .or_else(|| non_empty_string(&detail.spec.promotion_state.latest_validation_workspace_id))
        .or_else(|| non_empty_string(&detail.spec.promotion_state.canonical_workspace_id));
    let session_id = detail
        .status_view
        .live_session
        .as_ref()
        .map(|session| session.session_id.clone())
        .or_else(|| non_empty_string(&detail.registry_entry.latest_governance_validation_session_id))
        .or_else(|| non_empty_string(&detail.registry_entry.latest_validation_session_id))
        .or_else(|| non_empty_string(&detail.registry_entry.canonical_session_id))
        .or_else(|| non_empty_string(&detail.spec.promotion_state.latest_validation_session_id))
        .or_else(|| non_empty_string(&detail.spec.promotion_state.canonical_session_id));

    beagle_memory::CompiledContextRequest {
        task_profile: task_profile.to_string(),
        tool_id: tool_id.map(|value| value.to_string()),
        query_text: query_text
            .map(|value| value.trim().to_string())
            .filter(|value| !value.is_empty())
            .unwrap_or_else(|| workstream_memory_query_text(detail)),
        workstream_id: Some(detail.registry_entry.id.clone()),
        campaign_id: binding.as_ref().map(|value| value.campaign.id.clone()),
        program_id: binding.as_ref().map(|value| value.program.id.clone()),
        workspace_id,
        session_id,
        root_entity_type: Some("workstream".to_string()),
        root_entity_id: Some(detail.registry_entry.id.clone()),
        repo_path: None,
        file_type: None,
        tags: vec![detail.registry_entry.id.clone()],
        rerank_hint: Some(format!(
            "compiled-context-{}",
            task_profile.trim().to_ascii_lowercase()
        )),
    }
}

async fn resolve_workstream_compiled_context(
    state: &AppState,
    detail: &WorkstreamControlRoomDetailResponse,
    task_profile: Option<&str>,
    tool_id: Option<&str>,
    work_mode: Option<&str>,
    query_text: Option<&str>,
) -> anyhow::Result<beagle_memory::CompiledContextPacket> {
    #[cfg(feature = "memory")]
    {
        let profile = task_profile
            .map(|value| value.trim().to_ascii_lowercase())
            .filter(|value| !value.is_empty())
            .unwrap_or_else(|| task_profile_for_tool(tool_id, work_mode).to_string());
        let request =
            compiled_context_request_for_workstream(detail, &profile, tool_id, work_mode, query_text);
        let ctx = state.ctx.lock().await;
        ctx.memory_compile_context(request).await
    }

    #[cfg(not(feature = "memory"))]
    {
        let _ = state;
        let _ = detail;
        let _ = task_profile;
        let _ = tool_id;
        let _ = work_mode;
        let _ = query_text;
        anyhow::bail!("memory feature not enabled")
    }
}

fn task_profile_for_tool(tool_id: Option<&str>, work_mode: Option<&str>) -> &'static str {
    match (
        tool_id.map(|value| value.trim().to_ascii_lowercase()),
        work_mode.map(|value| value.trim().to_ascii_lowercase()),
    ) {
        (Some(tool), _) if tool == "codex" => "implementation",
        (Some(tool), _) if tool == "cursor" => "interactive-editing",
        (_, Some(mode)) if mode == "manuscript" => "manuscript",
        _ => "analysis",
    }
}

fn apply_compiled_context_to_packet(
    packet: &mut WorkstreamContextPacket,
    compiled: &beagle_memory::CompiledContextPacket,
) {
    if let Some(retrieval) = packet.retrieval_context.as_mut() {
        apply_compiled_context_to_retrieval_context(retrieval, compiled);
    }
}

fn apply_intent_planner_to_packet(packet: &mut WorkstreamContextPacket) {
    let planner = planner_availability_from_packet(&packet.workstream_id, packet);
    if let Some(retrieval) = packet.retrieval_context.as_mut() {
        retrieval.planner = planner;
    }
}

fn apply_plan_execution_to_packet(data_dir: &FsPath, packet: &mut WorkstreamContextPacket) {
    let execution = execution_status_summary_for_packet(data_dir, packet).ok().flatten();
    if let Some(retrieval) = packet.retrieval_context.as_mut() {
        retrieval.execution = execution;
    }
}

fn apply_baseline_adoption_to_packet(data_dir: &FsPath, packet: &mut WorkstreamContextPacket) {
    if let Ok(Some(summary)) =
        bounded_study_baseline_summary_from_plane(data_dir, &packet.workspace_id)
    {
        packet.bounded_study_baseline = Some(summary);
    }
}

fn apply_compiled_context_to_retrieval_context(
    retrieval: &mut WorkstreamContextPacketRetrievalContext,
    compiled: &beagle_memory::CompiledContextPacket,
) {
    retrieval.compiled_context_task_profile = Some(compiled.task_profile.clone());
    retrieval.compiled_context_budget_profile_id =
        Some(compiled.budget_profile.profile_id.clone());
    retrieval.compiled_context_retrieval_query_type =
        Some(compiled.retrieval_query_type.clone());
    retrieval.compiled_context_graphrag_query_mode =
        Some(compiled.graphrag_query_mode.clone());
    retrieval.compiled_context_selected_memory_tiers =
        compiled.selected_memory_tiers.clone();
    retrieval.compiled_context_source_slices = compiled
        .source_slices
        .iter()
        .map(|slice| beagle_darwin::CompiledContextSourceSliceSummary {
            source_kind: slice.source_kind.clone(),
            budgeted_items: slice.budgeted_items,
            selected_count: slice.selected_count,
            support_ids: slice.support_ids.clone(),
        })
        .collect();
    retrieval.compiled_context_top_memory_ids = compiled.top_memory_ids.clone();
    retrieval.compiled_context_preview = Some(
        compiled
            .compiled_context_text
            .lines()
            .take(6)
            .collect::<Vec<_>>()
            .join("\n"),
    );
}

fn temporal_preview_from_result(
    result: &beagle_memory::TemporalQueryResult,
) -> Option<String> {
    let first_track = result.tracks.first()?;
    Some(format!(
        "truth_view: {}\ntruth_key: {}\ncurrent_memory_id: {}\nhistorical_versions: {}\ncontradictions: {}",
        result.truth_view,
        first_track.truth_key,
        first_track.current_memory_id,
        first_track.historical_memory_ids.len(),
        result.contradiction_count
    ))
}

fn non_empty_string(value: &str) -> Option<String> {
    let trimmed = value.trim();
    if trimmed.is_empty() {
        None
    } else {
        Some(trimmed.to_string())
    }
}

fn retrieval_guidance_from_hits(
    hits: &[beagle_memory::RetrievalHit],
) -> (Option<String>, Option<String>, String) {
    let mut corpus = String::new();
    for hit in hits.iter().take(3) {
        if let Some(domain) = hit.point.payload.domain.as_deref() {
            corpus.push_str(domain);
            corpus.push(' ');
        }
        for tag in &hit.point.payload.tags {
            corpus.push_str(tag);
            corpus.push(' ');
        }
        corpus.push_str(&hit.point.payload.text);
        corpus.push(' ');
    }
    let corpus = corpus.to_ascii_lowercase();

    if contains_any(
        &corpus,
        &[
            "manuscript",
            "editorial",
            "jats",
            "crossref",
            "datacite",
            "claim",
            "review bundle",
            "review-bundle",
            "paper",
        ],
    ) {
        return (
            Some("manuscript".to_string()),
            Some("manuscript".to_string()),
            "retrieval top hits leaned editorial claims/review/manuscript work".to_string(),
        );
    }

    if contains_any(
        &corpus,
        &[
            "experiment",
            "experiments",
            "analysis",
            "evidence",
            "evaluation",
            "physio",
            "hrv",
            "observer",
            "expedition",
            "result",
        ],
    ) {
        return (
            Some("experiments".to_string()),
            Some("analysis".to_string()),
            "retrieval top hits leaned experiments/evidence/observer analysis".to_string(),
        );
    }

    (
        Some("core".to_string()),
        Some("implementation".to_string()),
        "retrieval top hits leaned runtime/governance/core implementation".to_string(),
    )
}

fn retrieval_guidance_from_reranked_hits(
    hits: &[beagle_memory::RerankedHit],
) -> (Option<String>, Option<String>, String) {
    let mut corpus = String::new();
    for hit in hits.iter().take(3) {
        if let Some(domain) = hit.point.payload.domain.as_deref() {
            corpus.push_str(domain);
            corpus.push(' ');
        }
        for tag in &hit.point.payload.tags {
            corpus.push_str(tag);
            corpus.push(' ');
        }
        corpus.push_str(&hit.point.payload.text);
        corpus.push(' ');
    }
    let corpus = corpus.to_ascii_lowercase();

    if contains_any(
        &corpus,
        &[
            "manuscript",
            "editorial",
            "jats",
            "crossref",
            "datacite",
            "claim",
            "review bundle",
            "review-bundle",
            "paper",
        ],
    ) {
        return (
            Some("manuscript".to_string()),
            Some("manuscript".to_string()),
            "retrieval top hits leaned editorial claims/review/manuscript work".to_string(),
        );
    }

    if contains_any(
        &corpus,
        &[
            "experiment",
            "experiments",
            "analysis",
            "evidence",
            "evaluation",
            "physio",
            "hrv",
            "observer",
            "expedition",
            "result",
        ],
    ) {
        return (
            Some("experiments".to_string()),
            Some("analysis".to_string()),
            "retrieval top hits leaned experiments/evidence/observer analysis".to_string(),
        );
    }

    (
        Some("core".to_string()),
        Some("implementation".to_string()),
        "retrieval top hits leaned runtime/governance/core implementation".to_string(),
    )
}

fn contains_any(haystack: &str, needles: &[&str]) -> bool {
    needles.iter().any(|needle| haystack.contains(needle))
}

fn unique_values<I>(values: I, limit: usize) -> Vec<String>
where
    I: IntoIterator<Item = String>,
{
    let mut seen = BTreeSet::new();
    let mut ordered = Vec::new();
    for value in values {
        let normalized = value.trim();
        if normalized.is_empty() {
            continue;
        }
        if seen.insert(normalized.to_string()) {
            ordered.push(normalized.to_string());
        }
        if ordered.len() >= limit {
            break;
        }
    }
    ordered
}

async fn ingest_workstream_tool_return_memory(
    state: &AppState,
    context_packet: &WorkstreamContextPacketResponse,
    payload: &WorkstreamToolReturnPayload,
) -> Result<Option<String>, JsonError> {
    #[cfg(feature = "memory")]
    {
        let text = {
            let memory_text = payload.memory_text.trim();
            if memory_text.is_empty() {
                payload.summary.trim().to_string()
            } else {
                memory_text.to_string()
            }
        };

        let turn_index = Utc::now().timestamp_millis().max(0) as usize;
        let tags = vec![
            context_packet.packet.workstream_id.clone(),
            context_packet.packet.workspace_id.clone(),
            context_packet.packet.session_id.clone(),
            "tool-return".to_string(),
            payload.tool.trim().to_ascii_lowercase(),
            payload.action_type.trim().to_ascii_lowercase(),
        ];
        let latest_physio = context_packet
            .packet
            .latest_physio
            .clone()
            .map(memory_physio_from_context_packet);
        let experiment_flags = context_packet
            .packet
            .experiment_flags
            .clone()
            .map(memory_experiment_flags_from_context_packet);
        let provider = context_packet
            .packet
            .experiment_flags
            .as_ref()
            .and_then(|flags| flags.provider.clone());
        let model = context_packet
            .packet
            .experiment_flags
            .as_ref()
            .and_then(|flags| flags.model.clone());

        let session = beagle_memory::ChatSession {
            source: payload.tool.trim().to_ascii_lowercase(),
            session_id: payload.session_id.clone(),
            turns: vec![beagle_memory::ChatTurn {
                role: "tool".to_string(),
                content: text,
                timestamp: Some(Utc::now()),
                model: model.clone(),
                turn_index: Some(turn_index),
            }],
            tags,
            metadata: json!({
                "domain": "beagle-workstream-writeback",
                "provider": provider,
                "model": model,
                "physio_snapshot": latest_physio,
                "experiment_flags": experiment_flags,
                "workstream_id": context_packet.packet.workstream_id,
                "workspace_id": context_packet.packet.workspace_id,
                "session_id": context_packet.packet.session_id,
                "tool": payload.tool,
                "action_type": payload.action_type,
                "summary": payload.summary,
                "patch_ref": payload.patch_ref,
                "repo_refs": payload.repo_refs,
                "result_refs": payload.result_refs,
            }),
        };

        let ctx = state.ctx.lock().await;
        let stats = ctx
            .memory_ingest_session(session)
            .await
            .map_err(|error| {
                internal_error_response(
                    "workstream_tool_return_memory_ingest_failed",
                    error.to_string(),
                )
            })?;
        Ok(stats.memory_id)
    }

    #[cfg(not(feature = "memory"))]
    {
        let _ = state;
        let _ = context_packet;
        let _ = payload;
        Ok(None)
    }
}

fn resolve_workstream_experiment_flags(
    data_dir: &FsPath,
    last_result: Option<&WorkstreamControlRoomLastResultResponse>,
    fallback: Option<WorkstreamContextPacketExperimentFlags>,
) -> Option<WorkstreamContextPacketExperimentFlags> {
    let source_run_id = last_result
        .and_then(|response| response.result.as_ref())
        .and_then(|result| result.source_run_id.as_deref());

    if let Some(run_id) = source_run_id {
        if let Some(flags) = load_experiment_flags_from_run_report(data_dir, run_id) {
            return Some(flags);
        }
    }

    fallback
}

fn load_experiment_flags_from_run_report(
    data_dir: &FsPath,
    run_id: &str,
) -> Option<WorkstreamContextPacketExperimentFlags> {
    let report_dir = data_dir.join("logs").join("beagle-pipeline");
    let entries = std::fs::read_dir(report_dir).ok()?;
    let suffix = format!("_{}.json", run_id);

    for entry in entries.flatten() {
        let path = entry.path();
        let Some(name) = path.file_name().and_then(|value| value.to_str()) else {
            continue;
        };
        if !name.ends_with(&suffix) {
            continue;
        }
        let raw = std::fs::read_to_string(&path).ok()?;
        let value: serde_json::Value = serde_json::from_str(&raw).ok()?;
        return Some(WorkstreamContextPacketExperimentFlags {
            hrv_aware: value
                .get("experiment_flags")
                .and_then(|flags| flags.get("hrv_aware"))
                .and_then(|flag| flag.as_bool()),
            observer_enabled: value
                .get("experiment_flags")
                .and_then(|flags| flags.get("observer_enabled"))
                .and_then(|flag| flag.as_bool()),
            serendipity_enabled: value
                .get("experiment_flags")
                .and_then(|flags| flags.get("serendipity_enabled"))
                .and_then(|flag| flag.as_bool()),
            triad_enabled: value
                .get("experiment_flags")
                .and_then(|flags| flags.get("triad_enabled"))
                .and_then(|flag| flag.as_bool()),
            provider: value
                .get("experiment_flags")
                .and_then(|flags| flags.get("provider"))
                .and_then(|flag| flag.as_str())
                .map(|value| value.to_string()),
            model: value
                .get("experiment_flags")
                .and_then(|flags| flags.get("model"))
                .and_then(|flag| flag.as_str())
                .map(|value| value.to_string()),
            experiment_id: value
                .get("experiment")
                .and_then(|experiment| experiment.get("experiment_id"))
                .and_then(|flag| flag.as_str())
                .map(|value| value.to_string()),
            condition: value
                .get("experiment")
                .and_then(|experiment| experiment.get("condition"))
                .and_then(|flag| flag.as_str())
                .map(|value| value.to_string()),
        });
    }

    None
}

fn workstream_memory_query_text(detail: &WorkstreamControlRoomDetailResponse) -> String {
    let mut parts = vec![
        detail.registry_entry.id.clone(),
        detail.spec.repo.clone(),
        detail.spec.default_branch.clone(),
    ];

    if let Some(handoff) = detail.handoff_view.last_handoff.as_deref() {
        if !handoff.trim().is_empty() {
            parts.push(handoff.trim().to_string());
        }
    }

    if let Some(task) = detail.handoff_view.last_successful_task.as_ref() {
        parts.push(task.task_kind.clone());
        parts.push(task.workflow_run_label.clone());
    }

    parts.join(" ")
}

fn context_packet_physio_from_memory_snapshot(
    snapshot: beagle_memory::PhysioSnapshot,
) -> WorkstreamContextPacketPhysioSnapshot {
    WorkstreamContextPacketPhysioSnapshot {
        hr: snapshot.hr,
        hrv_level: snapshot.hrv_level,
        spo2: snapshot.spo2,
        timestamp: snapshot.timestamp,
        source: snapshot.source,
    }
}

fn memory_physio_from_context_packet(
    snapshot: WorkstreamContextPacketPhysioSnapshot,
) -> beagle_memory::PhysioSnapshot {
    beagle_memory::PhysioSnapshot {
        hr: snapshot.hr,
        hrv_level: snapshot.hrv_level,
        spo2: snapshot.spo2,
        timestamp: snapshot.timestamp,
        source: snapshot.source,
    }
}

fn memory_experiment_flags_from_context_packet(
    flags: WorkstreamContextPacketExperimentFlags,
) -> beagle_memory::ExperimentFlags {
    beagle_memory::ExperimentFlags {
        hrv_aware: flags.hrv_aware,
        serendipity_enabled: flags.serendipity_enabled,
        triad_enabled: flags.triad_enabled,
        provider: flags.provider,
        model: flags.model,
    }
}

fn context_packet_experiment_flags_from_memory(
    flags: &beagle_memory::ExperimentFlags,
) -> WorkstreamContextPacketExperimentFlags {
    WorkstreamContextPacketExperimentFlags {
        hrv_aware: flags.hrv_aware,
        observer_enabled: None,
        serendipity_enabled: flags.serendipity_enabled,
        triad_enabled: flags.triad_enabled,
        provider: flags.provider.clone(),
        model: flags.model.clone(),
        experiment_id: None,
        condition: flags.hrv_aware.map(|enabled| {
            if enabled {
                "hrv_aware".to_string()
            } else {
                "hrv_blind".to_string()
            }
        }),
    }
}

fn context_packet_memory_hit_from_highlight(
    highlight: beagle_memory::MemoryResultHighlight,
) -> WorkstreamContextPacketMemoryHit {
    WorkstreamContextPacketMemoryHit {
        memory_id: highlight.memory_id,
        source: highlight.source,
        conversation_id: highlight.conversation_id,
        turn_index: highlight.turn_index,
        role: highlight.role,
        snippet: highlight.snippet,
        timestamp: highlight.date,
        relevance: highlight.relevance,
        tags: highlight.tags,
        domain: highlight.domain,
        physio_snapshot: highlight
            .physio_snapshot
            .map(context_packet_physio_from_memory_snapshot),
    }
}

fn context_packet_memory_hit_from_retrieval_hit(
    hit: beagle_memory::RetrievalHit,
) -> WorkstreamContextPacketMemoryHit {
    let payload = hit.point.payload;
    WorkstreamContextPacketMemoryHit {
        memory_id: Some(payload.memory_id),
        source: payload.source,
        conversation_id: Some(payload.conversation_id),
        turn_index: Some(payload.turn_index),
        role: Some(payload.role),
        snippet: payload.text.chars().take(240).collect(),
        timestamp: Some(payload.timestamp),
        relevance: hit.hybrid_score,
        tags: payload.tags,
        domain: payload.domain,
        physio_snapshot: payload
            .physio_snapshot
            .map(context_packet_physio_from_memory_snapshot),
    }
}

fn context_packet_memory_hit_from_reranked_hit(
    hit: beagle_memory::RerankedHit,
) -> WorkstreamContextPacketMemoryHit {
    let payload = hit.point.payload;
    WorkstreamContextPacketMemoryHit {
        memory_id: Some(payload.memory_id),
        source: payload.source,
        conversation_id: Some(payload.conversation_id),
        turn_index: Some(payload.turn_index),
        role: Some(payload.role),
        snippet: payload.text.chars().take(240).collect(),
        timestamp: Some(payload.timestamp),
        relevance: hit.rerank_score,
        tags: payload.tags,
        domain: payload.domain,
        physio_snapshot: payload
            .physio_snapshot
            .map(context_packet_physio_from_memory_snapshot),
    }
}

async fn current_cfg(state: &AppState) -> beagle_config::BeagleConfig {
    let ctx = state.ctx.lock().await;
    ctx.cfg.clone()
}

fn gateway_client() -> Result<DarwinHpcGatewayClient, JsonError> {
    DarwinHpcGatewayClient::from_env().map_err(|error| {
        internal_error_response("darwin_hpc_gateway_init_failed", error.to_string())
    })
}

fn tool_bridge_from_cfg(cfg: &beagle_config::BeagleConfig) -> Result<ToolBridge, JsonError> {
    ToolBridge::from_config(cfg)
        .map_err(|error| internal_error_response("tool_bridge_init_failed", error.to_string()))
}

fn gateway_error_response(error: DarwinHpcGatewayError) -> JsonError {
    let status = error
        .status_code
        .and_then(|code| StatusCode::from_u16(code).ok())
        .unwrap_or(StatusCode::BAD_GATEWAY);

    (
        status,
        Json(json!({
            "error": "darwin_hpc_gateway_error",
            "detail": error.message,
        })),
    )
}

fn internal_error_response(code: &str, detail: String) -> JsonError {
    (
        StatusCode::INTERNAL_SERVER_ERROR,
        Json(json!({
            "error": code,
            "detail": detail,
        })),
    )
}

fn not_found_response(code: &str, detail: String) -> JsonError {
    (
        StatusCode::NOT_FOUND,
        Json(json!({
            "error": code,
            "detail": detail,
        })),
    )
}

fn bad_request_response(code: &str, detail: String) -> JsonError {
    (
        StatusCode::BAD_REQUEST,
        Json(json!({
            "error": code,
            "detail": detail,
        })),
    )
}

fn conflict_response(code: &str, detail: String) -> JsonError {
    (
        StatusCode::CONFLICT,
        Json(json!({
            "error": code,
            "detail": detail,
        })),
    )
}

fn forbidden_response(code: &str, detail: String) -> JsonError {
    (
        StatusCode::FORBIDDEN,
        Json(json!({
            "error": code,
            "detail": detail,
            "available_consumers": available_consumers(),
        })),
    )
}

fn ensure_allowed(result: Result<(), String>) -> Result<(), JsonError> {
    result.map_err(|detail| forbidden_response("darwin_consumer_forbidden", detail))
}

fn workstream_control_room_error(workstream_id: &str, detail: String) -> JsonError {
    if detail.contains("is not present in the canonical registry") {
        return not_found_response(
            "workstream_control_room_not_found",
            format!("workstream {} is not present in the canonical registry", workstream_id),
        );
    }

    internal_error_response("workstream_control_room_failed", detail)
}

fn workstream_control_room_action_error(workstream_id: &str, detail: String) -> JsonError {
    if detail.contains("is not present in the canonical registry") {
        return not_found_response(
            "workstream_control_room_not_found",
            format!("workstream {} is not present in the canonical registry", workstream_id),
        );
    }
    if detail.contains("is not allowed from current state")
        || detail.contains("cannot run while a current task is active")
    {
        return conflict_response("workstream_control_action_conflict", detail);
    }

    internal_error_response("workstream_control_action_failed", detail)
}

fn workstream_tool_return_error(workstream_id: &str, detail: String) -> JsonError {
    if detail.contains("is not present in the canonical registry") {
        return not_found_response(
            "workstream_control_room_not_found",
            format!("workstream {} is not present in the canonical registry", workstream_id),
        );
    }
    if detail.contains("does not match") || detail.contains("is required") {
        return conflict_response("workstream_tool_return_conflict", detail);
    }

    internal_error_response("workstream_tool_return_failed", detail)
}

fn workstream_timeline_error(workstream_id: &str, detail: String) -> JsonError {
    if detail.contains("is not present in the canonical registry") {
        return not_found_response(
            "workstream_timeline_not_found",
            format!("workstream {} is not present in the canonical registry", workstream_id),
        );
    }
    if detail.contains("timeline event ") && detail.contains(" is not present for workstream ") {
        return not_found_response("workstream_timeline_event_not_found", detail);
    }

    internal_error_response("workstream_timeline_failed", detail)
}
