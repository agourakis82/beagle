// src/pages/Cognitive.jsx
//
// Cognitive substrate dashboard. Three stacked views:
//   1. Live SSE event feed (void / fractal / phi / physio / deep_think).
//   2. Φ-rhythm time-series from /api/v1/cognitive/phi_of_phi.
//   3. Deep-think launcher — POST /api/cognitive/deep-think, render tree.
//
// Auth: fetches the operator token once from the cockpit's auth bridge,
// caches it, and uses it for all beagle-core calls. If the bridge fails,
// the component renders a visible "declared" banner and disables actions.

import {
  createSignal,
  createResource,
  createEffect,
  onCleanup,
  Show,
  For,
  Suspense,
} from "solid-js";

const COCKPIT_ORIGIN = typeof window !== "undefined" ? window.location.origin : "";
const BEAGLE_BASE =
  (typeof window !== "undefined" && window.__BEAGLE_URL__) ||
  "http://beagle-core.tail21cbc4.ts.net";

async function fetchToken() {
  const r = await fetch(`${COCKPIT_ORIGIN}/api/auth/beagle-token`);
  if (!r.ok) throw new Error(`token bridge HTTP ${r.status}`);
  const d = await r.json();
  if (!d.token) throw new Error(`token bridge: ${d.error || "no token"}`);
  return d;
}

async function beagleGet(path, tok) {
  const r = await fetch(`${BEAGLE_BASE}${path}`, {
    headers: {
      "X-Beagle-Consumer": tok.consumer || "beagle-operator",
      Authorization: `Bearer ${tok.token}`,
    },
  });
  if (!r.ok) throw new Error(`${path} HTTP ${r.status}`);
  return r.json();
}

async function beaglePost(path, body, tok) {
  const r = await fetch(`${BEAGLE_BASE}${path}`, {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      "X-Beagle-Consumer": tok.consumer || "beagle-operator",
      Authorization: `Bearer ${tok.token}`,
    },
    body: JSON.stringify(body),
  });
  if (!r.ok) throw new Error(`${path} HTTP ${r.status}`);
  return r.json();
}

// ─── Live SSE feed ───────────────────────────────────────────────────

function EventFeed(props) {
  const [events, setEvents] = createSignal([]);
  const [status, setStatus] = createSignal("connecting");

  createEffect(() => {
    const tok = props.tok();
    if (!tok) return;
    // EventSource doesn't support custom headers; stream endpoint checks
    // token via query-string fallback OR we proxy through cockpit. For
    // now use URL + a cookie-less header is impossible → include auth in
    // URL as a query param only if the server accepts it. We'll rely on
    // the Tailnet's trusted origin for local dev. For production with
    // strict auth the cockpit UI should use fetch+ReadableStream.
    const url = `${BEAGLE_BASE}/api/v1/cognitive/stream`;
    const es = new EventSource(url, { withCredentials: false });
    setStatus("open");

    const handler = (kind) => (ev) => {
      try {
        const data = JSON.parse(ev.data);
        setEvents((prev) => [{ kind, data, t: Date.now() }, ...prev].slice(0, 60));
      } catch {
        // ignore malformed
      }
    };
    for (const k of ["void", "fractal", "phi", "physio", "deep_think", "lagged"]) {
      es.addEventListener(k, handler(k));
    }
    es.onerror = () => setStatus("error");
    onCleanup(() => es.close());
  });

  return (
    <div class="panel">
      <h3>Live cognitive events <span class={`dot dot-${status()}`} /></h3>
      <div class="event-feed">
        <Show when={events().length > 0} fallback={<em>waiting for first event…</em>}>
          <For each={events()}>
            {(e) => (
              <div class={`event event-${e.kind}`}>
                <span class="event-kind">{e.kind}</span>
                <span class="event-preview">{renderPreview(e.kind, e.data)}</span>
              </div>
            )}
          </For>
        </Show>
      </div>
    </div>
  );
}

function renderPreview(kind, data) {
  switch (kind) {
    case "void":
      return `${data.focus?.slice(0, 60) || ""} · depth=${data.max_depth_reached ?? "?"} · insights=${data.insight_count ?? "?"}`;
    case "fractal":
      return `${data.root_prompt?.slice(0, 60) || ""} · nodes=${data.node_count} · ${data.duration_ms}ms`;
    case "phi":
      return `Φ=${(data.phi ?? 0).toFixed(4)} · ${data.awareness_level || ""} · ${data.tpm_source || "?"}`;
    case "physio":
      return `HRV=${data.hrv_ms ?? "?"} · ${data.hrv_level ?? "?"} · ${data.flow_state ?? "?"}`;
    case "deep_think":
      return `${data.root_prompt?.slice(0, 50) || ""} · nodes=${data.fractal_node_count} · voids=${data.void_journey_count} · Φ=${(data.phi ?? 0).toFixed(4)}`;
    case "lagged":
      return `dropped=${data.dropped}`;
    default:
      return JSON.stringify(data).slice(0, 80);
  }
}

// ─── Φ-rhythm chart ──────────────────────────────────────────────────

function PhiRhythm(props) {
  const [rhythm, { refetch }] = createResource(
    () => props.tok(),
    (tok) => beagleGet("/api/v1/cognitive/phi_of_phi?window=40&bins=4", tok)
  );
  const intervalId = setInterval(() => refetch(), 30_000);
  onCleanup(() => clearInterval(intervalId));

  return (
    <div class="panel">
      <h3>Φ rhythm (phi_of_phi)</h3>
      <Suspense fallback={<em>loading…</em>}>
        <Show when={rhythm()}>
          {(r) => (
            <>
              <div class="phi-summary">
                <span>Φ-of-Φ: <b>{r().phi_of_phi?.toFixed(4)}</b></span>
                <span>rhythm: <b>{r().cognitive_rhythm}</b></span>
                <span>base count: {r().base_phi_count}</span>
                <span>truth: {r().truth_mode}</span>
              </div>
              <div class="phi-sparkline">
                <For each={r().trajectory || []}>
                  {(b) => (
                    <span
                      class="phi-bar"
                      style={{ height: `${(b + 1) * 12}px`, "background-color": barColor(b) }}
                      title={`band ${b}`}
                    />
                  )}
                </For>
              </div>
              <div class="phi-mip">
                MIP: [{(r().mip_partition?.[0] || []).join(", ")}] | [{(r().mip_partition?.[1] || []).join(", ")}]
              </div>
            </>
          )}
        </Show>
      </Suspense>
    </div>
  );
}

function barColor(b) {
  const palette = ["#6b7280", "#60a5fa", "#22c55e", "#f59e0b"];
  return palette[b] || "#6b7280";
}

// ─── Tool rhythm (MCP agent-call Φ) ──────────────────────────────────

function ToolRhythm(props) {
  const [rhythm, { refetch }] = createResource(
    () => props.tok(),
    (tok) => beagleGet("/api/v1/cognitive/tool_rhythm_phi?window=100", tok)
  );
  const [recentCalls, setRecentCalls] = createSignal([]);
  const intervalId = setInterval(() => refetch(), 20_000);
  onCleanup(() => clearInterval(intervalId));

  createEffect(() => {
    const tok = props.tok();
    if (!tok) return;
    const url = `${BEAGLE_BASE}/api/v1/cognitive/stream`;
    const es = new EventSource(url, { withCredentials: false });
    es.addEventListener("mcp_tool", (ev) => {
      try {
        const data = JSON.parse(ev.data);
        setRecentCalls((prev) => [data, ...prev].slice(0, 30));
        refetch();
      } catch {}
    });
    onCleanup(() => es.close());
  });

  return (
    <div class="panel">
      <h3>Tool rhythm (MCP agent calls)</h3>
      <Suspense fallback={<em>loading…</em>}>
        <Show when={rhythm()}>
          {(r) => (
            <>
              <div class="phi-summary">
                <span>tool-rhythm Φ: <b>{r().tool_rhythm_phi?.toFixed(4)}</b></span>
                <span>rhythm: <b class={`rhythm rhythm-${r().rhythm_label}`}>{r().rhythm_label}</b></span>
                <span>calls: {r().call_count}</span>
                <span>unique: {r().unique_tools}</span>
                <span>truth: {r().truth_mode}</span>
              </div>
              <div class="phi-sparkline">
                <For each={r().trajectory || []}>
                  {(b) => (
                    <span
                      class="phi-bar"
                      style={{
                        height: `${Math.min(60, 14 + b * 8)}px`,
                        "background-color": toolColor(b),
                      }}
                      title={`tool ${b}`}
                    />
                  )}
                </For>
              </div>
              <Show when={r().substrate?.length}>
                <div class="phi-mip">
                  substrate:
                  <For each={r().substrate}>
                    {(t, i) => (
                      <span class="tool-chip" style={{ "border-color": toolColor(i()) }}>
                        <span class="tool-index">{i() + 1}</span>{t}
                      </span>
                    )}
                  </For>
                </div>
              </Show>
              <Show when={r().mip_partition?.[0]?.length}>
                <div class="phi-mip">
                  MIP: [{(r().mip_partition?.[0] || []).join(", ")}] | [{(r().mip_partition?.[1] || []).join(", ")}]
                </div>
              </Show>
            </>
          )}
        </Show>
      </Suspense>
      <Show when={recentCalls().length > 0}>
        <div class="recent-tool-calls">
          <div class="section-label">recent calls (live)</div>
          <For each={recentCalls()}>
            {(c) => (
              <div class="tool-call-row">
                <span class={`event-kind ${c.is_error ? "err" : ""}`}>{c.tool_name}</span>
                <span class="tc-meta">{c.duration_ms ?? "?"}ms · {c.caller}</span>
              </div>
            )}
          </For>
        </div>
      </Show>
    </div>
  );
}

function toolColor(i) {
  const palette = ["#a78bfa", "#22c55e", "#f59e0b", "#60a5fa", "#ef4444", "#f472b6", "#14b8a6", "#eab308"];
  return palette[i % palette.length];
}

// ─── Deep-think launcher ─────────────────────────────────────────────

function DeepThinkLauncher(props) {
  const [prompt, setPrompt] = createSignal("");
  const [depth, setDepth] = createSignal(2);
  const [branching, setBranching] = createSignal(2);
  const [result, setResult] = createSignal(null);
  const [loading, setLoading] = createSignal(false);
  const [error, setError] = createSignal(null);

  async function fire() {
    setLoading(true);
    setError(null);
    setResult(null);
    try {
      const r = await beaglePost(
        "/api/cognitive/deep-think",
        {
          root_prompt: prompt(),
          max_depth: depth(),
          branching: branching(),
        },
        props.tok()
      );
      setResult(r);
    } catch (e) {
      setError(String(e.message || e));
    } finally {
      setLoading(false);
    }
  }

  return (
    <div class="panel">
      <h3>Deep-think launcher</h3>
      <textarea
        value={prompt()}
        onInput={(e) => setPrompt(e.currentTarget.value)}
        placeholder="root prompt — e.g. what does integration mean for a cognitive system"
        rows={2}
        style={{ width: "100%", "font-family": "inherit" }}
      />
      <div class="deep-think-controls">
        <label>
          depth
          <input type="number" min="1" max="2" value={depth()} onInput={(e) => setDepth(+e.currentTarget.value)} />
        </label>
        <label>
          branching
          <input type="number" min="1" max="2" value={branching()} onInput={(e) => setBranching(+e.currentTarget.value)} />
        </label>
        <button disabled={loading() || !prompt().trim()} onClick={fire}>
          {loading() ? "thinking…" : "think"}
        </button>
      </div>
      <Show when={error()}>
        <div class="error">error: {error()}</div>
      </Show>
      <Show when={result()}>
        {(r) => (
          <div class="deep-think-result">
            <div class="dt-summary">
              journey: <code>{r().journey_id}</code>
              <br />
              nodes: {r().fractal?.node_count} · voids: {r().void_journeys?.length} · Φ: {r().phi_measurement?.phi?.toFixed(4)} · tpm: {r().phi_measurement?.tpm_source} · hrv: {r().hrv_tier}
            </div>
            <details>
              <summary>fractal tree ({r().fractal?.node_count} nodes)</summary>
              <For each={r().fractal?.nodes || []}>
                {(n) => (
                  <div class={`ft-node ft-depth-${n.depth}`} style={{ "margin-left": `${n.depth * 16}px` }}>
                    <span class="ft-depth">[{n.depth}]</span> {n.summary}
                  </div>
                )}
              </For>
            </details>
            <Show when={(r().void_journeys || []).length > 0}>
              <details>
                <summary>void journeys ({r().void_journeys.length})</summary>
                <For each={r().void_journeys}>
                  {(v) => (
                    <div class="vj">
                      <b>{v.focus}</b>
                      <ul>
                        <For each={v.insights}>{(ins) => <li>{ins}</li>}</For>
                      </ul>
                    </div>
                  )}
                </For>
              </details>
            </Show>
          </div>
        )}
      </Show>
    </div>
  );
}

// ─── Page root ───────────────────────────────────────────────────────

export default function Cognitive() {
  const [tok, setTok] = createSignal(null);
  const [tokErr, setTokErr] = createSignal(null);
  fetchToken().then(setTok).catch((e) => setTokErr(String(e)));

  return (
    <div class="cognitive-page">
      <style>{`
        .cognitive-page { padding: 20px; font-family: system-ui, sans-serif; color: #e5e7eb; background: #0a0a0a; min-height: 100vh; }
        .panel { background: #111827; border: 1px solid #1f2937; border-radius: 8px; padding: 16px; margin-bottom: 16px; }
        .panel h3 { margin: 0 0 12px 0; font-size: 16px; font-weight: 600; color: #f3f4f6; }
        .dot { display: inline-block; width: 8px; height: 8px; border-radius: 50%; margin-left: 8px; }
        .dot-open { background: #22c55e; }
        .dot-connecting { background: #f59e0b; }
        .dot-error { background: #ef4444; }
        .event-feed { max-height: 360px; overflow-y: auto; font-family: ui-monospace, monospace; font-size: 12px; }
        .event { display: flex; gap: 10px; padding: 4px 8px; border-bottom: 1px solid #1f2937; }
        .event-kind { width: 80px; font-weight: 600; color: #60a5fa; }
        .event-void .event-kind { color: #a78bfa; }
        .event-fractal .event-kind { color: #22c55e; }
        .event-phi .event-kind { color: #f59e0b; }
        .event-physio .event-kind { color: #ef4444; }
        .event-deep_think .event-kind { color: #f472b6; }
        .event-preview { flex: 1; color: #9ca3af; white-space: nowrap; overflow: hidden; text-overflow: ellipsis; }
        .phi-summary { display: flex; gap: 18px; font-size: 13px; color: #9ca3af; margin-bottom: 8px; }
        .phi-summary b { color: #f3f4f6; }
        .phi-sparkline { display: flex; align-items: flex-end; gap: 2px; height: 64px; padding: 4px 0; background: #0a0a0a; border-radius: 4px; }
        .phi-bar { width: 8px; min-height: 2px; }
        .phi-mip { font-size: 12px; color: #6b7280; margin-top: 8px; font-family: ui-monospace, monospace; }
        .deep-think-controls { display: flex; gap: 12px; align-items: center; margin-top: 8px; }
        .deep-think-controls label { display: flex; gap: 4px; align-items: center; font-size: 12px; color: #9ca3af; }
        .deep-think-controls input { width: 60px; padding: 4px; background: #0a0a0a; color: #e5e7eb; border: 1px solid #1f2937; border-radius: 4px; }
        .deep-think-controls button { padding: 6px 14px; background: #2563eb; color: white; border: none; border-radius: 4px; font-weight: 600; cursor: pointer; }
        .deep-think-controls button:disabled { opacity: 0.5; cursor: not-allowed; }
        .error { color: #ef4444; font-size: 12px; margin-top: 8px; }
        .deep-think-result { margin-top: 16px; }
        .dt-summary { font-size: 13px; color: #9ca3af; margin-bottom: 12px; }
        .dt-summary code { color: #60a5fa; }
        details summary { cursor: pointer; color: #f3f4f6; margin-bottom: 6px; }
        .ft-node { font-size: 12px; color: #d1d5db; padding: 2px 0; font-family: ui-monospace, monospace; }
        .ft-depth { color: #6b7280; margin-right: 6px; }
        .ft-depth-0 { color: #f3f4f6; font-weight: 600; }
        .vj { margin: 8px 0; padding: 8px; background: #0a0a0a; border-radius: 4px; font-size: 12px; }
        .vj b { color: #a78bfa; }
        .vj ul { margin: 4px 0 0 16px; padding: 0; color: #9ca3af; }
        .rhythm { padding: 2px 6px; border-radius: 4px; text-transform: uppercase; font-size: 11px; letter-spacing: 0.05em; }
        .rhythm-focused { background: #14532d; color: #86efac; }
        .rhythm-balanced { background: #1e3a8a; color: #93c5fd; }
        .rhythm-exploratory { background: #78350f; color: #fcd34d; }
        .rhythm-insufficient { background: #374151; color: #9ca3af; }
        .tool-chip { display: inline-flex; align-items: center; gap: 4px; margin: 0 4px 4px 0; padding: 2px 6px; font-size: 11px; border: 1px solid; border-radius: 4px; color: #d1d5db; }
        .tool-chip .tool-index { font-weight: 600; color: #f3f4f6; margin-right: 3px; }
        .recent-tool-calls { margin-top: 12px; padding-top: 10px; border-top: 1px solid #1f2937; }
        .section-label { font-size: 10px; color: #6b7280; text-transform: uppercase; letter-spacing: 0.08em; margin-bottom: 6px; }
        .tool-call-row { display: flex; gap: 10px; font-family: ui-monospace, monospace; font-size: 11px; padding: 2px 0; }
        .tool-call-row .event-kind { width: 180px; color: #a78bfa; }
        .tool-call-row .event-kind.err { color: #ef4444; }
        .tc-meta { color: #6b7280; }
      `}</style>

      <h1 style={{ "margin-bottom": "20px", "font-size": "20px", "font-weight": 600 }}>
        Cognitive Substrate
      </h1>

      <Show when={tokErr()}>
        <div class="panel error" style={{ color: "#ef4444" }}>
          auth bridge failed: {tokErr()} — actions disabled
        </div>
      </Show>

      <Show when={tok()}>
        <EventFeed tok={tok} />
        <ToolRhythm tok={tok} />
        <PhiRhythm tok={tok} />
        <DeepThinkLauncher tok={tok} />
      </Show>
    </div>
  );
}
