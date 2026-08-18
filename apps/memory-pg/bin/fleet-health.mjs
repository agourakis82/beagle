#!/usr/bin/env node
// bin/fleet-health.mjs — vigia os modelos DECLARADOS COMO DEPENDÊNCIA e avisa quando eles
// somem ou ficam lentos demais para servir.
//
// Env:
//   FLEET_MODELS       lista separada por vírgula (ex.: "r1-distill-70b,qwen2.5-14b")
//   FLEET_ROUTER_URL   roteador OpenAI-compat (default: o LiteLLM do cluster)
//   FLEET_SLOW_MS      acima disto o modelo está vivo mas inútil (default 30000)
//   FLEET_TIMEOUT_MS   teto por prova (default 120000)
//   NTFY_*             destino do aviso
//
// Sai com 0 mesmo alarmando: um CronJob em Error vira ruído no cluster e some da vista. O
// canal do alarme é o ntfy, não o exit code.

import { fleetHealth, avisarFrota } from "../src/fleet-health.mjs";

const modelos = String(process.env.FLEET_MODELS || "").split(",").map((s) => s.trim()).filter(Boolean);
const routerUrl = process.env.FLEET_ROUTER_URL || "http://router.llm-router.svc.cluster.local:4000";
const lentoMs = Number(process.env.FLEET_SLOW_MS || 30000);
const timeoutMs = Number(process.env.FLEET_TIMEOUT_MS || 120000);

if (!modelos.length) {
  // Sem declaração não há vigia. Dizer isso alto é melhor que fingir saúde: um alarme que não
  // sabe do que depende é exatamente o alarme que estava no lugar errado antes.
  console.log("[fleet-health] FLEET_MODELS vazio — nada declarado como dependência, nada vigiado");
  process.exit(0);
}

const h = await fleetHealth({ modelos, routerUrl, lentoMs, timeoutMs });
for (const r of h.resultados) {
  console.log(`[fleet-health] ${r.model.padEnd(22)} ${r.ok ? "ok " : "FORA"} ${(r.ms / 1000).toFixed(1)}s` +
    (r.erro ? `  ${r.erro}` : ""));
}

if (h.ok) {
  console.log(`[fleet-health] frota sadia: ${h.declarados} modelo(s) declarados respondem`);
  process.exit(0);
}

console.error(`[fleet-health] ALARME: ${h.motivo}`);
const publicou = await avisarFrota(h.motivo);
console.log(`[fleet-health] aviso publicado: ${publicou}`);
process.exit(0);
