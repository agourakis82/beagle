/**
 * ProjectOS - /projects/os
 *
 * Multi-project operating surface: posture, workspace state, risks, agents,
 * jobs, and propose-only autopilot in one scan.
 */
import { For, Show, createMemo, createResource } from "solid-js";
import { useNavigate } from "@solidjs/router";
import { useTitle } from "../hooks/useTitle";
import { fetchWithTruth } from "../stores/truth";
import GlassPanel from "../components/GlassPanel";
import TruthBadge from "../components/TruthBadge";
import PostureIndicator from "../components/PostureIndicator";
import Skeleton from "../components/Skeleton";

async function fetchProjectOs() {
  return fetchWithTruth("/api/project-os", 12000);
}

function statusColor(value) {
  const normalized = String(value || "").toLowerCase();
  if (normalized.includes("fail") || normalized.includes("error") || normalized.includes("stale")) return "var(--state-error)";
  if (normalized.includes("warn") || normalized.includes("drift") || normalized.includes("pending")) return "var(--posture-warm)";
  if (normalized.includes("live") || normalized.includes("ready") || normalized.includes("ok") || normalized.includes("observed")) return "var(--truth-observed)";
  return "var(--text-tertiary)";
}

function valueOf(value, fallback = "-") {
  if (value === undefined || value === null || value === "") return fallback;
  return String(value);
}

function Metric(props) {
  return (
    <div style={{ display: "flex", "flex-direction": "column", gap: "var(--space-1)" }}>
      <span style={{
        "font-family": "var(--font-ui)",
        "font-size": "var(--text-xs)",
        "font-weight": "var(--weight-semibold)",
        "text-transform": "uppercase",
        "letter-spacing": "0.08em",
        color: "var(--text-tertiary)",
      }}>
        {props.label}
      </span>
      <span style={{
        "font-family": "var(--font-data)",
        "font-size": "var(--text-lg)",
        color: props.color || "var(--text-primary)",
      }}>
        {props.value}
      </span>
    </div>
  );
}

function ProjectRow(props) {
  const navigate = useNavigate();
  const project = () => props.project || {};
  const workspace = () => project().workspace || {};
  const git = () => project().git || {};
  const agentText = () => `${project().agents?.running || 0}/${project().agents?.count || 0}`;
  const jobText = () => `${project().jobs?.active || 0}/${project().jobs?.count || 0}`;
  const ledgerCount = () => project().actionLedger?.count || 0;

  return (
    <GlassPanel truth={project().truthMode || "declared"} style={{ padding: "var(--space-4)" }}>
      <div style={{
        display: "grid",
        "grid-template-columns": "repeat(auto-fit, minmax(220px, 1fr))",
        gap: "var(--space-4)",
        "align-items": "start",
      }}>
        <div>
          <div style={{ display: "flex", "align-items": "center", gap: "var(--space-2)", "margin-bottom": "var(--space-2)", "flex-wrap": "wrap" }}>
            <PostureIndicator mode={project().posture || "warm"} size="sm" showLabel={false} />
            <button
              onClick={() => navigate(project().routes?.control || `/projects/${project().projectSlug}/control`)}
              style={{
                color: "var(--text-primary)",
                "font-family": "var(--font-display)",
                "font-size": "var(--text-base)",
                "font-weight": "var(--weight-semibold)",
                "text-align": "left",
                "text-transform": "uppercase",
                "letter-spacing": "0",
              }}
            >
              {project().projectSlug}
            </button>
          </div>
          <div style={{ "font-family": "var(--font-data)", "font-size": "var(--text-xs)", color: "var(--text-tertiary)", "line-height": 1.5 }}>
            {valueOf(project().entrypoint)}
          </div>
        </div>

        <div style={{ display: "grid", "grid-template-columns": "repeat(auto-fit, minmax(110px, 1fr))", gap: "var(--space-3)" }}>
          <span style={{ "font-family": "var(--font-data)", "font-size": "var(--text-xs)", color: "var(--text-data)" }}>
            workspace <span style={{ color: statusColor(workspace().status) }}>{valueOf(workspace().status)}</span>
          </span>
          <span style={{ "font-family": "var(--font-data)", "font-size": "var(--text-xs)", color: "var(--text-data)" }}>
            branch <span style={{ color: git().branchDrift ? "var(--posture-warm)" : "var(--text-secondary)" }}>{valueOf(git().observedBranch || git().preferredBranch)}</span>
          </span>
          <span style={{ "font-family": "var(--font-data)", "font-size": "var(--text-xs)", color: "var(--text-data)" }}>
            dirty {valueOf(git().publishableDirtyCount ?? git().dirtyCount, "unknown")}
          </span>
          <span style={{ "font-family": "var(--font-data)", "font-size": "var(--text-xs)", color: "var(--text-data)" }}>
            agents {agentText()}
          </span>
          <span style={{ "font-family": "var(--font-data)", "font-size": "var(--text-xs)", color: "var(--text-data)" }}>
            jobs {jobText()}
          </span>
          <span style={{ "font-family": "var(--font-data)", "font-size": "var(--text-xs)", color: project().riskCount ? "var(--posture-warm)" : "var(--truth-observed)" }}>
            risks {project().riskCount || 0}
          </span>
          <span style={{ "font-family": "var(--font-data)", "font-size": "var(--text-xs)", color: ledgerCount() ? "var(--truth-observed)" : "var(--text-tertiary)" }}>
            actions {ledgerCount()}
          </span>
        </div>

        <div>
          <div style={{ "font-family": "var(--font-data)", "font-size": "var(--text-xs)", color: "var(--text-secondary)", "line-height": 1.45, "margin-bottom": "var(--space-2)" }}>
            {project().nextSafeMove || "observe project state"}
          </div>
          <Show when={project().autopilot?.proposalCount}>
            <div style={{ "font-family": "var(--font-data)", "font-size": "var(--text-xs)", color: "var(--truth-observed)" }}>
              autopilot proposals: {project().autopilot.proposalCount}
            </div>
          </Show>
        </div>
      </div>
    </GlassPanel>
  );
}

function LedgerRow(props) {
  const action = () => props.action || {};
  const status = () => action().status || "proposed";
  return (
    <div style={{ display: "grid", "grid-template-columns": "minmax(120px, 0.7fr) minmax(0, 1.5fr) minmax(90px, 0.4fr)", gap: "var(--space-3)", "align-items": "start", padding: "var(--space-2) 0", "border-bottom": "1px solid rgba(255,255,255,0.06)" }}>
      <div style={{ "font-family": "var(--font-data)", "font-size": "var(--text-xs)", color: "var(--text-tertiary)", "word-break": "break-word" }}>
        {action().projectSlug || "-"}
      </div>
      <div style={{ "min-width": 0 }}>
        <div style={{ "font-family": "var(--font-data)", "font-size": "var(--text-xs)", color: "var(--text-data)", "line-height": 1.35, "word-break": "break-word" }}>
          {action().proposal?.label || action().actionId || action().ledger_id}
        </div>
        <div style={{ "font-family": "var(--font-data)", "font-size": "var(--text-xs)", color: "var(--text-tertiary)", "line-height": 1.35, "margin-top": "var(--space-1)", "word-break": "break-word" }}>
          {action().proposal?.summary || action().route || action().command || "receipt"}
        </div>
      </div>
      <div style={{ "font-family": "var(--font-data)", "font-size": "var(--text-xs)", color: statusColor(status()), "text-align": "right" }}>
        {status()}
      </div>
    </div>
  );
}

export default function ProjectOS() {
  useTitle("Project OS");
  const navigate = useNavigate();
  const [packet, { refetch }] = createResource(fetchProjectOs);
  const data = () => packet()?.data || {};
  const projects = () => data().projects || [];
  const grouped = createMemo(() => ({
    alwaysOn: projects().filter((project) => project.posture === "always-on"),
    warm: projects().filter((project) => project.posture === "warm"),
    cold: projects().filter((project) => project.posture === "cold"),
  }));

  return (
    <div style={{
      position: "relative",
      "z-index": 1,
      padding: "var(--space-6) var(--space-8)",
      "max-width": "1280px",
      margin: "0 auto",
      height: "100%",
      "overflow-y": "auto",
    }}>
      <div style={{ display: "flex", "align-items": "center", "justify-content": "space-between", gap: "var(--space-4)", "margin-bottom": "var(--space-5)" }}>
        <div>
          <h1 style={{
            "font-family": "var(--font-display)",
            "font-size": "var(--text-2xl)",
            "font-weight": "var(--weight-semibold)",
            color: "var(--text-primary)",
            "letter-spacing": "0",
          }}>
            Darwin Project OS
          </h1>
          <div style={{ display: "flex", gap: "var(--space-2)", "align-items": "center", "margin-top": "var(--space-1)" }}>
            <TruthBadge mode={packet()?.truthMode || "declared"} />
            <span style={{ "font-family": "var(--font-data)", "font-size": "var(--text-xs)", color: "var(--text-tertiary)" }}>
              {data().policy?.mutationRule || "observe -> propose -> confirm -> readback"}
            </span>
          </div>
        </div>
        <div style={{ display: "flex", gap: "var(--space-2)", "flex-wrap": "wrap", "justify-content": "flex-end" }}>
          <button onClick={() => navigate("/projects")} style={{ padding: "var(--space-2) var(--space-3)", color: "var(--text-secondary)", "font-family": "var(--font-data)", "font-size": "var(--text-xs)", border: "1px solid var(--glass-border)", "border-radius": "var(--radius-sm)", background: "rgba(255,255,255,0.04)" }}>bridge</button>
          <button onClick={() => navigate("/projects/cluster")} style={{ padding: "var(--space-2) var(--space-3)", color: "var(--text-secondary)", "font-family": "var(--font-data)", "font-size": "var(--text-xs)", border: "1px solid var(--glass-border)", "border-radius": "var(--radius-sm)", background: "rgba(255,255,255,0.04)" }}>cluster</button>
          <button onClick={() => refetch()} style={{ padding: "var(--space-2) var(--space-3)", color: "var(--truth-observed)", "font-family": "var(--font-data)", "font-size": "var(--text-xs)", border: "1px solid rgba(81, 214, 189, 0.24)", "border-radius": "var(--radius-sm)", background: "rgba(81, 214, 189, 0.10)" }}>refresh</button>
        </div>
      </div>

      <Show when={data().schema} fallback={<GlassPanel><Skeleton lines={6} /></GlassPanel>}>
        <GlassPanel elevated truth={packet()?.truthMode || "observed"} style={{ "margin-bottom": "var(--space-4)" }}>
          <div style={{ display: "grid", "grid-template-columns": "repeat(auto-fit, minmax(110px, 1fr))", gap: "var(--space-4)" }}>
            <Metric label="projects" value={data().counts?.total || 0} />
            <Metric label="live" value={data().counts?.live || 0} color="var(--truth-observed)" />
            <Metric label="risks" value={data().counts?.risks || 0} color={data().counts?.risks ? "var(--posture-warm)" : "var(--truth-observed)"} />
            <Metric label="agents" value={data().counts?.agents || 0} />
            <Metric label="jobs" value={data().counts?.jobs || 0} />
            <Metric label="proposals" value={data().counts?.proposals || 0} color="var(--truth-observed)" />
            <Metric label="actions" value={data().counts?.actions || 0} color="var(--truth-observed)" />
          </div>
        </GlassPanel>

        <Show when={data().actionLedger?.recent?.length}>
          <GlassPanel truth={data().actionLedger?.status || "observed"} style={{ "margin-bottom": "var(--space-4)" }}>
            <div style={{ display: "flex", "align-items": "center", "justify-content": "space-between", gap: "var(--space-3)", "margin-bottom": "var(--space-2)" }}>
              <h2 style={{ "font-family": "var(--font-ui)", "font-size": "var(--text-xs)", "font-weight": "var(--weight-semibold)", "text-transform": "uppercase", "letter-spacing": "0.08em", color: "var(--text-tertiary)" }}>Recent Actions</h2>
              <span style={{ "font-family": "var(--font-data)", "font-size": "var(--text-xs)", color: "var(--truth-observed)" }}>ledger</span>
            </div>
            <For each={data().actionLedger.recent}>
              {(action) => <LedgerRow action={action} />}
            </For>
          </GlassPanel>
        </Show>

        <div style={{ display: "flex", "flex-direction": "column", gap: "var(--space-4)" }}>
          <Show when={grouped().alwaysOn.length}>
            <section>
              <h2 style={{ "font-family": "var(--font-ui)", "font-size": "var(--text-xs)", "font-weight": "var(--weight-semibold)", "text-transform": "uppercase", "letter-spacing": "0.08em", color: "var(--text-tertiary)", "margin-bottom": "var(--space-2)" }}>always-on</h2>
              <div style={{ display: "flex", "flex-direction": "column", gap: "var(--space-3)" }}>
                <For each={grouped().alwaysOn}>{(project) => <ProjectRow project={project} />}</For>
              </div>
            </section>
          </Show>

          <Show when={grouped().warm.length}>
            <section>
              <h2 style={{ "font-family": "var(--font-ui)", "font-size": "var(--text-xs)", "font-weight": "var(--weight-semibold)", "text-transform": "uppercase", "letter-spacing": "0.08em", color: "var(--text-tertiary)", "margin-bottom": "var(--space-2)" }}>warm</h2>
              <div style={{ display: "flex", "flex-direction": "column", gap: "var(--space-3)" }}>
                <For each={grouped().warm}>{(project) => <ProjectRow project={project} />}</For>
              </div>
            </section>
          </Show>

          <Show when={grouped().cold.length}>
            <section>
              <h2 style={{ "font-family": "var(--font-ui)", "font-size": "var(--text-xs)", "font-weight": "var(--weight-semibold)", "text-transform": "uppercase", "letter-spacing": "0.08em", color: "var(--text-tertiary)", "margin-bottom": "var(--space-2)" }}>cold</h2>
              <div style={{ display: "flex", "flex-direction": "column", gap: "var(--space-3)" }}>
                <For each={grouped().cold}>{(project) => <ProjectRow project={project} />}</For>
              </div>
            </section>
          </Show>
        </div>
      </Show>
    </div>
  );
}
