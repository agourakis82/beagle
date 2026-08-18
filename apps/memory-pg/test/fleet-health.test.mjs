// fleet-health.test.mjs — o alarme da frota.
//
// Dois modos de falha reais, e o alarme tem que pegar os DOIS:
//   1. o modelo nao responde (o `r1-distill-70b` apareceu em `/v1/models` com o backend fora);
//   2. o modelo responde e e inutil de tao lento (o `coder:32b` na CPU: 4min28s por 2 tokens).
//
// E um modo de falso positivo que mataria o alarme: tocar por deployment em zero replicas. O
// zero e DELIBERADO — os cientificos dividem uma RTX 8000 e so um fica ativo por vez. Um
// alarme que tocasse a cada zero tocaria sempre, seria silenciado, e ai ninguem olharia
// quando ele estivesse certo.

import { test } from "node:test";
import assert from "node:assert/strict";
import { fleetHealth, provaModelo, avisarFrota } from "../src/fleet-health.mjs";

const ok1tok = async () => ({ ok: true, text: async () => "{}" });
const erro500 = async () => ({ ok: false, status: 500, text: async () => "Connection error." });

test("frota sadia nao alarma", async () => {
  const h = await fleetHealth({ modelos: ["a", "b"], routerUrl: "http://r", fetchImpl: ok1tok });
  assert.equal(h.ok, true);
  assert.equal(h.motivo, null);
  assert.equal(h.declarados, 2);
});

test("ALARMA quando um modelo de que dependemos nao responde", async () => {
  const h = await fleetHealth({ modelos: ["vivo", "morto"], routerUrl: "http://r",
    fetchImpl: async (u, o) => (JSON.parse(o.body).model === "morto" ? erro500() : ok1tok()) });
  assert.equal(h.ok, false);
  assert.match(h.motivo, /morto/);
  assert.match(h.motivo, /1\/2/);
});

// 🚨 O modo que passou despercebido por horas: vivo, respondendo, e inutil.
test("ALARMA quando o modelo responde mas esta LENTO demais", async () => {
  let t = 0;
  const lento = async () => { t += 60000; return { ok: true, text: async () => "{}" }; };
  const relogio = Date.now;
  Date.now = () => 1700000000000 + t;
  try {
    const h = await fleetHealth({ modelos: ["cpu-bound"], routerUrl: "http://r",
      fetchImpl: lento, lentoMs: 30000 });
    assert.equal(h.ok, false);
    assert.match(h.motivo, /LENTOS/);
    assert.match(h.motivo, /cpu-bound/);
  } finally { Date.now = relogio; }
});

test("erro de rede conta como nao-responde, nao como excecao", async () => {
  const r = await provaModelo("x", { routerUrl: "http://r",
    fetchImpl: async () => { throw new Error("fetch failed"); } });
  assert.equal(r.ok, false);
  assert.match(r.erro, /fetch failed/);
});

// Sem dependencia declarada nao ha o que vigiar — e inventar uma lista varrendo o cluster
// faria o alarme tocar pelos zeros deliberados.
test("lista vazia nao alarma e nao inventa alvo", async () => {
  let chamou = false;
  const h = await fleetHealth({ modelos: [], routerUrl: "http://r",
    fetchImpl: async () => { chamou = true; return ok1tok(); } });
  assert.equal(h.ok, true);
  assert.equal(chamou, false, "nao sai perguntando por conta propria");
});

// ⚠️ O bug que deixou o alarme de extracao mudo: cabecalho HTTP e ByteString. Um travessao no
// Title faz o `fetch` LANCAR antes de publicar — o alarme existe, roda, e nunca alcanca.
test("nenhum cabecalho do aviso escapa de latin-1", async () => {
  const capturados = [];
  await avisarFrota(
    "modelo — não responde (travessão e acento de propósito)",
    { NTFY_TOPIC: "t", NTFY_USER: "u", NTFY_PASSWORD: "p" },
    async (u, o) => { capturados.push(o.headers); return { ok: true }; });

  assert.equal(capturados.length, 1);
  for (const [k, v] of Object.entries(capturados[0])) {
    for (const ch of String(v)) {
      assert.ok(ch.codePointAt(0) <= 255, `cabecalho ${k} fora de latin-1: ${JSON.stringify(ch)}`);
    }
  }
});

test("sem topico o aviso nem tenta publicar", async () => {
  let chamou = false;
  const r = await avisarFrota("x", {}, async () => { chamou = true; return { ok: true }; });
  assert.equal(r, false);
  assert.equal(chamou, false);
});

// As duas faixas do desenho vivem em endpoints DIFERENTES: o modelo de volume no Ollama do
// Spark, o r1 atras do roteador. Um alarme com um unico endereco vigiaria metade da frota
// achando que vigia a frota inteira.
test("cada dependencia carrega o proprio endereco", async () => {
  const vistos = [];
  await fleetHealth({
    modelos: ["rapido@http://spark:11434", "caro@http://router:4000", "sem-arroba"],
    routerUrl: "http://padrao:9999",
    fetchImpl: async (u, o) => { vistos.push([JSON.parse(o.body).model, u]); return { ok: true, text: async () => "{}" }; },
  });
  assert.deepEqual(vistos, [
    ["rapido", "http://spark:11434/v1/chat/completions"],
    ["caro", "http://router:4000/v1/chat/completions"],
    ["sem-arroba", "http://padrao:9999/v1/chat/completions"],
  ]);
});

// Nome de modelo nao tem "@", mas URL tem ":" e "/". Cortar no PRIMEIRO "@" e o que mantem
// `modelo@http://host:porta/caminho` inteiro.
test("o corte respeita url com porta e caminho", async () => {
  const vistos = [];
  await fleetHealth({
    modelos: ["qwen2.5:14b@http://192.168.3.24:11434/v1x"],
    fetchImpl: async (u, o) => { vistos.push([JSON.parse(o.body).model, u]); return { ok: true, text: async () => "{}" }; },
  });
  assert.equal(vistos[0][0], "qwen2.5:14b", "o nome mantem os dois-pontos");
  assert.equal(vistos[0][1], "http://192.168.3.24:11434/v1x/v1/chat/completions");
});
