use crate::workspace_habitat::ClusterWorkspaceHabitat;
use crate::workspace_launch_resume::WorkspaceLaunchResumePlane;
use crate::workspace_template::{
    build_workstream_workspace_template, WorkspaceTemplatePlane, WorkspaceTemplateResponse,
};
use crate::{WorkstreamContextPacket, WorkstreamContextPacketResponse};
use beagle_config::BeagleConfig;
use serde::Serialize;

const WORKSPACE_SUBAGENTS_PHASE: &str = "B20.7";
const WORKSPACE_SUBAGENTS_VERSION: &str = "beagle-workspace-devcontainer-subagents-v1";
const WORKSPACE_SUBAGENTS_KIND: &str = "workspace-subagents";
const WORKSPACE_SUBAGENTS_API_PREFIX: &str = "/api/darwin/workstreams";

#[derive(Debug, Clone, Serialize)]
pub struct WorkspaceSubAgentRole {
    pub subagent_id: String,
    pub label: String,
    pub role: String,
    pub role_tag: String,
    pub access_state: String,
    pub specialization: String,
    pub recommended_work_modes: Vec<String>,
    pub default_tools: Vec<String>,
    pub devcontainer_kind: String,
    pub devcontainer_name: String,
    pub devcontainer_config_file: String,
    pub env_file: String,
    pub workspace_folder: String,
    pub repo_focus_paths: Vec<String>,
    pub recommended_client: String,
    pub attach_method: String,
    pub managed_attach_state: String,
    pub stable_attach_alias: String,
    pub launch_resume_path: String,
    pub managed_attach_path: String,
    pub browser_url: String,
    pub shell_entry_hint: String,
    pub note: String,
}

#[derive(Debug, Clone, Serialize)]
pub struct WorkspaceSubAgentsPlane {
    pub subagents_version: String,
    pub subagents_kind: String,
    pub workstream_id: String,
    pub workspace_id: String,
    pub session_id: String,
    pub repo: String,
    pub branch: String,
    pub governance_state: String,
    pub workspace_subagents_path: String,
    pub workspace_subagent_handoff_path: String,
    pub subagents_file: String,
    pub subagents_dir: String,
    pub devcontainer_dir: String,
    pub attach_method: String,
    pub managed_attach_state: String,
    pub stable_attach_alias: String,
    pub browser_fallback_ready: bool,
    pub cursor_managed_attach_ready: bool,
    pub note: String,
    pub roles: Vec<WorkspaceSubAgentRole>,
}

#[derive(Debug, Clone, Serialize)]
pub struct WorkspaceSubAgentsResponse {
    pub status: String,
    pub phase: String,
    pub subagents: WorkspaceSubAgentsPlane,
    pub template: WorkspaceTemplatePlane,
    pub launch: WorkspaceLaunchResumePlane,
    pub habitat: ClusterWorkspaceHabitat,
    pub context_packet: WorkstreamContextPacket,
}

pub fn build_workstream_workspace_subagents(
    cfg: &BeagleConfig,
    workstream_id: &str,
    context_packet: WorkstreamContextPacketResponse,
) -> anyhow::Result<WorkspaceSubAgentsResponse> {
    let template_response = build_workstream_workspace_template(cfg, workstream_id, context_packet)?;
    Ok(workspace_subagents_from_template(template_response))
}

fn workspace_subagents_from_template(
    template_response: WorkspaceTemplateResponse,
) -> WorkspaceSubAgentsResponse {
    let launch = template_response.launch.clone();
    let template = template_response.template.clone();
    let habitat = template_response.habitat.clone();
    let packet = template_response.context_packet.clone();
    let stable_alias = template.metadata.stable_attach_alias.clone();
    let attach_method = template.metadata.attach_method.clone();
    let managed_attach_state = template.metadata.managed_attach_state.clone();
    let workspace_subagents_path = format!(
        "{}/{}/workspace-subagents",
        WORKSPACE_SUBAGENTS_API_PREFIX, packet.workstream_id
    );
    let workspace_subagent_handoff_path = format!(
        "{}/{}/workspace-subagent-handoff",
        WORKSPACE_SUBAGENTS_API_PREFIX, packet.workstream_id
    );
    let roles = vec![
        subagent_role(
            "core",
            "Beagle Core",
            "core-runtime",
            "runtime-and-control-plane",
            vec![
                "core".to_string(),
                "runtime".to_string(),
                "implementation".to_string(),
                "control-plane".to_string(),
                "governance".to_string(),
                "interactive-editing".to_string(),
            ],
            vec!["cursor".to_string(), "codex".to_string()],
            &format!("{}/beagle-core/devcontainer.json", habitat.devcontainer_dir),
            &format!("{}/core.env", habitat.subagents_dir),
            &habitat.workspace_root,
            vec![
                "apps/beagle-monorepo".to_string(),
                "crates/beagle-darwin".to_string(),
                "k8s/beagle".to_string(),
                "scripts/infrastructure/darwin-hpc".to_string(),
            ],
            &launch,
            &habitat,
            &attach_method,
            &managed_attach_state,
            &stable_alias,
        ),
        subagent_role(
            "experiments",
            "Beagle Experiments",
            "experiments-analysis",
            "experiments-analysis-and-evidence",
            vec![
                "experiments".to_string(),
                "analysis".to_string(),
                "evaluation".to_string(),
                "evidence".to_string(),
                "results-synthesis".to_string(),
            ],
            vec!["claude-code".to_string()],
            &format!("{}/beagle-experiments/devcontainer.json", habitat.devcontainer_dir),
            &format!("{}/experiments.env", habitat.subagents_dir),
            &format!(
                "{}/crates/beagle-experiments",
                habitat.workspace_root.trim_end_matches('/')
            ),
            vec![
                "crates/beagle-experiments".to_string(),
                "crates/beagle-feedback".to_string(),
                "docs/darwin/hpc".to_string(),
                ".artifacts/darwin-hpc".to_string(),
            ],
            &launch,
            &habitat,
            &attach_method,
            &managed_attach_state,
            &stable_alias,
        ),
        subagent_role(
            "manuscript",
            "Beagle Manuscript",
            "manuscript-authoring",
            "claims-evidence-and-manuscript-assembly",
            vec![
                "manuscript".to_string(),
                "paper".to_string(),
                "writing".to_string(),
                "editorial".to_string(),
                "claims".to_string(),
                "discussion".to_string(),
            ],
            vec!["claude-code".to_string(), "cursor".to_string()],
            &format!("{}/beagle-manuscript/devcontainer.json", habitat.devcontainer_dir),
            &format!("{}/manuscript.env", habitat.subagents_dir),
            &format!(
                "{}/docs/darwin/hpc",
                habitat.workspace_root.trim_end_matches('/')
            ),
            vec![
                "docs/darwin/hpc".to_string(),
                "crates/beagle-darwin/src".to_string(),
                ".artifacts/darwin-hpc".to_string(),
            ],
            &launch,
            &habitat,
            &attach_method,
            &managed_attach_state,
            &stable_alias,
        ),
    ];

    let subagents = WorkspaceSubAgentsPlane {
        subagents_version: WORKSPACE_SUBAGENTS_VERSION.to_string(),
        subagents_kind: WORKSPACE_SUBAGENTS_KIND.to_string(),
        workstream_id: packet.workstream_id.clone(),
        workspace_id: packet.workspace_id.clone(),
        session_id: packet.session_id.clone(),
        repo: packet.repo.clone(),
        branch: packet.branch.clone(),
        governance_state: packet.governance_state.clone(),
        workspace_subagents_path,
        workspace_subagent_handoff_path,
        subagents_file: habitat.subagents_file.clone(),
        subagents_dir: habitat.subagents_dir.clone(),
        devcontainer_dir: habitat.devcontainer_dir.clone(),
        attach_method,
        managed_attach_state,
        stable_attach_alias: stable_alias,
        browser_fallback_ready: template.metadata.browser_fallback_ready,
        cursor_managed_attach_ready: template.metadata.cursor_managed_attach_ready,
        note: "The workspace-subagents plane keeps one Beagle-owned workspace/session identity while freezing multiple reproducible inner work surfaces with explicit role separation and devcontainer-style metadata.".to_string(),
        roles,
    };

    WorkspaceSubAgentsResponse {
        status: "ok".to_string(),
        phase: WORKSPACE_SUBAGENTS_PHASE.to_string(),
        subagents,
        template,
        launch,
        habitat,
        context_packet: packet,
    }
}

fn subagent_role(
    subagent_id: &str,
    label: &str,
    role_tag: &str,
    specialization: &str,
    recommended_work_modes: Vec<String>,
    default_tools: Vec<String>,
    devcontainer_config_file: &str,
    env_file: &str,
    workspace_folder: &str,
    repo_focus_paths: Vec<String>,
    launch: &WorkspaceLaunchResumePlane,
    habitat: &ClusterWorkspaceHabitat,
    attach_method: &str,
    managed_attach_state: &str,
    stable_attach_alias: &str,
) -> WorkspaceSubAgentRole {
    WorkspaceSubAgentRole {
        subagent_id: subagent_id.to_string(),
        label: label.to_string(),
        role: subagent_id.to_string(),
        role_tag: role_tag.to_string(),
        access_state: "live".to_string(),
        specialization: specialization.to_string(),
        recommended_work_modes,
        default_tools,
        devcontainer_kind: "devcontainer-style-shared-workspace".to_string(),
        devcontainer_name: format!("beagle-{}", subagent_id),
        devcontainer_config_file: devcontainer_config_file.to_string(),
        env_file: env_file.to_string(),
        workspace_folder: workspace_folder.to_string(),
        repo_focus_paths,
        recommended_client: launch.launch_metadata.recommended_client.clone(),
        attach_method: attach_method.to_string(),
        managed_attach_state: managed_attach_state.to_string(),
        stable_attach_alias: stable_attach_alias.to_string(),
        launch_resume_path: launch.workspace_launch_resume_path.clone(),
        managed_attach_path: launch.managed_attach_path.clone(),
        browser_url: habitat.browser_url.clone(),
        shell_entry_hint: format!(
            "cd {} && . {} && exec \"${{SHELL:-/bin/sh}}\"",
            workspace_folder, env_file
        ),
        note: format!(
            "The {} sub-agent stays inside the same canonical workspace/session envelope and only narrows focus, not identity.",
            subagent_id
        ),
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
                data_dir: "/tmp/beagle-workspace-subagents-tests".to_string(),
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
    fn workspace_subagents_use_same_identity_as_launch_resume() {
        let response = build_workstream_workspace_subagents(
            &test_config(),
            "beagle-darwin-hpc-governance",
            packet(),
        )
        .expect("workspace subagents");

        assert_eq!(response.phase, "B20.7");
        assert_eq!(response.subagents.workstream_id, "beagle-darwin-hpc-governance");
        assert_eq!(response.subagents.workspace_id, "beagle-cluster-pilot");
        assert_eq!(response.subagents.session_id, "ws-cluster-workspace-habitat");
        assert_eq!(
            response.subagents.workspace_subagents_path,
            "/api/darwin/workstreams/beagle-darwin-hpc-governance/workspace-subagents"
        );
        assert_eq!(response.subagents.roles.len(), 3);
        assert_eq!(response.template.workspace_id, response.subagents.workspace_id);
        assert_eq!(response.launch.session_id, response.subagents.session_id);
        assert_eq!(response.habitat.workstream_id, response.subagents.workstream_id);
    }

    #[test]
    fn workspace_subagents_derive_role_separated_devcontainer_paths() {
        let response = build_workstream_workspace_subagents(
            &test_config(),
            "beagle-darwin-hpc-governance",
            packet(),
        )
        .expect("workspace subagents");

        let core = response
            .subagents
            .roles
            .iter()
            .find(|role| role.subagent_id == "core")
            .expect("core role");
        let experiments = response
            .subagents
            .roles
            .iter()
            .find(|role| role.subagent_id == "experiments")
            .expect("experiments role");
        let manuscript = response
            .subagents
            .roles
            .iter()
            .find(|role| role.subagent_id == "manuscript")
            .expect("manuscript role");

        assert_eq!(core.access_state, "live");
        assert_eq!(core.role_tag, "core-runtime");
        assert_eq!(core.devcontainer_kind, "devcontainer-style-shared-workspace");
        assert!(core
            .recommended_work_modes
            .iter()
            .any(|mode| mode == "implementation"));
        assert!(core.default_tools.iter().any(|tool| tool == "codex"));
        assert_eq!(
            core.devcontainer_config_file,
            "/workspace/beagle/.devcontainer/beagle-core/devcontainer.json"
        );
        assert_eq!(
            core.env_file,
            "/workspace/beagle/.beagle/context/subagents/core.env"
        );
        assert_eq!(core.workspace_folder, "/workspace/beagle");
        assert!(core.repo_focus_paths.iter().any(|path| path == "apps/beagle-monorepo"));

        assert_eq!(experiments.access_state, "live");
        assert_eq!(experiments.role_tag, "experiments-analysis");
        assert!(experiments
            .recommended_work_modes
            .iter()
            .any(|mode| mode == "analysis"));
        assert!(!experiments
            .recommended_work_modes
            .iter()
            .any(|mode| mode == "manuscript"));
        assert!(experiments
            .default_tools
            .iter()
            .any(|tool| tool == "claude-code"));
        assert_eq!(
            experiments.devcontainer_config_file,
            "/workspace/beagle/.devcontainer/beagle-experiments/devcontainer.json"
        );
        assert_eq!(
            experiments.env_file,
            "/workspace/beagle/.beagle/context/subagents/experiments.env"
        );
        assert_eq!(
            experiments.workspace_folder,
            "/workspace/beagle/crates/beagle-experiments"
        );
        assert!(experiments
            .repo_focus_paths
            .iter()
            .any(|path| path == "crates/beagle-experiments"));
        assert_eq!(experiments.managed_attach_state, "coder-compatible-ready");
        assert_eq!(experiments.stable_attach_alias, "beagle-cluster-pilot.coder");

        assert_eq!(manuscript.access_state, "live");
        assert_eq!(manuscript.role_tag, "manuscript-authoring");
        assert!(manuscript
            .recommended_work_modes
            .iter()
            .any(|mode| mode == "manuscript"));
        assert!(manuscript
            .default_tools
            .iter()
            .any(|tool| tool == "claude-code"));
        assert_eq!(
            manuscript.devcontainer_config_file,
            "/workspace/beagle/.devcontainer/beagle-manuscript/devcontainer.json"
        );
        assert_eq!(
            manuscript.env_file,
            "/workspace/beagle/.beagle/context/subagents/manuscript.env"
        );
        assert_eq!(manuscript.workspace_folder, "/workspace/beagle/docs/darwin/hpc");
        assert!(manuscript
            .repo_focus_paths
            .iter()
            .any(|path| path == "docs/darwin/hpc"));
    }
}
