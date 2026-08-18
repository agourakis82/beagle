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
  // Nota avulsa: ele diz algo e ninguém responde. Toda a espinha de memória
  // pressupunha troca conversacional, e é justamente o formato mais provável de
  // um auto-relato — "peito apertado", "dormi mal" — dito às três da manhã sem
  // querer conversa.
  //
  // O turno do assistente é OMITIDO, nunca preenchido com vazio: um turno
  // fantasma do companion no histórico seria a voz da máquina entrando onde não
  // deve, que é o erro que a guarda de falante existe para impedir.
  if (!u) return null;
  return {
    source: "companion-personal",
    session_id: clean(sessionId) || "companion-default",
    turns: a
      ? [{ role: "user", content: u }, { role: "assistant", content: a }]
      : [{ role: "user", content: u }],
    tags: ["companion", "personal", "verbatim"],
    metadata: {
      space: "personal",
      client_time: clean(clientTime),
      timezone: clean(timezone),
    },
  };
}

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

/**
 * POST one provenance-tagged record to memory-pg-serve /capture_turn. Best-effort:
 * returns the {id, created} JSON, or null on any error/non-2xx (never throws — ingestion
 * must never affect the chat).
 * @param {{source_type:string, content:string, prov_actor?:string, prov_surface?:string,
 *          prov_derived_from?:string[], prov_confidence?:number, occurred_at?:string|null,
 *          metadata?:object}} rec
 */
export async function captureProvenanced(rec, { memoryPgUrl, fetchImpl = fetch, ingestToken, timeoutMs = 8000 } = {}) {
  const ctrl = new AbortController();
  const timer = setTimeout(() => ctrl.abort(), timeoutMs);
  try {
    const res = await fetchImpl(`${memoryPgUrl}/capture_turn`, {
      method: "POST",
      headers: {
        "content-type": "application/json",
        ...(ingestToken ? { authorization: `Bearer ${ingestToken}` } : {}),
      },
      body: JSON.stringify(rec),
      signal: ctrl.signal,
    });
    if (!res.ok) return null;
    return await res.json();
  } catch {
    return null;
  } finally {
    clearTimeout(timer);
  }
}

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

/**
 * A superfície de um turno DELE, nas quatro combinações possíveis.
 *
 * Proveniência é sobre COMO a alegação veio a ser acreditada, e as quatro não são a mesma
 * coisa: "digitou sozinho no widget" ≠ "respondeu ao companion" ≠ "falou". Sem a marca, um
 * turno falado entra no banco indistinguível de um digitado — foi o que se mediu em
 * 17-ago-2026: os 120 turnos dele via `companion-ios` carregavam só role, session_id e
 * space, e a modalidade se perdia na porta.
 *
 * ⚠️ O que isto NÃO é: falado e digitado não são canais epistemicamente independentes.
 * São o MESMO canal — auto-relato — em duas formas. Marcar a modalidade serve para
 * auditar e para estratificar, nunca para contar como corroboração. A independência que a
 * Fase 2 exige vem do corpo, não do teclado.
 */
export function provSurfaceDoTurno({ spoken = false, standalone = false } = {}) {
  return `companion-ios${standalone ? "-nota" : ""}${spoken ? "-voz" : ""}`;
}

/**
 * Capture one personal exchange into the memory spine. Best-effort + fail-soft: any error
 * is swallowed (the chat reply has already gone to the user). Verbatim first (the transcript),
 * then the sovereign distill → atoms ingested with `distill` tags so recall ranks them.
 *
 * `spoken` marca que ELE falou, não que a máquina falou. O turno do assistente nunca leva a
 * marca: se o TTS leu a resposta em voz alta, isso é a boca do companion e não é evidência
 * nenhuma sobre ele.
 */
export async function ingestPersonalTurn({ sessionId, userText, assistantText, clientTime, timezone, spoken } = {}, deps = {}) {
  const {
    baseUrl = process.env.BEAGLE_INTERNAL_URL || "http://beagle-core.beagle.svc.cluster.local:8080",
    routerUrl = process.env.PROJECT_COCKPIT_LITELLM_ROUTER_URL || "http://router.llm-router.svc.cluster.local:4000",
    model = process.env.PROJECT_COCKPIT_DISTILL_MODEL || "qwen2.5-14b",
    memoryPgUrl = process.env.MEMORY_PG_QUERY_URL || "http://memory-pg-serve.beagle.svc.cluster.local",
    ingestToken = process.env.MEMORY_PG_INGEST_TOKEN,
    fetchImpl = fetch,
    tokenFn,
    distillFn = distillSalient,
    captureFn = captureProvenanced,
  } = deps;
  try {
    const verbatim = buildVerbatimPayload({ sessionId, userText, assistantText, clientTime, timezone });
    if (!verbatim) return;

    // occurred_at (A): stamp the exchange with the user's local moment (falls back to now).
    // Without this the turn lands with NULL occurred_at and is invisible to any recency /
    // temporal recall — only semantic search could ever surface it. captureFn passes this
    // straight through to the record row.
    let occurredAt;
    try { occurredAt = clientTime ? new Date(clientTime).toISOString() : new Date().toISOString(); }
    catch { occurredAt = new Date().toISOString(); }

    // Nota avulsa não se destila. Destilar "peito apertado" produziria um átomo
    // `model_distilled` que é a máquina parafraseando três palavras — ruído com
    // aparência de conhecimento, e um segundo registro sobre o mesmo evento que
    // não é modalidade nova nenhuma.
    const atoms = clean(assistantText)
      ? await distillFn({ userText, assistantText }, { routerUrl, model, fetchImpl })
      : [];

    // PROVENANCE FIRST. The user/assistant turns are written to the canonical store
    // (memory-pg) with provenance BEFORE the beagle-core path, which (synchronously)
    // dual-writes the same content as untagged model_generated. captureRecord dedups on
    // content hash with ON CONFLICT DO NOTHING — it cannot UPGRADE provenance — so whoever
    // writes first wins. Writing the tagged version first makes the user turn authoritative
    // as user_stated, so the distilled atoms that link to it are NOT orphaned.
    const capDeps = { memoryPgUrl, fetchImpl, ingestToken };
    const u = clean(userText), a = clean(assistantText);
    const sid = verbatim.session_id;
    let userId = null;
    if (u) {
      const r = await captureFn(
        // A superfície distingue nota de turno de chat e falado de digitado.
        { source_type: "ConversationPassage", content: u, prov_actor: "user_stated",
          prov_surface: provSurfaceDoTurno({ spoken: spoken === true, standalone: !a }),
          prov_confidence: 1.0, occurred_at: occurredAt,
          metadata: { space: "personal", session_id: sid, role: "user",
                      standalone: a ? undefined : true,
                      spoken: spoken === true ? true : undefined } },
        capDeps,
      );
      userId = r && r.id ? r.id : null;
    }
    if (a) {
      await captureFn(
        { source_type: "ConversationPassage", content: a, prov_actor: "model_generated",
          prov_surface: "companion-ios", occurred_at: occurredAt,
          metadata: { space: "personal", session_id: sid, role: "assistant" } },
        capDeps,
      );
    }
    for (const atom of atoms) {
      await captureFn(
        { source_type: "MemoryAtom", content: atom, prov_actor: "model_distilled",
          prov_surface: "companion-ios", occurred_at: occurredAt,
          prov_derived_from: userId ? [userId] : [],
          metadata: { space: "personal", session_id: sid, kind: "distill" } },
        capDeps,
      );
    }

    // THEN the beagle-core path (feeds the Claude Desktop bridge). Its memory-pg
    // dual-write now dedups against the already-provenance-tagged records above.
    await ingestVerbatim(verbatim, { baseUrl, fetchImpl, tokenFn });
    if (atoms.length) {
      await ingestVerbatim({
        source: "companion-personal",
        session_id: verbatim.session_id,
        turns: atoms.map((aa) => ({ role: "assistant", content: aa })),
        tags: ["companion", "personal", "distill"],
        metadata: { space: "personal", client_time: clean(clientTime), timezone: clean(timezone) },
      }, { baseUrl, fetchImpl, tokenFn });
    }
  } catch {
    // fail-soft — ingestion must never affect the chat
  }
}

/**
 * Handler core for POST /api/mobile/v1/ingest — flushes one queued offline turn into the spine.
 * Returns {status, body}. ingestPersonalTurn is fire-and-forget; we ack 202 immediately.
 */
export async function handleIngestRequest(body = {}, { ingestFn = ingestPersonalTurn, tokenFn } = {}) {
  const userText = clean(body.userText || body.user_text);
  const assistantText = clean(body.assistantText || body.assistant_text);
  // `assistantText` passa a ser OPCIONAL: uma captura rápida do widget é uma nota
  // solta, e exigir o par fazia toda nota avulsa morrer num 400. Só `userText` é
  // obrigatório — sem ele não há o que capturar.
  if (!userText) return { status: 400, body: { error: "userText required" } };
  ingestFn({
    sessionId: clean(body.session_id || body.sessionId),
    userText, assistantText,
    clientTime: clean(body.clientTime || body.client_time),
    timezone: clean(body.timezone),
    // Estritamente `true`. Uma string "false" vinda do cliente é verdadeira em JS, e
    // marcar como falado um turno digitado corromperia a proveniência na direção que
    // mais importa: seria a máquina afirmando algo sobre COMO ele se expressou.
    spoken: body.spoken === true || body.spoken === "true",
  }, { tokenFn }).catch(() => {});
  return { status: 202, body: { status: "accepted" } };
}
