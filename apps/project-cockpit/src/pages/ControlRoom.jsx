/**
 * ControlRoom — /projects/:slug
 *
 * Private control room per project.
 * 5 operational lanes with truth indicators.
 * GPU canvas shows project pod topology behind glass lanes.
 */
import { useParams, useNavigate } from "@solidjs/router";
import { createResource, Show, For, createSignal } from "solid-js";
import { useTitle } from "../hooks/useTitle";
import { fetchWithTruth, extractTruthMode, formatTruthAge } from "../stores/truth";
import GlassPanel from "../components/GlassPanel";
import TruthBadge from "../components/TruthBadge";
import PostureIndicator from "../components/PostureIndicator";
import Lane from "../components/Lane";
import Sparkline from "../components/Sparkline";
import Terminal from "../components/Terminal";
import Skeleton from "../components/Skeleton";

async function fetchLane(slug, path) {
  return fetchWithTruth(`/api/projects/${slug}/${path}`, 8000);
}

async function fetchJson(path, timeoutMs = 8000) {
  const res = await fetch(path, { signal: AbortSignal.timeout(timeoutMs) });
  if (!res.ok) throw new Error(`${res.status}`);
  return res.json();
}

async function postJson(path, body = {}, timeoutMs = 300000) {
  const requestId =
    body.idempotencyKey ||
    (crypto?.randomUUID ? crypto.randomUUID() : `${Date.now()}-${Math.random()}`);
  const res = await fetch(path, {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      "X-Request-ID": requestId,
    },
    body: JSON.stringify({ confirmed: true, ...body, idempotencyKey: requestId }),
    signal: AbortSignal.timeout(timeoutMs),
  });
  const payload = await res.json().catch(() => ({}));
  if (!res.ok) throw new Error(payload?.error?.message || payload?.error || `${res.status}`);
  return payload;
}

function short(value, fallback = "—") {
  if (value === undefined || value === null || value === "") return fallback;
  return String(value);
}

function statusColor(status) {
  const normalized = String(status || "").toLowerCase();
  if (normalized.includes("fail") || normalized.includes("error")) return "var(--state-error)";
  if (normalized.includes("run") || normalized.includes("live") || normalized.includes("ready") || normalized.includes("succeeded")) return "var(--truth-observed)";
  if (normalized.includes("pending") || normalized.includes("start")) return "var(--posture-warm)";
  return "var(--text-tertiary)";
}

function ActionButton(props) {
  return (
    <button
      disabled={props.disabled}
      onClick={props.onClick}
      title={props.title}
      style={{
        padding: "var(--space-2) var(--space-3)",
        background: props.danger ? "rgba(239, 68, 68, 0.10)" : "rgba(81, 214, 189, 0.10)",
        border: props.danger ? "1px solid rgba(239, 68, 68, 0.26)" : "1px solid rgba(81, 214, 189, 0.24)",
        "border-radius": "var(--radius-sm)",
        color: props.danger ? "var(--state-error)" : "var(--truth-observed)",
        "font-family": "var(--font-data)",
        "font-size": "var(--text-xs)",
        opacity: props.disabled ? 0.45 : 1,
        cursor: props.disabled ? "not-allowed" : "pointer",
      }}
    >
      {props.children}
    </button>
  );
}

export default function ControlRoom() {
  const params = useParams();
  const navigate = useNavigate();
  useTitle(() => `${params.slug} · Control Room`);

  // Fetch all lanes in parallel
  const [missionTruth] = createResource(() => params.slug, (s) => fetchLane(s, "mission-control"));
  const [clusterTruth] = createResource(() => params.slug, (s) => fetchLane(s, "cluster/lane-truth"));
  const [researchTruth] = createResource(() => params.slug, (s) => fetchLane(s, "research/operations"));
  const [inferenceTruth] = createResource(() => params.slug, (s) => fetchLane(s, "inference/runtime"));
  const [goWorkTruth, { refetch: refetchGoWork }] = createResource(() => params.slug, (s) => fetchLane(s, "go-work-now"));
  const [controlTruth, { refetch: refetchControl }] = createResource(() => params.slug, (s) => fetchLane(s, "control-plane"));
  const [auditTruth] = createResource(() => params.slug, () => fetchWithTruth("/api/catalog/audit", 5000));
  const [gitTruth, { refetch: refetchGit }] = createResource(() => params.slug, (s) => fetchLane(s, "git/status"));
  const [agentSessions, { refetch: refetchAgents }] = createResource(() => params.slug, (s) => fetchJson(`/api/projects/${s}/agent/sessions`).catch((error) => ({ error: error.message, sessions: [] })));
  const [jobsTruth, { refetch: refetchJobs }] = createResource(() => params.slug, (s) => fetchJson(`/api/projects/${s}/jobs`).catch((error) => ({ error: error.message, jobs: [] })));

  const [mutation, setMutation] = createSignal(null);
  const [jobPreset, setJobPreset] = createSignal(params.slug === "sounio" ? "sounio-compile-example" : "");
  const [agentKind, setAgentKind] = createSignal("codex");

  const project = () => missionTruth()?.data?.project || {};
  const posture = () => project().mode || "warm";
  const missionMode = () => missionTruth()?.truthMode || "declared";

  // Extract deep data
  const missionData = () => missionTruth()?.data || {};
  const clusterData = () => clusterTruth()?.data || {};
  const researchData = () => researchTruth()?.data || {};
  const inferenceRuntime = () => inferenceTruth()?.data?.runtime || inferenceTruth()?.data || {};
  const modelRegistry = () => inferenceRuntime().modelRegistry || {};
  const modelLanes = () => modelRegistry().lanes || [];
  const goWorkData = () => goWorkTruth()?.data || {};
  const auditFindings = () => (auditTruth()?.data?.findings || []).filter((finding) => finding.projectSlug === params.slug);
  const gitData = () => gitTruth()?.data || {};
  const sessions = () => agentSessions()?.sessions || agentSessions()?.agentSessions || [];
  const jobs = () => jobsTruth()?.jobs || [];
  const controlPlane = () => controlTruth()?.data?.controlPlane || {};
  const controlState = () => controlPlane().state || {};
  const controlActions = () => controlPlane().actions || [];
  const controlAction = (id) => controlActions().find((action) => action.id === id) || {};

  // Truth summary from mission control
  const truthSummary = () => missionData().truthSummary || {};

  async function runMutation(label, fn, refresh = []) {
    setMutation({ label, state: "running", output: "" });
    try {
      const result = await fn();
      setMutation({
        label,
        state: "done",
        output: result?.output || result?.status || result?.job_id || result?.action || "done",
      });
      refresh.forEach((item) => item && item());
    } catch (error) {
      setMutation({ label, state: "error", output: error.message });
    }
  }

  async function runControlAction(id, refresh = []) {
    const action = controlAction(id);
    if (!action.id || action.enabled === false) {
      setMutation({
        label: action.label || id,
        state: "error",
        output: action.reason || "action is not enabled",
      });
      return;
    }
    if (action.kind === "route") {
      navigate(action.route);
      return;
    }
    await runMutation(
      action.label || id,
      () => postJson(action.route, action.body || {}),
      [refetchControl, ...refresh]
    );
  }

  const goWorkPacket = () => goWorkData().goWorkNow || goWorkData();
  const workspaceState = () => goWorkPacket().workspaceState || {};
  const actionCommand = (name) => goWorkPacket().commands?.[name] || "";

  return (
    <div style={{
      position: "relative",
      "z-index": 1,
      padding: "var(--space-6) var(--space-8)",
      "max-width": "960px",
      margin: "0 auto",
      height: "100%",
      "overflow-y": "auto",
    }}>
      {/* Project header */}
      <div style={{
        display: "flex",
        "align-items": "center",
        "justify-content": "space-between",
        "margin-bottom": "var(--space-6)",
      }}>
        <div style={{ display: "flex", "align-items": "center", gap: "var(--space-3)" }}>
          <button
            onClick={() => navigate("/projects")}
            style={{
              color: "var(--text-tertiary)",
              "font-size": "var(--text-sm)",
              opacity: 0.6,
            }}
            title="Back to command bridge"
          >
            ←
          </button>
          <h1 style={{
            "font-family": "var(--font-display)",
            "font-size": "var(--text-2xl)",
            "font-weight": "var(--weight-semibold)",
            color: "var(--text-primary)",
            "text-transform": "uppercase",
            "letter-spacing": "0.03em",
          }}>
            {params.slug}
          </h1>
          <PostureIndicator mode={posture()} size="lg" />
        </div>
        <div style={{ display: "flex", "align-items": "center", gap: "var(--space-3)" }}>
          <TruthBadge mode={missionMode()} />
          <Show when={missionTruth()?.observedAt}>
            <span style={{ "font-family": "var(--font-data)", "font-size": "var(--text-xs)", color: "var(--text-tertiary)" }}>
              {formatTruthAge(missionTruth().observedAt)}
            </span>
          </Show>
        </div>
      </div>

      {/* Project control packet */}
      <GlassPanel elevated truth={controlTruth()?.truthMode || "declared"} style={{ "margin-bottom": "var(--space-5)" }}>
        <Show when={controlPlane().projectSlug} fallback={<Skeleton lines={4} />}>
          <div style={{
            display: "grid",
            "grid-template-columns": "repeat(auto-fit, minmax(260px, 1fr))",
            gap: "var(--space-5)",
            "align-items": "start",
          }}>
            <div>
              <div style={{ display: "flex", "align-items": "center", "justify-content": "space-between", gap: "var(--space-3)", "margin-bottom": "var(--space-3)" }}>
                <div>
                  <div style={{
                    "font-family": "var(--font-ui)",
                    "font-size": "var(--text-xs)",
                    "font-weight": "var(--weight-semibold)",
                    "text-transform": "uppercase",
                    "letter-spacing": "0.08em",
                    color: "var(--text-tertiary)",
                    "margin-bottom": "var(--space-1)",
                  }}>
                    Control Plane
                  </div>
                  <div style={{
                    "font-family": "var(--font-display)",
                    "font-size": "var(--text-xl)",
                    "font-weight": "var(--weight-semibold)",
                    color: "var(--text-primary)",
                  }}>
                    {controlPlane().nextSafeMove || "loading project control packet"}
                  </div>
                </div>
                <TruthBadge mode={controlTruth()?.truthMode || "declared"} />
              </div>

              <div style={{
                display: "grid",
                "grid-template-columns": "repeat(auto-fit, minmax(150px, 1fr))",
                gap: "var(--space-2) var(--space-4)",
                "font-family": "var(--font-data)",
                "font-size": "var(--text-mono)",
                color: "var(--text-data)",
              }}>
                <span>workspace: <span style={{ color: statusColor(controlState().workspaceStatus) }}>{short(controlState().workspaceStatus)}</span></span>
                <span>entry: {short(controlState().entrypoint)}</span>
                <span>catalog: <span style={{ color: statusColor(controlState().catalogStatus) }}>{short(controlState().catalogStatus)}</span></span>
                <span>git: <span style={{ color: controlState().branchDrift ? "var(--posture-warm)" : "var(--text-data)" }}>{short(controlState().observedBranch || controlState().preferredBranch)}</span></span>
                <span>dirty: {short(controlState().publishableDirtyCount ?? controlState().dirtyCount, "unknown")}</span>
                <span>namespace: {short(controlState().namespace)}</span>
              </div>

              <Show when={(controlPlane().blockers || []).length || (controlPlane().notices || []).length}>
                <div style={{ display: "flex", "flex-direction": "column", gap: "var(--space-1)", "margin-top": "var(--space-3)", "font-family": "var(--font-data)", "font-size": "var(--text-xs)" }}>
                  <For each={[...(controlPlane().blockers || []), ...(controlPlane().notices || [])].slice(0, 4)}>
                    {(finding) => (
                      <div style={{ color: finding.severity === "fail" ? "var(--state-error)" : finding.severity === "warn" ? "var(--posture-warm)" : "var(--text-tertiary)" }}>
                        {finding.severity} · {finding.code}: {finding.summary}
                      </div>
                    )}
                  </For>
                </div>
              </Show>
            </div>

            <div style={{ display: "flex", "flex-direction": "column", gap: "var(--space-2)" }}>
              <div style={{ display: "grid", "grid-template-columns": "1fr 1fr", gap: "var(--space-2)" }}>
                <ActionButton
                  disabled={controlAction("activate-habitat").enabled === false}
                  title={controlAction("activate-habitat").reason}
                  onClick={() => runControlAction("activate-habitat", [refetchGoWork])}
                >
                  {controlAction("activate-habitat").label || "activate workspace"}
                </ActionButton>
                <ActionButton
                  danger
                  disabled={controlAction("standby-habitat").enabled === false}
                  title={controlAction("standby-habitat").reason}
                  onClick={() => runControlAction("standby-habitat", [refetchGoWork])}
                >
                  standby
                </ActionButton>
                <ActionButton
                  disabled={controlAction("start-agent").enabled === false}
                  title={controlAction("start-agent").reason}
                  onClick={() => runControlAction("start-agent", [refetchAgents])}
                >
                  start codex
                </ActionButton>
                <ActionButton
                  onClick={() => {
                    refetchControl();
                    refetchGoWork();
                    refetchGit();
                    refetchAgents();
                    refetchJobs();
                  }}
                >
                  refresh
                </ActionButton>
              </div>
              <div style={{ "font-family": "var(--font-data)", "font-size": "var(--text-xs)", color: "var(--text-tertiary)", "line-height": 1.5 }}>
                Agents should enter through <span style={{ color: "var(--text-data)" }}>{short(controlState().entrypoint)}</span> and use cockpit routes for jobs, sessions, and workspace changes.
              </div>
            </div>
          </div>
        </Show>
      </GlassPanel>

      {/* ─── Lane 1: Mission Control ─── */}
      <Lane title="Mission Control" truth={missionMode()}>
        <Show when={project().projectSlug} fallback={
          <Skeleton lines={3} />
        }>
          <div style={{ display: "grid", "grid-template-columns": "1fr 1fr", gap: "var(--space-2) var(--space-6)", "font-family": "var(--font-data)", "font-size": "var(--text-mono)", color: "var(--text-data)" }}>
            <span>workspace: <span style={{ color: statusColor(workspaceState().status || project().workspacePod) }}>{workspaceState().status || (project().workspacePod ? "live" : "standby")}</span></span>
            <span>branch: {project().preferredPrBase || project().branch || "—"}</span>
            <span>namespace: {project().namespace || "—"}</span>
            <span>pod: {project().workspacePod || "—"}</span>
            <Show when={project().tmuxSession}>
              <span>zellij: {project().zellijSession || project().tmuxSession}</span>
            </Show>
            <Show when={project().foundryLastSmokeRunId}>
              <span>foundry: {project().foundryLastSmokeRunId}</span>
            </Show>
            <Show when={project().workspaceRole}>
              <span>role: {project().workspaceRole}</span>
            </Show>
            <Show when={project().playgroundClass}>
              <span>playground: {project().playgroundClass}</span>
            </Show>
          </div>

          <Show when={project().zellijTabs?.length}>
            <div style={{ "margin-top": "var(--space-2)", "font-family": "var(--font-data)", "font-size": "var(--text-xs)", color: "var(--text-secondary)", "line-height": 1.5 }}>
              tabs: {project().zellijTabs.join(" · ")}
            </div>
          </Show>

          {/* Execution packets summary */}
          <Show when={missionData().routing?.packets || missionData().packets}>
            <div style={{ "margin-top": "var(--space-3)", "font-size": "var(--text-xs)", color: "var(--text-secondary)" }}>
              execution packets: {missionData().packetCount || Object.keys(missionData().routing?.packets || missionData().packets || {}).length}
            </div>
          </Show>

          {/* Truth summary chips */}
          <Show when={Object.keys(truthSummary()).length > 0}>
            <div style={{ display: "flex", gap: "var(--space-2)", "margin-top": "var(--space-3)", "flex-wrap": "wrap" }}>
              <For each={Object.entries(truthSummary())}>
                {([key, val]) => (
                  <Show when={val && typeof val === "object" && val.truthMode}>
                    <span style={{
                      "font-family": "var(--font-data)",
                      "font-size": "var(--text-xs)",
                      color: "var(--text-tertiary)",
                      padding: "1px var(--space-2)",
                      background: "rgba(255,255,255,0.03)",
                      "border-radius": "3px",
                    }}>
                      {key}: <TruthBadge mode={val.truthMode} />
                    </span>
                  </Show>
                )}
              </For>
            </div>
          </Show>
        </Show>
      </Lane>

      {/* ─── Lane 2: Cluster Truth ─── */}
      <Lane title="Cluster Truth" truth={clusterTruth()?.truthMode || "remembered"}>
        <Show when={clusterData().project} fallback={
          <Skeleton lines={2} />
        }>
          <div style={{ "font-family": "var(--font-data)", "font-size": "var(--text-mono)", color: "var(--text-data)", display: "flex", "flex-direction": "column", gap: "var(--space-2)" }}>
            <div style={{ display: "flex", gap: "var(--space-4)" }}>
              <span><span style={{ color: "var(--truth-observed)" }}>●</span> r770 healthy</span>
              <span><span style={{ color: "var(--truth-observed)" }}>●</span> r740 healthy</span>
              <span><span style={{ color: "var(--truth-declared)" }}>○</span> t560 ctrl</span>
            </div>
          </div>
        </Show>
      </Lane>

      {/* ─── Lane 3: Research Operations ─── */}
      <Lane title="Research Operations" truth={researchTruth()?.truthMode || "declared"}>
        <Show when={researchData().project} fallback={
          <Skeleton lines={2} />
        }>
          <div style={{ "font-family": "var(--font-data)", "font-size": "var(--text-mono)", color: "var(--text-data)" }}>
            <p style={{ color: "var(--text-secondary)", "font-size": "var(--text-sm)" }}>
              ABIDE campaigns and job tracking
            </p>
          </div>
        </Show>
      </Lane>

      {/* ─── Lane 4: Inference Fabric ─── */}
      <Lane title="Inference Fabric" truth={inferenceTruth()?.truthMode || "declared"} defaultExpanded={true}>
        <Show when={inferenceRuntime().status} fallback={
          <Skeleton lines={2} />
        }>
          <div style={{ "font-family": "var(--font-data)", "font-size": "var(--text-mono)", color: "var(--text-data)", display: "flex", "flex-direction": "column", gap: "var(--space-2)" }}>
            <div style={{ display: "flex", gap: "var(--space-4)" }}>
              <span>
                <span style={{ color: inferenceRuntime().controlPlane?.status === "ready" ? "var(--truth-observed)" : "var(--truth-stale)" }}>●</span>
                {" "}Dynamo: {inferenceRuntime().controlPlane?.status || "—"}
              </span>
              <span>
                <span style={{ color: inferenceRuntime().engine?.status?.includes("published") ? "var(--truth-observed)" : "var(--truth-stale)" }}>●</span>
                {" "}SGLang: {inferenceRuntime().engine?.status || "—"}
              </span>
            </div>
            <Show when={inferenceRuntime().models?.length}>
              <div style={{ "margin-top": "var(--space-1)" }}>
                <For each={inferenceRuntime().models}>
                  {(m) => (
                    <span style={{ color: "var(--text-secondary)" }}>
                      model: {m.id || m.name || "unknown"} ({m.provider || "—"})
                    </span>
                  )}
                </For>
              </div>
            </Show>
            <Show when={inferenceRuntime().reachable !== undefined}>
              <span style={{ color: "var(--text-tertiary)", "font-size": "var(--text-xs)" }}>
                reachable: {inferenceRuntime().reachable ? "yes" : "no"} · configured: {inferenceRuntime().configured ? "yes" : "no"}
              </span>
            </Show>
            <Show when={modelRegistry().policy}>
              <div style={{
                "margin-top": "var(--space-2)",
                padding: "var(--space-2)",
                border: "1px solid rgba(255,255,255,0.10)",
                "border-radius": "var(--radius-sm)",
                background: "rgba(255,255,255,0.035)",
                color: "var(--text-secondary)",
                "font-size": "var(--text-xs)",
                display: "flex",
                "flex-direction": "column",
                gap: "var(--space-1)"
              }}>
                <span>model registry: {modelRegistry().truthMode || "declared"} · policy: {modelRegistry().policy?.wrapper || "—"}</span>
                <span>operator: {modelRegistry().policy?.operatorModel || "none approved"}</span>
              </div>
            </Show>
            <Show when={modelLanes().length}>
              <div style={{
                display: "grid",
                "grid-template-columns": "repeat(auto-fit, minmax(220px, 1fr))",
                gap: "var(--space-2)",
                "margin-top": "var(--space-2)"
              }}>
                <For each={modelLanes()}>
                  {(lane) => (
                    <div style={{
                      border: "1px solid rgba(255,255,255,0.10)",
                      "border-radius": "var(--radius-sm)",
                      padding: "var(--space-2)",
                      background: "rgba(0,0,0,0.16)",
                      display: "flex",
                      "flex-direction": "column",
                      gap: "var(--space-1)",
                      "min-width": 0
                    }}>
                      <div style={{ display: "flex", "justify-content": "space-between", gap: "var(--space-2)", "align-items": "center" }}>
                        <strong style={{ color: "var(--text-primary)", "font-size": "var(--text-sm)", overflow: "hidden", "text-overflow": "ellipsis", "white-space": "nowrap" }}>
                          {lane.title || lane.id}
                        </strong>
                        <span style={{ color: statusColor(lane.runtime?.status || lane.verdict), "font-size": "var(--text-xs)", "white-space": "nowrap" }}>
                          ● {lane.runtime?.status || "standby"}
                        </span>
                      </div>
                      <span style={{ color: "var(--text-secondary)", overflow: "hidden", "text-overflow": "ellipsis", "white-space": "nowrap" }}>
                        {lane.selectedModel || lane.servedModel || "unassigned"}
                      </span>
                      <span style={{ color: "var(--text-tertiary)", "font-size": "var(--text-xs)", overflow: "hidden", "text-overflow": "ellipsis", "white-space": "nowrap" }}>
                        gpu: {lane.gpu?.node || "—"} · {lane.gpu?.accelerator || "—"}
                      </span>
                      <span style={{ color: "var(--text-tertiary)", "font-size": "var(--text-xs)" }}>
                        vram: {lane.gpu?.vramMiB?.highWater || lane.gpu?.vramMiB?.startup || lane.gpu?.vramMiB?.jambaStartup || "—"} MiB · probe: {lane.lastProbe?.runId || "not-run"}
                      </span>
                      <span style={{ color: lane.id === "operator" ? "var(--state-error)" : "var(--text-data)", "font-size": "var(--text-xs)", overflow: "hidden", "text-overflow": "ellipsis", "white-space": "nowrap" }}>
                        verdict: {lane.verdict || "declared"}
                      </span>
                    </div>
                  )}
                </For>
              </div>
            </Show>
          </div>
        </Show>
      </Lane>

      {/* ─── Lane 5: Go Work Now (Actions) ─── */}
      <Lane title="Operator Actions" truth={goWorkTruth()?.truthMode || "declared"} defaultExpanded={true}>
        <Show when={goWorkData().project} fallback={
          <Skeleton lines={1} />
        }>
          <div style={{ "font-family": "var(--font-data)", "font-size": "var(--text-mono)", color: "var(--text-data)", display: "flex", "flex-direction": "column", gap: "var(--space-3)" }}>
            <div style={{ display: "grid", "grid-template-columns": "1fr 1fr", gap: "var(--space-2) var(--space-4)" }}>
              <span>workspace: <span style={{ color: statusColor(workspaceState().status) }}>{short(workspaceState().status || workspaceState().phase, "declared")}</span></span>
              <span>entry: {short(goWorkPacket().primaryEntry || goWorkPacket().entrypoint || (params.slug === "sounio" ? "sounio dev" : `dev ${params.slug}`))}</span>
              <span>activate: {short(actionCommand("activateHabitat") || actionCommand("activate"))}</span>
              <span>standby: {short(actionCommand("standbyHabitat") || actionCommand("standby"))}</span>
            </div>
            <div style={{ display: "flex", gap: "var(--space-2)", "flex-wrap": "wrap" }}>
              <ActionButton
                onClick={() => runMutation(
                  "activate workspace",
                  () => postJson(`/api/projects/${params.slug}/go-work-now/actions/activate-habitat`),
                  [refetchGoWork]
                )}
              >
                activate workspace
              </ActionButton>
              <ActionButton
                danger
                disabled={posture() === "always-on"}
                title={posture() === "always-on" ? "always-on projects cannot be put on standby from this lane" : ""}
                onClick={() => runMutation(
                  "standby workspace",
                  () => postJson(`/api/projects/${params.slug}/go-work-now/actions/standby-habitat`),
                  [refetchGoWork]
                )}
              >
                standby workspace
              </ActionButton>
              <ActionButton onClick={() => refetchGoWork()}>refresh truth</ActionButton>
            </div>
          </div>
        </Show>
      </Lane>

      {/* ─── Lane 6: Catalog Contract ─── */}
      <Lane title="Catalog Contract" truth={auditTruth()?.truthMode || "declared"} defaultExpanded={auditFindings().length > 0}>
        <div style={{ "font-family": "var(--font-data)", "font-size": "var(--text-mono)", color: "var(--text-data)", display: "flex", "flex-direction": "column", gap: "var(--space-2)" }}>
          <Show when={auditFindings().length} fallback={<span style={{ color: "var(--truth-observed)" }}>catalog contract clean for this project</span>}>
            <For each={auditFindings()}>
              {(finding) => (
                <div style={{ color: finding.severity === "fail" ? "var(--state-error)" : finding.severity === "warn" ? "var(--posture-warm)" : "var(--text-tertiary)" }}>
                  {finding.severity} · {finding.code}: {finding.summary}
                </div>
              )}
            </For>
          </Show>
        </div>
      </Lane>

      {/* ─── Lane 7: Agents ─── */}
      <Lane title="Agents" truth={agentSessions()?.error ? "stale" : "observed"} defaultExpanded={true}>
        <div style={{ display: "flex", "flex-direction": "column", gap: "var(--space-3)", "font-family": "var(--font-data)", "font-size": "var(--text-mono)", color: "var(--text-data)" }}>
          <div style={{ display: "flex", gap: "var(--space-2)", "align-items": "center", "flex-wrap": "wrap" }}>
            <select
              value={agentKind()}
              onInput={(event) => setAgentKind(event.currentTarget.value)}
              style={{ background: "var(--surface-2)", color: "var(--text-primary)", border: "1px solid var(--glass-border)", "border-radius": "var(--radius-sm)", padding: "var(--space-2)" }}
            >
              <option value="codex">codex</option>
              <option value="claude-code">claude-code</option>
              <option value="custom">custom</option>
            </select>
            <ActionButton onClick={() => runMutation(
              `start ${agentKind()}`,
              () => postJson(`/api/projects/${params.slug}/agent/session/start`, { kind: agentKind() }),
              [refetchAgents]
            )}>
              start agent
            </ActionButton>
            <ActionButton onClick={() => refetchAgents()}>refresh agents</ActionButton>
          </div>
          <Show when={sessions().length} fallback={<span style={{ color: "var(--text-tertiary)" }}>no observed agent sessions</span>}>
            <For each={sessions()}>
              {(session) => {
                const kind = session.kind || session.agentKind || session.name || "agent";
                return (
                  <div style={{ display: "flex", "justify-content": "space-between", gap: "var(--space-3)", "align-items": "center", padding: "var(--space-2)", background: "rgba(255,255,255,0.03)", "border-radius": "var(--radius-sm)" }}>
                    <span><span style={{ color: statusColor(session.phase || session.status) }}>●</span> {kind} · {short(session.phase || session.status)}</span>
                    <div style={{ display: "flex", gap: "var(--space-2)" }}>
                      <ActionButton onClick={() => runMutation(
                        `resume ${kind}`,
                        () => postJson(`/api/projects/${params.slug}/agent/session/${kind}/resume`),
                        [refetchAgents]
                      )}>resume</ActionButton>
                      <ActionButton danger onClick={() => runMutation(
                        `pause ${kind}`,
                        () => postJson(`/api/projects/${params.slug}/agent/session/${kind}/pause`),
                        [refetchAgents]
                      )}>pause</ActionButton>
                    </div>
                  </div>
                );
              }}
            </For>
          </Show>
        </div>
      </Lane>

      {/* ─── Lane 8: Git / Branch Lease ─── */}
      <Lane title="Git & Branch Lease" truth={gitTruth()?.truthMode || "declared"} defaultExpanded={true}>
        <div style={{ display: "grid", "grid-template-columns": "1fr 1fr", gap: "var(--space-2) var(--space-6)", "font-family": "var(--font-data)", "font-size": "var(--text-mono)", color: "var(--text-data)" }}>
          <span>branch: {short(gitData().git?.branch || gitData().branch || gitData().currentBranch || gitData().status?.branch)}</span>
          <span>dirty: {short(gitData().git?.dirty || gitData().dirty || gitData().isDirty || gitData().status?.dirty, "unknown")}</span>
          <span>preferred base: {short(project().preferredPrBase || project().branch)}</span>
          <span>contract: branch lease required for writers</span>
          <div style={{ "grid-column": "1 / -1", display: "flex", gap: "var(--space-2)", "margin-top": "var(--space-2)" }}>
            <ActionButton onClick={() => refetchGit()}>refresh git</ActionButton>
            <ActionButton onClick={() => runMutation(
              "create topic branch",
              () => postJson(`/api/projects/${params.slug}/git/topic-branch`, {
                branch: `agent/${params.slug}-${new Date().toISOString().slice(0, 10)}`,
              }, 20000),
              [refetchGit]
            )}>
              create branch lease
            </ActionButton>
          </div>
        </div>
      </Lane>

      {/* ─── Lane 9: Supercomputing Contract ─── */}
      <Lane title="Supercomputing Contract" truth={jobsTruth()?.error ? "stale" : "observed"} defaultExpanded={true}>
        <div style={{ display: "flex", "flex-direction": "column", gap: "var(--space-3)", "font-family": "var(--font-data)", "font-size": "var(--text-mono)", color: "var(--text-data)" }}>
          <div style={{ display: "flex", gap: "var(--space-2)", "align-items": "center", "flex-wrap": "wrap" }}>
            <input
              value={jobPreset()}
              onInput={(event) => setJobPreset(event.currentTarget.value)}
              placeholder="preset or empty custom"
              style={{ flex: "1 1 220px", background: "var(--surface-2)", color: "var(--text-primary)", border: "1px solid var(--glass-border)", "border-radius": "var(--radius-sm)", padding: "var(--space-2)" }}
            />
            <ActionButton onClick={() => runMutation(
              "submit compute packet",
              () => postJson(`/api/projects/${params.slug}/jobs/submit`, jobPreset() ? { preset: jobPreset() } : { command: ["bash", "-lc", "echo project-cockpit-contract-smoke"], resources: { cpu: "1", memory: "1Gi", gpu: 0 }, data_mounts: ["work-tmp"], timeout_seconds: 120 }),
              [refetchJobs]
            )}>
              submit job
            </ActionButton>
            <ActionButton onClick={() => refetchJobs()}>refresh jobs</ActionButton>
          </div>
          <Show when={jobs().length} fallback={<span style={{ color: "var(--text-tertiary)" }}>no cockpit-submitted jobs observed</span>}>
            <For each={jobs().slice(0, 5)}>
              {(job) => (
                <div style={{ display: "flex", "justify-content": "space-between", gap: "var(--space-3)", "align-items": "center", padding: "var(--space-2)", background: "rgba(255,255,255,0.03)", "border-radius": "var(--radius-sm)" }}>
                  <span>{short(job.job_id || job.job_name)} · {short(job.campaign, "campaign-free")} · active {job.active || 0} ok {job.succeeded || 0} fail {job.failed || 0}</span>
                  <Show when={job.job_id}>
                    <ActionButton danger onClick={() => runMutation(
                      `cancel ${job.job_id}`,
                      () => postJson(`/api/projects/${params.slug}/jobs/${job.job_id}/cancel`),
                      [refetchJobs]
                    )}>cancel</ActionButton>
                  </Show>
                </div>
              )}
            </For>
          </Show>
        </div>
      </Lane>

      <Show when={mutation()}>
        <GlassPanel subtle truth={mutation().state === "error" ? "stale" : mutation().state === "done" ? "observed" : "remembered"} style={{ "margin-bottom": "var(--space-4)" }}>
          <div style={{ "font-family": "var(--font-data)", "font-size": "var(--text-mono)", color: mutation().state === "error" ? "var(--state-error)" : "var(--text-data)" }}>
            {mutation().label}: {mutation().state} · {mutation().output}
          </div>
        </GlassPanel>
      </Show>

      {/* ─── Lane 10: Terminal ─── */}
      <Lane title={`Terminal · tmux: ${project().tmuxSession || params.slug}`} truth="observed" defaultExpanded={true}>
        <Terminal slug={params.slug} expanded={true} />
      </Lane>
    </div>
  );
}
