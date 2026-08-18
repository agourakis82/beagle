// graph-extract.mjs — Phase 4, Task 4.3: sovereign-LLM graph extraction + apply.
//
// extractGraph turns a record's text into {entities, facts} via a cluster-local
// (sovereign) LLM — health/biography is sensitive, so NEVER a commercial API.
// The LLM call is injected (llmFn) so this is unit-testable with a stub.
//
// applyExtraction persists the result onto the bi-temporal graph: resolveEntity
// each mention, then for each fact INVALIDATE any contradicting current fact
// (same subject+predicate, single-valued, different object → SET valid_to, never
// delete) before inserting the new one (idempotent on content_sha256).

import crypto from "node:crypto";
import { resolveEntity } from "./graph.mjs";

function sha256hex(s) {
  return crypto.createHash("sha256").update(s).digest("hex");
}

/**
 * Closed vocabulary of self-state channels — the measurable quantity that could
 * bear on a self-report. Mirrors the CHECK constraint in sql/008_self_report.sql;
 * both exist because the schema is the authority and this is the fast path that
 * keeps a malformed field from costing the whole fact.
 */
export const SELF_STATE_CHANNELS = new Set([
  "sleep", "arousal", "valence", "pain", "fatigue", "oncall",
]);

/**
 * O SINAL do auto-relato. Espelha o CHECK de sql/015_state_polarity.sql.
 *
 * `alta` é sempre MAIS do estado que o canal nomeia, nunca "melhor" — bom e ruim trocam de
 * lado conforme o canal (dormir mais é bom, ficar mais tenso não), e um vocabulário avaliativo
 * faria o extrator escorregar exatamente onde a direção pré-registrada precisa dele firme.
 */
export const SELF_STATE_POLARITIES = new Set(["alta", "baixa"]);

/**
 * Como o extrator nomeia O PRÓPRIO SUJEITO quando ele fala de si.
 *
 * Derivado dos sujeitos reais medidos em 18-ago-2026, não inventado: `eu` (14), `self` (5),
 * `speaker` (4), `user` (2), `I` (2), `ele` (2).
 */
export const SUJEITOS_DE_SI = new Set([
  "eu", "i", "me", "self", "myself", "speaker", "user", "ele", "o sujeito", "sujeito",
]);

/**
 * O ESTADO É DELE? Diferente de `speakerIsSubject`, que pergunta se ELE FALOU.
 *
 * As duas guardas são necessárias e nenhuma cobre a outra. Medido no primeiro veredito da
 * Fase 2: 3 de 9 auto-relatos em canal ELEGÍVEL eram falsos positivos, e todos tinham a mesma
 * forma — o falante era ele, o sujeito não:
 *
 *   "Você estava confuso."                    sujeito `você`      → o COMPANION
 *   "Tem muita coisa pra melhorar no beagle"  sujeito `Beagle`    → o PROJETO
 *   "A probabilidade posterior…"              sujeito `parser/…`  → texto técnico
 *
 * Corroboração confronta a fisiologia DELE. Um estado atribuído à máquina, ou ao compilador,
 * casado com a HRV de um humano é o mesmo erro que a quarentena de proveniência existe para
 * impedir — só que com a cara trocada.
 *
 * ⚠️ LISTA BRANCA de propósito, e não lista negra. O universo de coisas que não são ele é
 * infinito; o de nomes que ele usa para si é pequeno e medido. Errar para o lado de RECUSAR é
 * o lado seguro: falso positivo corrompe a ciência, falso negativo só custa cobertura.
 *
 * Pediu-se ao modelo a mesma coisa no prompt, e ele obedeceu em 2 dos 4 casos. Instrução de
 * prompt não é guarda: o modelo propõe, o código decide.
 */
export function subjectIsSelf(subject) {
  if (typeof subject !== "string") return false;
  return SUJEITOS_DE_SI.has(subject.trim().toLowerCase());
}

/**
 * Um auto-relato só vale se quem falou for O SUJEITO. Decidido pelo registro,
 * nunca pelo modelo — o extrator lê texto e não tem como saber de quem é a boca.
 *
 * Medido antes de escrever isto: os QUATRO primeiros auto-relatos com canal que
 * chegaram ao banco vinham de registros `role=assistant`,
 * `prov_actor=model_generated`. Eram o companion falando:
 *
 *   "o corpo está mais acelerado que o de costume"   (descrevendo a cena)
 *   "não tenho humor, tenho postura"                 (falando de SI MESMO)
 *   "você me disse que estava irritado comigo"       (lembrando o que ELE disse)
 *
 * O "self" do auto-relato era a máquina. Corroborar isso contra a fisiologia
 * dele seria confrontar a prosa do companion com a HRV de um humano — o modo de
 * falha que a quarentena de proveniência existe para impedir, acontecendo em
 * silêncio.
 *
 * A regra é dura de propósito. Na fila pessoal há 3.072 registros `assistant`
 * para 31 `user`: sem esta guarda, 99% do "substrato" seria a própria voz do
 * sistema voltando como evidência sobre o corpo dele.
 *
 * @param {{prov_actor?:string|null, role?:string|null}} rec
 * @returns {boolean}
 */
export function speakerIsSubject(rec = {}) {
  const role = typeof rec.role === "string" ? rec.role.trim().toLowerCase() : null;
  if (role) return role === "user";
  // Sem `role` declarado, o ator do registro é o que sobra. Note que
  // `user_stated` é frouxo (inclui ruído de harness de agente), mas texto de
  // harness não produz auto-relato de estado — e frouxo aqui erra para o lado
  // de aceitar fala humana, não para o de aceitar a máquina.
  return rec.prov_actor === "user_stated";
}

/**
 * Proveniência do fato, CARIMBADA PELO SISTEMA.
 *
 * Antes, a coluna `provenance` recebia `f.provenance` — o objeto que o próprio
 * modelo tinha emitido. Num sistema cuja tese inteira é que uma alegação carrega
 * como veio a ser acreditada, o extrator estava assinando o próprio atestado.
 *
 * Agora o que o modelo diz sobre si fica em quarentena sob `model_claimed`, e o
 * que o sistema sabe fica em `extracted_by`. Um modelo que emita
 * `{"provenance":{"extracted_by":{"model":"gpt-5"}}}` aterrissa em
 * `model_claimed.extracted_by` e nunca no topo — a chave de cima é escrita
 * depois, por quem observou a chamada.
 *
 * Também resolve o problema prático que motivou isto: até aqui, saber qual
 * modelo produziu um fato exigia cruzar `recorded_at` com a data de criação dos
 * ReplicaSets. Funcionou porque a janela era limpa; não é auditoria.
 *
 * @param {unknown} claimed  o que o modelo emitiu no campo provenance
 * @param {{model?:string|null, at?:string}} sistema
 */
export function stampProvenance(claimed, sistema = {}) {
  const out = {};
  if (claimed && typeof claimed === "object" && !Array.isArray(claimed)) {
    out.model_claimed = claimed;
  }
  out.extracted_by = {
    model: sistema.model ?? null,
    at: sistema.at ?? new Date().toISOString(),
  };
  return out;
}

/**
 * Aceita um instante só se for realmente um instante. O modelo escreve prosa
 * onde se pediu ISO — "cinco e quinze" apareceu em produção — e um valor assim
 * derruba o INSERT, levando o registro inteiro para a DLQ por causa de um campo.
 *
 * Devolve uma string ISO ou null. Não tenta adivinhar o que a prosa queria
 * dizer: interpretar "cinco e quinze" seria a máquina inventando o QUANDO de um
 * auto-relato, e o quando é justamente o que torna a corroboração possível.
 *
 * @param {unknown} v
 * @returns {string|null}
 */
export function coerceTimestamp(v) {
  if (v === null || v === undefined || v === "") return null;
  if (v instanceof Date) return Number.isNaN(v.getTime()) ? null : v.toISOString();
  if (typeof v !== "string" && typeof v !== "number") return null;
  const d = new Date(v);
  if (Number.isNaN(d.getTime())) return null;
  // Datas absurdas quase sempre são alucinação de formato, não história.
  const year = d.getUTCFullYear();
  if (year < 1900 || year > 2200) return null;
  return d.toISOString();
}

/**
 * Build the strict extraction prompt. Asks for ONLY a JSON object so parsing is
 * robust; the model is told to scope facts temporally and mark multi-valued
 * relations (so we don't over-invalidate).
 */
export function buildExtractionPrompt(content) {
  return [
    "Extract a knowledge graph from the text. Return ONLY a JSON object, no prose.",
    // O esquema era escrito em ABREVIACAO — `{"entities":[{"name","type"}]}` — que NAO e JSON
    // valido. Medido em 17-ago-2026: o modelo copiava `{"name", "type"}` literalmente para a
    // saida, produzindo JSON impossivel de parsear, o registro ia para a DLQ depois de tres
    // tentativas, e isso acontecia com o prompt antigo tanto quanto com o novo.
    //
    // Um esquema que o proprio modelo nao consegue copiar sem errar e um esquema mal escrito.
    // Agora vai um EXEMPLO completo e valido, que copiar acerta.
    "Shape (this is a valid example, follow it exactly):",
    '{"entities":[{"name":"Sounio","type":"system"}],',
    ' "facts":[{"subject":"Sounio","predicate":"passed_gate","object_literal":"madaros",',
    '           "statement":"O compilador Sounio passou no gate de madaros.",',
    '           "occurred_at":"2026-08-17T03:00:00Z","multi_valued":false,',
    '           "self_report":false}]}',
    "Optional keys: occurred_at, valid_from, confidence, multi_valued, self_report, state_channel.",
    "Rules: entities are people/projects/places/systems/concepts. predicate is a short snake_case",
    "relation. Set multi_valued=true for relations that can hold many objects at once (knows,",
    "uses, mentions). Use object_literal for non-entity objects (dates, numbers, free text).",
    "Scope facts in time when the text implies it. Extract only what the text supports.",
    "",
    // `statement` aparecia apenas na FORMA do JSON, sem nunca ser declarado obrigatorio nem
    // explicado — e todo modelo o tratava como enfeite. Medido em 17-ago-2026: 66% dos fatos
    // do `qwen2.5:14b` e ate 19 de um so registro no `r1-distill-70b` chegavam sem ele.
    //
    // Nao era defeito de modelo: era o prompt nao pedindo. E um fato sem `statement` nunca
    // pode ser recuperado, porque e esse texto que vai para o indice semantico.
    "STATEMENT IS MANDATORY. Every fact MUST have a non-empty `statement`: one self-contained",
    "sentence, in the language of the text, that a person could read on its own and understand",
    "without seeing subject/predicate/object. It is what makes the fact findable later.",
    "  good: \"Ele acordou as tres da manha com o peito apertado.\"",
    "  bad:  \"\"  (empty), \"blocked\", \"55\", \"contains_pr_state\"",
    "A fact you cannot phrase as a sentence is not a fact worth extracting — DROP IT instead of",
    "emitting it with an empty statement.",
    "",
    "SELF-REPORTS. When the speaker says something about their OWN state, set self_report=true",
    "and set state_channel to the one measurable quantity that could test it:",
    "  sleep    slept badly/well, hours slept, woke during the night",
    "  arousal  tense, agitated, wired, calm, relaxed",
    "  valence  feeling good/bad, down, content",
    "  pain     headache or any reported pain",
    "  fatigue  tired, exhausted, drained",
    "  oncall   working a shift / on call (context, not a state)",
    "occurred_at for a self-report is WHEN THE STATE HAPPENED, not when it was said. Two cases,",
    "and the difference matters:",
    "  PRESENT TENSE (\"estou irritado\", \"hoje está pior\", \"não durmo bem\") — the moment of",
    "  speaking IS the moment of the state. LEAVE occurred_at OUT and keep the fact; the system",
    "  stamps it with the utterance time. Do NOT drop these.",
    "  PAST, with no date given (\"semana passada dormi mal\", \"outro dia tive dor\") — you do not",
    "  know when. OMIT THE FACT. Do not guess a date, and do not leave occurred_at out either:",
    "  an absent time would be filled in with the moment of speaking, which would file last",
    "  week's state under today.",
    "If no channel fits, leave state_channel out; never force one. Statements about code, systems",
    "or other people are NOT self-reports.",
    "",
    // Medido em 18-ago-2026, no primeiro veredito: 3 de 9 auto-relatos em canal ELEGIVEL eram
    // falsos positivos, e o padrao era um so — o falante era ele, mas o SUJEITO nao.
    //
    //   "Voce estava confuso."                     -> arousal   (e sobre o COMPANION)
    //   "Voce esta me ouvindo?"                    -> arousal   (e uma pergunta)
    //   "Tem muita coisa pra melhorar no beagle"   -> fatigue   (e sobre o PROJETO)
    //
    // A guarda de falante (`speakerIsSubject`) garante que ELE falou. Nao garante que o
    // estado e DELE — e a corroboracao confronta a fisiologia DELE. Um estado atribuido a
    // maquina, ou ao projeto, casado com a HRV de um humano, e o mesmo erro de sempre com a
    // cara trocada.
    "THE SUBJECT MUST BE THE SPEAKER. self_report=true only when the person speaking is",
    "describing their OWN state, right now or at a stated time. First person, about themselves.",
    "  yes: \"estou ansioso\", \"dormi mal\", \"to cansado\", \"meu peito apertado\"",
    "  NO:  \"você estava confuso\"        (about the assistant)",
    "  NO:  \"você está me ouvindo?\"      (a question, not a state)",
    "  NO:  \"tem muita coisa pra melhorar\" (about a project)",
    "  NO:  \"a probabilidade posterior…\"  (technical text — no state at all)",
    "Speaking ABOUT someone or something else is never a self-report, even in first person",
    "(\"acho que você está lento\" is about the system, not about him).",
    "",
    // O SINAL. Sem ele a direcao pre-registrada nao se aplica a nada. `alta` e sempre "mais do
    // estado que o canal nomeia" — nunca "melhor" ou "pior", porque bom e ruim trocam de lado
    // conforme o canal e um vocabulario avaliativo faz o modelo escorregar.
    "state_polarity: the DIRECTION of the state, \"alta\" or \"baixa\". It means MORE or LESS of",
    "the state the channel names — never better/worse:",
    "  sleep    alta = slept MORE/better    baixa = slept LESS/worse (\"dormi mal\" -> baixa)",
    "  arousal  alta = tense, agitated      baixa = calm, relaxed",
    "  fatigue  alta = tired, exhausted     baixa = rested",
    "  valence  alta = feeling good         baixa = feeling bad",
    // Palpite de moeda nao deixaria o julgamento indeciso: produziria acordo ou desacordo
    // INVENTADO em metade dos casos. Omitir e o resultado honesto.
    "If the text does not make the direction clear, OMIT state_polarity. Do not guess: a coin",
    "flip here manufactures agreement. Omitting is a valid, expected answer.",
    "",
    "TEXT:",
    String(content || "").slice(0, 8000),
  ].join("\n");
}

/**
 * Build a sovereign LLM fn over the cluster LiteLLM router (OpenAI-compatible).
 * Reasoning models (r1-distill-70b) are fine — parseLlmJson strips <think> blocks.
 * @param {string} baseUrl  e.g. http://router.llm-router.svc.cluster.local:4000
 * @param {{model:string, apiKey?:string, timeoutMs?:number, temperature?:number}} opts
 * @returns {(prompt:string)=>Promise<string>}
 */
export function makeRouterLlmFn(baseUrl, opts = {}) {
  const url = baseUrl.replace(/\/+$/, "") + "/v1/chat/completions";
  const model = opts.model;
  const timeoutMs = opts.timeoutMs ?? 120000;
  const temperature = opts.temperature ?? 0;
  // Injetavel para o teste poder exercitar as respostas de erro REAIS dos servidores sem rede.
  // Sem isto, o unico jeito de provar o detector seria provocar um estouro em producao — que e
  // como as duas fixtures deste teste foram colhidas, e nao da para repetir a cada `npm test`.
  const fetchImpl = opts.fetchImpl ?? fetch;
  if (!model) throw new Error("makeRouterLlmFn: opts.model required");
  return async function llmFn(prompt) {
    const headers = { "content-type": "application/json" };
    if (opts.apiKey) headers.authorization = `Bearer ${opts.apiKey}`;
    const ctrl = new AbortController();
    const timer = setTimeout(() => ctrl.abort(), timeoutMs);
    try {
      const resp = await fetchImpl(url, {
        method: "POST",
        headers,
        body: JSON.stringify({ model, temperature, messages: [{ role: "user", content: prompt }] }),
        signal: ctrl.signal,
      });
      if (!resp.ok) {
        const corpo = await resp.text();
        // O reconhecimento vem ANTES do erro generico: embrulhado em `Error`, "nao coube"
        // fica indistinguivel de "o servidor caiu", e as duas coisas pedem politicas opostas.
        const excedeu = detectaContextoExcedido(resp.status, corpo);
        if (excedeu) {
          throw new ContextTooLargeError(
            `contexto excedido: ${excedeu.promptTokens ?? "?"} tokens de prompt para ${excedeu.ctxTokens ?? "?"} de contexto`,
            excedeu,
          );
        }
        throw new Error(`router ${resp.status}: ${corpo.slice(0, 200)}`);
      }
      const j = await resp.json();
      return j.choices?.[0]?.message?.content ?? "";
    } finally {
      clearTimeout(timer);
    }
  };
}

/** Pull the first balanced JSON object out of an LLM reply (tolerates prose/fences/reasoning). */
function parseLlmJson(reply) {
  // Strip reasoning blocks first — r1-distill emits <think>...</think> that may
  // itself contain braces, which would otherwise confuse the brace matcher.
  const s = String(reply || "").replace(/<think>[\s\S]*?<\/think>/gi, "");
  const start = s.indexOf("{");
  if (start === -1) return null;
  let depth = 0;
  for (let i = start; i < s.length; i++) {
    if (s[i] === "{") depth++;
    else if (s[i] === "}") {
      depth--;
      if (depth === 0) {
        try {
          return JSON.parse(s.slice(start, i + 1));
        } catch {
          return null;
        }
      }
    }
  }
  return null;
}

/**
 * Janela em que um instante DECLARADO pelo modelo e plausivel, em dias em torno da fala.
 *
 * Existe porque o modelo inventa a DATA quando o texto so da a HORA. Medido em 18-ago-2026
 * contra o servidor de producao: "Hoje acordei as 5h20 com o peito apertado" voltou como
 * `occurred_at = "2023-10-04T05:20:00Z"` — hora certa, data tres anos no passado. Com a
 * `direcao-v2`, que so admite hora declarada, seria exatamente esse fato a entrar no confronto,
 * contra a fisiologia de 2023.
 *
 * Sete dias, e nao trinta: a janela nao existe para acomodar relato antigo, existe para pegar
 * data alucinada. Um estado lembrado com precisao de instante mais de uma semana depois nao
 * sustenta um confronto de +-60 min de qualquer forma — aceita-lo largaria a guarda sem ganhar
 * um caso utilizavel.
 */
export const JANELA_INSTANTE_DIAS = 7;

/**
 * Aceita o instante declarado so se ele for plausivel perto do momento da fala.
 *
 * Sem ancora (o registro nao tem hora), NAO da para validar — e a resposta e recusar, nao
 * confiar. O custo de recusar e o fato cair para hora imputada, que sob a `direcao-v2` o torna
 * inelegivel: perde-se um caso. O custo de confiar e um instante inventado entrar no confronto
 * parecendo declarado, que e o unico erro que esta fase nao pode cometer.
 *
 * @returns {{ok:true, at:string}|{ok:false, motivo:string}}
 */
export function instanteDeclaradoPlausivel(declarado, ancora, janelaDias = JANELA_INSTANTE_DIAS) {
  if (declarado === null || declarado === undefined) return { ok: false, motivo: "ausente" };
  if (!ancora) return { ok: false, motivo: "sem ancora para validar" };
  const d = Date.parse(declarado);
  const a = Date.parse(ancora);
  if (!Number.isFinite(d) || !Number.isFinite(a)) return { ok: false, motivo: "instante ilegivel" };
  const dias = Math.abs(d - a) / 86400000;
  if (dias > janelaDias) {
    return { ok: false, motivo: `declarado a ${dias.toFixed(0)} dias da fala (teto ${janelaDias})` };
  }
  return { ok: true, at: declarado };
}

/** A broken extraction, as opposed to an empty one. Carries the reason to the DLQ. */
export class GraphExtractionError extends Error {
  constructor(message, { kind }) {
    super(message);
    this.name = "GraphExtractionError";
    this.kind = kind; // "llm" | "unparseable" | "exceed_context"
  }
}

/**
 * O registro nao cabe no contexto do servidor.
 *
 * Precisa ser um erro SEPARADO de "llm" porque a natureza da falha e outra: uma chamada que
 * falhou por rede ou por carga tem chance de dar certo na proxima; um registro grande demais
 * falha IDENTICAMENTE nas tres tentativas e depois morre na fila morta. Tratar os dois com a
 * mesma politica gasta GPU em repeticao garantidamente inutil e enterra o registro num lugar
 * de onde ele so volta por intervencao manual.
 *
 * Os numeros vem do corpo da resposta, nao de contagem propria: quem sabe quantos tokens o
 * prompt tem depois de aplicado o template do modelo e o servidor.
 */
export class ContextTooLargeError extends GraphExtractionError {
  constructor(message, { promptTokens = null, ctxTokens = null } = {}) {
    super(message, { kind: "exceed_context" });
    this.name = "ContextTooLargeError";
    this.promptTokens = promptTokens;
    this.ctxTokens = ctxTokens;
  }
}

/**
 * Reconhece "nao coube" na resposta de erro do servidor.
 *
 * Le o campo ESTRUTURADO, nunca a prosa da mensagem. Medido em 18-ago-2026 contra os dois
 * servidores reais do cluster:
 *
 *   llama.cpp  -> {"error":{"code":400,"type":"exceed_context_size_error",
 *                  "n_prompt_tokens":60031,"n_ctx":10240}}
 *   LiteLLM    -> {"error":{"message":"litellm.ContextWindowExceededError: ..."}}
 *
 * O llama.cpp carrega `type` e os dois numeros; o LiteLLM embrulha a excecao do provedor numa
 * string e nao tem campo proprio. Por isso o reconhecimento por prosa existe — mas so como
 * SEGUNDA via, para o backend que nao oferece campo. Onde ha campo, o campo manda.
 */
export function detectaContextoExcedido(status, corpo) {
  let j = null;
  try { j = typeof corpo === "string" ? JSON.parse(corpo) : corpo; } catch { j = null; }
  const e = j && typeof j === "object" ? j.error : null;

  if (e && typeof e === "object") {
    if (e.type === "exceed_context_size_error") {
      return {
        promptTokens: Number.isFinite(e.n_prompt_tokens) ? e.n_prompt_tokens : null,
        ctxTokens: Number.isFinite(e.n_ctx) ? e.n_ctx : null,
      };
    }
    const msg = typeof e.message === "string" ? e.message : "";
    // Segunda via: so vale para status 400. Um 500 com essa palavra no meio nao e o mesmo
    // caso, e tratar como se fosse mandaria uma falha transitoria para a quarentena.
    if (status === 400 && /ContextWindowExceededError|exceeds the available context size/i.test(msg)) {
      const m = msg.match(/\((\d+) tokens\) exceeds the available context size \((\d+) tokens\)/i);
      return { promptTokens: m ? Number(m[1]) : null, ctxTokens: m ? Number(m[2]) : null };
    }
  }
  return null;
}

/**
 * Extract {entities, facts} from a record via the injected sovereign LLM.
 *
 * THROWS on a broken extraction. It used to swallow every failure into an empty
 * result, which made "the model was unreachable" indistinguishable from "this
 * record contains no facts" — the worker marked the record done either way and
 * never came back to it. That is how the pipeline ran for 29 days emitting
 * facts=0 on every cycle with nothing in the DLQ and nothing in the logs.
 *
 * The three outcomes are now distinct:
 *   - LLM call fails            -> throw (kind "llm"): retry, then DLQ
 *   - reply present, unparseable -> throw (kind "unparseable"): retry, then DLQ
 *   - valid JSON, no entities/facts -> return empty: genuinely nothing to extract
 *
 * Only the third is success. Silence now means "nothing to say", never "the
 * extractor broke".
 *
 * @param {{content:string}} record
 * @param {{llmFn:(prompt:string)=>Promise<string>}} opts
 * @throws {GraphExtractionError}
 */
export async function extractGraph(record, { llmFn } = {}) {
  if (typeof llmFn !== "function") throw new Error("extractGraph: opts.llmFn required");
  let reply;
  try {
    reply = await llmFn(buildExtractionPrompt(record.content));
  } catch (err) {
    // "Nao coube" passa INTEIRO. Reembrulhar como `kind: "llm"` apagaria a unica informacao
    // que decide a politica la em cima — e o worker trataria um registro grande demais como
    // uma pane transitoria: tres repeticoes na GPU e enterro na fila morta.
    if (err instanceof ContextTooLargeError) throw err;
    throw new GraphExtractionError(`LLM call failed: ${err?.message ?? err}`, { kind: "llm" });
  }
  const obj = parseLlmJson(reply);
  if (!obj || typeof obj !== "object") {
    throw new GraphExtractionError(
      `LLM reply had no parseable JSON object (${String(reply ?? "").length} chars): ` +
        String(reply ?? "").replace(/\s+/g, " ").slice(0, 160),
      { kind: "unparseable" },
    );
  }
  const entities = Array.isArray(obj.entities) ? obj.entities.filter((e) => e && e.name) : [];
  const facts = Array.isArray(obj.facts) ? obj.facts.filter((f) => f && f.subject && f.predicate) : [];
  return { entities, facts };
}

/**
 * Persist an extraction onto the bi-temporal graph.
 * @param {import("pg").Pool} pool
 * @param {{entities:Array, facts:Array}} extraction
 * @param {{recordId?:(string|null), embedFn?:(texts:string[])=>Promise<number[][]>, occurredAt?:string}} opts
 * @returns {Promise<{entitiesResolved:number, factsInserted:number, factsInvalidated:number}>}
 */
export async function applyExtraction(pool, extraction, opts = {}) {
  const { recordId = null, embedFn = null, occurredAt = null, model = null,
          speaker = null } = opts;
  // Quem falou decide se auto-relato é admissível. Ausência de `speaker` é
  // tratada como "não é ele": um chamador que não sabe de quem é a fala não pode
  // autorizar uma alegação sobre o estado dele.
  const auto_ok = speaker ? speakerIsSubject(speaker) : false;
  const stampedAt = new Date().toISOString();
  const entities = extraction.entities || [];
  const facts = extraction.facts || [];

  // Optionally embed entity names (for near-dup resolution) AND fact statements
  // (for the graph retrieval channel) in one batch.
  let entEmb = {};
  let factEmb = {};
  if (embedFn && (entities.length || facts.length)) {
    try {
      const names = entities.map((e) => e.name);
      const statements = facts.map((f) => f.statement || "");
      const vecs = await embedFn([...names, ...statements]);
      entities.forEach((e, i) => (entEmb[e.name] = vecs[i]));
      facts.forEach((f, i) => (factEmb[i] = vecs[names.length + i]));
    } catch {
      entEmb = {};
      factEmb = {};
    }
  }

  // Resolve every entity to a node id, keyed by name.
  const idByName = {};
  let entitiesResolved = 0;
  for (const e of entities) {
    const r = await resolveEntity(pool, {
      name: e.name,
      type: e.type || "unknown",
      embedding: entEmb[e.name] ?? null,
      summary: e.summary || "",
    });
    idByName[e.name] = r.id;
    entitiesResolved++;
  }

  let factsInserted = 0;
  let factsInvalidated = 0;
  /** Fatos recusados por não terem sentença. Contado, nunca silencioso. */
  let semSentenca = 0;
  /**
   * Auto-relatos recusados porque o SUJEITO nao era ele. Contado, nunca silencioso.
   *
   * A lista branca de `subjectIsSelf` e estreita de proposito, e isso CUSTA relatos
   * legitimos — ja vi um: "Um pouco angustiado, mas sem motivo aparente", com sujeito
   * `person`, que a lista recusa. O custo foi aceito explicitamente; o que nao pode e ser
   * invisivel. Sem este numero, ninguem descobre que a guarda esta comendo demais.
   */
  let sujeitoAlheio = 0;
  // Instante declarado que a guarda recusou. Sai daqui pelo mesmo motivo que os outros dois:
  // um relato rebaixado de "hora declarada" para "hora imputada" muda de ELEGIVEL para
  // INELEGIVEL sob a direcao-v2, e um rebaixamento silencioso e indistinguivel de um relato
  // que nunca teve hora.
  let instanteRecusado = 0;
  for (let fi = 0; fi < facts.length; fi++) {
    const f = facts[fi];

    // FATO SEM `statement` NASCE INVISÍVEL.
    //
    // `statement` é o texto que vai para o índice semântico: sem ele o fato existe na tabela
    // e NUNCA pode ser recuperado. Não é um fato fraco — é um fato que ninguém jamais lerá,
    // ocupando espaço e inflando toda contagem de "conhecimento extraído".
    //
    // Medido em 17-ago-2026: 66% do que o `qwen2.5:14b` produzia vinha assim (contra 10% do
    // `coder:32b` e 7,9% do corpus histórico). A amostra mostra o padrão — `contains_pr_state
    // / blocked`, `has_pr_count / 55`: triplas raspadas de um dump, sem sentença.
    //
    // Recusar aqui, e CONTAR quantos foram recusados, é o oposto de deixar passar em
    // silêncio: a taxa de descarte vira um sinal da qualidade do extrator em vez de virar
    // lixo indistinguível dentro do grafo.
    if (typeof f.statement !== "string" || f.statement.trim() === "") {
      semSentenca++;
      continue;
    }

    let subjectId = idByName[f.subject];
    if (!subjectId) {
      subjectId = (await resolveEntity(pool, { name: f.subject, type: "unknown" })).id;
      idByName[f.subject] = subjectId;
    }
    let objectId = null;
    if (f.object) {
      objectId = idByName[f.object];
      if (!objectId) {
        objectId = (await resolveEntity(pool, { name: f.object, type: "unknown" })).id;
        idByName[f.object] = objectId;
      }
    }
    const objectLiteral = f.object ? null : (f.object_literal ?? null);
    // Um instante que o Postgres não sabe ler derruba o registro inteiro e o
    // manda para a DLQ depois de três tentativas. Visto em produção na primeira
    // hora depois do conserto: o modelo devolveu occurred_at="cinco e quinze".
    // Campo malformado custa um nulo, nunca o fato — a mesma regra do canal.
    const validFrom = coerceTimestamp(f.valid_from) ?? occurredAt ?? null;
    // A hora do fato vem do texto ou e' deduzida do instante da fala. As duas
    // valem, mas nao valem o mesmo: "acordei com o peito apertado" acordou ha
    // horas, e com janela de +-60min contra a fisiologia isso confronta o relato
    // com o corpo de outro momento. Marcado em vez de indistinguivel.
    // O instante declarado passa por uma checagem de plausibilidade antes de valer como
    // declarado. Ver `instanteDeclaradoPlausivel`: o modelo alucina a DATA quando o texto so
    // da a HORA, e sob a direcao-v2 e justamente o instante declarado que entra no confronto.
    const declaradoCru = coerceTimestamp(f.occurred_at);
    const plaus = instanteDeclaradoPlausivel(declaradoCru, occurredAt);
    const declarado = plaus.ok ? plaus.at : null;
    if (declaradoCru !== null && !plaus.ok) instanteRecusado++;
    const occ = declarado ?? occurredAt ?? null;
    const occImputado = declarado === null && occ !== null;

    // The model proposes; the schema decides. A channel outside the closed
    // vocabulary is dropped rather than stored, because the corroboration
    // criterion joins on this column — letting the model coin a channel would
    // let it quietly invent a new kind of evidence. The DB CHECK would reject it
    // anyway; doing it here means one bad field costs a null, not the whole fact.
    // DUAS guardas, e nenhuma cobre a outra: `auto_ok` diz que ELE FALOU (pelo registro),
    // `subjectIsSelf` diz que o ESTADO E DELE (pelo sujeito do fato).
    const propoeAuto = f.self_report === true && auto_ok;
    const selfReport = propoeAuto && subjectIsSelf(f.subject);
    // A recusa por sujeito e a unica que o dono escolheu pagar: ela vira numero.
    if (propoeAuto && !selfReport) sujeitoAlheio++;
    const proposed = typeof f.state_channel === "string" ? f.state_channel.trim().toLowerCase() : null;
    const stateChannel = selfReport && SELF_STATE_CHANNELS.has(proposed) ? proposed : null;
    // O SINAL do relato, sob a mesma regra do canal: vocabulario fechado, e o que cair fora
    // vira NULO em vez de entrar. Polaridade so existe se houver canal — sinal sem canal nao
    // julga nada, e guarda-lo daria a impressao de um dado utilizavel que nao e.
    //
    // NULO e resultado esperado: quando o texto nao deixa a direcao clara, o extrator omite.
    // Um palpite aqui nao deixaria o julgamento indeciso — fabricaria acordo ou desacordo em
    // metade dos casos.
    const polProposta = typeof f.state_polarity === "string"
      ? f.state_polarity.trim().toLowerCase() : null;
    const statePolarity = stateChannel && SELF_STATE_POLARITIES.has(polProposta) ? polProposta : null;
    const content_sha256 = sha256hex(
      [subjectId, f.predicate, objectId ?? "", objectLiteral ?? "", f.statement || ""].join("|"),
    );
    const factVec = f.embedding ?? factEmb[fi] ?? null;
    const embLit = factVec ? "[" + (Array.isArray(factVec) ? factVec.join(",") : factVec) + "]" : null;

    const client = await pool.connect();
    try {
      await client.query("BEGIN");
      // Contradiction: a SINGLE-VALUED relation whose object changed. Invalidate
      // the prior current fact(s) for (subject, predicate) with a different object.
      if (!f.multi_valued) {
        const inv = await client.query(
          `UPDATE facts SET valid_to = COALESCE($3::timestamptz, now())
             WHERE subject_id = $1 AND predicate = $2 AND valid_to IS NULL
               AND content_sha256 <> $4
               AND (object_id IS DISTINCT FROM $5 OR object_literal IS DISTINCT FROM $6)`,
          [subjectId, f.predicate, validFrom, content_sha256, objectId, objectLiteral],
        );
        factsInvalidated += inv.rowCount;
      }
      const ins = await client.query(
        `INSERT INTO facts
           (subject_id, predicate, object_id, object_literal, statement, embedding,
            valid_from, occurred_at, source_record_id, provenance, confidence, content_sha256,
            self_report, state_channel, occurred_at_imputed, state_polarity)
         VALUES ($1,$2,$3,$4,$5,$6::halfvec,
                 COALESCE($7::timestamptz, now()),$8,$9,$10::jsonb,$11,$12,$13,$14,$15,$16)
         ON CONFLICT (content_sha256) DO NOTHING
         RETURNING id`,
        [
          subjectId, f.predicate, objectId, objectLiteral, f.statement || "", embLit,
          validFrom, occ, recordId,
          JSON.stringify(stampProvenance(f.provenance, { model, at: stampedAt })),
          f.confidence ?? 1.0, content_sha256,
          selfReport, stateChannel, occImputado, statePolarity,
        ],
      );
      // Record the source→claim support for the quorum, even when the fact already
      // existed (rowCount 0). This is the corroboration multiplicity the dedup discards.
      const factId = ins.rowCount > 0
        ? ins.rows[0].id
        : (await client.query("SELECT id FROM facts WHERE content_sha256 = $1", [content_sha256])).rows[0]?.id;
      if (factId && recordId) {
        await client.query(
          `INSERT INTO fact_supports (fact_id, source_record_id)
           VALUES ($1, $2) ON CONFLICT (fact_id, source_record_id) DO NOTHING`,
          [factId, recordId],
        );
      }
      await client.query("COMMIT");
      if (ins.rowCount > 0) factsInserted++;
    } catch (err) {
      await client.query("ROLLBACK");
      throw err;
    } finally {
      client.release();
    }
  }
  return { entitiesResolved, factsInserted, factsInvalidated, semSentenca, sujeitoAlheio, instanteRecusado };
}

export default applyExtraction;
