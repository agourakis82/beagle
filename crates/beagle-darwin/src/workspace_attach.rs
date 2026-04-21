use crate::cursor_remote_lane::{
    build_workstream_cursor_remote_lane, CursorRemoteLane, CursorRemoteLaneResponse,
};
use crate::workspace_habitat::ClusterWorkspaceHabitat;
use crate::{WorkstreamContextPacket, WorkstreamContextPacketResponse};
use beagle_config::BeagleConfig;
use serde::Serialize;

const WORKSPACE_ATTACH_PHASE: &str = "B20.3";
const WORKSPACE_ATTACH_VERSION: &str = "beagle-operator-friendly-attach-plane-v1";
const MANAGED_ATTACH_PHASE: &str = "B20.4";
const MANAGED_ATTACH_VERSION: &str = "beagle-managed-attach-plane-v1";
const WORKSPACE_ATTACH_KIND: &str = "workspace-attach";
const WORKSPACE_ATTACH_API_PREFIX: &str = "/api/darwin/workstreams";
const WORKSPACE_ATTACH_HELPER_REPO_PATH: &str =
    "scripts/infrastructure/darwin-hpc/launch_workspace_attach.sh";
const WORKSPACE_ATTACH_HELPER_STATE_DIR_PREFIX: &str = "~/.beagle/workspace-attach";
const MANAGED_ATTACH_HELPER_REPO_PATH: &str =
    "scripts/infrastructure/darwin-hpc/install_managed_workspace_attach.sh";
const MANAGED_ATTACH_PROXY_REPO_PATH: &str =
    "scripts/infrastructure/darwin-hpc/workspace_exec_proxy.sh";
const MANAGED_ATTACH_STATE_DIR_PREFIX: &str = "~/.beagle/managed-attach";
const MANAGED_ATTACH_PROXY_TARGET_HOST: &str = "127.0.0.1";

#[derive(Debug, Clone, Serialize)]
pub struct WorkspaceAttachMetadata {
    pub recommended_client: String,
    pub attach_method: String,
    pub attach_plane_kind: String,
    pub managed_attach_state: String,
    pub stable_attach_host_alias: String,
    pub ssh_host: Option<String>,
    pub ssh_port: Option<u16>,
    pub workspace_namespace: String,
    pub workspace_service_name: String,
    pub browser_url: String,
    pub browser_internal_url: String,
    pub browser_health_url: String,
    pub ssh_user: Option<String>,
    pub ssh_service_port: Option<u16>,
    pub internal_ssh_target: Option<String>,
    pub suggested_local_browser_port: u16,
    pub suggested_local_ssh_port: Option<u16>,
    pub repo_root: String,
    pub context_env_file: String,
    pub context_packet_file: String,
    pub managed_state_dir: String,
    pub helper_state_dir: String,
    pub attach_snippet_ref: String,
    pub attach_transport: String,
    pub proxy_command_template: Option<String>,
    pub handoff_ref: String,
    pub context_packet_ref: String,
}

#[derive(Debug, Clone, Serialize)]
pub struct WorkspaceAttachHelperSnippets {
    pub helper_script_repo_relative_path: String,
    pub helper_script_workspace_path: String,
    pub proxy_script_repo_relative_path: String,
    pub proxy_script_workspace_path: String,
    pub helper_command: String,
    pub browser_helper_command: String,
    pub ssh_helper_command: String,
    pub ssh_config_host_alias: String,
    pub ssh_config_snippet: String,
    pub ssh_command: String,
    pub cursor_remote_hint: String,
}

#[derive(Debug, Clone, Serialize)]
pub struct WorkspaceAttachPlane {
    pub attach_version: String,
    pub attach_kind: String,
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
    pub workspace_habitat_path: String,
    pub workspace_habitat_env_path: String,
    pub context_packet_path: String,
    pub managed_attach_path: String,
    pub handoff_path: String,
    pub last_result_path: String,
    pub cursor_remote_lane_path: String,
    pub cursor_native_attach_path: String,
    pub note: String,
    pub attach_metadata: WorkspaceAttachMetadata,
    pub helper_snippets: WorkspaceAttachHelperSnippets,
}

#[derive(Debug, Clone, Serialize)]
pub struct WorkspaceAttachResponse {
    pub status: String,
    pub phase: String,
    pub attach: WorkspaceAttachPlane,
    pub lane: CursorRemoteLane,
    pub habitat: ClusterWorkspaceHabitat,
    pub context_packet: WorkstreamContextPacket,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
enum AttachMode {
    HelperManaged,
    Managed,
}

pub fn build_workstream_workspace_attach(
    cfg: &BeagleConfig,
    workstream_id: &str,
    context_packet: WorkstreamContextPacketResponse,
) -> anyhow::Result<WorkspaceAttachResponse> {
    let lane_response = build_workstream_cursor_remote_lane(cfg, workstream_id, context_packet)?;
    Ok(attach_response_from_cursor_lane(
        lane_response,
        AttachMode::HelperManaged,
    ))
}

pub fn build_workstream_managed_attach(
    cfg: &BeagleConfig,
    workstream_id: &str,
    context_packet: WorkstreamContextPacketResponse,
) -> anyhow::Result<WorkspaceAttachResponse> {
    let lane_response = build_workstream_cursor_remote_lane(cfg, workstream_id, context_packet)?;
    Ok(attach_response_from_cursor_lane(
        lane_response,
        AttachMode::Managed,
    ))
}

fn attach_response_from_cursor_lane(
    lane_response: CursorRemoteLaneResponse,
    mode: AttachMode,
) -> WorkspaceAttachResponse {
    let lane = lane_response.lane.clone();
    let habitat = lane_response.habitat.clone();
    let packet = lane_response.context_packet.clone();

    let helper_state_dir = helper_state_dir(mode, &packet.workstream_id);
    let helper_script_repo_path = helper_script_repo_path(mode);
    let helper_script_workspace_path = format!(
        "{}/{}",
        habitat.workspace_root.trim_end_matches('/'),
        helper_script_repo_path
    );
    let proxy_script_repo_path = if mode == AttachMode::Managed {
        MANAGED_ATTACH_PROXY_REPO_PATH
    } else {
        ""
    };
    let proxy_script_workspace_path = if proxy_script_repo_path.is_empty() {
        String::new()
    } else {
        format!(
            "{}/{}",
            habitat.workspace_root.trim_end_matches('/'),
            proxy_script_repo_path
        )
    };
    let ssh_config_path = format!("{}/ssh_config", helper_state_dir);
    let known_hosts_path = format!("{}/known_hosts", helper_state_dir);
    let identity_file_path = format!("{}/ssh/id_ed25519", helper_state_dir);
    let ssh_user = lane.connection_metadata.ssh_user.clone();
    let ssh_service_port = lane.connection_metadata.ssh_service_port;
    let suggested_ssh_local_port = lane.connection_metadata.suggested_ssh_local_port;
    let host_alias = host_alias_for_workspace(mode, &packet.workspace_id);
    let managed_attach_state = managed_attach_state(mode, lane.connection_metadata.ssh_transport_ready);
    let handoff_path = format!(
        "{}/{}/handoff",
        WORKSPACE_ATTACH_API_PREFIX, packet.workstream_id
    );
    let context_packet_path = format!(
        "{}/{}/context-packet",
        WORKSPACE_ATTACH_API_PREFIX, packet.workstream_id
    );
    let managed_attach_path = format!(
        "{}/{}/managed-attach",
        WORKSPACE_ATTACH_API_PREFIX, packet.workstream_id
    );
    let proxy_command_template = managed_proxy_command_template(
        mode,
        &habitat,
        &helper_state_dir,
        ssh_service_port,
        suggested_ssh_local_port,
    );
    let ssh_config_snippet = ssh_config_snippet(
        mode,
        &host_alias,
        ssh_user.as_deref(),
        ssh_service_port,
        suggested_ssh_local_port,
        &identity_file_path,
        &known_hosts_path,
        proxy_command_template.as_deref(),
    );
    let helper_command = format!(
        "{} --workstream {} --client cursor",
        helper_script_repo_path, packet.workstream_id
    );
    let browser_helper_command = format!(
        "{} --workstream {} --client browser",
        helper_script_repo_path, packet.workstream_id
    );
    let ssh_helper_command = format!(
        "{} --workstream {} --client ssh",
        helper_script_repo_path, packet.workstream_id
    );
    let ssh_command = if mode == AttachMode::Managed {
        if ssh_service_port.is_some() {
            format!("ssh -F {} {}", ssh_config_path, host_alias)
        } else {
            String::new()
        }
    } else if suggested_ssh_local_port.is_some() {
        format!("ssh -F {} {}", ssh_config_path, host_alias)
    } else {
        String::new()
    };
    let cursor_remote_hint = if mode == AttachMode::Managed {
        format!(
            "Run `{}` once to install the managed attach plane, then use Cursor Remote-SSH with host `{}` and folder `{}`.",
            helper_command, host_alias, habitat.workspace_root
        )
    } else {
        format!(
            "Run `{}` to prepare the attach plane, then use Cursor Remote-SSH with host `{}` and folder `{}`.",
            helper_command, host_alias, habitat.workspace_root
        )
    };

    let attach = WorkspaceAttachPlane {
        attach_version: attach_version(mode).to_string(),
        attach_kind: WORKSPACE_ATTACH_KIND.to_string(),
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
        workspace_habitat_path: habitat.habitat_path.clone(),
        workspace_habitat_env_path: habitat.context_env_path.clone(),
        context_packet_path: habitat.context_packet_path.clone(),
        managed_attach_path: managed_attach_path.clone(),
        handoff_path: handoff_path.clone(),
        last_result_path: format!(
            "{}/{}/last-result",
            WORKSPACE_ATTACH_API_PREFIX, packet.workstream_id
        ),
        cursor_remote_lane_path: format!(
            "{}/{}/cursor-remote-lane",
            WORKSPACE_ATTACH_API_PREFIX, packet.workstream_id
        ),
        cursor_native_attach_path: format!(
            "{}/{}/cursor-native-attach",
            WORKSPACE_ATTACH_API_PREFIX, packet.workstream_id
        ),
        note: note_for_mode(mode).to_string(),
        attach_metadata: WorkspaceAttachMetadata {
            recommended_client: "cursor".to_string(),
            attach_method: attach_method(mode, lane.connection_metadata.ssh_transport_ready),
            attach_plane_kind: attach_plane_kind(mode).to_string(),
            managed_attach_state,
            stable_attach_host_alias: host_alias.clone(),
            ssh_host: ssh_host(mode, &host_alias),
            ssh_port: ssh_port(mode, ssh_service_port, suggested_ssh_local_port),
            workspace_namespace: habitat.namespace.clone(),
            workspace_service_name: habitat.service_name.clone(),
            browser_url: habitat.browser_url.clone(),
            browser_internal_url: habitat.browser_url.clone(),
            browser_health_url: habitat.health_url.clone(),
            ssh_user: lane.connection_metadata.ssh_user.clone(),
            ssh_service_port,
            internal_ssh_target: lane.connection_metadata.ssh_target.clone(),
            suggested_local_browser_port: lane.connection_metadata.suggested_local_port,
            suggested_local_ssh_port: suggested_ssh_local_port,
            repo_root: habitat.workspace_root.clone(),
            context_env_file: habitat.context_env_file.clone(),
            context_packet_file: habitat.context_packet_file.clone(),
            managed_state_dir: if mode == AttachMode::Managed {
                helper_state_dir.clone()
            } else {
                helper_state_dir.clone()
            },
            helper_state_dir,
            attach_snippet_ref: ssh_config_path.clone(),
            attach_transport: attach_transport(mode).to_string(),
            proxy_command_template,
            handoff_ref: handoff_path,
            context_packet_ref: context_packet_path,
        },
        helper_snippets: WorkspaceAttachHelperSnippets {
            helper_script_repo_relative_path: helper_script_repo_path.to_string(),
            helper_script_workspace_path,
            proxy_script_repo_relative_path: proxy_script_repo_path.to_string(),
            proxy_script_workspace_path,
            helper_command,
            browser_helper_command,
            ssh_helper_command,
            ssh_config_host_alias: host_alias.clone(),
            ssh_config_snippet,
            ssh_command,
            cursor_remote_hint,
        },
    };

    WorkspaceAttachResponse {
        status: "ok".to_string(),
        phase: attach_phase(mode).to_string(),
        attach,
        lane,
        habitat,
        context_packet: packet,
    }
}

fn attach_phase(mode: AttachMode) -> &'static str {
    match mode {
        AttachMode::HelperManaged => WORKSPACE_ATTACH_PHASE,
        AttachMode::Managed => MANAGED_ATTACH_PHASE,
    }
}

fn attach_version(mode: AttachMode) -> &'static str {
    match mode {
        AttachMode::HelperManaged => WORKSPACE_ATTACH_VERSION,
        AttachMode::Managed => MANAGED_ATTACH_VERSION,
    }
}

fn helper_script_repo_path(mode: AttachMode) -> &'static str {
    match mode {
        AttachMode::HelperManaged => WORKSPACE_ATTACH_HELPER_REPO_PATH,
        AttachMode::Managed => MANAGED_ATTACH_HELPER_REPO_PATH,
    }
}

fn helper_state_dir(mode: AttachMode, workstream_id: &str) -> String {
    let prefix = match mode {
        AttachMode::HelperManaged => WORKSPACE_ATTACH_HELPER_STATE_DIR_PREFIX,
        AttachMode::Managed => MANAGED_ATTACH_STATE_DIR_PREFIX,
    };
    format!("{}/{}", prefix, workstream_id)
}

fn host_alias_for_workspace(mode: AttachMode, workspace_id: &str) -> String {
    let mut alias = String::with_capacity(workspace_id.len());
    let mut last_dash = false;
    for ch in workspace_id.chars() {
        if ch.is_ascii_alphanumeric() {
            alias.push(ch.to_ascii_lowercase());
            last_dash = false;
        } else if !last_dash {
            alias.push('-');
            last_dash = true;
        }
    }

    let base = alias.trim_matches('-');
    match mode {
        AttachMode::HelperManaged => base.to_string(),
        AttachMode::Managed => format!("{}.coder", base),
    }
}

fn managed_attach_state(mode: AttachMode, ssh_ready: bool) -> String {
    match mode {
        AttachMode::HelperManaged => {
            if ssh_ready {
                "helper-managed-ready".to_string()
            } else {
                "browser-fallback-only".to_string()
            }
        }
        AttachMode::Managed => {
            if ssh_ready {
                "coder-compatible-ready".to_string()
            } else {
                "browser-fallback-only".to_string()
            }
        }
    }
}

fn managed_proxy_command_template(
    mode: AttachMode,
    habitat: &ClusterWorkspaceHabitat,
    managed_state_dir: &str,
    ssh_service_port: Option<u16>,
    suggested_ssh_local_port: Option<u16>,
) -> Option<String> {
    if mode != AttachMode::Managed {
        return None;
    }

    match (ssh_service_port, suggested_ssh_local_port) {
        (Some(remote_port), Some(local_port)) => Some(format!(
            "bash __BEAGLE_REPO_ROOT__/{proxy} --namespace {namespace} --service {service} --local-port {local_port} --remote-port {remote_port} --state-dir {state_dir}",
            proxy = MANAGED_ATTACH_PROXY_REPO_PATH,
            namespace = habitat.namespace,
            service = habitat.service_name,
            local_port = local_port,
            remote_port = remote_port,
            state_dir = managed_state_dir,
        )),
        _ => None,
    }
}

fn ssh_config_snippet(
    mode: AttachMode,
    host_alias: &str,
    ssh_user: Option<&str>,
    _ssh_service_port: Option<u16>,
    suggested_ssh_local_port: Option<u16>,
    identity_file_path: &str,
    known_hosts_path: &str,
    proxy_command_template: Option<&str>,
) -> String {
    match mode {
        AttachMode::HelperManaged => {
            if let (Some(local_port), Some(user)) = (suggested_ssh_local_port, ssh_user) {
                format!(
                    "Host {host_alias}\n  HostName 127.0.0.1\n  Port {local_port}\n  User {user}\n  IdentityFile {identity}\n  IdentitiesOnly yes\n  StrictHostKeyChecking no\n  UserKnownHostsFile {known_hosts}\n",
                    host_alias = host_alias,
                    local_port = local_port,
                    user = user,
                    identity = identity_file_path,
                    known_hosts = known_hosts_path,
                )
            } else {
                String::new()
            }
        }
        AttachMode::Managed => {
            if let (Some(local_port), Some(user), Some(proxy_command)) =
                (suggested_ssh_local_port, ssh_user, proxy_command_template)
            {
                format!(
                    "Host {host_alias}\n  HostName {host}\n  Port {local_port}\n  User {user}\n  IdentityFile {identity}\n  IdentitiesOnly yes\n  StrictHostKeyChecking no\n  UserKnownHostsFile {known_hosts}\n  ProxyCommand {proxy_command}\n",
                    host_alias = host_alias,
                    host = MANAGED_ATTACH_PROXY_TARGET_HOST,
                    local_port = local_port,
                    user = user,
                    identity = identity_file_path,
                    known_hosts = known_hosts_path,
                    proxy_command = proxy_command,
                )
            } else {
                String::new()
            }
        }
    }
}

fn attach_method(mode: AttachMode, ssh_ready: bool) -> String {
    match mode {
        AttachMode::HelperManaged => {
            if ssh_ready {
                "helper-managed-native-remote-ssh".to_string()
            } else {
                "helper-managed-browser".to_string()
            }
        }
        AttachMode::Managed => {
            if ssh_ready {
                "managed-coder-compatible-remote-ssh".to_string()
            } else {
                "managed-browser-fallback".to_string()
            }
        }
    }
}

fn attach_plane_kind(mode: AttachMode) -> &'static str {
    match mode {
        AttachMode::HelperManaged => "operator-friendly-cluster-internal",
        AttachMode::Managed => "managed-coder-compatible-cluster-internal",
    }
}

fn ssh_host(mode: AttachMode, _host_alias: &str) -> Option<String> {
    match mode {
        AttachMode::HelperManaged => Some("127.0.0.1".to_string()),
        AttachMode::Managed => Some(MANAGED_ATTACH_PROXY_TARGET_HOST.to_string()),
    }
}

fn ssh_port(
    mode: AttachMode,
    _ssh_service_port: Option<u16>,
    suggested_ssh_local_port: Option<u16>,
) -> Option<u16> {
    match mode {
        AttachMode::HelperManaged => suggested_ssh_local_port,
        AttachMode::Managed => suggested_ssh_local_port,
    }
}

fn attach_transport(mode: AttachMode) -> &'static str {
    match mode {
        AttachMode::HelperManaged => "kubernetes-port-forward+ssh",
        AttachMode::Managed => "managed-kubernetes-port-forward+ssh",
    }
}

fn note_for_mode(mode: AttachMode) -> &'static str {
    match mode {
        AttachMode::HelperManaged => {
            "The attach plane keeps the Beagle-owned workspace/session identity intact while collapsing browser, Remote-SSH, and helper metadata into one stable operator-facing surface."
        }
        AttachMode::Managed => {
            "The managed attach plane keeps the Beagle-owned workspace/session identity intact while promoting Cursor/SSH access from helper-managed flow to a coder-compatible stable alias and ProxyCommand path."
        }
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
                    last_handoff: Some("resume from workspace attach".to_string()),
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
                data_dir: "/tmp/beagle-workspace-attach-tests".to_string(),
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
    fn workspace_attach_uses_same_identity_as_cursor_lane() {
        let response = build_workstream_workspace_attach(
            &test_config(),
            "beagle-darwin-hpc-governance",
            packet(),
        )
        .expect("workspace attach");

        assert_eq!(response.status, "ok");
        assert_eq!(response.phase, "B20.3");
        assert_eq!(response.attach.workstream_id, "beagle-darwin-hpc-governance");
        assert_eq!(response.attach.workspace_id, "beagle-cluster-pilot");
        assert_eq!(response.attach.session_id, "ws-cluster-workspace-habitat");
        assert_eq!(
            response.attach.attach_metadata.attach_method,
            "helper-managed-native-remote-ssh"
        );
        assert_eq!(
            response.attach.cursor_remote_lane_path,
            "/api/darwin/workstreams/beagle-darwin-hpc-governance/cursor-remote-lane"
        );
        assert_eq!(
            response.attach.managed_attach_path,
            "/api/darwin/workstreams/beagle-darwin-hpc-governance/managed-attach"
        );
    }

    #[test]
    fn workspace_attach_derives_stable_helper_paths_and_snippets() {
        let response = build_workstream_workspace_attach(
            &test_config(),
            "beagle-darwin-hpc-governance",
            packet(),
        )
        .expect("workspace attach");

        assert_eq!(
            response.attach.attach_metadata.stable_attach_host_alias,
            "beagle-cluster-pilot"
        );
        assert_eq!(
            response.attach.helper_snippets.helper_command,
            "scripts/infrastructure/darwin-hpc/launch_workspace_attach.sh --workstream beagle-darwin-hpc-governance --client cursor"
        );
        assert!(
            response
                .attach
                .helper_snippets
                .ssh_config_snippet
                .contains("Host beagle-cluster-pilot")
        );
        assert!(
            response
                .attach
                .helper_snippets
                .ssh_config_snippet
                .contains("Port 18022")
        );
        assert!(
            response
                .attach
                .helper_snippets
                .cursor_remote_hint
                .contains("Cursor Remote-SSH")
        );
        assert_eq!(
            response.attach.attach_metadata.helper_state_dir,
            "~/.beagle/workspace-attach/beagle-darwin-hpc-governance"
        );
    }

    #[test]
    fn managed_attach_uses_same_identity_as_cursor_lane() {
        let response = build_workstream_managed_attach(
            &test_config(),
            "beagle-darwin-hpc-governance",
            packet(),
        )
        .expect("managed attach");

        assert_eq!(response.status, "ok");
        assert_eq!(response.phase, "B20.4");
        assert_eq!(response.attach.workstream_id, "beagle-darwin-hpc-governance");
        assert_eq!(response.attach.workspace_id, "beagle-cluster-pilot");
        assert_eq!(response.attach.session_id, "ws-cluster-workspace-habitat");
        assert_eq!(
            response.attach.attach_metadata.attach_method,
            "managed-coder-compatible-remote-ssh"
        );
        assert_eq!(
            response.attach.attach_metadata.managed_attach_state,
            "coder-compatible-ready"
        );
        assert_eq!(
            response.attach.managed_attach_path,
            "/api/darwin/workstreams/beagle-darwin-hpc-governance/managed-attach"
        );
    }

    #[test]
    fn managed_attach_derives_managed_alias_and_proxy_snippets() {
        let response = build_workstream_managed_attach(
            &test_config(),
            "beagle-darwin-hpc-governance",
            packet(),
        )
        .expect("managed attach");

        assert_eq!(
            response.attach.attach_metadata.stable_attach_host_alias,
            "beagle-cluster-pilot.coder"
        );
        assert_eq!(
            response.attach.helper_snippets.helper_command,
            "scripts/infrastructure/darwin-hpc/install_managed_workspace_attach.sh --workstream beagle-darwin-hpc-governance --client cursor"
        );
        assert!(
            response
                .attach
                .helper_snippets
                .ssh_config_snippet
                .contains("Host beagle-cluster-pilot.coder")
        );
        assert!(
            response
                .attach
                .helper_snippets
                .ssh_config_snippet
                .contains("ProxyCommand bash __BEAGLE_REPO_ROOT__/scripts/infrastructure/darwin-hpc/workspace_exec_proxy.sh")
        );
        assert!(
            response
                .attach
                .helper_snippets
                .cursor_remote_hint
                .contains("Cursor Remote-SSH")
        );
        assert_eq!(
            response.attach.attach_metadata.managed_state_dir,
            "~/.beagle/managed-attach/beagle-darwin-hpc-governance"
        );
        assert_eq!(
            response.attach.attach_metadata.attach_snippet_ref,
            "~/.beagle/managed-attach/beagle-darwin-hpc-governance/ssh_config"
        );
    }
}
