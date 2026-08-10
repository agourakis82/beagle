// loomd.mjs — a metade MEDIDA da Frota.
//
// O LanePoller lê a TELA das 11 lanes e adivinha o estado com regex. O loomd (crates/loomd) não
// lê tela: ele fala JSON-RPC com o `codex app-server` e recebe hooks HTTP do Claude Code, então
// o estado dele vem como enum do protocolo. Este módulo transporta essa segunda fonte até o
// board e — a parte que importa — mantém as duas SEPARADAS e ROTULADAS:
//
//   confidence: "exact"    → veio de protocolo tipado (loomd)
//   confidence: "inferred" → veio de `tmux capture-pane` + regex (LanePoller)
//
// Regra dura: nada que veio de regex é marcado `exact`. Nunca. O rótulo é o produto.
//
// A OUTRA regra dura é a queda. Se o loomd cai e as lanes dele simplesmente somem (ou pior,
// reaparecem como `inferred`), o board fica idêntico ao de ontem e o operador não tem como
// saber que perdeu a fonte boa — indistinguível de sucesso a olho nu. Por isso a queda tem
// nome, e o nome viaja no frame:
//
//   | o que o sweep trouxe                       | efeito                                    |
//   |--------------------------------------------|-------------------------------------------|
//   | bloco com JSON do contrato                 | tabela substituída; mode="observed"       |
//   | bloco presente, corpo vazio/ilegível       | tabela DESCARTADA; mode="down"  + lost[]  |
//   | bloco ausente do stdout                    | tabela DESCARTADA; mode="absent" + lost[] |
//   | o sweep inteiro falhou (ingest não roda)   | tabela ENVELHECE; mode="stale" após o teto|
//
// A distinção entre "descarta" e "envelhece" é deliberada e é a diferença entre uma MEDIÇÃO e
// uma AUSÊNCIA DE MEDIÇÃO. Se o exec voltou e o loomd não respondeu, isso é um fato observado
// sobre o loomd: manter os cards `exact` seria afirmar uma verdade que ninguém mediu. Se o exec
// nem voltou (cluster fora), não sabemos nada sobre o loomd — aí a tabela envelhece, exatamente
// como o LanePoller faz com os vereditos dele.
import { parseLoomdState, hasLoomdBlock } from "../platform-bridge.mjs";

export const EXACT = "exact";
export const INFERRED = "inferred";

/// O `Kind` do loomd (event.rs) → o vocabulário de estado que o board e o Swift já falam.
/// Só o que o protocolo diz; nada aqui é heurística.
export const KIND_TO_STATE = {
  awaiting_approval: "waiting",
  awaiting_input: "waiting",
  turn_started: "running",
  tool_call: "running",
  tool_result: "running",
  diff_proposed: "running",
  approval_answered: "running",
  turn_ended: "idle",
  idle: "idle",
  session_started: "idle",
  session_ended: "exited",
  // Não existe estado "error" no board. `stuck` é o que o cliente já pinta como "precisa de
  // você e não está andando" — e o `detail` carrega a mensagem do erro, que é a evidência.
  error: "stuck",
  unknown: "unknown",
};

/// Um `Kind` que ainda não sabemos ler é `unknown`, nunca um chute otimista. O vocabulário do
/// CLI CRESCE (medido no loomd: codex foi de 58 a 70 notificações em 22 versões), então este
/// mapa vai ficar incompleto — e ficar incompleto não pode virar "idle".
export function loomdStateOf(kind) {
  return Object.prototype.hasOwnProperty.call(KIND_TO_STATE, String(kind)) ? KIND_TO_STATE[kind] : "unknown";
}

/// `pending_approval` chega do Rust como tupla → array JSON ["id", "método"]. O método decide o
/// enum da resposta lá no loomd; aqui ele é só evidência de que há uma pendência real.
function pendingOf(raw) {
  if (!Array.isArray(raw) || raw.length < 2) return null;
  return { id: String(raw[0]), method: String(raw[1]) };
}

/// Uma LaneState do loomd → um card da Frota. Puro.
///
/// 🚨 `readAtMs` é OBRIGATÓRIO e é o relógio DESTE sweep, não o do loomd.
///
/// Motivo (achado bloqueante da verificação adversarial): o `observed_at_ms` POR LANE do loomd é
/// a hora do ÚLTIMO EVENTO daquela lane (`trama.rs`: `st.observed_at_ms = e.ts_ms`), não a hora
/// em que nós confirmamos o estado. Uma lane exata e saudável que está simplesmente QUIETA há
/// dez minutos apareceria na Frota laranja, marcada "leitura antiga" — ou seja, a fonte MEDIDA
/// pareceria mais velha que as adivinhadas, que renovam o carimbo a cada 12s. A tela venderia o
/// oposto da verdade, e justamente no card que existe para provar a diferença.
///
/// São dois fatos diferentes e agora têm dois campos:
///   `observedAt`   — quando NÓS confirmamos este estado (envelhece o card);
///   `lastEventAt`  — quando a lane fez alguma coisa (informação, não frescor).
export function loomdCard(l, readAtMs) {
  const lane = String(l?.lane || "");
  const kind = String(l?.kind || "unknown");
  return {
    sid: lane,
    title: lane,
    kind: lane,
    source: "loomd",
    // De ONDE veio o veredito, por extenso. `confidence` é o rótulo; este é o endereço da fonte.
    truthSource: "loomd",
    // O `confidence` é do CONTRATO (trama.rs), não uma constante nossa: o loomd já prevê emitir
    // `inferred` na lane de compatibilidade por PTY, que ainda não existe. Cravar EXACT aqui
    // seria promover a mentira no dia em que ela aparecesse. Honramos o que a fonte declara, e
    // na ausência degradamos para o lado seguro.
    confidence: l?.confidence === INFERRED ? INFERRED : (l?.confidence === EXACT ? EXACT : INFERRED),
    state: loomdStateOf(kind),
    loomdKind: kind,
    detail: String(l?.detail || "").slice(0, 240),
    // Sem tela para citar: o card exato não tem peek, e inventar duas linhas seria voltar a
    // vender pixel como verdade.
    peek: [],
    // O loomd aprova por RPC (`POST /v2/lanes/:lane/approve`), não por tecla no tmux. Anunciar
    // uma tecla aqui faria o cliente mandar `send-keys` para um pane que não existe.
    approveKey: null,
    pendingApproval: pendingOf(l?.pending_approval),
    hasDiff: typeof l?.last_diff === "string" && l.last_diff.length > 0,
    // 🚨 O TEXTO do diff, não só o booleano. Até 10-ago-2026 o unified diff chegava pronto do
    // loomd e era descartado aqui — a tela sabia que EXISTIA uma mudança proposta e não tinha
    // como mostrá-la, então o operador voltava para o terminal justamente no momento em que a
    // interface deveria servir para alguma coisa.
    diff: typeof l?.last_diff === "string" && l.last_diff.length > 0 ? l.last_diff : null,
    // A mensagem sendo escrita agora (deltas coalescidos no loomd). `null` quando não há turno
    // em voo — e é `null` mesmo, não string vazia: vazio é um texto, ausente é outra coisa.
    streamingText: typeof l?.streaming_text === "string" && l.streaming_text.length > 0
      ? l.streaming_text : null,
    // Comando ou patch: decide o rótulo do botão porque decide o risco.
    approvalKind: l?.pending_kind || null,
    // O turno EM CURSO. É o que decide se a tela oferece parar/guiar — e a resposta vem daqui,
    // nunca de um palpite do cliente sobre o último passo que ele viu.
    currentTurn: l?.current_turn || null,
    turns: Number(l?.turns) || 0,
    session: l?.session ? String(l.session) : null,
    atShell: false,
    // O frescor do card é a hora da NOSSA leitura. Ver o comentário de loomdCard.
    observedAt: Number(readAtMs) || null,
    // A hora do último evento da lane continua disponível — como informação, não como frescor.
    lastEventAt: Number(l?.observed_at_ms) || null,
    cols: null, rows: null,
  };
}

/// O payload inteiro do /v2/state → Map(lane → card), na ordem em que o loomd mandou (ele já
/// ordena por urgência: quem espera por você vem primeiro).
export function reduceLoomdLanes(payload, readAtMs) {
  const out = new Map();
  for (const l of (payload?.lanes || [])) {
    const card = loomdCard(l, readAtMs);
    if (card.sid) out.set(card.sid, card);
  }
  return out;
}

/// A fusão. `entries` são os cards do LanePoller (tela raspada); `loomdLanes` é o Map acima.
/// Puro, e é aqui que mora o invariante:
///   * todo card sem contraparte no loomd sai `inferred` — LITERAL, não derivado, porque hoje
///     100% deles vem de `capture-pane`;
///   * uma lane que o loomd conhece é servida pelo loomd (veredito, detail e observedAt) e sai
///     `exact`; a tela dela, se houver, vira só o peek;
///   * uma lane que só o loomd conhece entra como card ADICIONAL, sem apagar ninguém.
/// Sem loomd no ar, o array de saída é exatamente o de hoje mais `confidence:"inferred"`.
export function fuseFleet(entries, loomdLanes) {
  const map = loomdLanes instanceof Map ? loomdLanes : new Map(Object.entries(loomdLanes || {}));
  const fused = (entries || []).map((e) => {
    const l = map.get(e.sid);
    if (!l) return { ...e, confidence: INFERRED, truthSource: "capture-pane" };
    return {
      ...e,
      // 🚨 O confidence é do CONTRATO, também aqui. `loomdCard` já honra o campo que a fonte
      // declara; cravar EXACT na fusão desfazia isso e reintroduzia a mentira num caminho só —
      // uma lane que o loomd declarasse `inferred` (a de compatibilidade por PTY, que virá)
      // sairia `exact` só por ter contraparte na tela. Achado da verificação adversarial.
      confidence: l.confidence,
      truthSource: "loomd",
      state: l.state,
      // 🚨 NÃO herdar o detail da tela. `detail` é a EVIDÊNCIA que o card cita e que o leitor de
      // acessibilidade lê em voz alta. Num card rotulado `exact`, cair para o texto vindo de
      // `capture-pane` seria vender regex como protocolo — a única mentira que este módulo
      // existe para impedir. Sem evidência do protocolo, o card fica SEM evidência: o loomd só
      // preenche `detail` em tool_call e error, e vazio é honesto.
      detail: l.detail || "",
      loomdKind: l.loomdKind,
      pendingApproval: l.pendingApproval,
      hasDiff: l.hasDiff,
      diff: l.diff,
      streamingText: l.streamingText,
      approvalKind: l.approvalKind,
      currentTurn: l.currentTurn,
      turns: l.turns,
      approveKey: null,          // aprovação por RPC, não por tecla — ver loomdCard
      // Idem: o frescor vem da leitura do loomd, não do último evento da lane.
      observedAt: l.observedAt ?? e.observedAt,
      lastEventAt: l.lastEventAt ?? null,
    };
  });
  const seen = new Set(fused.map((e) => e.sid));
  for (const [lane, card] of map) if (!seen.has(lane)) fused.push(card);
  return fused;
}

/// A leitura viva do loomd: estado + modo de verdade, no molde do OficinaPoller/HazardPoller.
/// Não tem timer próprio de propósito — ele pega carona no sweep do LanePoller, para o loomd e
/// a tela compartilharem UM relógio. Duas janelas de `isStale` concorrendo no mesmo board é
/// como se produz um card fresco ao lado de um card velho dizendo coisas diferentes.
export class LoomdView {
  constructor({ now = () => Date.now(), staleAfterMs = 45000 } = {}) {
    this._now = now;
    this._staleAfterMs = staleAfterMs;
    this._lanes = new Map();
    // DOIS carimbos, de propósito, e não são intercambiáveis:
    //   _observedAt — o relógio do loomd (`observed_at_ms`), o que o card mostra;
    //   _readAt     — o relógio DESTE sweep, o único contra o qual o frescor pode ser medido.
    // Misturar os dois é comparar o relógio do pod com o do cockpit e chamar o resultado de
    // idade. Custou um teste vermelho aqui antes de custar um card mentiroso no board.
    this._observedAt = null;
    this._readAt = null;
    this._mode = "unknown";       // nunca perguntamos / nunca respondeu
    this._error = null;
    this._lost = [];              // lanes que ele servia e parou de servir
  }

  get lanes() { return this._lanes; }
  get(lane) { return this._lanes.get(lane) || null; }
  all() { return Object.fromEntries(this._lanes); }

  /// `observed` só enquanto a leitura é recente. Passado o teto sem resposta nova, vira `stale`
  /// mesmo com a tabela cheia: um card exato de 5 minutos atrás continua sendo um card de 5
  /// minutos atrás.
  get mode() {
    if (this._mode !== "observed") return this._mode;
    const age = this._now() - (this._readAt || 0);
    return age > this._staleAfterMs ? "stale" : "observed";
  }

  /// O que o frame carrega para que a queda da fonte boa seja VISÍVEL, e não silenciosa.
  truth() {
    const mode = this.mode;
    return {
      mode,
      truthMode: mode === "observed" ? "observed" : (mode === "stale" ? "stale" : "unknown"),
      observedAt: this._observedAt,
      readAt: this._readAt,
      lanes: this._lanes.size,
      lost: [...this._lost],
      error: mode === "observed" ? null : (this._error || (mode === "stale" ? "loomd sem resposta nova" : null)),
    };
  }

  /// Ingere o stdout do sweep INTEIRO (o mesmo do LanePoller). Só deve ser chamado quando o exec
  /// voltou: um exec que falhou não é uma medição sobre o loomd, e chamar isto ali apagaria os
  /// cards exatos por causa de um problema de cluster.
  ingest(stdout, now = this._now()) {
    const payload = parseLoomdState(stdout);
    if (payload) {
      this._lanes = reduceLoomdLanes(payload, now);
      this._observedAt = Number(payload.observed_at_ms) || now;
      this._readAt = now;
      this._mode = "observed";
      this._error = null;
      this._lost = [];
      return this._lanes;
    }
    // Perguntamos e não veio resposta utilizável. Isso é uma medição: os cards exatos caem, e o
    // motivo vai junto. O que ele servia fica nomeado em `lost` — sem isso a queda seria só um
    // card a menos, que ninguém nota.
    const asked = hasLoomdBlock(stdout);
    if (this._lanes.size) this._lost = [...this._lanes.keys()];
    this._lanes = new Map();
    this._mode = asked ? "down" : "absent";
    this._error = asked
      ? "loomd não respondeu em 127.0.0.1:4400 dentro do pod (bloco vazio ou fora do contrato)"
      : "o exec não trouxe o bloco @@LOOMD: (cockpit desatualizado?)";
    return this._lanes;
  }
}
