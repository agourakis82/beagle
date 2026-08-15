import { test } from "node:test";
import assert from "node:assert/strict";
import {
  decidePrompt, PROMPT_MAX,
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
  // O duplo aceita GET também desde que a Sessão passou a LER a trama por HTTP. Um duplo que
  // não conhece o verbo faria a rota nova sumir da suíte em silêncio.
  const stdinWrites = [];
  const app = {
    post: (path, h) => { routes[`POST ${path}`] = h; },
    get: (path, h) => { routes[`GET ${path}`] = h; },
  };
  registerLaneActionRoutes(app, {
    poller, kubectl: "kubectl", ns: "beagle",
    execFn: (bin, argv, opts, cb) => {
      execs.push(argv);
      let done;
      if (String(argv.at(-1)).includes("curl")) {
        const out = loomdReply.httpCode === null
          ? loomdReply.body
          : `${loomdReply.body}\n${LOOMD_HTTP_DELIM}${loomdReply.httpCode}`;
        done = () => cb(loomdReply.err || null, out, loomdReply.stderr || "");
      } else {
        done = () => cb(null, "yes\n", "");
      }
      // O prompt entrega o corpo pelo STDIN, então o duplo precisa de um stdin de verdade — e
      // registrar o que foi escrito é o único jeito de provar que o texto saiu por aqui e não
      // pelo argv. Sem isto, um teste passaria com o servidor mandando corpo nenhum.
      const stdin = {
        on() {},
        end(data) { stdinWrites.push(String(data ?? "")); done(); },
      };
      // O caminho que não usa stdin chama o callback na hora, como o execFile faz.
      queueMicrotask(() => { if (!stdinWrites.length || !String(argv.at(-1)).includes("--data-binary")) done(); });
      return { stdin };
    },
  });
  const call = async (path, params, body, query) => {
    let code = 200, payload = null;
    const res = { status(c) { code = c; return this; }, json(p) { payload = p; return this; } };
    await routes[path]({ params, body, query: query || {} }, res);
    return { code, payload };
  };
  return { call, execs, stdinWrites, sweeps: () => sweeps };
}

test("the route re-reads the screen BEFORE deciding — never from a 12s-old verdict", async () => {
  const h = harness({ verdictsByCall: [waiting("y")] });
  const r = await h.call("POST /api/mobile/v1/lanes/:lane/key", { lane: "codex-2" }, { key: "y" });
  assert.equal(r.code, 200);
  assert.equal(h.sweeps() >= 2, true, "one sweep to decide, one so the card catches up");
  assert.equal(h.execs.length, 1);
  assert.match(h.execs[0].at(-1), / exec tmux send-keys -t fleet:codex-2 y$/);
  assert.equal(r.payload.data.verdictBefore.state, "waiting", "report what we acted on");
});

test("a refusal sends NOTHING to the lane", async () => {
  const h = harness({ verdictsByCall: [{ state: "running", approveKey: null }] });
  const r = await h.call("POST /api/mobile/v1/lanes/:lane/key", { lane: "claude-1" }, { key: "y" });
  assert.equal(r.code, 409);
  assert.equal(h.execs.length, 0, "no exec on a refusal — this is the invariant that matters");
  assert.equal(r.payload.data.verdict.state, "running", "and the card is told why");
});

test("a screen we could not read is a 503, not a guess", async () => {
  const h = harness({ refreshOk: false });
  const r = await h.call("POST /api/mobile/v1/lanes/:lane/key", { lane: "repo" }, { key: "enter" });
  assert.equal(r.code, 503);
  assert.equal(h.execs.length, 0);
});

test("an unknown lane never reaches the cluster", async () => {
  const h = harness({ verdictsByCall: [waiting("y")] });
  const r = await h.call("POST /api/mobile/v1/lanes/:lane/key", { lane: "evil" }, { key: "y" });
  assert.equal(r.code, 404);
  assert.equal(h.sweeps(), 0, "not even a sweep");
  assert.equal(h.execs.length, 0);
});

test("isolate checks the destination before typing the cd", async () => {
  const h = harness({ verdictsByCall: [{ state: "idle", approveKey: null, atShell: true }] });
  const r = await h.call("POST /api/mobile/v1/lanes/:lane/isolate", { lane: "codex-1" }, {});
  assert.equal(r.code, 200);
  assert.equal(h.execs.length, 2, "first the test -d, then the send-keys");
  assert.match(h.execs[0].at(-1), /test -d \/workspace\/\.wt\/codex-1/);
  assert.match(h.execs[1].at(-1), /send-keys -t fleet:codex-1 "cd \/workspace\/\.wt\/codex-1" Enter$/);
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
  const r = await h.call("POST /api/mobile/v1/lanes/:lane/approve", { lane: "loom-1" }, {});
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
  const r = await h.call("POST /api/mobile/v1/lanes/:lane/approve", { lane: "loom-1" }, { allow: false });
  assert.equal(r.code, 200);
  assert.equal(r.payload.data.allow, false);
  assert.match(String(h.execs[0].at(-1)), /-d '\{"allow":false\}'/);
});

test("loomd fora do ar NÃO vira 'aprovei' — e não chega a executar nada", async () => {
  const h = harness({
    loomdLanes: {},
    loomdTruth: { mode: "down", truthMode: "unknown", lost: ["loom-1"], error: "loomd não respondeu em 127.0.0.1:4400 dentro do pod" },
  });
  const r = await h.call("POST /api/mobile/v1/lanes/:lane/approve", { lane: "loom-1" }, {});
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
  const r = await h.call("POST /api/mobile/v1/lanes/:lane/approve", { lane: "loom-1" }, {});
  assert.equal(r.code, 409, JSON.stringify(r.payload));
  assert.match(r.payload.error, /nada para responder/);
  assert.equal(h.execs.length, 0, "nenhum curl numa recusa");
});

test("o motivo do loomd chega inteiro ao operador (409 dele = 409 nosso)", async () => {
  const h = harness({
    loomdLanes: { "loom-1": loomdCard() }, loomdTruth: loomdUp(),
    loomdReply: { httpCode: 409, body: '{"ok":false,"error":"a lane loom-1 não está esperando aprovação"}' },
  });
  const r = await h.call("POST /api/mobile/v1/lanes/:lane/approve", { lane: "loom-1" }, {});
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
  const r = await h.call("POST /api/mobile/v1/lanes/:lane/approve", { lane: "loom-1" }, {});
  assert.equal(r.code, 502, JSON.stringify(r.payload));
  assert.match(r.payload.error, /não consegui falar com o loomd/);
});

test("nome hostil de lane não chega nem à varredura", async () => {
  const h = harness({ loomdLanes: { "loom-1": loomdCard() }, loomdTruth: loomdUp() });
  for (const lane of ["loom-1; curl http://evil/", "$(id)", "../../etc/passwd", "loom-2", ""]) {
    const r = await h.call("POST /api/mobile/v1/lanes/:lane/approve", { lane }, {});
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
  const r = await h.call("POST /api/mobile/v1/lanes/:lane/approve", { lane: hostil }, {});
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
  const r = await h.call("POST /api/mobile/v1/lanes/:lane/approve", { lane: "codex-2" }, { allow: true });
  assert.equal(r.code, 409);
  assert.match(r.payload.error, /\/key/, "a recusa tem que dizer por onde aprovar");
  assert.equal(h.execs.length, 0, "e NADA é enviado à lane");
});


test("/key numa lane do loomd recusa com MOTIVO e aponta o caminho certo", async () => {
  const h = harness({ loomdLanes: { "loom-1": loomdCard() }, loomdTruth: loomdUp() });
  const r = await h.call("POST /api/mobile/v1/lanes/:lane/key", { lane: "loom-1" }, { key: "y" });
  assert.equal(r.code, 409);
  assert.match(r.payload.error, /servida pelo loomd/);
  assert.match(r.payload.error, /lanes\/loom-1\/approve/, "a recusa tem que dizer para onde ir");
  assert.equal(h.sweeps(), 0);
  assert.equal(h.execs.length, 0);
});

// ─── prompt de texto livre: a maior superfície de escrita, e a forma que a torna segura ─────

const loomdUpAqui = () => ({ mode: "observed", truthMode: "observed", lost: [], error: null });

test("decidePrompt recusa quando a fonte não foi observada — e diz que NÃO entregou", () => {
  const d = decidePrompt({
    lane: "loom-1", text: "arruma o E175", card: loomdCard(),
    truth: { mode: "down", error: "connection refused" },
  });
  assert.equal(d.status, 503);
  assert.match(d.error, /não vou fingir que entreguei/);
});

test("decidePrompt manda lane de TELA para o terminal, em vez de digitar cego", () => {
  // Texto livre num pty é digitação cega: sem eco tipado, sem confirmação, sem saber se o agente
  // estava num prompt ou num menu. A recusa nomeia a saída.
  const d = decidePrompt({ lane: "claude-1", text: "oi", card: null, truth: loomdUpAqui() });
  assert.equal(d.status, 409);
  assert.match(d.error, /digitação cega/);
  assert.match(d.error, /abra o Terminal/i);
});

test("decidePrompt exige conteúdo e impõe teto", () => {
  const truth = loomdUpAqui(), card = loomdCard();
  assert.equal(decidePrompt({ lane: "loom-1", text: "   \n ", card, truth }).status, 400);
  assert.equal(decidePrompt({ lane: "loom-1", text: "x".repeat(PROMPT_MAX + 1), card, truth }).status, 413);
  assert.equal(decidePrompt({ lane: "loom-1", text: "vai", card, truth }).ok, true);
});

test("🚨 o texto do operador NUNCA aparece no argv — ele vai pelo stdin", async () => {
  // A invariante desta rodada. Um texto com metacaractere de shell é o caso que decide: se ele
  // entrasse no `sh -c`, isto aqui seria injeção de comando com autorização do próprio operador.
  const veneno = 'oi"; rm -rf /workspace; echo "$(whoami)`id`';
  const h = harness({
    loomdLanes: { "loom-1": loomdCard() }, loomdTruth: loomdUpAqui(),
    loomdReply: { httpCode: 202, body: '{"ok":true,"lane":"loom-1"}' },
  });
  const r = await h.call("POST /api/mobile/v1/lanes/:lane/prompt", { lane: "loom-1" }, { text: veneno });

  assert.equal(r.code, 202, "202: o turno foi ACEITO, não concluído");
  const argv = h.execs.at(-1).join(" ");
  assert.ok(!argv.includes("rm -rf"), `o texto vazou para o argv: ${argv}`);
  assert.ok(!argv.includes(veneno));
  assert.ok(argv.includes("--data-binary @-"), "o corpo é lido do stdin pelo curl");
  // E foi entregue: um argv limpo com corpo nenhum seria um prompt que não chega.
  assert.deepEqual(JSON.parse(h.stdinWrites.at(-1)), { text: veneno },
    "o texto sai pelo stdin, serializado por JSON.stringify");
});

test("o prompt propaga a recusa do loomd em vez de responder 202", async () => {
  const h = harness({
    loomdLanes: { "loom-1": loomdCard() }, loomdTruth: loomdUpAqui(),
    loomdReply: { httpCode: 404, body: '{"ok":false,"error":"lane desconhecida"}' },
  });
  const r = await h.call("POST /api/mobile/v1/lanes/:lane/prompt", { lane: "loom-1" }, { text: "vai" });
  assert.equal(r.code, 404);
  assert.match(r.payload.error, /lane desconhecida/);
});

test("sem código HTTP, o prompt é 502 e diz que NINGUÉM RESPONDEU — não que recusaram", async () => {
  // Mesma família do bug que originou o `@@HTTP:`: curl sem resposta sai com 0 e corpo vazio
  // pareceria sucesso.
  //
  // 🚨 A asserção sobre a MENSAGEM é o que faz este teste valer. Testando só o status ele ficava
  // VERDE com a guarda removida — porque `null < 200` também cai no ramo do "recusou", e o
  // operador leria "o loomd recusou" para um loomd que nunca respondeu. Dois estados diferentes
  // (não respondeu · respondeu não) com o mesmo texto é como se perde uma hora no lugar errado.
  const h = harness({
    loomdLanes: { "loom-1": loomdCard() }, loomdTruth: loomdUpAqui(),
    loomdReply: { httpCode: null, body: "" },
  });
  const r = await h.call("POST /api/mobile/v1/lanes/:lane/prompt", { lane: "loom-1" }, { text: "vai" });
  assert.equal(r.code, 502);
  assert.match(r.payload.error, /sem resposta do loomd/);
  assert.doesNotMatch(r.payload.error, /recusou/);
});

// ─── a conversa: cursor que sobrevive a poll sem novidade ────────────────────────────────

test("os turnos voltam com um cursor que não quebra em lista vazia", async () => {
  const h = harness({
    loomdLanes: { "loom-1": loomdCard() }, loomdTruth: loomdUpAqui(),
    loomdReply: { httpCode: 200, body: '{"ok":true,"events":[]}' },
  });
  const r = await h.call("GET /api/mobile/v1/lanes/:lane/turns", { lane: "loom-1" }, null, { since: "42" });
  assert.equal(r.code, 200);
  assert.equal(r.payload.data.cursor, 42,
    "derivar do último elemento devolveria NaN num poll sem novidade — e o cliente voltaria ao começo");
});

test("os turnos avançam o cursor pelo MAIOR seq visto", async () => {
  const h = harness({
    loomdLanes: { "loom-1": loomdCard() }, loomdTruth: loomdUpAqui(),
    loomdReply: { httpCode: 200, body: '{"ok":true,"events":[{"seq":7},{"seq":9},{"seq":8}]}' },
  });
  const r = await h.call("GET /api/mobile/v1/lanes/:lane/turns", { lane: "loom-1" }, null, { since: "0" });
  assert.equal(r.payload.data.cursor, 9, "o maior, não o último — ordem não é garantia");
  assert.equal(r.payload.data.events.length, 3);
});

test("lane de tela não tem turnos, e a recusa explica a diferença", async () => {
  const h = harness({ verdictsByCall: [{ state: "idle" }] });
  const r = await h.call("GET /api/mobile/v1/lanes/:lane/turns", { lane: "claude-1" }, null, {});
  assert.equal(r.code, 409);
  assert.match(r.payload.error, /scrollback/);
  assert.equal(h.execs.length, 0, "e nada foi executado no cluster");
});

// ─── parar ou guiar o turno ─────────────────────────────────────────────────────────────────

test("lane de TELA é mandada para a tecla esc, não para o loomd", async () => {
  // Interromper existe nas duas categorias; o MECANISMO é que difere. Dizer "lane desconhecida"
  // aqui mandaria ele procurar um erro que não existe.
  const h = harness({ verdictsByCall: [{ state: "running" }] });
  const r = await h.call("POST /api/mobile/v1/lanes/:lane/interrupt", { lane: "claude-1" }, {});
  assert.equal(r.code, 409);
  assert.match(r.payload.error, /key.*esc/);
  assert.equal(h.execs.length, 0, "e nada foi executado no cluster");
});

test("guiar exige texto, e o texto vai pelo STDIN", async () => {
  const h = harness({
    loomdLanes: { "loom-1": loomdCard() }, loomdTruth: loomdUpAqui(),
    loomdReply: { httpCode: 202, body: '{"ok":true,"lane":"loom-1"}' },
  });
  assert.equal((await h.call("POST /api/mobile/v1/lanes/:lane/steer", { lane: "loom-1" }, { text: "  " })).code, 400);

  const veneno = 'muda o rumo"; rm -rf /workspace';
  const r = await h.call("POST /api/mobile/v1/lanes/:lane/steer", { lane: "loom-1" }, { text: veneno });
  assert.equal(r.code, 202);
  const argv = h.execs.at(-1).join(" ");
  assert.ok(!argv.includes("rm -rf"), "o texto de guiar vazou para o argv");
  assert.deepEqual(JSON.parse(h.stdinWrites.at(-1)), { text: veneno });
});

test("o 409 do loomd ATRAVESSA — 'nenhum turno em curso' não é falha de transporte", async () => {
  // Transformar a recusa do chamador em 502 mandaria o operador caçar rede quando o problema é
  // que a lane está parada.
  const h = harness({
    loomdLanes: { "loom-1": loomdCard() }, loomdTruth: loomdUpAqui(),
    loomdReply: { httpCode: 409, body: '{"ok":false,"error":"nenhum turno em curso nesta lane"}' },
  });
  const r = await h.call("POST /api/mobile/v1/lanes/:lane/interrupt", { lane: "loom-1" }, {});
  assert.equal(r.code, 409);
  assert.match(r.payload.error, /nenhum turno em curso/);
});

test("fonte não observada: não digo que parei o turno", async () => {
  const h = harness({ loomdLanes: { "loom-1": loomdCard() },
    loomdTruth: { mode: "down", truthMode: "unknown", lost: [], error: "connection refused" } });
  const r = await h.call("POST /api/mobile/v1/lanes/:lane/interrupt", { lane: "loom-1" }, {});
  assert.equal(r.code, 503);
  assert.match(r.payload.error, /não vou dizer que parei/);
  assert.equal(h.execs.length, 0);
});
