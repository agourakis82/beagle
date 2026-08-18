#!/usr/bin/env node
// bin/judge-agreement.mjs — o último elo da Fase 2.
//
// Aplica a regra congelada de `docs/PREREG_FASE2_DIRECAO_v2.md` aos auto-relatos que têm
// canal, sinal, hora e medida independente anexada — e grava o veredito com a versão e o
// hash do pré-registro na linha.
//
// Simulação é o padrão. Gravar veredito não pode ser efeito acidental de rodar sem argumentos.
//
//   node bin/judge-agreement.mjs                # conta, não grava
//   node bin/judge-agreement.mjs --apply        # grava
//
// Env: MEMORY_PG_DSN, PREREG_PATH (default: docs/PREREG_FASE2_DIRECAO_v2.md do repo)

import { join, dirname } from "node:path";
import { fileURLToPath } from "node:url";
import { makePool } from "../src/db.mjs";
import { judgeAll } from "../src/judge.mjs";

const RAIZ = join(dirname(fileURLToPath(import.meta.url)), "..", "..", "..");
const prereg = process.env.PREREG_PATH || join(RAIZ, "docs", "PREREG_FASE2_DIRECAO_v2.md");
const apply = process.argv.includes("--apply");
const dsn = process.env.MEMORY_PG_DSN;
if (!dsn) { console.error("MEMORY_PG_DSN obrigatorio"); process.exit(2); }

const pool = makePool(dsn);
try {
  const r = await judgeAll(pool, { prereg, apply });
  console.log(`pré-registro ${r.versao}  sha256=${r.sha256.slice(0, 12)}…  (conferido)`);
  console.log(`candidatos: ${r.candidatos}${apply ? `   gravados: ${r.gravados}` : "   (simulação)"}`);
  console.log("");
  // A ordem imprime primeiro o que INTERESSA e o que INCOMODA, lado a lado. Um relatório que
  // esconde DISCORDA no fim convida a ler só a primeira linha.
  for (const k of ["CONCORDA", "DISCORDA", "INCONCLUSIVO", "EXPLORATORIO", "INELEGIVEL"]) {
    console.log(`  ${k.padEnd(14)} ${r.contagem[k] ?? 0}`);
  }
  const c = r.contagem.CONCORDA ?? 0, d = r.contagem.DISCORDA ?? 0;
  console.log("");
  if (c + d === 0) {
    console.log("  nenhum veredito conclusivo ainda — nada a declarar, e isso é um resultado");
  } else {
    // ⚠️ Deliberadamente NÃO chamado de "taxa de acerto". Concordância por evento não é
    // corroboração: corroboração é sobre o padrão, e o padrão exige tratar a dependência
    // entre eventos (plantão, dia, hora) que este número ignora.
    console.log(`  conclusivos: ${c + d}  (${c} concordam, ${d} discordam)`);
    console.log("  ⚠️ isto é contagem por evento, NÃO corroboração — ver §5 do pré-registro");
  }
} finally {
  await pool.end();
}
