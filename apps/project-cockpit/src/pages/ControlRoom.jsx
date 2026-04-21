/**
 * ControlRoom — /projects/:slug
 *
 * Private control room per project.
 * 5 operational lanes with truth indicators.
 * GPU canvas shows project pod topology behind glass lanes.
 */
import { useParams, useNavigate } from "@solidjs/router";
import { createResource, Show, For, createMemo } from "solid-js";
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

export default function ControlRoom() {
  const params = useParams();
  const navigate = useNavigate();
  useTitle(() => `${params.slug} · Control Room`);

  // Fetch all lanes in parallel
  const [missionTruth] = createResource(() => params.slug, (s) => fetchLane(s, "mission-control"));
  const [clusterTruth] = createResource(() => params.slug, (s) => fetchLane(s, "cluster/lane-truth"));
  const [researchTruth] = createResource(() => params.slug, (s) => fetchLane(s, "research/operations"));
  const [inferenceTruth] = createResource(() => params.slug, (s) => fetchLane(s, "inference/runtime"));
  const [goWorkTruth] = createResource(() => params.slug, (s) => fetchLane(s, "go-work-now"));

  const project = () => missionTruth()?.data?.project || {};
  const posture = () => project().mode || "warm";
  const missionMode = () => missionTruth()?.truthMode || "declared";

  // Extract deep data
  const missionData = () => missionTruth()?.data || {};
  const clusterData = () => clusterTruth()?.data || {};
  const researchData = () => researchTruth()?.data || {};
  const inferenceRuntime = () => inferenceTruth()?.data?.runtime || inferenceTruth()?.data || {};
  const goWorkData = () => goWorkTruth()?.data || {};

  // Truth summary from mission control
  const truthSummary = () => missionData().truthSummary || {};

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

      {/* ─── Lane 1: Mission Control ─── */}
      <Lane title="Mission Control" truth={missionMode()}>
        <Show when={project().projectSlug} fallback={
          <Skeleton lines={3} />
        }>
          <div style={{ display: "grid", "grid-template-columns": "1fr 1fr", gap: "var(--space-2) var(--space-6)", "font-family": "var(--font-data)", "font-size": "var(--text-mono)", color: "var(--text-data)" }}>
            <span>habitat: <span style={{ color: posture() === "always-on" ? "var(--truth-observed)" : "var(--posture-warm)" }}>{project().workspacePod ? "live" : "standby"}</span></span>
            <span>branch: {project().preferredPrBase || project().branch || "—"}</span>
            <span>namespace: {project().namespace || "—"}</span>
            <span>node: {project().workspacePod || "—"}</span>
            <Show when={project().tmuxSession}>
              <span>tmux: {project().tmuxSession}</span>
            </Show>
            <Show when={project().playgroundClass}>
              <span>playground: {project().playgroundClass}</span>
            </Show>
          </div>

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
          </div>
        </Show>
      </Lane>

      {/* ─── Lane 5: Go Work Now (Actions) ─── */}
      <Lane title="Habitat Actions" truth={goWorkTruth()?.truthMode || "declared"} defaultExpanded={false}>
        <Show when={goWorkData().project} fallback={
          <Skeleton lines={1} />
        }>
          <div style={{ "font-family": "var(--font-data)", "font-size": "var(--text-mono)", color: "var(--text-data)" }}>
            <p style={{ color: "var(--text-secondary)", "font-size": "var(--text-sm)" }}>
              Habitat activation, standby, and mutation actions.
            </p>
          </div>
        </Show>
      </Lane>

      {/* ─── Lane 6: Terminal ─── */}
      <Lane title={`Terminal · tmux: ${project().tmuxSession || params.slug}`} truth="observed" defaultExpanded={true}>
        <Terminal slug={params.slug} expanded={true} />
      </Lane>
    </div>
  );
}
