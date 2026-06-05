#!/usr/bin/env node

import { appendFile, mkdir } from "node:fs/promises";
import path from "node:path";
import WebSocket from "ws";

const DATA_DIR =
  process.env.PROJECT_COCKPIT_MULTIMODEL_DATA_DIR ||
  process.env.BEAGLE_DATA_DIR ||
  path.resolve(process.cwd(), ".data");

function cleanString(value, fallback = "") {
  const text = String(value ?? "").trim();
  return text || fallback;
}

function safeSlug(slug) {
  return cleanString(slug, "unknown").replace(/[^a-zA-Z0-9_-]/g, "_");
}

function verificationFile(slug) {
  return path.join(DATA_DIR, "multimodel-chat", `${safeSlug(slug)}.verifications.jsonl`);
}

async function appendVerificationRecord(slug, record) {
  const file = verificationFile(slug);
  await mkdir(path.dirname(file), { recursive: true });
  await appendFile(file, `${JSON.stringify(record)}\n`, "utf8");
}

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
    const error = new Error(`${res.status} ${payload?.error || res.statusText}`);
    error.detail = payload;
    throw error;
  }
  return payload;
}

function pickProviders(providers = []) {
  const preferredLive = ["claude", "cursor", "agent-terminal:codex"];
  const preferredFailing = ["grok", "kimi", "grok-mcp", "claude-desktop", "chatgpt-mcp"];
  const byId = new Map(providers.map((provider) => [provider.id, provider]));
  const live = preferredLive
    .map((id) => byId.get(id))
    .find((provider) => provider?.status === "available");
  const failing = preferredFailing
    .map((id) => byId.get(id))
    .find((provider) => provider && provider.status !== "available");
  assert(live, "no live provider available for failure semantics verification", {
    providers: providers.map((provider) => ({ id: provider.id, status: provider.status }))
  });
  assert(failing, "no unavailable/waiting provider available for failure semantics verification", {
    providers: providers.map((provider) => ({ id: provider.id, status: provider.status }))
  });
  return { live, failing };
}

function runTurn({ wsBase, projectSlug, liveProvider, failingProvider, timeoutMs }) {
  return new Promise((resolve, reject) => {
    const turnId = `verify-provider-failure-${Date.now().toString(36)}`;
    const message = [
      "Responda em uma frase curta em português.",
      `Marcador: ${turnId}.`,
      "Não edite arquivos e não rode comandos."
    ].join(" ");
    const socket = new WebSocket(`${wsBase.replace(/\/$/, "")}/ws/projects/${encodeURIComponent(projectSlug)}/multimodel-chat`);
    const events = [];
    const responses = new Map();
    let turnDone = null;
    let sent = false;
    const timer = setTimeout(() => {
      try { socket.close(); } catch {
        // already closed
      }
      reject(Object.assign(new Error(`provider failure semantics timeout after ${timeoutMs}ms`), {
        detail: { turnId, events, responses: Object.fromEntries(responses), turnDone }
      }));
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
        fail(Object.assign(new Error("invalid WebSocket JSON"), { detail: { raw: raw.toString(), error: error.message } }));
        return;
      }
      if (event.turnId === turnId || ["ready", "error"].includes(event.type)) {
        events.push({
          type: event.type,
          provider: event.provider || "",
          status: event.status || "",
          error: event.error || event.reason || "",
          textChars: event.text ? String(event.text).length : 0
        });
      }
      if (event.type === "ready" && !sent) {
        sent = true;
        socket.send(JSON.stringify({
          type: "chat",
          turnId,
          message,
          providers: [liveProvider.id, failingProvider.id],
          history: [],
          enableSynthesis: false
        }));
        return;
      }
      if (event.turnId !== turnId) return;
      if (event.provider) {
        const current = responses.get(event.provider) || {
          provider: event.provider,
          label: event.label || event.provider,
          status: "waiting",
          text: "",
          error: ""
        };
        if (event.type === "delta") {
          current.status = "streaming";
          current.text = `${current.text}${event.text || ""}`;
        }
        if (event.type === "provider_done") {
          current.status = "done";
          current.text = cleanString(event.text || current.text);
        }
        if (event.type === "provider_error") {
          current.status = "error";
          current.error = cleanString(event.error || event.stderr, "provider error");
        }
        if (event.type === "provider_unavailable") {
          current.status = "unavailable";
          current.error = cleanString(event.reason, "unavailable");
        }
        responses.set(event.provider, current);
      }
      if (event.type === "turn_done") {
        turnDone = event;
        clearTimeout(timer);
        setTimeout(() => {
          try { socket.close(); } catch {
            // already closed
          }
          resolve({
            turnId,
            message,
            events,
            responses: Object.fromEntries(responses),
            turnDone
          });
        }, 300);
      }
    });

    socket.on("error", fail);
  });
}

async function main() {
  const projectSlug = process.env.PROJECT_SLUG || process.argv[2] || "darwin-mfc";
  const apiBase = cleanString(process.env.PROJECT_COCKPIT_API_BASE || "http://127.0.0.1:4370").replace(/\/$/, "");
  const wsBase = cleanString(process.env.PROJECT_COCKPIT_WS_BASE || apiBase.replace(/^http/, "ws")).replace(/\/$/, "");
  const timeoutMs = Number(process.env.VERIFY_MULTIMODEL_TIMEOUT_MS || 180_000);
  const providerPayload = await fetchJson(`${apiBase}/api/projects/${encodeURIComponent(projectSlug)}/multimodel/providers`);
  const { live, failing } = pickProviders(providerPayload.providers || []);
  const turn = await runTurn({
    wsBase,
    projectSlug,
    liveProvider: live,
    failingProvider: failing,
    timeoutMs
  });

  const liveResponse = turn.responses[live.id];
  const failingResponse = turn.responses[failing.id];
  assert(liveResponse?.status === "done", "live provider did not complete", { live, turn });
  assert(cleanString(liveResponse.text).length >= 8, "live provider returned too little text", { liveResponse });
  assert(["error", "unavailable"].includes(failingResponse?.status), "failing provider did not stay visibly failed/unavailable", {
    failing,
    failingResponse,
    turn
  });
  assert(cleanString(failingResponse.error), "failing provider did not expose a reason", { failingResponse });
  assert(turn.turnDone?.status === "completed_with_errors", "turn_done did not preserve completed_with_errors", { turnDone: turn.turnDone, turn });

  const turnsPayload = await fetchJson(`${apiBase}/api/projects/${encodeURIComponent(projectSlug)}/multimodel/turns?limit=20&includeActive=1`);
  const persistedTurn = (turnsPayload.turns || []).find((item) => item.turnId === turn.turnId);
  assert(persistedTurn, "turn was not persisted", { turnId: turn.turnId });
  assert(persistedTurn.status === "completed_with_errors", "persisted turn did not preserve completed_with_errors", { persistedTurn });
  const persistedResponses = new Map((persistedTurn.responses || []).map((response) => [response.provider, response]));
  assert(persistedResponses.get(live.id)?.status === "done", "persisted live response is not done", { persistedTurn });
  assert(["error", "unavailable"].includes(persistedResponses.get(failing.id)?.status), "persisted failing response is not failed/unavailable", { persistedTurn });

  const activePayload = await fetchJson(`${apiBase}/api/projects/${encodeURIComponent(projectSlug)}/multimodel/active-turns`);
  assert((activePayload.count || 0) === 0, "active turns remained after failure semantics verification", activePayload);

  const record = {
    ok: true,
    schema: "beagle.multimodel-provider-failure-semantics-verification.v1",
    kind: "provider-failure-semantics",
    projectSlug,
    turnId: turn.turnId,
    liveProvider: {
      id: live.id,
      status: liveResponse.status,
      textChars: cleanString(liveResponse.text).length
    },
    failingProvider: {
      id: failing.id,
      initialStatus: failing.status,
      observedStatus: failingResponse.status,
      reason: failingResponse.error
    },
    turnStatus: persistedTurn.status,
    activeTurns: activePayload.count || 0,
    verifiedAt: new Date().toISOString(),
    truthMode: "observed-websocket-real-provider-continues-while-selected-provider-fails"
  };
  await appendVerificationRecord(projectSlug, record);
  console.log(JSON.stringify(record, null, 2));
}

main().catch(async (error) => {
  const projectSlug = process.env.PROJECT_SLUG || process.argv[2] || "darwin-mfc";
  const record = {
    ok: false,
    schema: "beagle.multimodel-provider-failure-semantics-verification.v1",
    kind: "provider-failure-semantics",
    projectSlug,
    error: error.message,
    detail: error.detail || {},
    verifiedAt: new Date().toISOString(),
    truthMode: "verification-failed"
  };
  await appendVerificationRecord(projectSlug, record).catch(() => {});
  console.error(JSON.stringify(record, null, 2));
  process.exit(1);
});
