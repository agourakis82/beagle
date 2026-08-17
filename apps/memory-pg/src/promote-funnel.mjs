// promote-funnel.mjs — medir onde o funil zera, a cada ciclo.
//
// O critério de quórum vigente ("dois pares (sessão, dia) distintos entre
// apoiadores user_stated") é insatisfazível num sistema de sujeito único: todas
// as fontes são o mesmo homem, na mesma boca, e repetição não é independência.
// Mas o número final — zero corroborados — não distingue isso de extração parada
// ou de apoio que não acumula. Medido no corpus vivo em 17-ago-2026:
//
//   fatos                                549.059
//   com >= 1 apoio                       546.605
//   com >= 1 apoio user_stated            54.740
//   com >= 2 pares (sessão, dia)               0   <- zera aqui
//
// Nenhum fato tem sequer DOIS apoiadores user_stated, com ou sem sessão distinta.
// O critério nunca teve o que contar. Sem esta série, o zero final foi lido como
// rigor por semanas.

/** Identificador do critério vigente. Muda junto com a regra, nunca em silêncio. */
export const CRITERION_ID = "quorum-v1:distinct-session-day-user-stated";

/**
 * Mede o funil de promoção e grava uma linha em promote_funnel.
 *
 * Roda DEPOIS de promoteFacts, para que `promoted` reflita o ciclo recém-concluído
 * e não o anterior.
 *
 * @param {import("pg").Pool} pool
 * @param {{ criterion?: string, sessionKey?: string, record?: boolean }} [opts]
 * @returns {Promise<{facts_total:number, with_support:number, with_user_support:number,
 *                    independent_support:number, promoted:number, criterion:string}>}
 */
export async function measurePromoteFunnel(pool, opts = {}) {
  const criterion = opts.criterion ?? CRITERION_ID;
  const sessionKey = opts.sessionKey ??
    "COALESCE(NULLIF(r.metadata->>'session_id',''), r.metadata->'provenance'->>'session_id', r.id::text)";
  const record = opts.record !== false;

  const res = await pool.query(
    `SELECT
       (SELECT count(*) FROM facts)                                              AS facts_total,
       (SELECT count(DISTINCT fact_id) FROM fact_supports)                       AS with_support,
       (SELECT count(DISTINCT fs.fact_id) FROM fact_supports fs
          JOIN records r ON r.id = fs.source_record_id
         WHERE r.prov_actor = 'user_stated')                                     AS with_user_support,
       (SELECT count(*) FROM (
          SELECT fact_id FROM (
            SELECT DISTINCT fs.fact_id, ${sessionKey} AS sess, r.created_at::date AS day
              FROM fact_supports fs JOIN records r ON r.id = fs.source_record_id
             WHERE r.prov_actor = 'user_stated') d
          GROUP BY fact_id HAVING count(*) >= 2) q)                              AS independent_support,
       (SELECT count(*) FROM facts WHERE trust_tier IN ('corroborated','known'))  AS promoted`,
  );
  const r = res.rows[0];
  const out = {
    facts_total: Number(r.facts_total),
    with_support: Number(r.with_support),
    with_user_support: Number(r.with_user_support),
    independent_support: Number(r.independent_support),
    promoted: Number(r.promoted),
    criterion,
  };

  if (record) {
    await pool.query(
      `INSERT INTO promote_funnel
         (criterion, facts_total, with_support, with_user_support, independent_support, promoted)
       VALUES ($1,$2,$3,$4,$5,$6)`,
      [criterion, out.facts_total, out.with_support, out.with_user_support,
       out.independent_support, out.promoted],
    );
  }
  return out;
}

/**
 * Onde o funil zera. Devolve o nome do primeiro estágio que caiu a zero enquanto
 * o anterior era não-nulo, ou null se nada zerou.
 *
 * O ponto de zerar é o diagnóstico: `with_support` zerado é extração parada;
 * `with_user_support` zerado é proveniência; `independent_support` zerado com
 * `with_user_support` alto é o critério não tendo o que contar — que é o caso.
 */
export function collapseStage(f) {
  const stages = [
    ["facts_total", f.facts_total],
    ["with_support", f.with_support],
    ["with_user_support", f.with_user_support],
    ["independent_support", f.independent_support],
    ["promoted", f.promoted],
  ];
  for (let i = 1; i < stages.length; i++) {
    if (stages[i][1] === 0 && stages[i - 1][1] > 0) return stages[i][0];
  }
  return null;
}

export default { measurePromoteFunnel, collapseStage, CRITERION_ID };
