/**
 * ScientificViewport — /projects/:slug/viewer
 *
 * Full-viewport WebGPU dataset viewer with visionOS-style ornaments.
 *
 * Layout:
 * - Canvas: 100% viewport, dedicated Three.js scene
 * - Ornaments floating at edges:
 *   - top-left: back nav + project identity
 *   - top-right: renderer state + camera mode
 *   - bottom-left: dataset info + truth
 *   - bottom-right: execution packets
 *   - bottom-center: provenance chain
 */
import { onMount, onCleanup, createResource, Show, For } from "solid-js";
import { useParams, useNavigate } from "@solidjs/router";
import { useTitle } from "../hooks/useTitle";
import { initViewerScene, resizeViewer, destroyViewerScene, setCameraMode, updateVolumeFromMetadata } from "../engine/dataset-viewer";
import { fetchWithTruth } from "../stores/truth";
import Ornament from "../components/Ornament";
import TruthBadge from "../components/TruthBadge";
import PostureIndicator from "../components/PostureIndicator";

async function fetchViewerData(slug, path) {
  return fetchWithTruth(`/api/projects/${slug}/${path}`, 6000);
}

export default function ScientificViewport() {
  const params = useParams();
  const navigate = useNavigate();
  useTitle(() => `${params.slug} · Viewer`);
  let canvasRef;

  // Fetch all viewer data in parallel
  const [viewerRuntime] = createResource(() => params.slug, (s) => fetchViewerData(s, "viewer/runtime"));
  const [viewerState] = createResource(() => params.slug, (s) => fetchViewerData(s, "viewer/state"));
  const [datasetCatalog] = createResource(() => params.slug, (s) => fetchViewerData(s, "datasets/catalog"));
  const [executionPackets] = createResource(() => params.slug, (s) => fetchViewerData(s, "execution/packets"));
  const [graphLineage] = createResource(() => params.slug, (s) => fetchViewerData(s, "graph/lineage"));

  // Derived data accessors
  const runtime = () => viewerRuntime()?.data || {};
  const state = () => viewerState()?.data || {};
  const datasets = () => datasetCatalog()?.data?.datasetCatalog || [];
  const packets = () => {
    const d = executionPackets()?.data;
    if (!d) return { count: 0, lanes: {} };
    const pkts = d.packets || {};
    const lanes = {};
    for (const [, pkt] of Object.entries(pkts)) {
      const lane = pkt.lane || "unknown";
      lanes[lane] = (lanes[lane] || 0) + 1;
    }
    return { count: d.packetCount || Object.keys(pkts).length, lanes };
  };
  const lineage = () => graphLineage()?.data || {};

  const rendererStatus = () => runtime().renderer?.status || "unknown";
  const rendererApi = () => runtime().renderer?.runtime?.api || "—";
  const rendererBackend = () => runtime().renderer?.runtime?.backend || "unknown";
  const platforms = () => runtime().runtimeCapabilities || {};

  onMount(async () => {
    if (canvasRef) {
      canvasRef.width = window.innerWidth;
      canvasRef.height = window.innerHeight;
      try {
        await initViewerScene(canvasRef);
      } catch (e) {
        console.warn("[viewer] Scene init failed:", e.message);
      }
    }

    const handleResize = () => {
      if (canvasRef) {
        canvasRef.width = window.innerWidth;
        canvasRef.height = window.innerHeight;
        resizeViewer(window.innerWidth, window.innerHeight);
      }
    };
    window.addEventListener("resize", handleResize);
    onCleanup(() => {
      window.removeEventListener("resize", handleResize);
      destroyViewerScene();
    });
  });

  return (
    <div style={{ position: "relative", width: "100%", height: "100%" }}>
      {/* WebGPU Canvas — full viewport */}
      <canvas
        ref={canvasRef}
        style={{
          position: "absolute",
          top: 0,
          left: 0,
          width: "100%",
          height: "100%",
          "z-index": 0,
        }}
      />

      {/* ─── Ornaments ─── */}

      {/* Top-left: Back nav + project identity */}
      <Ornament position="top-left" compact>
        <div style={{ display: "flex", "align-items": "center", gap: "var(--space-3)" }}>
          <button
            onClick={() => navigate(`/projects/${params.slug}`)}
            style={{
              padding: "var(--space-1) var(--space-2)",
              background: "rgba(255,255,255,0.06)",
              border: "1px solid var(--glass-border)",
              "border-radius": "var(--radius-sm)",
              color: "var(--text-secondary)",
              "font-size": "var(--text-sm)",
              cursor: "pointer",
            }}
          >
            ← control room
          </button>
          <span style={{
            "font-family": "var(--font-display)",
            "font-size": "var(--text-base)",
            "font-weight": "var(--weight-semibold)",
            color: "var(--text-primary)",
            "text-transform": "uppercase",
            "letter-spacing": "0.04em",
          }}>
            {params.slug}
          </span>
        </div>
      </Ornament>

      {/* Top-right: Renderer state + camera */}
      <Ornament position="top-right" title="Renderer" truth={viewerRuntime()?.truthMode || "declared"} compact>
        <div style={{ "font-family": "var(--font-data)", "font-size": "var(--text-xs)", color: "var(--text-data)", display: "flex", "flex-direction": "column", gap: "var(--space-1)" }}>
          <span>status: <span style={{ color: rendererStatus() === "ready" ? "var(--truth-observed)" : "var(--posture-warm)" }}>{rendererStatus()}</span></span>
          <span>api: {rendererApi()}</span>
          <span>backend: {rendererBackend()}</span>
          <Show when={Object.keys(platforms()).length > 0}>
            <div style={{ "margin-top": "var(--space-1)", "border-top": "1px solid var(--glass-border)", "padding-top": "var(--space-1)" }}>
              <For each={Object.entries(platforms())}>
                {([platform, info]) => (
                  <span style={{ display: "block", color: info.status === "ready" ? "var(--truth-observed)" : "var(--text-tertiary)" }}>
                    {platform}: {info.status}
                  </span>
                )}
              </For>
            </div>
          </Show>
        </div>
      </Ornament>

      {/* Bottom-left: Dataset info */}
      <Ornament position="bottom-left" title="Datasets" truth={datasetCatalog()?.truthMode || "declared"} compact>
        <div style={{ "font-family": "var(--font-data)", "font-size": "var(--text-xs)", color: "var(--text-data)" }}>
          <Show when={datasets().length > 0} fallback={
            <span style={{ color: "var(--text-tertiary)" }}>no datasets configured</span>
          }>
            <For each={datasets()}>
              {(ds) => (
                <div style={{ "margin-bottom": "var(--space-1)" }}>
                  <span style={{ color: "var(--text-primary)" }}>{ds.id}</span>
                  <span style={{ color: "var(--text-tertiary)", "margin-left": "var(--space-2)" }}>
                    {ds.kind} · {ds.sourceKind}
                  </span>
                </div>
              )}
            </For>
          </Show>
        </div>
      </Ornament>

      {/* Bottom-right: Execution packets */}
      <Ornament position="bottom-right" title="Execution Packets" truth={executionPackets()?.truthMode || "declared"} compact>
        <div style={{ "font-family": "var(--font-data)", "font-size": "var(--text-xs)", color: "var(--text-data)" }}>
          <div style={{ "font-size": "var(--text-lg)", color: "var(--text-primary)", "margin-bottom": "var(--space-2)" }}>
            {packets().count}
          </div>
          <Show when={Object.keys(packets().lanes).length > 0}>
            <div style={{ display: "flex", "flex-direction": "column", gap: "2px" }}>
              <For each={Object.entries(packets().lanes)}>
                {([lane, count]) => (
                  <span>
                    <span style={{ color: "var(--truth-observed)" }}>{count}</span>
                    {" "}{lane}
                  </span>
                )}
              </For>
            </div>
          </Show>
        </div>
      </Ornament>

      {/* Bottom-center: Provenance chain */}
      <Ornament position="bottom-center" title="Lineage" truth={graphLineage()?.truthMode || "declared"} width="400px" compact>
        <div style={{ "font-family": "var(--font-data)", "font-size": "var(--text-xs)", color: "var(--text-data)", "text-align": "center" }}>
          <Show when={lineage().lineage} fallback={
            <span style={{ color: "var(--text-tertiary)" }}>loading lineage...</span>
          }>
            <span style={{ color: "var(--text-secondary)" }}>
              {params.slug} → viewer → {lineage().depth || "—"} depth
            </span>
          </Show>
        </div>
      </Ornament>
    </div>
  );
}
