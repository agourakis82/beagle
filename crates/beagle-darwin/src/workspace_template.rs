use crate::workspace_habitat::ClusterWorkspaceHabitat;
use crate::workspace_launch_resume::{
    build_workstream_workspace_launch_resume, WorkspaceLaunchResumePlane,
    WorkspaceLaunchResumeResponse,
};
use crate::{WorkstreamContextPacket, WorkstreamContextPacketResponse};
use beagle_config::BeagleConfig;
use serde::Serialize;

const WORKSPACE_TEMPLATE_PHASE: &str = "B20.6";
const WORKSPACE_TEMPLATE_VERSION: &str = "beagle-template-backed-prebuilt-workspace-v1";
const WORKSPACE_TEMPLATE_KIND: &str = "workspace-template";
const WORKSPACE_TEMPLATE_API_PREFIX: &str = "/api/darwin/workstreams";

#[derive(Debug, Clone, Serialize)]
pub struct ExternalWorkspaceRegistration {
    pub registration_kind: String,
    pub registration_state: String,
    pub external_workspace_kind: String,
    pub stable_workspace_alias: String,
    pub recommended_client: String,
    pub browser_url: String,
    pub launch_resume_path: String,
    pub managed_attach_path: String,
    pub registration_file: String,
    pub note: String,
}

#[derive(Debug, Clone, Serialize)]
pub struct WorkspaceHydrationMetadata {
    pub warm_start_strategy: String,
    pub startup_mode: String,
    pub warm_start_ready: bool,
    pub reproducible_ready: bool,
    pub prebuilt_snapshot_expected: bool,
    pub hydrated_startup_path: String,
    pub workspace_root: String,
    pub context_dir: String,
    pub repo_root: String,
    pub repo_remote_url: String,
    pub repo_branch: String,
    pub template_file: String,
    pub registration_file: String,
    pub hydration_file: String,
}

#[derive(Debug, Clone, Serialize)]
pub struct WorkspaceTemplateMetadata {
    pub template_id: String,
    pub template_version: String,
    pub template_contract_kind: String,
    pub reproducibility_mode: String,
    pub external_workspace_compatible: bool,
    pub attach_method: String,
    pub managed_attach_state: String,
    pub stable_attach_alias: String,
    pub browser_fallback_ready: bool,
    pub cursor_managed_attach_ready: bool,
    pub template_file: String,
    pub registration_file: String,
    pub hydration_file: String,
    pub context_packet_file: String,
    pub context_env_file: String,
    pub handoff_ref: String,
    pub context_packet_ref: String,
    pub launch_resume_path: String,
}

#[derive(Debug, Clone, Serialize)]
pub struct WorkspaceTemplatePlane {
    pub template_version: String,
    pub template_kind: String,
    pub workstream_id: String,
    pub workspace_id: String,
    pub session_id: String,
    pub repo: String,
    pub branch: String,
    pub governance_state: String,
    pub default_dev_plane: String,
    pub vm_fallback_role: String,
    pub program_id: Option<String>,
    pub campaign_id: Option<String>,
    pub workspace_template_path: String,
    pub workspace_launch_resume_path: String,
    pub managed_attach_path: String,
    pub workspace_habitat_path: String,
    pub workspace_habitat_env_path: String,
    pub context_packet_path: String,
    pub handoff_path: String,
    pub last_result_path: String,
    pub note: String,
    pub metadata: WorkspaceTemplateMetadata,
    pub hydration: WorkspaceHydrationMetadata,
    pub external_registration: ExternalWorkspaceRegistration,
}

#[derive(Debug, Clone, Serialize)]
pub struct WorkspaceTemplateResponse {
    pub status: String,
    pub phase: String,
    pub template: WorkspaceTemplatePlane,
    pub launch: WorkspaceLaunchResumePlane,
    pub habitat: ClusterWorkspaceHabitat,
    pub context_packet: WorkstreamContextPacket,
}

pub fn build_workstream_workspace_template(
    cfg: &BeagleConfig,
    workstream_id: &str,
    context_packet: WorkstreamContextPacketResponse,
) -> anyhow::Result<WorkspaceTemplateResponse> {
    let launch_response = build_workstream_workspace_launch_resume(cfg, workstream_id, context_packet)?;
    Ok(workspace_template_from_launch_resume(launch_response))
}

fn workspace_template_from_launch_resume(
    launch_response: WorkspaceLaunchResumeResponse,
) -> WorkspaceTemplateResponse {
    let launch = launch_response.launch.clone();
    let habitat = launch_response.habitat.clone();
    let packet = launch_response.context_packet.clone();
    let stable_alias = launch.launch_metadata.stable_launch_alias.clone();
    let template_path = format!(
        "{}/{}/workspace-template",
        WORKSPACE_TEMPLATE_API_PREFIX, packet.workstream_id
    );

    let template = WorkspaceTemplatePlane {
        template_version: WORKSPACE_TEMPLATE_VERSION.to_string(),
        template_kind: WORKSPACE_TEMPLATE_KIND.to_string(),
        workstream_id: packet.workstream_id.clone(),
        workspace_id: packet.workspace_id.clone(),
        session_id: packet.session_id.clone(),
        repo: packet.repo.clone(),
        branch: packet.branch.clone(),
        governance_state: packet.governance_state.clone(),
        default_dev_plane: habitat.default_dev_plane.clone(),
        vm_fallback_role: habitat.vm_fallback_role.clone(),
        program_id: habitat.program_id.clone(),
        campaign_id: habitat.campaign_id.clone(),
        workspace_template_path: template_path.clone(),
        workspace_launch_resume_path: launch.workspace_launch_resume_path.clone(),
        managed_attach_path: launch.managed_attach_path.clone(),
        workspace_habitat_path: habitat.habitat_path.clone(),
        workspace_habitat_env_path: habitat.context_env_path.clone(),
        context_packet_path: habitat.context_packet_path.clone(),
        handoff_path: launch.handoff_path.clone(),
        last_result_path: launch.last_result_path.clone(),
        note: "The template-backed workspace plane keeps the Beagle-owned workspace/session identity intact while freezing a reproducible workspace contract, a warm-start hydration path, and an external-workspace-compatible registration shape.".to_string(),
        metadata: WorkspaceTemplateMetadata {
            template_id: format!("beagle-template-{}", packet.workspace_id),
            template_version: WORKSPACE_TEMPLATE_VERSION.to_string(),
            template_contract_kind: "template-backed-external-workspace-contract".to_string(),
            reproducibility_mode: "template-backed-prehydrated-pvc".to_string(),
            external_workspace_compatible: true,
            attach_method: launch.launch_metadata.attach_method.clone(),
            managed_attach_state: launch.launch_metadata.managed_attach_state.clone(),
            stable_attach_alias: stable_alias.clone(),
            browser_fallback_ready: launch.launch_metadata.browser_fallback_ready,
            cursor_managed_attach_ready: launch.launch_metadata.cursor_managed_attach_ready,
            template_file: habitat.template_file.clone(),
            registration_file: habitat.external_registration_file.clone(),
            hydration_file: habitat.hydration_file.clone(),
            context_packet_file: habitat.context_packet_file.clone(),
            context_env_file: habitat.context_env_file.clone(),
            handoff_ref: launch.launch_metadata.handoff_ref.clone(),
            context_packet_ref: launch.launch_metadata.context_packet_ref.clone(),
            launch_resume_path: launch.workspace_launch_resume_path.clone(),
        },
        hydration: WorkspaceHydrationMetadata {
            warm_start_strategy: "template-backed-prehydrated-pvc".to_string(),
            startup_mode: "prehydrated-snapshot".to_string(),
            warm_start_ready: true,
            reproducible_ready: true,
            prebuilt_snapshot_expected: true,
            hydrated_startup_path: "pvc-hydrated-workspace-snapshot".to_string(),
            workspace_root: habitat.workspace_root.clone(),
            context_dir: habitat.context_dir.clone(),
            repo_root: habitat.workspace_root.clone(),
            repo_remote_url: format!("https://github.com/{}.git", packet.repo),
            repo_branch: packet.branch.clone(),
            template_file: habitat.template_file.clone(),
            registration_file: habitat.external_registration_file.clone(),
            hydration_file: habitat.hydration_file.clone(),
        },
        external_registration: ExternalWorkspaceRegistration {
            registration_kind: "coder-compatible-external-workspace".to_string(),
            registration_state: "template-backed-registered".to_string(),
            external_workspace_kind: "managed-private-remote-workspace".to_string(),
            stable_workspace_alias: stable_alias,
            recommended_client: launch.launch_metadata.recommended_client.clone(),
            browser_url: habitat.browser_url.clone(),
            launch_resume_path: launch.workspace_launch_resume_path.clone(),
            managed_attach_path: launch.managed_attach_path.clone(),
            registration_file: habitat.external_registration_file.clone(),
            note: "This registration stays private/internal, keeps Beagle as the system of truth, and remains compatible with coder-style Remote-SSH attach without creating a second canonical workspace state.".to_string(),
        },
    };

    WorkspaceTemplateResponse {
        status: "ok".to_string(),
        phase: WORKSPACE_TEMPLATE_PHASE.to_string(),
        template,
        launch,
        habitat,
        context_packet: packet,
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::{
        WorkstreamContextPacket, WorkstreamContextPacketExperimentFlags,
        WorkstreamContextPacketHandoff, WorkstreamContextPacketLastResult,
        WorkstreamContextPacketPhysioSnapshot, WorkstreamContextPacketRecipe,
        WorkstreamContextPacketResponse,
    };
    use beagle_config::{
        AdvancedModulesConfig, BeagleConfig, ConsumerAccessConfig, GraphConfig, HermesConfig,
        LlmConfig, ObserverThresholds, StorageConfig, ToolBridgeConfig, WorkspaceHabitatConfig,
        WorkspacePlaneConfig,
    };
    use chrono::Utc;

    fn packet() -> WorkstreamContextPacketResponse {
        WorkstreamContextPacketResponse {
            status: "ok".to_string(),
            phase: "B18.1".to_string(),
            packet: WorkstreamContextPacket {
                packet_version: "beagle-memory-aware-context-packet-v1".to_string(),
                workstream_id: "beagle-darwin-hpc-governance".to_string(),
                workspace_id: "beagle-cluster-pilot".to_string(),
                session_id: "ws-cluster-workspace-habitat".to_string(),
                repo: "agourakis82/beagle".to_string(),
                branch: "feat/darwin-hpc-governance".to_string(),
                governance_state: "canonical".to_string(),
                handoff: WorkstreamContextPacketHandoff {
                    handoff_required: true,
                    recovery_required: true,
                    handoff_present: true,
                    last_handoff: Some("resume from managed launch".to_string()),
                },
                last_result: WorkstreamContextPacketLastResult {
                    available: false,
                    reference: None,
                    summary: None,
                    manifest: None,
                    error: None,
                },
                last_successful_task: None,
                latest_physio: Some(WorkstreamContextPacketPhysioSnapshot {
                    hr: Some(72.0),
                    hrv_level: Some("steady".to_string()),
                    spo2: Some(98.0),
                    timestamp: Some(Utc::now()),
                    source: Some("observer-smoke".to_string()),
                }),
                experiment_flags: Some(WorkstreamContextPacketExperimentFlags {
                    hrv_aware: Some(true),
                    observer_enabled: Some(true),
                    serendipity_enabled: Some(false),
                    triad_enabled: Some(false),
                    provider: Some("xai".to_string()),
                    model: Some("grok-4-1-fast-reasoning".to_string()),
                    experiment_id: Some("beagle_exp_002_hrv_aware_vs_blind".to_string()),
                    condition: Some("hrv_aware".to_string()),
                }),
                memory_hits: Vec::new(),
                retrieval_context: None,
                recommended_recipe: Some(WorkstreamContextPacketRecipe {
                    id: "beagle-darwin-hpc-governance.operator_cpu_loop".to_string(),
                    kind: "operator_cpu_loop".to_string(),
                    summary: "Resume with the bounded CPU operator loop.".to_string(),
                }),
                bounded_study_baseline: None,
            },
        }
    }

    fn test_config() -> BeagleConfig {
        let mut cfg = BeagleConfig {
            profile: "cluster".to_string(),
            safe_mode: true,
            api_token: Some("test-token".to_string()),
            llm: LlmConfig::default(),
            storage: StorageConfig {
                data_dir: "/tmp/beagle-workspace-template-tests".to_string(),
            },
            graph: GraphConfig::default(),
            hermes: HermesConfig::default(),
            tool_bridge: ToolBridgeConfig::default(),
            workspace: WorkspacePlaneConfig {
                canonical_workspace_id: "beagle-cluster-pilot".to_string(),
                canonical_repo: "agourakis82/beagle".to_string(),
                canonical_branch: "feat/darwin-hpc-governance".to_string(),
                canonical_track: "darwin-hpc".to_string(),
                operator_name: Some("test-operator".to_string()),
                default_dev_plane: "beagle-cluster".to_string(),
                vm_fallback_role: "fallback-only".to_string(),
                promotion_scope: "beagle-darwin-hpc-general-noninfra".to_string(),
                cutover_workstream: "beagle-darwin-hpc-governance".to_string(),
                cutover_state: "canonical".to_string(),
                cutover_last_transition: "resume".to_string(),
                cutover_branch_lineage: "feat/darwin-hpc-governance".to_string(),
                cutover_default_profile: "cpu-short-v1".to_string(),
                cutover_batch_profile: "cpu-batch-v1".to_string(),
                cutover_advanced_profile: "gpu-single-v1".to_string(),
                cutover_result_publication: "object-backed".to_string(),
                cutover_result_retrieval: "object-backed".to_string(),
                cutover_result_retention_policy: "active".to_string(),
                cutover_operator_consumer_policy: "full".to_string(),
                cutover_research_consumer_policy: "bounded".to_string(),
                cutover_recovery_required: true,
                cutover_handoff_required: true,
                bootstrap_enabled: true,
                habitat: WorkspaceHabitatConfig::default(),
            },
            consumers: ConsumerAccessConfig::default(),
            advanced: AdvancedModulesConfig::default(),
            observer: ObserverThresholds::default(),
        };
        cfg.workspace.habitat.ssh_enabled = true;
        cfg.workspace.habitat.ssh_service_port = 2222;
        cfg.workspace.habitat.ssh_user = "openvscode-server".to_string();
        cfg
    }

    #[test]
    fn workspace_template_uses_same_identity_as_launch_resume() {
        let cfg = test_config();
        let response = build_workstream_workspace_template(
            &cfg,
            "beagle-darwin-hpc-governance",
            packet(),
        )
        .expect("workspace template");

        assert_eq!(response.phase, "B20.6");
        assert_eq!(response.template.workstream_id, "beagle-darwin-hpc-governance");
        assert_eq!(response.template.workspace_id, "beagle-cluster-pilot");
        assert_eq!(response.template.session_id, "ws-cluster-workspace-habitat");
        assert_eq!(
            response.template.workspace_template_path,
            "/api/darwin/workstreams/beagle-darwin-hpc-governance/workspace-template"
        );
        assert_eq!(
            response.template.workspace_launch_resume_path,
            "/api/darwin/workstreams/beagle-darwin-hpc-governance/workspace-launch-resume"
        );
        assert_eq!(
            response.template.metadata.stable_attach_alias,
            "beagle-cluster-pilot.coder"
        );
    }

    #[test]
    fn workspace_template_derives_reproducible_warm_contract_metadata() {
        let cfg = test_config();
        let response = build_workstream_workspace_template(
            &cfg,
            "beagle-darwin-hpc-governance",
            packet(),
        )
        .expect("workspace template");

        assert_eq!(
            response.template.metadata.template_id,
            "beagle-template-beagle-cluster-pilot"
        );
        assert_eq!(
            response.template.metadata.reproducibility_mode,
            "template-backed-prehydrated-pvc"
        );
        assert!(response.template.metadata.external_workspace_compatible);
        assert_eq!(
            response.template.metadata.template_file,
            "/workspace/beagle/.beagle/context/workspace-template.json"
        );
        assert_eq!(
            response.template.metadata.registration_file,
            "/workspace/beagle/.beagle/context/external-workspace-registration.json"
        );
        assert_eq!(
            response.template.metadata.hydration_file,
            "/workspace/beagle/.beagle/context/workspace-hydration.json"
        );
        assert_eq!(
            response.template.hydration.startup_mode,
            "prehydrated-snapshot"
        );
        assert!(response.template.hydration.warm_start_ready);
        assert_eq!(
            response.template.external_registration.registration_kind,
            "coder-compatible-external-workspace"
        );
        assert_eq!(
            response.template.external_registration.registration_state,
            "template-backed-registered"
        );
    }
}
