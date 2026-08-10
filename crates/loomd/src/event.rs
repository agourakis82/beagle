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
    let linha = t.lines().map(str::trim).find(|l| !l.is_empty()).unwrap_or("");
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
        .or_else(|| v.get("thread").and_then(|t| t.get("id")).and_then(|x| x.as_str()))
        .or_else(|| v.get("thread").and_then(|t| t.get("sessionId")).and_then(|x| x.as_str()))
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

pub fn from_codex_notification(lane: &str, method: &str, p: &serde_json::Value) -> Option<AgentEvent> {
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
    e.turn = s(p, "turnId");
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
        assert_eq!(codex_approval_reply("execCommandApproval", true)["decision"], "approved");
        assert_eq!(codex_approval_reply("applyPatchApproval", true)["decision"], "approved");
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
        let e = from_claude_hook("claude-1", &serde_json::json!({"hook_event_name":"AlgoNovoEm2027"}));
        assert_eq!(e.kind, Kind::Unknown);
        assert!(e.detail.as_deref().unwrap().contains("AlgoNovoEm2027"));
        // E uma notificação do codex sem valor operacional é descartada, não vira ruído.
        assert!(from_codex_notification("codex-1", "account/updated", &serde_json::json!({})).is_none());
    }

    #[test]
    fn o_id_da_thread_e_lido_nas_duas_formas() {
        // O mesmo protocolo usa `threadId` num método e `thread.id` noutro. Ler só um fazia o
        // supervisor nunca aprender o id — e o turno morria em silêncio.
        assert_eq!(thread_id(&serde_json::json!({"threadId":"a"})).as_deref(), Some("a"));
        assert_eq!(thread_id(&serde_json::json!({"thread":{"id":"b"}})).as_deref(), Some("b"));
        assert_eq!(thread_id(&serde_json::json!({"thread":{"sessionId":"c"}})).as_deref(), Some("c"));
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
        assert_eq!(e.tool.as_deref(), Some("msg_0fee"), "o itemId agrupa os pedaços de UMA mensagem");
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
        assert_eq!(faz("item/completed", "agentMessage"), Some(Kind::AgentMessage));
        assert_eq!(faz("item/started", "commandExecution"), Some(Kind::ToolCall));
    }

    #[test]
    fn a_fala_entra_UMA_vez_e_a_ferramenta_aparece_enquanto_roda() {
        // 🚨 MEDIDO AO VIVO: `item/started` e `item/completed` chegam para o MESMO item. Eu
        // registrava os dois, e a trama saiu com o prompt do operador DUPLICADO (seq 48 e 49) e a
        // resposta do agente duas vezes — a primeira vazia, porque no `started` o texto ainda não
        // existe. Numa tela de conversa isso é a pergunta aparecendo duas vezes.
        let item = |tipo: &str, texto: Option<&str>| {
            let mut i = serde_json::json!({ "type": tipo });
            if let Some(t) = texto { i["text"] = serde_json::json!(t); }
            serde_json::json!({ "threadId": "th-1", "item": i })
        };

        // Fala: só quando termina.
        assert!(from_codex_notification("c", "item/started", &item("agentMessage", None)).is_none(),
            "no started a fala ainda não existe — registrá-la cria uma linha vazia");
        assert!(from_codex_notification("c", "item/started", &item("userMessage", Some("oi"))).is_none());
        assert_eq!(
            from_codex_notification("c", "item/completed", &item("agentMessage", Some("resposta"))).unwrap().text.as_deref(),
            Some("resposta"));

        // Ferramenta: o contrário. Aparece ao COMEÇAR, senão um comando de 40s fica sem sinal.
        assert_eq!(
            from_codex_notification("c", "item/started", &item("commandExecution", None)).unwrap().kind,
            Kind::ToolCall);
        // E não se repete ao terminar, a menos que o fim traga conteúdo (a saída).
        assert!(from_codex_notification("c", "item/completed", &item("reasoning", None)).is_none(),
            "fim sem conteúdo é a mesma linha de novo");
        assert_eq!(
            from_codex_notification("c", "item/completed", &item("commandExecution", Some("exit 0"))).unwrap().kind,
            Kind::ToolResult);
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
        assert_eq!(e.text.as_deref().map(str::len), Some(longo.len()), "o texto NÃO é truncado");
        assert_eq!(e.detail.as_deref(), Some("primeira linha"), "o card cita a primeira linha");
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
        assert_eq!(resumir("\n\n  de verdade  \nresto"), "de verdade",
            "resposta que começa com linha vazia daria card em branco");
        let r = resumir(&format!("{} fim", "palavra ".repeat(40)));
        assert!(r.ends_with('…') && !r.ends_with("pa…"), "não parte palavra ao meio: {r}");
    }

    #[test]
    fn comando_e_patch_sao_riscos_diferentes() {
        // Aplicar patch se desfaz por git; rodar comando, não. O rótulo do botão sai daqui.
        assert_eq!(ApprovalKind::of("item/fileChange/requestApproval"), ApprovalKind::Patch);
        assert_eq!(ApprovalKind::of("applyPatchApproval"), ApprovalKind::Patch);
        assert_eq!(ApprovalKind::of("item/commandExecution/requestApproval"), ApprovalKind::Command);
        assert_eq!(ApprovalKind::of("execCommandApproval"), ApprovalKind::Command);
        assert_eq!(ApprovalKind::of("item/permissions/requestApproval"), ApprovalKind::Other);
    }
}
