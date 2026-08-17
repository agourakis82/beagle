// graph-health.mjs — o alarme que faltava.
//
// A extração passou 29 dias emitindo `facts=0` e ninguém soube. Havia um alarme
// (`memory-pg-capture-health`) e ele estava OK o tempo todo: vigia a CAPTURA —
// "o app está gravando registros?" — e a captura nunca parou. O que parou foi a
// etapa seguinte. Um alarme no lugar errado é pior que nenhum, porque dá a
// sensação de cobertura.
//
// SINAL, e por que não é "nenhum fato em X horas":
//
// Zero fatos é normal se não houve o que extrair — noite quieta, fila vazia. Um
// alarme assim tocaria à toa e seria silenciado, que é como alarmes morrem.
//
// A assinatura da pane é outra: **entrou material novo e não saiu nada.**
// Durante os 29 dias chegaram ~1.000 registros/dia e saíram zero fatos. Essa
// conjunção não tem leitura inocente.
//
// Linha de base medida em 17-ago, com o pipeline são: 44, 164, 197, 134, 179,
// 146, 47 fatos/hora. Três horas de zero COM entrada é inequívoco.

/**
 * Estado de saúde da extração.
 *
 * @param {import("pg").Pool} pool
 * @param {{windowHours?:number}} [opts]
 * @returns {Promise<{ok:boolean, motivo:string|null, facts:number, records:number,
 *                     pending:number, dlq:number, ultimoFato:string|null}>}
 */
export async function graphHealth(pool, { windowHours = 3 } = {}) {
  const r = await pool.query(
    `SELECT
       (SELECT count(*)::int FROM facts
         WHERE recorded_at > now() - make_interval(hours => $1))            AS facts,
       (SELECT count(*)::int FROM records
         WHERE created_at  > now() - make_interval(hours => $1))            AS records,
       (SELECT count(*)::int FROM pending_graph WHERE status='pending')     AS pending,
       (SELECT count(*)::int FROM failed_graph
         WHERE created_at  > now() - make_interval(hours => $1))            AS dlq,
       (SELECT max(recorded_at) FROM facts)                                 AS ultimo`,
    [windowHours],
  );
  const s = r.rows[0];
  const ultimoFato = s.ultimo ? new Date(s.ultimo).toISOString() : null;
  const base = { facts: s.facts, records: s.records, pending: s.pending, dlq: s.dlq, ultimoFato };

  // A conjunção. Entrada sem saída é a pane; qualquer uma das duas sozinha, não.
  if (s.facts === 0 && s.records > 0) {
    return {
      ...base, ok: false,
      motivo: `${s.records} registros novos em ${windowHours}h e ZERO fatos extraídos` +
              (ultimoFato ? ` (último fato: ${ultimoFato})` : " (nunca houve fato)"),
    };
  }

  // Fila parada com trabalho acumulado: o worker pode estar vivo e sem processar
  // — foi o que aconteceu quando duas réplicas caíram em nós sem rota para o
  // banco e ficaram num laço de EHOSTUNREACH, silenciosas para qualquer contador
  // que só olhasse `facts`.
  if (s.facts === 0 && s.pending > 0) {
    return {
      ...base, ok: false,
      motivo: `${s.pending} registros na fila e ZERO fatos em ${windowHours}h`,
    };
  }

  return { ...base, ok: true, motivo: null };
}

/**
 * Publica no ntfy do cluster, com dedup pela própria janela do canal.
 *
 * Um Job que falha só existe para quem já foi olhar — e ninguém foi olhar por 29
 * dias. O alarme precisa alcançar alguém fora do cluster.
 *
 * Dedup de 12h: se seguir quebrado o lembrete volta, sem virar enxurrada a cada
 * execução. Mesma disciplina do capture-health.
 */
export async function avisar(texto, env = process.env) {
  const topic = env.NTFY_TOPIC;
  if (!topic) { console.log("[aviso] NTFY_TOPIC ausente — alarme sem destino"); return false; }
  const base = env.NTFY_URL || "http://ntfy.beagle.svc.cluster.local";
  const auth = "Basic " + Buffer.from(`${env.NTFY_USER ?? ""}:${env.NTFY_PASSWORD ?? ""}`).toString("base64");
  const TAG = "[extracao-parada]";

  try {
    const r = await fetch(`${base}/${topic}/json?poll=1&since=12h`, {
      headers: { authorization: auth }, signal: AbortSignal.timeout(15000),
    });
    if ((await r.text()).includes(TAG)) {
      console.log("[aviso] ja notificado nas ultimas 12h");
      return false;
    }
  } catch { /* sem histórico legível: melhor avisar de novo que calar */ }

  try {
    await fetch(`${base}/${topic}`, {
      method: "POST",
      headers: {
        authorization: auth,
        // ⚠️ Cabeçalho HTTP é ByteString: só aceita latin-1. Um travessão ou um
        // "ç" aqui faz o fetch LANÇAR antes de publicar, e o alarme morre calado
        // — exatamente o modo de falha que ele existe para denunciar. Pego ao
        // provar o canal: a primeira versão deste Title tinha "—" e "extração".
        // Acento vai no CORPO, que é UTF-8 e aceita.
        Title: "Beagle: extracao de fatos parada",
        Priority: "high",
        Tags: "rotating_light",
      },
      body: `${TAG} ${texto}`,
      signal: AbortSignal.timeout(15000),
    });
    return true;
  } catch (e) {
    console.log("[aviso] ntfy falhou: " + String(e.message).slice(0, 60));
    return false;
  }
}

export default { graphHealth, avisar };
