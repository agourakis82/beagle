// faixa-por-tamanho.test.mjs — dois workers, duas placas, uma fila.
//
// A faixa `bulk` passa a ser dividida tambem por TAMANHO do registro, porque as duas GPUs tem
// tetos de contexto diferentes: a L4 do r770 aguenta 14.336 tokens por slot, a A5000 do r740 so
// 6.144 (divide a placa com o `hunyuan`). Um registro grande no endpoint pequeno estouraria o
// contexto e viraria quarentena — trabalho perdido por roteamento, nao por defeito.
//
// E resolve o gargalo que GPU sozinha nao resolvia. Medido em 19-ago-2026: a saida caiu de 289
// para 31 registros/hora enquanto a entrada seguia em ~100/h. Os workers sao SERIAIS, entao um
// registro de 5 minutos travava um terco da capacidade e a multidao de registros pequenos
// (mediana 776 caracteres) esperava atras dele.
//
// O que estes testes protegem e a PARTICAO. Um erro de sinal aqui nao aparece em produtividade:
// aparece como registro processado duas vezes (fato duplicado) ou nunca (some da fila sem
// ninguem notar). Nenhum dos dois grita.

import { test, before, beforeEach, after } from "node:test";
import assert from "node:assert/strict";
import { createHash } from "node:crypto";
import { makePool, ensureSchema } from "../src/db.mjs";
import { runGraphOnce } from "../src/graph-worker.mjs";

const DSN = process.env.MEMORY_PG_TEST_DSN;
if (!DSN) throw new Error("MEMORY_PG_TEST_DSN must be set");
const pool = makePool(DSN);

before(async () => { await ensureSchema(pool); });
beforeEach(async () => {
  await pool.query("TRUNCATE entities, facts, pending_graph, failed_graph, records CASCADE");
});
after(async () => { await pool.end(); });

const CORTE = 18000;

/** Registro com um tamanho exato de conteudo, enfileirado para extracao. */
async function enfileira(tamanho) {
  const conteudo = "x".repeat(tamanho);
  const sha = createHash("sha256").update(conteudo + Math.random()).digest("hex");
  const r = await pool.query(
    "INSERT INTO records (source_type, content, content_sha256) VALUES ('note',$1,$2) RETURNING id",
    [conteudo, sha]);
  await pool.query("INSERT INTO pending_graph (record_id) VALUES ($1)", [r.rows[0].id]);
  return r.rows[0].id;
}

test("o worker pequeno pega SO o que cabe nele", async () => {
  const pequeno = await enfileira(500);
  await enfileira(30000);

  const stats = await runGraphOnce(pool, {
    llmFn: async () => { throw new Error("x"); }, batch: 50, tier: "bulk", maxChars: CORTE,
  });
  assert.equal(stats.claimed, 1, "o gigante nao pode ser reivindicado pelo endpoint pequeno");

  const q = await pool.query("SELECT retry_count FROM pending_graph WHERE record_id=$1", [pequeno]);
  assert.equal(q.rows[0].retry_count, 1, "e o que ele pegou foi o pequeno");
});

test("o worker grande pega SO o que o pequeno recusa", async () => {
  await enfileira(500);
  const gigante = await enfileira(30000);

  const stats = await runGraphOnce(pool, {
    llmFn: async () => { throw new Error("x"); }, batch: 50, tier: "bulk", minChars: CORTE,
  });
  assert.equal(stats.claimed, 1);

  const q = await pool.query("SELECT retry_count FROM pending_graph WHERE record_id=$1", [gigante]);
  assert.equal(q.rows[0].retry_count, 1);
});

test("PARTICAO: juntos cobrem a fila inteira, sem sobra", async () => {
  // Exaustividade. Um registro que nenhum dos dois pega some da fila sem nada acusar — a fila
  // continua "andando" e o registro nunca e extraido.
  for (const t of [1, 500, 17999, 18000, 18001, 30000, 47039]) await enfileira(t);

  const a = await runGraphOnce(pool, { llmFn: async () => { throw new Error("x"); }, batch: 50, tier: "bulk", maxChars: CORTE });
  const b = await runGraphOnce(pool, { llmFn: async () => { throw new Error("x"); }, batch: 50, tier: "bulk", minChars: CORTE });

  assert.equal(a.claimed + b.claimed, 7, "todo registro tem que ser de exatamente um dos dois");
});

test("PARTICAO: o registro do TAMANHO EXATO do corte vai para um so", async () => {
  // O caso de borda que um `>=` no lugar de `>` estragaria: 18.000 seria processado pelos DOIS,
  // gerando fato duplicado. `<=` em cima e `>` embaixo e o que fecha isso.
  await enfileira(CORTE);

  const a = await runGraphOnce(pool, { llmFn: async () => { throw new Error("x"); }, batch: 50, tier: "bulk", maxChars: CORTE });
  assert.equal(a.claimed, 1, "o corte e inclusivo em cima");

  await pool.query("UPDATE pending_graph SET status='pending', retry_count=0, locked_until=NULL");

  const b = await runGraphOnce(pool, { llmFn: async () => { throw new Error("x"); }, batch: 50, tier: "bulk", minChars: CORTE });
  assert.equal(b.claimed, 0, "e exclusivo embaixo — o mesmo registro nao pode cair nos dois");
});

test("sem corte, o comportamento e o de antes", async () => {
  // Nao pode haver regressao para quem nao declarar faixa de tamanho.
  await enfileira(500);
  await enfileira(30000);
  const s = await runGraphOnce(pool, { llmFn: async () => { throw new Error("x"); }, batch: 50, tier: "bulk" });
  assert.equal(s.claimed, 2);
});

test("teto invalido LANCA, em vez de virar fila inteira", async () => {
  // Config errada tem que parar o processo. Um NaN escorregando para o SQL faria o worker
  // pequeno varrer a fila toda e engolir os gigantes que ele nao consegue processar.
  await assert.rejects(
    () => runGraphOnce(pool, { llmFn: async () => "{}", tier: "bulk", maxChars: Number("dezoito mil") }),
    /maxChars invalido/,
  );
});
