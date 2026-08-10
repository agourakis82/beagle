//! O vocabulário único da frota.
//!
//! Cada fornecedor escreve "esperando humano" do seu jeito — `waitingOnApproval` (Codex),
//! `permission_prompt`/`agent_needs_input` (Claude), `awaitingInput` (Linear), `blocked` (Devin).
//! A camada que faltava no mercado não é multiplexação: é ESTA TABELA.
use serde::{Deserialize, Serialize};

/// De onde veio a verdade. É um campo do schema, não um lema de UI.
///
/// `Exact`   — veio de um protocolo tipado (app-server do Codex, hook do Claude).
/// `Inferred`— veio de tela raspada (a lane de compatibilidade, para CLI sem protocolo).
/// Nenhuma ação destrutiva pode disparar a partir de `Inferred`.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "lowercase")]
pub enum Confidence {
    Exact,
    Inferred,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum Kind {
    SessionStarted,
    SessionEnded,
    TurnStarted,
    TurnEnded,
    /// O que o OPERADOR mandou. Sem isto a trama é monólogo: dava para reconstruir o que o
    /// agente disse e nunca o que foi pedido — e uma tela de sessão precisa dos dois lados.
    UserPrompt,
    /// O que o agente disse, INTEIRO, em `text`. Distinto de `ToolCall`: até 10-ago-2026 os dois
    /// caíam no mesmo balde porque a discriminação mora em `item.type`, que não era lida.
    AgentMessage,
    /// Pedaço de mensagem em voo. **Não vai para a trama** — ver a política em `codex.rs`.
    Delta,
    ToolCall,
    ToolResult,
    DiffProposed,
    AwaitingApproval,
    AwaitingInput,
    ApprovalAnswered,
    Idle,
    /// Custo e janela de contexto do turno. Chega sem ser pedido (`usage_update`) e não existia
    /// em nenhum outro lugar da plataforma. Escopo aqui é persistir e expor por `/turns`;
    /// desenhar na tela é outra fatia.
    Usage,
    Error,
    /// O vocabulário CRESCE a cada versão do CLI (medido: codex 58→70 notificações em 22
    /// versões, nada removido). Desconhecido é informação registrada, nunca falha.
    Unknown,
}

/// Que tipo de permissão está sendo pedida. **Muda o risco**, então muda o rótulo do botão:
/// aplicar um patch é reversível por git; rodar um comando não é.
///
/// Vive separado de `approval_method` porque aquele é a string do protocolo — necessária para
/// responder com o enum certo — e esta é a pergunta que a tela faz ao operador.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum ApprovalKind {
    Command,
    Patch,
    Other,
}

impl ApprovalKind {
    pub fn of(method: &str) -> Self {
        if method.contains("fileChange") || method.contains("applyPatch") {
            ApprovalKind::Patch
        } else if method.contains("commandExecution") || method.contains("execCommand") {
            ApprovalKind::Command
        } else {
            ApprovalKind::Other
        }
    }
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct AgentEvent {
    /// Ordinal na trama. É o cursor de leitura — o cliente pede `?since=`.
    pub seq: u64,
    pub ts_ms: u64,
    /// A lane (claude-1, codex-2, …). É o endereço que o operador conhece.
    pub lane: String,
    pub kind: Kind,
    pub confidence: Confidence,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub session: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub turn: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub tool: Option<String>,
    /// A evidência: a linha do diálogo, a mensagem de erro, o nome do evento cru desconhecido.
    /// **Curta de propósito** — é o que cabe num card do board. Para ler a conversa, use `text`.
    #[serde(skip_serializing_if = "Option::is_none")]
    pub detail: Option<String>,
    /// O texto ÍNTEGRO. Até 10-ago-2026 só existia `detail`, cortado em 240 caracteres — e uma
    /// tela de conversa não pode ler de um campo truncado. `detail` continua sendo o resumo do
    /// board; os dois coexistem porque respondem a perguntas diferentes.
    #[serde(skip_serializing_if = "Option::is_none")]
    pub text: Option<String>,
    /// Unified diff, quando o agente propõe mudança. Dado, não pixel.
    #[serde(skip_serializing_if = "Option::is_none")]
    pub diff: Option<String>,
    /// Id da requisição de aprovação pendente, para o operador responder depois.
    #[serde(skip_serializing_if = "Option::is_none")]
    pub approval_id: Option<String>,
    /// O método que pediu a aprovação — decide QUAL enum a resposta precisa usar.
    #[serde(skip_serializing_if = "Option::is_none")]
    pub approval_method: Option<String>,
    /// Comando ou patch — a distinção que muda o risco, derivada de `approval_method`.
    #[serde(skip_serializing_if = "Option::is_none")]
    pub approval_kind: Option<ApprovalKind>,
}

impl AgentEvent {
    pub fn new(lane: &str, kind: Kind, confidence: Confidence) -> Self {
        Self {
            seq: 0,
            ts_ms: now_ms(),
            lane: lane.to_string(),
            kind,
            confidence,
            session: None,
            turn: None,
            tool: None,
            detail: None,
            text: None,
            diff: None,
            approval_id: None,
            approval_method: None,
            approval_kind: None,
        }
    }
    pub fn detail(mut self, d: impl Into<String>) -> Self {
        self.detail = Some(d.into());
        self
    }
    /// Guarda o texto ÍNTEGRO e deriva o resumo do board a partir dele — nunca o contrário.
    /// Derivar na direção certa é o que garante que os dois campos nunca discordem.
    pub fn with_text(mut self, t: impl Into<String>) -> Self {
        let t = t.into();
        self.detail = Some(resumir(&t));
        self.text = Some(t);
        self
    }
}

/// O resumo de card: primeira linha não vazia, teto de 240 caracteres.
///
/// Cortar o texto CRU em 240 partia no meio de uma palavra e, pior, podia devolver só espaço em
/// branco quando a resposta começava com linha vazia. O card cita a primeira coisa que o agente
/// disse, que é o que o operador reconhece.
pub fn resumir(t: &str) -> String {
    let linha = t
        .lines()
        .map(str::trim)
        .find(|l| !l.is_empty())
        .unwrap_or("");
    if linha.chars().count() <= 240 {
        return linha.to_string();
    }
    let corte: String = linha.chars().take(239).collect();
    // Não parte palavra ao meio se der para evitar sem perder mais de 40 caracteres.
    match corte.rfind(' ') {
        Some(i) if corte.len() - i < 40 => format!("{}…", &corte[..i]),
        _ => format!("{corte}…"),
    }
}

pub fn now_ms() -> u64 {
    std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .map(|d| d.as_millis() as u64)
        .unwrap_or(0)
}

fn s(v: &serde_json::Value, k: &str) -> Option<String> {
    v.get(k).and_then(|x| x.as_str()).map(str::to_string)
}

/// O id da thread, onde quer que esta versão do Codex o tenha posto.
///
/// 🚨 MEDIDO (codex 0.147.0): a forma NÃO é uniforme dentro do mesmo protocolo.
///   thread/start (resposta)  → result.thread.id
///   thread/started (notif.)  → params.thread.id
///   thread/status/changed    → params.threadId
///   turn/diff/updated        → params.threadId
/// Ler só `threadId` fazia o supervisor nunca aprender o id e o turno morrer em silêncio.
/// Leitor tolerante: aceita as duas formas e sobrevive a uma terceira aparecer.
pub fn thread_id(v: &serde_json::Value) -> Option<String> {
    v.get("threadId")
        .and_then(|x| x.as_str())
        .or_else(|| {
            v.get("thread")
                .and_then(|t| t.get("id"))
                .and_then(|x| x.as_str())
        })
        .or_else(|| {
            v.get("thread")
                .and_then(|t| t.get("sessionId"))
                .and_then(|x| x.as_str())
        })
        .map(str::to_string)
}

/// O id do TURNO, onde quer que esta versão do Codex o tenha posto.
///
/// 🚨 MEDIDO ao tentar interromper um turno vivo e receber "nenhum turno em curso": a forma não é
/// uniforme, exatamente como no `threadId`.
///   turn/started, turn/completed  → params.turn.id
///   item/*, turn/diff/updated     → params.turnId
/// Ler só `turnId` fazia o `turn/started` — o ÚNICO evento que abre o turno — passar sem alvo, e
/// então `turn/interrupt`/`turn/steer` recusavam por falta de precondição. A armadilha já estava
/// documentada no README para a thread; o turno caiu nela do mesmo jeito.
pub fn turn_id(v: &serde_json::Value) -> Option<String> {
    v.get("turnId")
        .and_then(|x| x.as_str())
        .or_else(|| {
            v.get("turn")
                .and_then(|t| t.get("id"))
                .and_then(|x| x.as_str())
        })
        .map(str::to_string)
}

// ─── Claude Code: hooks HTTP ────────────────────────────────────────────────────────────────
// O CLI liga de volta a cada transição. Não somos donos do processo — é CONFIGURAÇÃO.
// É isso que permite supervisionar lane que já estava rodando.

pub fn from_claude_hook(lane: &str, body: &serde_json::Value) -> AgentEvent {
    let ev = s(body, "hook_event_name").unwrap_or_default();
    let kind = match ev.as_str() {
        "SessionStart" => Kind::SessionStarted,
        "SessionEnd" => Kind::SessionEnded,
        "UserPromptSubmit" => Kind::TurnStarted,
        "PreToolUse" => Kind::ToolCall,
        "PostToolUse" => Kind::ToolResult,
        "PermissionRequest" => Kind::AwaitingApproval,
        "Stop" => Kind::TurnEnded,
        "Notification" => match s(body, "notification_type").unwrap_or_default().as_str() {
            // A mesma verdade que `waitingOnApproval` do Codex, escrita de outro jeito.
            "permission_prompt" | "agent_needs_input" => Kind::AwaitingApproval,
            "idle_prompt" => Kind::Idle,
            "agent_completed" => Kind::TurnEnded,
            _ => Kind::Unknown,
        },
        _ => Kind::Unknown,
    };
    let mut e = AgentEvent::new(lane, kind, Confidence::Exact);
    e.session = s(body, "session_id");
    e.tool = s(body, "tool_name");
    if kind == Kind::Unknown {
        // Guardar o nome cru: é assim que se descobre que o fornecedor adicionou algo.
        e.detail = Some(format!("hook não mapeado: {ev}"));
    } else if let Some(m) = s(body, "message") {
        e.detail = Some(m);
    }
    e
}

// ─── Codex: app-server (JSON-RPC) ───────────────────────────────────────────────────────────
// Aqui somos donos do processo, e em troca ganhamos o estado como ENUM.

pub fn from_codex_notification(
    lane: &str,
    method: &str,
    p: &serde_json::Value,
) -> Option<AgentEvent> {
    let kind = match method {
        "thread/started" => Kind::SessionStarted,
        "turn/started" => Kind::TurnStarted,
        "turn/completed" => Kind::TurnEnded,
        "turn/diff/updated" => Kind::DiffProposed,
        // 🚨 MEDIDO em 10-ago-2026 (censo cru, codex 0.147.0): num único turno chegam **70**
        // `item/agentMessage/delta` — e todos eram DESCARTADOS aqui, porque método desconhecido
        // devolvia `None`. A fonte "exact" da Frota via 7 de 107 eventos.
        "item/agentMessage/delta" => Kind::Delta,
        // `item.type` é quem discrimina: `userMessage` é o operador, `agentMessage` é a fala do
        // agente, o resto é ferramenta. Mandar os três para `ToolCall` apagava a conversa.
        //
        // 🚨 MEDIDO AO VIVO (10-ago-2026): `item/started` e `item/completed` chegam para o MESMO
        // item, e eu registrava os dois — a trama saiu com o prompt dele duplicado (seq 48 e 49)
        // e a resposta do agente duas vezes, a primeira VAZIA (seq 52 sem texto, 53 com). Numa
        // tela de conversa isso é a pergunta aparecendo duas vezes.
        //
        // Fala só existe quando termina: no `started` o texto ainda não chegou. Ferramenta é o
        // contrário — o valor dela é aparecer ENQUANTO roda, senão um comando de 40s não dá sinal
        // nenhum até acabar. Daí a assimetria.
        "item/started" => match item_type(p).as_deref() {
            Some("userMessage") | Some("agentMessage") => return None,
            _ => Kind::ToolCall,
        },
        "item/completed" => match item_type(p).as_deref() {
            Some("userMessage") => Kind::UserPrompt,
            Some("agentMessage") => Kind::AgentMessage,
            // A ferramenta já entrou na trilha no `started`. Repetir a mesma linha ao terminar só
            // dobra o ruído; só vale registrar de novo se o fim trouxe conteúdo (a saída).
            _ => {
                if item_text(p.get("item")?).is_none() {
                    return None;
                }
                Kind::ToolResult
            }
        },
        "error" => Kind::Error,
        "thread/status/changed" => {
            // `ThreadActiveFlag` é enum do protocolo: waitingOnApproval | waitingOnUserInput.
            // Nada de `strings.Contains(line, "───────")`.
            let st = p.get("status");
            let flags: Vec<&str> = st
                .and_then(|s| s.get("activeFlags"))
                .and_then(|f| f.as_array())
                .map(|a| a.iter().filter_map(|x| x.as_str()).collect())
                .unwrap_or_default();
            if flags.contains(&"waitingOnApproval") {
                Kind::AwaitingApproval
            } else if flags.contains(&"waitingOnUserInput") {
                Kind::AwaitingInput
            } else if st.and_then(|s| s.get("type")).and_then(|t| t.as_str()) == Some("idle") {
                Kind::Idle
            } else {
                return None; // transição sem informação operacional: não polui a trama
            }
        }
        _ => return None,
    };
    let mut e = AgentEvent::new(lane, kind, Confidence::Exact);
    e.session = thread_id(p);
    e.turn = turn_id(p);
    e.diff = s(p, "diff");
    match kind {
        // O pedaço vem cru em `delta`. Quem monta a mensagem é o runtime; aqui só se traduz.
        Kind::Delta => {
            e.tool = s(p, "itemId");
            e.text = s(p, "delta");
        }
        Kind::ToolCall | Kind::ToolResult | Kind::AgentMessage | Kind::UserPrompt => {
            let item = p.get("item");
            e.tool = item_type(p);
            // O que foi DITO — pelo agente ou pelo operador. Sem isso não há como provar que uma
            // sessão retomada voltou com contexto. Formas variam por versão; leitor tolerante.
            if let Some(t) = item.and_then(item_text) {
                e = e.with_text(t);
            }
        }
        _ => {}
    }
    Some(e)
}

/// `item.type` — quem diz se aquilo é fala do operador, fala do agente ou ferramenta.
fn item_type(p: &serde_json::Value) -> Option<String> {
    p.get("item")
        .and_then(|i| i.get("type"))
        .and_then(|t| t.as_str())
        .map(str::to_string)
}

/// O texto de um `item`, nas três formas que o protocolo já usou.
///
/// MEDIDO: `userMessage` traz `content: [{type:"text", text:"…"}]`; outras formas trazem `text`
/// direto. Ler só uma delas apagaria metade da conversa — e apagaria em silêncio.
fn item_text(i: &serde_json::Value) -> Option<String> {
    if let Some(t) = i.get("text").and_then(|t| t.as_str()) {
        return Some(t.to_string());
    }
    if let Some(m) = i.get("message").and_then(|m| m.as_str()) {
        return Some(m.to_string());
    }
    // `content` é uma LISTA de blocos: juntar todos, não só o primeiro.
    let blocos: Vec<&str> = i
        .get("content")?
        .as_array()?
        .iter()
        .filter_map(|b| b.get("text").and_then(|t| t.as_str()))
        .collect();
    if blocos.is_empty() {
        return None;
    }
    Some(blocos.join("\n"))
}

/// A resposta que o Codex espera para CADA família de aprovação.
///
/// 🚨 MEDIDO NA MARRA (09-ago-2026): respondi `{"decision":"approved"}` a um
/// `item/fileChange/requestApproval`, o log disse "aprovado", **e o arquivo não mudou**.
/// O enum daquela família é `accept`. Valor inválido é aceito em silêncio pelo transporte e
/// ignorado pelo agente — ou seja, um "aprovado" que não aprova. Só peguei conferindo o EFEITO.
pub fn codex_approval_reply(method: &str, allow: bool) -> serde_json::Value {
    let decision = match (method, allow) {
        // FileChangeApprovalDecision / CommandExecutionApprovalDecision
        ("item/fileChange/requestApproval", true)
        | ("item/commandExecution/requestApproval", true) => "accept",
        ("item/fileChange/requestApproval", false)
        | ("item/commandExecution/requestApproval", false) => "decline",
        // ReviewDecision — enum DIFERENTE, mesmas palavras não servem
        (_, true) => "approved",
        (_, false) => "denied",
    };
    serde_json::json!({ "decision": decision })
}

pub const FIXTURE_ACP: &str =
    "../../docs/superpowers/fixtures/2026-08-10-acp-censo-modo-default.jsonl";

impl ApprovalKind {
    /// O ACP declara `toolCall.kind` — `edit` é reversível por git, `execute` não é. A
    /// distinção não é cosmética: ela muda o rótulo do botão.
    pub fn from_acp_kind(kind: &str) -> Self {
        match kind {
            "edit" => ApprovalKind::Patch,
            "execute" => ApprovalKind::Command,
            _ => ApprovalKind::Other,
        }
    }
}

/// O pedido de permissão do ACP → o evento que a tela de aprovação consome.
///
/// O diff vem PRONTO em `content[{type:"diff", oldText, newText}]`. No `codex.rs` isso foi
/// garimpado de campos não documentados; aqui é campo tipado e não se calcula nada.
pub fn from_acp_permission(lane: &str, id: &str, params: &serde_json::Value) -> AgentEvent {
    let kind = params
        .pointer("/toolCall/kind")
        .and_then(|x| x.as_str())
        .unwrap_or("");
    let titulo = params
        .pointer("/toolCall/title")
        .and_then(|x| x.as_str())
        .unwrap_or("permissao");

    let mut e = AgentEvent::new(lane, Kind::AwaitingApproval, Confidence::Exact).with_text(titulo);
    e.approval_id = Some(id.to_string());
    e.approval_method = Some("session/request_permission".into());
    e.approval_kind = Some(ApprovalKind::from_acp_kind(kind));

    if let Some(cs) = params
        .pointer("/toolCall/content")
        .and_then(|x| x.as_array())
    {
        for c in cs {
            if c.get("type").and_then(|x| x.as_str()) == Some("diff") {
                let p = c.get("path").and_then(|x| x.as_str()).unwrap_or("");
                let velho = c.get("oldText").and_then(|x| x.as_str()).unwrap_or("");
                let novo = c.get("newText").and_then(|x| x.as_str()).unwrap_or("");
                e.diff = Some(format!("--- {p}\n+++ {p}\n-{velho}\n+{novo}"));
                break;
            }
        }
    }
    e
}

/// Escolhe a opção pelo `kind` DECLARADO. `options[0]` foi medido como `reject_once`: escolher
/// por posição nega tudo, e a tela reporta sucesso.
pub fn acp_option_id(params: &serde_json::Value, allow: bool) -> Option<String> {
    let ops = params.get("options")?.as_array()?;
    let procura = |k: &str| {
        ops.iter()
            .find(|o| o.get("kind").and_then(|x| x.as_str()) == Some(k))
            .and_then(|o| o.get("optionId"))
            .and_then(|x| x.as_str())
            .map(str::to_string)
    };
    if allow {
        procura("allow_always").or_else(|| procura("allow_once"))
    } else {
        procura("reject_once").or_else(|| procura("reject_always"))
    }
}

/// Traduz uma `session/update` do ACP.
///
/// `None` significa **reconhecido e deliberadamente não persistido** — nunca "não entendi".
/// O que não se entende vira `Kind::Unknown`, porque o vocabulário cresce a cada versão e um
/// evento novo tem de aparecer no board, não sumir.
pub fn from_acp_update(lane: &str, u: &serde_json::Value) -> Option<AgentEvent> {
    let variante = u
        .get("sessionUpdate")
        .and_then(|x| x.as_str())
        .unwrap_or("");
    let texto = |campo: &str| -> String {
        u.pointer(&format!("/{campo}/text"))
            .and_then(|x| x.as_str())
            .unwrap_or_default()
            .to_string()
    };
    match variante {
        // Deltas de fala e de pensamento coalescem em RAM (`Trama::acumular_delta`) e não
        // viram linha na trama: 30% do fluxo do ACP, e persistir cada pedaço encheria o
        // arquivo de fragmentos que ninguém lê.
        "agent_message_chunk" | "agent_thought_chunk" => None,
        "user_message_chunk" => Some(
            AgentEvent::new(lane, Kind::UserPrompt, Confidence::Exact).with_text(texto("content")),
        ),
        // Abre `pending`. Quem fecha é `tool_call_update` com `status: completed`.
        "tool_call" => {
            let mut e = AgentEvent::new(lane, Kind::ToolCall, Confidence::Exact).with_text(
                u.get("title")
                    .and_then(|x| x.as_str())
                    .unwrap_or("")
                    .to_string(),
            );
            e.tool = u.get("kind").and_then(|x| x.as_str()).map(str::to_string);
            Some(e)
        }
        "tool_call_update" => {
            // 🚨 5 mensagens por ferramenta, medido (35 para 7). Título refina, `content`
            // chega, e SÓ ENTÃO vem `status: completed` com `rawOutput`. Persistir todas
            // multiplicaria a trama por 2,5 sem acrescentar um fato.
            if u.get("status").and_then(|x| x.as_str()) != Some("completed") {
                return None;
            }
            let saida = u
                .get("rawOutput")
                .map(|x| {
                    x.as_str()
                        .map(str::to_string)
                        .unwrap_or_else(|| x.to_string())
                })
                .unwrap_or_default();
            let mut e = AgentEvent::new(lane, Kind::ToolResult, Confidence::Exact).with_text(saida);
            e.tool = u
                .pointer("/_meta/claudeCode/toolName")
                .and_then(|x| x.as_str())
                .map(str::to_string);
            Some(e)
        }
        "usage_update" => {
            let usados = u.get("used").and_then(|x| x.as_u64()).unwrap_or(0);
            let teto = u.get("size").and_then(|x| x.as_u64()).unwrap_or(0);
            let custo = u
                .pointer("/cost/amount")
                .and_then(|x| x.as_f64())
                .unwrap_or(0.0);
            Some(
                AgentEvent::new(lane, Kind::Usage, Confidence::Exact)
                    .detail(format!("contexto {usados}/{teto} · USD {custo:.4}")),
            )
        }
        // Registrados sem UI: não há tela de plano, e prometer uma aqui seria escopo que o
        // spec explicitamente não pega.
        "plan" | "plan_update" | "plan_removed" => None,
        "available_commands_update"
        | "config_option_update"
        | "current_mode_update"
        | "session_info_update" => None,
        outro => Some(
            AgentEvent::new(lane, Kind::Unknown, Confidence::Exact)
                .detail(format!("session/update desconhecida: {outro}")),
        ),
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn cada_familia_de_aprovacao_usa_o_seu_enum() {
        // O teste que existe por causa do bug acima.
        assert_eq!(
            codex_approval_reply("item/fileChange/requestApproval", true)["decision"],
            "accept"
        );
        assert_eq!(
            codex_approval_reply("item/commandExecution/requestApproval", true)["decision"],
            "accept"
        );
        assert_eq!(
            codex_approval_reply("execCommandApproval", true)["decision"],
            "approved"
        );
        assert_eq!(
            codex_approval_reply("applyPatchApproval", true)["decision"],
            "approved"
        );
        assert_eq!(
            codex_approval_reply("item/fileChange/requestApproval", false)["decision"],
            "decline"
        );
    }

    #[test]
    fn as_duas_fontes_caem_no_mesmo_estado() {
        // Codex diz por enum de status; Claude diz por notification_type. Mesma verdade.
        let cx = from_codex_notification(
            "codex-1",
            "thread/status/changed",
            &serde_json::json!({"threadId":"t1","status":{"type":"active","activeFlags":["waitingOnApproval"]}}),
        )
        .unwrap();
        let cl = from_claude_hook(
            "claude-1",
            &serde_json::json!({"hook_event_name":"Notification","notification_type":"permission_prompt","session_id":"s1"}),
        );
        assert_eq!(cx.kind, Kind::AwaitingApproval);
        assert_eq!(cl.kind, Kind::AwaitingApproval);
        assert_eq!(cx.confidence, Confidence::Exact);
    }

    #[test]
    fn evento_desconhecido_nunca_derruba_nada() {
        let e = from_claude_hook(
            "claude-1",
            &serde_json::json!({"hook_event_name":"AlgoNovoEm2027"}),
        );
        assert_eq!(e.kind, Kind::Unknown);
        assert!(e.detail.as_deref().unwrap().contains("AlgoNovoEm2027"));
        // E uma notificação do codex sem valor operacional é descartada, não vira ruído.
        assert!(
            from_codex_notification("codex-1", "account/updated", &serde_json::json!({})).is_none()
        );
    }

    #[test]
    fn o_id_da_thread_e_lido_nas_duas_formas() {
        // O mesmo protocolo usa `threadId` num método e `thread.id` noutro. Ler só um fazia o
        // supervisor nunca aprender o id — e o turno morria em silêncio.
        assert_eq!(
            thread_id(&serde_json::json!({"threadId":"a"})).as_deref(),
            Some("a")
        );
        assert_eq!(
            thread_id(&serde_json::json!({"thread":{"id":"b"}})).as_deref(),
            Some("b")
        );
        assert_eq!(
            thread_id(&serde_json::json!({"thread":{"sessionId":"c"}})).as_deref(),
            Some("c")
        );
        assert_eq!(thread_id(&serde_json::json!({"nada":1})), None);
    }

    #[test]
    fn o_diff_chega_como_dado() {
        let e = from_codex_notification(
            "codex-1",
            "turn/diff/updated",
            &serde_json::json!({"threadId":"t","turnId":"u","diff":"--- a\n+++ b\n"}),
        )
        .unwrap();
        assert_eq!(e.kind, Kind::DiffProposed);
        assert!(e.diff.as_deref().unwrap().starts_with("--- a"));
    }

    // ─── O que o censo de 10-ago-2026 obrigou a existir ─────────────────────────────────────

    #[test]
    fn o_delta_e_traduzido_em_vez_de_descartado() {
        // 🚨 A regressão que estes testes guardam: num único turno chegam **70**
        // `item/agentMessage/delta`, e TODOS eram descartados — método desconhecido devolvia
        // `None`. A fonte "exact" da Frota via 7 de 107 eventos.
        let p = serde_json::json!({
            "threadId": "th-1", "turnId": "tu-1",
            "itemId": "msg_0fee", "delta": "Vou"
        });
        let e = from_codex_notification("codex-1", "item/agentMessage/delta", &p).unwrap();
        assert_eq!(e.kind, Kind::Delta);
        assert_eq!(e.text.as_deref(), Some("Vou"));
        assert_eq!(
            e.tool.as_deref(),
            Some("msg_0fee"),
            "o itemId agrupa os pedaços de UMA mensagem"
        );
    }

    #[test]
    fn item_type_separa_quem_falou() {
        // Mandar os três para `ToolCall` apagava a conversa: não dava para saber o que o
        // operador pediu nem o que o agente respondeu.
        let faz = |metodo: &str, tipo: &str| {
            let p = serde_json::json!({
                "threadId": "th-1", "turnId": "tu-1",
                "item": { "type": tipo, "text": "oi" }
            });
            from_codex_notification("codex-1", metodo, &p).map(|e| e.kind)
        };
        assert_eq!(faz("item/completed", "userMessage"), Some(Kind::UserPrompt));
        assert_eq!(
            faz("item/completed", "agentMessage"),
            Some(Kind::AgentMessage)
        );
        assert_eq!(
            faz("item/started", "commandExecution"),
            Some(Kind::ToolCall)
        );
    }

    #[test]
    fn a_fala_entra_UMA_vez_e_a_ferramenta_aparece_enquanto_roda() {
        // 🚨 MEDIDO AO VIVO: `item/started` e `item/completed` chegam para o MESMO item. Eu
        // registrava os dois, e a trama saiu com o prompt do operador DUPLICADO (seq 48 e 49) e a
        // resposta do agente duas vezes — a primeira vazia, porque no `started` o texto ainda não
        // existe. Numa tela de conversa isso é a pergunta aparecendo duas vezes.
        let item = |tipo: &str, texto: Option<&str>| {
            let mut i = serde_json::json!({ "type": tipo });
            if let Some(t) = texto {
                i["text"] = serde_json::json!(t);
            }
            serde_json::json!({ "threadId": "th-1", "item": i })
        };

        // Fala: só quando termina.
        assert!(
            from_codex_notification("c", "item/started", &item("agentMessage", None)).is_none(),
            "no started a fala ainda não existe — registrá-la cria uma linha vazia"
        );
        assert!(
            from_codex_notification("c", "item/started", &item("userMessage", Some("oi")))
                .is_none()
        );
        assert_eq!(
            from_codex_notification(
                "c",
                "item/completed",
                &item("agentMessage", Some("resposta"))
            )
            .unwrap()
            .text
            .as_deref(),
            Some("resposta")
        );

        // Ferramenta: o contrário. Aparece ao COMEÇAR, senão um comando de 40s fica sem sinal.
        assert_eq!(
            from_codex_notification("c", "item/started", &item("commandExecution", None))
                .unwrap()
                .kind,
            Kind::ToolCall
        );
        // E não se repete ao terminar, a menos que o fim traga conteúdo (a saída).
        assert!(
            from_codex_notification("c", "item/completed", &item("reasoning", None)).is_none(),
            "fim sem conteúdo é a mesma linha de novo"
        );
        assert_eq!(
            from_codex_notification(
                "c",
                "item/completed",
                &item("commandExecution", Some("exit 0"))
            )
            .unwrap()
            .kind,
            Kind::ToolResult
        );
    }

    #[test]
    fn o_texto_integro_sobrevive_e_o_resumo_e_derivado_dele() {
        // Uma tela de conversa não pode ler de um campo cortado em 240. `detail` continua curto
        // porque é o que cabe no card; `text` é a mensagem.
        let longo = format!("primeira linha\n{}", "x".repeat(900));
        let p = serde_json::json!({
            "threadId": "th-1", "item": { "type": "agentMessage", "text": longo }
        });
        let e = from_codex_notification("codex-1", "item/completed", &p).unwrap();
        assert_eq!(
            e.text.as_deref().map(str::len),
            Some(longo.len()),
            "o texto NÃO é truncado"
        );
        assert_eq!(
            e.detail.as_deref(),
            Some("primeira linha"),
            "o card cita a primeira linha"
        );
    }

    #[test]
    fn content_com_varios_blocos_nao_perde_o_resto() {
        // Ler só `content[0]` apagava metade de uma resposta longa — em silêncio, que é pior.
        let p = serde_json::json!({
            "item": { "type": "agentMessage", "content": [
                {"type": "text", "text": "um"}, {"type": "text", "text": "dois"}
            ]}
        });
        let e = from_codex_notification("codex-1", "item/completed", &p).unwrap();
        assert_eq!(e.text.as_deref(), Some("um\ndois"));
    }

    #[test]
    fn o_resumo_nao_devolve_linha_vazia_nem_parte_palavra() {
        assert_eq!(
            resumir("\n\n  de verdade  \nresto"),
            "de verdade",
            "resposta que começa com linha vazia daria card em branco"
        );
        let r = resumir(&format!("{} fim", "palavra ".repeat(40)));
        assert!(
            r.ends_with('…') && !r.ends_with("pa…"),
            "não parte palavra ao meio: {r}"
        );
    }

    #[test]
    fn comando_e_patch_sao_riscos_diferentes() {
        // Aplicar patch se desfaz por git; rodar comando, não. O rótulo do botão sai daqui.
        assert_eq!(
            ApprovalKind::of("item/fileChange/requestApproval"),
            ApprovalKind::Patch
        );
        assert_eq!(ApprovalKind::of("applyPatchApproval"), ApprovalKind::Patch);
        assert_eq!(
            ApprovalKind::of("item/commandExecution/requestApproval"),
            ApprovalKind::Command
        );
        assert_eq!(
            ApprovalKind::of("execCommandApproval"),
            ApprovalKind::Command
        );
        assert_eq!(
            ApprovalKind::of("item/permissions/requestApproval"),
            ApprovalKind::Other
        );
    }

    #[test]
    fn o_id_do_turno_e_lido_nas_duas_formas() {
        // A mesma armadilha do threadId, paga de novo — e descoberta só ao tentar interromper um
        // turno vivo e ouvir "nenhum turno em curso".
        let aninhado =
            serde_json::json!({"threadId":"th","turn":{"id":"tu-7","status":"inProgress"}});
        assert_eq!(turn_id(&aninhado).as_deref(), Some("tu-7"));
        let plano = serde_json::json!({"threadId":"th","turnId":"tu-9"});
        assert_eq!(turn_id(&plano).as_deref(), Some("tu-9"));

        // E pelo caminho que importa: `turn/started` é o único evento que ABRE o turno.
        let e = from_codex_notification("c", "turn/started", &aninhado).unwrap();
        assert_eq!(e.kind, Kind::TurnStarted);
        assert_eq!(
            e.turn.as_deref(),
            Some("tu-7"),
            "sem isto o turno nasce sem alvo e não dá para interromper nem guiar"
        );
    }

    /// O REPLAY DOURADO: 70 linhas de fio REAL, capturadas com a credencial do operador numa
    /// tarefa de verdade (ler, escrever, rodar shell). Rede de regressão feita de dado medido —
    /// não de exemplo que eu inventei e que por isso concorda comigo por construção.
    #[test]
    fn replay_do_censo_acp_produz_a_trama_esperada() {
        let bruto = std::fs::read_to_string(FIXTURE_ACP)
            .expect("fixture do censo ACP — rode de dentro de crates/loomd");

        let mut fala = 0;
        let mut abriu = 0;
        let mut fechou = 0;
        let mut custo = 0;
        let mut descartados = 0;

        for l in bruto.lines().filter(|l| !l.trim().is_empty()) {
            let env: serde_json::Value = serde_json::from_str(l).unwrap();
            if env["dir"] != "\u{2190}" {
                continue; // só o que o AGENTE mandou
            }
            let m = &env["msg"];
            if m["method"] != "session/update" {
                continue;
            }
            match from_acp_update("claude-4", &m["params"]["update"]) {
                None => descartados += 1,
                Some(e) => match e.kind {
                    Kind::AgentMessage => fala += 1,
                    Kind::ToolCall => abriu += 1,
                    Kind::ToolResult => fechou += 1,
                    Kind::Usage => custo += 1,
                    _ => {}
                },
            }
        }

        // Contagens do censo, rodada 2 (modo default): 7 tool_call, 28 tool_call_update dos
        // quais 7 fecham, 14 chunks de fala, 16 usage.
        assert_eq!(abriu, 7, "toda ferramenta que abriu tem de virar ToolCall");
        assert_eq!(
            fechou, 7,
            "so `status: completed` fecha — as outras 21 sao refino"
        );
        assert_eq!(custo, 16, "usage_update entrega custo por turno de graca");
        assert_eq!(
            fala, 0,
            "chunk de fala NAO vai para a trama: coalesce em RAM"
        );
        assert_eq!(
            descartados, 37,
            "14 chunks + 21 refinos + 2 de config, medido na fixture"
        );
    }

    #[test]
    fn tool_call_update_sem_status_nao_persiste() {
        let refino = serde_json::json!({
            "sessionUpdate": "tool_call_update",
            "toolCallId": "toolu_1",
            "title": "Edit medidas.txt",
            "kind": "edit"
        });
        assert!(
            from_acp_update("claude-4", &refino).is_none(),
            "refino de titulo nao e evento — sao 5 mensagens por ferramenta, so 2 interessam"
        );
    }

    #[test]
    fn variante_desconhecida_vira_unknown_e_nao_desaparece() {
        let novo = serde_json::json!({"sessionUpdate": "coisa_que_nao_existia_ontem"});
        let e = from_acp_update("claude-4", &novo).expect("desconhecido e informacao");
        assert_eq!(e.kind, Kind::Unknown);
        assert!(e.detail.unwrap().contains("coisa_que_nao_existia_ontem"));
    }

    /// O pedido REAL, extraído da fixture. Escrever isto à mão seria escrever o que eu acho que
    /// o protocolo manda — e foi exatamente assim que eu errei o `codex.rs` duas vezes.
    fn pedido_real_da_fixture() -> serde_json::Value {
        let bruto = std::fs::read_to_string(FIXTURE_ACP).expect("fixture");
        for l in bruto.lines().filter(|l| !l.trim().is_empty()) {
            let env: serde_json::Value = serde_json::from_str(l).unwrap();
            if env["msg"]["method"] == "session/request_permission" {
                return env["msg"]["params"].clone();
            }
        }
        panic!("a fixture tem de conter request_permission — foi medido em modo default");
    }

    #[test]
    fn permissao_de_edicao_vira_patch_com_o_diff_pronto() {
        let p = pedido_real_da_fixture();
        let e = from_acp_permission("claude-4", "42", &p);
        assert_eq!(e.kind, Kind::AwaitingApproval);
        assert_eq!(e.approval_kind, Some(ApprovalKind::Patch));
        assert_eq!(e.approval_id.as_deref(), Some("42"));
        let d = e
            .diff
            .expect("o ACP entrega o diff PRONTO — nao se calcula nada aqui");
        assert!(d.contains("medidas.txt"));
        assert!(d.contains("largura = 3"));
    }

    /// 🚨 `options[0]` é `reject_once` no que foi medido. Escolher por posição NEGA TUDO —
    /// silenciosamente, e com a tela dizendo que aprovou.
    #[test]
    fn a_opcao_sai_do_kind_declarado_nunca_da_posicao() {
        let p = pedido_real_da_fixture();
        assert_eq!(
            p["options"][0]["kind"], "reject_once",
            "premissa do teste, da fixture"
        );
        assert_eq!(acp_option_id(&p, true).as_deref(), Some("allow_always"));
        assert_eq!(acp_option_id(&p, false).as_deref(), Some("reject"));
    }
}
