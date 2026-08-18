// judge.mjs — aplica a regra congelada do pré-registro e grava o veredito.
//
// Este arquivo NÃO decide nada. Ele lê o que `agreement.mjs` fixou a partir de
// `docs/PREREG_FASE2_DIRECAO_v1.md`, e se recusa a rodar se o documento tiver mudado.
//
// A ordem em que as peças foram construídas é o argumento:
//   1. o pré-registro foi congelado quando a polaridade NÃO EXISTIA no banco;
//   2. a polaridade veio de um extrator que lê só o texto dele — cego à fisiologia;
//   3. só então o julgamento passou a existir.
// Nenhuma etapa pôde ser ajustada olhando o resultado da seguinte.

import { julgarRelato, verificarPrereg, PREREG_VERSION, PREREG_SHA256 } from "./agreement.mjs";

/**
 * Auto-relatos prontos para confronto: canal, sinal, hora — e ao menos uma medida anexada.
 *
 * O `JOIN` com `fact_measurements` é interno de propósito: sem medida não há o que julgar, e
 * inventar uma linha `INELEGIVEL` para cada auto-relato sem cobertura encheria a tabela de
 * vereditos que dizem apenas "a fisiologia não estava lá". Isso já é visível no funil.
 */
const SQL_CANDIDATOS = `
  SELECT f.id, f.state_channel, f.state_polarity,
         json_agg(json_build_object(
           'channel', f.state_channel,
           'measure_type', m.measure_type,
           'n_samples', m.n_samples,
           'baseline_pct', m.baseline_pct,
           'baseline_n', m.baseline_n,
           'independent', m.independent
         )) AS medidas
    FROM facts f
    JOIN fact_measurements m ON m.fact_id = f.id
   WHERE f.self_report
     AND f.state_channel  IS NOT NULL
     AND f.state_polarity IS NOT NULL
     AND f.occurred_at    IS NOT NULL
   GROUP BY f.id, f.state_channel, f.state_polarity`;

/**
 * Julga todos os candidatos e grava o veredito.
 *
 * @param {import("pg").Pool} pool
 * @param {{ prereg: string, apply?: boolean }} opts
 *   prereg  caminho do documento congelado — CONFERIDO antes de qualquer julgamento
 *   apply   false (padrão) apenas conta. Gravar veredito não pode ser efeito acidental de
 *           rodar o comando sem argumentos.
 */
export async function judgeAll(pool, { prereg, apply = false } = {}) {
  // Se o documento mudou, isto LANÇA. Julgar sob uma regra que mudou sem ninguém declarar
  // seria pior que não julgar: produziria números com aparência de rigor.
  const sel = await verificarPrereg(prereg);

  const { rows } = await pool.query(SQL_CANDIDATOS);
  const contagem = {
    CONCORDA: 0, DISCORDA: 0, INCONCLUSIVO: 0, INELEGIVEL: 0, EXPLORATORIO: 0,
  };
  const vereditos = [];

  for (const r of rows) {
    const j = julgarRelato(r.medidas ?? [], r.state_polarity);
    contagem[j.veredito] = (contagem[j.veredito] ?? 0) + 1;
    vereditos.push({ ...j, fact_id: r.id, channel: r.state_channel, polarity: r.state_polarity });
  }

  if (!apply) return { candidatos: rows.length, contagem, gravados: 0, applied: false, ...sel };

  let gravados = 0;
  for (const v of vereditos) {
    // ON CONFLICT DO NOTHING por (fact_id, prereg_version): rejulgar sob a MESMA regra não
    // reescreve o veredito. Mudança de direção exige nova versão, e aí a linha nova convive
    // com a antiga em vez de apagá-la.
    const r = await pool.query(
      `INSERT INTO fact_agreement
         (fact_id, prereg_version, prereg_sha256, verdict, motivo, reforco, channel, polarity)
       VALUES ($1,$2,$3,$4,$5,$6,$7,$8)
       ON CONFLICT (fact_id, prereg_version) DO NOTHING`,
      [v.fact_id, PREREG_VERSION, PREREG_SHA256, v.veredito, v.motivo, v.reforco ?? 0,
       v.channel, v.polarity],
    );
    gravados += r.rowCount ?? 0;
  }
  return { candidatos: rows.length, contagem, gravados, applied: true, ...sel };
}

export default { judgeAll };
