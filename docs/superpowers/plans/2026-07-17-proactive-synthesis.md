# Proactive Synthesis Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A deliberate, on-demand endpoint that synthesizes the user's own recorded thinking (optionally scoped to a topic) into a streamed 5-block markdown map that helps him articulate — without ever touching the intimate chat.

**Architecture:** A new `POST /api/mobile/v1/synthesize` route in project-cockpit that reuses read-only recall helpers + the streaming router client, but is a fully separate surface from `/chat`. Two pure units (gather material, build prompt) are unit-tested; the thin streaming handler is live-verified. A tiny memory-pg `/recent_trusted` endpoint provides the no-topic recency source.

**Tech Stack:** Node ESM (project-cockpit server, `node:test`), memory-pg (Node + pg + ParadeDB), LiteLLM router (`streamChatViaRouter`), kaniko builds, k8s.

## Global Constraints

THE HARD WALL — every task inherits these; any step that weakens one is a defect, copied verbatim from the spec (`docs/superpowers/specs/2026-07-17-proactive-synthesis-design.md`):
- **`/chat` is untouched** — synthesis is a SEPARATE route; the chat route, `completeChatRequest`, its persona/register/streaming are modified by ZERO lines.
- **Never automatic** — synthesis fires only on an explicit `POST /synthesize`; never mid-conversation, never unprompted.
- **Isolated register** — the synthesis system prompt + output live ONLY in `synthesize.mjs`/the route; they never flow into chat.
- **Output is not captured as his memory** — the route writes NOTHING to memory-pg; no capture call anywhere in the synthesis path.
- **Provenance integrity** — synthesize ONLY from the recalled material; incomplete thread → name under `## Perguntas abertas`, NEVER invent; background material is exploration/hypothesis, never asserted as his fact; insufficient material → honest message, not confabulation.
- Branch: `reconcile/unify-beagle`. Language: PT-BR user-facing copy, his register (elevado, rigoroso, "você").

---

### Task 1: memory-pg `/recent_trusted` endpoint (no-topic recency source)

The no-topic synthesis path needs his RECENT trusted records by recency. The existing
`/recent` requires a `surface` and filters `prov_surface` — wrong fit. Add a small
recency query over trusted records, as a testable src function + a thin route.

**Files:**
- Create: `apps/memory-pg/src/recent.mjs`
- Modify: `apps/memory-pg/bin/serve.mjs` (add the route next to `/recent`, ~line 114)
- Test: `apps/memory-pg/test/recent-trusted.test.mjs`

**Interfaces:**
- Produces: `recentTrusted(pool, { windowDays?: number, limit?: number }): Promise<Array<{text, source_type, occurred_at, trust_tier}>>` and `GET /recent_trusted?window_days=N&limit=M` returning `{ ok, results }`.

- [ ] **Step 1: Write the failing test** (`apps/memory-pg/test/recent-trusted.test.mjs`)

```js
// recentTrusted: recent non-unverified records by recency, within a day window.
import { test, before, beforeEach, after } from "node:test";
import assert from "node:assert/strict";
import { makePool, ensureSchema } from "../src/db.mjs";
import { recentTrusted } from "../src/recent.mjs";

const DSN = process.env.MEMORY_PG_TEST_DSN;
if (!DSN) throw new Error("MEMORY_PG_TEST_DSN must be set (scratch DSN)");
if (!/\/[^/]*test[^/]*$/i.test(DSN)) throw new Error("Refusing: DSN name must contain 'test'");
const pool = makePool(DSN);

async function seed({ text, tier, ageDays }) {
  await pool.query(
    `INSERT INTO records (source_type, content, content_sha256, trust_tier, occurred_at)
     VALUES ('T', $1, 'sha-'||gen_random_uuid()::text, $2, now() - ($3||' days')::interval)`,
    [text, tier, String(ageDays)]);
}

before(async () => { await ensureSchema(pool); });
beforeEach(async () => { await pool.query("TRUNCATE records CASCADE"); });
after(async () => { await pool.end(); });

test("returns recent trusted records, excludes unverified and out-of-window", async () => {
  await seed({ text: "his recent claimed thought", tier: "claimed", ageDays: 1 });
  await seed({ text: "recent model noise", tier: "unverified", ageDays: 1 });
  await seed({ text: "old claimed thought", tier: "claimed", ageDays: 30 });
  const rows = await recentTrusted(pool, { windowDays: 7, limit: 10 });
  assert.deepEqual(rows.map((r) => r.text), ["his recent claimed thought"]);
  assert.equal(rows[0].trust_tier, "claimed");
});

test("orders by recency (newest first) and respects limit", async () => {
  await seed({ text: "older", tier: "claimed", ageDays: 3 });
  await seed({ text: "newer", tier: "corroborated", ageDays: 1 });
  const rows = await recentTrusted(pool, { windowDays: 7, limit: 1 });
  assert.deepEqual(rows.map((r) => r.text), ["newer"]);
});
```

- [ ] **Step 2: Run test to verify it fails**

Run (scratch DB must exist w/ schema — see Task 6 setup, or reuse `memory_test`):
`cd apps/memory-pg && MEMORY_PG_TEST_DSN="$SCRATCH_DSN" node --test test/recent-trusted.test.mjs`
Expected: FAIL — `Cannot find module '../src/recent.mjs'`.

- [ ] **Step 3: Write the implementation** (`apps/memory-pg/src/recent.mjs`)

```js
// recent.mjs — recency-ordered pull of his TRUSTED records, for the no-topic
// synthesis path. Recall (/query) is semantic and needs a query; this is the
// deterministic "what has he committed to record lately" source.
export async function recentTrusted(pool, { windowDays = 7, limit = 12 } = {}) {
  const days = Math.min(Math.max(Number(windowDays) || 7, 1), 90);
  const lim = Math.min(Math.max(Number(limit) || 12, 1), 50);
  const { rows } = await pool.query(
    `SELECT content, source_type, occurred_at, trust_tier
       FROM records
      WHERE trust_tier <> 'unverified'
        AND COALESCE(occurred_at, created_at) >= now() - ($1 || ' days')::interval
      ORDER BY COALESCE(occurred_at, created_at) DESC
      LIMIT $2`,
    [String(days), lim]);
  return rows.map((r) => ({
    text: r.content, source_type: r.source_type,
    occurred_at: r.occurred_at, trust_tier: r.trust_tier,
  }));
}
export default recentTrusted;
```

- [ ] **Step 4: Wire the route** (`apps/memory-pg/bin/serve.mjs`)

Add the import near the top with the other src imports:
```js
import { recentTrusted } from "../src/recent.mjs";
```
Add the route immediately after the existing `app.get("/recent", ...)` block:
```js
  // Recency-ordered pull of his TRUSTED records (trust_tier != unverified), within a
  // day window. Feeds the no-topic synthesis path (see project-cockpit /synthesize).
  app.get("/recent_trusted", async (req, res) => {
    if (!authed(req)) return res.status(401).json({ error: "unauthorized" });
    try {
      const results = await recentTrusted(pool, {
        windowDays: Number(req.query.window_days) || 7,
        limit: Number(req.query.limit) || 12,
      });
      res.json({ ok: true, results });
    } catch (e) {
      res.status(500).json({ error: String(e?.message || e) });
    }
  });
```

- [ ] **Step 5: Run test to verify it passes**

Run: `cd apps/memory-pg && MEMORY_PG_TEST_DSN="$SCRATCH_DSN" node --test test/recent-trusted.test.mjs`
Expected: PASS (2 tests).

- [ ] **Step 6: Run the full memory-pg suite (no regression)**

Run: `MEMORY_PG_TEST_DSN="$SCRATCH_DSN" BEAGLE_TEI_EMBED_URL="http://127.0.0.1:1" MEMORY_PG_RERANK_URL="http://127.0.0.1:1" node --test --test-concurrency=1 test/`
Expected: `# fail 0`.

- [ ] **Step 7: Commit**

```bash
git add apps/memory-pg/src/recent.mjs apps/memory-pg/bin/serve.mjs apps/memory-pg/test/recent-trusted.test.mjs
git commit -m "memory-pg: /recent_trusted — recency pull of trusted records for no-topic synthesis"
```

---

### Task 2: cockpit `fetchRecentTrusted` recall helper

A fail-soft client for `/recent_trusted`, mirroring `fetchRecentMemories`.

**Files:**
- Modify: `apps/project-cockpit/server/auth-bridge.mjs` (add near `fetchRecentMemories`, ~line 1080)
- Test: `apps/project-cockpit/server/auth-bridge.test.mjs` (append)

**Interfaces:**
- Consumes: memory-pg `GET /recent_trusted` (Task 1).
- Produces: `fetchRecentTrusted({ baseUrl?, token?, windowDays?, limit?, timeoutMs?, fetchImpl? }): Promise<Array<{text, source_type, occurred_at, trust_tier}>>` (exported).

- [ ] **Step 1: Write the failing test** (append to `auth-bridge.test.mjs`)

```js
import { fetchRecentTrusted } from "./auth-bridge.mjs";

test("fetchRecentTrusted GETs /recent_trusted with window+limit, returns results", async () => {
  let sentUrl = null;
  const stub = async (url) => { sentUrl = url; return { ok: true, json: async () => ({ results: [{ text: "a" }] }) }; };
  const out = await fetchRecentTrusted({ baseUrl: "http://x", windowDays: 5, limit: 9, fetchImpl: stub });
  assert.match(sentUrl, /\/recent_trusted\?window_days=5&limit=9/);
  assert.deepEqual(out, [{ text: "a" }]);
});

test("fetchRecentTrusted is fail-soft: empty array on error", async () => {
  const stub = async () => { throw new Error("down"); };
  assert.deepEqual(await fetchRecentTrusted({ baseUrl: "http://x", fetchImpl: stub }), []);
});
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd apps/project-cockpit && node --test --test-name-pattern="fetchRecentTrusted" server/auth-bridge.test.mjs`
Expected: FAIL — `fetchRecentTrusted` is not exported (import error).

- [ ] **Step 3: Write the implementation** (`auth-bridge.mjs`, right after `fetchRecentMemories`)

```js
export async function fetchRecentTrusted({
  baseUrl = process.env.MEMORY_PG_QUERY_URL || "http://memory-pg-serve.beagle.svc.cluster.local",
  token = process.env.MEMORY_PG_QUERY_TOKEN || "",
  windowDays = 7,
  limit = 12,
  timeoutMs = 6000,
  fetchImpl = fetch,
} = {}) {
  const ctrl = new AbortController();
  const timer = setTimeout(() => ctrl.abort(), timeoutMs);
  try {
    const headers = {};
    if (token) headers.authorization = `Bearer ${token}`;
    const res = await fetchImpl(
      `${baseUrl}/recent_trusted?window_days=${Number(windowDays) || 7}&limit=${Number(limit) || 12}`,
      { headers, signal: ctrl.signal });
    if (!res.ok) return [];
    const j = await res.json();
    return Array.isArray(j?.results) ? j.results : [];
  } catch {
    return [];
  } finally {
    clearTimeout(timer);
  }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `node --test --test-name-pattern="fetchRecentTrusted" server/auth-bridge.test.mjs`
Expected: PASS (2 tests). (Note: the pre-existing `fetchSounioState: returns latest` test is unrelated and already red — ignore it.)

- [ ] **Step 5: Commit**

```bash
git add apps/project-cockpit/server/auth-bridge.mjs apps/project-cockpit/server/auth-bridge.test.mjs
git commit -m "cockpit: fetchRecentTrusted client for memory-pg /recent_trusted"
```

---

### Task 3: `gatherSynthesisMaterial` (recall assembly)

**Files:**
- Create: `apps/project-cockpit/server/synthesize.mjs`
- Test: `apps/project-cockpit/server/synthesize.test.mjs`

**Interfaces:**
- Consumes (injected `deps`): `fetchRecentMemories(query,{k,trustedOnly})`, `fetchExocortexContext(query,{limit,personal}): Promise<string>`, `fetchRecentTrusted({windowDays,limit})`.
- Produces: `gatherSynthesisMaterial({ topic?, windowDays? }, deps): Promise<{ mode:"topic"|"recent", topic?:string, windowDays?:number, trustedWords:Array<{text}>, background:string }>`.

- [ ] **Step 1: Write the failing test** (`synthesize.test.mjs`)

```js
import { test } from "node:test";
import assert from "node:assert/strict";
import { gatherSynthesisMaterial } from "./synthesize.mjs";

function deps(overrides = {}) {
  return {
    fetchRecentMemories: async (q, opts) => { deps._mem = { q, opts }; return [{ text: "minha palavra" }]; },
    fetchExocortexContext: async (q, opts) => { deps._exo = { q, opts }; return "fundo"; },
    fetchRecentTrusted: async (opts) => { deps._recent = opts; return [{ text: "pensamento recente" }]; },
    ...overrides,
  };
}

test("topic mode: pulls his words with trustedOnly + background, returns topic shape", async () => {
  const d = deps();
  const m = await gatherSynthesisMaterial({ topic: "HSN", windowDays: 7 }, d);
  assert.equal(m.mode, "topic");
  assert.equal(m.topic, "HSN");
  assert.equal(deps._mem.opts.trustedOnly, true);
  assert.deepEqual(m.trustedWords, [{ text: "minha palavra" }]);
  assert.equal(m.background, "fundo");
});

test("no-topic mode: pulls recent trusted by window, no semantic recall", async () => {
  let memCalled = false;
  const d = deps({ fetchRecentMemories: async () => { memCalled = true; return []; } });
  const m = await gatherSynthesisMaterial({ windowDays: 5 }, d);
  assert.equal(m.mode, "recent");
  assert.equal(m.windowDays, 5);
  assert.equal(memCalled, false);
  assert.deepEqual(m.trustedWords, [{ text: "pensamento recente" }]);
});
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd apps/project-cockpit && node --test server/synthesize.test.mjs`
Expected: FAIL — `Cannot find module './synthesize.mjs'`.

- [ ] **Step 3: Write the implementation** (`synthesize.mjs`)

```js
// synthesize.mjs — the proactive-synthesis units. SEPARATE from chat (the hard wall):
// nothing here touches or is imported by the chat path. Pure/injected so it is tested
// without the cluster.

export async function gatherSynthesisMaterial({ topic, windowDays = 7 } = {}, deps) {
  const t = typeof topic === "string" ? topic.trim() : "";
  if (t) {
    const [trustedWords, background] = await Promise.all([
      deps.fetchRecentMemories(t, { k: 16, trustedOnly: true }),
      deps.fetchExocortexContext(t, { limit: 8, personal: true }),
    ]);
    return {
      mode: "topic", topic: t,
      trustedWords: Array.isArray(trustedWords) ? trustedWords : [],
      background: typeof background === "string" ? background : "",
    };
  }
  const recent = await deps.fetchRecentTrusted({ windowDays, limit: 20 });
  return {
    mode: "recent", windowDays,
    trustedWords: Array.isArray(recent) ? recent : [],
    background: "",
  };
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `node --test server/synthesize.test.mjs`
Expected: PASS (2 tests).

- [ ] **Step 5: Commit**

```bash
git add apps/project-cockpit/server/synthesize.mjs apps/project-cockpit/server/synthesize.test.mjs
git commit -m "cockpit: gatherSynthesisMaterial — recall assembly for synthesis (topic + recent)"
```

---

### Task 4: `buildSynthesisPrompt` (pure — the wall + provenance live here)

**Files:**
- Modify: `apps/project-cockpit/server/synthesize.mjs` (add function)
- Test: `apps/project-cockpit/server/synthesize.test.mjs` (append)

**Interfaces:**
- Consumes: the material object from Task 3.
- Produces: `buildSynthesisPrompt(material): { system:string, user:string, sufficient:boolean }`.

- [ ] **Step 1: Write the failing test** (append to `synthesize.test.mjs`)

```js
import { buildSynthesisPrompt } from "./synthesize.mjs";

test("buildSynthesisPrompt: system carries the 5-block contract + provenance rule", () => {
  const p = buildSynthesisPrompt({ mode: "topic", topic: "HSN", trustedWords: [{ text: "x" }], background: "" });
  assert.equal(p.sufficient, true);
  for (const h of ["## Elevator", "## Espinha", "## O que você circula", "## Perguntas abertas", "## Próximo movimento concreto"]) {
    assert.ok(p.system.includes(h), `missing block: ${h}`);
  }
  assert.match(p.system, /SOMENTE o material|NUNCA invente/);
  assert.match(p.user, /HSN/);
});

test("buildSynthesisPrompt: no material → insufficient (never confabulate)", () => {
  const p = buildSynthesisPrompt({ mode: "topic", topic: "algo", trustedWords: [], background: "" });
  assert.equal(p.sufficient, false);
});
```

- [ ] **Step 2: Run test to verify it fails**

Run: `node --test --test-name-pattern="buildSynthesisPrompt" server/synthesize.test.mjs`
Expected: FAIL — `buildSynthesisPrompt` is not exported.

- [ ] **Step 3: Write the implementation** (append to `synthesize.mjs`)

```js
export function buildSynthesisPrompt(material) {
  const words = Array.isArray(material?.trustedWords) ? material.trustedWords : [];
  const wordsBlock = words
    .map((r) => `- ${String(r?.text || "").replace(/\s+/g, " ").trim()}`)
    .filter((l) => l.length > 2)
    .join("\n");
  const background = typeof material?.background === "string" ? material.background.trim() : "";
  const sufficient = wordsBlock.length > 0 || background.length > 0;

  const system = [
    "Você sintetiza o pensamento REGISTRADO de Demetrios (MD+PhD) para ajudá-lo a se articular.",
    "REGRA INEGOCIÁVEL: use SOMENTE o material registrado abaixo. Onde o fio estiver incompleto,",
    "nomeie sob '## Perguntas abertas' — NUNCA invente para preencher. O 'Fundo' é",
    "exploração/hipótese ('você parece explorar…'), nunca afirmado como fato dele.",
    "Registro: elevado, rigoroso, simbólico; trate-o por 'você'.",
    "Escreva markdown com EXATAMENTE estes 5 blocos, nesta ordem e com estes títulos:",
    "## Elevator",
    "## Espinha",
    "## O que você circula / tensões",
    "## Perguntas abertas",
    "## Próximo movimento concreto",
  ].join("\n");

  const scope = material?.mode === "topic"
    ? `sobre "${material.topic}"`
    : `dos últimos ${material?.windowDays ?? 7} dias`;
  const user = sufficient
    ? `Sintetize meu pensamento ${scope}, a partir do meu registro:\n\n` +
      `### Minhas palavras (confiáveis)\n${wordsBlock || "(nenhuma)"}\n\n` +
      `### Fundo (exploração — não é fato meu)\n${background || "(nenhum)"}`
    : "";
  return { system, user, sufficient };
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `node --test server/synthesize.test.mjs`
Expected: PASS (4 tests total in the file).

- [ ] **Step 5: Commit**

```bash
git add apps/project-cockpit/server/synthesize.mjs apps/project-cockpit/server/synthesize.test.mjs
git commit -m "cockpit: buildSynthesisPrompt — 5-block markdown contract + provenance rule"
```

---

### Task 5: the `/api/mobile/v1/synthesize` streaming route

Thin orchestration: gather → prompt → stream. Mirrors the `/chat/stream` SSE shape.
The hard wall means this route is NEW and shares no behavior with chat.

**Files:**
- Modify: `apps/project-cockpit/server/mobile-routes.mjs` (add route inside `registerMobileRoutes`, near the other routes ~line 2085; add imports at top)

**Interfaces:**
- Consumes: `gatherSynthesisMaterial`, `buildSynthesisPrompt` (Tasks 3-4); `fetchRecentMemories`, `fetchExocortexContext`, `fetchRecentTrusted`, `streamChatViaRouter` (auth-bridge).

- [ ] **Step 1: Add imports** at the top of `mobile-routes.mjs`

Extend the existing `auth-bridge.mjs` import to include `streamChatViaRouter`, `fetchRecentTrusted`, `fetchExocortexContext` (if not already imported), and add:
```js
import { gatherSynthesisMaterial, buildSynthesisPrompt } from "./synthesize.mjs";
```
Define the synthesis model near the top-level consts:
```js
// Own model knob; defaults to the companion's voice model. The register is isolated
// by the PROMPT, not the model — the wall lives in synthesize.mjs, not here.
const SYNTHESIS_MODEL =
  process.env.PROJECT_COCKPIT_SYNTHESIS_MODEL ||
  process.env.PROJECT_COCKPIT_PERSONAL_VOICE_MODEL ||
  "claude-sonnet-5";
```

- [ ] **Step 2: Add the route** inside `registerMobileRoutes(app, deps)` (place next to `app.post("/api/mobile/v1/chat/stream", ...)`)

```js
  // Proactive synthesis — a SEPARATE, deliberate surface (see the hard wall in
  // docs/superpowers/specs/2026-07-17-proactive-synthesis-design.md). It never fires
  // unprompted, never touches /chat, and writes NOTHING to memory.
  app.post("/api/mobile/v1/synthesize", async (req, res) => {
    res.setHeader("Content-Type", "text/event-stream; charset=utf-8");
    res.setHeader("Cache-Control", "no-cache, no-transform");
    res.setHeader("Connection", "keep-alive");
    res.flushHeaders?.();
    const writeEvent = (p) => res.write(`data: ${JSON.stringify(p)}\n\n`);
    try {
      const topic = typeof req.body?.topic === "string" ? req.body.topic : "";
      const windowDays = Number(req.body?.windowDays) || 7;
      const material = await gatherSynthesisMaterial({ topic, windowDays }, {
        fetchRecentMemories,
        fetchExocortexContext,
        fetchRecentTrusted,
      });
      const { system, user, sufficient } = buildSynthesisPrompt(material);
      if (!sufficient) {
        writeEvent({ token: "Ainda não tenho o bastante registrado sobre isso pra sintetizar com verdade." });
        writeEvent({ done: true, insufficient: true, mode: material.mode });
        return res.end();
      }
      const result = await streamChatViaRouter({
        model: SYNTHESIS_MODEL,
        messages: [
          { role: "system", content: system },
          { role: "user", content: user },
        ],
        temperature: 0.6,
        onToken: (tok) => writeEvent({ token: tok }),
      });
      writeEvent({ done: true, mode: material.mode, model: result?.model || SYNTHESIS_MODEL });
      res.end();
    } catch (error) {
      writeEvent({ done: true, error: error?.message || "synthesize failed" });
      res.end();
    }
  });
```

- [ ] **Step 3: Static check — the route imports resolve and the file parses**

Run: `cd apps/project-cockpit && node --check server/mobile-routes.mjs && node --check server/synthesize.mjs`
Expected: no output (both parse).

- [ ] **Step 4: Run the cockpit unit tests (no regression in the tested units)**

Run: `node --test server/synthesize.test.mjs server/auth-bridge.test.mjs`
Expected: the synthesize (4) + fetchRecentTrusted (2) + fetchRecentMemories tests PASS. (The pre-existing `fetchSounioState: returns latest` failure is unrelated — ignore.)

- [ ] **Step 5: Commit**

```bash
git add apps/project-cockpit/server/mobile-routes.mjs
git commit -m "cockpit: POST /api/mobile/v1/synthesize — streaming markdown synthesis (separate from chat)"
```

---

### Task 6: build, deploy, live-verify, and WALL-CHECK

**Files:**
- Modify: `k8s/memory-pg/embed-worker-build-job.yaml`, `k8s/memory-pg/serve.yaml` (new tag)
- Modify: `k8s/project-cockpit/build-job.yaml`, `k8s/project-cockpit/deployment.yaml` (new ref/tag)

- [ ] **Step 1: Push all commits** so the kaniko clones see them

```bash
git push origin HEAD
NEWSHA=$(git rev-parse --short HEAD)
```

- [ ] **Step 2: Build + deploy memory-pg serve** (carries `/recent_trusted`)

Bump `k8s/memory-pg/embed-worker-build-job.yaml` destination to `memory-pg-embed-worker:p9-$NEWSHA` and `k8s/memory-pg/serve.yaml` image to the same. Then:
```bash
kubectl -n beagle delete job memory-pg-embed-worker-build --ignore-not-found
kubectl -n beagle apply -f k8s/memory-pg/embed-worker-build-job.yaml
# wait for job succeeded, then:
kubectl -n beagle apply -f k8s/memory-pg/serve.yaml
kubectl -n beagle rollout status deploy/memory-pg-serve --timeout=120s
```
Expected: rollout succeeds; `kubectl -n beagle exec <serve-pod> -- node -e '...GET /recent_trusted...'` returns `{ ok:true, results:[...] }`.

- [ ] **Step 3: Build + deploy project-cockpit** (carries the synthesize route)

Set `k8s/project-cockpit/build-job.yaml` `BEAGLE_GIT_REF` + `BEAGLE_IMAGE_TAG` to `$NEWSHA`/`reconcile-$NEWSHA`; bump `k8s/project-cockpit/deployment.yaml` image. Then:
```bash
kubectl -n beagle delete job project-cockpit-build --ignore-not-found
kubectl -n beagle apply -f k8s/project-cockpit/build-job.yaml
# wait for job succeeded (native build ~3-4 min), then:
kubectl -n beagle set image deployment/project-cockpit app=192.168.3.207:5003/project-cockpit:reconcile-$NEWSHA
kubectl -n beagle rollout status deploy/project-cockpit --timeout=180s
```
Expected: rollout succeeds; pod 1/1.

- [ ] **Step 4: Live-verify the synthesis** (from inside the cockpit pod, SSE)

```bash
POD=$(kubectl -n beagle get pods -l app=project-cockpit -o jsonpath='{.items[0].metadata.name}')
# topic path — expect streamed 5-block markdown grounded in his words:
kubectl -n beagle exec "$POD" -- sh -c 'curl -s -N -X POST http://127.0.0.1:$PORT/api/mobile/v1/synthesize -H "content-type: application/json" -d "{\"topic\":\"redes semânticas em depressão\"}"' | head -40
# insufficient path — a nonsense topic returns the honest message, NOT a synthesis:
kubectl -n beagle exec "$POD" -- sh -c 'curl -s -N -X POST http://127.0.0.1:$PORT/api/mobile/v1/synthesize -H "content-type: application/json" -d "{\"topic\":\"zxcqwv nonsense 9182\"}"' | head -5
```
Expected: topic → SSE `data: {"token":"## Elevator..."}` … `data: {"done":true,...}`; nonsense → the "Ainda não tenho o bastante…" token then done+insufficient.

- [ ] **Step 5: WALL-CHECK (the load-bearing verification)**

```bash
# (a) /chat behavior is byte-identical — no synthesis change touched the chat path:
git diff <base>..HEAD -- apps/project-cockpit/server/mobile-routes.mjs | grep -nE '^\+' | grep -iE 'chat|completeChatRequest|persona' || echo "OK: no chat-path additions"
# (b) the synthesis route captures NOTHING to memory:
grep -n 'capture\|/capture_turn\|ingestPersonal\|append' apps/project-cockpit/server/synthesize.mjs || echo "OK: synthesize.mjs writes no memory"
# (c) the synthesis system prompt lives ONLY in synthesize.mjs:
grep -rln 'Próximo movimento concreto\|sintetiza o pensamento' apps/project-cockpit/server/ | grep -v synthesize.mjs || echo "OK: register isolated to synthesize.mjs"
```
Expected: all three print their `OK:` line.

- [ ] **Step 6: Commit the deploy manifests**

```bash
git add k8s/memory-pg/embed-worker-build-job.yaml k8s/memory-pg/serve.yaml k8s/project-cockpit/build-job.yaml k8s/project-cockpit/deployment.yaml
git commit -m "deploy: proactive synthesis — memory-pg /recent_trusted + cockpit /synthesize"
git push origin HEAD
```

---

## Self-Review

**Spec coverage:** motivation → whole plan; hard wall (4 invariants) → Global Constraints + Task 5 comments + Task 6 Step 5 wall-check; approach (separate endpoint) → Task 5; gather (topic + recent) → Tasks 1-3; build prompt (5 blocks) → Task 4; provenance integrity → Task 4 (prompt) + Task 6 insufficient verify; streaming markdown → Task 5; error/fail-soft → Task 5 (try/catch + insufficient) & Tasks 1-2 (empty arrays); testing → Tasks 1-4 unit + Task 6 live; out-of-scope (iOS, cron, persistence) → not implemented. No gaps.

**Placeholder scan:** all steps carry real code, real commands, real expected output. `$NEWSHA`/`$SCRATCH_DSN`/`<base>` are runtime values the executor fills, not placeholders for logic.

**Type consistency:** `trustedWords: Array<{text}>` and `background: string` flow consistently from `gatherSynthesisMaterial` (Task 3) into `buildSynthesisPrompt` (Task 4). `fetchRecentTrusted` return shape `{text,...}` (Task 2) matches `recentTrusted` (Task 1) and the `trustedWords` consumed in Task 4. `{ system, user, sufficient }` produced in Task 4 is consumed exactly in Task 5.
