// physio-join.mjs — Fase 2: a junta entre o que ele disse e o que o corpo registrou.
//
// Até aqui, corpo e fala viviam em bancos que nunca se encontravam:
// `grep memory-pg apps/physiome/src/*.mjs` devolvia vazio. Medido hoje, a junta
// só existe num sentido — o pod do memory-pg alcança o beagle-pg, e o inverso
// dá "No route to host". Por isso ela mora deste lado.
//
// ⚠️ O QUE ISTO NÃO FAZ: dizer que o auto-relato está corroborado. Anexa a
// evidência disponível — qual medida existia, na janela do evento, no canal que
// poderia testá-la. Declarar acordo exige direção pré-registrada, e escolher a
// direção depois de ver o dado é pesca.
//
// O que responde é a pergunta anterior, hoje sem resposta: para quantos
// auto-relatos dele existe medida independente no instante certo? Sem esse
// número, o pré-registro da Fase 5 seria escrito às cegas.

/** Versão do mapa canal→medida. Muda junto com o mapa, nunca em silêncio. */
export const MAPPING_VERSION = "physio-map-v1";

/**
 * Canal do auto-relato → medidas que podem testá-lo.
 *
 * `independent` é a coluna que carrega a tese inteira. Uma medida só corrobora
 * se seus erros não forem correlacionados com os do relato — o corpo registrando
 * sozinho vale; ele declarando o próprio humor noutro app, não.
 *
 * Contagens medidas no corpus em 17-ago-2026, porque a densidade decide o que é
 * utilizável: um canal com 4.995 amostras em sete anos raramente cobre um
 * instante específico.
 */
export const CHANNEL_MAP = {
  arousal: [
    // 359k amostras: é o que de fato cobre um instante qualquer.
    { type: "HKQuantityTypeIdentifierHeartRate", independent: true },
    // 4.995 em 7 anos: esparso, cobre pouco, mas é a medida mais específica.
    { type: "HKQuantityTypeIdentifierHeartRateVariabilitySDNN", independent: true },
    { type: "HKQuantityTypeIdentifierRespiratoryRate", independent: true },
  ],
  fatigue: [
    { type: "HKQuantityTypeIdentifierRestingHeartRate", independent: true },
    { type: "HKQuantityTypeIdentifierHeartRateVariabilitySDNN", independent: true },
  ],
  sleep: [
    { type: "HKCategoryTypeIdentifierSleepAnalysis", independent: true },
    { type: "HKQuantityTypeIdentifierRespiratoryRate", independent: true },
  ],
  // ⚠️ valence NÃO tem canal independente. HKStateOfMindType existe (16 amostras)
  // e é ELE declarando o próprio humor num app da Apple — outro auto-relato por
  // outra porta, não outra modalidade. Contá-lo como corroboração seria a mesma
  // boca com dois microfones, que é exatamente a repetição que o plano proíbe.
  // Fica mapeado com independent=false para que a ausência seja VISÍVEL na
  // tabela, em vez de o canal simplesmente não aparecer.
  valence: [
    { type: "HKStateOfMindType", independent: false },
  ],
  // Sem canal objetivo. Declarado vazio de propósito: um canal ausente do mapa
  // seria indistinguível de um canal esquecido.
  pain: [],
  // Contexto, não estado. Viria de calendário/turno, que não está aqui.
  oncall: [],
};

/**
 * Resume as medidas de um tipo em torno de um instante, e situa o valor na linha
 * de base DELE.
 *
 * A linha de base é a distribuição dele nos 90 dias ANTERIORES ao evento —
 * não a de uma população, e não a vida inteira. Uma referência populacional diria
 * respeito a outra pessoa; a vida inteira ignora que a linha de base dele muda.
 * Só olha para trás porque usar dados posteriores ao evento para julgar o evento
 * é vazamento.
 *
 * O percentil é DIREÇÃO-LIVRE de propósito: diz o quanto o valor é incomum para
 * ele, nunca se isso concorda com o que ele relatou. A direção pertence ao
 * pré-registro.
 *
 * @param {import("pg").Pool} bpg  pool do beagle-pg (onde vive health_samples)
 * @param {{type:string, at:string|Date, windowMinutes:number}} q
 */
export async function summariseWindow(bpg, { type, at, windowMinutes }) {
  const janela = await bpg.query(
    `SELECT count(*)::int n, avg(value) media, min(unit) unit
       FROM health_samples
      WHERE type = $1
        AND ts BETWEEN $2::timestamptz - make_interval(mins => $3)
                   AND $2::timestamptz + make_interval(mins => $3)`,
    [type, at, windowMinutes],
  );
  const { n, media, unit } = janela.rows[0];
  if (!n) return { n_samples: 0, mean_value: null, unit: null, baseline_pct: null, baseline_n: 0 };

  const base = await bpg.query(
    `SELECT count(*)::int n,
            count(*) FILTER (WHERE value <= $4)::int abaixo
       FROM health_samples
      WHERE type = $1
        AND ts <  $2::timestamptz
        AND ts >= $2::timestamptz - make_interval(days => $3)`,
    [type, at, 90, media],
  );
  const bn = base.rows[0].n;
  const pct = bn > 0 ? Math.round((100 * base.rows[0].abaixo) / bn) : null;
  return {
    n_samples: n,
    mean_value: Number(media),
    unit,
    baseline_pct: pct,
    baseline_n: bn,
  };
}

/**
 * Anexa a evidência fisiológica aos auto-relatos que têm canal e hora.
 *
 * Grava tambem as linhas com `n_samples = 0`. "Não havia medida" é um achado: se
 * a ausência não fosse gravada, a falta de cobertura sumiria do funil e o
 * pré-registro seria escrito supondo uma densidade que não existe.
 *
 * @param {import("pg").Pool} mpg  memory-pg (facts)
 * @param {import("pg").Pool} bpg  beagle-pg (health_samples)
 * @param {{windowMinutes?:number, limit?:number|null, since?:string|null}} [opts]
 */
export async function joinPhysiology(mpg, bpg, opts = {}) {
  const { windowMinutes = 60, limit = null, since = null } = opts;

  const alvo = await mpg.query(
    `SELECT f.id, f.state_channel, f.occurred_at
       FROM facts f
      WHERE f.self_report
        AND f.state_channel IS NOT NULL
        AND f.occurred_at IS NOT NULL
        AND ($1::timestamptz IS NULL OR f.occurred_at >= $1::timestamptz)
      ORDER BY f.occurred_at DESC
      ${limit ? "LIMIT $2" : ""}`,
    limit ? [since, limit] : [since],
  );

  const stats = { facts: alvo.rowCount, rows: 0, comCobertura: 0, semCobertura: 0, semCanal: 0 };

  for (const f of alvo.rows) {
    const medidas = CHANNEL_MAP[f.state_channel] ?? [];
    if (!medidas.length) { stats.semCanal++; continue; }
    for (const m of medidas) {
      const s = await summariseWindow(bpg, {
        type: m.type, at: f.occurred_at, windowMinutes,
      });
      await mpg.query(
        `INSERT INTO fact_measurements
           (fact_id, channel, measure_type, window_minutes, n_samples, mean_value, unit,
            baseline_pct, baseline_n, independent, mapping_version)
         VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11)
         ON CONFLICT (fact_id, measure_type, window_minutes) DO UPDATE SET
           n_samples = EXCLUDED.n_samples, mean_value = EXCLUDED.mean_value,
           unit = EXCLUDED.unit, baseline_pct = EXCLUDED.baseline_pct,
           baseline_n = EXCLUDED.baseline_n, independent = EXCLUDED.independent,
           mapping_version = EXCLUDED.mapping_version, computed_at = now()`,
        [f.id, f.state_channel, m.type, windowMinutes, s.n_samples, s.mean_value, s.unit,
         s.baseline_pct, s.baseline_n, m.independent, MAPPING_VERSION],
      );
      stats.rows++;
      if (s.n_samples > 0) stats.comCobertura++; else stats.semCobertura++;
    }
  }
  return stats;
}

/**
 * O funil da Fase 2: de auto-relato dele até evidência independente no instante.
 *
 * Cada estágio que zera aponta o estágio, igual ao funil de promoção. O último
 * NÃO é "corroborado" — é "tem medida independente para ser confrontada", que é
 * a pergunta que o pré-registro precisa responder antes de existir.
 */
export async function physioFunnel(mpg) {
  const r = await mpg.query(
    `SELECT
       (SELECT count(*) FROM facts WHERE self_report)                             AS auto_relatos,
       (SELECT count(*) FROM facts WHERE self_report AND state_channel IS NOT NULL) AS com_canal,
       (SELECT count(*) FROM facts
         WHERE self_report AND state_channel IS NOT NULL AND occurred_at IS NOT NULL) AS com_canal_e_hora,
       (SELECT count(DISTINCT fact_id) FROM fact_measurements)                    AS consultados,
       (SELECT count(DISTINCT fact_id) FROM fact_measurements WHERE n_samples > 0) AS com_medida,
       (SELECT count(DISTINCT fact_id) FROM fact_measurements
         WHERE n_samples > 0 AND independent)                                     AS com_medida_independente`,
  );
  const o = r.rows[0];
  return Object.fromEntries(Object.entries(o).map(([k, v]) => [k, Number(v)]));
}

export default { CHANNEL_MAP, MAPPING_VERSION, summariseWindow, joinPhysiology, physioFunnel };
