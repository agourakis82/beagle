use crate::workspace_habitat::{
    build_workstream_workspace_habitat, ClusterWorkspaceHabitat, ClusterWorkspaceHabitatResponse,
};
use crate::{WorkstreamContextPacket, WorkstreamContextPacketResponse};
use beagle_config::BeagleConfig;
use serde::Serialize;

const CURSOR_REMOTE_LANE_PHASE: &str = "B20.2a";
const CURSOR_REMOTE_LANE_VERSION: &str = "beagle-cursor-remote-lane-v2";
const CURSOR_REMOTE_LANE_KIND: &str = "cursor-remote-lane";
const CURSOR_REMOTE_LANE_API_PREFIX: &str = "/api/darwin/workstreams";
const CURSOR_REMOTE_LANE_SUGGESTED_HOST: &str = "127.0.0.1";
const CURSOR_REMOTE_LANE_SUGGESTED_LOCAL_PORT: u16 = 18080;
const CURSOR_REMOTE_LANE_SUGGESTED_SSH_LOCAL_PORT: u16 = 18022;

#[derive(Debug, Clone, Serialize)]
pub struct CursorRemoteLaneConnectionMetadata {
    pub remote_client: String,
    pub connection_mode: String,
    pub recommended_transport: String,
    pub ssh_transport_ready: bool,
    pub workspace_namespace: String,
    pub workspace_service_name: String,
    pub internal_base_url: String,
    pub browser_url: String,
    pub health_url: String,
    pub ssh_user: Option<String>,
    pub ssh_service_port: Option<u16>,
    pub ssh_target: Option<String>,
    pub workspace_root: String,
    pub context_dir: String,
    pub context_packet_file: String,
    pub context_env_file: String,
    pub context_packet_path: String,
    pub context_env_path: String,
    pub suggested_port_forward_host: String,
    pub suggested_local_port: u16,
    pub suggested_port_forward_command: String,
    pub suggested_ssh_local_port: Option<u16>,
    pub suggested_ssh_port_forward_command: Option<String>,
    pub suggested_ssh_command: Option<String>,
}

#[derive(Debug, Clone, Serialize)]
pub struct CursorRemoteLane {
    pub lane_version: String,
    pub lane_kind: String,
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
    pub cockpit_path: String,
    pub workspace_habitat_path: String,
    pub workspace_habitat_env_path: String,
    pub context_packet_path: String,
    pub tool_launch_path: String,
    pub tool_return_path: String,
    pub handoff_present: bool,
    pub last_result_ready: bool,
    pub recommended_recipe_id: Option<String>,
    pub recommended_recipe_kind: Option<String>,
    pub note: String,
    pub connection_metadata: CursorRemoteLaneConnectionMetadata,
}

#[derive(Debug, Clone, Serialize)]
pub struct CursorRemoteLaneResponse {
    pub status: String,
    pub phase: String,
    pub lane: CursorRemoteLane,
    pub habitat: ClusterWorkspaceHabitat,
    pub context_packet: WorkstreamContextPacket,
}

pub fn build_workstream_cursor_remote_lane(
    cfg: &BeagleConfig,
    workstream_id: &str,
    context_packet: WorkstreamContextPacketResponse,
) -> anyhow::Result<CursorRemoteLaneResponse> {
    let habitat_response = build_workstream_workspace_habitat(cfg, workstream_id, context_packet)?;
    Ok(cursor_remote_lane_from_habitat(habitat_response))
}

fn cursor_remote_lane_from_habitat(
    habitat_response: ClusterWorkspaceHabitatResponse,
) -> CursorRemoteLaneResponse {
    let habitat = habitat_response.habitat.clone();
    let packet = habitat_response.context_packet.clone();
    let lane = CursorRemoteLane {
        lane_version: CURSOR_REMOTE_LANE_VERSION.to_string(),
        lane_kind: CURSOR_REMOTE_LANE_KIND.to_string(),
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
        cockpit_path: habitat.cockpit_path.clone(),
        workspace_habitat_path: habitat.habitat_path.clone(),
        workspace_habitat_env_path: habitat.context_env_path.clone(),
        context_packet_path: habitat.context_packet_path.clone(),
        tool_launch_path: format!(
            "{}/{}/tool-dock/cursor",
            CURSOR_REMOTE_LANE_API_PREFIX, packet.workstream_id
        ),
        tool_return_path: format!(
            "{}/{}/tool-return",
            CURSOR_REMOTE_LANE_API_PREFIX, packet.workstream_id
        ),
        handoff_present: packet.handoff.handoff_present,
        last_result_ready: packet.last_result.available,
        recommended_recipe_id: packet.recommended_recipe.as_ref().map(|recipe| recipe.id.clone()),
        recommended_recipe_kind: packet
            .recommended_recipe
            .as_ref()
            .map(|recipe| recipe.kind.clone()),
        note: if habitat.ssh_enabled {
            "Cursor remains a premium client over the same Beagle-owned workspace/session envelope; canonical state stays in Beagle while the lane now exposes a native Remote-SSH-compatible attach path to the same cluster workspace.".to_string()
        } else {
            "Cursor remains a premium client over the same Beagle-owned workspace/session envelope; canonical state stays in Beagle while the current lane remains browser-first and port-forward-friendly.".to_string()
        },
        connection_metadata: CursorRemoteLaneConnectionMetadata {
            remote_client: "cursor".to_string(),
            connection_mode: if habitat.ssh_enabled {
                "same-workspace-remote-ssh".to_string()
            } else {
                "same-workspace-browser-first".to_string()
            },
            recommended_transport: if habitat.ssh_enabled {
                "kubernetes-port-forward+ssh".to_string()
            } else {
                "kubernetes-port-forward".to_string()
            },
            ssh_transport_ready: habitat.ssh_enabled,
            workspace_namespace: habitat.namespace.clone(),
            workspace_service_name: habitat.service_name.clone(),
            internal_base_url: habitat.internal_base_url.clone(),
            browser_url: habitat.browser_url.clone(),
            health_url: habitat.health_url.clone(),
            ssh_user: habitat.ssh_enabled.then(|| habitat.ssh_user.clone()),
            ssh_service_port: habitat.ssh_enabled.then_some(habitat.ssh_service_port),
            ssh_target: habitat.ssh_enabled.then(|| {
                format!(
                    "{}@{}.{}.svc.cluster.local:{}",
                    habitat.ssh_user, habitat.service_name, habitat.namespace, habitat.ssh_service_port
                )
            }),
            workspace_root: habitat.workspace_root.clone(),
            context_dir: habitat.context_dir.clone(),
            context_packet_file: habitat.context_packet_file.clone(),
            context_env_file: habitat.context_env_file.clone(),
            context_packet_path: habitat.context_packet_path.clone(),
            context_env_path: habitat.context_env_path.clone(),
            suggested_port_forward_host: CURSOR_REMOTE_LANE_SUGGESTED_HOST.to_string(),
            suggested_local_port: CURSOR_REMOTE_LANE_SUGGESTED_LOCAL_PORT,
            suggested_port_forward_command: format!(
                "kubectl -n {} port-forward service/{} {}:8080",
                habitat.namespace,
                habitat.service_name,
                CURSOR_REMOTE_LANE_SUGGESTED_LOCAL_PORT
            ),
            suggested_ssh_local_port: habitat
                .ssh_enabled
                .then_some(CURSOR_REMOTE_LANE_SUGGESTED_SSH_LOCAL_PORT),
            suggested_ssh_port_forward_command: habitat.ssh_enabled.then(|| {
                format!(
                    "kubectl -n {} port-forward service/{} {}:{}",
                    habitat.namespace,
                    habitat.service_name,
                    CURSOR_REMOTE_LANE_SUGGESTED_SSH_LOCAL_PORT,
                    habitat.ssh_service_port
                )
            }),
            suggested_ssh_command: habitat.ssh_enabled.then(|| {
                format!(
                    "ssh -p {} {}@127.0.0.1",
                    CURSOR_REMOTE_LANE_SUGGESTED_SSH_LOCAL_PORT, habitat.ssh_user
                )
            }),
        },
    };

    CursorRemoteLaneResponse {
        status: "ok".to_string(),
        phase: CURSOR_REMOTE_LANE_PHASE.to_string(),
        lane,
        habitat,
        context_packet: packet,
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::{
        WorkstreamContextPacketExperimentFlags, WorkstreamContextPacketHandoff,
        WorkstreamContextPacketLastResult, WorkstreamContextPacketPhysioSnapshot,
        WorkstreamContextPacketRecipe,
    };
    use beagle_config::{
        AdvancedModulesConfig, BeagleConfig, ConsumerAccessConfig, GraphConfig, HermesConfig,
        LlmConfig, ObserverThresholds, StorageConfig, ToolBridgeConfig, WorkspacePlaneConfig,
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
                    last_handoff: Some("resume from cluster workspace habitat".to_string()),
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
                data_dir: "/tmp/beagle-cursor-remote-lane-tests".to_string(),
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
                habitat: Default::default(),
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
    fn cursor_remote_lane_uses_same_workspace_identity_as_habitat() {
        let cfg = test_config();
        let response =
            build_workstream_cursor_remote_lane(&cfg, "beagle-darwin-hpc-governance", packet())
                .expect("cursor remote lane");

        assert_eq!(response.phase, "B20.2a");
        assert_eq!(response.lane.lane_kind, CURSOR_REMOTE_LANE_KIND);
        assert_eq!(response.lane.workstream_id, response.habitat.workstream_id);
        assert_eq!(response.lane.workspace_id, response.habitat.workspace_id);
        assert_eq!(response.lane.session_id, response.habitat.session_id);
        assert_eq!(response.lane.program_id, response.habitat.program_id);
        assert_eq!(response.lane.campaign_id, response.habitat.campaign_id);
    }

    #[test]
    fn cursor_remote_lane_derives_native_ssh_connection_metadata() {
        let cfg = test_config();
        let response =
            build_workstream_cursor_remote_lane(&cfg, "beagle-darwin-hpc-governance", packet())
                .expect("cursor remote lane");

        assert_eq!(response.habitat.ide_kind, "openvscode-server");
        assert_eq!(
            response.lane.connection_metadata.connection_mode,
            "same-workspace-remote-ssh"
        );
        assert!(response.lane.connection_metadata.ssh_transport_ready);
        assert_eq!(
            response.lane.connection_metadata.recommended_transport,
            "kubernetes-port-forward+ssh"
        );
        assert_eq!(
            response.lane.connection_metadata.ssh_user.as_deref(),
            Some("openvscode-server")
        );
        assert_eq!(response.lane.connection_metadata.ssh_service_port, Some(2222));
        assert_eq!(
            response.lane.connection_metadata.ssh_target.as_deref(),
            Some("openvscode-server@beagle-workspace.beagle.svc.cluster.local:2222")
        );
        assert_eq!(
            response.lane.connection_metadata.context_env_path,
            "/api/darwin/workstreams/beagle-darwin-hpc-governance/workspace-habitat/context.env"
        );
        assert_eq!(
            response
                .lane
                .connection_metadata
                .suggested_ssh_port_forward_command
                .as_deref(),
            Some("kubectl -n beagle port-forward service/beagle-workspace 18022:2222")
        );
        assert_eq!(
            response
                .lane
                .connection_metadata
                .suggested_ssh_command
                .as_deref(),
            Some("ssh -p 18022 openvscode-server@127.0.0.1")
        );
    }
}
