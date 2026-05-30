import WebSocket from "ws";

function assert(condition, message, detail = {}) {
  if (!condition) {
    const error = new Error(message);
    error.detail = detail;
    throw error;
  }
}

async function fetchJson(url) {
  const res = await fetch(url);
  const payload = await res.json().catch(() => ({}));
  if (!res.ok) {
    throw new Error(`${res.status} ${payload?.error || res.statusText}`);
  }
  return payload;
}

function providerState() {
  return {
    started: 0,
    delta: 0,
    done: 0,
    error: 0,
    chars: 0,
    firstDeltaMs: null,
    doneMs: null,
    errorText: ""
  };
}

function normalizedProviders(providers) {
  return (Array.isArray(providers) ? providers : String(providers || "claude,codex,cursor").split(","))
    .map((item) => String(item || "").trim())
    .filter(Boolean);
}

async function runRealtimeTurn({
  projectSlug,
  providers,
  wsBase,
  timeoutMs,
  turnId
}) {
  return await new Promise((resolve, reject) => {
    const socket = new WebSocket(`${wsBase}/ws/projects/${encodeURIComponent(projectSlug)}/multimodel-chat`);
    const startedAt = Date.now();
    const seen = Object.fromEntries(providers.map((provider) => [provider, providerState()]));
    const events = [];
    let sent = false;
    const timer = setTimeout(() => {
      try { socket.close(); } catch {
        // ignore close errors while failing the verification
      }
      reject(Object.assign(new Error(`timeout after ${timeoutMs}ms`), { detail: { turnId, seen, events } }));
    }, timeoutMs);

    function fail(error) {
      clearTimeout(timer);
      try { socket.close(); } catch {
        // already closed
      }
      reject(error);
    }

    function finish() {
      clearTimeout(timer);
      try { socket.close(); } catch {
        // already closed
      }
      resolve({ turnId, providers, seen, events });
    }

    socket.on("message", (raw) => {
      let event;
      try {
        event = JSON.parse(raw.toString());
      } catch (error) {
        fail(Object.assign(new Error("invalid WebSocket JSON event"), { detail: { raw: raw.toString(), error: error.message } }));
        return;
      }

      const elapsedMs = Date.now() - startedAt;
      if (["ready", "turn_started", "provider_started", "delta", "provider_done", "provider_error", "turn_done", "error"].includes(event.type)) {
        events.push({
          type: event.type,
          provider: event.provider || "",
          elapsedMs,
          textChars: event.text ? String(event.text).length : 0,
          error: event.error || ""
        });
      }

      if (event.type === "ready" && !sent) {
        const available = new Set((event.providers || [])
          .filter((provider) => provider.status === "available")
          .map((provider) => provider.id));
        const unavailableRequested = providers.filter((provider) => !available.has(provider));
        if (unavailableRequested.length) {
          fail(Object.assign(new Error(`requested provider(s) unavailable: ${unavailableRequested.join(", ")}`), {
            detail: {
              requested: providers,
              available: [...available]
            }
          }));
          return;
        }

        sent = true;
        socket.send(JSON.stringify({
          type: "chat",
          turnId,
          message: "Verification turn. Each selected provider must reply with exactly: OK",
          providers,
          history: [],
          enableSynthesis: false
        }));
        return;
      }

      const state = seen[event.provider];
      if (state) {
        if (event.type === "provider_started") state.started += 1;
        if (event.type === "delta") {
          state.delta += 1;
          state.chars += String(event.text || "").length;
          if (state.firstDeltaMs === null) state.firstDeltaMs = elapsedMs;
        }
        if (event.type === "provider_done") {
          state.done += 1;
          state.doneMs = elapsedMs;
        }
        if (event.type === "provider_error") {
          state.error += 1;
          state.errorText = event.error || "";
        }
      }

      if (event.type === "turn_done") {
        setTimeout(finish, 300);
      }
    });

    socket.on("error", (error) => fail(error));
  });
}

async function verifyPersistedTurn({
  projectSlug,
  providers,
  apiBase,
  turnId
}) {
  const turnsPayload = await fetchJson(`${apiBase}/api/projects/${encodeURIComponent(projectSlug)}/multimodel/turns?limit=10&includeActive=1`);
  const turn = (turnsPayload.turns || []).find((item) => item.turnId === turnId);
  assert(turn, "turn was not found in persisted history", { turnId, turns: (turnsPayload.turns || []).map((item) => item.turnId) });

  const responses = new Map((turn.responses || []).map((response) => [response.provider, response]));
  for (const provider of providers) {
    const response = responses.get(provider);
    assert(response, `missing persisted response for ${provider}`, { turn });
    assert(response.status === "done", `${provider} did not persist as done`, { response });
    assert(Number(response.firstDeltaMs) >= 0, `${provider} missing persisted firstDeltaMs`, { response });
    assert(Number(response.deltaCount) > 0, `${provider} missing persisted deltaCount`, { response });
    assert(Number(response.streamedChars) > 0, `${provider} missing persisted streamedChars`, { response });
    assert(Number(response.durationMs) >= Number(response.firstDeltaMs), `${provider} duration does not cover first delta`, { response });
  }

  const activePayload = await fetchJson(`${apiBase}/api/projects/${encodeURIComponent(projectSlug)}/multimodel/active-turns`);
  assert((activePayload.count || 0) === 0, "active turns remained after verification", activePayload);

  return { turn, activePayload };
}

export async function verifyMultimodelRealtime({
  projectSlug = "darwin-mfc",
  providers = ["claude", "codex", "cursor"],
  apiBase = "http://127.0.0.1:4370",
  wsBase = apiBase.replace(/^http/, "ws"),
  timeoutMs = 180_000,
  minProviders = null,
  turnId = `verify-multimodel-realtime-${Date.now()}`
} = {}) {
  const selectedProviders = normalizedProviders(providers);
  const minimum = Number(minProviders || selectedProviders.length);
  assert(selectedProviders.length >= minimum, "not enough providers requested", { providers: selectedProviders, minProviders: minimum });

  const realtime = await runRealtimeTurn({
    projectSlug,
    providers: selectedProviders,
    wsBase: wsBase.replace(/\/$/, ""),
    timeoutMs,
    turnId
  });
  for (const provider of selectedProviders) {
    const state = realtime.seen[provider];
    assert(state.started > 0, `${provider} never started`, realtime);
    assert(state.delta > 0, `${provider} never streamed a delta`, realtime);
    assert(state.chars > 0, `${provider} streamed zero characters`, realtime);
    assert(state.done > 0, `${provider} never completed`, realtime);
    assert(state.error === 0, `${provider} emitted an error`, realtime);
  }

  const persisted = await verifyPersistedTurn({
    projectSlug,
    providers: selectedProviders,
    apiBase: apiBase.replace(/\/$/, ""),
    turnId
  });

  return {
    ok: true,
    projectSlug,
    turnId,
    providers: selectedProviders,
    realtime: realtime.seen,
    persisted: (persisted.turn.responses || [])
      .filter((response) => selectedProviders.includes(response.provider))
      .map((response) => ({
        provider: response.provider,
        status: response.status,
        firstDeltaMs: response.firstDeltaMs,
        deltaCount: response.deltaCount,
        streamedChars: response.streamedChars,
        durationMs: response.durationMs
      })),
    activeTurns: persisted.activePayload.count,
    verifiedAt: new Date().toISOString(),
    truthMode: "observed-websocket-and-persisted-rest"
  };
}
