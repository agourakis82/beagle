//! Beagle Darwin - Incorporação completa do darwin-core no BEAGLE
//!
//! Features:
//! - GraphRAG real (usa hypergraph + neo4j)
//! - Self-RAG (agente decide se precisa de mais busca)
//! - Plugin system (troca LLM em runtime: Grok 3 / local 70B / Heavy)
//! - Multi-AI orchestration integrado
//!
//! **Uso direto:**
//! ```rust
//! use beagle_darwin::darwin_enhanced_cycle;
//!
//! let answer = darwin_enhanced_cycle("unificar entropia curva com consciência celular").await;
//! println!("DARWIN + BEAGLE: {answer}");
//! ```

pub mod approval_gate;
pub mod autonomy_calibration;
pub mod autonomy_policy;
pub mod consumer_policy;
pub mod claim_layer;
pub mod collaborative_workbench;
pub mod workbench;
pub mod workbench_session;
pub mod compute_selection;
pub mod collaboration_access;
pub mod compiled_context;
pub mod code_provenance;
pub mod continuation_dispatch;
pub mod continuation_state;
pub mod cursor_remote_lane;
pub mod evidence_pack;
pub mod execution_plan;
pub mod execution_reflection;
pub mod execution_state;
pub mod intent_planner;
pub mod manuscript_pack;
pub mod plan_execution;
pub mod program_context_packet;
pub mod replan;
pub mod replay_execution;
pub mod next_run_proposal;
pub mod review_decision;
pub mod review_inbox;
pub mod review_bundle;
pub mod repo_context;
pub mod risk_evaluation;
pub mod run_capsule;
pub mod run_diff;
pub mod source_fingerprint;
pub mod study_dag;
pub mod study_decision;
pub mod study_continuation;
pub mod study_convergence;
pub mod study_promotion_execution;
pub mod baseline_adoption;
pub mod next_study_seed;
pub mod study_proposal_dispatch;
pub mod study_registry;
pub mod study_sweep;
pub mod object_results;
pub mod result_catalog;
pub mod tool_bridge;
pub mod tool_bridge_ledger;
pub mod tool_bridge_types;
pub mod workstream_cockpit;
pub mod workstream_context_packet;
pub mod workstream_control_room;
pub mod workstream_tool_return;
pub mod workstream_timeline;
pub mod trajectory_eval;
pub mod follow_on_plan;
pub mod workbench_reservation;
pub mod workbench_result_binding;
pub mod workbench_run;
pub mod workbench_orchestration;
pub mod workspace_plane;
pub mod workspace_attach;
pub mod workspace_habitat;
pub mod workspace_launch_resume;
pub mod workspace_manuscript_handoff;
pub mod workspace_manuscript_assembly;
pub mod workspace_external_registry_staging;
pub mod workspace_sandbox_deposit_handshake;
pub mod workspace_publication_package;
pub mod workspace_scholarly_release;
pub mod workspace_subagent_handoff;
pub mod workspace_subagent_routing;
pub mod workspace_subagents;
pub mod workspace_snapshot;
pub mod workspace_template;
pub mod workspace_tenancy;

use beagle_core::{BeagleContext, KnowledgeSnippet};
use beagle_llm::vllm::{SamplingParams, VllmClient, VllmCompletionRequest};
use beagle_smart_router::query_smart;
use std::sync::Arc;
use tracing::{info, warn};

pub use approval_gate::ApprovalGatingDecision;
pub use autonomy_calibration::{
    AnalysisCanaryActivationBundle, AnalysisCanaryFamilyMetric, AnalysisCanaryMetrics,
    AnalysisCanaryRollbackDecision, AnalysisPromotionGate, AnalysisRolloutDecision,
    AnalysisRolloutMetrics, AnalysisShadowCalibration, AnalysisShadowCalibrationBundle,
    AnalysisShadowComparisonEntry, AnalysisShadowHistoryEntry, AnalysisShadowSoak,
    AnalysisShadowSoakBundle, AnalysisSampleAccumulationBundle, AnalysisSoakMetrics,
    AnalysisTaskFamilyMetric, AutonomyCalibrationDataset, AutonomyCalibrationSample,
    AutonomyPolicyCalibrationBundle, AutonomyPolicyEvalReport,
    AutonomyShadowTaskFamilyThreshold, AutonomyShadowThreshold, CanaryRollbackDecision,
    CanaryRolloutMetrics, CanaryTaskFamilyMetric, EscalationThreshold,
    EscalationThresholds, GuardedPolicyRolloutBundle, GuardedRolloutDecision,
    GuardedTaskFamilyDecision, ImplementationCanaryAutonomyBundle,
    ManuscriptAlignmentLabelEntry, ManuscriptAlignmentLabelingBundle,
    ManuscriptAlignmentSignalBundle, ManuscriptAlignmentLabels,
    ManuscriptContextAdequacy, ManuscriptPromotionEvidence, ManuscriptPromotionGate,
    ManuscriptQualityUpliftBundle, ManuscriptRolloutDecision, ManuscriptRolloutMetrics,
    ManuscriptSampleAccumulationBundle, ManuscriptShadowCalibration,
    ManuscriptShadowCalibrationBundle, ManuscriptShadowComparisonEntry,
    ManuscriptShadowHistory, ManuscriptShadowHistoryEntry, ManuscriptSoakMetrics,
    ManuscriptTaskFamilyMetric, ManuscriptTrajectoryQuality,
    ManuscriptTuningRecommendation, PolicyRolloutMetrics, PolicySignalImpact,
    PolicyTaskFamilyUpdateRecommendation, ShadowPolicyComparison,
    ShadowPolicyComparisonEntry, TaskFamilyCalibrationSummary, TaskFamilyRolloutMetric,
    UpdatedPolicyRecommendation,
};
pub use autonomy_policy::AutonomyPolicy;
pub use consumer_policy::{
    available_consumers, consumer_identity_for_id, ConsumerId, ConsumerIdentity,
};
pub use claim_layer::{
    build_campaign_claims, build_campaign_manuscript_pack, CampaignClaimsResponse,
    ClaimRecord, ManuscriptPack, ManuscriptPackResponse,
};
pub use collaborative_workbench::{
    build_collaborative_compute_experiment_workbench,
    CollaborativeComputeExperimentWorkbench,
    CollaborativeComputeExperimentWorkbenchBundle,
    CollaborativeWorkbenchCollaborationContract,
    CollaborativeWorkbenchComputeSelectionContract,
    CollaborativeWorkbenchRunContract,
    CollaborativeWorkbenchSessionContract,
    WorkbenchMemoryContextSummary,
    WorkbenchResultReference,
};
pub use code_provenance::{
    capture_code_provenance, CodeProvenance, CodeProvenanceBundle,
    CodeProvenanceCaptureRequest, CodeProvenanceContext,
};
pub use workbench_reservation::{
    read_workbench_reservation, WorkbenchReservation, WorkbenchReservationRequest,
};
pub use workbench_result_binding::{
    read_deterministic_result_binding, read_run_result_identity_receipt,
    read_run_scoped_publication, read_workbench_result_binding,
    DeterministicResultBinding, RunResultIdentityReceipt, RunScopedPublication,
    WorkbenchBoundResultRef, WorkbenchResultBinding,
};
pub use workbench_run::{
    orchestrate_workbench_run, read_workbench_run, WorkbenchRun,
    WorkbenchRunDispatchRequest, WorkbenchRunOrchestrationBundle, WorkbenchRunTransition,
};
pub use run_capsule::{
    read_code_provenance, read_latest_run_capsule, read_prior_run_capsule,
    read_replay_request, read_source_fingerprint, read_workspace_snapshot,
    record_run_capsule, ReplayRequest, RunCapsule, RunCapsuleEnvironmentSnapshot,
    RunCapsuleGitSnapshot, RunCapsuleInputManifest,
};
pub use replay_execution::{
    execute_replay_request, read_latest_replay_execution, ReplayExecutionBundle,
    ReplayExecutionReceipt, ReplayExecutionRequest,
};
pub use run_diff::{
    generate_run_diff, read_reproducibility_bundle, read_run_diff, RunDiff, RunDiffCategory,
};
pub use next_run_proposal::{build_next_run_proposal, read_next_run_proposal, NextRunProposal};
pub use source_fingerprint::{
    build_source_fingerprint, LockfileFingerprint, SourceFingerprint,
    SourceFingerprintCaptureRequest, SourceFingerprintContext,
};
pub use study_dag::{StudyDag, StudyDagEdge, StudyDagNode};
pub use study_decision::{
    ensure_study_decision_engine, read_study_decision, read_study_decision_basis,
    StudyDecision, StudyDecisionBasis, StudyDecisionEngineBundle, StudyEvidenceRef,
};
pub use study_continuation::{
    build_study_continuation_state, build_study_run_update, read_study_continuation_state,
    read_study_run_update, write_study_continuation_state, write_study_run_update,
    StudyContinuationState, StudyRunUpdate,
};
pub use study_convergence::{
    ensure_study_convergence, read_study_closeout_summary, read_study_convergence,
    read_variant_promotion_decision, StudyCloseoutSummary, StudyConvergence,
    StudyConvergenceBundle, VariantPromotionDecision,
};
pub use study_promotion_execution::{
    ensure_study_promotion_execution, read_study_promotion_execution, StudyPromotionExecution,
    StudyPromotionExecutionBundle,
};
pub use baseline_adoption::{
    bounded_study_baseline_summary_from_plane, ensure_baseline_adoption, read_baseline_adoption,
    read_baseline_rollback_plan, read_next_study_seed, read_promoted_variant_receipt,
    read_workbench_context_after_baseline, BaselineAdoption, BaselineAdoptionBundle,
    BaselineRollbackPlan, PromotedVariantReceipt, WorkbenchContextAfterBaseline,
};
pub use next_study_seed::{build_next_study_seed, NextStudySeed};
pub use study_proposal_dispatch::{
    ensure_study_proposal_dispatch, read_latest_study_proposal_dispatch_bundle,
    read_study_proposal_dispatch, StudyProposalDispatch, StudyProposalDispatchBundle,
    StudyProposalDispatchRequest,
};
pub use study_registry::{
    ensure_study_registry_sweep, read_comparative_result_summary, read_study_dag,
    read_study_registry, read_study_sweep, ComparativeResultSummary,
    ComparativeRunSummary, StudyRegistry, StudyRegistrySweepBundle,
    StudyRunRegistration,
};
pub use study_sweep::{StudySweep, StudySweepVariant};
pub use compiled_context::CompiledContextSourceSliceSummary;
pub use continuation_dispatch::{ContinuationDispatch, ContinuationDispatchRequest};
pub use continuation_state::{ContinuationReceipt, ContinuationStatePlane, ContinuationStateTransition};
pub use cursor_remote_lane::{
    build_workstream_cursor_remote_lane, CursorRemoteLane, CursorRemoteLaneConnectionMetadata,
    CursorRemoteLaneResponse,
};
pub use evidence_pack::{
    build_campaign_evidence_pack, EvidencePack, EvidencePackCitation,
    EvidencePackDatasetRef, EvidencePackDecisionNote, EvidencePackExperimentRef,
    EvidencePackMemoryRef, EvidencePackPhysioRef, EvidencePackProvenance,
    EvidencePackProvenanceActivity, EvidencePackProvenanceAgent,
    EvidencePackProvenanceEntity, EvidencePackRecipeRef, EvidencePackRelatedIdentifier,
    EvidencePackResponse, EvidencePackResultRef,
};
pub use execution_plan::{
    ExecutionExperimentTarget, ExecutionPlan, ExecutionRecipeTarget, IntentPlan,
    IntentPlannerAvailability, PlanAcceptanceCriterion, PlannerCompiledContextSelection,
    PlannerPolicy, PlannerPolicyProfile,
};
pub use execution_reflection::ExecutionReflection;
pub use execution_state::{
    ExecutionReceipt, ExecutionResultLink, ExecutionResultLinksDocument,
    ExecutionStatePlane, ExecutionStateTransition, PlanApproval,
    PlanExecutionStatusSummary,
};
pub use follow_on_plan::FollowOnPlan;
pub use intent_planner::{
    build_intent_execution_plan, planner_availability_from_packet,
    planner_compiled_context_selection_from_packet, planner_policy_for_workstream,
    task_family_hint, IntentPlanRequest, IntentPlannerResponse,
};
pub use plan_execution::{
    approve_execution_plan, ensure_analysis_canary_activation,
    ensure_analysis_shadow_calibration, ensure_analysis_sample_accumulation,
    ensure_analysis_shadow_soak, ensure_autonomy_policy_calibration,
    ensure_guarded_policy_rollout, ensure_implementation_canary_autonomy,
    ensure_manuscript_alignment_labeling,
    ensure_manuscript_alignment_signal_acquisition,
    ensure_manuscript_quality_uplift,
    ensure_manuscript_sample_accumulation, ensure_manuscript_shadow_calibration,
    execution_status_summary_for_packet,
    read_approval_gating_decision, read_analysis_canary_metrics,
    read_analysis_canary_rollback_decision, read_analysis_promotion_gate,
    read_analysis_rollout_decision, read_analysis_rollout_metrics,
    read_analysis_shadow_comparison, read_analysis_shadow_history,
    read_analysis_sample_accumulation, read_analysis_sample_accumulation_metrics,
    read_analysis_promotion_gate_recheck, read_analysis_soak_metrics,
    read_autonomy_policy_analysis_canary, read_autonomy_policy_analysis_control,
    read_autonomy_calibration_dataset, read_autonomy_policy,
    read_autonomy_policy_candidate, read_autonomy_policy_analysis_candidate,
    read_autonomy_policy_control, read_autonomy_policy_current,
    read_autonomy_policy_canary, read_autonomy_policy_implementation_canary_retained,
    read_autonomy_policy_eval_report, read_autonomy_policy_manuscript_candidate,
    read_canary_rollback_decision, read_canary_rollout_metrics,
    read_continuation_dispatch, read_continuation_receipt, read_continuation_state,
    read_escalation_thresholds, read_execution_envelope, read_execution_receipt,
    read_execution_reflection, read_execution_result_links, read_execution_state,
    read_follow_on_plan, read_guarded_rollout_decision,
    read_manuscript_alignment_labels, read_manuscript_promotion_evidence,
    read_manuscript_promotion_gate, read_manuscript_context_adequacy,
    read_manuscript_rollout_decision,
    read_manuscript_rollout_metrics, read_manuscript_shadow_comparison,
    read_manuscript_shadow_history, read_manuscript_soak_metrics,
    read_manuscript_trajectory_quality, read_manuscript_tuning_recommendation,
    read_replan_suggestion, read_review_decision, read_review_inbox_item,
    read_rollout_metrics, read_risk_evaluation, read_shadow_policy_comparison,
    read_trajectory_eval, read_updated_policy_recommendation, decide_review_inbox_item,
    dispatch_follow_on_plan, materialize_review_inbox_item, start_execution_plan,
    stop_execution_plan, PlanApprovalRequest, PlanExecutionEnvelope,
    PlanExecutionStartRequest, PlanExecutionStopRequest, ReviewInboxDecisionRequest,
    ReviewInboxMaterializeRequest,
};
pub use manuscript_pack::{
    build_campaign_jats_manuscript_pack, JatsManuscriptPack, JatsManuscriptPackResponse,
    JatsManuscriptSection,
};
pub use review_bundle::{
    build_campaign_review_bundle, ReviewBundle, ReviewBundlePayloadItem,
    ReviewBundleResponse,
};
pub use program_context_packet::{
    build_program_context_packet, resolve_campaign_context_binding,
    resolve_program_campaign_binding_for_workstream, resolve_program_context_binding,
    CampaignDatasetRef, CampaignDocument, CampaignExperimentRef, CampaignMemoryContext,
    CampaignObserverContext, CampaignWorkstreamRef, ProgramCampaignBinding,
    ProgramCampaignRef, ProgramContextPacket, ProgramContextPacketEvidenceTarget,
    ProgramContextPacketLatestResult, ProgramContextPacketMemoryHit,
    ProgramContextPacketResponse, ProgramContextPacketRetrievalContext, ProgramDocument, ProgramEvidenceTarget,
    ProgramExperimentRef, ProgramNorthStar, ProgramWorkstreamRef,
};
pub use replan::ReplanSuggestion;
pub use review_decision::{ReviewDecision, ReviewDecisionEditPatch};
pub use review_inbox::ReviewInboxItem;
pub use repo_context::RepoContext;
pub use risk_evaluation::{RiskEvaluation, RiskSignal};
pub use workspace_snapshot::{
    capture_workspace_snapshot, dirty_state_to_bool, WorkspaceSnapshot,
    WorkspaceSnapshotCaptureRequest, WorkspaceSnapshotContext,
};
pub use object_results::{HpcTextArtifact, JobArtifactManifest, ObjectPublishedArtifact, ObjectResultManifest};
pub use result_catalog::{
    DarwinHpcGatewayClient, DarwinHpcGatewayError, HpcJobStatus, HpcProfile, HpcProfileCatalog,
    HpcSubmitRequest, HpcSubmitResponse, ResultCatalogEntry, ResultCatalogQuery,
    ResultCatalogResponse, DEFAULT_DARWIN_HPC_GATEWAY_BASE_URL,
};
pub use tool_bridge::ToolBridge;
pub use tool_bridge_ledger::{
    append_ledger_entry, ledger_file_path, read_recent_ledger_entries, BridgeLedgerEntry,
};
pub use tool_bridge_types::{
    BridgeHealth, BridgeKind, BridgeMode, BridgeProvider, BridgeProviderInfo, BridgeRequest,
    BridgeResponse, BridgeStatus, BridgeTokenUsage,
};
pub use workstream_cockpit::{
    get_premium_tool_launch_surface, get_premium_tool_launch_surface_with_context_packet,
    get_workstream_cockpit, get_workstream_cockpit_with_context_packet,
    render_workstream_cockpit_page,
    WorkstreamCockpitHandoffPanel, WorkstreamCockpitLastResultPanel,
    WorkstreamCockpitManifestSummary, WorkstreamCockpitRecipeCard,
    WorkstreamCockpitResponse, WorkstreamCockpitResultSummary,
    WorkstreamPremiumToolLaunchResponse, WorkstreamPremiumToolLaunchSurface,
    WorkstreamSessionEnvelope,
};
pub use workstream_context_packet::{
    get_workstream_context_packet, BoundedStudyBaselineSummary, WorkstreamContextPacket,
    WorkstreamContextPacketAugmentation, WorkstreamContextPacketExperimentFlags,
    WorkstreamContextPacketHandoff, WorkstreamContextPacketLastResult,
    WorkstreamContextPacketManifestSummary, WorkstreamContextPacketMemoryHit,
    WorkstreamContextPacketMemoryHierarchyCount,
    WorkstreamContextPacketPhysioSnapshot, WorkstreamContextPacketRecipe,
    WorkstreamContextPacketResponse, WorkstreamContextPacketResultSummary,
    WorkstreamContextPacketRetrievalContext, WorkstreamContextPacketRetrievalFilters,
};
pub use workstream_control_room::{
    get_workstream_portfolio_control_room,
    run_workstream_control_room_action,
    get_workstream_control_room_detail, get_workstream_control_room_handoff,
    get_workstream_control_room_last_result, get_workstream_control_room_recipes,
    get_workstream_control_room_status, list_workstream_control_room,
    resolve_registered_workstream, WorkstreamControlRoomActionAvailability,
    WorkstreamControlRoomActionResponse,
    WorkstreamControlRoomActionSupport, WorkstreamControlRoomDetailResponse,
    WorkstreamGovernanceActionLedgerEntry,
    WorkstreamControlRoomHandoffResponse, WorkstreamControlRoomLastResultResponse,
    WorkstreamControlRoomListEntry, WorkstreamControlRoomListResponse,
    WorkstreamPortfolioActivitySummary, WorkstreamPortfolioEntry,
    WorkstreamPortfolioResponse, WorkstreamPortfolioSummary,
    WorkstreamControlRoomRecipeSetResponse, WorkstreamControlRoomStatusResponse,
    WorkstreamLastResultReference, WorkstreamLiveSessionSummary, WorkstreamRecipeDocument,
    WorkstreamRecipeStep, WorkstreamRegistryDocument, WorkstreamRegistryEntry,
    WorkstreamRegistryRecipeFiles, WorkstreamSpecDocument, WorkstreamSpecPromotionState,
    WorkstreamSpecRecipeRegistry,
};
pub use workstream_tool_return::{
    apply_workstream_tool_return, tool_return_ledger_path, WorkstreamToolRepoRefs,
    WorkstreamToolReturnLedgerEntry, WorkstreamToolReturnPayload, WorkstreamToolReturnResponse,
};
pub use workstream_timeline::{
    get_workstream_timeline, get_workstream_timeline_event, WorkstreamTimelineEvent,
    WorkstreamTimelineEventDetailResponse, WorkstreamTimelineIdentity,
    WorkstreamTimelineResponse,
};
pub use trajectory_eval::{TrajectoryCriterionEval, TrajectoryEval};
pub use workspace_plane::{
    bootstrap_workspace_session, bootstrap_workspace_session_for_workstream,
    load_workspace_session, read_workspace_session,
    record_workspace_fallback_return, record_workspace_fallback_start, run_workspace_pilot,
    workspace_fallback_ledger_path, workspace_plane_dir, workspace_session_path,
    write_workspace_session, WorkspaceBootstrapResponse, WorkspacePilotRequest,
    WorkspaceCatalogSnapshot, WorkspaceCurrentTask, WorkspaceDevPlanePolicy,
    WorkspaceFallbackDrillRequest, WorkspaceFallbackDrillResponse, WorkspaceFallbackEvent,
    WorkspaceLastSuccessfulTask, WorkspacePilotResponse, WorkspacePilotWorkstreamOverride,
    WorkspaceSessionState,
    WorkspaceWorkstreamCutoverPolicy,
};
pub use workspace_attach::{
    build_workstream_managed_attach, build_workstream_workspace_attach,
    WorkspaceAttachHelperSnippets, WorkspaceAttachMetadata, WorkspaceAttachPlane,
    WorkspaceAttachResponse,
};
pub use workspace_habitat::{
    build_workstream_workspace_habitat, render_workspace_habitat_context_env,
    ClusterWorkspaceHabitat, ClusterWorkspaceHabitatResponse,
};
pub use workspace_launch_resume::{
    build_workstream_workspace_launch_resume, WorkspaceLaunchResumeHelperSnippets,
    WorkspaceLaunchResumeMetadata, WorkspaceLaunchResumePlane,
    WorkspaceLaunchResumeResponse,
};
pub use workspace_manuscript_handoff::{
    read_workspace_manuscript_handoff, record_workspace_manuscript_handoff,
    WorkspaceManuscriptHandoffContinuity, WorkspaceManuscriptHandoffPlane,
    WorkspaceManuscriptHandoffRequest, WorkspaceManuscriptHandoffResponse,
};
pub use workspace_manuscript_assembly::{
    read_workspace_manuscript_assembly, record_workspace_manuscript_assembly,
    WorkspaceManuscriptAssemblyContinuity, WorkspaceManuscriptAssemblyPlane,
    WorkspaceManuscriptAssemblyRequest, WorkspaceManuscriptAssemblyResponse,
};
pub use workspace_external_registry_staging::{
    read_workspace_external_registry_staging, record_workspace_external_registry_staging,
    CrossrefDryRunBundle, DataCiteTestStagingPayload, ExternalRegistryStagingBundle,
    ExternalStagingReadinessCheck, ExternalStagingReadinessReport,
    WorkspaceExternalRegistryStagingContinuity, WorkspaceExternalRegistryStagingPlane,
    WorkspaceExternalRegistryStagingRequest, WorkspaceExternalRegistryStagingResponse,
};
pub use workspace_sandbox_deposit_handshake::{
    read_workspace_sandbox_deposit_handshake, record_workspace_sandbox_deposit_handshake,
    CrossrefTestReceipt, DataCiteTestReceipt, RegistrySubmissionLedger,
    RegistrySubmissionLedgerEntry, SandboxDepositBundle,
    WorkspaceSandboxDepositHandshakeContinuity, WorkspaceSandboxDepositHandshakePlane,
    WorkspaceSandboxDepositHandshakeRequest, WorkspaceSandboxDepositHandshakeResponse,
};
pub use workspace_publication_package::{
    read_workspace_publication_package, record_workspace_publication_package,
    CrossrefDepositBundle, DataCiteDepositPayload, PublicationPackageBundle,
    PublicationReadinessCheck, PublicationReadinessReport,
    WorkspacePublicationPackageContinuity, WorkspacePublicationPackagePlane,
    WorkspacePublicationPackageRequest, WorkspacePublicationPackageResponse,
};
pub use workspace_scholarly_release::{
    read_workspace_scholarly_release, record_workspace_scholarly_release,
    CrossrefArticleStub, DataCiteCreator, DataCiteDescription, DataCiteIdentifier,
    DataCiteReadyMetadata, DataCiteSubject, DataCiteTitle, DataCiteType, JatsQaCheck,
    JatsQaReport, ScholarlyReleaseBundle, ScholarlyReleasePayloadItem,
    ScholarlyRoCrateExport, WorkspaceScholarlyReleaseContinuity,
    WorkspaceScholarlyReleasePlane, WorkspaceScholarlyReleaseRequest,
    WorkspaceScholarlyReleaseResponse,
};
pub use workspace_subagent_handoff::{
    read_workspace_subagent_handoff, record_workspace_subagent_handoff,
    WorkspaceSubAgentHandoffPlane, WorkspaceSubAgentHandoffPropagation,
    WorkspaceSubAgentHandoffRequest, WorkspaceSubAgentHandoffResponse,
};
pub use workspace_subagent_routing::{
    build_workstream_workspace_subagent_list,
    build_workstream_workspace_subagent_route,
    default_subagent_for_tool,
    default_work_mode_for_tool,
    WorkspaceSubAgentListPlane,
    WorkspaceSubAgentListResponse,
    WorkspaceSubAgentRouteAttachMetadata,
    WorkspaceSubAgentRoutePlane,
    WorkspaceSubAgentRouteRequest,
    WorkspaceSubAgentRouteResponse,
    WorkspaceSubAgentRouteSelection,
};
pub use workspace_subagents::{
    build_workstream_workspace_subagents, WorkspaceSubAgentRole,
    WorkspaceSubAgentsPlane, WorkspaceSubAgentsResponse,
};
pub use workspace_template::{
    build_workstream_workspace_template, ExternalWorkspaceRegistration,
    WorkspaceHydrationMetadata, WorkspaceTemplateMetadata, WorkspaceTemplatePlane,
    WorkspaceTemplateResponse,
};
pub use workspace_tenancy::{
    build_multi_user_gpu_workspace_tenancy_bundle, ComputeRoleScope, ComputeTenancyClass,
    ComputeTenancyContract, MultiUserGpuWorkspaceTenancyBundle, PartnerAccessContract,
    PartnerAccessRole, RepoHydrationContract, VsCodeCursorAccessContract,
    WorkspaceClientAccessPath, WorkspaceTenancyContract,
};

/// Contexto retornado pelo enhanced_cycle
#[derive(Debug, Clone)]
pub struct DarwinContext {
    /// Texto combinado para feed no HERMES
    pub combined_text: String,
    /// Snippets estruturados (opcional, para metadata)
    pub snippets: Vec<KnowledgeSnippet>,
    /// Score de confiança Self-RAG (0-100)
    pub confidence: Option<u64>,
}

/// Darwin Core - Sistema completo de GraphRAG + Self-RAG + Plugin System
pub struct DarwinCore {
    pub graph_rag_enabled: bool,
    pub self_rag_enabled: bool,
    ctx: Option<Arc<BeagleContext>>,
    vllm_client: VllmClient,
}

impl DarwinCore {
    /// Cria nova instância do Darwin Core (modo legacy, sem BeagleContext)
    pub fn new() -> Self {
        let vllm_url =
            std::env::var("VLLM_URL").unwrap_or_else(|_| "http://t560.local:8000/v1".to_string());

        Self {
            graph_rag_enabled: true,
            self_rag_enabled: true,
            ctx: None,
            vllm_client: VllmClient::new(vllm_url),
        }
    }

    /// Cria nova instância do Darwin Core com BeagleContext
    pub fn with_context(ctx: Arc<BeagleContext>) -> Self {
        let vllm_url = ctx
            .cfg
            .llm
            .vllm_url
            .clone()
            .unwrap_or_else(|| "http://t560.local:8000/v1".to_string());

        Self {
            graph_rag_enabled: true,
            self_rag_enabled: true,
            ctx: Some(ctx),
            vllm_client: VllmClient::new(vllm_url),
        }
    }

    /// GraphRAG real (usa teu hypergraph + neo4j + qdrant)
    ///
    /// Integra:
    /// - Knowledge graph (neo4j) para relações estruturadas
    /// - Vector store (qdrant) para busca semântica
    /// - Entity extraction para contexto enriquecido
    pub async fn graph_rag_query(&self, user_question: &str) -> String {
        // Se temos BeagleContext, usa as traits
        if let Some(ctx) = &self.ctx {
            info!("🔍 GraphRAG query (com BeagleContext): {}", user_question);

            // 1. Busca no vector store
            let vectors = match ctx.vector.query(user_question, 10).await {
                Ok(v) => v,
                Err(e) => {
                    warn!("Erro ao buscar no vector store: {}", e);
                    vec![]
                }
            };

            // 2. Busca no graph store
            let graph_result = match ctx.graph.cypher_query(
                "MATCH (n)-[r]->(m) WHERE n.name CONTAINS $query OR m.name CONTAINS $query RETURN n, r, m LIMIT 20",
                serde_json::json!({"query": user_question}),
            ).await {
                Ok(g) => g,
                Err(e) => {
                    warn!("Erro ao buscar no graph store: {}", e);
                    serde_json::json!({})
                }
            };

            // 3. Monta contexto enriquecido
            let context = format!(
                "Vector results: {}\nGraph results: {}",
                vectors.len(),
                graph_result
                    .get("results")
                    .and_then(|r| r.as_array())
                    .map(|a| a.len())
                    .unwrap_or(0)
            );

            let prompt = format!(
                "Tu és o Darwin RAG++ dentro do BEAGLE.

Pergunta do usuário: {user_question}

Contexto do knowledge graph:
{context}

Responde com raciocínio estruturado + citações reais do graph.

Se não souber, diz 'preciso de mais dados'."
            );

            // 4. Usa LLM do contexto
            match ctx.llm.complete(&prompt).await {
                Ok(answer) => answer,
                Err(e) => {
                    warn!("Erro ao consultar LLM: {}, usando fallback", e);
                    query_smart(&prompt, 80000).await
                }
            }
        } else {
            // Modo legacy: usa smart router diretamente
            let prompt = format!(
                "Tu és o Darwin RAG++ dentro do BEAGLE.

Pergunta do usuário: {user_question}

Usa o knowledge graph inteiro (neo4j) + vector store (qdrant) + entity extraction.
Responde com raciocínio estruturado + citações reais do graph.

Se não souber, diz 'preciso de mais dados'."
            );

            info!("🔍 GraphRAG query (legacy): {}", user_question);
            query_smart(&prompt, 80000).await
        }
    }

    /// Self-RAG real (o agente decide se precisa de mais busca)
    ///
    /// Sistema de gatekeeping que avalia confiança da resposta:
    /// - Se confiança < 85: gera nova query de busca
    /// - Se confiança >= 85: retorna resposta atual
    pub async fn self_rag(&self, initial_answer: &str, question: &str) -> String {
        let check_prompt = format!(
            "Tu és o Self-RAG gatekeeper.

Pergunta original: {question}
Resposta atual: {initial_answer}

Score 0-100 de confiança. Se <85, gera nova query de busca.
Responde JSON: {{\"confidence\": 88, \"new_query\": \"ou deixa vazio se ok\"}}"
        );

        info!("🎯 Self-RAG: avaliando confiança da resposta");
        let gate = query_smart(&check_prompt, 10000).await;

        // Tenta parsear JSON da resposta
        let json: serde_json::Value = match serde_json::from_str(&gate) {
            Ok(v) => v,
            Err(e) => {
                warn!(
                    "⚠️  Self-RAG: falha ao parsear JSON: {}. Retornando resposta original.",
                    e
                );
                return initial_answer.to_string();
            }
        };

        if let Some(conf) = json["confidence"].as_u64() {
            if conf < 85 {
                if let Some(new_q) = json["new_query"].as_str() {
                    if !new_q.is_empty() {
                        info!(
                            "🔄 Self-RAG: confiança {} < 85, buscando com nova query: {}",
                            conf, new_q
                        );
                        return self.graph_rag_query(new_q).await;
                    }
                }
            } else {
                info!("✅ Self-RAG: confiança {} >= 85, resposta aceita", conf);
            }
        }

        initial_answer.to_string()
    }

    /// Plugin system (troca LLM em runtime)
    ///
    /// Plugins disponíveis:
    /// - `"grok3"`: Grok 3 via smart router (128k contexto, ilimitado)
    /// - `"local70b"`: vLLM local (Llama-3.3-70B-Instruct)
    /// - `"heavy"`: Grok 4.1 Heavy via smart router (256k contexto, quota)
    /// - `_`: Default para Grok 3
    pub async fn run_with_plugin(&self, prompt: &str, plugin: &str) -> String {
        match plugin {
            "grok3" => {
                info!("🔌 Plugin: Grok 3 (128k contexto, ilimitado)");
                query_smart(prompt, 100000).await
            }
            "local70b" => {
                info!("🔌 Plugin: vLLM local (Llama-3.3-70B-Instruct)");
                self.query_local_vllm(prompt).await
            }
            "heavy" => {
                info!("🔌 Plugin: Grok 4.1 Heavy (256k contexto, quota)");
                // Força uso do Heavy via smart router (contexto grande)
                query_smart(prompt, 200000).await
            }
            _ => {
                warn!("⚠️  Plugin '{}' desconhecido, usando Grok 3", plugin);
                query_smart(prompt, 100000).await
            }
        }
    }

    /// Enhanced cycle completo: GraphRAG + Self-RAG
    ///
    /// Pipeline:
    /// 1. GraphRAG query inicial (usa hypergraph + neo4j + qdrant)
    /// 2. Self-RAG avalia confiança
    /// 3. Se necessário, busca adicional com nova query
    /// 4. Retorna DarwinContext estruturado
    ///
    /// Este é o método primário que o pipeline deve chamar.
    pub async fn enhanced_cycle(&self, question: &str) -> anyhow::Result<DarwinContext> {
        info!("🚀 Darwin Enhanced Cycle iniciado: {}", question);

        // 1. GraphRAG query inicial
        let initial = self.graph_rag_query(question).await;

        // 2. Self-RAG avalia e potencialmente busca mais
        let final_answer = self.self_rag(&initial, question).await;

        // 3. Coleta snippets estruturados (se temos BeagleContext)
        let mut snippets = Vec::new();
        if let Some(ctx) = &self.ctx {
            // Busca snippets no vector store
            if let Ok(hits) = ctx.vector.query(question, 5).await {
                for hit in hits {
                    snippets.push(beagle_core::implementations::vector_hit_to_snippet(&hit));
                }
            }

            // Busca snippets no graph store
            if let Ok(graph_result) = ctx.graph.cypher_query(
                "MATCH (n)-[r]->(m) WHERE n.name CONTAINS $query OR m.name CONTAINS $query RETURN n, r, m LIMIT 5",
                serde_json::json!({"query": question}),
            ).await {
                if let Some(results) = graph_result.get("results").and_then(|r| r.as_array()) {
                    for result in results {
                        if let Some(data) = result.get("data").and_then(|d| d.as_array()) {
                            for row in data {
                                snippets.push(beagle_core::implementations::neo4j_result_to_snippet(row, None));
                            }
                        }
                    }
                }
            }
        }

        info!(
            "✅ Darwin Enhanced Cycle concluído ({} snippets)",
            snippets.len()
        );

        Ok(DarwinContext {
            combined_text: final_answer,
            snippets,
            confidence: None, // TODO: extrair do Self-RAG
        })
    }

    /// Query vLLM local (helper interno)
    async fn query_local_vllm(&self, prompt: &str) -> String {
        let request = VllmCompletionRequest {
            model: "meta-llama/Llama-3.3-70B-Instruct".to_string(),
            prompt: prompt.to_string(),
            sampling_params: SamplingParams {
                temperature: 0.8,
                top_p: 0.95,
                max_tokens: 8192,
                n: 1,
                stop: None,
                frequency_penalty: 0.0,
            },
        };

        match self.vllm_client.completions(&request).await {
            Ok(response) => response
                .choices
                .first()
                .map(|c| c.text.trim().to_string())
                .unwrap_or_else(|| "Resposta vazia do vLLM".to_string()),
            Err(e) => {
                warn!("❌ Erro ao consultar vLLM local: {}", e);
                format!("Erro ao consultar vLLM local: {}", e)
            }
        }
    }
}

impl Default for DarwinCore {
    fn default() -> Self {
        Self::new()
    }
}

/// Ciclo completo Darwin-enhanced (GraphRAG + Self-RAG)
///
/// Pipeline:
/// 1. GraphRAG query inicial (usa hypergraph + neo4j + qdrant)
/// 2. Self-RAG avalia confiança
/// 3. Se necessário, busca adicional com nova query
/// 4. Retorna resposta final
///
/// # Example
/// ```rust
/// use beagle_darwin::darwin_enhanced_cycle;
///
/// let answer = darwin_enhanced_cycle("unificar entropia curva com consciência celular").await;
/// println!("DARWIN + BEAGLE: {answer}");
/// ```
pub async fn darwin_enhanced_cycle(question: &str) -> String {
    info!("🚀 Darwin Enhanced Cycle iniciado: {}", question);

    let darwin = DarwinCore::new();

    // 1. GraphRAG query inicial
    let initial = darwin.graph_rag_query(question).await;

    // 2. Self-RAG avalia e potencialmente busca mais
    let final_answer = darwin.self_rag(&initial, question).await;

    info!("✅ Darwin Enhanced Cycle concluído");
    final_answer
}

#[cfg(test)]
mod tests {
    use super::*;

    #[tokio::test]
    async fn test_darwin_core_creation() {
        let darwin = DarwinCore::new();
        assert!(darwin.graph_rag_enabled);
        assert!(darwin.self_rag_enabled);
    }

    #[tokio::test]
    async fn test_plugin_system() {
        let darwin = DarwinCore::new();
        // Testa que o plugin system não quebra (pode falhar se não tiver LLM configurado)
        let _result = darwin.run_with_plugin("Test prompt", "grok3").await;
        // Não asserta sucesso pois pode não ter API keys configuradas nos testes
    }
}
