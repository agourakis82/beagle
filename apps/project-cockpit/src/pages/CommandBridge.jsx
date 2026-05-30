/**
 * CommandBridge — /projects
 *
 * The daily entrypoint. A mission board, not a card grid.
 * GPU topology as background. Glass panels floating over it.
 *
 * Layout:
 * - Main column: sovereign surfaces (hero → medium → chips)
 * - Side rail: cluster truth + inference fabric summaries
 *
 * Hero treatment for always-on. Medium for warm. Chips for cold.
 */
import { For, Show, createMemo, createResource, createSignal } from "solid-js";
import { useNavigate } from "@solidjs/router";
import { useCatalog } from "../stores/catalog";
import { fetchWithTruth } from "../stores/truth";
import { useTitle } from "../hooks/useTitle";
import GlassPanel from "../components/GlassPanel";
import PostureIndicator from "../components/PostureIndicator";
import TruthBadge from "../components/TruthBadge";
import Sparkline from "../components/Sparkline";

// Fetch inference runtime for the sidebar summary
async function fetchInferenceSummary() {
  const result = await fetchWithTruth("/api/projects/sounio/inference/runtime", 4000);
  return result;
}

async function fetchCatalogAudit() {
  return fetchWithTruth("/api/catalog/audit", 5000);
}

async function fetchClusterSummary() {
  return fetchWithTruth("/api/cluster/ops/summary", 15000);
}

export default function CommandBridge() {
  useTitle("Command Bridge");
  const { projects, postureCounts, posturePolicy, refetchCatalog } = useCatalog();
  const [inferenceTruth] = createResource(fetchInferenceSummary);
  const [catalogAuditTruth] = createResource(fetchCatalogAudit);
  const [clusterTruth] = createResource(fetchClusterSummary);
  const navigate = useNavigate();
  const [mutation, setMutation] = createSignal(null);

  const grouped = createMemo(() => {
    const all = projects();
    return {
      alwaysOn: all.filter(p => (p.mode || p.posture) === "always-on"),
      warm: all.filter(p => (p.mode || p.posture) === "warm"),
      cold: all.filter(p => (p.mode || p.posture) === "cold"),
    };
  });

  const inferenceData = () => {
    const t = inferenceTruth();
    if (!t || !t.data) return null;
    return t.data.runtime || t.data;
  };
  const catalogAudit = () => catalogAuditTruth()?.data || {};
  const catalogStatus = () => catalogAudit().status || "loading";
  const catalogStatusColor = () =>
    catalogStatus() === "ok"
      ? "var(--truth-observed)"
      : catalogStatus() === "warn"
        ? "var(--posture-warm)"
        : catalogStatus() === "loading"
          ? "var(--text-tertiary)"
          : "var(--state-error)";
  const clusterData = () => clusterTruth()?.data || {};
  const clusterStatusColor = () => {
    const status = String(clusterData().status || clusterTruth()?.truthMode || "").toLowerCase();
    if (status.includes("red") || status.includes("stale")) return "var(--state-error)";
    if (status.includes("yellow") || status.includes("remembered")) return "var(--posture-warm)";
    if (status.includes("green") || status.includes("observed")) return "var(--truth-observed)";
    return "var(--text-tertiary)";
  };

  const slug = (p) => p.projectSlug || p.slug;

  async function postProjectAction(project, actionId) {
    const projectSlug = slug(project);
    const requestId = crypto?.randomUUID ? crypto.randomUUID() : `${Date.now()}-${Math.random()}`;
    setMutation({ projectSlug, actionId, state: "running" });
    try {
      const res = await fetch(`/api/projects/${projectSlug}/go-work-now/actions/${actionId}`, {
        method: "POST",
        headers: {
          "Content-Type": "application/json",
          "X-Request-ID": requestId,
        },
        body: JSON.stringify({ confirmed: true, idempotencyKey: requestId }),
        signal: AbortSignal.timeout(300000),
      });
      const payload = await res.json().catch(() => ({}));
      if (!res.ok) throw new Error(payload?.error?.message || payload?.error || `${res.status}`);
      setMutation({ projectSlug, actionId, state: "done" });
      refetchCatalog();
    } catch (error) {
      setMutation({ projectSlug, actionId, state: "error", output: error.message });
    }
  }

  function projectSummary(project) {
    const packet = project.goWorkNow || {};
    const workspace = packet.workspaceState || project.workspace || {};
    return {
      workspaceState: workspace.status || workspace.phase || (project.mode === "always-on" ? "expected-live" : "standby"),
      entry: packet.primaryEntry || packet.entrypoint || (slug(project) === "sounio" ? "sounio dev" : `dev ${slug(project)}`),
      branch: project.preferredPrBase || project.branch || project.workspaceBootstrapBranch || "main",
    };
  }

  const isLive = (project) => projectSummary(project).workspaceState === "live";

  return (
    <div class="command-bridge" style={{
      position: "relative",
      "z-index": 1,
      padding: "var(--space-6) var(--space-8)",
      "max-width": "1280px",
      margin: "0 auto",
      height: "100%",
      "overflow-y": "auto",
      display: "grid",
      "grid-template-columns": "1fr 280px",
      "grid-template-rows": "auto 1fr",
      gap: "var(--space-6)",
      "align-content": "start",
    }}>
      {/* ─── Header (spans full width) ─── */}
      <div style={{
        "grid-column": "1 / -1",
        display: "flex",
        "align-items": "baseline",
        "justify-content": "space-between",
      }}>
        <div>
          <h1 style={{
            "font-family": "var(--font-display)",
            "font-size": "var(--text-2xl)",
            "font-weight": "var(--weight-semibold)",
            color: "var(--text-primary)",
            "letter-spacing": "-0.02em",
          }}>
            Darwin Project Cockpit
          </h1>
          <p style={{
            "font-size": "var(--text-sm)",
            color: "var(--text-tertiary)",
            "margin-top": "var(--space-1)",
          }}>
            GUI-first control · {postureCounts().totalProjects || "—"} projects
          </p>
        </div>
        <Show when={postureCounts().totalProjects}>
          <div style={{
            display: "flex",
            gap: "var(--space-4)",
            "font-family": "var(--font-data)",
            "font-size": "var(--text-xs)",
            color: "var(--text-secondary)",
            "align-items": "center",
          }}>
            <span><span style={{ color: catalogStatusColor() }}>●</span> audit {catalogStatus()}</span>
            <span><span style={{ color: "var(--posture-on)" }}>{postureCounts().alwaysOn}</span> on</span>
            <span><span style={{ color: "var(--posture-warm)" }}>{postureCounts().warm}</span> warm</span>
            <span><span style={{ color: "var(--posture-cold)" }}>{postureCounts().cold}</span> cold</span>
            <button
              onClick={() => navigate("/projects/os")}
              style={{
                padding: "var(--space-1) var(--space-2)",
                background: "rgba(81, 214, 189, 0.10)",
                border: "1px solid rgba(81, 214, 189, 0.24)",
                "border-radius": "var(--radius-sm)",
                color: "var(--truth-observed)",
                "font-family": "var(--font-data)",
                "font-size": "var(--text-xs)",
              }}
            >
              project os
            </button>
            <button
              onClick={() => navigate("/projects/cluster")}
              style={{
                padding: "var(--space-1) var(--space-2)",
                background: "rgba(255, 255, 255, 0.04)",
                border: "1px solid var(--glass-border)",
                "border-radius": "var(--radius-sm)",
                color: "var(--text-secondary)",
                "font-family": "var(--font-data)",
                "font-size": "var(--text-xs)",
              }}
            >
              cluster
            </button>
          </div>
        </Show>
      </div>

      {/* ─── Main column: Sovereign surfaces ─── */}
      <div>
        {/* Always-on projects — hero treatment */}
        <For each={grouped().alwaysOn}>
          {(project) => (
            <GlassPanel elevated class="truth-pulse" truth="observed" style={{ "margin-bottom": "var(--space-4)" }}>
              <div style={{ display: "flex", "align-items": "flex-start", "justify-content": "space-between" }}>
                <div>
                  <div style={{ display: "flex", "align-items": "center", gap: "var(--space-3)", "margin-bottom": "var(--space-2)" }}>
                    <h2 style={{
                      "font-family": "var(--font-display)",
                      "font-size": "var(--text-xl)",
                      "font-weight": "var(--weight-semibold)",
                      color: "var(--text-primary)",
                      "text-transform": "uppercase",
                      "letter-spacing": "0.04em",
                    }}>
                      {slug(project)}
                    </h2>
                    <PostureIndicator mode="always-on" />
                  </div>
                  <p style={{ "font-size": "var(--text-sm)", color: "var(--text-secondary)" }}>
                    {slug(project) === "sounio" ? "PL lane · sounio dev remains canonical" : "continuous project cockpit"}
                  </p>
                </div>
                <TruthBadge mode="observed" />
              </div>

              {/* Quick stats */}
              <div style={{
                display: "grid",
                "grid-template-columns": "repeat(auto-fit, minmax(160px, 1fr))",
                gap: "var(--space-3) var(--space-6)",
                "margin-top": "var(--space-4)",
                "font-family": "var(--font-data)",
                "font-size": "var(--text-mono)",
                color: "var(--text-data)",
              }}>
                <span>workspace: <span style={{ color: "var(--truth-observed)" }}>{projectSummary(project).workspaceState}</span></span>
                <span>entry: <span style={{ opacity: 0.8 }}>{projectSummary(project).entry}</span></span>
                <span>branch: <span style={{ opacity: 0.8 }}>{projectSummary(project).branch}</span></span>
                <Show when={project.workspaceBootstrapBranch && project.workspaceBootstrapBranch !== (project.preferredPrBase || project.branch || "main")}>
                  <span>boot: <span style={{ opacity: 0.8 }}>{project.workspaceBootstrapBranch}</span></span>
                </Show>
                <Show when={project.playgroundClass}>
                  <span>playground: <span style={{ opacity: 0.8 }}>{project.playgroundClass}</span></span>
                </Show>
                <Show when={project.namespace}>
                  <span>ns: <span style={{ opacity: 0.8 }}>{project.namespace}</span></span>
                </Show>
              </div>

              {/* Actions */}
              <div style={{
                display: "flex",
                gap: "var(--space-3)",
                "margin-top": "var(--space-5)",
              }}>
                <button
                  onClick={() => navigate(`/projects/${slug(project)}/control`)}
                  style={{
                    padding: "var(--space-2) var(--space-4)",
                    background: "rgba(81, 214, 189, 0.12)",
                    border: "1px solid rgba(81, 214, 189, 0.25)",
                    "border-radius": "var(--radius-sm)",
                    color: "var(--truth-observed)",
                    "font-family": "var(--font-data)",
                    "font-size": "var(--text-sm)",
                    transition: `background var(--duration-fast) var(--ease-out)`,
                  }}
                >
                  control
                </button>
                <button
                  onClick={() => navigate(`/projects/${slug(project)}/viewer`)}
                  style={{
                    padding: "var(--space-2) var(--space-4)",
                    background: "rgba(255, 255, 255, 0.04)",
                    border: "1px solid var(--glass-border)",
                    "border-radius": "var(--radius-sm)",
                    color: "var(--text-secondary)",
                    "font-family": "var(--font-data)",
                    "font-size": "var(--text-sm)",
                  }}
                >
                  viewer
                </button>
                <button
                  onClick={() => navigate(`/projects/${slug(project)}`)}
                  style={{
                    padding: "var(--space-2) var(--space-4)",
                    background: "rgba(255, 255, 255, 0.04)",
                    border: "1px solid var(--glass-border)",
                    "border-radius": "var(--radius-sm)",
                    color: "var(--text-secondary)",
                    "font-family": "var(--font-data)",
                    "font-size": "var(--text-sm)",
                  }}
                >
                  full control
                </button>
              </div>
            </GlassPanel>
          )}
        </For>

        {/* Warm projects — medium cards */}
        <Show when={grouped().warm.length > 0}>
          <div style={{
            display: "grid",
            "grid-template-columns": "repeat(auto-fill, minmax(240px, 1fr))",
            gap: "var(--space-3)",
            "margin-bottom": "var(--space-4)",
          }}>
            <For each={grouped().warm}>
              {(project) => (
                <GlassPanel
                  style={{ cursor: "pointer", padding: "var(--space-4)" }}
                  truth={isLive(project) ? "observed" : "declared"}
                >
                  <div onClick={() => navigate(`/projects/${slug(project)}`)}>
                    <div style={{ display: "flex", "align-items": "center", gap: "var(--space-2)", "margin-bottom": "var(--space-2)" }}>
                      <span style={{ color: isLive(project) ? "var(--truth-observed)" : "var(--text-tertiary)", "font-size": "var(--text-xs)" }}>●</span>
                      <h3 style={{
                        "font-family": "var(--font-display)",
                        "font-size": "var(--text-base)",
                        "font-weight": "var(--weight-medium)",
                        color: "var(--text-primary)",
                      }}>
                        {slug(project)}
                      </h3>
                      <PostureIndicator mode="warm" size="sm" showLabel={false} />
                    </div>
                    <p style={{ "font-size": "var(--text-xs)", color: "var(--text-tertiary)" }}>
                      {projectSummary(project).workspaceState} · {project.namespace || "beagle"} · {projectSummary(project).entry}
                    </p>
                    <div style={{ display: "flex", gap: "var(--space-2)", "margin-top": "var(--space-3)", "flex-wrap": "wrap" }}>
                      <button
                        onClick={(event) => {
                          event.stopPropagation();
                          navigate(`/projects/${slug(project)}/control`);
                        }}
                        style={{
                          padding: "var(--space-1) var(--space-2)",
                          background: "rgba(81, 214, 189, 0.10)",
                          border: "1px solid rgba(81, 214, 189, 0.24)",
                          "border-radius": "var(--radius-sm)",
                          color: "var(--truth-observed)",
                          "font-family": "var(--font-data)",
                          "font-size": "var(--text-xs)",
                        }}
                      >
                        control
                      </button>
                      <button
                        onClick={(event) => {
                          event.stopPropagation();
                          postProjectAction(project, isLive(project) ? "standby-habitat" : "activate-habitat");
                        }}
                        style={{
                          padding: "var(--space-1) var(--space-2)",
                          background: "rgba(255, 255, 255, 0.04)",
                          border: "1px solid var(--glass-border)",
                          "border-radius": "var(--radius-sm)",
                          color: "var(--text-secondary)",
                          "font-family": "var(--font-data)",
                          "font-size": "var(--text-xs)",
                        }}
                      >
                        {isLive(project) ? "standby" : "activate"}
                      </button>
                    </div>
                  </div>
                </GlassPanel>
              )}
            </For>
          </div>
        </Show>

        {/* Cold projects — chip row */}
        <Show when={grouped().cold.length > 0}>
          <div style={{
            display: "flex",
            gap: "var(--space-2)",
            "flex-wrap": "wrap",
            "margin-top": "var(--space-2)",
          }}>
            <For each={grouped().cold}>
              {(project) => (
                <span
                  style={{
                    display: "inline-flex",
                    "align-items": "center",
                    gap: "var(--space-1)",
                    padding: "var(--space-1) var(--space-3)",
                    background: "rgba(255, 255, 255, 0.03)",
                    border: "1px dotted var(--truth-declared)",
                    "border-radius": "var(--radius-sm)",
                    "font-family": "var(--font-data)",
                    "font-size": "var(--text-xs)",
                    color: "var(--text-tertiary)",
                    cursor: "pointer",
                  }}
                  onClick={() => navigate(`/projects/${slug(project)}`)}
                >
                  <PostureIndicator mode="cold" size="sm" showLabel={false} />
                  {slug(project)}
                </span>
              )}
            </For>
          </div>
        </Show>

        <Show when={mutation()}>
          <GlassPanel subtle padding="var(--space-3)" truth={mutation().state === "error" ? "stale" : mutation().state === "done" ? "observed" : "remembered"}>
            <div style={{ "font-family": "var(--font-data)", "font-size": "var(--text-xs)", color: mutation().state === "error" ? "var(--state-error)" : "var(--text-data)" }}>
              {mutation().projectSlug} · {mutation().actionId}: {mutation().state}{mutation().output ? ` · ${mutation().output}` : ""}
            </div>
          </GlassPanel>
        </Show>
      </div>

      {/* ─── Side rail: Cluster + Inference + Posture ─── */}
      <div style={{ display: "flex", "flex-direction": "column", gap: "var(--space-3)" }}>
        {/* Posture Policy */}
        <GlassPanel subtle padding="var(--space-4)">
          <h4 style={{
            "font-family": "var(--font-ui)",
            "font-size": "var(--text-xs)",
            "font-weight": "var(--weight-semibold)",
            "text-transform": "uppercase",
            "letter-spacing": "0.08em",
            color: "var(--text-tertiary)",
            "margin-bottom": "var(--space-3)",
          }}>
            Posture Policy
          </h4>
          <Show when={posturePolicy()} fallback={<span style={{ color: "var(--text-tertiary)", "font-size": "var(--text-xs)" }}>loading...</span>}>
            <div style={{ "font-family": "var(--font-data)", "font-size": "var(--text-xs)", color: "var(--text-secondary)", display: "flex", "flex-direction": "column", gap: "var(--space-2)" }}>
              <For each={posturePolicy()?.postureDefinitions || []}>
                {(def) => (
                  <div style={{ display: "flex", gap: "var(--space-2)", "align-items": "baseline" }}>
                    <PostureIndicator mode={def.name} size="sm" showLabel={false} />
                    <div>
                      <span style={{ color: "var(--text-primary)" }}>{def.name}</span>
                      <span style={{ color: "var(--text-tertiary)", "margin-left": "var(--space-2)" }}>{def.summary}</span>
                    </div>
                  </div>
                )}
              </For>
            </div>
          </Show>
        </GlassPanel>

        {/* Inference Fabric */}
        <GlassPanel subtle padding="var(--space-4)" truth={inferenceTruth()?.truthMode || "declared"}>
          <div style={{ display: "flex", "align-items": "center", "justify-content": "space-between", "margin-bottom": "var(--space-3)" }}>
            <h4 style={{
              "font-family": "var(--font-ui)",
              "font-size": "var(--text-xs)",
              "font-weight": "var(--weight-semibold)",
              "text-transform": "uppercase",
              "letter-spacing": "0.08em",
              color: "var(--text-tertiary)",
            }}>
              Inference Fabric
            </h4>
            <TruthBadge mode={inferenceTruth()?.truthMode || "declared"} />
          </div>
          <Show when={inferenceData()} fallback={<span style={{ color: "var(--text-tertiary)", "font-size": "var(--text-xs)" }}>loading...</span>}>
            <div style={{ "font-family": "var(--font-data)", "font-size": "var(--text-xs)", color: "var(--text-data)", display: "flex", "flex-direction": "column", gap: "var(--space-2)" }}>
              <div style={{ display: "flex", "align-items": "center", gap: "var(--space-2)" }}>
                <span style={{ color: inferenceData()?.controlPlane?.status === "ready" ? "var(--truth-observed)" : "var(--truth-stale)" }}>●</span>
                <span>Dynamo {inferenceData()?.controlPlane?.status || "—"}</span>
              </div>
              <div style={{ display: "flex", "align-items": "center", gap: "var(--space-2)" }}>
                <span style={{ color: inferenceData()?.engine?.status?.includes("published") ? "var(--truth-observed)" : "var(--truth-stale)" }}>●</span>
                <span>SGLang {inferenceData()?.engine?.status || "—"}</span>
              </div>
              <Show when={inferenceData()?.models?.length}>
                <div style={{ color: "var(--text-secondary)", "margin-top": "var(--space-1)" }}>
                  {inferenceData().models.length} model{inferenceData().models.length > 1 ? "s" : ""} serving
                </div>
              </Show>
            </div>
          </Show>
        </GlassPanel>

        {/* Catalog Audit */}
        <GlassPanel subtle padding="var(--space-4)" truth={catalogAuditTruth()?.truthMode || "declared"}>
          <div style={{ display: "flex", "align-items": "center", "justify-content": "space-between", "margin-bottom": "var(--space-3)" }}>
            <h4 style={{
              "font-family": "var(--font-ui)",
              "font-size": "var(--text-xs)",
              "font-weight": "var(--weight-semibold)",
              "text-transform": "uppercase",
              "letter-spacing": "0.08em",
              color: "var(--text-tertiary)",
            }}>
              Catalog Audit
            </h4>
            <TruthBadge mode={catalogAuditTruth()?.truthMode || "declared"} />
          </div>
          <Show when={catalogAudit().status} fallback={<span style={{ color: "var(--text-tertiary)", "font-size": "var(--text-xs)" }}>loading...</span>}>
            <div style={{ "font-family": "var(--font-data)", "font-size": "var(--text-xs)", color: "var(--text-data)", display: "flex", "flex-direction": "column", gap: "var(--space-2)" }}>
              <div>
                <span style={{ color: catalogAudit().status === "ok" ? "var(--truth-observed)" : catalogAudit().status === "warn" ? "var(--posture-warm)" : "var(--state-error)" }}>●</span>
                {" "}{catalogAudit().status} · {catalogAudit().counts?.findings || 0} finding{catalogAudit().counts?.findings === 1 ? "" : "s"}
              </div>
              <For each={(catalogAudit().findings || []).slice(0, 4)}>
                {(finding) => (
                  <div style={{ color: finding.severity === "fail" ? "var(--state-error)" : finding.severity === "warn" ? "var(--posture-warm)" : "var(--text-tertiary)" }}>
                    {finding.projectSlug}: {finding.code}
                  </div>
                )}
              </For>
            </div>
          </Show>
        </GlassPanel>

        {/* Cluster */}
        <GlassPanel subtle padding="var(--space-4)" truth={clusterTruth()?.truthMode || "declared"}>
          <div style={{ display: "flex", "align-items": "center", "justify-content": "space-between", "margin-bottom": "var(--space-3)" }}>
            <h4 style={{
              "font-family": "var(--font-ui)",
              "font-size": "var(--text-xs)",
              "font-weight": "var(--weight-semibold)",
              "text-transform": "uppercase",
              "letter-spacing": "0.08em",
              color: "var(--text-tertiary)",
            }}>
              Cluster
            </h4>
            <TruthBadge mode={clusterTruth()?.truthMode || "declared"} />
          </div>
          <Show when={clusterData().schema} fallback={<span style={{ color: "var(--text-tertiary)", "font-size": "var(--text-xs)" }}>loading...</span>}>
            <div style={{ "font-family": "var(--font-data)", "font-size": "var(--text-xs)", color: "var(--text-data)", display: "flex", "flex-direction": "column", gap: "var(--space-2)" }}>
              <div>
                <span style={{ color: clusterStatusColor() }}>●</span> {clusterData().status}
                <span style={{ color: "var(--text-tertiary)", "margin-left": "var(--space-2)" }}>{clusterData().risks?.length || 0} risk(s)</span>
              </div>
              <div>
                nodes {clusterData().lanes?.kubernetes?.counts?.ready || 0}/{clusterData().lanes?.kubernetes?.counts?.nodes || 0}
                <span style={{ color: "var(--text-tertiary)", "margin-left": "var(--space-2)" }}>gpu {clusterData().lanes?.kubernetes?.counts?.gpuAllocatable || 0}/{clusterData().lanes?.kubernetes?.counts?.gpuCapacity || 0}</span>
              </div>
              <div>
                slurm <span style={{ color: clusterData().lanes?.slurm?.status === "healthy" ? "var(--truth-observed)" : "var(--posture-warm)" }}>{clusterData().lanes?.slurm?.status || "-"}</span>
              </div>
              <div>
                orangefs <span style={{ color: clusterStatusColor() }}>{clusterData().lanes?.orangefs?.risk || "-"}</span>
                <span style={{ color: "var(--text-tertiary)", "margin-left": "var(--space-2)" }}>{clusterData().lanes?.orangefs?.thinPoolPct == null ? "thin unknown" : `${Number(clusterData().lanes.orangefs.thinPoolPct).toFixed(1)}%`}</span>
              </div>
              <button
                onClick={() => navigate("/projects/cluster")}
                style={{
                  "align-self": "flex-start",
                  padding: "var(--space-1) var(--space-2)",
                  background: "rgba(81, 214, 189, 0.10)",
                  border: "1px solid rgba(81, 214, 189, 0.24)",
                  "border-radius": "var(--radius-sm)",
                  color: "var(--truth-observed)",
                  "font-family": "var(--font-data)",
                  "font-size": "var(--text-xs)",
                  "margin-top": "var(--space-1)",
                }}
              >
                open ops
              </button>
            </div>
          </Show>
        </GlassPanel>
      </div>
    </div>
  );
}
