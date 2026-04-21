use crate::{
    IntentPlannerAvailability, PlanExecutionStatusSummary,
    DarwinHpcGatewayClient, ObjectResultManifest, ProgramCampaignBinding,
    ResultCatalogEntry, WorkspaceLastSuccessfulTask, WorkstreamContextPacket,
    WorkstreamContextPacketAugmentation, WorkstreamContextPacketResponse,
    WorkstreamControlRoomActionSupport, WorkstreamLastResultReference,
    WorkstreamRecipeDocument, get_workstream_context_packet,
    get_workstream_control_room_detail, get_workstream_control_room_last_result,
    resolve_program_campaign_binding_for_workstream,
    default_subagent_for_tool, default_work_mode_for_tool,
};
use anyhow::anyhow;
use beagle_config::BeagleConfig;
use serde::Serialize;
use std::path::Path;

const COCKPIT_PHASE: &str = "B15.2";
const SESSION_ENVELOPE_VERSION: &str = "beagle-premium-tool-dock-session-envelope-v1";
const LAUNCH_SURFACE_KIND: &str = "beagle-session-envelope";
const COCKPIT_PAGE_PATH_PREFIX: &str = "/darwin/workstreams";
const COCKPIT_API_PATH_PREFIX: &str = "/api/darwin/workstreams";
const SHARED_CONTEXT_FIELDS: [&str; 15] = [
    "repo",
    "branch",
    "session_id",
    "governance_state",
    "handoff",
    "last_result",
    "last_successful_task",
    "latest_physio",
    "experiment_flags",
    "memory_hits",
    "retrieval_context",
    "planner",
    "execution",
    "recommended_recipe",
    "recipes",
];

#[derive(Debug, Clone, Serialize)]
pub struct WorkstreamSessionEnvelope {
    pub envelope_version: String,
    pub workstream_id: String,
    pub workspace_id: String,
    pub session_id: String,
    pub identity_source: String,
    pub repo: String,
    pub branch: String,
    pub default_dev_plane: String,
    pub vm_fallback_role: String,
    pub governance_state: String,
    pub governance_last_transition: String,
    pub promotion_scope: String,
    pub fallback_active: bool,
    pub handoff_present: bool,
    pub result_ready: bool,
    pub recipe_count: usize,
    pub last_successful_task: Option<WorkspaceLastSuccessfulTask>,
    pub last_result_reference: Option<WorkstreamLastResultReference>,
}

#[derive(Debug, Clone, Serialize)]
pub struct WorkstreamCockpitRecipeCard {
    pub id: String,
    pub kind: String,
    pub summary: String,
    pub recovery_points: Vec<String>,
}

#[derive(Debug, Clone, Serialize)]
pub struct WorkstreamCockpitHandoffPanel {
    pub handoff_required: bool,
    pub recovery_required: bool,
    pub handoff_present: bool,
    pub last_handoff: Option<String>,
    pub last_successful_task: Option<WorkspaceLastSuccessfulTask>,
}

#[derive(Debug, Clone, Serialize)]
pub struct WorkstreamCockpitResultSummary {
    pub job_id: u64,
    pub state: String,
    pub run_label: String,
    pub profile_id: String,
    pub node_list: String,
    pub manifest_key: String,
}

#[derive(Debug, Clone, Serialize)]
pub struct WorkstreamCockpitManifestSummary {
    pub job_id: u64,
    pub object_bucket: String,
    pub object_key: String,
    pub manifest_object_key: String,
    pub profile_id: Option<String>,
    pub run_label: Option<String>,
}

#[derive(Debug, Clone, Serialize)]
pub struct WorkstreamCockpitLastResultPanel {
    pub available: bool,
    pub reference: Option<WorkstreamLastResultReference>,
    pub summary: Option<WorkstreamCockpitResultSummary>,
    pub manifest: Option<WorkstreamCockpitManifestSummary>,
    pub error: Option<String>,
}

#[derive(Debug, Clone, Serialize)]
pub struct WorkstreamPremiumToolLaunchSurface {
    pub tool_id: String,
    pub label: String,
    pub open_label: String,
    pub launch_surface_kind: String,
    pub launch_path: String,
    pub cockpit_path: String,
    pub context_packet_path: String,
    pub program_id: Option<String>,
    pub campaign_id: Option<String>,
    pub program_context_packet_path: Option<String>,
    pub campaign_context_packet_path: Option<String>,
    pub workspace_habitat_path: String,
    pub workspace_habitat_env_path: String,
    pub workspace_habitat_browser_url: String,
    pub workspace_subagent_list_path: Option<String>,
    pub workspace_subagent_route_path: Option<String>,
    pub workspace_subagent_handoff_path: Option<String>,
    pub recommended_subagent_id: Option<String>,
    pub recommended_work_mode: Option<String>,
    pub retrieval_context_present: bool,
    pub retrieval_memory_ids: Vec<String>,
    pub retrieval_recommended_subagent_id: Option<String>,
    pub retrieval_recommended_work_mode: Option<String>,
    pub retrieval_launch_reason: Option<String>,
    pub compiled_context_present: bool,
    pub compiled_context_task_profile: Option<String>,
    pub compiled_context_budget_profile_id: Option<String>,
    pub compiled_context_memory_tiers: Vec<String>,
    pub compiled_context_top_memory_ids: Vec<String>,
    pub compiled_context_preview: Option<String>,
    pub planner: Option<IntentPlannerAvailability>,
    pub execution: Option<PlanExecutionStatusSummary>,
    pub plan_execution_path: String,
    pub remote_lane_kind: Option<String>,
    pub remote_lane_path: Option<String>,
    pub managed_attach_path: Option<String>,
    pub workspace_launch_resume_path: Option<String>,
    pub native_attach_path: Option<String>,
    pub tool_return_path: String,
    pub workspace_id: String,
    pub session_id: String,
    pub repo: String,
    pub branch: String,
    pub governance_state: String,
    pub shared_context_fields: Vec<String>,
    pub note: String,
}

#[derive(Debug, Clone, Serialize)]
pub struct WorkstreamPremiumToolLaunchResponse {
    pub status: String,
    pub phase: String,
    pub tool: WorkstreamPremiumToolLaunchSurface,
    pub envelope: WorkstreamSessionEnvelope,
    pub context_packet: WorkstreamContextPacket,
    pub handoff: WorkstreamCockpitHandoffPanel,
    pub last_result: WorkstreamCockpitLastResultPanel,
    pub recipe_ids: Vec<String>,
}

#[derive(Debug, Clone, Serialize)]
pub struct WorkstreamCockpitResponse {
    pub status: String,
    pub phase: String,
    pub workstream_id: String,
    pub envelope: WorkstreamSessionEnvelope,
    pub context_packet: WorkstreamContextPacket,
    pub recipes: Vec<WorkstreamCockpitRecipeCard>,
    pub handoff: WorkstreamCockpitHandoffPanel,
    pub last_result: WorkstreamCockpitLastResultPanel,
    pub tool_dock: Vec<WorkstreamPremiumToolLaunchSurface>,
    pub actions: WorkstreamControlRoomActionSupport,
}

#[derive(Debug, Clone, Copy)]
struct PremiumToolSpec {
    tool_id: &'static str,
    label: &'static str,
    open_label: &'static str,
    note: &'static str,
}

const PREMIUM_TOOLS: [PremiumToolSpec; 3] = [
    PremiumToolSpec {
        tool_id: "cursor",
        label: "Cursor",
        open_label: "Open in Cursor",
        note: "Visual IDE lane bound to the Beagle-owned workstream/session envelope.",
    },
    PremiumToolSpec {
        tool_id: "claude-code",
        label: "Claude Code",
        open_label: "Open Claude Code",
        note: "Agentic terminal lane bound to the same Beagle-owned workstream/session envelope.",
    },
    PremiumToolSpec {
        tool_id: "codex",
        label: "Codex",
        open_label: "Open Codex",
        note: "Codex terminal lane bound to the same Beagle-owned workstream/session envelope.",
    },
];

pub async fn get_workstream_cockpit(
    data_dir: &Path,
    cfg: &BeagleConfig,
    gateway: &DarwinHpcGatewayClient,
    workstream_id: &str,
) -> anyhow::Result<WorkstreamCockpitResponse> {
    let context_packet =
        get_workstream_context_packet(data_dir, cfg, gateway, workstream_id, WorkstreamContextPacketAugmentation::default())
            .await?;
    get_workstream_cockpit_with_context_packet(data_dir, cfg, gateway, workstream_id, context_packet).await
}

pub async fn get_workstream_cockpit_with_context_packet(
    data_dir: &Path,
    cfg: &BeagleConfig,
    gateway: &DarwinHpcGatewayClient,
    workstream_id: &str,
    context_packet: WorkstreamContextPacketResponse,
) -> anyhow::Result<WorkstreamCockpitResponse> {
    let detail = get_workstream_control_room_detail(data_dir, cfg, workstream_id)?;
    let last_result = match get_workstream_control_room_last_result(data_dir, cfg, gateway, workstream_id)
        .await
    {
        Ok(response) => last_result_panel_from_response(&response, None),
        Err(error) => last_result_panel_from_reference(
            detail.last_result_reference.clone(),
            Some(error.to_string()),
        ),
    };
    let envelope = session_envelope_from_detail(cfg, &detail, &last_result);
    let recipes = detail
        .recipes
        .iter()
        .map(recipe_card_from_document)
        .collect::<Vec<_>>();
    let handoff = WorkstreamCockpitHandoffPanel {
        handoff_required: detail.handoff_view.handoff_required,
        recovery_required: detail.handoff_view.recovery_required,
        handoff_present: detail.handoff_view.handoff_present,
        last_handoff: detail.handoff_view.last_handoff.clone(),
        last_successful_task: detail.handoff_view.last_successful_task.clone(),
    };
    let program_binding = resolve_program_campaign_binding_for_workstream(workstream_id).ok().flatten();
    let tool_dock =
        tool_dock_surfaces(cfg, &envelope, program_binding.as_ref(), &context_packet.packet);

    Ok(WorkstreamCockpitResponse {
        status: "ok".to_string(),
        phase: COCKPIT_PHASE.to_string(),
        workstream_id: workstream_id.to_string(),
        envelope,
        context_packet: context_packet.packet,
        recipes,
        handoff,
        last_result,
        tool_dock,
        actions: detail.status_view.actions,
    })
}

pub async fn get_premium_tool_launch_surface(
    data_dir: &Path,
    cfg: &BeagleConfig,
    gateway: &DarwinHpcGatewayClient,
    workstream_id: &str,
    tool_id: &str,
) -> anyhow::Result<WorkstreamPremiumToolLaunchResponse> {
    let context_packet =
        get_workstream_context_packet(data_dir, cfg, gateway, workstream_id, WorkstreamContextPacketAugmentation::default())
            .await?;
    get_premium_tool_launch_surface_with_context_packet(
        data_dir,
        cfg,
        gateway,
        workstream_id,
        tool_id,
        context_packet,
    )
    .await
}

pub async fn get_premium_tool_launch_surface_with_context_packet(
    data_dir: &Path,
    cfg: &BeagleConfig,
    gateway: &DarwinHpcGatewayClient,
    workstream_id: &str,
    tool_id: &str,
    context_packet: WorkstreamContextPacketResponse,
) -> anyhow::Result<WorkstreamPremiumToolLaunchResponse> {
    let tool = resolve_tool_spec(tool_id)?;
    let cockpit =
        get_workstream_cockpit_with_context_packet(data_dir, cfg, gateway, workstream_id, context_packet)
            .await?;
    let program_binding = resolve_program_campaign_binding_for_workstream(workstream_id).ok().flatten();
    let launch_surface = tool_launch_surface(
        cfg,
        tool,
        &cockpit.envelope,
        program_binding.as_ref(),
        &cockpit.context_packet,
    );

    Ok(WorkstreamPremiumToolLaunchResponse {
        status: "ok".to_string(),
        phase: COCKPIT_PHASE.to_string(),
        tool: launch_surface,
        envelope: cockpit.envelope,
        context_packet: cockpit.context_packet,
        handoff: cockpit.handoff,
        last_result: cockpit.last_result,
        recipe_ids: cockpit.recipes.into_iter().map(|recipe| recipe.id).collect(),
    })
}

pub fn render_workstream_cockpit_page(cockpit: &WorkstreamCockpitResponse) -> String {
    let envelope = &cockpit.envelope;
    let context_packet = &cockpit.context_packet;
    let last_handoff_html = cockpit
        .handoff
        .last_handoff
        .as_deref()
        .map(html_escape)
        .unwrap_or_else(|| "No handoff recorded yet.".to_string());
    let last_task_html = cockpit
        .handoff
        .last_successful_task
        .as_ref()
        .map(render_last_successful_task)
        .unwrap_or_else(|| "<p class=\"muted\">No successful task recorded yet.</p>".to_string());
    let last_result_html = render_last_result_panel(&cockpit.last_result);
    let recipe_cards = cockpit
        .recipes
        .iter()
        .map(|recipe| {
            let recovery_points = if recipe.recovery_points.is_empty() {
                "<span class=\"pill\">No explicit recovery points</span>".to_string()
            } else {
                recipe
                    .recovery_points
                    .iter()
                    .map(|point| format!("<span class=\"pill\">{}</span>", html_escape(point)))
                    .collect::<Vec<_>>()
                    .join("")
            };
            format!(
                "<article class=\"card recipe-card\"><h3>{}</h3><p class=\"mono\">{}</p><p>{}</p><div class=\"pill-row\">{}</div></article>",
                html_escape(&recipe.kind),
                html_escape(&recipe.id),
                html_escape(&recipe.summary),
                recovery_points
            )
        })
        .collect::<Vec<_>>()
        .join("");
    let tool_cards = cockpit
        .tool_dock
        .iter()
        .map(|tool| {
            format!(
                "<article class=\"tool-card\"><div><h3>{}</h3><p>{}</p><p class=\"mono\">workspace={} session={}</p><p class=\"mono\">context={} program={} campaign={} habitat={} env={} subagent_list={} subagent_route={} subagent_handoff={} recommended_subagent={} recommended_work_mode={} remote_lane={} managed_attach={} launch_resume={} native_attach={} writeback={}</p><p class=\"mono\">browser={}</p></div><a class=\"tool-link\" href=\"{}\" target=\"_blank\" rel=\"noreferrer\">{}</a></article>",
                html_escape(&tool.label),
                html_escape(&tool.note),
                html_escape(&tool.workspace_id),
                html_escape(&tool.session_id),
                html_escape(&tool.context_packet_path),
                html_escape(tool.program_context_packet_path.as_deref().unwrap_or("unresolved")),
                html_escape(tool.campaign_context_packet_path.as_deref().unwrap_or("unresolved")),
                html_escape(&tool.workspace_habitat_path),
                html_escape(&tool.workspace_habitat_env_path),
                html_escape(tool.workspace_subagent_list_path.as_deref().unwrap_or("n/a")),
                html_escape(tool.workspace_subagent_route_path.as_deref().unwrap_or("n/a")),
                html_escape(tool.workspace_subagent_handoff_path.as_deref().unwrap_or("n/a")),
                html_escape(tool.recommended_subagent_id.as_deref().unwrap_or("n/a")),
                html_escape(tool.recommended_work_mode.as_deref().unwrap_or("n/a")),
                html_escape(tool.remote_lane_path.as_deref().unwrap_or("n/a")),
                html_escape(tool.managed_attach_path.as_deref().unwrap_or("n/a")),
                html_escape(tool.workspace_launch_resume_path.as_deref().unwrap_or("n/a")),
                html_escape(tool.native_attach_path.as_deref().unwrap_or("n/a")),
                html_escape(&tool.tool_return_path),
                html_escape(&tool.workspace_habitat_browser_url),
                html_escape(&tool.launch_path),
                html_escape(&tool.open_label),
            )
        })
    .collect::<Vec<_>>()
        .join("");
    let action_cards = render_control_room_actions(&cockpit.actions);
    let recommended_recipe_html = context_packet
        .recommended_recipe
        .as_ref()
        .map(|recipe| {
            format!(
                "<div class=\"code-callout\">recommended={} ({})<br>{}</div>",
                html_escape(&recipe.id),
                html_escape(&recipe.kind),
                html_escape(&recipe.summary),
            )
        })
        .unwrap_or_else(|| {
            "<p class=\"muted\">No recommended recipe has been derived yet.</p>".to_string()
        });
    let physio_html = render_context_packet_physio(context_packet);
    let experiment_flags_html = render_context_packet_experiment_flags(context_packet);
    let memory_hits_html = render_context_packet_memory_hits(context_packet);

    format!(
        "<!doctype html>
<html lang=\"en\">
<head>
  <meta charset=\"utf-8\">
  <meta name=\"viewport\" content=\"width=device-width, initial-scale=1\">
  <title>Beagle Premium Tool Dock</title>
  <style>
    :root {{
      --ink: #18343a;
      --muted: #53717a;
      --accent: #006d77;
      --accent-soft: #d8f0ef;
      --sand: #f7f1e3;
      --paper: rgba(255,255,255,0.82);
      --line: rgba(24,52,58,0.12);
      --shadow: 0 20px 60px rgba(18,43,50,0.12);
      --mono: \"SFMono-Regular\", \"SF Mono\", Consolas, \"Liberation Mono\", Menlo, monospace;
      --serif: \"Iowan Old Style\", \"Palatino Linotype\", \"Book Antiqua\", Georgia, serif;
    }}
    * {{ box-sizing: border-box; }}
    body {{
      margin: 0;
      min-height: 100vh;
      color: var(--ink);
      background:
        radial-gradient(circle at top left, #f6debf 0%, rgba(246,222,191,0) 38%),
        radial-gradient(circle at top right, #cdece8 0%, rgba(205,236,232,0) 34%),
        linear-gradient(180deg, #f5efe4 0%, #eef5f3 55%, #e4edf5 100%);
      font-family: var(--serif);
    }}
    main {{
      width: min(1200px, calc(100% - 32px));
      margin: 24px auto 48px;
      display: grid;
      gap: 18px;
    }}
    .hero, .card {{
      background: var(--paper);
      backdrop-filter: blur(14px);
      border: 1px solid var(--line);
      border-radius: 22px;
      box-shadow: var(--shadow);
    }}
    .hero {{
      padding: 28px;
    }}
    h1, h2, h3 {{
      margin: 0;
      font-weight: 700;
      letter-spacing: -0.02em;
    }}
    h1 {{
      font-size: clamp(2rem, 3vw, 3.3rem);
      margin-bottom: 10px;
    }}
    h2 {{
      font-size: 1.35rem;
      margin-bottom: 14px;
    }}
    h3 {{
      font-size: 1rem;
      margin-bottom: 8px;
    }}
    p {{
      margin: 0;
      line-height: 1.5;
    }}
    .lede {{
      color: var(--muted);
      max-width: 70ch;
      margin-bottom: 18px;
    }}
    .grid {{
      display: grid;
      grid-template-columns: repeat(auto-fit, minmax(220px, 1fr));
      gap: 12px;
    }}
    .meta-block {{
      padding: 14px;
      border-radius: 16px;
      background: rgba(255,255,255,0.7);
      border: 1px solid var(--line);
    }}
    .label, .mono {{
      font-family: var(--mono);
      font-size: 0.86rem;
    }}
    .label {{
      display: block;
      color: var(--muted);
      text-transform: uppercase;
      letter-spacing: 0.08em;
      margin-bottom: 8px;
    }}
    .mono {{
      word-break: break-word;
    }}
    .section {{
      padding: 22px;
    }}
    .tool-grid, .panel-grid, .recipes-grid {{
      display: grid;
      gap: 14px;
    }}
    .tool-grid {{
      grid-template-columns: repeat(auto-fit, minmax(260px, 1fr));
    }}
    .action-grid {{
      display: grid;
      gap: 14px;
      grid-template-columns: repeat(auto-fit, minmax(260px, 1fr));
    }}
    .panel-grid {{
      grid-template-columns: repeat(auto-fit, minmax(280px, 1fr));
    }}
    .recipes-grid {{
      grid-template-columns: repeat(auto-fit, minmax(250px, 1fr));
    }}
    .tool-card, .recipe-card {{
      display: grid;
      gap: 12px;
      padding: 18px;
      border-radius: 18px;
      background: rgba(255,255,255,0.76);
      border: 1px solid var(--line);
    }}
    .action-card {{
      display: grid;
      gap: 10px;
      padding: 18px;
      border-radius: 18px;
      background: rgba(255,255,255,0.76);
      border: 1px solid var(--line);
    }}
    .tool-link {{
      display: inline-flex;
      align-items: center;
      justify-content: center;
      padding: 11px 16px;
      border-radius: 999px;
      background: linear-gradient(135deg, var(--accent) 0%, #1d3557 100%);
      color: white;
      text-decoration: none;
      font-weight: 700;
    }}
    .pill-row {{
      display: flex;
      flex-wrap: wrap;
      gap: 8px;
      margin-top: 8px;
    }}
    .pill {{
      padding: 6px 10px;
      border-radius: 999px;
      background: var(--accent-soft);
      color: var(--accent);
      font-family: var(--mono);
      font-size: 0.8rem;
    }}
    .muted {{
      color: var(--muted);
    }}
    .code-callout {{
      margin-top: 12px;
      padding: 14px;
      border-radius: 16px;
      border: 1px solid var(--line);
      background: rgba(255,255,255,0.64);
      font-family: var(--mono);
      font-size: 0.85rem;
      word-break: break-word;
    }}
    @media (max-width: 720px) {{
      main {{
        width: min(100% - 20px, 100%);
        margin-top: 16px;
      }}
      .hero, .section {{
        padding: 18px;
      }}
    }}
  </style>
</head>
<body>
  <main>
    <section class=\"hero\">
      <p class=\"label\">Beagle Premium Tool Dock MVP</p>
      <h1>{}</h1>
      <p class=\"lede\">One canonical workstream cockpit, one Beagle-owned session envelope, three premium work surfaces. Cursor, Claude Code, and Codex all inherit the same repo, branch, session, handoff, last result, recipes, and governance context.</p>
      <div class=\"grid\">
        <div class=\"meta-block\"><span class=\"label\">Repo</span><p class=\"mono\">{}</p></div>
        <div class=\"meta-block\"><span class=\"label\">Branch</span><p class=\"mono\">{}</p></div>
        <div class=\"meta-block\"><span class=\"label\">Workspace</span><p class=\"mono\">{}</p></div>
        <div class=\"meta-block\"><span class=\"label\">Session</span><p class=\"mono\">{}</p></div>
        <div class=\"meta-block\"><span class=\"label\">Governance</span><p class=\"mono\">{} / {}</p></div>
        <div class=\"meta-block\"><span class=\"label\">Dev Plane</span><p class=\"mono\">{} · fallback {}</p></div>
      </div>
      <div class=\"code-callout\">Envelope source: {} · handoff_present={} · result_ready={} · recipe_count={}</div>
    </section>

    <section class=\"card section\">
      <h2>Premium Tool Dock</h2>
      <p class=\"lede\">Each launch surface is bounded to the same Beagle session envelope and the same Beagle-owned context packet. The transport into the external tool remains outside the runtime in this MVP, but the session identity and shared context are already canonicalized here.</p>
      <div class=\"tool-grid\">{}</div>
    </section>

    <section class=\"panel-grid\">
      <article class=\"card section\">
        <h2>Context Packet</h2>
        <p class=\"muted\">The cockpit, Cursor, Claude Code, and Codex all derive from this same Beagle-owned packet.</p>
        {}
      </article>
      <article class=\"card section\">
        <h2>Latest Physio</h2>
        {}
      </article>
    </section>

    <section class=\"panel-grid\">
      <article class=\"card section\">
        <h2>Experiment Flags</h2>
        {}
      </article>
      <article class=\"card section\">
        <h2>Memory Hits</h2>
        {}
      </article>
    </section>

    <section class=\"card section\">
      <h2>Control Room Actions</h2>
      <p class=\"lede\">Bounded governance actions for the same canonical workstream/session envelope. Beagle remains the source of truth; these action endpoints are part of the same internal control-room surface.</p>
      <div class=\"action-grid\">{}</div>
    </section>

    <section class=\"panel-grid\">
      <article class=\"card section\">
        <h2>Handoff</h2>
        <p class=\"muted\">{}</p>
        <div class=\"code-callout\">{}</div>
      </article>
      <article class=\"card section\">
        <h2>Last Result</h2>
        {}
      </article>
    </section>

    <section class=\"card section\">
      <h2>Last Successful Task</h2>
      {}
    </section>

    <section class=\"card section\">
      <h2>Canonical Recipes</h2>
      <div class=\"recipes-grid\">{}</div>
    </section>
  </main>
</body>
</html>",
        html_escape(&cockpit.workstream_id),
        html_escape(&envelope.repo),
        html_escape(&envelope.branch),
        html_escape(&envelope.workspace_id),
        html_escape(&envelope.session_id),
        html_escape(&envelope.governance_state),
        html_escape(&envelope.governance_last_transition),
        html_escape(&envelope.default_dev_plane),
        html_escape(&envelope.vm_fallback_role),
        html_escape(&envelope.identity_source),
        envelope.handoff_present,
        envelope.result_ready,
        envelope.recipe_count,
        tool_cards,
        recommended_recipe_html,
        physio_html,
        experiment_flags_html,
        memory_hits_html,
        action_cards,
        if cockpit.handoff.handoff_required {
            "Handoff is required for this workstream."
        } else {
            "Handoff is optional for this workstream."
        },
        last_handoff_html,
        last_result_html,
        last_task_html,
        recipe_cards
    )
}

fn session_envelope_from_detail(
    cfg: &BeagleConfig,
    detail: &crate::WorkstreamControlRoomDetailResponse,
    last_result: &WorkstreamCockpitLastResultPanel,
) -> WorkstreamSessionEnvelope {
    let identity_source = if detail.status_view.live_session.is_some() {
        "live-session"
    } else if !detail.registry_entry.canonical_session_id.trim().is_empty() {
        "registry-canonical"
    } else {
        "config-default"
    }
    .to_string();

    let workspace_id = detail
        .status_view
        .live_session
        .as_ref()
        .map(|session| session.workspace_id.clone())
        .or_else(|| non_empty_string(&detail.registry_entry.latest_governance_validation_workspace_id))
        .or_else(|| non_empty_string(&detail.registry_entry.latest_validation_workspace_id))
        .or_else(|| non_empty_string(&detail.spec.promotion_state.latest_validation_workspace_id))
        .or_else(|| non_empty_string(&detail.spec.promotion_state.canonical_workspace_id))
        .unwrap_or_else(|| cfg.workspace.canonical_workspace_id.clone());

    let session_id = detail
        .status_view
        .live_session
        .as_ref()
        .map(|session| session.session_id.clone())
        .or_else(|| non_empty_string(&detail.registry_entry.latest_governance_validation_session_id))
        .or_else(|| non_empty_string(&detail.registry_entry.latest_validation_session_id))
        .or_else(|| non_empty_string(&detail.registry_entry.canonical_session_id))
        .or_else(|| non_empty_string(&detail.spec.promotion_state.latest_validation_session_id))
        .or_else(|| non_empty_string(&detail.spec.promotion_state.canonical_session_id))
        .unwrap_or_else(|| "unassigned-session".to_string());

    WorkstreamSessionEnvelope {
        envelope_version: SESSION_ENVELOPE_VERSION.to_string(),
        workstream_id: detail.registry_entry.id.clone(),
        workspace_id,
        session_id,
        identity_source,
        repo: detail.spec.repo.clone(),
        branch: detail.spec.default_branch.clone(),
        default_dev_plane: detail.status_view.default_dev_plane.clone(),
        vm_fallback_role: detail.status_view.vm_fallback_role.clone(),
        governance_state: detail.status_view.governance_state.clone(),
        governance_last_transition: detail.status_view.governance_last_transition.clone(),
        promotion_scope: detail.spec.scope.clone(),
        fallback_active: detail
            .status_view
            .live_session
            .as_ref()
            .map(|session| session.fallback_active)
            .unwrap_or(false),
        handoff_present: detail.handoff_view.handoff_present,
        result_ready: last_result.available || last_result.reference.is_some(),
        recipe_count: detail.recipes.len(),
        last_successful_task: detail.handoff_view.last_successful_task.clone(),
        last_result_reference: last_result.reference.clone(),
    }
}

fn tool_dock_surfaces(
    cfg: &BeagleConfig,
    envelope: &WorkstreamSessionEnvelope,
    program_binding: Option<&ProgramCampaignBinding>,
    context_packet: &WorkstreamContextPacket,
) -> Vec<WorkstreamPremiumToolLaunchSurface> {
    PREMIUM_TOOLS
        .iter()
        .map(|tool| tool_launch_surface(cfg, *tool, envelope, program_binding, context_packet))
        .collect()
}

fn tool_launch_surface(
    cfg: &BeagleConfig,
    tool: PremiumToolSpec,
    envelope: &WorkstreamSessionEnvelope,
    program_binding: Option<&ProgramCampaignBinding>,
    context_packet: &WorkstreamContextPacket,
) -> WorkstreamPremiumToolLaunchSurface {
    let program_id = program_binding.map(|binding| binding.program.id.clone());
    let campaign_id = program_binding.map(|binding| binding.campaign.id.clone());
    let habitat = &cfg.workspace.habitat;
    let default_subagent_id = default_subagent_for_tool(tool.tool_id).to_string();
    let default_work_mode = default_work_mode_for_tool(tool.tool_id).to_string();
    let retrieval_context = context_packet.retrieval_context.as_ref();
    let retrieval_memory_ids = retrieval_context
        .map(|context| context.top_memory_ids.clone())
        .unwrap_or_default();
    let retrieval_recommended_subagent_id = retrieval_context
        .and_then(|context| context.suggested_subagent_id.clone());
    let retrieval_recommended_work_mode = retrieval_context
        .and_then(|context| context.suggested_work_mode.clone());
    let compiled_context_task_profile = retrieval_context
        .and_then(|context| context.compiled_context_task_profile.clone());
    let compiled_context_budget_profile_id = retrieval_context
        .and_then(|context| context.compiled_context_budget_profile_id.clone());
    let compiled_context_memory_tiers = retrieval_context
        .map(|context| context.compiled_context_selected_memory_tiers.clone())
        .unwrap_or_default();
    let compiled_context_top_memory_ids = retrieval_context
        .map(|context| context.compiled_context_top_memory_ids.clone())
        .unwrap_or_default();
    let compiled_context_preview = retrieval_context
        .and_then(|context| context.compiled_context_preview.clone());
    let planner = retrieval_context.and_then(|context| context.planner.clone());
    let execution = retrieval_context.and_then(|context| context.execution.clone());
    let retrieval_launch_reason = retrieval_context.map(|context| {
        format!(
            "{} (dense={} sparse={})",
            context.influence_reason, context.dense_backend, context.sparse_backend
        )
    });
    let retrieval_override_allowed = retrieval_recommended_subagent_id
        .as_deref()
        .map(|subagent_id| subagent_supports_tool(subagent_id, tool.tool_id))
        .unwrap_or(false);
    let recommended_subagent_id = if retrieval_override_allowed {
        retrieval_recommended_subagent_id
            .clone()
            .unwrap_or_else(|| default_subagent_id.clone())
    } else {
        default_subagent_id.clone()
    };
    let recommended_work_mode = if retrieval_override_allowed {
        retrieval_recommended_work_mode
            .clone()
            .unwrap_or_else(|| default_work_mode.clone())
    } else {
        default_work_mode.clone()
    };
    WorkstreamPremiumToolLaunchSurface {
        tool_id: tool.tool_id.to_string(),
        label: tool.label.to_string(),
        open_label: tool.open_label.to_string(),
        launch_surface_kind: LAUNCH_SURFACE_KIND.to_string(),
        launch_path: format!(
            "{}/{}/tool-dock/{}",
            COCKPIT_API_PATH_PREFIX, envelope.workstream_id, tool.tool_id
        ),
        cockpit_path: format!("{}/{}/cockpit", COCKPIT_PAGE_PATH_PREFIX, envelope.workstream_id),
        context_packet_path: format!(
            "{}/{}/context-packet",
            COCKPIT_API_PATH_PREFIX, envelope.workstream_id
        ),
        program_context_packet_path: program_id.as_ref().map(|program_id| {
            format!("/api/darwin/programs/{}/context-packet", program_id)
        }),
        campaign_context_packet_path: campaign_id.as_ref().map(|campaign_id| {
            format!("/api/darwin/campaigns/{}/context-packet", campaign_id)
        }),
        program_id,
        campaign_id,
        workspace_habitat_path: format!(
            "{}/{}/workspace-habitat",
            COCKPIT_API_PATH_PREFIX, envelope.workstream_id
        ),
        workspace_habitat_env_path: format!(
            "{}/{}/workspace-habitat/context.env",
            COCKPIT_API_PATH_PREFIX, envelope.workstream_id
        ),
        workspace_habitat_browser_url: habitat.internal_base_url.clone(),
        workspace_subagent_list_path: Some(format!(
            "{}/{}/workspace-subagent-list",
            COCKPIT_API_PATH_PREFIX, envelope.workstream_id
        )),
        workspace_subagent_route_path: Some(format!(
            "{}/{}/workspace-subagent-route?tool_id={}&work_mode={}",
            COCKPIT_API_PATH_PREFIX,
            envelope.workstream_id,
            tool.tool_id,
            recommended_work_mode
        )),
        workspace_subagent_handoff_path: Some(format!(
            "{}/{}/workspace-subagent-handoff",
            COCKPIT_API_PATH_PREFIX, envelope.workstream_id
        )),
        recommended_subagent_id: Some(recommended_subagent_id),
        recommended_work_mode: Some(recommended_work_mode),
        retrieval_context_present: retrieval_context.is_some(),
        retrieval_memory_ids,
        retrieval_recommended_subagent_id,
        retrieval_recommended_work_mode,
        retrieval_launch_reason,
        compiled_context_present: retrieval_context
            .map(|context| context.compiled_context_task_profile.is_some())
            .unwrap_or(false),
        compiled_context_task_profile,
        compiled_context_budget_profile_id,
        compiled_context_memory_tiers,
        compiled_context_top_memory_ids,
        compiled_context_preview,
        planner,
        execution,
        plan_execution_path: format!(
            "{}/{}/plan-execution",
            COCKPIT_API_PATH_PREFIX, envelope.workstream_id
        ),
        remote_lane_kind: if tool.tool_id == "cursor" {
            Some("cursor-remote-lane".to_string())
        } else {
            None
        },
        remote_lane_path: if tool.tool_id == "cursor" {
            Some(format!(
                "{}/{}/cursor-remote-lane",
                COCKPIT_API_PATH_PREFIX, envelope.workstream_id
            ))
        } else {
            None
        },
        managed_attach_path: if tool.tool_id == "cursor" {
            Some(format!(
                "{}/{}/managed-attach",
                COCKPIT_API_PATH_PREFIX, envelope.workstream_id
            ))
        } else {
            None
        },
        workspace_launch_resume_path: if tool.tool_id == "cursor" {
            Some(format!(
                "{}/{}/workspace-launch-resume",
                COCKPIT_API_PATH_PREFIX, envelope.workstream_id
            ))
        } else {
            None
        },
        native_attach_path: if tool.tool_id == "cursor" {
            Some(format!(
                "{}/{}/cursor-native-attach",
                COCKPIT_API_PATH_PREFIX, envelope.workstream_id
            ))
        } else {
            None
        },
        tool_return_path: format!(
            "{}/{}/tool-return",
            COCKPIT_API_PATH_PREFIX, envelope.workstream_id
        ),
        workspace_id: envelope.workspace_id.clone(),
        session_id: envelope.session_id.clone(),
        repo: envelope.repo.clone(),
        branch: envelope.branch.clone(),
        governance_state: envelope.governance_state.clone(),
        shared_context_fields: SHARED_CONTEXT_FIELDS.iter().map(|field| field.to_string()).collect(),
        note: tool.note.to_string(),
    }
}

fn subagent_supports_tool(subagent_id: &str, tool_id: &str) -> bool {
    let normalized_subagent = subagent_id.trim().to_ascii_lowercase();
    let normalized_tool = tool_id.trim().to_ascii_lowercase();

    match normalized_subagent.as_str() {
        "core" => matches!(normalized_tool.as_str(), "cursor" | "codex"),
        "experiments" => matches!(
            normalized_tool.as_str(),
            "claude-code" | "claude_code" | "claude"
        ),
        "manuscript" => matches!(
            normalized_tool.as_str(),
            "cursor" | "claude-code" | "claude_code" | "claude"
        ),
        _ => false,
    }
}

fn resolve_tool_spec(tool_id: &str) -> anyhow::Result<PremiumToolSpec> {
    let normalized = tool_id.trim().to_ascii_lowercase();
    let resolved = match normalized.as_str() {
        "cursor" => PREMIUM_TOOLS[0],
        "claude-code" | "claude_code" | "claude" => PREMIUM_TOOLS[1],
        "codex" => PREMIUM_TOOLS[2],
        _ => {
            return Err(anyhow!(
                "unsupported premium tool {}; expected one of cursor, claude-code, codex",
                tool_id
            ))
        }
    };
    Ok(resolved)
}

fn recipe_card_from_document(recipe: &WorkstreamRecipeDocument) -> WorkstreamCockpitRecipeCard {
    WorkstreamCockpitRecipeCard {
        id: recipe.id.clone(),
        kind: recipe.kind.clone(),
        summary: recipe.summary.clone(),
        recovery_points: recipe.recovery_points.clone(),
    }
}

fn last_result_panel_from_response(
    response: &crate::WorkstreamControlRoomLastResultResponse,
    error: Option<String>,
) -> WorkstreamCockpitLastResultPanel {
    let summary = response.result.as_ref().map(result_summary_from_entry);
    let manifest = response.manifest.as_ref().map(manifest_summary_from_manifest);
    WorkstreamCockpitLastResultPanel {
        available: summary.is_some(),
        reference: response.last_result_reference.clone(),
        summary,
        manifest,
        error,
    }
}

fn last_result_panel_from_reference(
    reference: Option<WorkstreamLastResultReference>,
    error: Option<String>,
) -> WorkstreamCockpitLastResultPanel {
    WorkstreamCockpitLastResultPanel {
        available: false,
        reference,
        summary: None,
        manifest: None,
        error,
    }
}

fn result_summary_from_entry(entry: &ResultCatalogEntry) -> WorkstreamCockpitResultSummary {
    WorkstreamCockpitResultSummary {
        job_id: entry.job_id,
        state: entry.state.clone(),
        run_label: entry.run_label.clone(),
        profile_id: entry.profile_id.clone(),
        node_list: entry.node_list.clone(),
        manifest_key: entry.artifact_manifest_key.clone(),
    }
}

fn manifest_summary_from_manifest(manifest: &ObjectResultManifest) -> WorkstreamCockpitManifestSummary {
    WorkstreamCockpitManifestSummary {
        job_id: manifest.job_id,
        object_bucket: manifest.object_bucket.clone(),
        object_key: manifest.object_key.clone(),
        manifest_object_key: manifest.manifest_object_key.clone(),
        profile_id: manifest.profile_id.clone(),
        run_label: manifest.run_label.clone(),
    }
}

fn render_last_successful_task(task: &WorkspaceLastSuccessfulTask) -> String {
    format!(
        "<div class=\"grid\">\
            <div class=\"meta-block\"><span class=\"label\">Task Kind</span><p class=\"mono\">{}</p></div>\
            <div class=\"meta-block\"><span class=\"label\">Profile</span><p class=\"mono\">{}</p></div>\
            <div class=\"meta-block\"><span class=\"label\">Run Label</span><p class=\"mono\">{}</p></div>\
            <div class=\"meta-block\"><span class=\"label\">Published Result Job</span><p class=\"mono\">{}</p></div>\
         </div>",
        html_escape(&task.task_kind),
        html_escape(&task.profile_id),
        html_escape(&task.workflow_run_label),
        task.published_result_job_id
    )
}

fn render_last_result_panel(panel: &WorkstreamCockpitLastResultPanel) -> String {
    if let Some(summary) = &panel.summary {
        let manifest = panel
            .manifest
            .as_ref()
            .map(|manifest| {
                format!(
                    "<div class=\"code-callout\">manifest={} bucket={} object={}</div>",
                    html_escape(&manifest.manifest_object_key),
                    html_escape(&manifest.object_bucket),
                    html_escape(&manifest.object_key)
                )
            })
            .unwrap_or_default();
        return format!(
            "<div class=\"grid\">\
                <div class=\"meta-block\"><span class=\"label\">Job</span><p class=\"mono\">{}</p></div>\
                <div class=\"meta-block\"><span class=\"label\">State</span><p class=\"mono\">{}</p></div>\
                <div class=\"meta-block\"><span class=\"label\">Profile</span><p class=\"mono\">{}</p></div>\
                <div class=\"meta-block\"><span class=\"label\">Run Label</span><p class=\"mono\">{}</p></div>\
             </div>{}",
            summary.job_id,
            html_escape(&summary.state),
            html_escape(&summary.profile_id),
            html_escape(&summary.run_label),
            manifest
        );
    }

    if let Some(reference) = &panel.reference {
        let error_html = panel
            .error
            .as_deref()
            .map(|error| {
                format!(
                    "<div class=\"code-callout\">Last-result lookup stayed bounded: {}</div>",
                    html_escape(error)
                )
            })
            .unwrap_or_default();
        return format!(
            "<p class=\"muted\">A published result reference exists but the full result payload is not currently resolved.</p>\
             <div class=\"code-callout\">job={} run_label={} manifest_key={}</div>{}",
            reference.job_id,
            html_escape(reference.run_label.as_deref().unwrap_or("n/a")),
            html_escape(reference.manifest_key.as_deref().unwrap_or("n/a")),
            error_html
        );
    }

    "<p class=\"muted\">No published result is attached to this workstream session yet.</p>".to_string()
}

fn render_control_room_actions(actions: &WorkstreamControlRoomActionSupport) -> String {
    [
        ("Hold", &actions.hold),
        ("Resume", &actions.resume),
    ]
    .into_iter()
    .map(|(label, action)| {
        format!(
            "<article class=\"action-card\"><h3>{}</h3><p class=\"mono\">endpoint={}</p><p class=\"muted\">enabled={}</p><div class=\"code-callout\">{}</div></article>",
            html_escape(label),
            html_escape(&action.endpoint),
            action.enabled,
            html_escape(&action.reason)
        )
    })
    .collect::<Vec<_>>()
    .join("")
}

fn render_context_packet_physio(packet: &WorkstreamContextPacket) -> String {
    packet
        .latest_physio
        .as_ref()
        .map(|snapshot| {
            format!(
                "<div class=\"grid\">\
                    <div class=\"meta-block\"><span class=\"label\">HR</span><p class=\"mono\">{}</p></div>\
                    <div class=\"meta-block\"><span class=\"label\">HRV</span><p class=\"mono\">{}</p></div>\
                    <div class=\"meta-block\"><span class=\"label\">SpO2</span><p class=\"mono\">{}</p></div>\
                    <div class=\"meta-block\"><span class=\"label\">Source</span><p class=\"mono\">{}</p></div>\
                 </div>\
                 <div class=\"code-callout\">timestamp={}</div>",
                snapshot.hr.map(|value| format!("{value:.1}")).unwrap_or_else(|| "n/a".to_string()),
                snapshot.hrv_level.clone().unwrap_or_else(|| "n/a".to_string()),
                snapshot
                    .spo2
                    .map(|value| format!("{value:.1}"))
                    .unwrap_or_else(|| "n/a".to_string()),
                html_escape(snapshot.source.as_deref().unwrap_or("n/a")),
                html_escape(
                    &snapshot
                        .timestamp
                        .map(|value| value.to_rfc3339())
                        .unwrap_or_else(|| "n/a".to_string()),
                ),
            )
        })
        .unwrap_or_else(|| "<p class=\"muted\">No physiological snapshot is attached to the current packet.</p>".to_string())
}

fn render_context_packet_experiment_flags(packet: &WorkstreamContextPacket) -> String {
    packet
        .experiment_flags
        .as_ref()
        .map(|flags| {
            format!(
                "<div class=\"grid\">\
                    <div class=\"meta-block\"><span class=\"label\">hrv_aware</span><p class=\"mono\">{}</p></div>\
                    <div class=\"meta-block\"><span class=\"label\">observer_enabled</span><p class=\"mono\">{}</p></div>\
                    <div class=\"meta-block\"><span class=\"label\">serendipity_enabled</span><p class=\"mono\">{}</p></div>\
                    <div class=\"meta-block\"><span class=\"label\">triad_enabled</span><p class=\"mono\">{}</p></div>\
                 </div>\
                 <div class=\"code-callout\">provider={} model={} experiment_id={} condition={}</div>",
                render_optional_bool(flags.hrv_aware),
                render_optional_bool(flags.observer_enabled),
                render_optional_bool(flags.serendipity_enabled),
                render_optional_bool(flags.triad_enabled),
                html_escape(flags.provider.as_deref().unwrap_or("n/a")),
                html_escape(flags.model.as_deref().unwrap_or("n/a")),
                html_escape(flags.experiment_id.as_deref().unwrap_or("n/a")),
                html_escape(flags.condition.as_deref().unwrap_or("n/a")),
            )
        })
        .unwrap_or_else(|| "<p class=\"muted\">No experiment flags were resolved for this packet.</p>".to_string())
}

fn render_context_packet_memory_hits(packet: &WorkstreamContextPacket) -> String {
    if packet.memory_hits.is_empty() {
        return "<p class=\"muted\">No bounded memory hits are attached to the current packet.</p>"
            .to_string();
    }

    packet
        .memory_hits
        .iter()
        .map(|hit| {
            let tags = if hit.tags.is_empty() {
                "<span class=\"pill\">untagged</span>".to_string()
            } else {
                hit.tags
                    .iter()
                    .map(|tag| format!("<span class=\"pill\">{}</span>", html_escape(tag)))
                    .collect::<Vec<_>>()
                    .join("")
            };
            format!(
                "<article class=\"recipe-card\">\
                    <h3>{}</h3>\
                    <p class=\"mono\">conversation={} turn={} role={} relevance={:.3}</p>\
                    <p>{}</p>\
                    <div class=\"pill-row\">{}</div>\
                 </article>",
                html_escape(&hit.source),
                html_escape(hit.conversation_id.as_deref().unwrap_or("n/a")),
                hit.turn_index
                    .map(|value| value.to_string())
                    .unwrap_or_else(|| "n/a".to_string()),
                html_escape(hit.role.as_deref().unwrap_or("n/a")),
                hit.relevance,
                html_escape(&hit.snippet),
                tags,
            )
        })
        .collect::<Vec<_>>()
        .join("")
}

fn render_optional_bool(value: Option<bool>) -> &'static str {
    match value {
        Some(true) => "true",
        Some(false) => "false",
        None => "n/a",
    }
}

fn html_escape(input: &str) -> String {
    input
        .replace('&', "&amp;")
        .replace('<', "&lt;")
        .replace('>', "&gt;")
        .replace('"', "&quot;")
        .replace('\'', "&#39;")
}

fn non_empty_string(value: &str) -> Option<String> {
    let trimmed = value.trim();
    if trimmed.is_empty() {
        None
    } else {
        Some(trimmed.to_string())
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::workspace_plane::{write_workspace_session, WorkspaceSessionState};
    use beagle_config::{
        AdvancedModulesConfig, ConsumerAccessConfig, GraphConfig, HermesConfig, LlmConfig,
        ObserverThresholds, StorageConfig, ToolBridgeConfig, WorkspaceHabitatConfig,
        WorkspacePlaneConfig,
    };
    use chrono::Utc;
    use std::fs;
    use std::path::{Path, PathBuf};
    use std::sync::Mutex;
    use std::time::{SystemTime, UNIX_EPOCH};
    use tokio::io::{AsyncReadExt, AsyncWriteExt};
    use tokio::net::TcpListener;
    use tokio::time::{timeout, Duration};

    const CANONICAL_WORKSTREAM_ID: &str = "beagle-darwin-hpc-governance";
    static ENV_LOCK: Mutex<()> = Mutex::new(());

    struct TestDir {
        path: PathBuf,
    }

    impl TestDir {
        fn new(label: &str) -> Self {
            let unique = SystemTime::now()
                .duration_since(UNIX_EPOCH)
                .unwrap()
                .as_nanos();
            let path = std::env::temp_dir().join(format!(
                "beagle-darwin-workstream-cockpit-{label}-{}-{unique}",
                std::process::id()
            ));
            fs::create_dir_all(&path).unwrap();
            Self { path }
        }

        fn path(&self) -> &Path {
            &self.path
        }
    }

    impl Drop for TestDir {
        fn drop(&mut self) {
            let _ = fs::remove_dir_all(&self.path);
        }
    }

    fn test_config(data_dir: &Path) -> BeagleConfig {
        BeagleConfig {
            profile: "cluster".to_string(),
            safe_mode: true,
            api_token: Some("test-token".to_string()),
            llm: LlmConfig::default(),
            storage: StorageConfig {
                data_dir: data_dir.display().to_string(),
            },
            graph: GraphConfig::default(),
            hermes: HermesConfig::default(),
            tool_bridge: ToolBridgeConfig::default(),
            workspace: WorkspacePlaneConfig {
                canonical_workspace_id: "test-cockpit".to_string(),
                canonical_repo: "agourakis82/beagle".to_string(),
                canonical_branch: "feat/darwin-hpc-governance".to_string(),
                canonical_track: "darwin-hpc".to_string(),
                operator_name: Some("test-operator".to_string()),
                default_dev_plane: "beagle-cluster".to_string(),
                vm_fallback_role: "fallback-only".to_string(),
                promotion_scope: "beagle-darwin-hpc-general-noninfra".to_string(),
                cutover_workstream: CANONICAL_WORKSTREAM_ID.to_string(),
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
        }
    }

    fn seeded_session(cfg: &BeagleConfig, workspace_id: &str, session_id: &str) -> WorkspaceSessionState {
        let mut session = WorkspaceSessionState::new(
            cfg,
            workspace_id.to_string(),
            Some(session_id.to_string()),
        );
        session.updated_at = Utc::now();
        session.last_handoff = Some("resume from premium tool dock".to_string());
        session.last_published_result_job_id = Some(42);
        session.last_published_result_run_label = Some("b152-tool-dock".to_string());
        session.last_published_result_profile_id = Some("gpu-single-v1".to_string());
        session.last_published_result_node_list = Some("r740-proxmox".to_string());
        session.last_published_manifest_key = Some("results/42/manifest.json".to_string());
        session.last_successful_task = Some(last_successful_task(session_id));
        session
    }

    fn last_successful_task(session_id: &str) -> WorkspaceLastSuccessfulTask {
        WorkspaceLastSuccessfulTask {
            task_kind: "advanced_operator_gpu_workflow".to_string(),
            task_state: "completed".to_string(),
            profile_id: "gpu-single-v1".to_string(),
            workflow_run_label: "b152-premium-gpu".to_string(),
            execution_node: Some("r740-proxmox".to_string()),
            resolved_result_node: Some("r740-proxmox".to_string()),
            repo: "agourakis82/beagle".to_string(),
            branch: "feat/darwin-hpc-governance".to_string(),
            session_id: session_id.to_string(),
            submitted_job_id: 55,
            published_result_job_id: 42,
            published_result_run_label: "b152-tool-dock".to_string(),
            completed_at: Utc::now(),
        }
    }

    fn sample_result() -> ResultCatalogEntry {
        ResultCatalogEntry {
            artifact_bucket: "beagle-results".to_string(),
            artifact_manifest_key: "results/42/manifest.json".to_string(),
            artifact_object_key: Some("results/42/output.txt".to_string()),
            artifact_prefix: "results/42".to_string(),
            artifact_sha256: "abc123".to_string(),
            end_time: Some("2026-03-22T00:00:00Z".to_string()),
            exit_code: Some(0),
            job_id: 42,
            job_name: "gpu-job".to_string(),
            node_list: "r740-proxmox".to_string(),
            partition: Some("gpu".to_string()),
            profile_id: "gpu-single-v1".to_string(),
            publication_time: Some("2026-03-22T00:01:00Z".to_string()),
            retention_scope: "active".to_string(),
            run_label: "b152-tool-dock".to_string(),
            source_phase: Some("B15.2".to_string()),
            source_run_id: Some("b152-0000000000".to_string()),
            start_time: Some("2026-03-22T00:00:10Z".to_string()),
            state: "COMPLETED".to_string(),
            submit_time: Some("2026-03-21T23:59:30Z".to_string()),
        }
    }

    fn sample_manifest() -> ObjectResultManifest {
        ObjectResultManifest {
            artifact_source: Some("object-backed".to_string()),
            end_time: Some("2026-03-22T00:00:00Z".to_string()),
            exit_code: Some(0),
            gateway_retrieval_time: Some("2026-03-22T00:01:05Z".to_string()),
            job_id: 42,
            job_name: Some("gpu-job".to_string()),
            manifest_format: Some("json".to_string()),
            manifest_object_key: "results/42/manifest.json".to_string(),
            node_list: Some("r740-proxmox".to_string()),
            object_bucket: "beagle-results".to_string(),
            object_key: "results/42/output.txt".to_string(),
            object_manifest_resolved_key: Some("results/42/manifest.json".to_string()),
            object_retrieval_mode: Some("catalog".to_string()),
            partition: Some("gpu".to_string()),
            profile_id: Some("gpu-single-v1".to_string()),
            publication_target_id: Some("rgw".to_string()),
            publication_time: Some("2026-03-22T00:01:00Z".to_string()),
            published_checksum: "abc123".to_string(),
            published_objects: vec![],
            retrieval_source: Some("gateway".to_string()),
            run_label: Some("b152-tool-dock".to_string()),
            source_manifest_path: Some("/tmp/manifest.json".to_string()),
            source_phase: Some("B15.2".to_string()),
            source_run_id: Some("b152-0000000000".to_string()),
            start_time: Some("2026-03-22T00:00:10Z".to_string()),
            state: Some("COMPLETED".to_string()),
            submit_time: Some("2026-03-21T23:59:30Z".to_string()),
        }
    }

    async fn spawn_gateway_server(
        result: ResultCatalogEntry,
        manifest: ObjectResultManifest,
    ) -> (String, tokio::task::JoinHandle<()>) {
        let listener = TcpListener::bind("127.0.0.1:0").await.unwrap();
        let base_url = format!("http://{}", listener.local_addr().unwrap());
        let result_body = serde_json::to_vec(&result).unwrap();
        let manifest_body = serde_json::to_vec(&manifest).unwrap();

        let handle = tokio::spawn(async move {
            loop {
                let accept_result = timeout(Duration::from_millis(250), listener.accept()).await;
                let Ok(Ok((mut stream, _))) = accept_result else {
                    break;
                };
                let mut buf = [0u8; 4096];
                let read = stream.read(&mut buf).await.unwrap();
                let request = String::from_utf8_lossy(&buf[..read]);
                let first_line = request.lines().next().unwrap_or_default();
                let (status_line, body) = if first_line.starts_with("GET /results/42/manifest ") {
                    ("HTTP/1.1 200 OK\r\n", manifest_body.as_slice())
                } else if first_line.starts_with("GET /results/42 ") {
                    ("HTTP/1.1 200 OK\r\n", result_body.as_slice())
                } else {
                    ("HTTP/1.1 404 Not Found\r\n", b"{\"error\":\"not_found\"}" as &[u8])
                };

                let headers = format!(
                    "{status_line}content-type: application/json\r\ncontent-length: {}\r\nconnection: close\r\n\r\n",
                    body.len()
                );
                stream.write_all(headers.as_bytes()).await.unwrap();
                stream.write_all(body).await.unwrap();
            }
        });

        (base_url, handle)
    }

    #[tokio::test]
    async fn cockpit_consolidates_shared_session_envelope_and_tool_dock() {
        let dir = TestDir::new("cockpit");
        let cfg = test_config(dir.path());
        let session = seeded_session(&cfg, &cfg.workspace.canonical_workspace_id, "ws-cockpit");
        write_workspace_session(dir.path(), &session).unwrap();

        let (base_url, handle) = spawn_gateway_server(sample_result(), sample_manifest()).await;
        let _env_lock = ENV_LOCK.lock().unwrap_or_else(|error| error.into_inner());
        std::env::set_var("BEAGLE_DARWIN_HPC_GATEWAY_BASE_URL", &base_url);
        std::env::set_var("BEAGLE_DARWIN_HPC_GATEWAY_TIMEOUT_SECONDS", "5");

        let gateway = DarwinHpcGatewayClient::from_env().unwrap();
        let cockpit = get_workstream_cockpit(dir.path(), &cfg, &gateway, CANONICAL_WORKSTREAM_ID)
            .await
            .unwrap();

        std::env::remove_var("BEAGLE_DARWIN_HPC_GATEWAY_BASE_URL");
        std::env::remove_var("BEAGLE_DARWIN_HPC_GATEWAY_TIMEOUT_SECONDS");
        handle.await.unwrap();

        assert_eq!(cockpit.status, "ok");
        assert_eq!(cockpit.workstream_id, CANONICAL_WORKSTREAM_ID);
        assert_eq!(cockpit.envelope.workspace_id, cfg.workspace.canonical_workspace_id);
        assert_eq!(cockpit.envelope.session_id, "ws-cockpit");
        assert_eq!(cockpit.envelope.repo, "agourakis82/beagle");
        assert_eq!(cockpit.envelope.branch, "feat/darwin-hpc-governance");
        assert_eq!(cockpit.envelope.governance_state, "canonical");
        assert!(cockpit.envelope.handoff_present);
        assert!(cockpit.envelope.result_ready);
        assert_eq!(cockpit.recipes.len(), 4);
        assert_eq!(cockpit.tool_dock.len(), 3);
        assert!(cockpit.last_result.available);
        assert_eq!(cockpit.last_result.summary.as_ref().unwrap().job_id, 42);

        for tool in &cockpit.tool_dock {
            assert_eq!(tool.workspace_id, cockpit.envelope.workspace_id);
            assert_eq!(tool.session_id, cockpit.envelope.session_id);
            assert_eq!(tool.repo, cockpit.envelope.repo);
            assert_eq!(tool.branch, cockpit.envelope.branch);
            assert_eq!(tool.governance_state, cockpit.envelope.governance_state);
            assert_eq!(
                tool.program_context_packet_path.as_deref(),
                Some("/api/darwin/programs/beagle-physio-symbolic-exocortex/context-packet")
            );
            assert_eq!(
                tool.campaign_context_packet_path.as_deref(),
                Some("/api/darwin/campaigns/expedition-002-hrv-aware/context-packet")
            );
            assert!(tool.launch_path.contains(CANONICAL_WORKSTREAM_ID));
            assert_eq!(
                tool.tool_return_path,
                format!("/api/darwin/workstreams/{}/tool-return", CANONICAL_WORKSTREAM_ID)
            );
        }
    }

    #[tokio::test]
    async fn tool_launch_surfaces_share_the_same_beagle_owned_envelope() {
        let dir = TestDir::new("tool-launch");
        let cfg = test_config(dir.path());
        let session = seeded_session(&cfg, &cfg.workspace.canonical_workspace_id, "ws-tools");
        write_workspace_session(dir.path(), &session).unwrap();

        let (base_url, handle) = spawn_gateway_server(sample_result(), sample_manifest()).await;
        let _env_lock = ENV_LOCK.lock().unwrap_or_else(|error| error.into_inner());
        std::env::set_var("BEAGLE_DARWIN_HPC_GATEWAY_BASE_URL", &base_url);
        std::env::set_var("BEAGLE_DARWIN_HPC_GATEWAY_TIMEOUT_SECONDS", "5");

        let gateway = DarwinHpcGatewayClient::from_env().unwrap();
        let cursor = get_premium_tool_launch_surface(
            dir.path(),
            &cfg,
            &gateway,
            CANONICAL_WORKSTREAM_ID,
            "cursor",
        )
        .await
        .unwrap();
        let claude = get_premium_tool_launch_surface(
            dir.path(),
            &cfg,
            &gateway,
            CANONICAL_WORKSTREAM_ID,
            "claude-code",
        )
        .await
        .unwrap();
        let codex = get_premium_tool_launch_surface(
            dir.path(),
            &cfg,
            &gateway,
            CANONICAL_WORKSTREAM_ID,
            "codex",
        )
        .await
        .unwrap();

        std::env::remove_var("BEAGLE_DARWIN_HPC_GATEWAY_BASE_URL");
        std::env::remove_var("BEAGLE_DARWIN_HPC_GATEWAY_TIMEOUT_SECONDS");
        handle.await.unwrap();

        assert_eq!(cursor.envelope.workspace_id, claude.envelope.workspace_id);
        assert_eq!(claude.envelope.workspace_id, codex.envelope.workspace_id);
        assert_eq!(cursor.envelope.session_id, claude.envelope.session_id);
        assert_eq!(claude.envelope.session_id, codex.envelope.session_id);
        assert_eq!(cursor.envelope.last_result_reference.as_ref().unwrap().job_id, 42);
        assert_eq!(cursor.recipe_ids.len(), 4);
        assert_eq!(claude.recipe_ids.len(), 4);
        assert_eq!(codex.recipe_ids.len(), 4);
        assert_eq!(cursor.tool.launch_surface_kind, LAUNCH_SURFACE_KIND);
        assert_eq!(claude.tool.launch_surface_kind, LAUNCH_SURFACE_KIND);
        assert_eq!(codex.tool.launch_surface_kind, LAUNCH_SURFACE_KIND);
        assert_eq!(
            cursor.tool.program_context_packet_path.as_deref(),
            Some("/api/darwin/programs/beagle-physio-symbolic-exocortex/context-packet")
        );
        assert_eq!(
            cursor.tool.campaign_context_packet_path.as_deref(),
            Some("/api/darwin/campaigns/expedition-002-hrv-aware/context-packet")
        );
        assert_eq!(
            cursor.tool.program_context_packet_path,
            claude.tool.program_context_packet_path
        );
        assert_eq!(
            claude.tool.program_context_packet_path,
            codex.tool.program_context_packet_path
        );
        assert_eq!(
            cursor.tool.campaign_context_packet_path,
            claude.tool.campaign_context_packet_path
        );
        assert_eq!(
            claude.tool.campaign_context_packet_path,
            codex.tool.campaign_context_packet_path
        );
        assert_eq!(
            cursor.tool.tool_return_path,
            format!("/api/darwin/workstreams/{}/tool-return", CANONICAL_WORKSTREAM_ID)
        );
        assert_eq!(
            cursor.tool.remote_lane_kind.as_deref(),
            Some("cursor-remote-lane")
        );
        assert_eq!(
            cursor.tool.remote_lane_path.as_deref(),
            Some("/api/darwin/workstreams/beagle-darwin-hpc-governance/cursor-remote-lane")
        );
        assert_eq!(
            cursor.tool.native_attach_path.as_deref(),
            Some("/api/darwin/workstreams/beagle-darwin-hpc-governance/cursor-native-attach")
        );
        assert_eq!(
            cursor.tool.managed_attach_path.as_deref(),
            Some("/api/darwin/workstreams/beagle-darwin-hpc-governance/managed-attach")
        );
        assert_eq!(
            cursor.tool.workspace_launch_resume_path.as_deref(),
            Some("/api/darwin/workstreams/beagle-darwin-hpc-governance/workspace-launch-resume")
        );
        assert_eq!(
            cursor.tool.workspace_subagent_list_path.as_deref(),
            Some("/api/darwin/workstreams/beagle-darwin-hpc-governance/workspace-subagent-list")
        );
        assert_eq!(
            cursor.tool.workspace_subagent_route_path.as_deref(),
            Some("/api/darwin/workstreams/beagle-darwin-hpc-governance/workspace-subagent-route?tool_id=cursor&work_mode=interactive-editing")
        );
        assert_eq!(
            cursor.tool.workspace_subagent_handoff_path.as_deref(),
            Some("/api/darwin/workstreams/beagle-darwin-hpc-governance/workspace-subagent-handoff")
        );
        assert_eq!(cursor.tool.recommended_subagent_id.as_deref(), Some("core"));
        assert_eq!(cursor.tool.recommended_work_mode.as_deref(), Some("interactive-editing"));
        assert_eq!(
            claude.tool.workspace_subagent_route_path.as_deref(),
            Some("/api/darwin/workstreams/beagle-darwin-hpc-governance/workspace-subagent-route?tool_id=claude-code&work_mode=analysis")
        );
        assert_eq!(claude.tool.recommended_subagent_id.as_deref(), Some("experiments"));
        assert_eq!(claude.tool.recommended_work_mode.as_deref(), Some("analysis"));
        assert_eq!(
            claude.tool.workspace_subagent_handoff_path.as_deref(),
            Some("/api/darwin/workstreams/beagle-darwin-hpc-governance/workspace-subagent-handoff")
        );
        assert_eq!(
            codex.tool.workspace_subagent_route_path.as_deref(),
            Some("/api/darwin/workstreams/beagle-darwin-hpc-governance/workspace-subagent-route?tool_id=codex&work_mode=implementation")
        );
        assert_eq!(codex.tool.recommended_subagent_id.as_deref(), Some("core"));
        assert_eq!(codex.tool.recommended_work_mode.as_deref(), Some("implementation"));
        assert_eq!(
            codex.tool.workspace_subagent_handoff_path.as_deref(),
            Some("/api/darwin/workstreams/beagle-darwin-hpc-governance/workspace-subagent-handoff")
        );
        assert!(claude.tool.remote_lane_path.is_none());
        assert!(codex.tool.remote_lane_path.is_none());
        assert!(claude.tool.native_attach_path.is_none());
        assert!(codex.tool.native_attach_path.is_none());
        assert!(claude.tool.managed_attach_path.is_none());
        assert!(codex.tool.managed_attach_path.is_none());
        assert!(claude.tool.workspace_launch_resume_path.is_none());
        assert!(codex.tool.workspace_launch_resume_path.is_none());
        assert_eq!(cursor.tool.tool_return_path, claude.tool.tool_return_path);
        assert_eq!(claude.tool.tool_return_path, codex.tool.tool_return_path);
    }

    #[tokio::test]
    async fn rendered_cockpit_page_contains_required_context_and_tool_labels() {
        let dir = TestDir::new("html");
        let cfg = test_config(dir.path());
        let session = seeded_session(&cfg, &cfg.workspace.canonical_workspace_id, "ws-html");
        write_workspace_session(dir.path(), &session).unwrap();

        let (base_url, handle) = spawn_gateway_server(sample_result(), sample_manifest()).await;
        let _env_lock = ENV_LOCK.lock().unwrap_or_else(|error| error.into_inner());
        std::env::set_var("BEAGLE_DARWIN_HPC_GATEWAY_BASE_URL", &base_url);
        std::env::set_var("BEAGLE_DARWIN_HPC_GATEWAY_TIMEOUT_SECONDS", "5");

        let gateway = DarwinHpcGatewayClient::from_env().unwrap();
        let cockpit = get_workstream_cockpit(dir.path(), &cfg, &gateway, CANONICAL_WORKSTREAM_ID)
            .await
            .unwrap();
        let html = render_workstream_cockpit_page(&cockpit);

        std::env::remove_var("BEAGLE_DARWIN_HPC_GATEWAY_BASE_URL");
        std::env::remove_var("BEAGLE_DARWIN_HPC_GATEWAY_TIMEOUT_SECONDS");
        handle.await.unwrap();

        assert!(html.contains("Beagle Premium Tool Dock MVP"));
        assert!(html.contains("agourakis82/beagle"));
        assert!(html.contains("feat/darwin-hpc-governance"));
        assert!(html.contains("ws-html"));
        assert!(html.contains("Open in Cursor"));
        assert!(html.contains("Open Claude Code"));
        assert!(html.contains("Open Codex"));
        assert!(html.contains("/api/darwin/workstreams/beagle-darwin-hpc-governance/tool-return"));
        assert!(html.contains("/api/darwin/workstreams/beagle-darwin-hpc-governance/workspace-launch-resume"));
        assert!(html.contains("/api/darwin/programs/beagle-physio-symbolic-exocortex/context-packet"));
        assert!(html.contains("/api/darwin/campaigns/expedition-002-hrv-aware/context-packet"));
        assert!(html.contains("Control Room Actions"));
        assert!(html.contains("/api/darwin/workstreams/beagle-darwin-hpc-governance/hold"));
        assert!(html.contains("/api/darwin/workstreams/beagle-darwin-hpc-governance/resume"));
        assert!(html.contains("resume from premium tool dock"));
    }
}
