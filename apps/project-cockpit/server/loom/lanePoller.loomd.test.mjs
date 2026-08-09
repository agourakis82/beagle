// O loomd pega carona no sweep do LanePoller: mesmo exec, mesmo pod, mesmo relógio. O que estes
// testes protegem é a fronteira entre as duas fontes — e, principalmente, o que acontece quando
// a fonte boa cai. Um board que fica igual ao de ontem quando o loomd morre é indistinguível de
// sucesso a olho nu; é por isso que a queda tem nome, motivo e lista de lanes perdidas.
import { test } from "node:test";
import assert from "node:assert/strict";
import { LanePoller } from "./lanePoller.mjs";
import { EXACT } from "./loomd.mjs";
import { PEEK_DELIM, ALIVE_DELIM, LOOMD_DELIM } from "../platform-bridge.mjs";

const WORKING = "● lowering the IR\n  ⏵⏵ auto mode on · esc to interrupt · ctrl+t to show tasks\n";
const alive = (...l) => `${ALIVE_DELIM}\n${l.join("\n")}\n`;
const screen = (lane, body) => `${PEEK_DELIM}${lane}\n${body}\n`;
const loomdBlock = (lanes, ms = 1000) =>
  `${LOOMD_DELIM}\n${JSON.stringify({ ok: true, observed_at_ms: ms, lanes })}\n`;
const LOOM1 = { lane: "loom-1", kind: "awaiting_approval", confidence: "exact", observed_at_ms: 1000, turns: 3,
  detail: "posso escrever em src/main.rs?", pending_approval: ["7", "item/fileChange/requestApproval"] };

// Um sweep REAL: bloco do loomd, depois liveness, depois as telas.
const sweep = (loomd) => (loomd ? loomdBlock([LOOM1]) : `${LOOMD_DELIM}\n`)
  + alive("claude-1", "repo") + screen("claude-1", WORKING) + screen("repo", "workspace%\n");

function poller(stdout, now = () => 1_000_000) {
  let out = stdout, fail = false;
  const execFn = (bin, argv, opts, cb) => (fail ? cb(new Error("cluster unreachable"), "", "") : cb(null, out, ""));
  const p = new LanePoller({ kubectl: "kubectl", ns: "beagle", execFn, now });
  return { p, set: (s) => { out = s; }, breakExec: () => { fail = true; } };
}

test("um sweep com o bloco do loomd popula a tabela exata sem tocar nos vereditos de tela", async () => {
  const { p } = poller(sweep(true));
  await p.poll();
  assert.equal(p.loomd("loom-1").confidence, EXACT);
  assert.equal(p.loomd("loom-1").state, "waiting");
  assert.deepEqual(p.loomd("loom-1").pendingApproval, { id: "7", method: "item/fileChange/requestApproval" });
  assert.equal(p.loomdTruth().mode, "observed");
  // As 11 lanes continuam vindo da tela, e continuam sendo tela.
  assert.equal(p.get("claude-1").state, "running");
  assert.equal(p.loomd("claude-1"), null, "nada que veio de regex entra na tabela exata");
});

test("as duas leituras compartilham UM relógio — o do sweep", async () => {
  // Dois relógios produziriam um card fresco ao lado de um card velho dizendo coisas diferentes,
  // com duas janelas de isStale concorrendo no mesmo board.
  const { p } = poller(sweep(true), () => 5_555_000);
  await p.poll();
  assert.equal(p.get("claude-1").observedAt, 5_555_000);
  assert.equal(p.loomdTruth().observedAt, 1000, "o loomd carimba a própria observação");
  assert.equal(p.loomdTruth().mode, "observed", "e ela é fresca pelo relógio do sweep");
});

test("o sweep SEGUINTE sem o bloco derruba o exact — com nome e motivo, nunca em silêncio", async () => {
  const { p, set } = poller(sweep(true));
  await p.poll();
  assert.equal(p.loomdAll().size, 1);
  set(sweep(false));                       // loomd parado: o curl volta vazio
  await p.poll();
  const t = p.loomdTruth();
  assert.equal(t.mode, "down");
  assert.deepEqual(t.lost, ["loom-1"]);
  assert.match(t.error, /não respondeu/);
  assert.equal(p.loomdAll().size, 0, "nenhum card exato sobrevive à medição de que a fonte caiu");
  // E o board não encolheu: as 11 continuam lá, ainda lidas da tela.
  assert.equal(p.get("claude-1").state, "running");
  assert.equal(p.get("repo").state, "idle");
});

test("o exec falhar NÃO apaga a tabela exata — ausência de medição não é medição de ausência", async () => {
  const { p, breakExec } = poller(sweep(true));
  await p.poll();
  breakExec();
  const ok = await p.poll();
  assert.equal(ok, false);
  assert.match(p.lastError, /unreachable/);
  assert.equal(p.loomd("loom-1")?.confidence, EXACT, "a leitura envelhece, não é descartada");
  assert.equal(p.loomdTruth().mode, "observed", "ainda dentro do teto de frescor");
});

test("e envelhecendo além do teto, a leitura exata parada se declara `stale`", async () => {
  let t = 1_000_000;
  const { p, breakExec } = poller(sweep(true), () => t);
  await p.poll();
  breakExec();
  t += 300_000;                            // 5 min de cluster fora
  await p.poll();
  assert.equal(p.loomdTruth().mode, "stale");
  assert.match(p.loomdTruth().error, /sem resposta nova/);
});
