/**
 * PublicPortal — /public
 *
 * Entry point for the public vision surfaces.
 * Links to all 9 vision routes + showcase routes.
 */
import { createResource, Show, For } from "solid-js";
import { useNavigate } from "@solidjs/router";
import { fetchWithTruth } from "../stores/truth";
import { useTitle } from "../hooks/useTitle";
import GlassPanel from "../components/GlassPanel";
import TruthBadge from "../components/TruthBadge";

const VISION_ROUTES = [
  { slug: "control-room",      label: "Control Room",     detail: "Spatial mission control" },
  { slug: "apple-brief",       label: "Apple Brief",      detail: "Platform-native briefing" },
  { slug: "apple-launchpad",   label: "Apple Launchpad",  detail: "App + workflow launcher" },
  { slug: "operator-board",    label: "Operator Board",   detail: "Operator dashboard" },
  { slug: "runtime-matrix",    label: "Runtime Matrix",   detail: "Platform capability matrix" },
  { slug: "route-atlas",       label: "Route Atlas",      detail: "Navigation atlas (7 routes)" },
  { slug: "mission-timeline",  label: "Mission Timeline", detail: "Operational phases (7 phases)" },
  { slug: "sovereign-bridge",  label: "Sovereign Bridge", detail: "Cross-platform continuity" },
  { slug: "handoff",           label: "Handoff",          detail: "iPhone ↔ VisionPro handoff" },
];

async function fetchPortal() {
  return fetchWithTruth("/api/public/portal", 4000);
}

export default function PublicPortal() {
  useTitle("Public Portal");
  const navigate = useNavigate();
  const [portal] = createResource(fetchPortal);

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
      {/* Header */}
      <div style={{ "margin-bottom": "var(--space-6)" }}>
        <div style={{ display: "flex", "align-items": "center", gap: "var(--space-3)", "margin-bottom": "var(--space-2)" }}>
          <button
            onClick={() => navigate("/projects")}
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
            ← cockpit
          </button>
          <TruthBadge mode={portal()?.truthMode || "declared"} />
        </div>
        <h1 style={{
          "font-family": "var(--font-display)",
          "font-size": "var(--text-2xl)",
          "font-weight": "var(--weight-semibold)",
          color: "var(--text-primary)",
          "letter-spacing": "-0.02em",
          "margin-bottom": "var(--space-2)",
        }}>
          Public Portal
        </h1>
        <p style={{
          "font-size": "var(--text-sm)",
          color: "var(--text-secondary)",
          "max-width": "640px",
        }}>
          Spatial surfaces for the sovereign supercomputing playground.
          Navigate the 9 Apple Vision routes, designed for visionOS but readable on any shell.
        </p>
      </div>

      {/* Vision routes grid */}
      <h3 style={{
        "font-family": "var(--font-ui)",
        "font-size": "var(--text-xs)",
        "font-weight": "var(--weight-semibold)",
        "text-transform": "uppercase",
        "letter-spacing": "0.08em",
        color: "var(--text-tertiary)",
        "margin-bottom": "var(--space-3)",
      }}>
        Apple Vision · 9 routes
      </h3>

      <div style={{
        display: "grid",
        "grid-template-columns": "repeat(auto-fill, minmax(260px, 1fr))",
        gap: "var(--space-3)",
      }}>
        <For each={VISION_ROUTES}>
          {(route) => (
            <GlassPanel subtle padding="var(--space-4)" style={{ cursor: "pointer" }}>
              <div onClick={() => navigate(`/public/vision/${route.slug}`)}>
                <div style={{
                  "font-family": "var(--font-data)",
                  "font-size": "var(--text-base)",
                  "font-weight": "var(--weight-medium)",
                  color: "var(--text-primary)",
                  "margin-bottom": "var(--space-1)",
                }}>
                  {route.label}
                </div>
                <div style={{
                  "font-size": "var(--text-xs)",
                  color: "var(--text-tertiary)",
                }}>
                  {route.detail}
                </div>
              </div>
            </GlassPanel>
          )}
        </For>
      </div>

      {/* Showcase projects */}
      <h3 style={{
        "font-family": "var(--font-ui)",
        "font-size": "var(--text-xs)",
        "font-weight": "var(--weight-semibold)",
        "text-transform": "uppercase",
        "letter-spacing": "0.08em",
        color: "var(--text-tertiary)",
        "margin-top": "var(--space-8)",
        "margin-bottom": "var(--space-3)",
      }}>
        Project Showcases
      </h3>

      <div style={{
        display: "grid",
        "grid-template-columns": "repeat(auto-fill, minmax(260px, 1fr))",
        gap: "var(--space-3)",
      }}>
        <GlassPanel padding="var(--space-4)" truth="observed" style={{ cursor: "pointer" }}>
          <div onClick={() => navigate("/public/projects/sounio")}>
            <div style={{
              "font-family": "var(--font-display)",
              "font-size": "var(--text-base)",
              "font-weight": "var(--weight-semibold)",
              color: "var(--text-primary)",
              "margin-bottom": "var(--space-1)",
              "text-transform": "uppercase",
              "letter-spacing": "0.04em",
            }}>
              sounio
            </div>
            <div style={{
              "font-size": "var(--text-xs)",
              color: "var(--text-secondary)",
            }}>
              Self-hosted compiler · always-on · epistemic types
            </div>
          </div>
        </GlassPanel>
      </div>
    </div>
  );
}
