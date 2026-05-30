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

function cleanText(value) {
  return String(value || "").trim();
}

async function runConversationTurn({
  projectSlug,
  providers,
  wsBase,
  timeoutMs,
  turnId,
  message,
  history = []
}) {
  return await new Promise((resolve, reject) => {
    const socket = new WebSocket(`${wsBase.replace(/\/$/, "")}/ws/projects/${encodeURIComponent(projectSlug)}/multimodel-chat`);
    const startedAt = Date.now();
    const responses = Object.fromEntries(providers.map((provider) => [provider, ""]));
    const events = [];
    let sent = false;
    const timer = setTimeout(() => {
      try { socket.close(); } catch {
        // already closed
      }
      reject(Object.assign(new Error(`conversation timeout after ${timeoutMs}ms`), { detail: { turnId, events, responses } }));
    }, timeoutMs);

    function fail(error) {
      clearTimeout(timer);
      try { socket.close(); } catch {
        // already closed
      }
      reject(error);
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
            detail: { requested: providers, available: [...available] }
          }));
          return;
        }
        sent = true;
        socket.send(JSON.stringify({
          type: "chat",
          turnId,
          message,
          providers,
          history: Array.isArray(history) ? history : [],
          enableSynthesis: false
        }));
        return;
      }

      if (event.turnId && event.turnId !== turnId) return;

      if (event.provider && Object.hasOwn(responses, event.provider)) {
        if (event.type === "delta") {
          responses[event.provider] = `${responses[event.provider] || ""}${event.text || ""}`;
        }
        if (event.type === "provider_done") {
          responses[event.provider] = cleanText(event.text || responses[event.provider]);
        }
        if (event.type === "provider_error") {
          fail(Object.assign(new Error(`${event.provider} emitted an error`), { detail: { event, events, responses } }));
        }
      }

      if (event.type === "turn_done" && event.turnId === turnId) {
        clearTimeout(timer);
        setTimeout(() => {
          try { socket.close(); } catch {
            // already closed
          }
          resolve({ turnId, message, providers, responses, events });
        }, 300);
      }
    });

    socket.on("error", fail);
  });
}

async function verifyPersistedConversation({ apiBase, projectSlug, providers, turnId, minChars }) {
  const turnsPayload = await fetchJson(`${apiBase.replace(/\/$/, "")}/api/projects/${encodeURIComponent(projectSlug)}/multimodel/turns?limit=10&includeActive=1`);
  const turn = (turnsPayload.turns || []).find((item) => item.turnId === turnId);
  assert(turn, "conversation turn was not found in persisted history", { turnId });
  const responses = new Map((turn.responses || []).map((response) => [response.provider, response]));
  for (const provider of providers) {
    const response = responses.get(provider);
    assert(response, `missing persisted response for ${provider}`, { turn });
    assert(response.status === "done", `${provider} did not persist as done`, { response });
    assert(cleanText(response.text).length >= minChars, `${provider} persisted too little text`, { response, minChars });
    assert(Number(response.deltaCount) > 0, `${provider} missing persisted deltaCount`, { response });
    assert(Number(response.streamedChars) > 0, `${provider} missing persisted streamedChars`, { response });
  }
  const activePayload = await fetchJson(`${apiBase.replace(/\/$/, "")}/api/projects/${encodeURIComponent(projectSlug)}/multimodel/active-turns`);
  assert((activePayload.count || 0) === 0, "active turns remained after conversation verification", activePayload);
  return { turn, activePayload };
}

export async function verifyMultimodelConversation({
  projectSlug = "darwin-mfc",
  providers = ["claude", "codex", "cursor"],
  apiBase = "http://127.0.0.1:4370",
  wsBase = apiBase.replace(/^http/, "ws"),
  timeoutMs = 180_000,
  message = "Responda em uma palavra: vivo",
  minChars = 2,
  turnId = `verify-multimodel-conversation-${Date.now()}`,
  history = []
} = {}) {
  const selectedProviders = normalizedProviders(providers);
  assert(selectedProviders.length > 0, "at least one provider is required");
  const minimumChars = Math.max(1, Number(minChars) || 2);
  const conversation = await runConversationTurn({
    projectSlug,
    providers: selectedProviders,
    wsBase,
    timeoutMs,
    turnId,
    message: cleanText(message) || "Responda em uma palavra: vivo",
    history
  });
  for (const provider of selectedProviders) {
    assert(cleanText(conversation.responses[provider]).length >= minimumChars, `${provider} returned too little text`, conversation);
  }
  const persisted = await verifyPersistedConversation({
    apiBase,
    projectSlug,
    providers: selectedProviders,
    turnId,
    minChars: minimumChars
  });
  return {
    ok: true,
    projectSlug,
    turnId,
    message: conversation.message,
    providers: selectedProviders,
    responses: selectedProviders.map((provider) => ({
      provider,
      text: cleanText(conversation.responses[provider]),
      chars: cleanText(conversation.responses[provider]).length
    })),
    persisted: (persisted.turn.responses || [])
      .filter((response) => selectedProviders.includes(response.provider))
      .map((response) => ({
        provider: response.provider,
        status: response.status,
        text: cleanText(response.text),
        firstDeltaMs: response.firstDeltaMs,
        deltaCount: response.deltaCount,
        streamedChars: response.streamedChars,
        durationMs: response.durationMs
      })),
    activeTurns: persisted.activePayload.count,
    verifiedAt: new Date().toISOString(),
    truthMode: "observed-conversation-websocket-and-persisted-rest"
  };
}
