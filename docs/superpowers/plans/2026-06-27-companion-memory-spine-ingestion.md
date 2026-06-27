# Companion Memory Spine — Ingestion Loop Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Wire the cockpit so every personal-space companion exchange is durably written to the exocortex — verbatim (transcript/recall) and distilled into salient "atoms" — fire-and-forget, sovereignly, so the companion actually remembers what you tell it.

**Architecture:** A new self-contained module `memory-ingest.mjs` in project-cockpit. After the personal reply is produced in `mobile-routes.mjs`, it calls `ingestPersonalTurn(...)` detached. Verbatim → beagle-core `POST /api/memory/ingest_chat` (already persists passages + reindexes + dual-writes to memory-pg). Distill → a sovereign Spark LLM (`qwen2.5-14b` via the LiteLLM router) extracts 0–4 memorable atoms, which are ingested with `distill` tags. Everything is best-effort and must never block, delay, or fail the chat reply.

**Tech Stack:** Node ESM (`.mjs`), `node:test` + `node:assert`, Express (project-cockpit). beagle-core `/api/memory/ingest_chat` (Rust, payload `{source, session_id, turns:[{role,content,timestamp?}], tags, metadata}`). LiteLLM router (`${LITELLM_ROUTER_URL}/v1/chat/completions`, model `qwen2.5-14b` = sovereign DGX Spark). Reuses `fetchOperatorToken()` (exported from `auth-bridge.mjs`).

**Out of scope (separate plans):** the iOS offline routing + ingestion outbox (Swift/SwiftData subsystem); sessions UI; diary; timeline; search. This plan is the server-side ingestion loop only — it produces working, testable software on its own.

---

## File Structure

- **Create:** `apps/project-cockpit/server/memory-ingest.mjs` — the companion ingestion module. One responsibility: turn a personal exchange into exocortex writes. Pure helpers (`buildVerbatimPayload`, `buildDistillPrompt`, `parseDistillAtoms`) + IO functions (`ingestVerbatim`, `distillSalient`, `ingestPersonalTurn`) with injectable `fetchImpl`/`tokenFn` for tests.
- **Create:** `apps/project-cockpit/server/test/memory-ingest.test.mjs` — unit tests (no network; inject fakes).
- **Modify:** `apps/project-cockpit/server/mobile-routes.mjs` — import `ingestPersonalTurn`; call it fire-and-forget right after the personal `runMuseVoiceEnsemble` result.

---

### Task 1: Verbatim payload builder (pure)

**Files:**
- Create: `apps/project-cockpit/server/memory-ingest.mjs`
- Test: `apps/project-cockpit/server/test/memory-ingest.test.mjs`

- [ ] **Step 1: Write the failing test**

```javascript
import { test } from "node:test";
import assert from "node:assert/strict";
import { buildVerbatimPayload } from "../memory-ingest.mjs";

test("buildVerbatimPayload shapes a beagle-core ingest_chat session", () => {
  const p = buildVerbatimPayload({
    sessionId: "sess-1",
    userText: "amanhã tenho consulta às 9h",
    assistantText: "anotado, te lembro de manhã",
    clientTime: "2026-06-27T08:00:00Z",
    timezone: "America/Sao_Paulo",
  });
  assert.equal(p.source, "companion-personal");
  assert.equal(p.session_id, "sess-1");
  assert.deepEqual(p.turns, [
    { role: "user", content: "amanhã tenho consulta às 9h" },
    { role: "assistant", content: "anotado, te lembro de manhã" },
  ]);
  assert.deepEqual(p.tags, ["companion", "personal", "verbatim"]);
  assert.equal(p.metadata.space, "personal");
  assert.equal(p.metadata.client_time, "2026-06-27T08:00:00Z");
  assert.equal(p.metadata.timezone, "America/Sao_Paulo");
});

test("buildVerbatimPayload returns null when a side is empty", () => {
  assert.equal(buildVerbatimPayload({ sessionId: "s", userText: "", assistantText: "hi" }), null);
  assert.equal(buildVerbatimPayload({ sessionId: "s", userText: "hi", assistantText: "" }), null);
});
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd apps/project-cockpit && node --test test/memory-ingest.test.mjs`
Expected: FAIL — `Cannot find module '../memory-ingest.mjs'`.

- [ ] **Step 3: Write minimal implementation**

Create `apps/project-cockpit/server/memory-ingest.mjs`:

```javascript
// Companion memory spine — ingestion of personal-space exchanges into the exocortex.
// Verbatim (transcript/recall) + sovereign distilled "atoms". Best-effort, never blocks chat.

function clean(s) {
  return typeof s === "string" ? s.trim() : "";
}

/**
 * Build the beagle-core /api/memory/ingest_chat payload for one personal exchange.
 * Returns null if either side is empty (nothing worth a round trip).
 */
export function buildVerbatimPayload({ sessionId, userText, assistantText, clientTime, timezone } = {}) {
  const u = clean(userText);
  const a = clean(assistantText);
  if (!u || !a) return null;
  return {
    source: "companion-personal",
    session_id: clean(sessionId) || "companion-default",
    turns: [
      { role: "user", content: u },
      { role: "assistant", content: a },
    ],
    tags: ["companion", "personal", "verbatim"],
    metadata: {
      space: "personal",
      client_time: clean(clientTime),
      timezone: clean(timezone),
    },
  };
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd apps/project-cockpit && node --test test/memory-ingest.test.mjs`
Expected: PASS (2 tests).

- [ ] **Step 5: Commit**

```bash
git add apps/project-cockpit/server/memory-ingest.mjs apps/project-cockpit/server/test/memory-ingest.test.mjs
git commit -m "feat(companion): verbatim ingest payload builder"
```

---

### Task 2: Verbatim ingest IO (POST to beagle-core, best-effort)

**Files:**
- Modify: `apps/project-cockpit/server/memory-ingest.mjs`
- Test: `apps/project-cockpit/server/test/memory-ingest.test.mjs`

- [ ] **Step 1: Write the failing test**

```javascript
import { ingestVerbatim } from "../memory-ingest.mjs";

test("ingestVerbatim POSTs to beagle-core ingest_chat with operator auth", async () => {
  let captured = null;
  const fetchImpl = async (url, opts) => {
    captured = { url, opts };
    return { ok: true, status: 200, text: async () => '{"status":"ok"}' };
  };
  const tokenFn = async () => ({ token: "tok-123" });
  const payload = { source: "companion-personal", session_id: "s", turns: [], tags: [], metadata: {} };
  const ok = await ingestVerbatim(payload, { baseUrl: "http://beagle-core", fetchImpl, tokenFn });
  assert.equal(ok, true);
  assert.equal(captured.url, "http://beagle-core/api/memory/ingest_chat");
  assert.equal(captured.opts.method, "POST");
  assert.equal(captured.opts.headers.Authorization, "Bearer tok-123");
  assert.equal(captured.opts.headers["X-Beagle-Consumer"], "beagle-operator");
  assert.deepEqual(JSON.parse(captured.opts.body), payload);
});

test("ingestVerbatim is best-effort: returns false on error, never throws", async () => {
  const fetchImpl = async () => { throw new Error("network down"); };
  const tokenFn = async () => ({ token: "t" });
  const ok = await ingestVerbatim({ turns: [] }, { baseUrl: "http://x", fetchImpl, tokenFn });
  assert.equal(ok, false);
});

test("ingestVerbatim returns false when no token", async () => {
  const ok = await ingestVerbatim({ turns: [] }, {
    baseUrl: "http://x",
    fetchImpl: async () => ({ ok: true }),
    tokenFn: async () => ({ token: "", error: "no token" }),
  });
  assert.equal(ok, false);
});
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd apps/project-cockpit && node --test test/memory-ingest.test.mjs`
Expected: FAIL — `ingestVerbatim is not a function`.

- [ ] **Step 3: Write minimal implementation**

Append to `apps/project-cockpit/server/memory-ingest.mjs`:

```javascript
/**
 * POST a verbatim payload to beagle-core /api/memory/ingest_chat. Best-effort:
 * returns true on 2xx, false on any failure (never throws). beagle-core dedups
 * by content_hash, so re-posting the same payload is harmless.
 */
export async function ingestVerbatim(payload, { baseUrl, fetchImpl = fetch, tokenFn, timeoutMs = 8000 } = {}) {
  try {
    const tk = await tokenFn();
    if (!tk || !tk.token) return false;
    const ctrl = new AbortController();
    const timer = setTimeout(() => ctrl.abort(), timeoutMs);
    try {
      const res = await fetchImpl(`${baseUrl}/api/memory/ingest_chat`, {
        method: "POST",
        headers: {
          "content-type": "application/json",
          Accept: "application/json",
          Authorization: `Bearer ${tk.token}`,
          "X-Beagle-Consumer": "beagle-operator",
        },
        body: JSON.stringify(payload),
        signal: ctrl.signal,
      });
      return !!(res && res.ok);
    } finally {
      clearTimeout(timer);
    }
  } catch {
    return false;
  }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd apps/project-cockpit && node --test test/memory-ingest.test.mjs`
Expected: PASS (5 tests total).

- [ ] **Step 5: Commit**

```bash
git add apps/project-cockpit/server/memory-ingest.mjs apps/project-cockpit/server/test/memory-ingest.test.mjs
git commit -m "feat(companion): best-effort verbatim ingest to beagle-core"
```

---

### Task 3: Distill prompt + parser (pure, selective, []-by-default)

**Files:**
- Modify: `apps/project-cockpit/server/memory-ingest.mjs`
- Test: `apps/project-cockpit/server/test/memory-ingest.test.mjs`

- [ ] **Step 1: Write the failing test**

```javascript
import { buildDistillPrompt, parseDistillAtoms } from "../memory-ingest.mjs";

test("buildDistillPrompt instructs []-by-default selective extraction", () => {
  const p = buildDistillPrompt({ userText: "oi", assistantText: "ola!" });
  assert.match(p, /\[\]/);                 // mentions empty-array default
  assert.match(p, /oi/);                   // includes the exchange
  assert.match(p, /ola!/);
});

test("parseDistillAtoms reads a JSON array of strings", () => {
  assert.deepEqual(parseDistillAtoms('["consulta amanhã 9h","prefere chá a café"]'),
    ["consulta amanhã 9h", "prefere chá a café"]);
});

test("parseDistillAtoms tolerates prose-wrapped JSON and caps at 4", () => {
  const out = parseDistillAtoms('claro:\n["a","b","c","d","e","f"]\nfim');
  assert.deepEqual(out, ["a", "b", "c", "d"]);
});

test("parseDistillAtoms returns [] for junk / empty / non-array", () => {
  assert.deepEqual(parseDistillAtoms("[]"), []);
  assert.deepEqual(parseDistillAtoms("não sei"), []);
  assert.deepEqual(parseDistillAtoms('{"x":1}'), []);
  assert.deepEqual(parseDistillAtoms(""), []);
});
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd apps/project-cockpit && node --test test/memory-ingest.test.mjs`
Expected: FAIL — `buildDistillPrompt is not a function`.

- [ ] **Step 3: Write minimal implementation**

Append to `apps/project-cockpit/server/memory-ingest.mjs`:

```javascript
const MAX_ATOMS = 4;

/** Selective extraction prompt. The model returns [] for smalltalk (the common case). */
export function buildDistillPrompt({ userText, assistantText }) {
  return (
    "Você é a camada de memória de um companheiro pessoal. Da troca abaixo, extraia de 0 a 4 " +
    "ATOMOS que valham lembrar a LONGO PRAZO sobre o usuário: fatos, decisões, compromissos, " +
    "preferências, sentimentos importantes. NÃO inclua saudações ou conversa fiada. Cada átomo = " +
    "uma frase curta, na voz do usuário. Responda APENAS um array JSON de strings. Se não houver " +
    "nada que valha guardar, responda exatamente [].\n\n" +
    `USUÁRIO: ${clean(userText)}\nCOMPANION: ${clean(assistantText)}\n\nATOMOS (JSON):`
  );
}

/** Parse the model output into at most MAX_ATOMS non-empty strings; [] on anything odd. */
export function parseDistillAtoms(text) {
  const s = clean(text);
  if (!s) return [];
  const start = s.indexOf("[");
  const end = s.lastIndexOf("]");
  if (start === -1 || end === -1 || end < start) return [];
  let arr;
  try {
    arr = JSON.parse(s.slice(start, end + 1));
  } catch {
    return [];
  }
  if (!Array.isArray(arr)) return [];
  return arr.map((x) => clean(x)).filter(Boolean).slice(0, MAX_ATOMS);
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd apps/project-cockpit && node --test test/memory-ingest.test.mjs`
Expected: PASS (9 tests total).

- [ ] **Step 5: Commit**

```bash
git add apps/project-cockpit/server/memory-ingest.mjs apps/project-cockpit/server/test/memory-ingest.test.mjs
git commit -m "feat(companion): distill prompt + selective atom parser"
```

---

### Task 4: Distill IO (sovereign Spark LLM call)

**Files:**
- Modify: `apps/project-cockpit/server/memory-ingest.mjs`
- Test: `apps/project-cockpit/server/test/memory-ingest.test.mjs`

- [ ] **Step 1: Write the failing test**

```javascript
import { distillSalient } from "../memory-ingest.mjs";

test("distillSalient calls the sovereign model and returns atoms", async () => {
  let captured = null;
  const fetchImpl = async (url, opts) => {
    captured = { url, body: JSON.parse(opts.body) };
    return { ok: true, json: async () => ({ choices: [{ message: { content: '["consulta 9h"]' } }] }) };
  };
  const atoms = await distillSalient(
    { userText: "consulta amanhã 9h", assistantText: "anotado" },
    { routerUrl: "http://router:4000", model: "qwen2.5-14b", fetchImpl });
  assert.deepEqual(atoms, ["consulta 9h"]);
  assert.equal(captured.url, "http://router:4000/v1/chat/completions");
  assert.equal(captured.body.model, "qwen2.5-14b");           // sovereign Spark
});

test("distillSalient returns [] on error (best-effort)", async () => {
  const fetchImpl = async () => { throw new Error("spark down"); };
  const atoms = await distillSalient({ userText: "x", assistantText: "y" },
    { routerUrl: "http://r", model: "qwen2.5-14b", fetchImpl });
  assert.deepEqual(atoms, []);
});
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd apps/project-cockpit && node --test test/memory-ingest.test.mjs`
Expected: FAIL — `distillSalient is not a function`.

- [ ] **Step 3: Write minimal implementation**

Append to `apps/project-cockpit/server/memory-ingest.mjs`:

```javascript
/**
 * Run the sovereign distill pass on one exchange. Returns up to MAX_ATOMS atom strings,
 * or [] (the common case for smalltalk, and on any error). Never throws.
 */
export async function distillSalient({ userText, assistantText }, { routerUrl, model = "qwen2.5-14b", fetchImpl = fetch, timeoutMs = 20000 } = {}) {
  try {
    const ctrl = new AbortController();
    const timer = setTimeout(() => ctrl.abort(), timeoutMs);
    try {
      const res = await fetchImpl(`${routerUrl}/v1/chat/completions`, {
        method: "POST",
        headers: { "content-type": "application/json" },
        body: JSON.stringify({
          model,
          messages: [{ role: "user", content: buildDistillPrompt({ userText, assistantText }) }],
          temperature: 0.2,
          max_tokens: 400,
        }),
        signal: ctrl.signal,
      });
      if (!res || !res.ok) return [];
      const j = await res.json();
      const content = j?.choices?.[0]?.message?.content || "";
      return parseDistillAtoms(content);
    } finally {
      clearTimeout(timer);
    }
  } catch {
    return [];
  }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd apps/project-cockpit && node --test test/memory-ingest.test.mjs`
Expected: PASS (11 tests total).

- [ ] **Step 5: Commit**

```bash
git add apps/project-cockpit/server/memory-ingest.mjs apps/project-cockpit/server/test/memory-ingest.test.mjs
git commit -m "feat(companion): sovereign Spark distill IO"
```

---

### Task 5: Orchestrator `ingestPersonalTurn` (verbatim + distill, fail-soft)

**Files:**
- Modify: `apps/project-cockpit/server/memory-ingest.mjs`
- Test: `apps/project-cockpit/server/test/memory-ingest.test.mjs`

- [ ] **Step 1: Write the failing test**

```javascript
import { ingestPersonalTurn } from "../memory-ingest.mjs";

test("ingestPersonalTurn ingests verbatim then distilled atoms", async () => {
  const posted = [];
  const deps = {
    baseUrl: "http://bc",
    routerUrl: "http://rt",
    model: "qwen2.5-14b",
    tokenFn: async () => ({ token: "t" }),
    fetchImpl: async (url, opts) => {
      if (url.endsWith("/api/memory/ingest_chat")) {
        posted.push(JSON.parse(opts.body));
        return { ok: true, status: 200, text: async () => "ok" };
      }
      // router distill
      return { ok: true, json: async () => ({ choices: [{ message: { content: '["fato X"]' } }] }) };
    },
  };
  await ingestPersonalTurn(
    { sessionId: "s1", userText: "guarda o fato X", assistantText: "guardado" }, deps);
  // 1 verbatim + 1 distill ingest
  const verb = posted.find((p) => p.tags.includes("verbatim"));
  const dist = posted.find((p) => p.tags.includes("distill"));
  assert.ok(verb, "verbatim ingested");
  assert.ok(dist, "distill ingested");
  assert.equal(dist.turns[0].content, "fato X");
});

test("ingestPersonalTurn never throws even if everything fails", async () => {
  await ingestPersonalTurn(
    { sessionId: "s", userText: "a", assistantText: "b" },
    { baseUrl: "http://x", routerUrl: "http://y", tokenFn: async () => { throw new Error("boom"); },
      fetchImpl: async () => { throw new Error("boom"); } });
  assert.ok(true); // reached here = did not throw
});

test("ingestPersonalTurn skips when a side is empty (no posts)", async () => {
  let calls = 0;
  await ingestPersonalTurn({ sessionId: "s", userText: "", assistantText: "b" },
    { baseUrl: "http://x", routerUrl: "http://y", tokenFn: async () => ({ token: "t" }),
      fetchImpl: async () => { calls++; return { ok: true }; } });
  assert.equal(calls, 0);
});
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd apps/project-cockpit && node --test test/memory-ingest.test.mjs`
Expected: FAIL — `ingestPersonalTurn is not a function`.

- [ ] **Step 3: Write minimal implementation**

Append to `apps/project-cockpit/server/memory-ingest.mjs`:

```javascript
/**
 * Capture one personal exchange into the memory spine. Best-effort + fail-soft: any error
 * is swallowed (the chat reply has already gone to the user). Verbatim first (the transcript),
 * then the sovereign distill → atoms ingested with `distill` tags so recall ranks them.
 */
export async function ingestPersonalTurn({ sessionId, userText, assistantText, clientTime, timezone } = {}, deps = {}) {
  const {
    baseUrl = process.env.BEAGLE_INTERNAL_URL || "http://beagle-core.beagle.svc.cluster.local:8080",
    routerUrl = process.env.PROJECT_COCKPIT_LITELLM_ROUTER_URL || "http://router.llm-router.svc.cluster.local:4000",
    model = process.env.PROJECT_COCKPIT_DISTILL_MODEL || "qwen2.5-14b",
    fetchImpl = fetch,
    tokenFn,
  } = deps;
  try {
    const verbatim = buildVerbatimPayload({ sessionId, userText, assistantText, clientTime, timezone });
    if (!verbatim) return;
    await ingestVerbatim(verbatim, { baseUrl, fetchImpl, tokenFn });

    const atoms = await distillSalient({ userText, assistantText }, { routerUrl, model, fetchImpl });
    if (atoms.length) {
      await ingestVerbatim({
        source: "companion-personal",
        session_id: verbatim.session_id,
        turns: atoms.map((a) => ({ role: "assistant", content: a })),
        tags: ["companion", "personal", "distill"],
        metadata: { space: "personal", client_time: clean(clientTime), timezone: clean(timezone) },
      }, { baseUrl, fetchImpl, tokenFn });
    }
  } catch {
    // fail-soft — ingestion must never affect the chat
  }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd apps/project-cockpit && node --test test/memory-ingest.test.mjs`
Expected: PASS (14 tests total).

- [ ] **Step 5: Commit**

```bash
git add apps/project-cockpit/server/memory-ingest.mjs apps/project-cockpit/server/test/memory-ingest.test.mjs
git commit -m "feat(companion): ingestPersonalTurn orchestrator (verbatim + distill, fail-soft)"
```

---

### Task 6: Wire into the personal chat handler (fire-and-forget)

**Files:**
- Modify: `apps/project-cockpit/server/mobile-routes.mjs` (the `chatSpace === "personal"` branch, after `runMuseVoiceEnsemble`)
- Test: `apps/project-cockpit/server/test/memory-ingest-wire.test.mjs`

- [ ] **Step 1: Write the failing test**

The wiring is a one-liner; assert the default-deps `ingestPersonalTurn` exists and is callable with the real arg shape (smoke), and that calling it fire-and-forget with a throwing tokenFn does not reject — guarding the "never blocks chat" contract at the call site.

Create `apps/project-cockpit/server/test/memory-ingest-wire.test.mjs`:

```javascript
import { test } from "node:test";
import assert from "node:assert/strict";
import { ingestPersonalTurn } from "../memory-ingest.mjs";

test("fire-and-forget call shape resolves without throwing", async () => {
  // mirrors the mobile-routes call site: detached, swallowed
  await assert.doesNotReject(
    ingestPersonalTurn(
      { sessionId: "s", userText: "oi", assistantText: "olá", clientTime: "", timezone: "UTC" },
      { tokenFn: async () => ({ token: "", error: "x" }), fetchImpl: async () => ({ ok: false }) }
    )
  );
});
```

- [ ] **Step 2: Run test to verify it passes (it should — proves the contract)**

Run: `cd apps/project-cockpit && node --test test/memory-ingest-wire.test.mjs`
Expected: PASS. (This is a guard test for the call-site contract; it passes against the Task 5 code.)

- [ ] **Step 3: Add the wiring in `mobile-routes.mjs`**

At the top of `mobile-routes.mjs`, add to the existing import from `./auth-bridge.mjs` is NOT needed; add a new import line near the other imports:

```javascript
import { ingestPersonalTurn } from "./memory-ingest.mjs";
```

Then, in the personal branch (right after `result = await runMuseVoiceEnsemble({...});`), insert:

```javascript
  if (chatSpace === "personal") {
    appliedDiscussionProfile = "personal-ensemble";
    result = await runMuseVoiceEnsemble({
      prompt,
      system: effectiveSystem,
      voiceModel: cleanString(req.body?.voiceModel || req.body?.voice_model)
        || cleanString(process.env.PROJECT_COCKPIT_PERSONAL_VOICE_MODEL)
        || "glm-5.1",
      onToken
    });
    // Memory spine: capture this exchange into the exocortex. Fire-and-forget — the reply
    // is already on its way to the user; ingestion must never block or fail the chat.
    ingestPersonalTurn({
      sessionId: cleanString(req.body?.session_id || req.body?.sessionId),
      userText: prompt,
      assistantText: cleanString(result?.payload?.text || result?.payload?.answer || result?.payload?.response),
      clientTime: cleanString(req.body?.clientTime),
      timezone: cleanString(req.body?.timezone),
      tokenFn: fetchOperatorToken,
    }).catch(() => {});
  } else {
```

Note: `fetchOperatorToken` must be imported in `mobile-routes.mjs` — confirm it is in the existing `import { ... } from "./auth-bridge.mjs"` list; if not, add it.

- [ ] **Step 4: Verify syntax + the wire test still passes**

Run: `cd apps/project-cockpit && node --check server/mobile-routes.mjs && node --test test/memory-ingest-wire.test.mjs`
Expected: no syntax error; PASS.

- [ ] **Step 5: Commit**

```bash
git add apps/project-cockpit/server/mobile-routes.mjs apps/project-cockpit/server/test/memory-ingest-wire.test.mjs
git commit -m "feat(companion): wire ingestPersonalTurn into personal chat (fire-and-forget)"
```

---

### Task 7: Full suite green + deploy note

**Files:** none (verification)

- [ ] **Step 1: Run the whole cockpit test suite**

Run: `cd apps/project-cockpit && node --test test/`
Expected: all tests PASS, including the existing ones.

- [ ] **Step 2: Syntax-check the touched server files**

Run: `cd apps/project-cockpit && node --check server/memory-ingest.mjs && node --check server/mobile-routes.mjs`
Expected: no output (clean).

- [ ] **Step 3: Record the deploy step (not executed by this plan)**

The cockpit must be rebuilt + rolled (kaniko build-job off this branch → `kubectl set image deploy/project-cockpit`) for the loop to go live. The distill model env `PROJECT_COCKPIT_DISTILL_MODEL` defaults to `qwen2.5-14b` (sovereign Spark) — no new secret needed. Verify post-deploy: send a personal message containing a distinct fact, then `fetchRecentMemories` (or the recall path) surfaces it on the next turn.

---

## Self-Review

**Spec coverage:** verbatim layer (Tasks 1–2, 6) ✓ · sovereign distill (Tasks 3–4) ✓ · selective `[]`-default noise guard (Task 3) ✓ · fire-and-forget/fail-soft (Tasks 2,4,5,6) ✓ · idempotency relies on beagle-core `content_hash` (noted) ✓ · sovereignty: distill on `qwen2.5-14b` Spark, writes in-cluster (Task 4) ✓ · session_id passed through (Tasks 1,6) ✓. Offline outbox + sessions/diary/timeline/search are explicitly out of scope (separate plans). No gaps for the ingestion-loop scope.

**Placeholder scan:** every code step has complete code; no TBD/TODO; commands have expected output. ✓

**Type consistency:** `buildVerbatimPayload`/`ingestVerbatim`/`buildDistillPrompt`/`parseDistillAtoms`/`distillSalient`/`ingestPersonalTurn` names + `{role,content}` turn shape + `{token}` token result are used identically across tasks. ✓
