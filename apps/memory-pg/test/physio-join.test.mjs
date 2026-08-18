// physio-join.test.mjs — a junta entre o que ele disse e o que o corpo registrou.
//
// ⚠️ O teste central deste arquivo NAO e' "a corroboracao funciona". E' que a
// junta se recusa a chamar de corroboracao o que nao e': presenca de medida no
// instante nao diz que a medida CONCORDA com o relato. Declarar acordo exige
// direcao pre-registrada, e escolher a direcao depois de ver o dado e' pesca.
//
// O segundo teste central e' a independencia: HKStateOfMindType existe no
// health_samples (16 amostras) e e' ELE declarando o proprio humor num app.
// Contar isso como corroboracao seria a mesma boca com dois microfones.

import { test, before, beforeEach, after } from "node:test";
import assert from "node:assert/strict";
import { createHash } from "node:crypto";
import { makePool, ensureSchema } from "../src/db.mjs";
import { resolveEntity } from "../src/graph.mjs";
import {
  CHANNEL_MAP, MAPPING_VERSION, summariseWindow, joinPhysiology, physioFunnel,
} from "../src/physio-join.mjs";

const DSN = process.env.MEMORY_PG_TEST_DSN;
if (!DSN) throw new Error("MEMORY_PG_TEST_DSN must be set");
// Neste teste o mesmo banco faz os dois papeis: `health_samples` e criada aqui
// para nao depender do beagle-pg, que em producao vive noutro host.
const pool = makePool(DSN);

before(async () => {
  await ensureSchema(pool);
  await pool.query(`CREATE TABLE IF NOT EXISTS health_samples (
    uuid uuid PRIMARY KEY DEFAULT gen_random_uuid(), ts timestamptz NOT NULL,
    end_ts timestamptz, type text NOT NULL, value double precision, unit text,
    source text, device text, metadata jsonb NOT NULL DEFAULT '{}')`);
});
beforeEach(async () => {
  await pool.query("TRUNCATE entities, facts, records, fact_measurements, health_samples CASCADE");
});
after(async () => { await pool.end(); });

const T = "2026-08-03T02:19:00.000Z";

async function autoRelato(channel, at = T) {
  const sha = createHash("sha256").update("r" + Math.random()).digest("hex");
  const rid = (await pool.query(
    `INSERT INTO records (source_type, content, content_sha256, occurred_at, prov_actor, metadata)
     VALUES ('ConversationPassage','x',$1,$2,'user_stated','{"role":"user"}') RETURNING id`,
    [sha, at])).rows[0].id;
  const { id: subj } = await resolveEntity(pool, { name: "Demetrios", type: "person" });
  const fsha = createHash("sha256").update("f" + Math.random()).digest("hex");
  const f = await pool.query(
    `INSERT INTO facts (subject_id, predicate, statement, source_record_id, content_sha256,
                        self_report, state_channel, occurred_at)
     VALUES ($1,'p','s',$2,$3,true,$4,$5) RETURNING id`,
    [subj, rid, fsha, channel, at]);
  return f.rows[0].id;
}

const amostra = (type, ts, value) =>
  pool.query(
    "INSERT INTO health_samples (ts, type, value, unit) VALUES ($1,$2,$3,'count/min')",
    [ts, type, value]);

test("o mapa declara canais vazios em vez de omiti-los", () => {
  // Um canal ausente do mapa seria indistinguivel de um canal esquecido.
  assert.ok("pain" in CHANNEL_MAP, "pain declarado, mesmo sem medida objetiva");
  assert.equal(CHANNEL_MAP.pain.length, 0);
  assert.ok("oncall" in CHANNEL_MAP);
  assert.equal(CHANNEL_MAP.oncall.length, 0);
});

// O teste que carrega a tese: outro auto-relato NAO e' outra modalidade.
test("HKStateOfMindType e' mapeado como NAO independente", () => {
  const v = CHANNEL_MAP.valence;
  assert.equal(v.length, 1);
  assert.equal(v[0].type, "HKStateOfMindType");
  assert.equal(v[0].independent, false,
    "e' ele declarando o proprio humor: a mesma boca com dois microfones");
  // E os canais do corpo sao independentes.
  for (const m of CHANNEL_MAP.arousal) assert.equal(m.independent, true);
});

test("summariseWindow resume a janela e situa o valor na linha de base DELE", async () => {
  // Linha de base: 90 dias antes, valores baixos.
  for (let i = 1; i <= 20; i++) {
    await amostra("HKQuantityTypeIdentifierHeartRate",
      new Date(Date.parse(T) - i * 86400000).toISOString(), 60);
  }
  // Na janela do evento: valores altos.
  await amostra("HKQuantityTypeIdentifierHeartRate", T, 100);
  await amostra("HKQuantityTypeIdentifierHeartRate", "2026-08-03T02:30:00Z", 100);

  const s = await summariseWindow(pool, {
    type: "HKQuantityTypeIdentifierHeartRate", at: T, windowMinutes: 60 });
  assert.equal(s.n_samples, 2);
  assert.equal(s.mean_value, 100);
  assert.equal(s.baseline_n, 20);
  assert.equal(s.baseline_pct, 100, "100 esta acima de toda a linha de base dele");
});

// Vazamento: julgar o evento com dados posteriores ao evento.
test("a linha de base olha so para TRAS", async () => {
  await amostra("HKQuantityTypeIdentifierHeartRate", T, 100);
  // Amostras DEPOIS do evento nao podem entrar na linha de base.
  for (let i = 1; i <= 10; i++) {
    await amostra("HKQuantityTypeIdentifierHeartRate",
      new Date(Date.parse(T) + i * 86400000).toISOString(), 200);
  }
  const s = await summariseWindow(pool, {
    type: "HKQuantityTypeIdentifierHeartRate", at: T, windowMinutes: 60 });
  assert.equal(s.baseline_n, 0, "nada antes do evento: sem linha de base");
  assert.equal(s.baseline_pct, null);
});

test("sem medida na janela, grava n_samples=0 em vez de omitir a linha", async () => {
  const fid = await autoRelato("arousal");
  const st = await joinPhysiology(pool, pool, { windowMinutes: 60 });
  assert.equal(st.facts, 1);

  const q = await pool.query(
    "SELECT measure_type, n_samples FROM fact_measurements WHERE fact_id=$1 ORDER BY measure_type", [fid]);
  assert.equal(q.rowCount, CHANNEL_MAP.arousal.length, "uma linha por medida do canal");
  assert.ok(q.rows.every((r) => r.n_samples === 0));
  // "Nao havia medida" e' um achado: apagar a linha faria a falta de cobertura
  // sumir do funil.
  assert.equal(st.semCobertura, CHANNEL_MAP.arousal.length);
});

test("com medida na janela, anexa a evidencia com a versao do mapa", async () => {
  const fid = await autoRelato("arousal");
  await amostra("HKQuantityTypeIdentifierHeartRate", T, 79.4);
  await joinPhysiology(pool, pool, { windowMinutes: 60 });

  const q = await pool.query(
    `SELECT n_samples, mean_value, independent, mapping_version FROM fact_measurements
      WHERE fact_id=$1 AND measure_type='HKQuantityTypeIdentifierHeartRate'`, [fid]);
  assert.equal(q.rows[0].n_samples, 1);
  assert.ok(Math.abs(q.rows[0].mean_value - 79.4) < 0.01);
  assert.equal(q.rows[0].independent, true);
  assert.equal(q.rows[0].mapping_version, MAPPING_VERSION,
    "a versao do mapa fica na linha: o mapa e' decisao teorica, nao detalhe");
});

// O ponto que separa esta junta de uma alegacao de corroboracao.
test("ter medida NAO promove o fato a corroborado", async () => {
  const fid = await autoRelato("arousal");
  await amostra("HKQuantityTypeIdentifierHeartRate", T, 120);
  await joinPhysiology(pool, pool, { windowMinutes: 60 });

  const q = await pool.query("SELECT trust_tier FROM facts WHERE id=$1", [fid]);
  assert.equal(q.rows[0].trust_tier, "unverified",
    "presenca de medida nao e' acordo; acordo exige direcao pre-registrada");
});

test("valence com StateOfMind conta como medida, mas NAO como independente", async () => {
  const fid = await autoRelato("valence");
  await pool.query(
    "INSERT INTO health_samples (ts, type, value, unit) VALUES ($1,'HKStateOfMindType',0.4,'score')", [T]);
  const st = await joinPhysiology(pool, pool, { windowMinutes: 60 });
  assert.equal(st.comCobertura, 1);

  const q = await pool.query(
    "SELECT independent FROM fact_measurements WHERE fact_id=$1", [fid]);
  assert.equal(q.rows[0].independent, false);

  const f = await physioFunnel(pool);
  assert.equal(f.com_medida, 1, "tem medida");
  assert.equal(f.com_medida_independente, 0, "mas nenhuma independente");
});

test("o funil nomeia cada estagio ate a evidencia independente", async () => {
  await autoRelato("arousal");
  await amostra("HKQuantityTypeIdentifierHeartRate", T, 88);
  await joinPhysiology(pool, pool, { windowMinutes: 60 });

  const f = await physioFunnel(pool);
  assert.equal(f.auto_relatos, 1);
  assert.equal(f.com_canal, 1);
  assert.equal(f.com_canal_e_hora, 1);
  assert.equal(f.consultados, 1);
  assert.equal(f.com_medida, 1);
  assert.equal(f.com_medida_independente, 1);
});

test("reprocessar e' idempotente", async () => {
  await autoRelato("arousal");
  await amostra("HKQuantityTypeIdentifierHeartRate", T, 88);
  await joinPhysiology(pool, pool, { windowMinutes: 60 });
  const a = await pool.query("SELECT count(*)::int n FROM fact_measurements");
  await joinPhysiology(pool, pool, { windowMinutes: 60 });
  const b = await pool.query("SELECT count(*)::int n FROM fact_measurements");
  assert.equal(a.rows[0].n, b.rows[0].n);
});
