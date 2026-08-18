// self-report-presente.test.mjs — auto-relato no presente nao pode ser descartado
// por nao trazer hora.
//
// Medido em producao: dos 84 turnos DELE ja extraidos, 52 renderam ZERO fatos.
// A amostra explica:
//
//   07-16 01:45  "Estou irritado com voce"   <- auto-relato de arousal, com hora
//                                               no registro, descartado
//   08-02 21:05  "Como voce esta agora?"
//
// Os turnos dele tem 25 caracteres em media (o companion tem 264), e uma frase
// dessas nunca diz "quando". O prompt mandava omitir o fato sem hora explicita —
// regra certa para fato sobre o mundo, errada para auto-relato: quando o sujeito
// fala de si NO PRESENTE, o instante da fala E o instante do estado.
//
// A sutileza que a regra precisa preservar: no PASSADO sem data ("semana passada
// dormi mal"), deixar a hora em branco seria pior que descartar — o fallback
// carimbaria o instante da fala e arquivaria o sono da semana passada sob hoje.

import { test, before, beforeEach, after } from "node:test";
import assert from "node:assert/strict";
import { createHash } from "node:crypto";
import { makePool, ensureSchema } from "../src/db.mjs";
import { applyExtraction, buildExtractionPrompt } from "../src/graph-extract.mjs";

const DSN = process.env.MEMORY_PG_TEST_DSN;
if (!DSN) throw new Error("MEMORY_PG_TEST_DSN must be set");
const pool = makePool(DSN);
const FALANTE = { role: "user", prov_actor: "user_stated" };
const FALA_EM = "2026-08-02T21:45:00.000Z";

before(async () => { await ensureSchema(pool); });
beforeEach(async () => { await pool.query("TRUNCATE entities, facts, records CASCADE"); });
after(async () => { await pool.end(); });

async function mkRecord(content) {
  const sha = createHash("sha256").update(content + Math.random()).digest("hex");
  const r = await pool.query(
    `INSERT INTO records (source_type, content, content_sha256, occurred_at)
     VALUES ('ConversationPassage',$1,$2,$3) RETURNING id`,
    [content, sha, FALA_EM],
  );
  return r.rows[0].id;
}

test("o prompt manda NAO descartar auto-relato no presente", () => {
  const p = buildExtractionPrompt("estou irritado");
  assert.match(p, /PRESENT TENSE/);
  assert.match(p, /LEAVE occurred_at OUT and keep the fact/);
  assert.match(p, /Do NOT drop these/);
  // E preserva a recusa para o passado sem data.
  assert.match(p, /PAST, with no date given/);
  assert.match(p, /OMIT THE FACT/);
});

// O caso que estava sendo perdido: 25 caracteres, sem hora no texto, hora no registro.
test("auto-relato no presente sem hora herda o instante da fala", async () => {
  const rid = await mkRecord("Estou irritado com você");
  await applyExtraction(pool,
    { entities: [{ name: "Demetrios", type: "person" }],
      facts: [{ subject: "Demetrios", predicate: "felt_irritated",
                statement: "Estou irritado com você",
                self_report: true, state_channel: "arousal" }] },
    { recordId: rid, speaker: FALANTE, occurredAt: FALA_EM, model: "m" });

  const q = await pool.query("SELECT self_report, state_channel, occurred_at FROM facts");
  assert.equal(q.rowCount, 1, "o fato nao pode mais ser perdido");
  assert.equal(q.rows[0].self_report, true);
  assert.equal(q.rows[0].state_channel, "arousal");
  assert.equal(new Date(q.rows[0].occurred_at).toISOString(), FALA_EM,
    "sem hora no fato, vale a hora da fala — que e' quando o estado aconteceu");
});

// A hora explicita continua mandando: o fallback nao pode atropelar o que o
// texto de fato disse.
test("hora explicita no fato prevalece sobre a hora da fala", async () => {
  const ontem = "2026-08-01T06:00:00.000Z";
  const rid = await mkRecord("ontem de manhã dormi mal");
  await applyExtraction(pool,
    { entities: [{ name: "Demetrios", type: "person" }],
      facts: [{ subject: "Demetrios", predicate: "slept_badly", statement: "dormi mal",
                self_report: true, state_channel: "sleep", occurred_at: ontem }] },
    { recordId: rid, speaker: FALANTE, occurredAt: FALA_EM, model: "m" });

  const q = await pool.query("SELECT occurred_at FROM facts");
  assert.equal(new Date(q.rows[0].occurred_at).toISOString(), ontem);
});

// Sem hora em lugar nenhum, o fato existe mas nao entra na corroboracao: o
// indice da Fase 2 exige occurred_at.
test("sem hora no fato e sem hora no registro, fica fora do indice da Fase 2", async () => {
  const sha = createHash("sha256").update("sem hora" + Math.random()).digest("hex");
  const rid = (await pool.query(
    "INSERT INTO records (source_type, content, content_sha256) VALUES ('note','x',$1) RETURNING id",
    [sha])).rows[0].id;

  await applyExtraction(pool,
    { entities: [{ name: "Demetrios", type: "person" }],
      facts: [{ subject: "Demetrios", predicate: "felt_tense", statement: "tenso",
                self_report: true, state_channel: "arousal" }] },
    { recordId: rid, speaker: FALANTE, model: "m" });

  const q = await pool.query(
    `SELECT count(*)::int n FROM facts
      WHERE self_report AND state_channel IS NOT NULL AND occurred_at IS NOT NULL`);
  assert.equal(q.rows[0].n, 0, "sem quando, nao ha o que casar com a medida");
});
