/**
 * ControlTower - /projects/:slug/control
 *
 * A compact operator surface for the daily loop: orient, inspect, then run
 * only confirmed Cockpit actions.
 */
import { For, Show, createMemo, createResource, createSignal } from "solid-js";
import { useNavigate, useParams } from "@solidjs/router";
import { useTitle } from "../hooks/useTitle";
import { fetchWithTruth } from "../stores/truth";
import GlassPanel from "../components/GlassPanel";
import TruthBadge from "../components/TruthBadge";
import PostureIndicator from "../components/PostureIndicator";
import Skeleton from "../components/Skeleton";

async function fetchJson(path, timeoutMs = 8000) {
  const res = await fetch(path, { signal: AbortSignal.timeout(timeoutMs) });
  const payload = await res.json().catch(() => ({}));
  if (!res.ok) throw new Error(payload?.error?.message || payload?.error || `${res.status}`);
  return payload;
}

async function postJson(path, body = {}, timeoutMs = 300000) {
  const requestId =
    body.idempotencyKey ||
    (globalThis.crypto?.randomUUID ? globalThis.crypto.randomUUID() : `${Date.now()}-${Math.random()}`);
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

async function fetchActions(slug) {
  return fetchJson(`/api/projects/${slug}/actions?limit=12`).catch((error) => ({
    error: error.message,
    actions: [],
  }));
}

function valueOf(value, fallback = "-") {
  if (value === undefined || value === null || value === "") return fallback;
  return String(value);
}

function statusColor(value) {
  const normalized = String(value || "").toLowerCase();
  if (normalized.includes("fail") || normalized.includes("error") || normalized.includes("stale")) return "var(--state-error)";
  if (normalized.includes("warn") || normalized.includes("drift") || normalized.includes("pending")) return "var(--posture-warm)";
  if (normalized.includes("live") || normalized.includes("ready") || normalized.includes("ok") || normalized.includes("observed")) return "var(--truth-observed)";
  return "var(--text-tertiary)";
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
        "font-size": "var(--text-sm)",
        color: props.color || "var(--text-data)",
        "word-break": "break-word",
      }}>
        {props.value}
      </span>
    </div>
  );
}

function TowerButton(props) {
  return (
    <button
      disabled={props.disabled}
      title={props.title}
      onClick={props.onClick}
      style={{
        padding: "var(--space-2) var(--space-3)",
        background: props.danger ? "rgba(239, 68, 68, 0.10)" : "rgba(81, 214, 189, 0.10)",
        border: props.danger ? "1px solid rgba(239, 68, 68, 0.28)" : "1px solid rgba(81, 214, 189, 0.24)",
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

export default function ControlTower() {
  const params = useParams();
  const navigate = useNavigate();
  useTitle(() => `${params.slug} · Control Tower`);

  const [controlTruth, { refetch: refetchControl }] = createResource(() => params.slug, (slug) => fetchWithTruth(`/api/projects/${slug}/control-plane`, 8000));
  const [goWorkTruth, { refetch: refetchGoWork }] = createResource(() => params.slug, (slug) => fetchWithTruth(`/api/projects/${slug}/go-work-now`, 8000));
  const [agentTruth, { refetch: refetchAgents }] = createResource(() => params.slug, (slug) => fetchJson(`/api/projects/${slug}/agent/sessions`).catch((error) => ({ error: error.message, sessions: [] })));
  const [jobTruth, { refetch: refetchJobs }] = createResource(() => params.slug, (slug) => fetchJson(`/api/projects/${slug}/jobs`).catch((error) => ({ error: error.message, jobs: [] })));
  const [ledgerTruth, { refetch: refetchLedger }] = createResource(() => params.slug, fetchActions);
  const [mutation, setMutation] = createSignal(null);

  const controlPlane = () => controlTruth()?.data?.controlPlane || {};
  const state = () => controlPlane().state || {};
  const actions = () => controlPlane().actions || [];
  const goWork = () => goWorkTruth()?.data?.goWorkNow || goWorkTruth()?.data || {};
  const workspace = () => goWork().workspaceState || {};
  const sessions = () => agentTruth()?.sessions || agentTruth()?.agentSessions || [];
  const jobs = () => jobTruth()?.jobs || [];
  const ledgerActions = () => ledgerTruth()?.actions || [];
  const action = (id) => actions().find((item) => item.id === id) || {};
  const autopilot = () => controlPlane().autopilot || {};
  const proposals = () => autopilot().proposals || [];
  const risks = createMemo(() => [
    ...(state().branchDrift ? [{ severity: "warn", code: "branch_drift", summary: `${state().observedBranch || "unknown"} vs ${state().preferredBranch || "unknown"}` }] : []),
    ...(Number(state().publishableDirtyCount ?? state().dirtyCount ?? 0) > 0 ? [{ severity: "warn", code: "dirty_workspace", summary: `${state().publishableDirtyCount ?? state().dirtyCount} changed item(s)` }] : []),
    ...(controlPlane().blockers || []),
    ...(controlPlane().notices || []),
  ]);

  async function runAction(actionId) {
    const item = action(actionId);
    if (!item.id || item.enabled === false) {
      setMutation({ state: "error", label: item.label || actionId, output: item.reason || "action disabled" });
      return;
    }
    if (item.kind === "route" || item.method === "GET") {
      navigate(item.route);
      return;
    }
    const label = item.label || item.id;
    const accepted = globalThis.confirm(`${label}\n${item.route}`);
    if (!accepted) return;

    setMutation({ state: "running", label, output: "" });
    try {
      const result = await postJson(item.route, item.body || {});
      setMutation({ state: "done", label, output: result?.status || result?.job_id || result?.action || "done" });
      refetchControl();
      refetchGoWork();
      refetchAgents();
      refetchJobs();
    } catch (error) {
      setMutation({ state: "error", label, output: error.message });
    }
  }

  async function recordProposal(proposal) {
    const requestId =
      globalThis.crypto?.randomUUID ? globalThis.crypto.randomUUID() : `${Date.now()}-${Math.random()}`;
    setMutation({ state: "running", label: proposal.label || proposal.id, output: "recording proposal" });
    try {
      const result = await postJson(
        `/api/projects/${params.slug}/actions/propose`,
        {
          proposal,
          actionId: proposal.actionId || "",
          source: "control-tower-autopilot",
          actor: "operator",
          idempotencyKey: requestId,
        },
        12000
      );
      const ledgerId = result?.action?.ledger_id || result?.event?.ledger_id || "recorded";
      setMutation({ state: "done", label: proposal.label || proposal.id, output: `proposal ${ledgerId}` });
      refetchLedger();
      refetchControl();
    } catch (error) {
      setMutation({ state: "error", label: proposal.label || proposal.id, output: error.message });
    }
  }

  function refreshAll() {
    refetchControl();
    refetchGoWork();
    refetchAgents();
    refetchJobs();
    refetchLedger();
  }

  return (
    <div style={{
      position: "relative",
      "z-index": 1,
      padding: "var(--space-6) var(--space-8)",
      "max-width": "1180px",
      margin: "0 auto",
      height: "100%",
      "overflow-y": "auto",
    }}>
      <div style={{ display: "flex", "align-items": "center", "justify-content": "space-between", gap: "var(--space-4)", "margin-bottom": "var(--space-5)" }}>
        <div style={{ display: "flex", "align-items": "center", gap: "var(--space-3)" }}>
          <button
            onClick={() => navigate("/projects")}
            title="Projects"
            style={{ color: "var(--text-tertiary)", "font-size": "var(--text-sm)", opacity: 0.7 }}
          >
            back
          </button>
          <div>
            <h1 style={{
              "font-family": "var(--font-display)",
              "font-size": "var(--text-2xl)",
              "font-weight": "var(--weight-semibold)",
              color: "var(--text-primary)",
              "letter-spacing": "0",
              "text-transform": "uppercase",
            }}>
              {params.slug} control
            </h1>
            <div style={{ display: "flex", gap: "var(--space-2)", "align-items": "center", "margin-top": "var(--space-1)" }}>
              <PostureIndicator mode={state().posture || "warm"} />
              <TruthBadge mode={controlTruth()?.truthMode || "declared"} />
            </div>
          </div>
        </div>
        <div style={{ display: "flex", gap: "var(--space-2)", "flex-wrap": "wrap", "justify-content": "flex-end" }}>
          <TowerButton onClick={() => navigate(`/projects/${params.slug}`)}>full cockpit</TowerButton>
          <TowerButton onClick={() => navigate("/projects/os")}>project os</TowerButton>
          <TowerButton onClick={() => navigate("/projects/cluster")}>cluster</TowerButton>
          <TowerButton onClick={() => navigate(`/projects/${params.slug}/viewer`)}>viewer</TowerButton>
          <TowerButton onClick={refreshAll}>refresh</TowerButton>
        </div>
      </div>

      <GlassPanel elevated truth={controlTruth()?.truthMode || "declared"} style={{ "margin-bottom": "var(--space-4)" }}>
        <Show when={controlPlane().projectSlug} fallback={<Skeleton lines={5} />}>
          <div style={{ display: "grid", "grid-template-columns": "minmax(0, 1.4fr) minmax(280px, 0.6fr)", gap: "var(--space-5)" }}>
            <div>
              <div style={{
                "font-family": "var(--font-display)",
                "font-size": "var(--text-xl)",
                "font-weight": "var(--weight-semibold)",
                color: "var(--text-primary)",
                "line-height": 1.25,
                "margin-bottom": "var(--space-4)",
              }}>
                {controlPlane().nextSafeMove || "control packet loading"}
              </div>
              <div style={{
                display: "grid",
                "grid-template-columns": "repeat(auto-fit, minmax(170px, 1fr))",
                gap: "var(--space-4)",
              }}>
                <Metric label="workspace" value={valueOf(state().workspaceStatus || workspace().status)} color={statusColor(state().workspaceStatus || workspace().status)} />
                <Metric label="entrypoint" value={valueOf(state().entrypoint || goWork().primaryEntry)} />
                <Metric label="branch" value={valueOf(state().observedBranch || state().preferredBranch)} color={state().branchDrift ? "var(--posture-warm)" : "var(--text-data)"} />
                <Metric label="preferred" value={valueOf(state().preferredBranch)} />
                <Metric label="dirty" value={valueOf(state().publishableDirtyCount ?? state().dirtyCount, "unknown")} />
                <Metric label="namespace" value={valueOf(state().namespace)} />
              </div>
            </div>

            <div style={{ display: "flex", "flex-direction": "column", gap: "var(--space-2)" }}>
              <For each={["activate-habitat", "start-agent", "submit-smoke", "standby-habitat"]}>
                {(id) => {
                  const item = action(id);
                  return (
                    <TowerButton
                      danger={item.destructive}
                      disabled={!item.id || item.enabled === false}
                      title={item.reason}
                      onClick={() => runAction(id)}
                    >
                      {item.label || id}
                    </TowerButton>
                  );
                }}
              </For>
            </div>
          </div>
        </Show>
      </GlassPanel>

      <div style={{ display: "grid", "grid-template-columns": "repeat(auto-fit, minmax(280px, 1fr))", gap: "var(--space-4)" }}>
        <GlassPanel truth={risks().some((risk) => risk.severity === "fail") ? "stale" : risks().length ? "remembered" : "observed"}>
          <div style={{ display: "flex", "align-items": "center", "justify-content": "space-between", "margin-bottom": "var(--space-3)" }}>
            <h2 style={{ "font-family": "var(--font-ui)", "font-size": "var(--text-xs)", "font-weight": "var(--weight-semibold)", "text-transform": "uppercase", "letter-spacing": "0.08em", color: "var(--text-tertiary)" }}>Risks</h2>
            <span style={{ "font-family": "var(--font-data)", "font-size": "var(--text-xs)", color: risks().length ? "var(--posture-warm)" : "var(--truth-observed)" }}>{risks().length}</span>
          </div>
          <Show when={risks().length} fallback={<div style={{ "font-family": "var(--font-data)", "font-size": "var(--text-sm)", color: "var(--truth-observed)" }}>clean</div>}>
            <div style={{ display: "flex", "flex-direction": "column", gap: "var(--space-2)" }}>
              <For each={risks().slice(0, 6)}>
                {(risk) => (
                  <div style={{ "font-family": "var(--font-data)", "font-size": "var(--text-xs)", color: risk.severity === "fail" ? "var(--state-error)" : "var(--posture-warm)", "line-height": 1.45 }}>
                    {risk.severity || "warn"} · {risk.code || "risk"}: {risk.summary || risk.reason || "observed"}
                  </div>
                )}
              </For>
            </div>
          </Show>
        </GlassPanel>

        <GlassPanel truth={agentTruth()?.error ? "stale" : "observed"}>
          <h2 style={{ "font-family": "var(--font-ui)", "font-size": "var(--text-xs)", "font-weight": "var(--weight-semibold)", "text-transform": "uppercase", "letter-spacing": "0.08em", color: "var(--text-tertiary)", "margin-bottom": "var(--space-3)" }}>Agents</h2>
          <Show when={sessions().length} fallback={<div style={{ "font-family": "var(--font-data)", "font-size": "var(--text-sm)", color: "var(--text-tertiary)" }}>{agentTruth()?.error || "no sessions"}</div>}>
            <div style={{ display: "flex", "flex-direction": "column", gap: "var(--space-2)" }}>
              <For each={sessions().slice(0, 6)}>
                {(session) => (
                  <div style={{ display: "flex", "justify-content": "space-between", gap: "var(--space-3)", "font-family": "var(--font-data)", "font-size": "var(--text-xs)", color: "var(--text-data)" }}>
                    <span>{valueOf(session.kind || session.agentKind || session.name, "agent")}</span>
                    <span style={{ color: statusColor(session.phase || session.status) }}>{valueOf(session.phase || session.status, "observed")}</span>
                  </div>
                )}
              </For>
            </div>
          </Show>
        </GlassPanel>

        <GlassPanel truth={jobTruth()?.error ? "stale" : "observed"}>
          <h2 style={{ "font-family": "var(--font-ui)", "font-size": "var(--text-xs)", "font-weight": "var(--weight-semibold)", "text-transform": "uppercase", "letter-spacing": "0.08em", color: "var(--text-tertiary)", "margin-bottom": "var(--space-3)" }}>Jobs</h2>
          <Show when={jobs().length} fallback={<div style={{ "font-family": "var(--font-data)", "font-size": "var(--text-sm)", color: "var(--text-tertiary)" }}>{jobTruth()?.error || "no jobs"}</div>}>
            <div style={{ display: "flex", "flex-direction": "column", gap: "var(--space-2)" }}>
              <For each={jobs().slice(0, 6)}>
                {(job) => (
                  <div style={{ display: "flex", "justify-content": "space-between", gap: "var(--space-3)", "font-family": "var(--font-data)", "font-size": "var(--text-xs)", color: "var(--text-data)" }}>
                    <span>{valueOf(job.job_id || job.job_name)}</span>
                    <span style={{ color: statusColor(job.status || job.phase || (job.failed ? "fail" : job.active ? "running" : "ok")) }}>
                      active {job.active || 0} ok {job.succeeded || 0} fail {job.failed || 0}
                    </span>
                  </div>
                )}
              </For>
            </div>
          </Show>
        </GlassPanel>

        <GlassPanel truth={proposals().length ? "remembered" : "observed"}>
          <div style={{ display: "flex", "align-items": "center", "justify-content": "space-between", gap: "var(--space-3)", "margin-bottom": "var(--space-3)" }}>
            <h2 style={{ "font-family": "var(--font-ui)", "font-size": "var(--text-xs)", "font-weight": "var(--weight-semibold)", "text-transform": "uppercase", "letter-spacing": "0.08em", color: "var(--text-tertiary)" }}>Autopilot</h2>
            <span style={{ "font-family": "var(--font-data)", "font-size": "var(--text-xs)", color: "var(--truth-observed)" }}>{autopilot().mode || "propose-only"}</span>
          </div>
          <Show when={proposals().length} fallback={<div style={{ "font-family": "var(--font-data)", "font-size": "var(--text-sm)", color: "var(--text-tertiary)" }}>no proposals</div>}>
            <div style={{ display: "flex", "flex-direction": "column", gap: "var(--space-2)" }}>
              <For each={proposals().slice(0, 6)}>
                {(proposal) => (
                  <div style={{ display: "flex", "flex-direction": "column", gap: "var(--space-1)", padding: "var(--space-2)", background: "rgba(255,255,255,0.03)", "border-radius": "var(--radius-sm)" }}>
                    <div style={{ display: "flex", "justify-content": "space-between", gap: "var(--space-2)", "font-family": "var(--font-data)", "font-size": "var(--text-xs)", color: "var(--text-data)" }}>
                      <span>{proposal.label || proposal.id}</span>
                      <span style={{ color: proposal.risk === "high" ? "var(--state-error)" : proposal.risk === "medium" ? "var(--posture-warm)" : "var(--truth-observed)" }}>{proposal.risk || "low"}</span>
                    </div>
                    <div style={{ "font-family": "var(--font-data)", "font-size": "var(--text-xs)", color: "var(--text-tertiary)", "line-height": 1.45 }}>
                      {proposal.summary}
                    </div>
                    <Show when={proposal.actionId}>
                      <button
                        onClick={() => recordProposal(proposal)}
                        style={{ "align-self": "flex-start", padding: "var(--space-1) var(--space-2)", background: "rgba(81, 214, 189, 0.10)", border: "1px solid rgba(81, 214, 189, 0.24)", "border-radius": "var(--radius-sm)", color: "var(--truth-observed)", "font-family": "var(--font-data)", "font-size": "var(--text-xs)" }}
                      >
                        prepare
                      </button>
                    </Show>
                  </div>
                )}
              </For>
            </div>
          </Show>
        </GlassPanel>

        <GlassPanel truth={ledgerTruth()?.error ? "stale" : "observed"}>
          <div style={{ display: "flex", "align-items": "center", "justify-content": "space-between", gap: "var(--space-3)", "margin-bottom": "var(--space-3)" }}>
            <h2 style={{ "font-family": "var(--font-ui)", "font-size": "var(--text-xs)", "font-weight": "var(--weight-semibold)", "text-transform": "uppercase", "letter-spacing": "0.08em", color: "var(--text-tertiary)" }}>Action Ledger</h2>
            <span style={{ "font-family": "var(--font-data)", "font-size": "var(--text-xs)", color: "var(--truth-observed)" }}>receipts</span>
          </div>
          <Show when={ledgerActions().length} fallback={<div style={{ "font-family": "var(--font-data)", "font-size": "var(--text-sm)", color: "var(--text-tertiary)" }}>{ledgerTruth()?.error || "no receipts"}</div>}>
            <div style={{ display: "flex", "flex-direction": "column", gap: "var(--space-2)" }}>
              <For each={ledgerActions().slice(0, 6)}>
                {(entry) => (
                  <div style={{ display: "flex", "flex-direction": "column", gap: "var(--space-1)", padding: "var(--space-2)", background: "rgba(255,255,255,0.03)", "border-radius": "var(--radius-sm)" }}>
                    <div style={{ display: "flex", "justify-content": "space-between", gap: "var(--space-2)", "font-family": "var(--font-data)", "font-size": "var(--text-xs)", color: "var(--text-data)" }}>
                      <span style={{ "word-break": "break-word" }}>{entry.proposal?.label || entry.actionId || entry.ledger_id}</span>
                      <span style={{ color: statusColor(entry.status) }}>{entry.status || "proposed"}</span>
                    </div>
                    <div style={{ "font-family": "var(--font-data)", "font-size": "var(--text-xs)", color: "var(--text-tertiary)", "line-height": 1.45, "word-break": "break-word" }}>
                      {entry.proposal?.summary || entry.route || entry.command || entry.ledger_id}
                    </div>
                  </div>
                )}
              </For>
            </div>
          </Show>
        </GlassPanel>
      </div>

      <Show when={mutation()}>
        <GlassPanel subtle truth={mutation().state === "error" ? "stale" : mutation().state === "done" ? "observed" : "remembered"} style={{ "margin-top": "var(--space-4)" }}>
          <div style={{ "font-family": "var(--font-data)", "font-size": "var(--text-xs)", color: mutation().state === "error" ? "var(--state-error)" : "var(--text-data)" }}>
            {mutation().label}: {mutation().state}{mutation().output ? ` - ${mutation().output}` : ""}
          </div>
        </GlassPanel>
      </Show>
    </div>
  );
}
