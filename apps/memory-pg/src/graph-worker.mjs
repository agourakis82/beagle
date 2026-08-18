// graph-worker.mjs — Phase 4, Task 4.3: SKIP-LOCKED drain of the pending_graph
// outbox. Mirrors the embed worker: claim a batch atomically (FOR UPDATE SKIP
// LOCKED, with an inherent reaper via locked_until), extract a knowledge graph
// from each record via the sovereign LLM, apply it bi-temporally, mark done.
// Failures retry up to maxRetries, then move to the failed_graph DLQ.

import { extractGraph, applyExtraction } from "./graph-extract.mjs";

/**
 * Process one batch of pending_graph rows.
 * @param {import("pg").Pool} pool
 * @param {{
 *   llmFn: (prompt:string)=>Promise<string>,
 *   embedFn?: (texts:string[])=>Promise<number[][]>,
 *   batch?: number,
 *   maxRetries?: number,
 *   model?: string|null,
 * }} opts
 * @returns {Promise<{claimed:number, processed:number, facts:number, entities:number, failed:number, errors:string[]}>}
 */
/**
 * A fila partida em DUAS FAIXAS, servidas por modelos diferentes.
 *
 * Medido em 17-ago-2026: o `r1-distill-70b` leva ~150 s por registro e tem 4 slots — teto de
 * ~96/hora contra ~875/hora de entrada. Ele nao serve para varrer 9 mil registros; cada
 * estouro de conexao mandava um registro para a DLQ. Mas ele e o melhor modelo disponivel, e
 * o que merece o melhor modelo nao e o volume: e a FALA DELE, que sao ~170 registros.
 *
 * A particao e por `prov_actor` e e EXAUSTIVA E DISJUNTA de proposito: todo registro cai em
 * exatamente uma faixa. Faixas que se sobrepoem fariam os dois workers disputar a mesma
 * linha; faixas que deixam buraco fariam registros nunca serem processados — e ninguem
 * notaria, porque a fila continuaria drenando.
 *
 *   voice  `prov_actor = 'user_stated'`            — o que ele disse
 *   bulk   `prov_actor IS DISTINCT FROM ...`       — todo o resto
 *
 * `IS DISTINCT FROM` e nao `<>` porque `prov_actor` pode ser NULL, e `NULL <> 'x'` e NULL,
 * nao true: com `<>` os registros sem ator sumiriam das DUAS faixas.
 */
export const TIERS = {
  voice: "r.prov_actor = 'user_stated'",
  bulk: "r.prov_actor IS DISTINCT FROM 'user_stated'",
  all: "true",
};

export async function runGraphOnce(pool, opts) {
  const { llmFn, embedFn = null, batch = 8, maxRetries = 3, model = null, tier = "all" } = opts || {};
  if (typeof llmFn !== "function") throw new Error("runGraphOnce: llmFn required");
  // Faixa desconhecida e erro, nunca "processa tudo": um typo no env viraria os dois workers
  // varrendo a fila inteira e brigando por cada linha.
  const cond = Object.prototype.hasOwnProperty.call(TIERS, tier) ? TIERS[tier] : null;
  if (cond === null) throw new Error(`runGraphOnce: tier desconhecido "${tier}"`);

  const claimed = await pool.query(
    `UPDATE pending_graph
        SET status='processing', locked_until = now() + interval '10 minutes'
      WHERE id IN (
        SELECT pg.id FROM pending_graph pg
          JOIN records r ON r.id = pg.record_id
         WHERE (pg.status='pending' OR (pg.status='processing' AND pg.locked_until < now()))
           AND ${cond}
         ORDER BY pg.id FOR UPDATE OF pg SKIP LOCKED LIMIT $1)
      RETURNING id, record_id, retry_count`,
    [batch],
  );

  // `oversized` sai daqui pelo mesmo motivo que `semSentenca` e `sujeitoAlheio`: um registro
  // posto de lado sem numero visivel e um registro perdido em silencio.
  const stats = { claimed: claimed.rowCount, processed: 0, facts: 0, entities: 0, failed: 0, oversized: 0, semSentenca: 0, sujeitoAlheio: 0, errors: [] };

  for (const row of claimed.rows) {
    try {
      const rec = await pool.query(
        `SELECT content, occurred_at, prov_actor, metadata->>'role' AS role
           FROM records WHERE id = $1`,
        [row.record_id],
      );
      if (rec.rowCount === 0) {
        // record gone — drop the queue row as done (nothing to extract)
        await pool.query("UPDATE pending_graph SET status='done' WHERE id=$1", [row.id]);
        stats.processed++;
        continue;
      }
      const extraction = await extractGraph({ content: rec.rows[0].content }, { llmFn });
      const applied = await applyExtraction(pool, extraction, {
        recordId: row.record_id,
        embedFn,
        occurredAt: rec.rows[0].occurred_at,
        // Quem extraiu vai junto do fato: sem isso, saber qual modelo produziu o
        // que exige cruzar recorded_at com a data dos ReplicaSets.
        model,
        // Quem FALOU decide se auto-relato e' admissivel. O extrator le texto e
        // nao sabe de quem e' a boca; o registro sabe.
        speaker: { prov_actor: rec.rows[0].prov_actor, role: rec.rows[0].role },
      });
      stats.facts += applied.factsInserted;
      stats.entities += applied.entitiesResolved;
      // Descarte silencioso seria repetir o defeito que este arquivo inteiro conserta.
      // A taxa de recusa e' um sinal da QUALIDADE DO EXTRATOR: 66% num modelo e 10% em
      // outro nao e ruido, e ver isso exige que o numero saia daqui.
      stats.semSentenca += applied.semSentenca ?? 0;
      // A guarda de sujeito e ESTREITA por escolha declarada, e por isso custa relatos
      // legitimos. O custo foi aceito; invisivel ele nao pode ser — sem este numero ninguem
      // descobre que a lista branca esta comendo demais.
      stats.sujeitoAlheio += applied.sujeitoAlheio ?? 0;
      if (applied.sujeitoAlheio) {
        console.error(
          `[graph-worker] record=${row.record_id} ${applied.sujeitoAlheio} auto-relato(s) recusado(s): sujeito nao e o falante`,
        );
      }
      if (applied.semSentenca) {
        console.error(
          `[graph-worker] record=${row.record_id} ${applied.semSentenca} fato(s) recusado(s): sem statement`,
        );
      }
      await pool.query("UPDATE pending_graph SET status='done' WHERE id=$1", [row.id]);
      stats.processed++;
    } catch (err) {
      const next = row.retry_count + 1;
      const reason = `${err?.name ?? "Error"}${err?.kind ? "/" + err.kind : ""}: ${err?.message ?? err}`;
      // Log every failure. Previously the catch was completely silent, so a
      // pipeline whose LLM had no backend looked identical to a healthy one.
      console.error(`[graph-worker] record=${row.record_id} try=${next}/${maxRetries} ${reason.slice(0, 240)}`);
      stats.errors.push(reason.slice(0, 240));
      if (err?.kind === "exceed_context") {
        // Nao gasta tentativa e nao vai para a fila morta.
        //
        // Repetir seria queimar GPU num resultado garantidamente identico: o registro tem o
        // tamanho que tem. E a fila morta e o lugar do que quebrou, nao do que ainda nao coube
        // — enterrar aqui faria um registro perfeitamente valido depender de alguem lembrar de
        // desenterra-lo.
        //
        // `oversized` e uma quarentena RECUPERAVEL: a consulta de reivindicacao so pega
        // `pending`, entao ele para de girar; e quando o teto de contexto subir, um unico
        // UPDATE devolve todos (`bin/reenqueue-graph.mjs --oversized`). O teto ja subiu duas
        // vezes num so dia — 8192 -> 10240 -> 14336 tokens por slot.
        await pool.query(
          "UPDATE pending_graph SET status='oversized', locked_until=NULL, last_error=$2 WHERE id=$1",
          [row.id, reason.slice(0, 2000)],
        );
        stats.oversized++;
        continue;
      }
      if (next > maxRetries) {
        // `created_at` continua sendo copiado da fila — e a hora do ENFILEIRAMENTO, e serve
        // para medir quanto tempo o registro esperou. Mas ela nao responde "desde quando
        // esta quebrando?", que e a pergunta que a fila morta existe para responder: as 9
        // falhas de 17-ago-2026 carregavam created_at de 04-jul a 17-ago. Por isso
        // `failed_at` e gravado aqui, explicitamente, no instante da falha.
        await pool.query(
          "INSERT INTO failed_graph (id, record_id, status, retry_count, created_at, last_error, failed_at) " +
            "SELECT id, record_id, 'failed', $2, created_at, $3, now() FROM pending_graph WHERE id=$1",
          [row.id, next, reason.slice(0, 2000)],
        );
        await pool.query("DELETE FROM pending_graph WHERE id=$1", [row.id]);
        stats.failed++;
      } else {
        await pool.query(
          "UPDATE pending_graph SET status='pending', retry_count=$2, locked_until=NULL WHERE id=$1",
          [row.id, next],
        );
      }
    }
  }
  return stats;
}

export default runGraphOnce;
