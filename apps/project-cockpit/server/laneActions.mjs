// laneActions.mjs — the Frota stops being a panel and becomes a control surface.
//
// THE BOUNDARY, and the whole security argument for this file:
//
//   one touch = ONE named key from a closed set  ·  arbitrary text = you must be at the terminal
//
// A named key is not a command: `y` here is the same `y` he would press. Anything a lane needs
// TYPED (a real answer to a real question) still goes through the terminal on /ws/loom, where he
// can see what he is answering.
//
// And the refusal lives HERE, not in the client. `laneState.mjs` already computes `approveKey`
// (`"y"` / `"enter"` / `null`); until now that was decoration — no endpoint acted on it, and no
// endpoint enforced it. A client bug, or a second client, must not be able to press Enter at a
// question that needs a sentence.
//
// Every decision is taken against a screen read LESS THAN A SECOND OLD: each action forces a
// fresh sweep first. Deciding from a 12s-old verdict would mean approving whatever happens to be
// on screen now, which is not what he saw when he pressed the button.
import { execFile } from "node:child_process";
import {
  WORKSPACE_LANES, LANE_KEYS, LANE_WT_ROOT,
  laneSendKeyArgv, laneIsolateArgv, laneWorktreeCheckArgv,
  loomdApproveArgv, loomdPromptArgv, loomdTramaArgv, loomdTurnArgv, parseLoomdHttp, loomdErrorOf,
} from "./platform-bridge.mjs";

/// States in which typing a `cd` at the lane is sound at all. Necessary, NOT sufficient: see the
/// shell check in `decideIsolate`. Moving a lane also restarts the agent there and loses its
/// context, so it is never automatic.
const ISOLATABLE = new Set(["idle", "exited"]);

/// Pure decision: may this key be delivered to this lane, given the freshest verdict we have?
/// Returns { ok: true } or { status, error } — a REASON, always, because a button that refuses
/// without saying why is worse than no button.
export function decideKey({ lane, key, verdict }) {
  if (!WORKSPACE_LANES.includes(lane)) return { status: 404, error: `lane desconhecida: ${lane}` };
  if (!Object.prototype.hasOwnProperty.call(LANE_KEYS, key)) {
    return { status: 400, error: `tecla não permitida: ${key} (só ${Object.keys(LANE_KEYS).join(", ")})` };
  }
  if (!verdict) return { status: 409, error: "lane nunca observada — não sei o que está na tela dela" };

  // Escape is the interrupt the CLIs themselves advertise ("esc to interrupt"), so it is the one
  // key that also makes sense on a lane that is working. It never confirms anything.
  if (key === "esc") {
    if (verdict.state === "waiting" || verdict.state === "running") return { ok: true };
    return { status: 409, error: `nada para interromper: a lane está ${verdict.state}` };
  }

  if (verdict.state !== "waiting") {
    return { status: 409, error: `a lane está ${verdict.state}, não esperando por você` };
  }
  if (!verdict.approveKey) {
    return { status: 409, error: "essa lane pede uma resposta digitada, não uma tecla — abra o terminal" };
  }
  if (key !== verdict.approveKey) {
    return { status: 409, error: `essa lane espera "${verdict.approveKey}", não "${key}"` };
  }
  return { ok: true };
}

// ─── APROVAR: um gesto, dois transportes ─────────────────────────────────────────────────
//
// ACHADO (2026-08-09): a única lane cujo pedido de aprovação é TIPADO era a única que o operador
// não conseguia aprovar. `fuseFleet` zera o `approveKey` da lane servida pelo loomd — e está
// certo, não há tecla: o loomd aprova por RPC. Mas o cockpit só sabia `tmux send-keys`, e
// `decideKey` recusa explicitamente quem não tem `approveKey`. O card exato ficava decorativo.
//
// A rota nova é IRMÃ de `/key`, não uma substituição, e a separação é semântica:
//
//   POST …/key      → "entregue ESTA tecla a esta lane". O pedido nomeia a tecla; só faz sentido
//                     onde existe um pane. Continua sendo a única porta do `esc` (interromper).
//   POST …/approve  → "responda ao pedido que a lane está fazendo". O pedido NÃO nomeia
//                     mecanismo; quem escolhe é o servidor, a partir de quem serve a lane.
//
// Por que não sobrecarregar `/key` com uma tecla fantasma: para a lane do loomd não existe tecla
// nenhuma para nomear, e inventar uma (`y` que na verdade vira RPC) faria o cliente afirmar um
// mecanismo que não é o que acontece — o mesmo tipo de mentira que o rótulo `exact` existe para
// impedir. O card já traz o sinal tipado para desenhar o botão: `pendingApproval`, não `approveKey`.
//
// E o transporte é decidido no SERVIDOR, pelo último estado observado. Se o cliente decidisse,
// ele decidiria com o card que tem na mão — que envelhece exatamente quando o loomd cai.

// `decideScreenApprove` foi REMOVIDA junto com o ramo de tela desta rota. Ela existia para o
// servidor escolher a tecla sozinho a partir do veredito de regex — e é isso que a verificação
// adversarial derrubou. Aprovar lane de tela continua em `/key`, onde o cliente NOMEIA a tecla.
/// Aprovação na lane servida pelo LOOMD. Puro.
///
/// 🚨 O allowlist NÃO é `WORKSPACE_LANES` — as lanes do loomd não estão lá (a de laboratório se
/// chama `loom-1`). Ele é o conjunto que o loomd DECLAROU na última leitura, e é por isso que
/// `card` chega aqui já resolvido pelo chamador: nenhum nome vindo do request escolhe o caminho.
///
/// E `mode !== "observed"` é 503, não "aprovei": se o loomd não respondeu nesta varredura, não
/// existe pendência medida para responder. Deixar passar produziria um 200 para uma aprovação
/// que ninguém entregou — indistinguível de sucesso na tela do operador.
export function decideLoomdApprove({ lane, allow, card, truth }) {
  const mode = truth?.mode || "unknown";
  if (mode !== "observed") {
    return {
      status: 503,
      error: `o loomd não respondeu nesta leitura (${mode}): ${truth?.error || "sem motivo declarado"} — não vou dizer que aprovei`,
    };
  }
  if (!card) return { status: 404, error: `lane desconhecida: ${lane}` };
  if (!card.pendingApproval) {
    return { status: 409, error: `a lane está ${card.state} e não tem pedido de aprovação pendente — nada para responder` };
  }
  return { ok: true, pending: card.pendingApproval, allow: allow !== false };
}

/// Decisão pura do PROMPT de texto livre.
///
/// Diferente de `/key`, aqui não há tecla nem estado que autorize ou proíba: mandar um pedido a um
/// agente é sempre legítimo, inclusive enquanto ele trabalha (o Codex enfileira). O que a decisão
/// guarda é outra coisa:
///   1. a lane precisa ser **do loomd** — numa lane de tela o texto viraria digitação cega num pty;
///   2. a leitura precisa estar `observed` — mandar prompt para uma fonte caída daria 202 sem
///      ninguém do outro lado, que é a mentira que este arquivo inteiro existe para não contar;
///   3. o texto precisa ter conteúdo, e teto — sem teto, um paste acidental de 10 MB vira corpo
///      de requisição dentro de um `kubectl exec`.
export const PROMPT_MAX = 32_000;

export function decidePrompt({ lane, text, card, truth }) {
  const mode = truth?.mode || "unknown";
  if (mode !== "observed") {
    return {
      status: 503,
      error: `o loomd não respondeu nesta leitura (${mode}): ${truth?.error || "sem motivo declarado"} — não vou fingir que entreguei seu pedido`,
    };
  }
  if (!card) {
    return {
      status: 409,
      error: `a lane ${lane} não é servida pelo loomd — texto livre nela seria digitação cega num terminal; abra o Terminal`,
    };
  }
  const t = String(text ?? "");
  if (!t.trim()) return { status: 400, error: "prompt vazio" };
  if (t.length > PROMPT_MAX) {
    return { status: 413, error: `prompt de ${t.length} caracteres passa do teto de ${PROMPT_MAX}` };
  }
  return { ok: true, text: t };
}

/// Pure decision for moving a lane into its own worktree.
export function decideIsolate({ lane, verdict, worktreeExists }) {
  if (!WORKSPACE_LANES.includes(lane)) return { status: 404, error: `lane desconhecida: ${lane}` };
  if (!verdict) return { status: 409, error: "lane nunca observada — não sei se ela está em repouso" };
  if (!ISOLATABLE.has(verdict.state)) {
    return { status: 409, error: `a lane está ${verdict.state}; mover reinicia o agente e perde o contexto dele` };
  }
  // CAUGHT BEFORE THE FIRST REAL MOVE (2026-08-09): "idle" covers a lane sitting at its AGENT's
  // input box as well as one at a shell. A shell runs `cd /workspace/.wt/<lane>`; an agent CLI
  // would receive that same text as a REQUEST and go do something with it. Isolation types a
  // command, so it may only aim at a shell — the agent has to be closed first.
  if (!verdict.atShell) {
    return {
      status: 409,
      error: "a lane está no prompt do agente, não num shell — feche o agente antes (o `cd` viraria um pedido a ele)",
    };
  }
  if (worktreeExists === false) {
    return { status: 409, error: `worktree ausente: ${LANE_WT_ROOT}/${lane} — rode sounio-lane-worktrees --apply antes` };
  }
  return { ok: true };
}

/// Igual a `run`, mas escrevendo no STDIN do processo. É o que mantém o texto do operador FORA
/// do argv: `kubectl exec -i` repassa este stdin ao `curl --data-binary @-` do outro lado.
const runWithInput = (bin, argv, exec, input) => new Promise((resolve) => {
  const child = exec(bin, argv, { timeout: 20000, maxBuffer: 1024 * 1024 }, (err, stdout, stderr) => {
    resolve({ err, stdout: String(stdout || ""), stderr: String(stderr || "") });
  });
  // `execFile` devolve o ChildProcess; um duplo (fake) de teste pode não devolver — e aí a
  // ausência de stdin é silenciosa, então checar aqui é o que impede um teste verde de mentir.
  if (!child?.stdin) return resolve({ err: new Error("sem stdin no processo — não dá para enviar o corpo"), stdout: "", stderr: "" });
  child.stdin.on("error", () => {});
  child.stdin.end(input);
});

const run = (bin, argv, exec) => new Promise((resolve) => {
  exec(bin, argv, { timeout: 15000, maxBuffer: 1024 * 1024 }, (err, stdout, stderr) => {
    resolve({ err, stdout: String(stdout || ""), stderr: String(stderr || "") });
  });
});

export function registerLaneActionRoutes(app, {
  poller, kubectl, ns, execFn = execFile,
} = {}) {
  // Read the screen NOW, so the decision is about what is there, not what was there 12s ago.
  // A sweep we could not complete is a 503: refusing is honest, guessing is not.
  async function freshVerdict(lane, res) {
    const ok = await poller.refreshNow();
    if (!ok) {
      res.status(503).json({ ok: false, error: `não consegui ler a tela das lanes agora: ${poller.lastError || "sweep falhou"}` });
      return null;
    }
    return poller.get(lane) || { state: "unknown", approveKey: null };
  }

  /// A lane é do loomd? A resposta é o ÚLTIMO ESTADO OBSERVADO, nunca o request. `lost` entra
  /// junto de propósito: uma lane que o loomd servia e parou de servir continua sendo dele — o
  /// caminho certo para ela é a recusa do loomd (503 com motivo), não cair para `send-keys` num
  /// pane que não existe.
  const servedByLoomd = (lane) =>
    Boolean(poller.loomd(lane)) || (poller.loomdTruth().lost || []).includes(lane);

  app.post("/api/mobile/v1/lanes/:lane/key", async (req, res) => {
    const lane = String(req.params.lane || "");
    const key = String((req.body || {}).key || "");
    // Antes do 404 genérico: a lane do loomd não é desconhecida, ela é de outro transporte, e
    // dizer "desconhecida" mandaria o operador procurar um erro que não existe.
    if (!WORKSPACE_LANES.includes(lane) && servedByLoomd(lane)) {
      return res.status(409).json({
        ok: false,
        error: `a lane ${lane} é servida pelo loomd e não tem tecla — aprove em POST /api/mobile/v1/lanes/${lane}/approve`,
      });
    }
    if (!WORKSPACE_LANES.includes(lane)) return res.status(404).json({ ok: false, error: `lane desconhecida: ${lane}` });

    const verdict = await freshVerdict(lane, res);
    if (!verdict) return;
    const verdictBefore = { state: verdict.state, detail: verdict.detail || "", approveKey: verdict.approveKey || null };

    const d = decideKey({ lane, key, verdict });
    if (!d.ok) return res.status(d.status).json({ ok: false, error: d.error, data: { verdict: verdictBefore } });

    const argv = laneSendKeyArgv(ns, lane, key);
    if (!argv) return res.status(400).json({ ok: false, error: "ação recusada pelo allowlist" });
    const { err, stderr } = await run(kubectl, argv, execFn);
    if (err) return res.status(502).json({ ok: false, error: `send-keys falhou: ${stderr || err.message}` });

    // Sweep again so the card he is looking at catches up in a beat, not in 12s.
    await poller.refreshNow();
    const after = poller.get(lane);
    res.json({
      ok: true,
      data: {
        lane, key,
        verdictBefore,
        state: after?.state || null, detail: after?.detail || "", observedAt: after?.observedAt || null,
      },
    });
  });

  app.post("/api/mobile/v1/lanes/:lane/approve", async (req, res) => {
    const lane = String(req.params.lane || "");
    const allow = (req.body || {}).allow !== false;

    // Porteiro barato ANTES de qualquer exec: um nome que não pertence a nenhuma das duas fontes
    // não dispara nem uma varredura. O card que ele tocou veio de uma varredura, então toda lane
    // legítima já está numa das duas listas.
    if (!WORKSPACE_LANES.includes(lane) && !servedByLoomd(lane)) {
      return res.status(404).json({ ok: false, error: `lane desconhecida: ${lane}` });
    }

    // Mesma disciplina de `/key`: decide-se sobre uma leitura de menos de um segundo. O sweep é o
    // MESMO para as duas fontes (o bloco @@LOOMD: pega carona nele), então uma chamada atualiza
    // a tela e o loomd de uma vez.
    const verdict = await freshVerdict(lane, res);
    if (!verdict) return;

    if (servedByLoomd(lane)) {
      const truth = poller.loomdTruth();
      const card = poller.loomd(lane);
      const d = decideLoomdApprove({ lane, allow, card, truth });
      if (!d.ok) return res.status(d.status).json({ ok: false, error: d.error, data: { truth } });

      const argv = loomdApproveArgv(ns, lane, d.allow);
      if (!argv) return res.status(400).json({ ok: false, error: "ação recusada pelo allowlist" });
      const { err, stdout, stderr } = await run(kubectl, argv, execFn);
      const http = parseLoomdHttp(stdout);
      // Sem código HTTP não houve resposta: exec falhou, curl não conectou ou estourou o teto.
      // Isto é o oposto de sucesso e não pode virar 200.
      if (http.code === null) {
        return res.status(502).json({
          ok: false,
          error: `não consegui falar com o loomd dentro do pod: ${stderr || err?.message || "resposta sem código HTTP"}`,
        });
      }
      if (http.code !== 200) {
        // O motivo do loomd é melhor que o nosso: ele sabe se a lane não é supervisionada (404)
        // ou se a pendência já foi respondida por outro caminho (409).
        const reason = loomdErrorOf(http.body) || `HTTP ${http.code}`;
        const status = http.code === 404 ? 404 : (http.code === 409 ? 409 : 502);
        return res.status(status).json({ ok: false, error: `o loomd recusou: ${reason}`, data: { httpCode: http.code } });
      }

      await poller.refreshNow();
      const after = poller.loomd(lane);
      return res.json({
        ok: true,
        data: {
          lane, allow: d.allow, via: "loomd", pending: d.pending,
          state: after?.state || null, detail: after?.detail || "", observedAt: after?.observedAt || null,
        },
      });
    }

    // 🚨 Lane de TELA: esta rota NÃO aprova. Removido depois da verificação adversarial.
    //
    // O ramo anterior deixava o SERVIDOR escolher sozinho, por regex, a tecla a injetar numa das
    // 11 lanes vivas. Medido com o classificador real: uma tela
    //   `Bash(rm -rf /workspace/x) / Do you want to proceed? / ❯ 1. Yes / 2. No`
    // devolve `approveKey: "enter"` — que é o DEFAULT do regex quando não casa `(y/n)`. Ou seja,
    // um pedido sem tecla nomeada faria o cockpit confirmar um comando destrutivo escolhido por
    // heurística. Isso é exatamente a fronteira que `/key` existe para manter: o cliente NOMEIA
    // a tecla, e o servidor só verifica se ela é a certa para o que está na tela.
    //
    // Escopo desta rota é a lane servida pelo loomd, onde a aprovação é RPC tipada e não há
    // tecla nenhuma para adivinhar.
    return res.status(409).json({
      ok: false,
      error: `a lane ${lane} é servida por tela, não pelo loomd — aprove por /key nomeando a tecla que o card mostra`,
    });
  });

  /// TEXTO LIVRE para uma lane de protocolo. É a maior superfície de escrita deste servidor, e a
  /// forma dela é o que a torna segura: o texto vai pelo STDIN, nunca pelo argv.
  app.post("/api/mobile/v1/lanes/:lane/prompt", async (req, res) => {
    const lane = String(req.params.lane || "");
    const text = String((req.body || {}).text ?? "");

    if (!WORKSPACE_LANES.includes(lane) && !servedByLoomd(lane)) {
      return res.status(404).json({ ok: false, error: `lane desconhecida: ${lane}` });
    }
    const verdict = await freshVerdict(lane, res);
    if (!verdict) return;

    const truth = poller.loomdTruth();
    const d = decidePrompt({ lane, text, card: poller.loomd(lane), truth });
    if (!d.ok) return res.status(d.status).json({ ok: false, error: d.error, data: { truth } });

    const argv = loomdPromptArgv(ns, lane);
    if (!argv) return res.status(400).json({ ok: false, error: "ação recusada pelo allowlist" });
    // JSON montado pelo SERIALIZADOR, não por concatenação — e entregue pelo stdin.
    const { err, stdout, stderr } = await runWithInput(
      kubectl, argv, execFn, JSON.stringify({ text: d.text }));
    const http = parseLoomdHttp(stdout);
    if (http.code === null) {
      return res.status(502).json({
        ok: false,
        error: `sem resposta do loomd ao enviar o prompt: ${loomdErrorOf(http.body) || stderr || err?.message || "motivo desconhecido"}`,
      });
    }
    if (http.code < 200 || http.code >= 300) {
      return res.status(http.code === 404 ? 404 : 502).json({
        ok: false,
        error: loomdErrorOf(http.body) || `o loomd recusou o prompt (HTTP ${http.code})`,
      });
    }
    // 202 do loomd: o turno foi ACEITO, não concluído. Dizer "pronto" aqui seria prometer o que
    // ainda não aconteceu — quem conta o resto é a trama.
    await poller.refreshNow();
    res.status(202).json({ ok: true, data: { lane, accepted: true, chars: d.text.length } });
  });

  /// Parar o turno, ou GUIÁ-LO. Duas ações no mesmo lugar porque a decisão é a mesma — "este
  /// turno está indo para o lugar errado" — e o que muda é quanto se joga fora.
  for (const acao of ["interrupt", "steer"]) {
    app.post(`/api/mobile/v1/lanes/:lane/${acao}`, async (req, res) => {
      const lane = String(req.params.lane || "");
      const text = String((req.body || {}).text ?? "");

      if (!servedByLoomd(lane)) {
        // Numa lane de tela quem interrompe é a tecla `esc`, que a rota `/key` já entrega.
        return res.status(409).json({
          ok: false,
          error: `a lane ${lane} é servida por tela — interrompa com POST /api/mobile/v1/lanes/${lane}/key {"key":"esc"}`,
        });
      }
      if (acao === "steer" && !text.trim()) {
        return res.status(400).json({ ok: false, error: "guiar exige texto" });
      }
      const verdict = await freshVerdict(lane, res);
      if (!verdict) return;
      const truth = poller.loomdTruth();
      if (truth.mode !== "observed") {
        return res.status(503).json({
          ok: false,
          error: `o loomd não respondeu nesta leitura (${truth.mode}) — não vou dizer que parei o turno`,
          data: { truth },
        });
      }

      const argv = loomdTurnArgv(ns, lane, acao);
      if (!argv) return res.status(400).json({ ok: false, error: "ação recusada pelo allowlist" });
      const r = acao === "steer"
        ? await runWithInput(kubectl, argv, execFn, JSON.stringify({ text }))
        : await run(kubectl, argv, execFn);
      const http = parseLoomdHttp(r.stdout);
      if (http.code === null) {
        return res.status(502).json({
          ok: false,
          error: `sem resposta do loomd: ${r.stderr || r.err?.message || "motivo desconhecido"}`,
        });
      }
      if (http.code < 200 || http.code >= 300) {
        // 409 do loomd = "nenhum turno em curso". É recusa do CHAMADOR, e o status precisa
        // atravessar: transformá-la em 502 mandaria o operador caçar falha de transporte.
        return res.status(http.code === 409 || http.code === 404 ? http.code : 502).json({
          ok: false,
          error: loomdErrorOf(http.body) || `o loomd recusou (HTTP ${http.code})`,
        });
      }
      await poller.refreshNow();
      res.status(202).json({ ok: true, data: { lane, acao } });
    });
  }

  /// A CONVERSA, a partir de um cursor. `seq` é monotônico e atravessa reinício do loomd, então o
  /// cliente pede só o que ainda não viu — e não precisa de socket para acompanhar um turno.
  app.get("/api/mobile/v1/lanes/:lane/turns", async (req, res) => {
    const lane = String(req.params.lane || "");
    const since = Number(req.query.since ?? 0);

    if (!servedByLoomd(lane)) {
      return res.status(409).json({
        ok: false,
        error: `a lane ${lane} é servida por tela, não pelo loomd — ela não tem turnos, tem scrollback`,
      });
    }
    const argv = loomdTramaArgv(ns, lane, since);
    if (!argv) return res.status(400).json({ ok: false, error: "cursor ou lane inválidos" });

    const { err, stdout, stderr } = await run(kubectl, argv, execFn);
    const http = parseLoomdHttp(stdout);
    if (http.code === null) {
      return res.status(502).json({
        ok: false,
        error: `sem resposta do loomd ao ler a trama: ${stderr || err?.message || "motivo desconhecido"}`,
      });
    }
    if (http.code < 200 || http.code >= 300) {
      return res.status(502).json({ ok: false, error: loomdErrorOf(http.body) || `o loomd recusou a leitura (HTTP ${http.code})` });
    }
    let payload;
    try {
      payload = JSON.parse(http.body);
    } catch {
      return res.status(502).json({ ok: false, error: "a trama voltou ilegível" });
    }
    const events = Array.isArray(payload?.events) ? payload.events : [];
    // O cursor volta com a resposta para o cliente não ter que derivá-lo — derivar do último
    // elemento quebra em lista vazia, que é o caso comum de um poll sem novidade.
    const cursor = events.reduce((m, e) => Math.max(m, Number(e?.seq) || 0), Number(since) || 0);
    const card = poller.loomd(lane);
    res.json({ ok: true, data: {
      lane, since: Number(since) || 0, cursor, events,
      streaming: card?.streamingText || null,
      // Explícito, e não derivado do parcial: um turno que ainda não emitiu texto também é um
      // turno, e a tela precisa oferecer "parar" nele — que é justamente quando mais se quer.
      turnRunning: Boolean(card?.currentTurn),
    } });
  });

  app.post("/api/mobile/v1/lanes/:lane/isolate", async (req, res) => {
    const lane = String(req.params.lane || "");
    if (!WORKSPACE_LANES.includes(lane)) return res.status(404).json({ ok: false, error: `lane desconhecida: ${lane}` });

    const verdict = await freshVerdict(lane, res);
    if (!verdict) return;

    // Check the destination BEFORE typing: a `cd` into a directory that is not there leaves the
    // lane exactly where it was, and the UI would report a move that never happened.
    const checkArgv = laneWorktreeCheckArgv(ns, lane);
    const check = await run(kubectl, checkArgv, execFn);
    const worktreeExists = /(^|\n)\s*yes\s*(\n|$)/.test(check.stdout);

    const d = decideIsolate({ lane, verdict, worktreeExists });
    if (!d.ok) return res.status(d.status).json({ ok: false, error: d.error, data: { verdict: { state: verdict.state } } });

    const argv = laneIsolateArgv(ns, lane);
    if (!argv) return res.status(400).json({ ok: false, error: "ação recusada pelo allowlist" });
    const { err, stderr } = await run(kubectl, argv, execFn);
    if (err) return res.status(502).json({ ok: false, error: `mover falhou: ${stderr || err.message}` });

    await poller.refreshNow();
    res.json({ ok: true, data: { lane, movedTo: `${LANE_WT_ROOT}/${lane}`, state: poller.get(lane)?.state || null } });
  });
}
