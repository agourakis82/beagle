// instante-do-sujeito.test.mjs — o instante declarado NO APP chega como declarado.
//
// Este e o elo que faz a Fase 2 sair de zero. A cadeia inteira:
//
//   app  -> o sujeito toca a ancora; `state_occurred_at` + `state_anchor` viajam no chat
//   cockpit -> `ingestPersonalTurn` grava o registro com esse `occurred_at` e a MARCA
//              `metadata.state_declared_at`
//   aqui -> o fato herda o instante do registro e, por causa da marca, nasce
//           `occurred_at_imputed = false` — elegivel sob o pre-registro `direcao-v2`
//
// Sem a marca, herdar do registro sempre significou IMPUTAR. Era correto enquanto a unica hora
// do registro era a de chegada; deixou de ser quando o sujeito passou a poder declarar.

import { test, before, beforeEach, after } from "node:test";
import assert from "node:assert/strict";
import { createHash } from "node:crypto";
import { makePool, ensureSchema } from "../src/db.mjs";
import { applyExtraction } from "../src/graph-extract.mjs";

const DSN = process.env.MEMORY_PG_TEST_DSN;
if (!DSN) throw new Error("MEMORY_PG_TEST_DSN must be set");
const pool = makePool(DSN);

before(async () => { await ensureSchema(pool); });
beforeEach(async () => {
  await pool.query("TRUNCATE entities, facts, pending_graph, failed_graph, records CASCADE");
});
after(async () => { await pool.end(); });

const T_ESTADO = "2026-08-18T05:20:00.000Z";

async function registro({ declarado = false } = {}) {
  const sha = createHash("sha256").update("r" + Math.random()).digest("hex");
  const meta = declarado
    ? { space: "personal", role: "user", state_declared_at: T_ESTADO, state_anchor: "horario_escolhido" }
    : { space: "personal", role: "user" };
  const r = await pool.query(
    `INSERT INTO records (source_type, content, content_sha256, occurred_at, prov_actor, metadata)
     VALUES ('ConversationPassage','acordei com o peito apertado',$1,$2,'user_stated',$3) RETURNING id`,
    [sha, T_ESTADO, JSON.stringify(meta)]);
  return r.rows[0].id;
}

const EXTRACAO = {
  entities: [{ name: "eu", type: "person" }],
  // O modelo NAO declara occurred_at — e o caso real: em 60 dias, nenhum dos 26.617 registros
  // trazia hora no texto. O instante tem que vir do registro.
  facts: [{ subject: "eu", predicate: "sentiu", object_literal: "peito apertado",
            statement: "acordei com o peito apertado", self_report: true,
            state_channel: "pain", confidence: 0.9 }],
};

test("com a marca do app, o instante herdado nasce DECLARADO", async () => {
  const rid = await registro({ declarado: true });
  await applyExtraction(pool, EXTRACAO, {
    recordId: rid, occurredAt: T_ESTADO,
    speaker: { prov_actor: "user_stated", role: "user" },
    instanteDeclaradoPeloSujeito: true,
  });

  const q = await pool.query("SELECT occurred_at, occurred_at_imputed FROM facts WHERE self_report");
  assert.equal(q.rowCount, 1);
  assert.equal(q.rows[0].occurred_at_imputed, false, "declarado pelo sujeito nao e imputado");
  assert.equal(new Date(q.rows[0].occurred_at).toISOString(), T_ESTADO);
});

test("SEM a marca, herdar continua sendo imputar", async () => {
  // A guarda so vale se discrimina. Se tudo que herda virasse declarado, a direcao-v2 perderia
  // o sentido e os 10 relatos que ela torna inelegiveis voltariam pela porta dos fundos.
  const rid = await registro({ declarado: false });
  await applyExtraction(pool, EXTRACAO, {
    recordId: rid, occurredAt: T_ESTADO,
    speaker: { prov_actor: "user_stated", role: "user" },
    instanteDeclaradoPeloSujeito: false,
  });

  const q = await pool.query("SELECT occurred_at_imputed FROM facts WHERE self_report");
  assert.equal(q.rows[0].occurred_at_imputed, true);
});

test("o padrao e imputar: quem nao passar a flag nao ganha elegibilidade de brinde", async () => {
  // Chamador antigo, que nao conhece a flag, continua produzindo fato imputado. Um default
  // permissivo aqui daria elegibilidade a todo o corpus historico de uma vez, em silencio.
  const rid = await registro({ declarado: false });
  await applyExtraction(pool, EXTRACAO, {
    recordId: rid, occurredAt: T_ESTADO,
    speaker: { prov_actor: "user_stated", role: "user" },
  });
  const q = await pool.query("SELECT occurred_at_imputed FROM facts WHERE self_report");
  assert.equal(q.rows[0].occurred_at_imputed, true);
});
