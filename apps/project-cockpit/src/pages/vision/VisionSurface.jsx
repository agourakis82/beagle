/**
 * VisionSurface — Shared page template for all 9 public vision endpoints.
 *
 * All vision endpoints share a common shape:
 *   { surface, generatedAt, title, subtitle, route, runtimeVision, ...payload }
 *
 * This component adapts to render lists, stages, timelines, panels, etc.
 * based on what arrays are present in the payload.
 *
 * Spatial layout concepts for future VisionOS:
 * - Header stays pinned top (spatial anchor)
 * - Content uses multi-panel layout (vision is multi-panel-native)
 * - Lists render as horizontal stages/cards (readable in spatial depth)
 */
import { createResource, Show, For, createMemo, createEffect } from "solid-js";
import { useNavigate } from "@solidjs/router";
import { fetchWithTruth } from "../../stores/truth";
import { setTitle } from "../../hooks/useTitle";
import GlassPanel from "../../components/GlassPanel";
import TruthBadge from "../../components/TruthBadge";

/**
 * Detect all array fields in the payload (excluding meta fields).
 * These are the content we render as horizontal/spatial groups.
 */
function extractArrayFields(data) {
  if (!data) return [];
  const skipKeys = new Set(["tags", "metaTags", "handoffChecklist", "launchGates"]);
  const arrays = [];
  for (const [key, value] of Object.entries(data)) {
    if (Array.isArray(value) && value.length > 0 && !skipKeys.has(key)) {
      arrays.push({ key, items: value });
    }
  }
  return arrays;
}

/**
 * Format field key into readable label.
 * atlasRoutes → Atlas Routes; matrixChecks → Matrix Checks
 */
function formatKey(key) {
  return key.replace(/([A-Z])/g, " $1").replace(/^./, c => c.toUpperCase()).trim();
}

/**
 * Pick the "main" field from an item (id, label, title, route).
 */
function itemMainField(item) {
  if (typeof item === "string") return item;
  if (!item || typeof item !== "object") return String(item);
  return item.label || item.title || item.id || item.route || item.stage || item.phase || "—";
}

function itemDetailField(item) {
  if (typeof item === "string") return null;
  if (!item || typeof item !== "object") return null;
  return item.summary || item.detail || item.description || item.route || item.status || null;
}

function itemStatusField(item) {
  if (typeof item !== "object") return null;
  return item.status || null;
}

const STATUS_COLOR = {
  ready: "var(--truth-observed)",
  observed: "var(--truth-observed)",
  active: "var(--truth-observed)",
  starting: "var(--posture-warm)",
  planned: "var(--truth-declared)",
  warm: "var(--posture-warm)",
  cold: "var(--posture-cold)",
  "public-ready": "var(--truth-observed)",
  "showcase-ready": "var(--truth-observed)",
  "published-via-control-plane": "var(--truth-observed)",
};

export default function VisionSurface(props) {
  const navigate = useNavigate();
  const [data] = createResource(() => props.endpoint, (url) => fetchWithTruth(url, 6000));

  const payload = () => data()?.data || {};
  const truthMode = () => data()?.truthMode || "declared";
  const arrays = createMemo(() => extractArrayFields(payload()));

  // Update document title when data loads
  createEffect(() => {
    const title = payload().title || props.fallbackTitle;
    if (title) setTitle(title);
  });

  const runtimeVision = () => payload().runtimeVision || {};
  const narrative = () => runtimeVision().narrative || {};

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
      {/* Header (spatial anchor) */}
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
          <span style={{
            "font-family": "var(--font-data)",
            "font-size": "var(--text-xs)",
            color: "var(--text-tertiary)",
            "letter-spacing": "0.08em",
            "text-transform": "uppercase",
          }}>
            public · vision
          </span>
          <TruthBadge mode={truthMode()} />
        </div>
        <h1 style={{
          "font-family": "var(--font-display)",
          "font-size": "var(--text-2xl)",
          "font-weight": "var(--weight-semibold)",
          color: "var(--text-primary)",
          "letter-spacing": "-0.02em",
          "margin-bottom": "var(--space-2)",
        }}>
          {payload().title || props.fallbackTitle || "Loading..."}
        </h1>
        <Show when={payload().subtitle}>
          <p style={{
            "font-size": "var(--text-sm)",
            color: "var(--text-secondary)",
            "max-width": "720px",
            "line-height": "var(--leading-relaxed)",
          }}>
            {payload().subtitle}
          </p>
        </Show>
      </div>

      {/* Narrative card (if present) */}
      <Show when={narrative().headline || narrative().summary}>
        <GlassPanel elevated truth="observed" style={{ "margin-bottom": "var(--space-5)" }}>
          <Show when={narrative().headline}>
            <h2 style={{
              "font-family": "var(--font-display)",
              "font-size": "var(--text-lg)",
              color: "var(--text-primary)",
              "margin-bottom": "var(--space-2)",
            }}>
              {narrative().headline}
            </h2>
          </Show>
          <Show when={narrative().summary}>
            <p style={{
              "font-size": "var(--text-sm)",
              color: "var(--text-secondary)",
              "line-height": "var(--leading-relaxed)",
            }}>
              {narrative().summary}
            </p>
          </Show>

          {/* Use cases */}
          <Show when={narrative().publicUseCases?.length}>
            <div style={{
              display: "flex",
              gap: "var(--space-2)",
              "flex-wrap": "wrap",
              "margin-top": "var(--space-3)",
            }}>
              <For each={narrative().publicUseCases}>
                {(uc) => (
                  <span style={{
                    padding: "var(--space-1) var(--space-3)",
                    background: "rgba(81, 214, 189, 0.08)",
                    border: "1px solid rgba(81, 214, 189, 0.15)",
                    "border-radius": "var(--radius-sm)",
                    "font-family": "var(--font-data)",
                    "font-size": "var(--text-xs)",
                    color: "var(--truth-observed)",
                  }}>
                    {uc}
                  </span>
                )}
              </For>
            </div>
          </Show>
        </GlassPanel>
      </Show>

      {/* Adaptive array rendering */}
      <For each={arrays()}>
        {(group) => (
          <div style={{ "margin-bottom": "var(--space-5)" }}>
            <h3 style={{
              "font-family": "var(--font-ui)",
              "font-size": "var(--text-xs)",
              "font-weight": "var(--weight-semibold)",
              "text-transform": "uppercase",
              "letter-spacing": "0.08em",
              color: "var(--text-tertiary)",
              "margin-bottom": "var(--space-3)",
            }}>
              {formatKey(group.key)} <span style={{ color: "var(--text-secondary)", "font-weight": "var(--weight-normal)" }}>· {group.items.length}</span>
            </h3>

            <div style={{
              display: "grid",
              "grid-template-columns": `repeat(auto-fill, minmax(${group.items.length > 5 ? "200px" : "280px"}, 1fr))`,
              gap: "var(--space-3)",
            }}>
              <For each={group.items}>
                {(item) => {
                  const status = itemStatusField(item);
                  const statusColor = STATUS_COLOR[status] || "var(--text-tertiary)";
                  const isClickable = typeof item === "object" && item?.route;

                  return (
                    <GlassPanel
                      subtle
                      padding="var(--space-3)"
                      style={isClickable ? { cursor: "pointer" } : {}}
                    >
                      <div
                        onClick={isClickable ? () => {
                          // Internal routes stay in SPA, external go full nav
                          if (item.route.startsWith("/public") || item.route.startsWith("/projects")) {
                            navigate(item.route);
                          } else {
                            window.location.href = item.route;
                          }
                        } : undefined}
                      >
                        <div style={{
                          display: "flex",
                          "align-items": "baseline",
                          "justify-content": "space-between",
                          "margin-bottom": "var(--space-1)",
                          gap: "var(--space-2)",
                        }}>
                          <span style={{
                            "font-family": "var(--font-data)",
                            "font-size": "var(--text-sm)",
                            color: "var(--text-primary)",
                            "font-weight": "var(--weight-medium)",
                          }}>
                            {itemMainField(item)}
                          </span>
                          <Show when={status}>
                            <span style={{
                              "font-family": "var(--font-data)",
                              "font-size": "var(--text-xs)",
                              color: statusColor,
                              "flex-shrink": 0,
                            }}>
                              ● {status}
                            </span>
                          </Show>
                        </div>
                        <Show when={itemDetailField(item)}>
                          <div style={{
                            "font-size": "var(--text-xs)",
                            color: "var(--text-tertiary)",
                            "line-height": "var(--leading-normal)",
                          }}>
                            {itemDetailField(item)}
                          </div>
                        </Show>
                      </div>
                    </GlassPanel>
                  );
                }}
              </For>
            </div>
          </div>
        )}
      </For>

      {/* Footer: generation timestamp */}
      <Show when={payload().generatedAt}>
        <div style={{
          "margin-top": "var(--space-8)",
          "padding-top": "var(--space-4)",
          "border-top": "1px solid var(--glass-border)",
          "font-family": "var(--font-data)",
          "font-size": "var(--text-xs)",
          color: "var(--text-tertiary)",
          "text-align": "center",
        }}>
          surface: {payload().surface || "—"} · generated {new Date(payload().generatedAt).toLocaleString()}
        </div>
      </Show>
    </div>
  );
}
