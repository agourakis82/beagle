import { test } from "node:test";
import assert from "node:assert/strict";
import { LOOMD_DELIM, ALIVE_DELIM, PEEK_DELIM } from "../platform-bridge.mjs";
import { LoomdView, fuseFleet, reduceLoomdLanes, loomdStateOf, loomdCard, EXACT, INFERRED } from "./loomd.mjs";

const bloco = (payload) => `${LOOMD_DELIM}\n${JSON.stringify(payload)}\n`;
const resto = `${ALIVE_DELIM}\nclaude-1\n${PEEK_DELIM}claude-1\n$ \n`;
const state = (lanes, ms = 1000) => bloco({ ok: true, observed_at_ms: ms, lanes }) + resto;

const lane = (over = {}) => ({
  lane: "loom-1", kind: "idle", confidence: "exact", observed_at_ms: 1000, turns: 1, ...over,
});

// Cards do LanePoller (tela raspada) no formato que o broker monta.
const card = (sid, over = {}) => ({
  sid, title: sid, kind: sid, source: "adapted", state: "running",
  detail: "● lowering the IR", peek: ["● lowering the IR"], approveKey: null,
  atShell: false, observedAt: 999, cols: 120, rows: 34, ...over,
});

test("o Kind do protocolo vira estado do board sem heurística nenhuma", () => {
  assert.equal(loomdStateOf("awaiting_approval"), "waiting");
  assert.equal(loomdStateOf("awaiting_input"), "waiting");
  assert.equal(loomdStateOf("tool_call"), "running");
  assert.equal(loomdStateOf("turn_ended"), "idle");
  assert.equal(loomdStateOf("session_ended"), "exited");
  assert.equal(loomdStateOf("error"), "stuck");
});

test("um Kind que ainda não sabemos ler é `unknown`, nunca um chute otimista", () => {
  // O vocabulário do CLI CRESCE (medido no loomd: 58→70 notificações do codex em 22 versões).
  // Este mapa VAI ficar incompleto; ficar incompleto não pode virar "idle" — um board que
  // relaxa sozinho quando o fornecedor inventa um evento é pior do que um board que diz que
  // não sabe.
  assert.equal(loomdStateOf("algo_novo_em_2027"), "unknown");
  assert.equal(loomdStateOf(undefined), "unknown");
});

test("a pendência de aprovação chega como id + método, não como tupla crua", () => {
  const c = loomdCard(lane({ kind: "awaiting_approval", pending_approval: ["7", "item/fileChange/requestApproval"] }));
  assert.equal(c.state, "waiting");
  assert.deepEqual(c.pendingApproval, { id: "7", method: "item/fileChange/requestApproval" });
  // O método é o que decide o enum da resposta lá no loomd — perdê-lo é o "aprovado" que não aprova.
  assert.equal(c.approveKey, null, "o loomd aprova por RPC; anunciar tecla mandaria send-keys a um pane inexistente");
});

test("o card exato não inventa peek — sem tela para citar, nada é citado", () => {
  const c = loomdCard(lane());
  assert.deepEqual(c.peek, []);
  assert.equal(c.confidence, EXACT);
  assert.equal(c.truthSource, "loomd");
});

test("o loomd manda a ordem de urgência e a fusão a preserva", () => {
  const m = reduceLoomdLanes({ lanes: [lane({ lane: "loom-9", kind: "awaiting_approval" }), lane()] });
  assert.deepEqual([...m.keys()], ["loom-9", "loom-1"]);
});

// ─── A FUSÃO: o rótulo é o produto ───────────────────────────────────────────────────────────

test("tudo que veio de capture-pane sai `inferred` — literal, não derivado", () => {
  const out = fuseFleet([card("claude-1"), card("codex-1")], new Map());
  assert.deepEqual(out.map((e) => e.confidence), [INFERRED, INFERRED]);
  assert.deepEqual(out.map((e) => e.truthSource), ["capture-pane", "capture-pane"]);
});

test("a lane que só o loomd conhece entra como card ADICIONAL, sem apagar ninguém", () => {
  const m = reduceLoomdLanes({ lanes: [lane({ kind: "awaiting_approval" })] });
  const out = fuseFleet([card("claude-1"), card("codex-1")], m);
  assert.equal(out.length, 3);
  assert.equal(out.find((e) => e.sid === "loom-1").confidence, EXACT);
  assert.equal(out.filter((e) => e.confidence === INFERRED).length, 2);
});

test("O CONTRASTE: exact e inferred convivem no MESMO array", () => {
  // Este é o produto da fatia. Não é "as lanes agora são exact": é o operador conseguir VER,
  // lado a lado, o que foi medido no protocolo e o que foi adivinhado da tela.
  const m = reduceLoomdLanes({ lanes: [lane()] });
  const out = fuseFleet(["claude-1", "claude-2", "codex-1"].map((s) => card(s)), m);
  assert.equal(out.filter((e) => e.confidence === EXACT).length, 1);
  assert.equal(out.filter((e) => e.confidence === INFERRED).length, 3);
});

test("quando as duas fontes veem a mesma lane, o protocolo ganha — e a regex nunca é promovida", () => {
  const m = reduceLoomdLanes({ lanes: [lane({ lane: "claude-1", kind: "awaiting_approval", detail: "posso escrever?" })] });
  const out = fuseFleet([card("claude-1", { state: "running", detail: "adivinhado da tela" })], m);
  assert.equal(out.length, 1);
  assert.equal(out[0].state, "waiting");
  assert.equal(out[0].detail, "posso escrever?");
  assert.equal(out[0].confidence, EXACT);
  // A tela continua servindo de peek; ela só não decide mais o veredito.
  assert.deepEqual(out[0].peek, ["● lowering the IR"]);
});

// ─── A QUEDA: precisa ser VISÍVEL ────────────────────────────────────────────────────────────

test("sem nunca ter perguntado, o modo é `unknown` e ninguém é exact", () => {
  const v = new LoomdView({ now: () => 1000 });
  assert.equal(v.truth().mode, "unknown");
  assert.equal(v.lanes.size, 0);
});

test("um sweep com o bloco popula a tabela e declara `observed`", () => {
  const v = new LoomdView({ now: () => 1000 });
  v.ingest(state([lane()]));
  assert.equal(v.truth().mode, "observed");
  assert.equal(v.get("loom-1").confidence, EXACT);
  assert.equal(v.truth().lanes, 1);
  assert.equal(v.truth().error, null);
});

test("o loomd cair NÃO vira `tudo inferred em silêncio`: os cards exatos caem COM nome e motivo", () => {
  // O falso-positivo mais provável desta fatia: sem loomd, todo mundo sai inferred, nada quebra,
  // e o board fica idêntico ao de ontem — indistinguível de sucesso a olho nu.
  const v = new LoomdView({ now: () => 1000 });
  v.ingest(state([lane()]));
  v.ingest(`${LOOMD_DELIM}\n${resto}`);          // perguntamos; o curl voltou vazio
  const t = v.truth();
  assert.equal(t.mode, "down");
  assert.equal(v.lanes.size, 0, "nenhum card exato sobrevive a uma medição de que a fonte caiu");
  assert.deepEqual(t.lost, ["loom-1"], "a lane perdida é NOMEADA — sem isso a queda é só um card a menos");
  assert.match(t.error, /não respondeu/);
});

test("`não perguntamos` é um modo diferente de `perguntamos e ele não respondeu`", () => {
  const v = new LoomdView({ now: () => 1000 });
  v.ingest(resto);                                // stdout de um cockpit sem o bloco
  assert.equal(v.truth().mode, "absent");
  assert.match(v.truth().error, /@@LOOMD/);
});

test("uma leitura exata parada envelhece para `stale` — card de 5 min atrás é card de 5 min atrás", () => {
  let t = 1000;
  const v = new LoomdView({ now: () => t, staleAfterMs: 45000 });
  v.ingest(state([lane()], 1000), 1000);
  assert.equal(v.truth().mode, "observed");
  t = 1000 + 46000;                               // o sweep falhou; ingest não roda
  assert.equal(v.truth().mode, "stale");
  assert.equal(v.get("loom-1").confidence, EXACT, "a tabela envelhece, não é apagada");
  assert.match(v.truth().error, /sem resposta nova/);
});

test("um bloco só com linhas em branco é medição de ausência, não leitura válida", () => {
  // A metade "AUSÊNCIA DE MEDIÇÃO" (o exec inteiro falhar) não pode ser exercida aqui — ingest
  // nem é chamado nesse caminho. Ela é medida em lanePoller.loomd.test.mjs, com um exec que
  // realmente falha; afirmá-la neste arquivo seria verde sem condição exercida.
  const v = new LoomdView({ now: () => 1000 });
  v.ingest(state([lane()]));
  v.ingest(`${LOOMD_DELIM}\n\n \n${resto}`);
  assert.equal(v.lanes.size, 0);
  assert.equal(v.truth().mode, "down");
});

test("o loomd voltar restaura o exact e limpa o motivo da queda", () => {
  const v = new LoomdView({ now: () => 1000 });
  v.ingest(state([lane()]));
  v.ingest(`${LOOMD_DELIM}\n${resto}`);
  v.ingest(state([lane()], 2000));
  const t = v.truth();
  assert.equal(t.mode, "observed");
  assert.deepEqual(t.lost, []);
  assert.equal(t.error, null);
  assert.equal(v.get("loom-1").confidence, EXACT);
});

// ─── consertos dos achados da verificação adversarial (09-ago) ───────────────────────────

test("o frescor do card exato é a hora da LEITURA, nunca a do último evento da lane", () => {
  // Bloqueante achado pelo cético: `observed_at_ms` por lane é a hora do último EVENTO
  // (trama.rs: st.observed_at_ms = e.ts_ms). Uma lane exata, saudável e QUIETA há 10 min
  // apareceria laranja, "leitura antiga" — a fonte medida pareceria mais velha que as
  // adivinhadas, que renovam o carimbo a cada 12s. A tela venderia o oposto da verdade.
  const antigo = 1_000_000;      // a lane fez algo há muito tempo
  const agora = 1_600_000;       // mas nós confirmamos o estado AGORA
  const c = loomdCard({ lane: "loom-1", kind: "idle", observed_at_ms: antigo }, agora);
  assert.equal(c.observedAt, agora, "o card envelhece pelo nosso relógio de leitura");
  assert.equal(c.lastEventAt, antigo, "e a hora do último evento continua disponível, como informação");
  assert.notEqual(c.observedAt, c.lastEventAt);
});

test("um card rotulado `exact` NUNCA cita evidência vinda da tela", () => {
  // Achado sério: `detail: l.detail || e.detail` fazia um card `exact` cair para o texto do
  // capture-pane quando o loomd não tinha evidência — regex vendida como protocolo, dentro do
  // card que existe justamente para provar a diferença. E o Swift lê esse texto em voz alta.
  // A fixture DECLARA `exact` porque agora o campo vem do contrato: card sem `confidence`
  // degrada para `inferred`, que é o lado seguro. O invariante testado aqui é o do `detail`.
  const semEvidencia = loomdCard({ lane: "codex-1", kind: "idle", confidence: "exact" }, 5);
  const daTela = [{ sid: "codex-1", state: "running", detail: "✻ Crunched for 12m — lido da TELA" }];
  const [f] = fuseFleet(daTela, new Map([["codex-1", semEvidencia]]));
  assert.equal(f.confidence, "exact");
  assert.equal(f.detail, "", "sem evidência do protocolo, o card fica SEM evidência — vazio é honesto");
  assert.doesNotMatch(f.detail, /TELA/);

  // E quando o loomd TEM evidência, é a dele que aparece.
  const comEvidencia = loomdCard({ lane: "codex-1", kind: "error", detail: "rpc recusado", confidence: "exact" }, 5);
  const [g] = fuseFleet(daTela, new Map([["codex-1", comEvidencia]]));
  assert.equal(g.detail, "rpc recusado");
});

test("o confidence vem do CONTRATO do loomd, não de uma constante nossa", () => {
  // Hoje nenhum emissor Rust produz `inferred`, mas o campo existe porque a lane de
  // compatibilidade por PTY vai produzir. Cravar EXACT promoveria a mentira no dia em que ela
  // aparecesse; e ausência degrada para o lado seguro, nunca para o confortável.
  assert.equal(loomdCard({ lane: "a", kind: "idle", confidence: "exact" }, 1).confidence, "exact");
  assert.equal(loomdCard({ lane: "a", kind: "idle", confidence: "inferred" }, 1).confidence, "inferred");
  assert.equal(loomdCard({ lane: "a", kind: "idle" }, 1).confidence, "inferred", "campo ausente NÃO vira exact");
});

test("a fusão também honra o contrato: lane que o loomd declara `inferred` NÃO vira `exact`", () => {
  // Achado adversarial: `loomdCard` passou a honrar o campo, mas `fuseFleet` cravava EXACT
  // literal e desfazia isso — a mentira sobrevivia num caminho só. O caso é o da lane de
  // compatibilidade por PTY, que o loomd já prevê e ainda não emite.
  const daTela = [{ sid: "codex-1", state: "running", detail: "tela" }];
  const cardInferido = loomdCard({ lane: "codex-1", kind: "idle", confidence: "inferred" }, 9);
  const [f] = fuseFleet(daTela, new Map([["codex-1", cardInferido]]));
  assert.equal(f.confidence, "inferred", "o loomd disse inferred; a fusão não pode promover");
  const cardExato = loomdCard({ lane: "codex-1", kind: "idle", confidence: "exact" }, 9);
  assert.equal(fuseFleet(daTela, new Map([["codex-1", cardExato]]))[0].confidence, "exact");
});
