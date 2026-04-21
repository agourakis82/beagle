use crate::cursor_remote_lane::{build_workstream_cursor_remote_lane, CursorRemoteLaneResponse};
use crate::result_catalog::{HpcProfile, HpcProfileCatalog};
use crate::workspace_attach::{build_workstream_managed_attach, WorkspaceAttachResponse};
use crate::workspace_plane::WorkspaceSessionState;
use crate::workspace_template::{build_workstream_workspace_template, WorkspaceTemplateResponse};
use crate::WorkstreamContextPacketResponse;
use anyhow::{anyhow, Result};
use beagle_config::BeagleConfig;
use serde::Serialize;

const MULTI_USER_GPU_WORKSPACE_TENANCY_PHASE: &str = "B25.1";
const WORKSPACE_TENANCY_VERSION: &str = "beagle-workspace-tenancy-v1";
const COMPUTE_TENANCY_VERSION: &str = "beagle-compute-tenancy-v1";
const PARTNER_ACCESS_VERSION: &str = "beagle-partner-access-v1";
const CANONICAL_WORKSPACE_COMBINATION: [&str; 3] = [
    "shared-workspace",
    "external-workspace-compatible",
    "template-backed-prehydrated",
];

#[derive(Debug, Clone, Serialize)]
pub struct WorkspaceClientAccessPath {
    pub client_id: String,
    pub access_state: String,
    pub workspace_mode: String,
    pub connection_mode: String,
    pub attach_method: String,
    pub stable_attach_alias: String,
    pub recommended_entry_command: String,
    pub suggested_ssh_command: String,
    pub suggested_ssh_port_forward_command: Option<String>,
    pub workspace_root: String,
    pub browser_fallback_url: String,
    pub browser_fallback_ready: bool,
    pub same_beagle_owned_identity: bool,
    pub note: String,
}

#[derive(Debug, Clone, Serialize)]
pub struct VsCodeCursorAccessContract {
    pub access_version: String,
    pub access_kind: String,
    pub workstream_id: String,
    pub workspace_id: String,
    pub session_id: String,
    pub same_beagle_owned_identity: bool,
    pub browser_fallback_url: String,
    pub clients: Vec<WorkspaceClientAccessPath>,
    pub note: String,
}

#[derive(Debug, Clone, Serialize)]
pub struct RepoHydrationContract {
    pub hydration_version: String,
    pub hydration_kind: String,
    pub workstream_id: String,
    pub workspace_id: String,
    pub session_id: String,
    pub warm_start_strategy: String,
    pub startup_mode: String,
    pub reproducible_ready: bool,
    pub warm_start_ready: bool,
    pub prebuilt_snapshot_expected: bool,
    pub external_workspace_compatible: bool,
    pub repo_remote_url: String,
    pub repo_branch: String,
    pub repo_root: String,
    pub hydrated_startup_path: String,
    pub template_file: String,
    pub registration_file: String,
    pub hydration_file: String,
    pub recommended_clone_command: String,
    pub note: String,
}

#[derive(Debug, Clone, Serialize)]
pub struct WorkspaceTenancyContract {
    pub phase: String,
    pub contract_kind: String,
    pub contract_version: String,
    pub workstream_id: String,
    pub workspace_id: String,
    pub session_id: String,
    pub same_beagle_owned_identity: bool,
    pub workspace_identity_owner: String,
    pub workspace_model: String,
    pub workspace_tenancy_state: String,
    pub default_dev_plane: String,
    pub vm_fallback_role: String,
    pub promotion_scope: String,
    pub shared_workspace_recommended: bool,
    pub external_workspace_compatible: bool,
    pub prebuilt_prehydrated_recommended: bool,
    pub canonical_workspace_combination: Vec<String>,
    pub canonical_workspace_recommendation: String,
    pub workspace_template_path: String,
    pub workspace_launch_resume_path: String,
    pub managed_attach_path: String,
    pub cursor_remote_lane_path: String,
    pub stable_workspace_alias: String,
    pub vscode_cursor_access: VsCodeCursorAccessContract,
    pub repo_hydration: RepoHydrationContract,
    pub note: String,
}

#[derive(Debug, Clone, Serialize)]
pub struct ComputeTenancyClass {
    pub profile_id: String,
    pub description: String,
    pub kind: String,
    pub partition: String,
    pub single_node: bool,
    pub gpu: bool,
    pub max_walltime: String,
    pub artifact_mode: String,
    pub allowed_parameters: Vec<String>,
    pub access_lane: String,
    pub quota_boundary: String,
    pub gpu_isolation_mode: String,
    pub shared_access_state: String,
    pub live_enablement_state: String,
    pub note: String,
}

#[derive(Debug, Clone, Serialize)]
pub struct ComputeRoleScope {
    pub role_id: String,
    pub allowed_profile_ids: Vec<String>,
    pub submit_mode: String,
    pub gpu_access_mode: String,
    pub quota_boundary: String,
    pub note: String,
}

#[derive(Debug, Clone, Serialize)]
pub struct ComputeTenancyContract {
    pub phase: String,
    pub contract_kind: String,
    pub contract_version: String,
    pub workstream_id: String,
    pub workspace_id: String,
    pub session_id: String,
    pub same_beagle_owned_identity: bool,
    pub scheduler_kind: String,
    pub scheduler_control_plane: String,
    pub scheduler_policy_state: String,
    pub quota_policy_kind: String,
    pub default_profile_id: String,
    pub batch_profile_id: String,
    pub advanced_profile_id: String,
    pub live_gpu_access_mode: String,
    pub shared_gpu_access_state: String,
    pub typed_gpu_required: bool,
    pub compute_classes: Vec<ComputeTenancyClass>,
    pub role_scopes: Vec<ComputeRoleScope>,
    pub note: String,
}

#[derive(Debug, Clone, Serialize)]
pub struct PartnerAccessRole {
    pub role_id: String,
    pub role_kind: String,
    pub access_state: String,
    pub workspace_attach_allowed: bool,
    pub shared_workspace_allowed: bool,
    pub allowed_clients: Vec<String>,
    pub allowed_profile_ids: Vec<String>,
    pub cluster_admin_allowed: bool,
    pub direct_kubernetes_access_allowed: bool,
    pub activation_mode: String,
    pub rollback_mode: String,
    pub note: String,
}

#[derive(Debug, Clone, Serialize)]
pub struct PartnerAccessContract {
    pub phase: String,
    pub contract_kind: String,
    pub contract_version: String,
    pub workstream_id: String,
    pub workspace_id: String,
    pub session_id: String,
    pub same_beagle_owned_identity: bool,
    pub partner_access_state: String,
    pub workspace_sharing_mode: String,
    pub direct_cluster_admin_grant: bool,
    pub direct_kubernetes_access_grant: bool,
    pub per_user_cluster_identity_live: bool,
    pub recommended_workspace_pattern: String,
    pub workspace_template_path: String,
    pub managed_attach_path: String,
    pub stable_workspace_alias: String,
    pub roles: Vec<PartnerAccessRole>,
    pub note: String,
}

#[derive(Debug, Clone)]
pub struct MultiUserGpuWorkspaceTenancyBundle {
    pub workspace_tenancy: WorkspaceTenancyContract,
    pub compute_tenancy: ComputeTenancyContract,
    pub partner_access: PartnerAccessContract,
}

pub fn build_multi_user_gpu_workspace_tenancy_bundle(
    cfg: &BeagleConfig,
    workstream_id: &str,
    context_packet: WorkstreamContextPacketResponse,
    workspace_session: &WorkspaceSessionState,
    profile_catalog: &HpcProfileCatalog,
) -> Result<MultiUserGpuWorkspaceTenancyBundle> {
    let template_response =
        build_workstream_workspace_template(cfg, workstream_id, context_packet.clone())?;
    let attach_response =
        build_workstream_managed_attach(cfg, workstream_id, context_packet.clone())?;
    let cursor_response = build_workstream_cursor_remote_lane(cfg, workstream_id, context_packet)?;

    let same_identity = same_beagle_owned_identity(
        &template_response,
        &attach_response,
        &cursor_response,
        workspace_session,
    );
    let workspace_tenancy = build_workspace_tenancy_contract(
        &template_response,
        &attach_response,
        &cursor_response,
        workspace_session,
        same_identity,
    );
    let compute_tenancy =
        build_compute_tenancy_contract(&template_response, workspace_session, profile_catalog, same_identity)?;
    let partner_access =
        build_partner_access_contract(&template_response, &compute_tenancy, same_identity);

    Ok(MultiUserGpuWorkspaceTenancyBundle {
        workspace_tenancy,
        compute_tenancy,
        partner_access,
    })
}

fn same_beagle_owned_identity(
    template_response: &WorkspaceTemplateResponse,
    attach_response: &WorkspaceAttachResponse,
    cursor_response: &CursorRemoteLaneResponse,
    workspace_session: &WorkspaceSessionState,
) -> bool {
    let workspace_id = &template_response.template.workspace_id;
    let session_id = &template_response.template.session_id;
    let workstream_id = &template_response.template.workstream_id;

    attach_response.attach.workspace_id == *workspace_id
        && attach_response.attach.session_id == *session_id
        && attach_response.attach.workstream_id == *workstream_id
        && cursor_response.lane.workspace_id == *workspace_id
        && cursor_response.lane.session_id == *session_id
        && cursor_response.lane.workstream_id == *workstream_id
        && workspace_session.workspace_id == *workspace_id
        && workspace_session.session_id == *session_id
}

fn build_workspace_tenancy_contract(
    template_response: &WorkspaceTemplateResponse,
    attach_response: &WorkspaceAttachResponse,
    cursor_response: &CursorRemoteLaneResponse,
    workspace_session: &WorkspaceSessionState,
    same_identity: bool,
) -> WorkspaceTenancyContract {
    let template = &template_response.template;
    let launch = &template_response.launch;
    let attach = &attach_response.attach;
    let cursor = &cursor_response.lane;
    let stable_alias = attach.attach_metadata.stable_attach_host_alias.clone();
    let browser_url = attach.attach_metadata.browser_url.clone();
    let ssh_port_forward = cursor
        .connection_metadata
        .suggested_ssh_port_forward_command
        .clone();

    let vscode_access = WorkspaceClientAccessPath {
        client_id: "vscode-desktop".to_string(),
        access_state: "ready".to_string(),
        workspace_mode: "same-workspace-remote-ssh".to_string(),
        connection_mode: "remote-ssh".to_string(),
        attach_method: attach.attach_metadata.attach_method.clone(),
        stable_attach_alias: stable_alias.clone(),
        recommended_entry_command: launch.helper_snippets.ssh_resume_command.clone(),
        suggested_ssh_command: attach.helper_snippets.ssh_command.clone(),
        suggested_ssh_port_forward_command: ssh_port_forward.clone(),
        workspace_root: attach.attach_metadata.repo_root.clone(),
        browser_fallback_url: browser_url.clone(),
        browser_fallback_ready: true,
        same_beagle_owned_identity: same_identity,
        note: format!(
            "VS Code Desktop reaches the same Beagle-owned workspace by preparing the managed SSH attach and opening host `{}` via Remote-SSH.",
            stable_alias
        ),
    };
    let cursor_access = WorkspaceClientAccessPath {
        client_id: "cursor".to_string(),
        access_state: "ready".to_string(),
        workspace_mode: "same-workspace-remote-ssh".to_string(),
        connection_mode: cursor.connection_metadata.connection_mode.clone(),
        attach_method: attach.attach_metadata.attach_method.clone(),
        stable_attach_alias: stable_alias.clone(),
        recommended_entry_command: launch.helper_snippets.cursor_resume_command.clone(),
        suggested_ssh_command: attach.helper_snippets.ssh_command.clone(),
        suggested_ssh_port_forward_command: ssh_port_forward,
        workspace_root: cursor.connection_metadata.workspace_root.clone(),
        browser_fallback_url: browser_url.clone(),
        browser_fallback_ready: true,
        same_beagle_owned_identity: same_identity,
        note: cursor.note.clone(),
    };
    let vscode_cursor_access = VsCodeCursorAccessContract {
        access_version: WORKSPACE_TENANCY_VERSION.to_string(),
        access_kind: "vscode-cursor-access".to_string(),
        workstream_id: template.workstream_id.clone(),
        workspace_id: template.workspace_id.clone(),
        session_id: template.session_id.clone(),
        same_beagle_owned_identity: same_identity,
        browser_fallback_url: browser_url.clone(),
        clients: vec![vscode_access, cursor_access],
        note: "VS Code Desktop and Cursor both attach to the same Beagle-owned workspace/session envelope; browser OpenVSCode remains the bounded fallback surface.".to_string(),
    };
    let repo_hydration = RepoHydrationContract {
        hydration_version: WORKSPACE_TENANCY_VERSION.to_string(),
        hydration_kind: "repo-hydration".to_string(),
        workstream_id: template.workstream_id.clone(),
        workspace_id: template.workspace_id.clone(),
        session_id: template.session_id.clone(),
        warm_start_strategy: template.hydration.warm_start_strategy.clone(),
        startup_mode: template.hydration.startup_mode.clone(),
        reproducible_ready: template.hydration.reproducible_ready,
        warm_start_ready: template.hydration.warm_start_ready,
        prebuilt_snapshot_expected: template.hydration.prebuilt_snapshot_expected,
        external_workspace_compatible: template.metadata.external_workspace_compatible,
        repo_remote_url: template.hydration.repo_remote_url.clone(),
        repo_branch: template.hydration.repo_branch.clone(),
        repo_root: template.hydration.repo_root.clone(),
        hydrated_startup_path: template.hydration.hydrated_startup_path.clone(),
        template_file: template.hydration.template_file.clone(),
        registration_file: template.hydration.registration_file.clone(),
        hydration_file: template.hydration.hydration_file.clone(),
        recommended_clone_command: format!(
            "git clone --branch {} {} {}",
            template.hydration.repo_branch,
            template.hydration.repo_remote_url,
            template.hydration.repo_root
        ),
        note: "The canonical warm start is template-backed and prehydrated; repo clone remains explicit for fresh hydration or external-workspace claim flows without changing Beagle-owned identity.".to_string(),
    };

    WorkspaceTenancyContract {
        phase: MULTI_USER_GPU_WORKSPACE_TENANCY_PHASE.to_string(),
        contract_kind: "workspace-tenancy".to_string(),
        contract_version: WORKSPACE_TENANCY_VERSION.to_string(),
        workstream_id: template.workstream_id.clone(),
        workspace_id: template.workspace_id.clone(),
        session_id: template.session_id.clone(),
        same_beagle_owned_identity: same_identity,
        workspace_identity_owner: "beagle".to_string(),
        workspace_model: "same-beagle-owned-remote-workspace".to_string(),
        workspace_tenancy_state: "shared-workspace-live-external-compatible".to_string(),
        default_dev_plane: workspace_session.dev_plane_policy.default_dev_plane.clone(),
        vm_fallback_role: workspace_session.dev_plane_policy.vm_fallback_role.clone(),
        promotion_scope: workspace_session.dev_plane_policy.promotion_scope.clone(),
        shared_workspace_recommended: true,
        external_workspace_compatible: template.metadata.external_workspace_compatible,
        prebuilt_prehydrated_recommended: template.hydration.prebuilt_snapshot_expected,
        canonical_workspace_combination: CANONICAL_WORKSPACE_COMBINATION
            .iter()
            .map(|value| value.to_string())
            .collect(),
        canonical_workspace_recommendation:
            "Use the live shared workspace as the canonical collaboration surface, keep the template external-workspace-compatible, and preserve template-backed prehydration as the warm-start path.".to_string(),
        workspace_template_path: template.workspace_template_path.clone(),
        workspace_launch_resume_path: template.workspace_launch_resume_path.clone(),
        managed_attach_path: template.managed_attach_path.clone(),
        cursor_remote_lane_path: launch.cursor_remote_lane_path.clone(),
        stable_workspace_alias: stable_alias,
        vscode_cursor_access,
        repo_hydration,
        note: "B25.1 does not replace Beagle with a workspace manager; it freezes the existing habitat, attach, and prehydrated template path into one VM-agnostic tenancy contract for the same Beagle-owned workspace identity.".to_string(),
    }
}

fn build_compute_tenancy_contract(
    template_response: &WorkspaceTemplateResponse,
    workspace_session: &WorkspaceSessionState,
    profile_catalog: &HpcProfileCatalog,
    same_identity: bool,
) -> Result<ComputeTenancyContract> {
    let compute_profiles = &workspace_session.workstream_cutover_policy.compute_profiles;
    let default_profile = profile_from_catalog(profile_catalog, &compute_profiles.default_profile)?;
    let batch_profile = profile_from_catalog(profile_catalog, &compute_profiles.batch_profile)?;
    let advanced_profile = profile_from_catalog(profile_catalog, &compute_profiles.advanced_profile)?;

    let compute_classes = vec![
        compute_class_from_profile(default_profile, "interactive-cpu", "shared-cpu-live"),
        compute_class_from_profile(batch_profile, "batch-cpu", "shared-cpu-live"),
        compute_class_from_profile(advanced_profile, "advanced-gpu", "isolated-dedicated-gpu"),
    ];
    let role_scopes = vec![
        ComputeRoleScope {
            role_id: "beagle-operator".to_string(),
            allowed_profile_ids: vec![
                default_profile.id.clone(),
                batch_profile.id.clone(),
                advanced_profile.id.clone(),
            ],
            submit_mode: "full-bounded-submit".to_string(),
            gpu_access_mode: "typed-isolated-gpu".to_string(),
            quota_boundary: "role+profile-id".to_string(),
            note: "The operator retains the full bounded cutover profile set for the canonical workspace.".to_string(),
        },
        ComputeRoleScope {
            role_id: "partner-dev".to_string(),
            allowed_profile_ids: vec![default_profile.id.clone(), advanced_profile.id.clone()],
            submit_mode: "scoped-profile-submit".to_string(),
            gpu_access_mode: "typed-isolated-gpu".to_string(),
            quota_boundary: "role+profile-id".to_string(),
            note: "The partner-dev lane is intentionally narrower: interactive CPU plus one typed GPU profile, without broad batch access or cluster-admin rights.".to_string(),
        },
    ];

    Ok(ComputeTenancyContract {
        phase: MULTI_USER_GPU_WORKSPACE_TENANCY_PHASE.to_string(),
        contract_kind: "compute-tenancy".to_string(),
        contract_version: COMPUTE_TENANCY_VERSION.to_string(),
        workstream_id: template_response.template.workstream_id.clone(),
        workspace_id: template_response.template.workspace_id.clone(),
        session_id: template_response.template.session_id.clone(),
        same_beagle_owned_identity: same_identity,
        scheduler_kind: "slurm-backed-profile-tenancy".to_string(),
        scheduler_control_plane: "darwin-hpc-gateway".to_string(),
        scheduler_policy_state: "bounded-live".to_string(),
        quota_policy_kind: "typed-profile-quota-aware".to_string(),
        default_profile_id: default_profile.id.clone(),
        batch_profile_id: batch_profile.id.clone(),
        advanced_profile_id: advanced_profile.id.clone(),
        live_gpu_access_mode: "isolated-dedicated-gpu".to_string(),
        shared_gpu_access_state: "explicitly-modeled-nonlive".to_string(),
        typed_gpu_required: true,
        compute_classes,
        role_scopes,
        note: "The canonical live GPU path remains typed and isolated through `gpu-single-v1`; shared or oversubscribed GPU access is only modeled explicitly in this phase and is not enabled live by default.".to_string(),
    })
}

fn compute_class_from_profile(
    profile: &HpcProfile,
    access_lane: &str,
    gpu_mode: &str,
) -> ComputeTenancyClass {
    let shared_access_state = if profile.gpu {
        "shared-oversubscription-staged-nonlive".to_string()
    } else {
        "shared-cpu-live".to_string()
    };
    let live_enablement_state = if profile.gpu {
        "live-isolated".to_string()
    } else {
        "live".to_string()
    };
    ComputeTenancyClass {
        profile_id: profile.id.clone(),
        description: profile.description.clone(),
        kind: profile.kind.clone(),
        partition: profile.partition.clone(),
        single_node: profile.single_node,
        gpu: profile.gpu,
        max_walltime: profile.max_walltime.clone(),
        artifact_mode: profile.artifact_mode.clone(),
        allowed_parameters: profile.allowed_parameters.clone(),
        access_lane: access_lane.to_string(),
        quota_boundary: "profile-id".to_string(),
        gpu_isolation_mode: if profile.gpu {
            gpu_mode.to_string()
        } else {
            "not-applicable".to_string()
        },
        shared_access_state,
        live_enablement_state,
        note: if profile.gpu {
            "GPU access stays bounded to a typed single-node profile; oversubscription is not the canonical live path in B25.1.".to_string()
        } else {
            "CPU access remains shared but bounded through the existing Slurm profile catalog.".to_string()
        },
    }
}

fn build_partner_access_contract(
    template_response: &WorkspaceTemplateResponse,
    compute_tenancy: &ComputeTenancyContract,
    same_identity: bool,
) -> PartnerAccessContract {
    let operator_profiles = compute_tenancy
        .role_scopes
        .iter()
        .find(|scope| scope.role_id == "beagle-operator")
        .map(|scope| scope.allowed_profile_ids.clone())
        .unwrap_or_default();
    let partner_profiles = compute_tenancy
        .role_scopes
        .iter()
        .find(|scope| scope.role_id == "partner-dev")
        .map(|scope| scope.allowed_profile_ids.clone())
        .unwrap_or_default();

    PartnerAccessContract {
        phase: MULTI_USER_GPU_WORKSPACE_TENANCY_PHASE.to_string(),
        contract_kind: "partner-access".to_string(),
        contract_version: PARTNER_ACCESS_VERSION.to_string(),
        workstream_id: template_response.template.workstream_id.clone(),
        workspace_id: template_response.template.workspace_id.clone(),
        session_id: template_response.template.session_id.clone(),
        same_beagle_owned_identity: same_identity,
        partner_access_state: "operator-mediated-ready".to_string(),
        workspace_sharing_mode: "shared-workspace".to_string(),
        direct_cluster_admin_grant: false,
        direct_kubernetes_access_grant: false,
        per_user_cluster_identity_live: false,
        recommended_workspace_pattern:
            "shared-workspace+external-workspace-compatible+template-backed-prehydrated"
                .to_string(),
        workspace_template_path: template_response.template.workspace_template_path.clone(),
        managed_attach_path: template_response.template.managed_attach_path.clone(),
        stable_workspace_alias: template_response
            .template
            .external_registration
            .stable_workspace_alias
            .clone(),
        roles: vec![
            PartnerAccessRole {
                role_id: "beagle-operator".to_string(),
                role_kind: "owner".to_string(),
                access_state: "live".to_string(),
                workspace_attach_allowed: true,
                shared_workspace_allowed: true,
                allowed_clients: vec![
                    "cursor".to_string(),
                    "vscode-desktop".to_string(),
                    "browser-openvscode".to_string(),
                ],
                allowed_profile_ids: operator_profiles,
                cluster_admin_allowed: false,
                direct_kubernetes_access_allowed: false,
                activation_mode: "direct".to_string(),
                rollback_mode: "retain-control".to_string(),
                note: "The operator remains the Beagle control-plane owner, but still works through the bounded workspace and profile surfaces rather than raw cluster ownership.".to_string(),
            },
            PartnerAccessRole {
                role_id: "partner-dev".to_string(),
                role_kind: "collaborator".to_string(),
                access_state: "ready".to_string(),
                workspace_attach_allowed: true,
                shared_workspace_allowed: true,
                allowed_clients: vec![
                    "cursor".to_string(),
                    "vscode-desktop".to_string(),
                ],
                allowed_profile_ids: partner_profiles,
                cluster_admin_allowed: false,
                direct_kubernetes_access_allowed: false,
                activation_mode: "operator-mediated".to_string(),
                rollback_mode: "revoke-shared-attach-or-profile-scope".to_string(),
                note: "Partner-dev access is intentionally bounded to the shared Beagle-owned workspace plus a narrowed profile set; this phase does not hand out unrestricted cluster credentials.".to_string(),
            },
        ],
        note: "B25.1 introduces an explicit partner-dev path without making the partner a second state owner: the collaboration surface is the same Beagle-owned workspace, and compute access stays scoped by profile and operator mediation.".to_string(),
    }
}

fn profile_from_catalog<'a>(catalog: &'a HpcProfileCatalog, profile_id: &str) -> Result<&'a HpcProfile> {
    catalog
        .profiles
        .iter()
        .find(|profile| profile.id == profile_id)
        .ok_or_else(|| anyhow!("required HPC profile '{}' missing from catalog", profile_id))
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::{
        WorkstreamContextPacket, WorkstreamContextPacketExperimentFlags,
        WorkstreamContextPacketHandoff, WorkstreamContextPacketLastResult,
        WorkstreamContextPacketResponse,
    };
    use beagle_config::{
        AdvancedModulesConfig, BeagleConfig, ConsumerAccessConfig, GraphConfig, HermesConfig,
        LlmConfig, ObserverThresholds, StorageConfig, ToolBridgeConfig, WorkspacePlaneConfig,
    };

    fn cfg() -> BeagleConfig {
        let mut workspace = WorkspacePlaneConfig::default();
        workspace.habitat.ssh_enabled = true;
        workspace.habitat.ssh_service_port = 2222;
        workspace.habitat.ssh_user = "openvscode-server".to_string();
        BeagleConfig {
            profile: "dev".to_string(),
            safe_mode: true,
            api_token: None,
            llm: LlmConfig::default(),
            storage: StorageConfig {
                data_dir: "/tmp/beagle-tests".to_string(),
            },
            graph: GraphConfig::default(),
            hermes: HermesConfig::default(),
            tool_bridge: ToolBridgeConfig::default(),
            workspace,
            consumers: ConsumerAccessConfig::default(),
            advanced: AdvancedModulesConfig::default(),
            observer: ObserverThresholds::default(),
        }
    }

    fn context_packet() -> WorkstreamContextPacketResponse {
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
                    last_handoff: Some("resume from workspace tenancy test".to_string()),
                },
                last_result: WorkstreamContextPacketLastResult {
                    available: true,
                    reference: None,
                    summary: None,
                    manifest: None,
                    error: None,
                },
                last_successful_task: None,
                latest_physio: None,
                experiment_flags: Some(WorkstreamContextPacketExperimentFlags {
                    hrv_aware: Some(true),
                    observer_enabled: Some(true),
                    serendipity_enabled: Some(false),
                    triad_enabled: Some(false),
                    provider: Some("codex".to_string()),
                    model: Some("gpt-5.4".to_string()),
                    experiment_id: None,
                    condition: Some("steady".to_string()),
                }),
                memory_hits: Vec::new(),
                retrieval_context: None,
                recommended_recipe: None,
                bounded_study_baseline: None,
            },
        }
    }

    fn profile_catalog() -> HpcProfileCatalog {
        HpcProfileCatalog {
            profiles: vec![
                HpcProfile {
                    id: "cpu-short-v1".to_string(),
                    description: "Short-lived CPU canary profile".to_string(),
                    kind: "cpu".to_string(),
                    single_node: true,
                    gpu: false,
                    partition: "cpu".to_string(),
                    max_walltime: "00:02:00".to_string(),
                    artifact_mode: "deterministic-small".to_string(),
                    allowed_parameters: vec!["run_label".to_string()],
                },
                HpcProfile {
                    id: "cpu-batch-v1".to_string(),
                    description: "Longer single-node CPU batch profile".to_string(),
                    kind: "cpu".to_string(),
                    single_node: true,
                    gpu: false,
                    partition: "cpu".to_string(),
                    max_walltime: "00:10:00".to_string(),
                    artifact_mode: "deterministic-medium".to_string(),
                    allowed_parameters: vec!["run_label".to_string()],
                },
                HpcProfile {
                    id: "gpu-single-v1".to_string(),
                    description: "Single-node GPU profile on the Slurm execution plane".to_string(),
                    kind: "gpu".to_string(),
                    single_node: true,
                    gpu: true,
                    partition: "gpu".to_string(),
                    max_walltime: "00:05:00".to_string(),
                    artifact_mode: "deterministic-small".to_string(),
                    allowed_parameters: vec!["run_label".to_string()],
                },
            ],
        }
    }

    #[test]
    fn multi_user_gpu_workspace_tenancy_keeps_same_workspace_identity() {
        let cfg = cfg();
        let session = WorkspaceSessionState::new(
            &cfg,
            "beagle-cluster-pilot".to_string(),
            Some("ws-cluster-workspace-habitat".to_string()),
        );
        let bundle = build_multi_user_gpu_workspace_tenancy_bundle(
            &cfg,
            "beagle-darwin-hpc-governance",
            context_packet(),
            &session,
            &profile_catalog(),
        )
        .unwrap();

        assert!(bundle.workspace_tenancy.same_beagle_owned_identity);
        assert!(bundle.workspace_tenancy.shared_workspace_recommended);
        assert!(bundle.workspace_tenancy.external_workspace_compatible);
        assert!(bundle.workspace_tenancy.prebuilt_prehydrated_recommended);
        assert_eq!(
            bundle.workspace_tenancy.canonical_workspace_combination,
            CANONICAL_WORKSPACE_COMBINATION
                .iter()
                .map(|value| value.to_string())
                .collect::<Vec<_>>()
        );
        assert_eq!(
            bundle.workspace_tenancy.stable_workspace_alias,
            "beagle-cluster-pilot.coder"
        );
        assert_eq!(
            bundle.compute_tenancy.advanced_profile_id,
            "gpu-single-v1"
        );
        assert_eq!(
            bundle.compute_tenancy.live_gpu_access_mode,
            "isolated-dedicated-gpu"
        );
        assert_eq!(
            bundle.partner_access.workspace_sharing_mode,
            "shared-workspace"
        );
        assert_eq!(bundle.partner_access.roles.len(), 2);
        assert_eq!(
            bundle.partner_access.roles[1].allowed_profile_ids,
            vec!["cpu-short-v1".to_string(), "gpu-single-v1".to_string()]
        );
    }
}
