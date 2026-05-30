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

function normalizedProviders(providers) {
  return (Array.isArray(providers) ? providers : String(providers || "claude,codex,cursor").split(","))
    .map((item) => String(item || "").trim())
    .filter(Boolean);
}

function wait(ms) {
  return new Promise((resolve) => setTimeout(resolve, ms));
}

function socketUrl(wsBase, projectSlug) {
  return `${wsBase.replace(/\/$/, "")}/ws/projects/${encodeURIComponent(projectSlug)}/multimodel-chat`;
}

async function openReadySocket({ wsBase, projectSlug, timeoutMs }) {
  return await new Promise((resolve, reject) => {
    const socket = new WebSocket(socketUrl(wsBase, projectSlug));
    const timer = setTimeout(() => {
      try { socket.close(); } catch {
        // already closed
      }
      reject(new Error(`ready timeout after ${timeoutMs}ms`));
    }, timeoutMs);

    socket.on("message", (raw) => {
      const event = JSON.parse(raw.toString());
      if (event.type !== "ready") return;
      clearTimeout(timer);
      resolve({ socket, ready: event });
    });
    socket.on("error", (error) => {
      clearTimeout(timer);
      reject(error);
    });
  });
}

async function startAndDetachTurn({ wsBase, projectSlug, providers, turnId, timeoutMs }) {
  const { socket, ready } = await openReadySocket({ wsBase, projectSlug, timeoutMs: Math.min(20_000, timeoutMs) });
  const available = new Set((ready.providers || [])
    .filter((provider) => provider.status === "available")
    .map((provider) => provider.id));
  const unavailableRequested = providers.filter((provider) => !available.has(provider));
  assert(!unavailableRequested.length, `requested provider(s) unavailable: ${unavailableRequested.join(", ")}`, {
    requested: providers,
    available: [...available]
  });

  return await new Promise((resolve, reject) => {
    const events = [];
    const timer = setTimeout(() => {
      try { socket.close(); } catch {
        // already closed
      }
      reject(Object.assign(new Error(`detach timeout after ${timeoutMs}ms`), { detail: { events } }));
    }, timeoutMs);

    socket.on("message", (raw) => {
      const event = JSON.parse(raw.toString());
      if (event.type !== "ready") {
        events.push({ type: event.type, provider: event.provider || "", turnId: event.turnId || "" });
      }
      if (event.type === "turn_started" && event.turnId === turnId) {
        clearTimeout(timer);
        socket.close();
        resolve({ events });
      }
    });

    socket.on("error", (error) => {
      clearTimeout(timer);
      reject(error);
    });

    socket.send(JSON.stringify({
      type: "chat",
      turnId,
      message: "Reconnect verification turn. Each selected provider must reply with exactly: OK",
      providers,
      history: [],
      enableSynthesis: false
    }));
  });
}

async function reconnectAndObserve({ wsBase, projectSlug, turnId, timeoutMs }) {
  return await new Promise((resolve, reject) => {
    const socket = new WebSocket(socketUrl(wsBase, projectSlug));
    const events = [];
    let sawReady = false;
    let sawSnapshot = false;
    let sawHeartbeat = false;
    let sawDone = false;
    const timer = setTimeout(() => {
      try { socket.close(); } catch {
        // already closed
      }
      reject(Object.assign(new Error(`reconnect observation timeout after ${timeoutMs}ms`), {
        detail: { sawReady, sawSnapshot, sawHeartbeat, sawDone, events }
      }));
    }, timeoutMs);

    socket.on("message", (raw) => {
      const event = JSON.parse(raw.toString());
      if (["ready", "turn_snapshot", "turn_heartbeat", "provider_started", "delta", "provider_done", "provider_error", "turn_done"].includes(event.type)) {
        events.push({
          type: event.type,
          turnId: event.turnId || "",
          provider: event.provider || "",
          detached: event.detached === true,
          reason: event.reason || "",
          textChars: event.text ? String(event.text).length : 0
        });
      }
      if (event.type === "ready") {
        sawReady = true;
      }
      if (event.type === "turn_snapshot" && event.turnId === turnId && event.detached === true) {
        sawSnapshot = true;
      }
      if (event.type === "turn_heartbeat" && event.turnId === turnId) {
        sawHeartbeat = true;
      }
      if (event.type === "turn_done" && event.turnId === turnId) {
        sawDone = true;
        clearTimeout(timer);
        setTimeout(() => {
          try { socket.close(); } catch {
            // already closed
          }
          resolve({ sawReady, sawSnapshot, sawHeartbeat, sawDone, events });
        }, 200);
      }
    });

    socket.on("error", (error) => {
      clearTimeout(timer);
      reject(error);
    });
  });
}

async function verifyPersistedTurn({ apiBase, projectSlug, providers, turnId }) {
  const turnsPayload = await fetchJson(`${apiBase.replace(/\/$/, "")}/api/projects/${encodeURIComponent(projectSlug)}/multimodel/turns?limit=10&includeActive=1`);
  const turn = (turnsPayload.turns || []).find((item) => item.turnId === turnId);
  assert(turn, "turn was not found in persisted history", { turnId, turns: (turnsPayload.turns || []).map((item) => item.turnId) });
  const responses = new Map((turn.responses || []).map((response) => [response.provider, response]));
  for (const provider of providers) {
    const response = responses.get(provider);
    assert(response, `missing persisted response for ${provider}`, { turn });
    assert(response.status === "done", `${provider} did not persist as done`, { response });
    assert(Number(response.deltaCount) > 0, `${provider} missing persisted deltaCount`, { response });
    assert(Number(response.streamedChars) > 0, `${provider} missing persisted streamedChars`, { response });
  }
  const activePayload = await fetchJson(`${apiBase.replace(/\/$/, "")}/api/projects/${encodeURIComponent(projectSlug)}/multimodel/active-turns`);
  assert((activePayload.count || 0) === 0, "active turns remained after reconnect verification", activePayload);
  return { turn, activePayload };
}

export async function verifyMultimodelReconnect({
  projectSlug = "darwin-mfc",
  providers = ["claude", "codex", "cursor"],
  apiBase = "http://127.0.0.1:4370",
  wsBase = apiBase.replace(/^http/, "ws"),
  timeoutMs = 180_000,
  turnId = `verify-multimodel-reconnect-${Date.now()}`
} = {}) {
  const selectedProviders = normalizedProviders(providers);
  assert(selectedProviders.length > 0, "at least one provider is required");

  const detached = await startAndDetachTurn({
    wsBase,
    projectSlug,
    providers: selectedProviders,
    turnId,
    timeoutMs: Math.min(timeoutMs, 30_000)
  });
  await wait(100);
  const reconnected = await reconnectAndObserve({
    wsBase,
    projectSlug,
    turnId,
    timeoutMs
  });
  assert(reconnected.sawReady, "reconnected socket never became ready", reconnected);
  assert(reconnected.sawSnapshot, "reconnected socket did not receive active detached turn snapshot", reconnected);
  assert(reconnected.sawDone, "reconnected socket did not observe turn_done", reconnected);
  const persisted = await verifyPersistedTurn({
    apiBase,
    projectSlug,
    providers: selectedProviders,
    turnId
  });

  return {
    ok: true,
    projectSlug,
    turnId,
    providers: selectedProviders,
    detached,
    reconnected,
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
    truthMode: "observed-reconnect-active-turn-and-persisted-rest"
  };
}
