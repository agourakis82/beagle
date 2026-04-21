use crate::workspace_attach::{
    build_workstream_managed_attach, WorkspaceAttachPlane, WorkspaceAttachResponse,
};
use crate::workspace_habitat::ClusterWorkspaceHabitat;
use crate::{WorkstreamContextPacket, WorkstreamContextPacketResponse};
use beagle_config::BeagleConfig;
use serde::Serialize;

const WORKSPACE_LAUNCH_RESUME_PHASE: &str = "B20.5";
const WORKSPACE_LAUNCH_RESUME_VERSION: &str = "beagle-managed-workspace-launch-resume-v1";
const WORKSPACE_LAUNCH_RESUME_KIND: &str = "workspace-launch-resume";
const WORKSPACE_LAUNCH_RESUME_API_PREFIX: &str = "/api/darwin/workstreams";
const WORKSPACE_LAUNCH_RESUME_HELPER_REPO_PATH: &str =
    "scripts/infrastructure/darwin-hpc/launch_managed_workspace_session.sh";

#[derive(Debug, Clone, Serialize)]
pub struct WorkspaceLaunchResumeMetadata {
    pub recommended_client: String,
    pub launch_method: String,
    pub launch_state: String,
    pub attach_method: String,
    pub managed_attach_state: String,
    pub browser_fallback_ready: bool,
    pub cursor_managed_attach_ready: bool,
    pub stable_launch_alias: String,
    pub attach_transport: String,
    pub repo_root: String,
    pub launch_state_dir: String,
    pub workspace_habitat_env_path: String,
    pub handoff_ref: String,
    pub context_packet_ref: String,
    pub attach_snippet_ref: String,
    pub launch_helper_ref: String,
}

#[derive(Debug, Clone, Serialize)]
pub struct WorkspaceLaunchResumeHelperSnippets {
    pub helper_script_repo_relative_path: String,
    pub helper_script_workspace_path: String,
    pub cursor_resume_command: String,
    pub browser_resume_command: String,
    pub ssh_resume_command: String,
    pub ssh_config_host_alias: String,
    pub ssh_command: String,
    pub cursor_remote_hint: String,
}

#[derive(Debug, Clone, Serialize)]
pub struct WorkspaceLaunchResumePlane {
    pub launch_version: String,
    pub launch_kind: String,
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
    pub handoff_present: bool,
    pub last_result_ready: bool,
    pub recommended_recipe_id: Option<String>,
    pub recommended_recipe_kind: Option<String>,
    pub workspace_launch_resume_path: String,
    pub workspace_habitat_path: String,
    pub workspace_habitat_env_path: String,
    pub context_packet_path: String,
    pub managed_attach_path: String,
    pub cursor_remote_lane_path: String,
    pub cursor_native_attach_path: String,
    pub handoff_path: String,
    pub last_result_path: String,
    pub browser_url: String,
    pub note: String,
    pub launch_metadata: WorkspaceLaunchResumeMetadata,
    pub helper_snippets: WorkspaceLaunchResumeHelperSnippets,
}

#[derive(Debug, Clone, Serialize)]
pub struct WorkspaceLaunchResumeResponse {
    pub status: String,
    pub phase: String,
    pub launch: WorkspaceLaunchResumePlane,
    pub managed_attach: WorkspaceAttachPlane,
    pub habitat: ClusterWorkspaceHabitat,
    pub context_packet: WorkstreamContextPacket,
}

pub fn build_workstream_workspace_launch_resume(
    cfg: &BeagleConfig,
    workstream_id: &str,
    context_packet: WorkstreamContextPacketResponse,
) -> anyhow::Result<WorkspaceLaunchResumeResponse> {
    let managed_attach_response = build_workstream_managed_attach(cfg, workstream_id, context_packet)?;
    Ok(workspace_launch_resume_from_managed_attach(
        managed_attach_response,
    ))
}

fn workspace_launch_resume_from_managed_attach(
    managed_attach_response: WorkspaceAttachResponse,
) -> WorkspaceLaunchResumeResponse {
    let managed_attach = managed_attach_response.attach.clone();
    let habitat = managed_attach_response.habitat.clone();
    let packet = managed_attach_response.context_packet.clone();
    let helper_script_workspace_path = format!(
        "{}/{}",
        habitat.workspace_root.trim_end_matches('/'),
        WORKSPACE_LAUNCH_RESUME_HELPER_REPO_PATH
    );
    let cursor_resume_command = format!(
        "{} --workstream {} --client cursor",
        WORKSPACE_LAUNCH_RESUME_HELPER_REPO_PATH, packet.workstream_id
    );
    let browser_resume_command = format!(
        "{} --workstream {} --client browser",
        WORKSPACE_LAUNCH_RESUME_HELPER_REPO_PATH, packet.workstream_id
    );
    let ssh_resume_command = format!(
        "{} --workstream {} --client ssh",
        WORKSPACE_LAUNCH_RESUME_HELPER_REPO_PATH, packet.workstream_id
    );
    let browser_fallback_ready = !habitat.browser_url.trim().is_empty();
    let cursor_managed_attach_ready =
        managed_attach.attach_metadata.attach_method == "managed-coder-compatible-remote-ssh";
    let launch = WorkspaceLaunchResumePlane {
        launch_version: WORKSPACE_LAUNCH_RESUME_VERSION.to_string(),
        launch_kind: WORKSPACE_LAUNCH_RESUME_KIND.to_string(),
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
        handoff_present: packet.handoff.handoff_present,
        last_result_ready: packet.last_result.available,
        recommended_recipe_id: packet.recommended_recipe.as_ref().map(|recipe| recipe.id.clone()),
        recommended_recipe_kind: packet
            .recommended_recipe
            .as_ref()
            .map(|recipe| recipe.kind.clone()),
        workspace_launch_resume_path: format!(
            "{}/{}/workspace-launch-resume",
            WORKSPACE_LAUNCH_RESUME_API_PREFIX, packet.workstream_id
        ),
        workspace_habitat_path: habitat.habitat_path.clone(),
        workspace_habitat_env_path: habitat.context_env_path.clone(),
        context_packet_path: habitat.context_packet_path.clone(),
        managed_attach_path: managed_attach.managed_attach_path.clone(),
        cursor_remote_lane_path: managed_attach.cursor_remote_lane_path.clone(),
        cursor_native_attach_path: managed_attach.cursor_native_attach_path.clone(),
        handoff_path: managed_attach.handoff_path.clone(),
        last_result_path: managed_attach.last_result_path.clone(),
        browser_url: habitat.browser_url.clone(),
        note: "The launch/resume plane keeps the Beagle-owned workspace/session identity intact while collapsing tool dock resume, managed attach, browser fallback, and immediate context hydration into one operator-facing surface.".to_string(),
        launch_metadata: WorkspaceLaunchResumeMetadata {
            recommended_client: "cursor".to_string(),
            launch_method: "tool-dock-managed-workspace-launch-resume".to_string(),
            launch_state: if cursor_managed_attach_ready {
                "resume-ready".to_string()
            } else if browser_fallback_ready {
                "browser-fallback-only".to_string()
            } else {
                "launch-blocked".to_string()
            },
            attach_method: managed_attach.attach_metadata.attach_method.clone(),
            managed_attach_state: managed_attach.attach_metadata.managed_attach_state.clone(),
            browser_fallback_ready,
            cursor_managed_attach_ready,
            stable_launch_alias: managed_attach
                .attach_metadata
                .stable_attach_host_alias
                .clone(),
            attach_transport: managed_attach.attach_metadata.attach_transport.clone(),
            repo_root: managed_attach.attach_metadata.repo_root.clone(),
            launch_state_dir: managed_attach.attach_metadata.managed_state_dir.clone(),
            workspace_habitat_env_path: managed_attach.workspace_habitat_env_path.clone(),
            handoff_ref: managed_attach.attach_metadata.handoff_ref.clone(),
            context_packet_ref: managed_attach.attach_metadata.context_packet_ref.clone(),
            attach_snippet_ref: managed_attach.attach_metadata.attach_snippet_ref.clone(),
            launch_helper_ref: WORKSPACE_LAUNCH_RESUME_HELPER_REPO_PATH.to_string(),
        },
        helper_snippets: WorkspaceLaunchResumeHelperSnippets {
            helper_script_repo_relative_path: WORKSPACE_LAUNCH_RESUME_HELPER_REPO_PATH.to_string(),
            helper_script_workspace_path,
            cursor_resume_command: cursor_resume_command.clone(),
            browser_resume_command,
            ssh_resume_command,
            ssh_config_host_alias: managed_attach
                .helper_snippets
                .ssh_config_host_alias
                .clone(),
            ssh_command: managed_attach.helper_snippets.ssh_command.clone(),
            cursor_remote_hint: format!(
                "Run `{}` to resume the same Beagle-owned workspace/session envelope in Cursor, with immediate handoff and context packet hydration.",
                cursor_resume_command
            ),
        },
    };

    WorkspaceLaunchResumeResponse {
        status: "ok".to_string(),
        phase: WORKSPACE_LAUNCH_RESUME_PHASE.to_string(),
        launch,
        managed_attach,
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
                    experiment_id: None,
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
                data_dir: "/tmp/beagle-workspace-launch-resume-tests".to_string(),
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
        cfg.workspace.habitat.namespace = "beagle".to_string();
        cfg.workspace.habitat.service_name = "beagle-workspace".to_string();
        cfg.workspace.habitat.internal_base_url =
            "http://beagle-workspace.beagle.svc.cluster.local:8080".to_string();
        cfg.workspace.habitat.health_path = "/".to_string();
        cfg.workspace.habitat.ide_kind = "openvscode-server".to_string();
        cfg.workspace.habitat.workspace_root = "/workspace/beagle".to_string();
        cfg.workspace.habitat.context_dir = "/workspace/beagle/.beagle/context".to_string();
        cfg.workspace.habitat.context_env_file =
            "/workspace/beagle/.beagle/context/beagle-context.env".to_string();
        cfg.workspace.habitat.context_packet_file =
            "/workspace/beagle/.beagle/context/current-context-packet.json".to_string();
        cfg.workspace.habitat.ssh_enabled = true;
        cfg.workspace.habitat.ssh_service_port = 2222;
        cfg.workspace.habitat.ssh_user = "openvscode-server".to_string();
        cfg
    }

    #[test]
    fn workspace_launch_resume_uses_same_identity_as_managed_attach() {
        let response = build_workstream_workspace_launch_resume(
            &test_config(),
            "beagle-darwin-hpc-governance",
            packet(),
        )
        .expect("workspace launch resume");

        assert_eq!(response.status, "ok");
        assert_eq!(response.phase, "B20.5");
        assert_eq!(response.launch.workstream_id, "beagle-darwin-hpc-governance");
        assert_eq!(response.launch.workspace_id, "beagle-cluster-pilot");
        assert_eq!(response.launch.session_id, "ws-cluster-workspace-habitat");
        assert_eq!(
            response.launch.workspace_launch_resume_path,
            "/api/darwin/workstreams/beagle-darwin-hpc-governance/workspace-launch-resume"
        );
        assert_eq!(
            response.managed_attach.attach_metadata.attach_method,
            "managed-coder-compatible-remote-ssh"
        );
        assert_eq!(
            response.launch.launch_metadata.managed_attach_state,
            "coder-compatible-ready"
        );
    }

    #[test]
    fn workspace_launch_resume_derives_one_gesture_resume_metadata() {
        let response = build_workstream_workspace_launch_resume(
            &test_config(),
            "beagle-darwin-hpc-governance",
            packet(),
        )
        .expect("workspace launch resume");

        assert_eq!(
            response.launch.launch_metadata.launch_method,
            "tool-dock-managed-workspace-launch-resume"
        );
        assert_eq!(response.launch.launch_metadata.launch_state, "resume-ready");
        assert!(response.launch.launch_metadata.browser_fallback_ready);
        assert!(response.launch.launch_metadata.cursor_managed_attach_ready);
        assert_eq!(
            response.launch.launch_metadata.stable_launch_alias,
            "beagle-cluster-pilot.coder"
        );
        assert_eq!(
            response.launch.helper_snippets.cursor_resume_command,
            "scripts/infrastructure/darwin-hpc/launch_managed_workspace_session.sh --workstream beagle-darwin-hpc-governance --client cursor"
        );
        assert_eq!(
            response.launch.helper_snippets.browser_resume_command,
            "scripts/infrastructure/darwin-hpc/launch_managed_workspace_session.sh --workstream beagle-darwin-hpc-governance --client browser"
        );
        assert!(
            response
                .launch
                .helper_snippets
                .cursor_remote_hint
                .contains("Cursor")
        );
        assert_eq!(
            response.launch.launch_metadata.launch_helper_ref,
            "scripts/infrastructure/darwin-hpc/launch_managed_workspace_session.sh"
        );
        assert_eq!(
            response.launch.launch_metadata.attach_snippet_ref,
            "~/.beagle/managed-attach/beagle-darwin-hpc-governance/ssh_config"
        );
    }
}
