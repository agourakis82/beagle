/**
 * ProjectShowcase — /public/projects/:slug
 *
 * Project-level public showcase with 3 sub-surfaces:
 * - /public/projects/:slug/sovereign-bridge
 * - /public/projects/:slug/sovereign-cockpit-preview
 * - /public/projects/:slug/packet-graph
 *
 * This is the public project-scoped version of vision surfaces.
 */
import { createResource, Show, For } from "solid-js";
import { useParams, useNavigate } from "@solidjs/router";
import { fetchWithTruth } from "../stores/truth";
import GlassPanel from "../components/GlassPanel";
import TruthBadge from "../components/TruthBadge";
import VisionSurface from "./vision/VisionSurface";

export function ProjectShowcaseIndex() {
  const params = useParams();
  const navigate = useNavigate();
  const [showcase] = createResource(
    () => params.slug,
    (s) => fetchWithTruth(`/api/public/projects/${s}/showcase`, 5000)
  );

  const data = () => showcase()?.data || {};
  const truthMode = () => showcase()?.truthMode || "declared";

  const subRoutes = [
    { slug: "sovereign-bridge",        label: "Sovereign Bridge",        detail: "Cross-platform project continuity" },
    { slug: "sovereign-cockpit-preview", label: "Cockpit Preview",       detail: "Private cockpit preview" },
    { slug: "packet-graph",            label: "Packet Graph",            detail: "Execution packet lineage" },
  ];

  return (
    <div style={{
      position: "relative",
      "z-index": 1,
      padding: "var(--space-6) var(--space-8)",
      "max-width": "1200px",
      margin: "0 auto",
      height: "100%",
      "overflow-y": "auto",
    }}>
      <div style={{ "margin-bottom": "var(--space-6)" }}>
        <div style={{ display: "flex", "align-items": "center", gap: "var(--space-3)", "margin-bottom": "var(--space-2)" }}>
          <button
            onClick={() => navigate("/public")}
            style={{
              padding: "var(--space-1) var(--space-2)",
              background: "rgba(255,255,255,0.04)",
              border: "1px solid var(--glass-border)",
              "border-radius": "var(--radius-sm)",
              color: "var(--text-tertiary)",
              "font-size": "var(--text-xs)",
              cursor: "pointer",
            }}
          >
            ← public portal
          </button>
          <span style={{
            "font-family": "var(--font-data)",
            "font-size": "var(--text-xs)",
            color: "var(--text-tertiary)",
            "letter-spacing": "0.08em",
            "text-transform": "uppercase",
          }}>
            showcase
          </span>
          <TruthBadge mode={truthMode()} />
        </div>
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
        <Show when={data().subtitle}>
          <p style={{ "font-size": "var(--text-sm)", color: "var(--text-secondary)", "margin-top": "var(--space-2)" }}>
            {data().subtitle}
          </p>
        </Show>
      </div>

      <div style={{
        display: "grid",
        "grid-template-columns": "repeat(auto-fill, minmax(260px, 1fr))",
        gap: "var(--space-3)",
      }}>
        <For each={subRoutes}>
          {(sub) => (
            <GlassPanel subtle padding="var(--space-4)" style={{ cursor: "pointer" }}>
              <div onClick={() => navigate(`/public/projects/${params.slug}/${sub.slug}`)}>
                <div style={{
                  "font-family": "var(--font-data)",
                  "font-size": "var(--text-base)",
                  "font-weight": "var(--weight-medium)",
                  color: "var(--text-primary)",
                  "margin-bottom": "var(--space-1)",
                }}>
                  {sub.label}
                </div>
                <div style={{
                  "font-size": "var(--text-xs)",
                  color: "var(--text-tertiary)",
                }}>
                  {sub.detail}
                </div>
              </div>
            </GlassPanel>
          )}
        </For>
      </div>
    </div>
  );
}

// Sub-surface wrappers — reuse VisionSurface pattern
export function ProjectSovereignBridge() {
  const params = useParams();
  return <VisionSurface endpoint={`/api/public/projects/${params.slug}/sovereign-bridge`} fallbackTitle="Sovereign Bridge" />;
}

export function ProjectCockpitPreview() {
  const params = useParams();
  return <VisionSurface endpoint={`/api/public/projects/${params.slug}/sovereign-cockpit-preview`} fallbackTitle="Cockpit Preview" />;
}

export function ProjectPacketGraph() {
  const params = useParams();
  return <VisionSurface endpoint={`/api/public/projects/${params.slug}/packet-graph`} fallbackTitle="Packet Graph" />;
}
