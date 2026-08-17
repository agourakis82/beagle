// reenqueue-graph.mjs — recolocar na fila o que a pane engoliu.
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

/**
 * Conta e, opcionalmente, reenfileira registros marcados como processados que
 * não geraram nenhum fato dentro da janela.
 *
 * @param {import("pg").Pool} pool
 * @param {{ since: string, until?: string|null, apply?: boolean, limit?: number|null }} opts
 *   since  ISO — início da janela (obrigatório; sem ele isto viraria varredura total)
 *   until  ISO — fim da janela; ausente = agora
 *   apply  false (padrão) apenas conta. Reenfileirar 29 mil registros não pode
 *          ser o comportamento acidental de rodar o comando sem argumentos.
 *   limit  teto de registros por execução, para drenar em lotes
 * @returns {Promise<{candidates:number, requeued:number, applied:boolean}>}
 */
export async function reenqueueEmptyExtractions(pool, opts = {}) {
  const { since, until = null, apply = false, limit = null } = opts;
  if (!since) throw new Error("reenqueueEmptyExtractions: `since` é obrigatório (janela da pane)");

  const where = `
      pg.status = 'done'
      AND r.created_at >= $1::timestamptz
      AND ($2::timestamptz IS NULL OR r.created_at < $2::timestamptz)
      AND NOT EXISTS (SELECT 1 FROM facts f WHERE f.source_record_id = r.id)`;

  const count = await pool.query(
    `SELECT count(*)::int AS n FROM pending_graph pg JOIN records r ON r.id = pg.record_id WHERE ${where}`,
    [since, until],
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
         ${limit ? "LIMIT $3" : ""})`,
    limit ? [since, until, limit] : [since, until],
  );
  return { candidates, requeued: res.rowCount ?? 0, applied: true };
}

export default { reenqueueEmptyExtractions };
