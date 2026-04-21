use crate::{
    resolve_program_campaign_binding_for_workstream, WorkstreamContextPacket,
    WorkstreamContextPacketResponse,
};
use beagle_config::{resolve_workspace_habitat_binding, BeagleConfig};
use serde::Serialize;

const WORKSPACE_HABITAT_PHASE: &str = "B20.1";
const WORKSPACE_HABITAT_VERSION: &str = "beagle-cluster-workspace-habitat-v1";
const WORKSPACE_HABITAT_API_PREFIX: &str = "/api/darwin/workstreams";
const WORKSPACE_HABITAT_PAGE_PREFIX: &str = "/darwin/workstreams";

#[derive(Debug, Clone, Serialize)]
pub struct ClusterWorkspaceHabitat {
    pub habitat_version: String,
    pub ide_kind: String,
    pub ssh_enabled: bool,
    pub ssh_service_port: u16,
    pub ssh_user: String,
    pub workstream_id: String,
    pub workspace_id: String,
    pub session_id: String,
    pub repo: String,
    pub branch: String,
    pub governance_state: String,
    pub default_dev_plane: String,
    pub vm_fallback_role: String,
    pub promotion_scope: String,
    pub namespace: String,
    pub service_name: String,
    pub internal_base_url: String,
    pub browser_url: String,
    pub health_url: String,
    pub cockpit_path: String,
    pub habitat_path: String,
    pub context_packet_path: String,
    pub context_env_path: String,
    pub workspace_root: String,
    pub context_dir: String,
    pub context_packet_file: String,
    pub context_env_file: String,
    pub template_file: String,
    pub external_registration_file: String,
    pub hydration_file: String,
    pub subagents_file: String,
    pub subagents_dir: String,
    pub devcontainer_dir: String,
    pub program_id: Option<String>,
    pub campaign_id: Option<String>,
}

#[derive(Debug, Clone, Serialize)]
pub struct ClusterWorkspaceHabitatResponse {
    pub status: String,
    pub phase: String,
    pub habitat: ClusterWorkspaceHabitat,
    pub context_packet: WorkstreamContextPacket,
}

pub fn build_workstream_workspace_habitat(
    cfg: &BeagleConfig,
    workstream_id: &str,
    context_packet: WorkstreamContextPacketResponse,
) -> anyhow::Result<ClusterWorkspaceHabitatResponse> {
    let binding = resolve_program_campaign_binding_for_workstream(workstream_id).ok().flatten();
    let habitat_cfg = resolve_workspace_habitat_binding(cfg, workstream_id);
    let fallback_habitat_cfg = &cfg.workspace.habitat;
    let workstream_id = context_packet.packet.workstream_id.clone();
    let workspace_id = if context_packet.packet.workspace_id.trim().is_empty() {
        habitat_cfg
            .as_ref()
            .map(|binding| binding.workspace_id.clone())
            .unwrap_or_else(|| cfg.workspace.canonical_workspace_id.clone())
    } else {
        context_packet.packet.workspace_id.clone()
    };
    let session_id = if context_packet.packet.session_id.trim().is_empty()
        || context_packet.packet.session_id == "unassigned-session"
    {
        habitat_cfg
            .as_ref()
            .map(|binding| binding.session_id.clone())
            .filter(|value| !value.trim().is_empty() && value != "unassigned-session")
            .unwrap_or_else(|| context_packet.packet.session_id.clone())
    } else {
        context_packet.packet.session_id.clone()
    };
    let repo = if context_packet.packet.repo.trim().is_empty() {
        habitat_cfg
            .as_ref()
            .map(|binding| binding.canonical_repo.clone())
            .unwrap_or_else(|| context_packet.packet.repo.clone())
    } else {
        context_packet.packet.repo.clone()
    };
    let branch = if context_packet.packet.branch.trim().is_empty() {
        habitat_cfg
            .as_ref()
            .map(|binding| binding.canonical_branch.clone())
            .unwrap_or_else(|| context_packet.packet.branch.clone())
    } else {
        context_packet.packet.branch.clone()
    };
    let ide_kind = habitat_cfg
        .as_ref()
        .map(|binding| binding.ide_kind.clone())
        .unwrap_or_else(|| fallback_habitat_cfg.ide_kind.clone());
    let ssh_enabled = habitat_cfg
        .as_ref()
        .map(|binding| binding.ssh_enabled)
        .unwrap_or(fallback_habitat_cfg.ssh_enabled);
    let ssh_service_port = habitat_cfg
        .as_ref()
        .map(|binding| binding.ssh_service_port)
        .unwrap_or(fallback_habitat_cfg.ssh_service_port);
    let ssh_user = habitat_cfg
        .as_ref()
        .map(|binding| binding.ssh_user.clone())
        .unwrap_or_else(|| fallback_habitat_cfg.ssh_user.clone());
    let namespace = habitat_cfg
        .as_ref()
        .map(|binding| binding.namespace.clone())
        .unwrap_or_else(|| fallback_habitat_cfg.namespace.clone());
    let service_name = habitat_cfg
        .as_ref()
        .map(|binding| binding.service_name.clone())
        .unwrap_or_else(|| fallback_habitat_cfg.service_name.clone());
    let internal_base_url = habitat_cfg
        .as_ref()
        .map(|binding| binding.internal_base_url.clone())
        .unwrap_or_else(|| fallback_habitat_cfg.internal_base_url.clone());
    let health_path = habitat_cfg
        .as_ref()
        .map(|binding| binding.health_path.clone())
        .unwrap_or_else(|| fallback_habitat_cfg.health_path.clone());
    let workspace_root = habitat_cfg
        .as_ref()
        .map(|binding| binding.workspace_root.clone())
        .unwrap_or_else(|| fallback_habitat_cfg.workspace_root.clone());
    let context_dir = habitat_cfg
        .as_ref()
        .map(|binding| binding.context_dir.clone())
        .unwrap_or_else(|| fallback_habitat_cfg.context_dir.clone());
    let context_packet_file = habitat_cfg
        .as_ref()
        .map(|binding| binding.context_packet_file.clone())
        .unwrap_or_else(|| fallback_habitat_cfg.context_packet_file.clone());
    let context_env_file = habitat_cfg
        .as_ref()
        .map(|binding| binding.context_env_file.clone())
        .unwrap_or_else(|| fallback_habitat_cfg.context_env_file.clone());
    let default_dev_plane = habitat_cfg
        .as_ref()
        .map(|binding| binding.default_dev_plane.clone())
        .unwrap_or_else(|| cfg.workspace.default_dev_plane.clone());
    let vm_fallback_role = habitat_cfg
        .as_ref()
        .map(|binding| binding.vm_fallback_role.clone())
        .unwrap_or_else(|| cfg.workspace.vm_fallback_role.clone());
    let promotion_scope = habitat_cfg
        .as_ref()
        .map(|binding| binding.promotion_scope.clone())
        .unwrap_or_else(|| cfg.workspace.promotion_scope.clone());

    let habitat = ClusterWorkspaceHabitat {
        habitat_version: WORKSPACE_HABITAT_VERSION.to_string(),
        ide_kind,
        ssh_enabled,
        ssh_service_port,
        ssh_user,
        workstream_id: workstream_id.clone(),
        workspace_id: workspace_id.clone(),
        session_id,
        repo,
        branch,
        governance_state: context_packet.packet.governance_state.clone(),
        default_dev_plane,
        vm_fallback_role,
        promotion_scope,
        namespace,
        service_name,
        internal_base_url: internal_base_url.clone(),
        browser_url: internal_base_url.clone(),
        health_url: format!(
            "{}{}",
            internal_base_url.trim_end_matches('/'),
            health_path
        ),
        cockpit_path: format!(
            "{}/{}/cockpit",
            WORKSPACE_HABITAT_PAGE_PREFIX, workstream_id
        ),
        habitat_path: format!(
            "{}/{}/workspace-habitat",
            WORKSPACE_HABITAT_API_PREFIX, workstream_id
        ),
        context_packet_path: format!(
            "{}/{}/context-packet",
            WORKSPACE_HABITAT_API_PREFIX, workstream_id
        ),
        context_env_path: format!(
            "{}/{}/workspace-habitat/context.env",
            WORKSPACE_HABITAT_API_PREFIX, workstream_id
        ),
        workspace_root: workspace_root.clone(),
        context_dir: context_dir.clone(),
        context_packet_file: context_packet_file.clone(),
        context_env_file: context_env_file.clone(),
        template_file: format!(
            "{}/workspace-template.json",
            context_dir.trim_end_matches('/')
        ),
        external_registration_file: format!(
            "{}/external-workspace-registration.json",
            context_dir.trim_end_matches('/')
        ),
        hydration_file: format!(
            "{}/workspace-hydration.json",
            context_dir.trim_end_matches('/')
        ),
        subagents_file: format!(
            "{}/workspace-subagents.json",
            context_dir.trim_end_matches('/')
        ),
        subagents_dir: format!(
            "{}/subagents",
            context_dir.trim_end_matches('/')
        ),
        devcontainer_dir: format!(
            "{}/.devcontainer",
            workspace_root.trim_end_matches('/')
        ),
        program_id: binding.as_ref().map(|binding| binding.program.id.clone()),
        campaign_id: binding.as_ref().map(|binding| binding.campaign.id.clone()),
    };

    Ok(ClusterWorkspaceHabitatResponse {
        status: "ok".to_string(),
        phase: WORKSPACE_HABITAT_PHASE.to_string(),
        habitat,
        context_packet: context_packet.packet,
    })
}

pub fn render_workspace_habitat_context_env(
    response: &ClusterWorkspaceHabitatResponse,
) -> String {
    let packet = &response.context_packet;
    let habitat = &response.habitat;
    let mut lines = vec![
        "# Beagle Cluster Workspace Habitat".to_string(),
        format!("# phase={}", response.phase),
        format!("export BEAGLE_WORKSTREAM_ID={}", shell_escape(&packet.workstream_id)),
        format!("export BEAGLE_WORKSPACE_ID={}", shell_escape(&packet.workspace_id)),
        format!("export BEAGLE_SESSION_ID={}", shell_escape(&packet.session_id)),
        format!("export BEAGLE_REPO={}", shell_escape(&packet.repo)),
        format!("export BEAGLE_BRANCH={}", shell_escape(&packet.branch)),
        format!(
            "export BEAGLE_GOVERNANCE_STATE={}",
            shell_escape(&packet.governance_state)
        ),
        format!(
            "export BEAGLE_DEFAULT_DEV_PLANE={}",
            shell_escape(&habitat.default_dev_plane)
        ),
        format!(
            "export BEAGLE_VM_FALLBACK_ROLE={}",
            shell_escape(&habitat.vm_fallback_role)
        ),
        format!(
            "export BEAGLE_PROMOTION_SCOPE={}",
            shell_escape(&habitat.promotion_scope)
        ),
        format!("export BEAGLE_IDE_KIND={}", shell_escape(&habitat.ide_kind)),
        format!(
            "export BEAGLE_WORKSPACE_SSH_ENABLED={}",
            shell_escape(if habitat.ssh_enabled { "true" } else { "false" })
        ),
        format!(
            "export BEAGLE_WORKSPACE_SSH_SERVICE_PORT={}",
            shell_escape(&habitat.ssh_service_port.to_string())
        ),
        format!(
            "export BEAGLE_WORKSPACE_SSH_USER={}",
            shell_escape(&habitat.ssh_user)
        ),
        format!(
            "export BEAGLE_WORKSPACE_BROWSER_URL={}",
            shell_escape(&habitat.browser_url)
        ),
        format!(
            "export BEAGLE_WORKSPACE_HEALTH_URL={}",
            shell_escape(&habitat.health_url)
        ),
        format!(
            "export BEAGLE_WORKSPACE_ROOT={}",
            shell_escape(&habitat.workspace_root)
        ),
        format!(
            "export BEAGLE_CONTEXT_DIR={}",
            shell_escape(&habitat.context_dir)
        ),
        format!(
            "export BEAGLE_CONTEXT_PACKET_FILE={}",
            shell_escape(&habitat.context_packet_file)
        ),
        format!(
            "export BEAGLE_CONTEXT_ENV_FILE={}",
            shell_escape(&habitat.context_env_file)
        ),
        format!(
            "export BEAGLE_WORKSPACE_TEMPLATE_FILE={}",
            shell_escape(&habitat.template_file)
        ),
        format!(
            "export BEAGLE_EXTERNAL_WORKSPACE_REGISTRATION_FILE={}",
            shell_escape(&habitat.external_registration_file)
        ),
        format!(
            "export BEAGLE_WORKSPACE_HYDRATION_FILE={}",
            shell_escape(&habitat.hydration_file)
        ),
        format!(
            "export BEAGLE_WORKSPACE_SUBAGENTS_FILE={}",
            shell_escape(&habitat.subagents_file)
        ),
        format!(
            "export BEAGLE_WORKSPACE_SUBAGENTS_DIR={}",
            shell_escape(&habitat.subagents_dir)
        ),
        format!(
            "export BEAGLE_WORKSPACE_DEVCONTAINER_DIR={}",
            shell_escape(&habitat.devcontainer_dir)
        ),
        format!(
            "export BEAGLE_CONTEXT_PACKET_PATH={}",
            shell_escape(&habitat.context_packet_path)
        ),
        format!(
            "export BEAGLE_WORKSPACE_TEMPLATE_PATH={}",
            shell_escape(&format!(
                "/api/darwin/workstreams/{}/workspace-template",
                packet.workstream_id
            ))
        ),
        format!(
            "export BEAGLE_HABITAT_PATH={}",
            shell_escape(&habitat.habitat_path)
        ),
        format!(
            "export BEAGLE_WORKSPACE_SUBAGENTS_PATH={}",
            shell_escape(&format!(
                "/api/darwin/workstreams/{}/workspace-subagents",
                packet.workstream_id
            ))
        ),
        format!(
            "export BEAGLE_CURSOR_REMOTE_LANE_PATH={}",
            shell_escape(&format!(
                "/api/darwin/workstreams/{}/cursor-remote-lane",
                packet.workstream_id
            ))
        ),
        format!(
            "export BEAGLE_CURSOR_NATIVE_ATTACH_PATH={}",
            shell_escape(&format!(
                "/api/darwin/workstreams/{}/cursor-native-attach",
                packet.workstream_id
            ))
        ),
        format!(
            "export BEAGLE_WORKSPACE_ATTACH_PATH={}",
            shell_escape(&format!(
                "/api/darwin/workstreams/{}/workspace-attach",
                packet.workstream_id
            ))
        ),
        format!(
            "export BEAGLE_WORKSPACE_ATTACH_HELPER={}",
            shell_escape(&format!(
                "{}/scripts/infrastructure/darwin-hpc/launch_workspace_attach.sh",
                habitat.workspace_root.trim_end_matches('/')
            ))
        ),
        format!(
            "export BEAGLE_MANAGED_ATTACH_PATH={}",
            shell_escape(&format!(
                "/api/darwin/workstreams/{}/managed-attach",
                packet.workstream_id
            ))
        ),
        format!(
            "export BEAGLE_MANAGED_ATTACH_INSTALLER={}",
            shell_escape(&format!(
                "{}/scripts/infrastructure/darwin-hpc/install_managed_workspace_attach.sh",
                habitat.workspace_root.trim_end_matches('/')
            ))
        ),
        format!(
            "export BEAGLE_MANAGED_ATTACH_PROXY={}",
            shell_escape(&format!(
                "{}/scripts/infrastructure/darwin-hpc/workspace_exec_proxy.sh",
                habitat.workspace_root.trim_end_matches('/')
            ))
        ),
        format!(
            "export BEAGLE_MANAGED_ATTACH_ALIAS={}",
            shell_escape(&format!("{}.coder", packet.workspace_id))
        ),
        format!(
            "export BEAGLE_WORKSPACE_LAUNCH_RESUME_PATH={}",
            shell_escape(&format!(
                "/api/darwin/workstreams/{}/workspace-launch-resume",
                packet.workstream_id
            ))
        ),
        format!(
            "export BEAGLE_WORKSPACE_LAUNCH_RESUME_HELPER={}",
            shell_escape(&format!(
                "{}/scripts/infrastructure/darwin-hpc/launch_managed_workspace_session.sh",
                habitat.workspace_root.trim_end_matches('/')
            ))
        ),
        format!(
            "export BEAGLE_COCKPIT_PATH={}",
            shell_escape(&habitat.cockpit_path)
        ),
        format!(
            "export BEAGLE_HANDOFF_PRESENT={}",
            shell_escape(if packet.handoff.handoff_present { "true" } else { "false" })
        ),
        format!(
            "export BEAGLE_LAST_HANDOFF={}",
            shell_escape(packet.handoff.last_handoff.as_deref().unwrap_or(""))
        ),
    ];

    lines.push(format!(
        "export BEAGLE_PROGRAM_ID={}",
        shell_escape(habitat.program_id.as_deref().unwrap_or(""))
    ));
    lines.push(format!(
        "export BEAGLE_CAMPAIGN_ID={}",
        shell_escape(habitat.campaign_id.as_deref().unwrap_or(""))
    ));

    if let Some(last_result) = packet.last_result.summary.as_ref() {
        lines.push(format!(
            "export BEAGLE_LAST_RESULT_JOB_ID={}",
            shell_escape(&last_result.job_id.to_string())
        ));
        lines.push(format!(
            "export BEAGLE_LAST_RESULT_RUN_LABEL={}",
            shell_escape(&last_result.run_label)
        ));
        lines.push(format!(
            "export BEAGLE_LAST_RESULT_PROFILE_ID={}",
            shell_escape(&last_result.profile_id)
        ));
        lines.push(format!(
            "export BEAGLE_LAST_RESULT_MANIFEST_KEY={}",
            shell_escape(&last_result.manifest_key)
        ));
    } else {
        lines.push("export BEAGLE_LAST_RESULT_JOB_ID=''".to_string());
        lines.push("export BEAGLE_LAST_RESULT_RUN_LABEL=''".to_string());
        lines.push("export BEAGLE_LAST_RESULT_PROFILE_ID=''".to_string());
        lines.push("export BEAGLE_LAST_RESULT_MANIFEST_KEY=''".to_string());
    }

    if let Some(task) = packet.last_successful_task.as_ref() {
        lines.push(format!(
            "export BEAGLE_LAST_SUCCESSFUL_TASK_KIND={}",
            shell_escape(&task.task_kind)
        ));
        lines.push(format!(
            "export BEAGLE_LAST_SUCCESSFUL_TASK_PROFILE_ID={}",
            shell_escape(&task.profile_id)
        ));
        lines.push(format!(
            "export BEAGLE_LAST_SUCCESSFUL_TASK_RESULT_JOB_ID={}",
            shell_escape(&task.published_result_job_id.to_string())
        ));
    } else {
        lines.push("export BEAGLE_LAST_SUCCESSFUL_TASK_KIND=''".to_string());
        lines.push("export BEAGLE_LAST_SUCCESSFUL_TASK_PROFILE_ID=''".to_string());
        lines.push("export BEAGLE_LAST_SUCCESSFUL_TASK_RESULT_JOB_ID=''".to_string());
    }

    if let Some(recipe) = packet.recommended_recipe.as_ref() {
        lines.push(format!(
            "export BEAGLE_RECOMMENDED_RECIPE_ID={}",
            shell_escape(&recipe.id)
        ));
        lines.push(format!(
            "export BEAGLE_RECOMMENDED_RECIPE_KIND={}",
            shell_escape(&recipe.kind)
        ));
        lines.push(format!(
            "export BEAGLE_RECOMMENDED_RECIPE_SUMMARY={}",
            shell_escape(&recipe.summary)
        ));
    } else {
        lines.push("export BEAGLE_RECOMMENDED_RECIPE_ID=''".to_string());
        lines.push("export BEAGLE_RECOMMENDED_RECIPE_KIND=''".to_string());
        lines.push("export BEAGLE_RECOMMENDED_RECIPE_SUMMARY=''".to_string());
    }

    if let Some(snapshot) = packet.latest_physio.as_ref() {
        lines.push(format!(
            "export BEAGLE_LATEST_PHYSIO_SOURCE={}",
            shell_escape(snapshot.source.as_deref().unwrap_or(""))
        ));
        lines.push(format!(
            "export BEAGLE_LATEST_PHYSIO_HR={}",
            shell_escape(&snapshot.hr.map(|value| value.to_string()).unwrap_or_default())
        ));
        lines.push(format!(
            "export BEAGLE_LATEST_PHYSIO_HRV_LEVEL={}",
            shell_escape(snapshot.hrv_level.as_deref().unwrap_or(""))
        ));
        lines.push(format!(
            "export BEAGLE_LATEST_PHYSIO_SPO2={}",
            shell_escape(&snapshot.spo2.map(|value| value.to_string()).unwrap_or_default())
        ));
        lines.push(format!(
            "export BEAGLE_LATEST_PHYSIO_TIMESTAMP={}",
            shell_escape(
                &snapshot
                    .timestamp
                    .map(|value| value.to_rfc3339())
                    .unwrap_or_default()
            )
        ));
    } else {
        lines.push("export BEAGLE_LATEST_PHYSIO_SOURCE=''".to_string());
        lines.push("export BEAGLE_LATEST_PHYSIO_HR=''".to_string());
        lines.push("export BEAGLE_LATEST_PHYSIO_HRV_LEVEL=''".to_string());
        lines.push("export BEAGLE_LATEST_PHYSIO_SPO2=''".to_string());
        lines.push("export BEAGLE_LATEST_PHYSIO_TIMESTAMP=''".to_string());
    }

    lines.join("\n") + "\n"
}

fn shell_escape(value: &str) -> String {
    format!("'{}'", value.replace('\'', "'\"'\"'"))
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
                data_dir: "/tmp/beagle-workspace-habitat-tests".to_string(),
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
    fn workspace_habitat_derives_internal_urls_and_ids() {
        let cfg = test_config();
        let response = build_workstream_workspace_habitat(
            &cfg,
            "beagle-darwin-hpc-governance",
            packet(),
        )
        .expect("workspace habitat");

        assert_eq!(response.phase, "B20.1");
        assert_eq!(response.habitat.ide_kind, "openvscode-server");
        assert!(response.habitat.ssh_enabled);
        assert_eq!(response.habitat.ssh_service_port, 2222);
        assert_eq!(response.habitat.ssh_user, "openvscode-server");
        assert_eq!(response.habitat.workspace_id, "beagle-cluster-pilot");
        assert_eq!(
            response.habitat.context_env_path,
            "/api/darwin/workstreams/beagle-darwin-hpc-governance/workspace-habitat/context.env"
        );
        assert_eq!(
            response.habitat.template_file,
            "/workspace/beagle/.beagle/context/workspace-template.json"
        );
        assert_eq!(
            response.habitat.external_registration_file,
            "/workspace/beagle/.beagle/context/external-workspace-registration.json"
        );
        assert_eq!(
            response.habitat.hydration_file,
            "/workspace/beagle/.beagle/context/workspace-hydration.json"
        );
        assert_eq!(
            response.habitat.subagents_file,
            "/workspace/beagle/.beagle/context/workspace-subagents.json"
        );
        assert_eq!(
            response.habitat.subagents_dir,
            "/workspace/beagle/.beagle/context/subagents"
        );
        assert_eq!(
            response.habitat.devcontainer_dir,
            "/workspace/beagle/.devcontainer"
        );
        assert_eq!(response.habitat.health_url, "http://beagle-workspace.beagle.svc.cluster.local:8080/");
    }

    #[test]
    fn workspace_habitat_env_exports_required_context() {
        let cfg = test_config();
        let response = build_workstream_workspace_habitat(
            &cfg,
            "beagle-darwin-hpc-governance",
            packet(),
        )
        .expect("workspace habitat");
        let env_text = render_workspace_habitat_context_env(&response);

        assert!(env_text.contains("export BEAGLE_WORKSTREAM_ID='beagle-darwin-hpc-governance'"));
        assert!(env_text.contains("export BEAGLE_SESSION_ID='ws-cluster-workspace-habitat'"));
        assert!(env_text.contains("export BEAGLE_WORKSPACE_SSH_ENABLED='true'"));
        assert!(env_text.contains("export BEAGLE_WORKSPACE_SSH_SERVICE_PORT='2222'"));
        assert!(env_text.contains("export BEAGLE_WORKSPACE_SSH_USER='openvscode-server'"));
        assert!(env_text.contains("export BEAGLE_LATEST_PHYSIO_SOURCE='observer-smoke'"));
        assert!(env_text.contains(
            "export BEAGLE_CURSOR_REMOTE_LANE_PATH='/api/darwin/workstreams/beagle-darwin-hpc-governance/cursor-remote-lane'"
        ));
        assert!(env_text.contains(
            "export BEAGLE_CURSOR_NATIVE_ATTACH_PATH='/api/darwin/workstreams/beagle-darwin-hpc-governance/cursor-native-attach'"
        ));
        assert!(env_text.contains(
            "export BEAGLE_WORKSPACE_ATTACH_PATH='/api/darwin/workstreams/beagle-darwin-hpc-governance/workspace-attach'"
        ));
        assert!(env_text.contains(
            "export BEAGLE_WORKSPACE_ATTACH_HELPER='/workspace/beagle/scripts/infrastructure/darwin-hpc/launch_workspace_attach.sh'"
        ));
        assert!(env_text.contains(
            "export BEAGLE_MANAGED_ATTACH_PATH='/api/darwin/workstreams/beagle-darwin-hpc-governance/managed-attach'"
        ));
        assert!(env_text.contains(
            "export BEAGLE_MANAGED_ATTACH_INSTALLER='/workspace/beagle/scripts/infrastructure/darwin-hpc/install_managed_workspace_attach.sh'"
        ));
        assert!(env_text.contains(
            "export BEAGLE_MANAGED_ATTACH_PROXY='/workspace/beagle/scripts/infrastructure/darwin-hpc/workspace_exec_proxy.sh'"
        ));
        assert!(env_text.contains(
            "export BEAGLE_MANAGED_ATTACH_ALIAS='beagle-cluster-pilot.coder'"
        ));
        assert!(env_text.contains(
            "export BEAGLE_WORKSPACE_LAUNCH_RESUME_PATH='/api/darwin/workstreams/beagle-darwin-hpc-governance/workspace-launch-resume'"
        ));
        assert!(env_text.contains(
            "export BEAGLE_WORKSPACE_LAUNCH_RESUME_HELPER='/workspace/beagle/scripts/infrastructure/darwin-hpc/launch_managed_workspace_session.sh'"
        ));
        assert!(env_text.contains(
            "export BEAGLE_WORKSPACE_TEMPLATE_PATH='/api/darwin/workstreams/beagle-darwin-hpc-governance/workspace-template'"
        ));
        assert!(env_text.contains(
            "export BEAGLE_WORKSPACE_TEMPLATE_FILE='/workspace/beagle/.beagle/context/workspace-template.json'"
        ));
        assert!(env_text.contains(
            "export BEAGLE_EXTERNAL_WORKSPACE_REGISTRATION_FILE='/workspace/beagle/.beagle/context/external-workspace-registration.json'"
        ));
        assert!(env_text.contains(
            "export BEAGLE_WORKSPACE_HYDRATION_FILE='/workspace/beagle/.beagle/context/workspace-hydration.json'"
        ));
        assert!(env_text.contains(
            "export BEAGLE_WORKSPACE_SUBAGENTS_FILE='/workspace/beagle/.beagle/context/workspace-subagents.json'"
        ));
        assert!(env_text.contains(
            "export BEAGLE_WORKSPACE_SUBAGENTS_DIR='/workspace/beagle/.beagle/context/subagents'"
        ));
        assert!(env_text.contains(
            "export BEAGLE_WORKSPACE_DEVCONTAINER_DIR='/workspace/beagle/.devcontainer'"
        ));
        assert!(env_text.contains(
            "export BEAGLE_WORKSPACE_SUBAGENTS_PATH='/api/darwin/workstreams/beagle-darwin-hpc-governance/workspace-subagents'"
        ));
        assert!(env_text.contains(
            "export BEAGLE_RECOMMENDED_RECIPE_KIND='operator_cpu_loop'"
        ));
    }
}
