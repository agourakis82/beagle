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
    #[serde(skip_serializing_if = "Option::is_none")]
    pub detail: Option<String>,
    /// Unified diff, quando o agente propõe mudança. Dado, não pixel.
    #[serde(skip_serializing_if = "Option::is_none")]
    pub diff: Option<String>,
    /// Id da requisição de aprovação pendente, para o operador responder depois.
    #[serde(skip_serializing_if = "Option::is_none")]
    pub approval_id: Option<String>,
    /// O método que pediu a aprovação — decide QUAL enum a resposta precisa usar.
    #[serde(skip_serializing_if = "Option::is_none")]
    pub approval_method: Option<String>,
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
            diff: None,
            approval_id: None,
            approval_method: None,
        }
    }
    pub fn detail(mut self, d: impl Into<String>) -> Self {
        self.detail = Some(d.into());
        self
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
        "item/started" | "item/completed" => Kind::ToolCall,
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
    if kind == Kind::ToolCall {
        let item = p.get("item");
        e.tool = item.and_then(|i| i.get("type")).and_then(|t| t.as_str()).map(str::to_string);
        // O que o agente DISSE é a evidência que o card cita — e sem ela não há como provar que
        // uma sessão retomada voltou com contexto. Formas variam por versão; leitor tolerante.
        e.detail = item.and_then(|i| {
            i.get("text")
                .and_then(|t| t.as_str())
                .or_else(|| i.get("message").and_then(|m| m.as_str()))
                .or_else(|| {
                    i.get("content")
                        .and_then(|c| c.as_array())
                        .and_then(|a| a.first())
                        .and_then(|f| f.get("text"))
                        .and_then(|t| t.as_str())
                })
        })
        .map(|t| t.chars().take(240).collect());
    }
    Some(e)
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
}
