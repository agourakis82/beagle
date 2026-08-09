import { test } from "node:test";
import assert from "node:assert/strict";
import {
  decideKey, decideIsolate, decideLoomdApprove, registerLaneActionRoutes,
} from "./laneActions.mjs";
import { LOOMD_HTTP_DELIM } from "./platform-bridge.mjs";

const waiting = (approveKey) => ({ state: "waiting", approveKey, detail: "Do you want to proceed?" });

// ─── the refusal is the feature ──────────────────────────────────────────────────────────

test("a question that needs a SENTENCE never accepts a keystroke", () => {
  // Measured shape (kimi-cli1): agent asks something open, box empty, nothing running. The
  // classifier already marks approveKey = null; until now nothing enforced it.
  const d = decideKey({ lane: "kimi-cli1", key: "enter", verdict: waiting(null) });
  assert.equal(d.ok, undefined);
  assert.equal(d.status, 409);
  assert.match(d.error, /resposta digitada/);
  assert.match(d.error, /abra o terminal/, "the refusal must say what to do instead");
});

test("the key must be the one the lane actually asked for", () => {
  assert.equal(decideKey({ lane: "codex-2", key: "enter", verdict: waiting("enter") }).ok, true);
  assert.equal(decideKey({ lane: "codex-2", key: "y", verdict: waiting("enter") }).status, 409);
  assert.match(decideKey({ lane: "codex-2", key: "y", verdict: waiting("enter") }).error, /espera "enter"/);
  assert.equal(decideKey({ lane: "claude-1", key: "y", verdict: waiting("y") }).ok, true);
});

test("a lane that is NOT waiting gets nothing confirmed", () => {
  for (const state of ["running", "idle", "stuck", "exited", "unknown"]) {
    const d = decideKey({ lane: "claude-1", key: "y", verdict: { state, approveKey: "y" } });
    assert.equal(d.status, 409, state);
    assert.match(d.error, new RegExp(state));
  }
});

test("esc is the one key that also works on a lane that is working — it confirms nothing", () => {
  // The CLIs advertise it themselves ("esc to interrupt"), so interrupting is a real operator act.
  assert.equal(decideKey({ lane: "claude-1", key: "esc", verdict: { state: "running", approveKey: null } }).ok, true);
  assert.equal(decideKey({ lane: "kimi-cli1", key: "esc", verdict: waiting(null) }).ok, true);
  assert.equal(decideKey({ lane: "repo", key: "esc", verdict: { state: "idle" } }).status, 409);
});

test("never observed is never approved — and unknown lanes/keys are refused up front", () => {
  assert.match(decideKey({ lane: "codex-3", key: "y", verdict: null }).error, /nunca observada/);
  assert.equal(decideKey({ lane: "not-a-lane", key: "y", verdict: waiting("y") }).status, 404);
  assert.equal(decideKey({ lane: "repo", key: "C-c", verdict: waiting("y") }).status, 400);
  assert.match(decideKey({ lane: "repo", key: "rm -rf /", verdict: waiting("y") }).error, /não permitida/);
});

test("isolate only moves a lane at rest, AT A SHELL, and only into a worktree that exists", () => {
  const shell = (state) => ({ state, atShell: true });
  assert.equal(decideIsolate({ lane: "codex-1", verdict: shell("idle"), worktreeExists: true }).ok, true);
  assert.equal(decideIsolate({ lane: "codex-1", verdict: shell("exited"), worktreeExists: true }).ok, true);
  const busy = decideIsolate({ lane: "claude-1", verdict: { state: "running", atShell: false }, worktreeExists: true });
  assert.equal(busy.status, 409);
  assert.match(busy.error, /perde o contexto/, "the cost must be stated, not implied");
  assert.match(decideIsolate({ lane: "claude-1", verdict: { state: "waiting", atShell: false }, worktreeExists: true }).error, /waiting/);

  // The one that nearly went wrong: an agent CLI idling at ITS OWN input box is "idle" too, and
  // `cd /workspace/.wt/codex-1` typed there is not a command — it is a request to the agent.
  const agentIdle = decideIsolate({ lane: "codex-1", verdict: { state: "idle", atShell: false }, worktreeExists: true });
  assert.equal(agentIdle.status, 409);
  assert.match(agentIdle.error, /prompt do agente/);
  assert.match(agentIdle.error, /feche o agente/, "say what unblocks it");

  const missing = decideIsolate({ lane: "codex-1", verdict: shell("idle"), worktreeExists: false });
  assert.match(missing.error, /worktree ausente/);
  assert.match(missing.error, /sounio-lane-worktrees --apply/, "say the command that fixes it");
});

// ─── the routes: decide on a FRESH screen, and never exec on a refusal ───────────────────

function harness({
  verdictsByCall = [], refreshOk = true,
  // A segunda fonte, como o LanePoller a publica: Map(lane → card) + o veredito sobre a fonte.
  // Sem loomd no ar, o padrão é o que o `ingest` produz quando o bloco não veio.
  loomdLanes = {},
  loomdTruth = { mode: "absent", truthMode: "unknown", lost: [], error: "o exec não trouxe o bloco @@LOOMD:" },
  // Resposta do curl ao loomd. `null` em `httpCode` = o curl não teve resposta HTTP nenhuma.
  loomdReply = { httpCode: 200, body: '{"ok":true,"lane":"loom-1","method":"execCommandApproval","allow":true}' },
} = {}) {
  const execs = [];
  let sweeps = 0;
  const lanes = new Map(Object.entries(loomdLanes));
  const poller = {
    lastError: null,
    refreshNow: async () => { sweeps++; return refreshOk; },
    get: () => verdictsByCall[Math.min(sweeps - 1, verdictsByCall.length - 1)] ?? null,
    loomd: (lane) => lanes.get(lane) || null,
    loomdAll: () => lanes,
    loomdTruth: () => loomdTruth,
  };
  const routes = {};
  const app = { post: (path, h) => { routes[path] = h; } };
  registerLaneActionRoutes(app, {
    poller, kubectl: "kubectl", ns: "beagle",
    execFn: (bin, argv, opts, cb) => {
      execs.push(argv);
      if (String(argv.at(-1)).includes("curl")) {
        const out = loomdReply.httpCode === null
          ? loomdReply.body
          : `${loomdReply.body}\n${LOOMD_HTTP_DELIM}${loomdReply.httpCode}`;
        return cb(loomdReply.err || null, out, loomdReply.stderr || "");
      }
      cb(null, "yes\n", "");
    },
  });
  const call = async (path, params, body) => {
    let code = 200, payload = null;
    const res = { status(c) { code = c; return this; }, json(p) { payload = p; return this; } };
    await routes[path]({ params, body }, res);
    return { code, payload };
  };
  return { call, execs, sweeps: () => sweeps };
}

test("the route re-reads the screen BEFORE deciding — never from a 12s-old verdict", async () => {
  const h = harness({ verdictsByCall: [waiting("y")] });
  const r = await h.call("/api/mobile/v1/lanes/:lane/key", { lane: "codex-2" }, { key: "y" });
  assert.equal(r.code, 200);
  assert.equal(h.sweeps() >= 2, true, "one sweep to decide, one so the card catches up");
  assert.equal(h.execs.length, 1);
  assert.match(h.execs[0].at(-1), / exec tmux send-keys -t codex-2 y$/);
  assert.equal(r.payload.data.verdictBefore.state, "waiting", "report what we acted on");
});

test("a refusal sends NOTHING to the lane", async () => {
  const h = harness({ verdictsByCall: [{ state: "running", approveKey: null }] });
  const r = await h.call("/api/mobile/v1/lanes/:lane/key", { lane: "claude-1" }, { key: "y" });
  assert.equal(r.code, 409);
  assert.equal(h.execs.length, 0, "no exec on a refusal — this is the invariant that matters");
  assert.equal(r.payload.data.verdict.state, "running", "and the card is told why");
});

test("a screen we could not read is a 503, not a guess", async () => {
  const h = harness({ refreshOk: false });
  const r = await h.call("/api/mobile/v1/lanes/:lane/key", { lane: "repo" }, { key: "enter" });
  assert.equal(r.code, 503);
  assert.equal(h.execs.length, 0);
});

test("an unknown lane never reaches the cluster", async () => {
  const h = harness({ verdictsByCall: [waiting("y")] });
  const r = await h.call("/api/mobile/v1/lanes/:lane/key", { lane: "evil" }, { key: "y" });
  assert.equal(r.code, 404);
  assert.equal(h.sweeps(), 0, "not even a sweep");
  assert.equal(h.execs.length, 0);
});

test("isolate checks the destination before typing the cd", async () => {
  const h = harness({ verdictsByCall: [{ state: "idle", approveKey: null, atShell: true }] });
  const r = await h.call("/api/mobile/v1/lanes/:lane/isolate", { lane: "codex-1" }, {});
  assert.equal(r.code, 200);
  assert.equal(h.execs.length, 2, "first the test -d, then the send-keys");
  assert.match(h.execs[0].at(-1), /test -d \/workspace\/\.wt\/codex-1/);
  assert.match(h.execs[1].at(-1), /send-keys -t codex-1 "cd \/workspace\/\.wt\/codex-1" Enter$/);
  assert.equal(r.payload.data.movedTo, "/workspace/.wt/codex-1");
});

// ─── APROVAR A LANE EXATA: o card que o protocolo tipou também tem que ser respondível ────
//
// ACHADO 4 (2026-08-09): `fuseFleet` zera o `approveKey` da lane do loomd — certo, não há tecla.
// Só que `send-keys` era o único caminho que o cockpit tinha, então a ÚNICA lane cujo pedido de
// aprovação é tipado era a única que o operador não conseguia aprovar pelo app.

const loomdCard = (over = {}) => ({
  sid: "loom-1", state: "waiting", confidence: "exact", truthSource: "loomd",
  loomdKind: "awaiting_approval", detail: "",
  pendingApproval: { id: "call_42", method: "execCommandApproval" },
  approveKey: null, observedAt: 1000, ...over,
});
const loomdUp = (lost = []) => ({ mode: "observed", truthMode: "observed", lost, error: null });

test("a decisão pura: lane do loomd só aprova com pendência TIPADA e com a fonte no ar", () => {
  const truth = loomdUp();
  assert.equal(decideLoomdApprove({ lane: "loom-1", allow: true, card: loomdCard(), truth }).ok, true);

  // Trabalhando, sem pendência: não há o que responder.
  const semPendencia = decideLoomdApprove({
    lane: "loom-1", allow: true, card: loomdCard({ state: "running", pendingApproval: null }), truth,
  });
  assert.equal(semPendencia.status, 409);
  assert.match(semPendencia.error, /running/);
  assert.match(semPendencia.error, /nada para responder/);

  // A fonte caiu: a recusa tem que ser explícita, porque 200 aqui seria afirmar uma entrega que
  // ninguém fez — indistinguível de sucesso na tela.
  const caiu = decideLoomdApprove({
    lane: "loom-1", allow: true, card: null,
    truth: { mode: "down", lost: ["loom-1"], error: "loomd não respondeu em 127.0.0.1:4400 dentro do pod" },
  });
  assert.equal(caiu.status, 503);
  assert.match(caiu.error, /down/);
  assert.match(caiu.error, /127\.0\.0\.1:4400/, "o motivo do loomd tem que viajar junto");
  assert.match(caiu.error, /não vou dizer que aprovei/);

  assert.equal(decideLoomdApprove({ lane: "loom-9", allow: true, card: null, truth }).status, 404);
});


test("a lane do loomd é aprovada por RPC no mesmo exec da leitura — nenhum send-keys", async () => {
  const h = harness({ loomdLanes: { "loom-1": loomdCard() }, loomdTruth: loomdUp() });
  const r = await h.call("/api/mobile/v1/lanes/:lane/approve", { lane: "loom-1" }, {});
  assert.equal(r.code, 200, JSON.stringify(r.payload));
  assert.equal(r.payload.data.via, "loomd");
  assert.deepEqual(r.payload.data.pending, { id: "call_42", method: "execCommandApproval" });
  assert.equal(h.execs.length, 1);
  const body = String(h.execs[0].at(-1));
  assert.match(body, /curl .*-X POST/);
  assert.match(body, /http:\/\/127\.0\.0\.1:4400\/v2\/lanes\/loom-1\/approve/);
  assert.match(body, /-d '\{"allow":true\}'/);
  assert.doesNotMatch(body, /send-keys/, "a lane do loomd não tem pane onde apertar tecla");
  // O pod alvo é o do workspace, pelo exec já autenticado — a porta 4400 continua sem exposição.
  assert.deepEqual(h.execs[0].slice(0, 8),
    ["-n", "beagle", "exec", "-i", "sounio-workspace-control-0", "-c", "workspace-ssh", "--"]);
});

test("allow:false vira negação RPC, com corpo literal", async () => {
  const h = harness({ loomdLanes: { "loom-1": loomdCard() }, loomdTruth: loomdUp() });
  const r = await h.call("/api/mobile/v1/lanes/:lane/approve", { lane: "loom-1" }, { allow: false });
  assert.equal(r.code, 200);
  assert.equal(r.payload.data.allow, false);
  assert.match(String(h.execs[0].at(-1)), /-d '\{"allow":false\}'/);
});

test("loomd fora do ar NÃO vira 'aprovei' — e não chega a executar nada", async () => {
  const h = harness({
    loomdLanes: {},
    loomdTruth: { mode: "down", truthMode: "unknown", lost: ["loom-1"], error: "loomd não respondeu em 127.0.0.1:4400 dentro do pod" },
  });
  const r = await h.call("/api/mobile/v1/lanes/:lane/approve", { lane: "loom-1" }, {});
  assert.equal(r.code, 503, JSON.stringify(r.payload));
  assert.equal(r.payload.ok, false);
  assert.match(r.payload.error, /down/);
  assert.equal(h.execs.length, 0, "nenhum exec numa recusa — o invariante de sempre");
  // E a queda continua tendo NOME no frame, não vira card ausente em silêncio.
  assert.deepEqual(r.payload.data.truth.lost, ["loom-1"]);
});

test("lane do loomd sem pendência não executa nada", async () => {
  const h = harness({
    loomdLanes: { "loom-1": loomdCard({ state: "running", loomdKind: "tool_call", pendingApproval: null }) },
    loomdTruth: loomdUp(),
  });
  const r = await h.call("/api/mobile/v1/lanes/:lane/approve", { lane: "loom-1" }, {});
  assert.equal(r.code, 409, JSON.stringify(r.payload));
  assert.match(r.payload.error, /nada para responder/);
  assert.equal(h.execs.length, 0, "nenhum curl numa recusa");
});

test("o motivo do loomd chega inteiro ao operador (409 dele = 409 nosso)", async () => {
  const h = harness({
    loomdLanes: { "loom-1": loomdCard() }, loomdTruth: loomdUp(),
    loomdReply: { httpCode: 409, body: '{"ok":false,"error":"a lane loom-1 não está esperando aprovação"}' },
  });
  const r = await h.call("/api/mobile/v1/lanes/:lane/approve", { lane: "loom-1" }, {});
  assert.equal(r.code, 409);
  assert.match(r.payload.error, /não está esperando aprovação/);
  assert.match(r.payload.error, /o loomd recusou/);
});

test("curl sem código HTTP é 502 — corpo bonito não é entrega", async () => {
  // O caso que o `-w` existe para pegar: sem o marcador não houve resposta HTTP nenhuma (loomd
  // morto, timeout, exec quebrado). Tratar isso como 200 seria o falso-positivo clássico.
  const h = harness({
    loomdLanes: { "loom-1": loomdCard() }, loomdTruth: loomdUp(),
    loomdReply: { httpCode: null, body: "curl: (7) Failed to connect to 127.0.0.1 port 4400", stderr: "curl: (7)" },
  });
  const r = await h.call("/api/mobile/v1/lanes/:lane/approve", { lane: "loom-1" }, {});
  assert.equal(r.code, 502, JSON.stringify(r.payload));
  assert.match(r.payload.error, /não consegui falar com o loomd/);
});

test("nome hostil de lane não chega nem à varredura", async () => {
  const h = harness({ loomdLanes: { "loom-1": loomdCard() }, loomdTruth: loomdUp() });
  for (const lane of ["loom-1; curl http://evil/", "$(id)", "../../etc/passwd", "loom-2", ""]) {
    const r = await h.call("/api/mobile/v1/lanes/:lane/approve", { lane }, {});
    assert.equal(r.code, 404, `deveria recusar ${JSON.stringify(lane)}`);
  }
  assert.equal(h.sweeps(), 0, "nem uma varredura para um nome fora das duas listas");
  assert.equal(h.execs.length, 0);
});

test("mesmo se o loomd DECLARAR um nome hostil, o argv não é montado", async () => {
  // Segunda tranca: o nome das lanes do loomd vem de LOOMD_CODEX_LANES dentro do pod, não daqui.
  // O allowlist observado deixaria passar; o charset não.
  const hostil = "loom-1;rm -rf /";
  const h = harness({
    loomdLanes: { [hostil]: loomdCard({ sid: hostil }) },
    loomdTruth: loomdUp(),
  });
  const r = await h.call("/api/mobile/v1/lanes/:lane/approve", { lane: hostil }, {});
  assert.equal(r.code, 400, JSON.stringify(r.payload));
  assert.match(r.payload.error, /allowlist/);
  assert.equal(h.execs.length, 0, "nada com metacaractere de shell pode virar exec");
});

test("/approve numa lane de TELA recusa e aponta para /key — o servidor não escolhe tecla destrutiva", async () => {
  // Achado adversarial: o ramo de tela deixava o SERVIDOR escolher a tecla por regex. Medido com
  // o classificador real, uma tela `Bash(rm -rf …) / Do you want to proceed? / ❯ 1. Yes` devolve
  // `approveKey:"enter"` — o DEFAULT quando não casa `(y/n)`. Um pedido sem tecla nomeada
  // confirmaria um comando destrutivo escolhido por heurística.
  const h = harness({ verdictsByCall: [waiting("enter")] });
  const r = await h.call("/api/mobile/v1/lanes/:lane/approve", { lane: "codex-2" }, { allow: true });
  assert.equal(r.code, 409);
  assert.match(r.payload.error, /\/key/, "a recusa tem que dizer por onde aprovar");
  assert.equal(h.execs.length, 0, "e NADA é enviado à lane");
});


test("/key numa lane do loomd recusa com MOTIVO e aponta o caminho certo", async () => {
  const h = harness({ loomdLanes: { "loom-1": loomdCard() }, loomdTruth: loomdUp() });
  const r = await h.call("/api/mobile/v1/lanes/:lane/key", { lane: "loom-1" }, { key: "y" });
  assert.equal(r.code, 409);
  assert.match(r.payload.error, /servida pelo loomd/);
  assert.match(r.payload.error, /lanes\/loom-1\/approve/, "a recusa tem que dizer para onde ir");
  assert.equal(h.sweeps(), 0);
  assert.equal(h.execs.length, 0);
});
