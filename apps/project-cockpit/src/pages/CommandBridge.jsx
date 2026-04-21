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
import { For, Show, createMemo, createResource } from "solid-js";
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

export default function CommandBridge() {
  useTitle("Command Bridge");
  const { catalog, projects, postureCounts, posturePolicy } = useCatalog();
  const [inferenceTruth] = createResource(fetchInferenceSummary);
  const navigate = useNavigate();

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

  const slug = (p) => p.projectSlug || p.slug;

  // Generate fake sparkline data (will be replaced with real metrics later)
  const demoSparkline = () => Array.from({ length: 24 }, () => 30 + Math.random() * 50);

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
            Sovereign Surfaces
          </h1>
          <p style={{
            "font-size": "var(--text-sm)",
            color: "var(--text-tertiary)",
            "margin-top": "var(--space-1)",
          }}>
            Command bridge · {postureCounts().totalProjects || "—"} projects
          </p>
        </div>
        <Show when={postureCounts().totalProjects}>
          <div style={{
            display: "flex",
            gap: "var(--space-4)",
            "font-family": "var(--font-data)",
            "font-size": "var(--text-xs)",
            color: "var(--text-secondary)",
          }}>
            <span><span style={{ color: "var(--posture-on)" }}>{postureCounts().alwaysOn}</span> on</span>
            <span><span style={{ color: "var(--posture-warm)" }}>{postureCounts().warm}</span> warm</span>
            <span><span style={{ color: "var(--posture-cold)" }}>{postureCounts().cold}</span> cold</span>
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
                    Sovereign habitat · continuous operations
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
                <span>workspace: <span style={{ color: "var(--truth-observed)" }}>live</span></span>
                <span>branch: <span style={{ opacity: 0.8 }}>{project.preferredPrBase || project.branch || "main"}</span></span>
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
                  onClick={() => navigate(`/projects/${slug(project)}`)}
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
                  enter control room
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
                  terminal
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
                  truth="declared"
                >
                  <div onClick={() => navigate(`/projects/${slug(project)}`)}>
                    <div style={{ display: "flex", "align-items": "center", gap: "var(--space-2)", "margin-bottom": "var(--space-2)" }}>
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
                      standby · {project.namespace || "beagle"}
                    </p>
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

        {/* Cluster (placeholder — will be enriched in Phase 3) */}
        <GlassPanel subtle padding="var(--space-4)" truth="remembered">
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
            <TruthBadge mode="remembered" />
          </div>
          <div style={{ "font-family": "var(--font-data)", "font-size": "var(--text-xs)", color: "var(--text-data)", display: "flex", "flex-direction": "column", gap: "var(--space-2)" }}>
            <div>
              <span style={{ color: "var(--truth-observed)" }}>●</span> r770-proxmox
              <span style={{ color: "var(--text-tertiary)", "margin-left": "var(--space-2)" }}>gpu</span>
            </div>
            <div>
              <span style={{ color: "var(--truth-observed)" }}>●</span> r740-proxmox
              <span style={{ color: "var(--text-tertiary)", "margin-left": "var(--space-2)" }}>gpu</span>
            </div>
            <div>
              <span style={{ color: "var(--truth-declared)" }}>○</span> t560-proxmox
              <span style={{ color: "var(--text-tertiary)", "margin-left": "var(--space-2)" }}>ctrl</span>
            </div>
          </div>
        </GlassPanel>
      </div>
    </div>
  );
}
