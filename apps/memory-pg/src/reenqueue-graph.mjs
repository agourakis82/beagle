// reenqueue-graph.mjs — recolocar na fila o que a pane engoliu, na ordem certa.
//
// Entre 2026-07-19 e 2026-08-17 o extrator recebeu HTTP 500 do router em toda
// chamada e convertia o erro numa extração vazia. O worker marcava o registro
// `done` e seguia. A fila drenou perfeitamente, a DLQ ficou vazia, nada foi
// logado: 127.771 registros processados, zero fatos.
//
// Esses registros não voltam sozinhos. `done` é `done`, e o worker só olha para
// `pending`. Este módulo devolve à fila os registros que foram marcados como
// processados sem produzir nada.
//
// A ASSINATURA DA PANE, e por que ela não é conclusiva sozinha: um registro sem
// fatos pode ser um registro sem nada a extrair. É por isso que a seleção é
// limitada por janela temporal — dentro da janela da pane, "nenhum fato" é
// consequência do erro; fora dela, pode ser a verdade. Reprocessar um registro
// genuinamente vazio custa uma chamada e não corrompe nada (a inserção é
// idempotente por content_sha256), mas alargar a janela sem pensar transforma um
// conserto em varredura do corpus inteiro.
//
// ORDEM IMPORTA. Medido no backlog de 25.503:
//
//   ConversationPassage  15.595     metadata->>'space'='personal'   4.279
//   MemoryAtom            4.244     (sem space)                    21.254
//   MemoryEpisode         3.919
//   SounioCommit          1.763
//
// A esmagadora maioria é log de trabalho do compilador. A ~75s por extração,
// varrer 21 mil logs técnicos em ordem cronológica para colher algumas dezenas
// de auto-relatos é semanas de GPU pelo material errado.
//
// ⚠️ E `prov_actor='user_stated'` NÃO serve como filtro de "ele falando": 774 dos
// 1.174 user_stated pendentes são ruído de harness (`<environment_context>`,
// `<task-notification>`, "You are doing a deep-read audit..."). O papel de
// usuário numa sessão de agente é ocupado por texto de máquina. `space` é o
// discriminador confiável.

/** Filtro de janela + "processado sem produzir nada", compartilhado pelas duas funções. */
const WHERE_VAZIO = `
      pg.status = 'done'
      AND r.created_at >= $1::timestamptz
      AND ($2::timestamptz IS NULL OR r.created_at < $2::timestamptz)
      AND NOT EXISTS (SELECT 1 FROM facts f WHERE f.source_record_id = r.id)`;

/**
 * Conta e, opcionalmente, reenfileira registros marcados como processados que
 * não geraram nenhum fato dentro da janela.
 *
 * @param {import("pg").Pool} pool
 * @param {{ since: string, until?: string|null, apply?: boolean, limit?: number|null,
 *           space?: string|null }} opts
 *   since  ISO — início da janela (obrigatório; sem ele isto viraria varredura total)
 *   until  ISO — fim da janela; ausente = agora
 *   apply  false (padrão) apenas conta. Reenfileirar 25 mil registros não pode
 *          ser o comportamento acidental de rodar o comando sem argumentos.
 *   limit  teto de registros por execução, para drenar em lotes
 *   space  restringe a metadata->>'space' (ex.: "personal"). É o que separa o
 *          corpus pessoal do log de trabalho.
 *   role   restringe a metadata->>'role' (ex.: "user"). Separa a fala DELE da do
 *          companion dentro do mesmo space.
 * @returns {Promise<{candidates:number, requeued:number, applied:boolean}>}
 */
export async function reenqueueEmptyExtractions(pool, opts = {}) {
  const { since, until = null, apply = false, limit = null, space = null, role = null } = opts;
  if (!since) throw new Error("reenqueueEmptyExtractions: `since` é obrigatório (janela da pane)");

  // `role` separa a fala DELE da do companion dentro do mesmo space. Na fila
  // pessoal ha 3.072 registros `assistant` para 31 `user`: sem este filtro, dar
  // prioridade ao "pessoal" ainda significa processar 99% de voz da maquina.
  const base = [since, until];
  let where = WHERE_VAZIO;
  if (space) { base.push(space); where += ` AND r.metadata->>'space' = $${base.length}`; }
  if (role) { base.push(role); where += ` AND r.metadata->>'role' = $${base.length}`; }

  const count = await pool.query(
    `SELECT count(*)::int AS n FROM pending_graph pg JOIN records r ON r.id = pg.record_id WHERE ${where}`,
    base,
  );
  const candidates = count.rows[0].n;
  if (!apply) return { candidates, requeued: 0, applied: false };

  // Volta para `pending` com o contador de tentativas zerado: a falha anterior
  // foi da infraestrutura, não deste registro, e fazê-lo herdar tentativas o
  // mandaria para a DLQ cedo demais.
  const res = await pool.query(
    `UPDATE pending_graph SET status = 'pending', retry_count = 0, locked_until = NULL, last_error = NULL
      WHERE id IN (
        SELECT pg.id FROM pending_graph pg JOIN records r ON r.id = pg.record_id
         WHERE ${where}
         ORDER BY r.created_at
         ${limit ? `LIMIT $${base.length + 1}` : ""})`,
    limit ? [...base, limit] : base,
  );
  return { candidates, requeued: res.rowCount ?? 0, applied: true };
}

/**
 * Tira da fila o que não é do `space` pedido, devolvendo para `done`.
 *
 * O worker reivindica `ORDER BY id` e não sabe o que é importante, então a única
 * forma de priorizar sem mexer nele é encolher a fila. Isto é seguro por ser
 * reversível: o critério de seleção acima ("done, na janela, sem fatos") é
 * idempotente, então um registro estacionado é reencontrado por
 * reenqueueEmptyExtractions quando for a vez dele. Nada se perde — muda a ordem,
 * não o conjunto.
 *
 * @param {import("pg").Pool} pool
 * @param {{ keepSpace: string, apply?: boolean }} opts
 * @returns {Promise<{parked:number, kept:number, applied:boolean}>}
 */
export async function parkQueuedExcept(pool, { keepSpace, keepRole = null, apply = false } = {}) {
  if (!keepSpace) throw new Error("parkQueuedExcept: `keepSpace` é obrigatório");

  const cond = `pg.status = 'pending'
                AND ((r.metadata->>'space' IS DISTINCT FROM $1)
                  OR ($2::text IS NOT NULL AND r.metadata->>'role' IS DISTINCT FROM $2))`;
  const c = await pool.query(
    `SELECT
       (SELECT count(*)::int FROM pending_graph pg JOIN records r ON r.id=pg.record_id WHERE ${cond}) AS fora,
       (SELECT count(*)::int FROM pending_graph pg JOIN records r ON r.id=pg.record_id
         WHERE pg.status='pending' AND r.metadata->>'space' = $1
           AND ($2::text IS NULL OR r.metadata->>'role' = $2)) AS dentro`,
    [keepSpace, keepRole],
  );
  const parked = c.rows[0].fora, kept = c.rows[0].dentro;
  if (!apply) return { parked: 0, kept, applied: false, candidates: parked };

  const res = await pool.query(
    `UPDATE pending_graph SET status='done', locked_until=NULL
      WHERE id IN (SELECT pg.id FROM pending_graph pg JOIN records r ON r.id=pg.record_id WHERE ${cond})`,
    [keepSpace, keepRole],
  );
  return { parked: res.rowCount ?? 0, kept, applied: true };
}

/**
 * Devolve à fila registros que estão na DLQ — o caminho de volta que não existia.
 *
 * **Cair na fila morta era definitivo.** O backfill exclui do reenfileiramento tudo que está
 * lá (`AND NOT EXISTS (SELECT 1 FROM failed_graph ...)`) e o worker contínuo só olha
 * `pending_graph`. Medido em 17-ago-2026: **3.045** registros na DLQ nunca produziram fato
 * nenhum, e **175** deles são `user_stated` — fala DELE que nunca virou conhecimento.
 *
 * E boa parte foi descartada barato: o backfill roda com `maxRetries: 2` fixo no código
 * (`bin/graph-backfill.mjs`), contra 3 do worker contínuo. Dois tropeços do LLM, numa época
 * em que a frota estava instável, bastavam para excluir um registro para sempre.
 *
 * A linha da DLQ é **preservada**, não apagada: ela é o registro histórico de que aquela
 * tentativa falhou, e apagá-la para "limpar" destruiria a única evidência do episódio. O que
 * se cria é uma nova entrada na fila viva.
 *
 * @param {import("pg").Pool} pool
 * @param {{ provActor?: string|null, apply?: boolean, limit?: number|null }} opts
 *   provActor  restringe por quem falou (ex.: "user_stated"). A fila é lenta e o corpus é
 *              majoritariamente máquina; sem isto, priorizar a fala dele é impossível.
 *   apply      false (padrão) apenas conta. Reenfileirar 3 mil registros não pode ser o
 *              comportamento acidental de rodar o comando sem argumentos.
 *   limit      teto por execução, para drenar em lotes.
 * @returns {Promise<{candidates:number, requeued:number, applied:boolean}>}
 */
export async function requeueFromDlq(pool, { provActor = null, apply = false, limit = null } = {}) {
  const args = [];
  let cond = `NOT EXISTS (SELECT 1 FROM facts x WHERE x.source_record_id = f.record_id)
              AND NOT EXISTS (SELECT 1 FROM pending_graph g WHERE g.record_id = f.record_id)`;
  if (provActor) { args.push(provActor); cond += ` AND r.prov_actor = $${args.length}`; }

  const c = await pool.query(
    `SELECT count(*)::int n FROM failed_graph f JOIN records r ON r.id = f.record_id WHERE ${cond}`,
    args,
  );
  const candidates = c.rows[0].n;
  if (!apply) return { candidates, requeued: 0, applied: false };

  // `retry_count` volta a zero: a falha anterior foi da infraestrutura (LLM fora do ar,
  // resposta impossível de parsear), não uma propriedade do registro. Herdar tentativas o
  // mandaria de volta para a DLQ ao primeiro tropeço.
  const res = await pool.query(
    `INSERT INTO pending_graph (record_id, status, retry_count)
     SELECT f.record_id, 'pending', 0
       FROM failed_graph f JOIN records r ON r.id = f.record_id
      WHERE ${cond}
      ORDER BY r.created_at
      ${limit ? `LIMIT $${args.length + 1}` : ""}
     ON CONFLICT DO NOTHING
     RETURNING 1`,
    limit ? [...args, limit] : args,
  );
  return { candidates, requeued: res.rowCount ?? 0, applied: true };
}

export default { reenqueueEmptyExtractions, parkQueuedExcept, requeueFromDlq };
