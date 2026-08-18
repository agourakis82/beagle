#!/usr/bin/env node
// bin/funnel.mjs — o funil da Fase 2, sob demanda. SÓ LEITURA: não junta, não julga, não grava.
//
// Existe separado de `physio-join` e `judge-agreement` de propósito: olhar o estado não pode
// ter efeito colateral. Um comando que mede E altera faz a medição virar parte do fenômeno.
//
//   node bin/funnel.mjs
//
// Env: MEMORY_PG_DSN

import { makePool } from "../src/db.mjs";
import { physioFunnel } from "../src/physio-join.mjs";

const dsn = process.env.MEMORY_PG_DSN;
if (!dsn) { console.error("MEMORY_PG_DSN obrigatorio"); process.exit(2); }
const pool = makePool(dsn);

try {
  const f = await physioFunnel(pool);
  const linhas = [
    ["auto-relatos", f.auto_relatos, "ele falou de um estado dele"],
    ["  com canal", f.com_canal, "há uma grandeza que poderia testar"],
    ["  com canal e hora", f.com_canal_e_hora, "sem QUANDO não há confronto"],
    ["  consultados", f.consultados, "a fisiologia foi perguntada"],
    ["  com medida", f.com_medida, "havia o que medir naquele instante"],
    ["  INDEPENDENTE", f.com_medida_independente, "e a medida é de OUTRA modalidade"],
  ];
  console.log("FUNIL DA FASE 2\n");
  for (const [rot, v, nota] of linhas) {
    console.log(`  ${rot.padEnd(22)}${String(v).padStart(6)}   ${nota}`);
  }

  // O ultimo estagio do funil diz "tem o que confrontar". O VEREDITO e outra coisa, e mostrar
  // os dois juntos evita a leitura de que ter medida ja seria concordar.
  const v = await pool.query(
    `SELECT prereg_version, verdict, count(*)::int n
       FROM fact_agreement GROUP BY 1,2 ORDER BY 1,3 DESC`);
  console.log("\nVEREDITOS (regra congelada)\n");
  if (!v.rowCount) {
    console.log("  nenhum ainda — nada a declarar, e isso e um resultado");
  } else {
    for (const r of v.rows) {
      console.log(`  ${r.prereg_version}  ${r.verdict.padEnd(14)}${String(r.n).padStart(5)}`);
    }
    const c = v.rows.find((r) => r.verdict === "CONCORDA")?.n ?? 0;
    const d = v.rows.find((r) => r.verdict === "DISCORDA")?.n ?? 0;
    if (c + d > 0) {
      console.log(`\n  conclusivos: ${c + d}  (${c} concordam, ${d} discordam)`);
      console.log("  ⚠️ contagem por evento, NAO corroboracao — ver §5 do pre-registro");
    }
  }

  // A perda que o funil esconderia se so mostrasse quem passou.
  const perda = await pool.query(
    `SELECT count(*)::int n FROM facts
      WHERE self_report AND state_channel IS NOT NULL AND occurred_at IS NULL`);
  if (perda.rows[0].n) {
    console.log(`\n  perdidos por falta de HORA: ${perda.rows[0].n}  (nunca poderao ser confrontados)`);
  }
} finally {
  await pool.end();
}
