/**
 * ClusterOps - /projects/cluster
 *
 * Darwin cluster control lane: observed state, allowlisted actions, ledgered
 * confirmation, execution receipt, and readback.
 */
import { For, Show, createMemo, createResource, createSignal } from "solid-js";
import { useNavigate } from "@solidjs/router";
import { useTitle } from "../hooks/useTitle";
import { fetchWithTruth } from "../stores/truth";
import GlassPanel from "../components/GlassPanel";
import TruthBadge from "../components/TruthBadge";
import Skeleton from "../components/Skeleton";

const ACTION_PROJECT = "beagle";

async function fetchClusterOps() {
  return fetchWithTruth("/api/cluster/ops/summary", 60000);
}

function requestId() {
  return globalThis.crypto?.randomUUID
    ? globalThis.crypto.randomUUID()
    : `${Date.now()}-${Math.random()}`;
}

async function postJson(path, body = {}, timeoutMs = 300000) {
  const id = body.idempotencyKey || requestId();
  const res = await fetch(path, {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      "X-Request-ID": id,
      "X-Darwin-Actor": "operator",
    },
    body: JSON.stringify({ ...body, idempotencyKey: id }),
    signal: AbortSignal.timeout(timeoutMs),
  });
  const payload = await res.json().catch(() => ({}));
  if (!res.ok) throw new Error(payload?.error?.message || payload?.error || `${res.status}`);
  return payload;
}

function valueOf(value, fallback = "-") {
  if (value === undefined || value === null || value === "") return fallback;
  return String(value);
}

function statusColor(value) {
  const normalized = String(value || "").toLowerCase();
  if (normalized.includes("red") || normalized.includes("fail") || normalized.includes("error") || normalized.includes("stale") || normalized.includes("critical")) return "var(--state-error)";
  if (normalized.includes("yellow") || normalized.includes("attention") || normalized.includes("partial") || normalized.includes("warn") || normalized.includes("medium") || normalized.includes("high")) return "var(--posture-warm)";
  if (normalized.includes("green") || normalized.includes("healthy") || normalized.includes("ready") || normalized.includes("observed") || normalized.includes("low")) return "var(--truth-observed)";
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
        "font-size": props.large ? "var(--text-lg)" : "var(--text-sm)",
        color: props.color || "var(--text-data)",
        "word-break": "break-word",
      }}>
        {props.value}
      </span>
    </div>
  );
}

function OpsButton(props) {
  return (
    <button
      disabled={props.disabled}
      onClick={props.onClick}
      title={props.title}
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

function SectionTitle(props) {
  return (
    <div style={{ display: "flex", "align-items": "center", "justify-content": "space-between", gap: "var(--space-3)", "margin-bottom": "var(--space-3)" }}>
      <h2 style={{
        "font-family": "var(--font-ui)",
        "font-size": "var(--text-xs)",
        "font-weight": "var(--weight-semibold)",
        "text-transform": "uppercase",
        "letter-spacing": "0.08em",
        color: "var(--text-tertiary)",
      }}>
        {props.children}
      </h2>
      <Show when={props.status}>
        <span style={{ "font-family": "var(--font-data)", "font-size": "var(--text-xs)", color: statusColor(props.status) }}>
          {props.status}
        </span>
      </Show>
    </div>
  );
}

function NodeTable(props) {
  return (
    <div style={{ overflow: "auto" }}>
      <div style={{
        display: "grid",
        "grid-template-columns": "minmax(130px, 1fr) 70px 105px minmax(120px, 1fr) 65px minmax(130px, 1fr)",
        gap: "var(--space-3)",
        "font-family": "var(--font-data)",
        "font-size": "var(--text-xs)",
        color: "var(--text-tertiary)",
        "padding-bottom": "var(--space-2)",
        "min-width": "720px",
      }}>
        <span>node</span>
        <span>ready</span>
        <span>role</span>
        <span>accelerator</span>
        <span>gpu</span>
        <span>storage/runtime</span>
      </div>
      <For each={props.nodes || []}>
        {(node) => (
          <div style={{
            display: "grid",
            "grid-template-columns": "minmax(130px, 1fr) 70px 105px minmax(120px, 1fr) 65px minmax(130px, 1fr)",
            gap: "var(--space-3)",
            "font-family": "var(--font-data)",
            "font-size": "var(--text-xs)",
            color: "var(--text-data)",
            padding: "var(--space-2) 0",
            "border-top": "1px solid rgba(255,255,255,0.06)",
            "min-width": "720px",
          }}>
            <span style={{ "word-break": "break-word" }}>{node.name}</span>
            <span style={{ color: node.ready ? "var(--truth-observed)" : "var(--state-error)" }}>{node.ready ? "yes" : "no"}</span>
            <span>{node.role}</span>
            <span style={{ "word-break": "break-word" }}>{valueOf(node.gpu?.accelerator || node.gpu?.acceleratorClass)}</span>
            <span>{node.gpu?.allocatable ?? 0}/{node.gpu?.capacity ?? 0}</span>
            <span style={{ "word-break": "break-word" }}>
              {valueOf(node.labels?.storageProfile || node.labels?.orangefsClient)} / {valueOf(node.labels?.runtimeRole || node.labels?.pool)}
            </span>
          </div>
        )}
      </For>
    </div>
  );
}

function ResultPanel(props) {
  const result = () => props.result || {};
  return (
    <Show when={props.result}>
      <GlassPanel subtle truth={result().state === "error" ? "stale" : result().state === "done" ? "observed" : "remembered"} style={{ "margin-top": "var(--space-4)" }}>
        <div style={{ display: "flex", "justify-content": "space-between", gap: "var(--space-3)", "margin-bottom": "var(--space-2)", "flex-wrap": "wrap" }}>
          <span style={{ "font-family": "var(--font-data)", "font-size": "var(--text-xs)", color: result().state === "error" ? "var(--state-error)" : "var(--truth-observed)" }}>
            {result().label}: {result().state}
          </span>
          <Show when={result().receipt?.artifactRoot}>
            <span style={{ "font-family": "var(--font-data)", "font-size": "var(--text-xs)", color: "var(--text-tertiary)", "word-break": "break-word" }}>
              {result().receipt.artifactRoot}
            </span>
          </Show>
        </div>
        <pre style={{
          margin: 0,
          "max-height": "260px",
          overflow: "auto",
          "white-space": "pre-wrap",
          "font-family": "var(--font-data)",
          "font-size": "var(--text-xs)",
          color: result().state === "error" ? "var(--state-error)" : "var(--text-data)",
        }}>
          {result().output || ""}
        </pre>
      </GlassPanel>
    </Show>
  );
}

export default function ClusterOps() {
  useTitle("Darwin Cluster Ops");
  const navigate = useNavigate();
  const [packet, { refetch }] = createResource(fetchClusterOps);
  const [targetNode, setTargetNode] = createSignal("r740-proxmox");
  const [mutation, setMutation] = createSignal(null);

  const data = () => packet()?.data || {};
  const lanes = () => data().lanes || {};
  const nodes = () => lanes().kubernetes?.nodes || [];
  const risks = () => data().risks || [];
  const actions = () => data().actions || [];
  const workerTargets = createMemo(() =>
    nodes()
      .filter((node) => node.role !== "control-plane")
      .map((node) => node.name)
      .filter((name) => ["r770-proxmox", "5860-proxmox", "r740-proxmox"].includes(name))
  );
  const gpuNodes = createMemo(() => nodes().filter((node) => Number(node.gpu?.capacity || 0) > 0));

  async function runClusterAction(action) {
    if (!action?.id) return;
    const target = action.requiresTarget ? targetNode() : "";
    const targetText = target ? `\nTarget: ${target}` : "";
    const accepted = globalThis.confirm(`${action.label}\nRisk: ${action.risk}${targetText}\n\nRecord intent and execute this allowlisted action?`);
    if (!accepted) return;

    setMutation({ state: "running", label: action.label, output: "recording Action Ledger proposal" });
    try {
      const baseBody = {
        actor: "operator",
        source: "cluster-ops-ui",
      };
      const proposed = await postJson(
        `/api/projects/${ACTION_PROJECT}/actions/propose`,
        {
          ...baseBody,
          proposal: {
            id: `cluster-${action.id}`,
            label: action.label,
            kind: "cluster-ops",
            summary: target ? `${action.summary} target=${target}` : action.summary,
            risk: action.risk,
            actionId: action.id,
            route: action.route,
            requiresConfirmation: true,
          },
        },
        12000
      );
      const ledgerId = proposed?.action?.ledger_id || proposed?.event?.ledger_id;
      if (!ledgerId) throw new Error("Action Ledger did not return ledger_id");
      setMutation({ state: "running", label: action.label, output: `intent ${ledgerId}` });

      await postJson(
        `/api/projects/${ACTION_PROJECT}/actions/${ledgerId}/confirm-intent`,
        {
          ...baseBody,
          reason: `Cluster Ops execution requested for ${action.id}`,
        },
        20000
      );

      setMutation({ state: "running", label: action.label, output: "executing allowlisted action" });
      const result = await postJson(
        action.route,
        {
          ...baseBody,
          confirmed: true,
          ledgerId,
          targetNode: target || undefined,
        },
        action.kind === "host" ? 1900000 : 240000
      );
      const output = [
        `ledger ${ledgerId}`,
        `exit ${result?.result?.code ?? "unknown"}`,
        result?.result?.stdout || "",
        result?.result?.stderr || "",
      ].filter(Boolean).join("\n\n");
      setMutation({ state: result.ok ? "done" : "error", label: action.label, output, receipt: result.receipt });
      refetch();
    } catch (error) {
      setMutation({ state: "error", label: action.label, output: error.message });
    }
  }

  return (
    <div style={{
      position: "relative",
      "z-index": 1,
      padding: "var(--space-6) var(--space-8)",
      "max-width": "1320px",
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
            "text-transform": "uppercase",
          }}>
            Darwin Cluster Ops
          </h1>
          <div style={{ display: "flex", gap: "var(--space-2)", "align-items": "center", "margin-top": "var(--space-1)", "flex-wrap": "wrap" }}>
            <TruthBadge mode={packet()?.truthMode || "declared"} />
            <span style={{ "font-family": "var(--font-data)", "font-size": "var(--text-xs)", color: statusColor(data().status) }}>
              status {valueOf(data().status, "loading")}
            </span>
            <span style={{ "font-family": "var(--font-data)", "font-size": "var(--text-xs)", color: "var(--text-tertiary)" }}>
              {data().policy?.mutationRule || "ledger -> confirm -> run -> readback"}
            </span>
          </div>
        </div>
        <div style={{ display: "flex", gap: "var(--space-2)", "flex-wrap": "wrap", "justify-content": "flex-end" }}>
          <OpsButton onClick={() => navigate("/projects")}>bridge</OpsButton>
          <OpsButton onClick={() => navigate("/projects/os")}>project os</OpsButton>
          <OpsButton onClick={() => refetch()}>refresh</OpsButton>
        </div>
      </div>

      <Show when={data().schema} fallback={<GlassPanel><Skeleton lines={8} /></GlassPanel>}>
        <GlassPanel elevated truth={data().status === "green" ? "observed" : "remembered"} style={{ "margin-bottom": "var(--space-4)" }}>
          <div style={{ display: "grid", "grid-template-columns": "repeat(auto-fit, minmax(120px, 1fr))", gap: "var(--space-4)" }}>
            <Metric label="nodes" value={`${lanes().kubernetes?.counts?.ready || 0}/${lanes().kubernetes?.counts?.nodes || 0}`} color={statusColor(lanes().kubernetes?.status)} large />
            <Metric label="gpus" value={`${lanes().kubernetes?.counts?.gpuAllocatable || 0}/${lanes().kubernetes?.counts?.gpuCapacity || 0}`} color="var(--truth-observed)" large />
            <Metric label="slurm" value={valueOf(lanes().slurm?.status)} color={statusColor(lanes().slurm?.status)} large />
            <Metric label="orangefs" value={valueOf(lanes().orangefs?.risk || lanes().orangefs?.status)} color={statusColor(lanes().orangefs?.risk || lanes().orangefs?.status)} large />
            <Metric label="thin pool" value={lanes().orangefs?.thinPoolPct === null || lanes().orangefs?.thinPoolPct === undefined ? "unknown" : `${Number(lanes().orangefs.thinPoolPct).toFixed(1)}%`} color={statusColor(lanes().orangefs?.risk)} large />
            <Metric label="host ssh" value={valueOf(lanes().hosts?.status)} color={statusColor(lanes().hosts?.status)} large />
            <Metric label="risks" value={risks().length} color={risks().length ? "var(--posture-warm)" : "var(--truth-observed)"} large />
          </div>
        </GlassPanel>

        <div style={{ display: "grid", "grid-template-columns": "minmax(0, 1.35fr) minmax(320px, 0.65fr)", gap: "var(--space-4)", "align-items": "start" }}>
          <div style={{ display: "flex", "flex-direction": "column", gap: "var(--space-4)" }}>
            <GlassPanel truth={lanes().orangefs?.risk === "red" ? "stale" : "observed"}>
              <SectionTitle status={lanes().orangefs?.risk}>OrangeFS 5860 Ceiling</SectionTitle>
              <div style={{ display: "grid", "grid-template-columns": "repeat(auto-fit, minmax(180px, 1fr))", gap: "var(--space-4)", "margin-bottom": "var(--space-3)" }}>
                <Metric label="thin pool" value={lanes().orangefs?.thinPoolPct === null || lanes().orangefs?.thinPoolPct === undefined ? "unknown" : `${Number(lanes().orangefs.thinPoolPct).toFixed(2)}%`} color={statusColor(lanes().orangefs?.risk)} />
                <Metric label="worker mounts" value={(lanes().orangefs?.workerMounts || []).filter((mount) => mount.mounted).length} color="var(--truth-observed)" />
                <Metric label="status" value={valueOf(lanes().orangefs?.status)} color={statusColor(lanes().orangefs?.status)} />
              </div>
              <div style={{ "font-family": "var(--font-data)", "font-size": "var(--text-xs)", color: "var(--text-tertiary)", "line-height": 1.45 }}>
                {lanes().orangefs?.capacityNote}
              </div>
              <div style={{ display: "flex", "flex-direction": "column", gap: "var(--space-2)", "margin-top": "var(--space-3)" }}>
                <For each={lanes().orangefs?.workerMounts || []}>
                  {(mount) => (
                    <div style={{ "font-family": "var(--font-data)", "font-size": "var(--text-xs)", color: mount.mounted ? "var(--truth-observed)" : "var(--state-error)", "word-break": "break-word" }}>
                      {mount.node}: {mount.mounted ? "mounted" : "not mounted"} · {valueOf(mount.df)}
                    </div>
                  )}
                </For>
              </div>
            </GlassPanel>

            <GlassPanel truth={lanes().kubernetes?.status === "healthy" ? "observed" : "remembered"}>
              <SectionTitle status={lanes().kubernetes?.status}>Kubernetes Nodes</SectionTitle>
              <NodeTable nodes={nodes()} />
            </GlassPanel>

            <GlassPanel truth={lanes().slurm?.status === "healthy" ? "observed" : "remembered"}>
              <SectionTitle status={lanes().slurm?.status}>Slurm Lane</SectionTitle>
              <div style={{ display: "grid", "grid-template-columns": "repeat(auto-fit, minmax(180px, 1fr))", gap: "var(--space-3)" }}>
                <For each={lanes().slurm?.partitions || []}>
                  {(partition) => (
                    <div style={{ "font-family": "var(--font-data)", "font-size": "var(--text-xs)", color: "var(--text-data)", padding: "var(--space-2)", background: "rgba(255,255,255,0.03)", "border-radius": "var(--radius-sm)" }}>
                      <div style={{ color: "var(--text-primary)", "margin-bottom": "var(--space-1)" }}>{partition.partition}</div>
                      <div>{partition.state} · {partition.nodes} node(s)</div>
                      <div style={{ color: "var(--text-tertiary)", "word-break": "break-word" }}>{partition.nodeList}</div>
                    </div>
                  )}
                </For>
              </div>
              <Show when={lanes().slurm?.recentJobs?.length}>
                <div style={{ "margin-top": "var(--space-3)", "font-family": "var(--font-data)", "font-size": "var(--text-xs)", color: "var(--text-tertiary)", "line-height": 1.45 }}>
                  recent jobs: {lanes().slurm.recentJobs.slice(0, 4).map((job) => `${job.jobId}:${job.state}`).join("  ")}
                </div>
              </Show>
            </GlassPanel>
          </div>

          <div style={{ display: "flex", "flex-direction": "column", gap: "var(--space-4)" }}>
            <GlassPanel truth={risks().length ? "remembered" : "observed"}>
              <SectionTitle status={risks().length ? `${risks().length} active` : "clean"}>Risks</SectionTitle>
              <Show when={risks().length} fallback={<div style={{ "font-family": "var(--font-data)", "font-size": "var(--text-sm)", color: "var(--truth-observed)" }}>clean</div>}>
                <div style={{ display: "flex", "flex-direction": "column", gap: "var(--space-2)" }}>
                  <For each={risks()}>
                    {(risk) => (
                      <div style={{ "font-family": "var(--font-data)", "font-size": "var(--text-xs)", color: statusColor(risk.severity), "line-height": 1.45 }}>
                        {risk.severity} · {risk.layer} · {risk.code}: {risk.summary}
                      </div>
                    )}
                  </For>
                </div>
              </Show>
            </GlassPanel>

            <GlassPanel truth={lanes().kubernetes?.cilium?.status || "declared"}>
              <SectionTitle status={lanes().kubernetes?.cilium?.status}>Cilium</SectionTitle>
              <div style={{ display: "flex", "flex-direction": "column", gap: "var(--space-2)" }}>
                <Metric label="agent" value={valueOf(lanes().kubernetes?.cilium?.version)} />
                <Metric label="envoy" value={valueOf(lanes().kubernetes?.cilium?.envoyImage)} />
                <Metric label="kpr" value={valueOf(lanes().kubernetes?.cilium?.kubeProxyReplacement)} />
                <Metric label="routing" value={valueOf(lanes().kubernetes?.cilium?.routingMode)} />
              </div>
            </GlassPanel>

            <GlassPanel truth={lanes().hosts?.status === "observed" ? "observed" : "remembered"}>
              <SectionTitle status={lanes().hosts?.status}>Host Freshness</SectionTitle>
              <div style={{ display: "flex", "flex-direction": "column", gap: "var(--space-2)" }}>
                <For each={lanes().hosts?.entries || []}>
                  {(entry) => (
                    <div style={{ "font-family": "var(--font-data)", "font-size": "var(--text-xs)", color: statusColor(entry.status), "line-height": 1.45 }}>
                      {entry.node}: {entry.status} · apt {entry.aptUpgradable ?? "blocked"} · reboot {entry.rebootRequired}
                    </div>
                  )}
                </For>
              </div>
            </GlassPanel>

            <GlassPanel truth="declared">
              <SectionTitle status={`${actions().length} actions`}>Action Lane</SectionTitle>
              <Show when={workerTargets().length}>
                <label style={{ display: "flex", "align-items": "center", "justify-content": "space-between", gap: "var(--space-3)", "margin-bottom": "var(--space-3)", "font-family": "var(--font-data)", "font-size": "var(--text-xs)", color: "var(--text-tertiary)" }}>
                  target
                  <select
                    value={targetNode()}
                    onChange={(event) => setTargetNode(event.currentTarget.value)}
                    style={{
                      flex: 1,
                      "max-width": "190px",
                      padding: "var(--space-2)",
                      background: "rgba(255,255,255,0.04)",
                      border: "1px solid var(--glass-border)",
                      "border-radius": "var(--radius-sm)",
                      color: "var(--text-primary)",
                      "font-family": "var(--font-data)",
                      "font-size": "var(--text-xs)",
                    }}
                  >
                    <For each={workerTargets()}>
                      {(node) => <option value={node}>{node}</option>}
                    </For>
                  </select>
                </label>
              </Show>
              <div style={{ display: "flex", "flex-direction": "column", gap: "var(--space-2)" }}>
                <For each={actions()}>
                  {(item) => (
                    <div style={{ display: "grid", "grid-template-columns": "minmax(0, 1fr) auto", gap: "var(--space-2)", "align-items": "center", padding: "var(--space-2)", background: "rgba(255,255,255,0.03)", "border-radius": "var(--radius-sm)" }}>
                      <div style={{ "min-width": 0 }}>
                        <div style={{ display: "flex", "justify-content": "space-between", gap: "var(--space-2)", "font-family": "var(--font-data)", "font-size": "var(--text-xs)", color: "var(--text-data)" }}>
                          <span>{item.label}</span>
                          <span style={{ color: statusColor(item.risk) }}>{item.risk}</span>
                        </div>
                        <div style={{ "font-family": "var(--font-data)", "font-size": "var(--text-xs)", color: "var(--text-tertiary)", "line-height": 1.35, "margin-top": "var(--space-1)" }}>
                          {item.summary}
                        </div>
                      </div>
                      <OpsButton
                        danger={["high", "critical"].includes(item.risk)}
                        disabled={mutation()?.state === "running" || (item.requiresTarget && !targetNode())}
                        onClick={() => runClusterAction(item)}
                      >
                        run
                      </OpsButton>
                    </div>
                  )}
                </For>
              </div>
            </GlassPanel>
          </div>
        </div>

        <ResultPanel result={mutation()} />

        <Show when={gpuNodes().length}>
          <GlassPanel truth="observed" style={{ "margin-top": "var(--space-4)" }}>
            <SectionTitle status={`${gpuNodes().length} nodes`}>GPU Placement</SectionTitle>
            <div style={{ display: "grid", "grid-template-columns": "repeat(auto-fit, minmax(210px, 1fr))", gap: "var(--space-3)" }}>
              <For each={gpuNodes()}>
                {(node) => (
                  <div style={{ "font-family": "var(--font-data)", "font-size": "var(--text-xs)", color: "var(--text-data)", padding: "var(--space-2)", background: "rgba(255,255,255,0.03)", "border-radius": "var(--radius-sm)" }}>
                    <div style={{ color: "var(--text-primary)", "margin-bottom": "var(--space-1)" }}>{node.name}</div>
                    <div>{valueOf(node.gpu?.accelerator || node.gpu?.acceleratorClass)}</div>
                    <div style={{ color: "var(--text-tertiary)" }}>gpu {node.gpu?.allocatable ?? 0}/{node.gpu?.capacity ?? 0}</div>
                  </div>
                )}
              </For>
            </div>
          </GlassPanel>
        </Show>
      </Show>
    </div>
  );
}
