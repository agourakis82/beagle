#!/usr/bin/env node
// bin/physio-join.mjs — anexa a evidência fisiológica aos auto-relatos.
//
//   MEMORY_PG_DSN=... BEAGLE_PG_DSN=... node bin/physio-join.mjs
//   ... node bin/physio-join.mjs --window 30 --since 2026-06-01 --limit 200
//
// ⚠️ Isto NÃO promove nada a `corroborated`. Anexa a medida que existia no
// instante do relato, no canal que poderia testá-lo. Dizer se ela CONCORDA exige
// direção pré-registrada.

import pg from "pg";
import { makePool } from "../src/db.mjs";
import { joinPhysiology, physioFunnel, MAPPING_VERSION } from "../src/physio-join.mjs";

function arg(name, fallback = null) {
  const i = process.argv.indexOf(`--${name}`);
  return i >= 0 && process.argv[i + 1] && !process.argv[i + 1].startsWith("--")
    ? process.argv[i + 1] : fallback;
}

const bdsn = process.env.BEAGLE_PG_DSN;
if (!bdsn) {
  console.error("BEAGLE_PG_DSN não definido — é onde vive health_samples.");
  console.error("A junta só funciona neste sentido: o memory-pg alcança o beagle-pg,");
  console.error("e o inverso dá 'No route to host'.");
  process.exit(2);
}

const mpg = makePool();
const bpg = new pg.Pool({ connectionString: bdsn, connectionTimeoutMillis: 10000 });

try {
  const windowMinutes = Number(arg("window", "60"));
  const limitRaw = arg("limit");
  const st = await joinPhysiology(mpg, bpg, {
    windowMinutes,
    since: arg("since"),
    limit: limitRaw ? Number(limitRaw) : null,
  });
  console.log(`mapa           : ${MAPPING_VERSION}   janela: ±${windowMinutes}min`);
  console.log(`auto-relatos   : ${st.facts}`);
  console.log(`  sem canal mapeado : ${st.semCanal}`);
  console.log(`linhas gravadas: ${st.rows}   com medida: ${st.comCobertura}   sem medida: ${st.semCobertura}`);

  const f = await physioFunnel(mpg);
  console.log("");
  console.log("funil da Fase 2:");
  console.log(`  auto-relatos              ${f.auto_relatos}`);
  console.log(`  com canal                 ${f.com_canal}`);
  console.log(`  com canal e hora          ${f.com_canal_e_hora}`);
  console.log(`  consultados               ${f.consultados}`);
  console.log(`  COM medida                ${f.com_medida}`);
  console.log(`  com medida INDEPENDENTE   ${f.com_medida_independente}`);
  console.log("");
  console.log("  (o último estágio é 'tem o que confrontar', NÃO 'corroborado')");
} finally {
  await mpg.end();
  await bpg.end();
}
