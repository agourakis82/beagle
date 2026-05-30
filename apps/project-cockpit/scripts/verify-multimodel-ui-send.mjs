#!/usr/bin/env node

import { spawn } from "node:child_process";
import { appendFile, mkdir } from "node:fs/promises";
import path from "node:path";

const DATA_DIR =
  process.env.PROJECT_COCKPIT_MULTIMODEL_DATA_DIR ||
  process.env.BEAGLE_DATA_DIR ||
  path.resolve(process.cwd(), ".data");

function assert(condition, message, detail = {}) {
  if (!condition) {
    const error = new Error(message);
    error.detail = detail;
    throw error;
  }
}

function cleanString(value, fallback = "") {
  const text = String(value || "").trim();
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

async function fetchJson(url) {
  const res = await fetch(url);
  const payload = await res.json().catch(() => ({}));
  if (!res.ok) throw new Error(`${res.status} ${payload?.error || res.statusText}`);
  return payload;
}

function shellQuote(value) {
  return `'${String(value).replace(/'/g, "'\\''")}'`;
}

function runShell(command, { stdin = "", timeoutMs = 60_000 } = {}) {
  return new Promise((resolve, reject) => {
    const child = spawn("/bin/bash", ["-lc", command], {
      stdio: ["pipe", "pipe", "pipe"]
    });
    let stdout = "";
    let stderr = "";
    const timer = setTimeout(() => {
      child.kill("SIGTERM");
      reject(Object.assign(new Error(`command timeout after ${timeoutMs}ms`), { detail: { command, stdout, stderr } }));
    }, timeoutMs);
    child.stdout.on("data", (chunk) => {
      stdout += chunk.toString();
    });
    child.stderr.on("data", (chunk) => {
      stderr += chunk.toString();
    });
    child.on("error", (error) => {
      clearTimeout(timer);
      reject(error);
    });
    child.on("close", (code) => {
      clearTimeout(timer);
      if (code === 0) {
        resolve({ stdout, stderr });
      } else {
        reject(Object.assign(new Error(`command exited ${code}`), { detail: { command, stdout, stderr } }));
      }
    });
    child.stdin.end(stdin);
  });
}

function runProcess(command, args = [], { timeoutMs = 60_000 } = {}) {
  return new Promise((resolve, reject) => {
    const child = spawn(command, args, {
      stdio: ["ignore", "pipe", "pipe"]
    });
    let stdout = "";
    let stderr = "";
    const timer = setTimeout(() => {
      child.kill("SIGTERM");
      reject(Object.assign(new Error(`command timeout after ${timeoutMs}ms`), { detail: { command, args, stdout, stderr } }));
    }, timeoutMs);
    child.stdout.on("data", (chunk) => {
      stdout += chunk.toString();
    });
    child.stderr.on("data", (chunk) => {
      stderr += chunk.toString();
    });
    child.on("error", (error) => {
      clearTimeout(timer);
      reject(error);
    });
    child.on("close", (code) => {
      clearTimeout(timer);
      if (code === 0) {
        resolve({ stdout, stderr });
      } else {
        reject(Object.assign(new Error(`command exited ${code}`), { detail: { command: [command, ...args].join(" "), stdout, stderr } }));
      }
    });
  });
}

function parseAgentBrowserJson(stdout) {
  const lines = stdout
    .split("\n")
    .map((line) => line.trim())
    .filter(Boolean);
  for (const line of [...lines].reverse()) {
    const unquoted = line.startsWith("\"") && line.endsWith("\"")
      ? JSON.parse(line)
      : line;
    if (typeof unquoted === "string" && unquoted.startsWith("{")) {
      return JSON.parse(unquoted);
    }
    if (typeof unquoted === "object" && unquoted) return unquoted;
  }
  throw Object.assign(new Error("agent-browser JSON result not found"), { detail: { stdout } });
}

async function agentBrowserEval({ url, script, timeoutMs = 90_000, attempts = 3 }) {
  let lastError = null;
  for (let attempt = 1; attempt <= attempts; attempt += 1) {
    try {
      await runShell("agent-browser close", { timeoutMs: 10_000 }).catch(() => {});
      await runShell(`agent-browser open ${shellQuote(url)}`, { timeoutMs });
      await runShell("agent-browser wait 1500", { timeoutMs: 10_000 });
      const result = await runProcess("agent-browser", ["eval", script], { timeoutMs });
      return parseAgentBrowserJson(result.stdout);
    } catch (error) {
      lastError = error;
      await runShell("agent-browser close", { timeoutMs: 10_000 }).catch(() => {});
      if (attempt < attempts) {
        await new Promise((resolve) => setTimeout(resolve, 750 * attempt));
      }
    }
  }
  throw lastError;
}

async function waitForPersistedTurn({ apiBase, projectSlug, marker, turnId = "", timeoutMs = 90_000 }) {
  const deadline = Date.now() + timeoutMs;
  let lastPayload = null;
  let terminalCandidate = null;
  let terminalCandidateSince = 0;
  while (Date.now() < deadline) {
    lastPayload = await fetchJson(`${apiBase}/api/projects/${encodeURIComponent(projectSlug)}/multimodel/turns?limit=12&includeActive=1`);
    const turn = cleanString(turnId)
      ? (lastPayload.turns || []).find((item) => item.turnId === turnId)
      : (lastPayload.turns || []).find((item) => String(item.message || "").includes(marker));
    if (turn && !["waiting", "streaming"].includes(turn.status)) {
      if (turn.status === "done") return { turn, payload: lastPayload };
      terminalCandidate = { turn, payload: lastPayload };
      terminalCandidateSince ||= Date.now();
      if (Date.now() - terminalCandidateSince >= 5_000) return terminalCandidate;
    }
    await new Promise((resolve) => setTimeout(resolve, 1000));
  }
  if (terminalCandidate) return terminalCandidate;
  throw Object.assign(new Error("persisted UI turn was not found in time"), { detail: { marker, turnId, lastPayload } });
}

async function waitForNoActiveTurns({ apiBase, projectSlug, timeoutMs = 30_000 }) {
  const deadline = Date.now() + timeoutMs;
  let activePayload = null;
  while (Date.now() < deadline) {
    activePayload = await fetchJson(`${apiBase}/api/projects/${encodeURIComponent(projectSlug)}/multimodel/active-turns`);
    if ((activePayload.count || 0) === 0) return activePayload;
    await new Promise((resolve) => setTimeout(resolve, 500));
  }
  return activePayload;
}

export async function verifyMultimodelUiSend({
  projectSlug = "darwin-mfc",
  providers = ["claude", "codex", "cursor"],
  appBase = "http://127.0.0.1:4173",
  apiBase = "http://127.0.0.1:4370",
  timeoutMs = 180_000,
  marker = `ui-send-${Date.now()}-${Math.random().toString(16).slice(2)}`,
  prompt = "Responda em uma palavra: vivo",
  expectedText = "vivo",
  requiredHistoryMarker = "",
  recordKind = "ui-send",
  recordSchema = "beagle.multimodel-ui-send-verification.v1"
} = {}) {
  const url = `${appBase.replace(/\/$/, "")}/workbench/${encodeURIComponent(projectSlug)}`;
  const message = `${cleanString(prompt, "Responda em uma palavra: vivo")} (${marker})`;
  const preflightActive = await waitForNoActiveTurns({
    apiBase: apiBase.replace(/\/$/, ""),
    projectSlug,
    timeoutMs: Math.min(45_000, Math.max(10_000, timeoutMs / 4))
  });
  assert((preflightActive.count || 0) === 0, "active turns were still running before UI send verification", preflightActive);
  let recoveredPersisted = null;
  let browserEvalError = null;
  let sendResult = null;
  try {
    sendResult = await agentBrowserEval({
      url,
      timeoutMs: Math.min(timeoutMs, 90_000),
      attempts: 1,
      script: `
(async () => {
  const expectedProviders = ${JSON.stringify(providers)};
  const input = document.querySelector('[data-testid="multimodel-composer-input"]');
  const send = document.querySelector('[data-testid="multimodel-send"]');
  const notice = () => document.querySelector('[data-testid="multimodel-send-notice"]')?.innerText || '';
  const providerToggles = () => Array.from(document.querySelectorAll('[data-testid="multimodel-provider-toggle"]'));
  const providerSelection = () => providerToggles().map((button) => ({
    provider: button.getAttribute('data-provider-id') || '',
    status: button.getAttribute('data-provider-status') || '',
    selected: button.getAttribute('data-selected') === 'true',
    disabled: button.disabled,
    text: button.innerText
  }));
  const waitForHistoryMarker = async () => {
    const marker = ${JSON.stringify(requiredHistoryMarker)};
    if (!marker) return { ok: true, marker: '', observed: false };
    const deadline = Date.now() + 20000;
    while (Date.now() < deadline) {
      const turn = Array.from(document.querySelectorAll('[data-testid="multimodel-turn"]')).find((item) => item.innerText.includes(marker));
      if (turn) {
        return {
          ok: true,
          marker,
          observed: true,
          turnId: turn.getAttribute('data-turn-id') || '',
          status: turn.getAttribute('data-turn-status') || ''
        };
      }
      await new Promise((resolve) => setTimeout(resolve, 250));
    }
    return { ok: false, marker, observed: false, body: document.body.innerText.slice(0, 1200) };
  };
  const alignProviderSelection = async () => {
    const deadline = Date.now() + 15000;
    let selection = providerSelection();
    while (selection.length === 0 && Date.now() < deadline) {
      await new Promise((resolve) => setTimeout(resolve, 250));
      selection = providerSelection();
    }
    const missingToggles = expectedProviders.filter((provider) => !selection.some((item) => item.provider === provider));
    if (missingToggles.length) {
      return { ok: false, reason: 'missing provider toggles', missingToggles, selection };
    }
    const unavailable = selection.filter((item) => expectedProviders.includes(item.provider) && (item.disabled || item.status !== 'available'));
    if (unavailable.length) {
      return { ok: false, reason: 'requested provider unavailable', unavailable, selection };
    }
    for (const button of providerToggles()) {
      const provider = button.getAttribute('data-provider-id') || '';
      const shouldSelect = expectedProviders.includes(provider);
      const isSelected = button.getAttribute('data-selected') === 'true';
      if (button.disabled) continue;
      if (shouldSelect !== isSelected) {
        button.click();
        await new Promise((resolve) => setTimeout(resolve, 120));
      }
    }
    const selectedDeadline = Date.now() + 5000;
    let finalSelection = providerSelection();
    while (Date.now() < selectedDeadline) {
      const selected = finalSelection.filter((item) => item.selected).map((item) => item.provider).sort();
      const expected = [...expectedProviders].sort();
      if (JSON.stringify(selected) === JSON.stringify(expected)) {
        return { ok: true, selection: finalSelection, selected };
      }
      await new Promise((resolve) => setTimeout(resolve, 150));
      finalSelection = providerSelection();
    }
    return {
      ok: false,
      reason: 'provider selection did not settle',
      selection: finalSelection,
      selected: finalSelection.filter((item) => item.selected).map((item) => item.provider)
    };
  };
  const liveTurn = () => {
    const matchingTurn = Array.from(document.querySelectorAll('[data-testid="multimodel-turn"]')).find((turn) => turn.innerText.includes(${JSON.stringify(marker)}));
    return {
      ok: Boolean(matchingTurn),
      turnId: matchingTurn?.getAttribute('data-turn-id') || '',
      status: matchingTurn?.getAttribute('data-turn-status') || '',
      trace: matchingTurn ? Array.from(matchingTurn.querySelectorAll('[data-testid="turn-live-trace"] span')).map((el) => ({
        type: el.getAttribute('data-event-type') || '',
        provider: el.getAttribute('data-event-provider') || '',
        text: el.innerText
      })) : [],
      responses: matchingTurn ? Array.from(matchingTurn.querySelectorAll('[data-testid="multimodel-response"]')).map((el) => ({
        provider: el.getAttribute('data-provider'),
        status: el.getAttribute('data-response-status'),
        transport: el.getAttribute('data-provider-transport') || '',
        deltaCount: Number(el.getAttribute('data-delta-count') || 0),
        streamedChars: Number(el.getAttribute('data-streamed-chars') || 0),
        evidence: Array.from(el.querySelectorAll('[data-testid="response-evidence"] span')).map((item) => item.innerText),
        textChars: el.innerText.length,
        text: el.innerText
      })) : []
    };
  };
  const hasLiveProgress = (turn) => (turn.responses || []).some((response) => {
    if (!expectedProviders.includes(response.provider)) return false;
    if (response.status && response.status !== 'waiting') return true;
    return /\\bvivo\\b|done · first|streaming · first/i.test(response.text || '');
  });
  const providerHasVisibleText = (response) => {
    const text = response.text || '';
    if (/\\bvivo\\b/i.test(text)) return true;
    return response.status === 'done' && !/waiting for stream/i.test(text);
  };
  const textProviders = (turn) => expectedProviders.filter((provider) => {
    const response = (turn.responses || []).find((item) => item.provider === provider);
    return response && providerHasVisibleText(response);
  });
  const traceTypes = (turn) => new Set((turn.trace || []).map((event) => event.type));
  const hasLiveTrace = (turn) => {
    const types = traceTypes(turn);
    return types.has('turn_started') && types.has('provider_started') && (types.has('delta') || types.has('provider_done'));
  };
  if (!input || !send) {
    return JSON.stringify({ ok: false, reason: 'missing composer', body: document.body.innerText.slice(0, 800) });
  }
  const historyMarkerResult = await waitForHistoryMarker();
  if (!historyMarkerResult.ok) {
    return JSON.stringify({ ok: false, reason: 'required history marker missing before send', historyMarkerResult });
  }
  const existing = liveTurn();
  if (existing.ok) {
    let progress = existing;
    const progressDeadline = Date.now() + 25000;
    while (!(hasLiveProgress(progress) && hasLiveTrace(progress)) && Date.now() < progressDeadline) {
      await new Promise((resolve) => setTimeout(resolve, 250));
      progress = liveTurn();
    }
    const textSnapshot = progress;
    return JSON.stringify({
      ok: true,
      marker: ${JSON.stringify(marker)},
      message: ${JSON.stringify(message)},
      reusedExistingTurn: true,
      historyMarker: historyMarkerResult,
      providerSelection: { ok: true, selection: providerSelection(), selected: providerSelection().filter((item) => item.selected).map((item) => item.provider) },
      beforeClick: { disabled: send.disabled, notice: notice(), reusedExistingTurn: true },
      afterClickNotice: notice() || 'Existing turn observed.',
      liveTurn: existing,
      liveProgress: progress,
      observedLiveProgress: hasLiveProgress(progress),
      observedLiveTrace: hasLiveTrace(progress),
      liveText: textSnapshot,
      observedLiveTextProviders: textProviders(textSnapshot),
      missingLiveTextProviders: expectedProviders.filter((provider) => !textProviders(textSnapshot).includes(provider)),
      missingLiveProviders: expectedProviders.filter((provider) => !existing.responses.some((response) => response.provider === provider))
    });
  }
  const selectionResult = await alignProviderSelection();
  if (!selectionResult.ok) {
    return JSON.stringify({ ok: false, ...selectionResult, body: document.body.innerText.slice(0, 1200) });
  }
  input.focus();
  input.value = ${JSON.stringify(message)};
  input.dispatchEvent(new InputEvent('input', { bubbles: true, inputType: 'insertText', data: input.value }));
  await new Promise((resolve) => setTimeout(resolve, 250));
  const beforeClick = { disabled: send.disabled, notice: notice() };
  if (send.disabled) return JSON.stringify({ ok: false, reason: 'send disabled before click', beforeClick });
  send.click();
  let live = liveTurn();
  const deadline = Date.now() + 5000;
  while (!live.ok && Date.now() < deadline) {
    await new Promise((resolve) => setTimeout(resolve, 100));
    live = liveTurn();
  }
  let progress = live;
  const progressDeadline = Date.now() + 25000;
  while (!(hasLiveProgress(progress) && hasLiveTrace(progress)) && Date.now() < progressDeadline) {
    await new Promise((resolve) => setTimeout(resolve, 250));
    progress = liveTurn();
  }
  const textSnapshot = progress;
  const missingProviders = expectedProviders.filter((provider) => !live.responses.some((response) => response.provider === provider));
  const missingTextProviders = expectedProviders.filter((provider) => !textProviders(textSnapshot).includes(provider));
  return JSON.stringify({
    ok: true,
    marker: ${JSON.stringify(marker)},
    message: ${JSON.stringify(message)},
    historyMarker: historyMarkerResult,
    providerSelection: selectionResult,
    beforeClick,
    afterClickNotice: notice(),
    liveTurn: live,
    liveProgress: progress,
    observedLiveProgress: hasLiveProgress(progress),
    observedLiveTrace: hasLiveTrace(progress),
    liveText: textSnapshot,
    observedLiveTextProviders: textProviders(textSnapshot),
    missingLiveTextProviders: missingTextProviders,
    missingLiveProviders: missingProviders
  });
})()
`
    });
  } catch (error) {
    browserEvalError = error;
    recoveredPersisted = await waitForPersistedTurn({
      apiBase: apiBase.replace(/\/$/, ""),
      projectSlug,
      marker,
      timeoutMs: Math.min(timeoutMs, 120_000)
    }).catch((persistError) => {
      error.detail = {
        ...(error.detail || {}),
        persistedRecoveryError: persistError.message,
        persistedRecoveryDetail: persistError.detail || null
      };
      throw error;
    });
    const recoveredTurn = recoveredPersisted.turn || {};
    const recoveredResponses = Array.isArray(recoveredTurn.responses) ? recoveredTurn.responses : [];
    const recoveredTrace = Array.isArray(recoveredTurn.trace) ? recoveredTurn.trace : [];
    const recoveredTraceTypes = new Set(recoveredTrace.map((event) => event.type));
    sendResult = {
      ok: true,
      marker,
      message,
      browserEvalRecovered: true,
      browserEvalError: {
        message: error.message,
        stderr: String(error.detail?.stderr || "").slice(0, 800),
        stdout: String(error.detail?.stdout || "").slice(0, 800)
      },
      liveTurn: {
        ok: true,
        turnId: cleanString(recoveredTurn.turnId),
        status: cleanString(recoveredTurn.status)
      },
      liveProgress: {
        ok: true,
        turnId: cleanString(recoveredTurn.turnId),
        status: cleanString(recoveredTurn.status),
        trace: recoveredTrace,
        responses: recoveredResponses
      },
      liveText: {
        ok: true,
        turnId: cleanString(recoveredTurn.turnId),
        status: cleanString(recoveredTurn.status),
        trace: recoveredTrace,
        responses: recoveredResponses
      },
      observedLiveProgress: false,
      observedLiveTrace: false,
      observedPersistedProgress: providers.some((provider) =>
        recoveredResponses.some((response) => response.provider === provider && response.status && response.status !== "waiting")
      ),
      observedPersistedTrace:
        recoveredTraceTypes.has("turn_started") &&
        providers.every((provider) =>
          recoveredTrace.some((event) => event.type === "provider_started" && event.provider === provider) &&
          recoveredTrace.some((event) => ["delta", "provider_done"].includes(event.type) && event.provider === provider)
        ),
      missingLiveTextProviders: [],
      missingLiveProviders: providers.filter((provider) => !recoveredResponses.some((response) => response.provider === provider))
    };
  }
  assert(sendResult.ok, "UI send did not start", sendResult);
  assert(
    sendResult.browserEvalRecovered === true ||
    sendResult.reusedExistingTurn === true || /^(Sent to|Streaming|Turn complete)\b/.test(String(sendResult.afterClickNotice || "")),
    "UI did not show sent, streaming, or completion feedback",
    sendResult
  );
  assert(sendResult.liveTurn?.ok, "UI did not render the sent turn immediately", sendResult);
  assert(!(sendResult.missingLiveProviders || []).length, "UI live turn is missing provider cards", sendResult);
  assert(
    sendResult.observedLiveProgress || sendResult.observedPersistedProgress,
    "UI did not show or persist provider progress",
    sendResult
  );
  assert(
    sendResult.observedLiveTrace || sendResult.observedPersistedTrace,
    "UI did not show or persist websocket trace",
    sendResult
  );
  const observedTurnId = cleanString(sendResult.liveText?.turnId || sendResult.liveProgress?.turnId || sendResult.liveTurn?.turnId);
  assert(observedTurnId, "UI did not expose a live turn id", sendResult);

  const persisted = recoveredPersisted || await waitForPersistedTurn({
    apiBase: apiBase.replace(/\/$/, ""),
    projectSlug,
    marker,
    turnId: observedTurnId,
    timeoutMs
  });
  assert(persisted.turn.turnId === observedTurnId, "persisted turn id does not match live UI turn id", {
    observedTurnId,
    persistedTurnId: persisted.turn.turnId,
    marker
  });
  const responses = new Map((persisted.turn.responses || []).map((response) => [response.provider, response]));
  const expectedPattern = cleanString(expectedText)
    ? new RegExp(cleanString(expectedText).replace(/[.*+?^${}()|[\]\\]/g, "\\$&"), "i")
    : null;
  for (const provider of providers) {
    const response = responses.get(provider);
    assert(response, `missing persisted UI response for ${provider}`, persisted.turn);
    assert(response.status === "done", `${provider} UI response did not finish`, response);
    assert(cleanString(response.text).length > 0, `${provider} UI response had no text`, response);
    assert(Number(response.streamedChars) > 0, `${provider} UI response missing streamed chars`, response);
    if (expectedPattern) {
      assert(expectedPattern.test(cleanString(response.text)), `${provider} UI response did not contain expected text`, {
        provider,
        expectedText,
        text: cleanString(response.text),
        turnId: persisted.turn.turnId
      });
    }
  }
  const persistedTrace = Array.isArray(persisted.turn.trace) ? persisted.turn.trace : [];
  const persistedTraceTypes = new Set(persistedTrace.map((event) => event.type));
  assert(persistedTraceTypes.has("turn_started"), "persisted turn trace is missing turn_started", persisted.turn);
  assert(persistedTraceTypes.has("turn_done"), "persisted turn trace is missing turn_done", persisted.turn);
  for (const provider of providers) {
    assert(
      persistedTrace.some((event) => event.type === "provider_started" && event.provider === provider),
      `persisted turn trace is missing provider_started for ${provider}`,
      persisted.turn
    );
    assert(
      persistedTrace.some((event) => ["delta", "provider_done"].includes(event.type) && event.provider === provider),
      `persisted turn trace is missing response event for ${provider}`,
      persisted.turn
    );
  }

  const renderResult = await agentBrowserEval({
    url,
    timeoutMs: Math.min(timeoutMs, 45_000),
    script: `
(async () => {
  const marker = ${JSON.stringify(marker)};
  const findTurn = () => Array.from(document.querySelectorAll('[data-testid="multimodel-turn"]')).find((turn) => turn.innerText.includes(marker));
  let matchingTurn = findTurn();
  const deadline = Date.now() + 20000;
  while (!matchingTurn && Date.now() < deadline) {
    await new Promise((resolve) => setTimeout(resolve, 250));
    matchingTurn = findTurn();
  }
  return JSON.stringify({
    ok: Boolean(matchingTurn),
    marker,
    turnId: matchingTurn?.getAttribute('data-turn-id') || '',
    status: matchingTurn?.getAttribute('data-turn-status') || '',
    trace: matchingTurn ? Array.from(matchingTurn.querySelectorAll('[data-testid="turn-live-trace"] span')).map((el) => ({
      type: el.getAttribute('data-event-type') || '',
      provider: el.getAttribute('data-event-provider') || '',
      text: el.innerText
    })) : [],
    responses: matchingTurn ? Array.from(matchingTurn.querySelectorAll('[data-testid="multimodel-response"]')).map((el) => ({
      provider: el.getAttribute('data-provider'),
      status: el.getAttribute('data-response-status'),
      transport: el.getAttribute('data-provider-transport') || '',
      deltaCount: Number(el.getAttribute('data-delta-count') || 0),
      streamedChars: Number(el.getAttribute('data-streamed-chars') || 0),
      evidence: Array.from(el.querySelectorAll('[data-testid="response-evidence"] span')).map((item) => item.innerText),
      text: el.innerText
    })) : []
  });
})()
`
  });
  assert(renderResult.ok, "persisted UI turn did not render after reload", renderResult);
  assert(renderResult.turnId === observedTurnId, "rendered turn id does not match live UI turn id", {
    observedTurnId,
    renderedTurnId: renderResult.turnId,
    marker
  });
  for (const provider of providers) {
    const response = (renderResult.responses || []).find((item) => item.provider === provider);
    assert(response, `rendered UI response missing for ${provider}`, renderResult);
    assert(response.status === "done", `rendered UI response not done for ${provider}`, response);
    assert(cleanString(response.transport), `rendered UI response missing transport evidence for ${provider}`, response);
    assert(Number(response.deltaCount) > 0, `rendered UI response missing delta count evidence for ${provider}`, response);
    assert(Number(response.streamedChars) > 0, `rendered UI response missing streamed chars evidence for ${provider}`, response);
    assert(Array.isArray(response.evidence) && response.evidence.length >= 4, `rendered UI response missing evidence chips for ${provider}`, response);
  }
  assert((renderResult.trace || []).some((event) => event.type === "turn_done"), "rendered UI turn missing real turn_done trace after reload", renderResult);
  assert((renderResult.trace || []).some((event) => event.type === "provider_done"), "rendered UI turn missing real provider_done trace after reload", renderResult);

  const activePayload = await waitForNoActiveTurns({
    apiBase: apiBase.replace(/\/$/, ""),
    projectSlug,
    timeoutMs: Math.min(45_000, Math.max(10_000, timeoutMs / 3))
  });
  assert((activePayload.count || 0) === 0, "active turns remained after UI send verification", activePayload);

  const result = {
    ok: true,
    projectSlug,
    marker,
    message,
    turnId: persisted.turn.turnId,
    providers,
    send: sendResult,
    liveProgress: sendResult.liveProgress,
    liveText: sendResult.liveText,
    persisted: (persisted.turn.responses || [])
      .filter((response) => providers.includes(response.provider))
      .map((response) => ({
        provider: response.provider,
        status: response.status,
        text: cleanString(response.text),
        firstDeltaMs: response.firstDeltaMs,
        deltaCount: response.deltaCount,
        streamedChars: response.streamedChars,
        durationMs: response.durationMs
      })),
    rendered: renderResult,
    activeTurns: activePayload.count,
    browserEvalRecovered: sendResult.browserEvalRecovered === true,
    browserEvalError: browserEvalError
      ? {
          message: browserEvalError.message,
          stderr: String(browserEvalError.detail?.stderr || "").slice(0, 800)
        }
      : null,
    verifiedAt: new Date().toISOString(),
    truthMode: sendResult.browserEvalRecovered === true
      ? "observed-browser-ui-send-persisted-rendered-after-cdp-recovery"
      : "observed-browser-ui-send-live-text-websocket-persisted-rendered"
  };
  if (recordKind) {
    await appendVerificationRecord(projectSlug, {
      schema: recordSchema,
      kind: recordKind,
      ...result,
      generatedAt: new Date().toISOString()
    });
  }
  return result;
}

if (import.meta.url === `file://${process.argv[1]}`) {
  const projectSlug = process.env.PROJECT_SLUG || process.argv[2] || "darwin-mfc";
  const providers = (process.env.PROVIDERS || process.argv[3] || "claude,codex,cursor")
    .split(",")
    .map((item) => item.trim())
    .filter(Boolean);
  const appBase = process.env.PROJECT_COCKPIT_APP_BASE || "http://127.0.0.1:4173";
  const apiBase = process.env.PROJECT_COCKPIT_API_BASE || "http://127.0.0.1:4370";
  const timeoutMs = Number(process.env.VERIFY_MULTIMODEL_TIMEOUT_MS || 180_000);
  const prompt = process.env.VERIFY_MULTIMODEL_MESSAGE || process.argv[4] || "Responda em uma palavra: vivo";
  const expectedText = process.env.VERIFY_MULTIMODEL_EXPECT_TEXT || "vivo";
  const requiredHistoryMarker = process.env.VERIFY_MULTIMODEL_REQUIRE_HISTORY_MARKER || "";
  try {
    const result = await verifyMultimodelUiSend({
      projectSlug,
      providers,
      appBase,
      apiBase,
      timeoutMs,
      prompt,
      expectedText,
      requiredHistoryMarker
    });
    console.log(JSON.stringify(result, null, 2));
  } catch (error) {
    console.error(JSON.stringify({
      ok: false,
      projectSlug,
      providers,
      error: error.message,
      detail: error.detail || null,
      truthMode: "verification-failed"
    }, null, 2));
    process.exit(1);
  } finally {
    await runShell("agent-browser close", { timeoutMs: 10_000 }).catch(() => {});
  }
}
