//! A trama: diário append-only de tudo que a frota fez, e o estado DERIVADO dele.
//!
//! Duas escolhas que carregam o peso:
//!
//! 1. **O estado nunca é gerenciado à mão.** Ele é uma redução sobre os eventos, no modelo da
//!    Linear. Um campo `state` que alguém escreve à mão diverge do que aconteceu; uma redução
//!    não pode divergir da sua própria entrada.
//! 2. **Persistir a SESSÃO, não os pixels.** O tmux persiste tela: depois de um restart do pod
//!    ele te devolve um scrollback morto. Aqui o diário guarda o que aconteceu, e a sessão do
//!    agente é retomada pelo id no store do próprio CLI.
use crate::event::{AgentEvent, Confidence, Kind};
use serde::Serialize;
use std::collections::HashMap;
use std::io::Write;
use std::sync::Mutex;

/// O que o operador precisa saber de uma lane, tudo derivado da trama.
#[derive(Debug, Clone, Serialize)]
pub struct LaneState {
    pub lane: String,
    pub kind: Kind,
    pub confidence: Confidence,
    pub observed_at_ms: u64,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub detail: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub session: Option<String>,
    /// Aprovação pendente: o id e o método (que decide o enum da resposta).
    #[serde(skip_serializing_if = "Option::is_none")]
    pub pending_approval: Option<(String, String)>,
    /// Último diff proposto — respondido da trama, sem grep em rio ANSI.
    #[serde(skip_serializing_if = "Option::is_none")]
    pub last_diff: Option<String>,
    pub turns: u32,
}

pub struct Trama {
    inner: Mutex<Inner>,
    path: std::path::PathBuf,
}

struct Inner {
    seq: u64,
    events: Vec<AgentEvent>,
    lanes: HashMap<String, LaneState>,
    file: Option<std::fs::File>,
}

impl Trama {
    pub fn open(path: impl Into<std::path::PathBuf>) -> Self {
        let path = path.into();
        if let Some(p) = path.parent() {
            let _ = std::fs::create_dir_all(p);
        }
        let file = std::fs::OpenOptions::new().create(true).append(true).open(&path).ok();
        Self {
            inner: Mutex::new(Inner { seq: 0, events: Vec::new(), lanes: HashMap::new(), file }),
            path,
        }
    }

    pub fn path(&self) -> &std::path::Path {
        &self.path
    }

    /// Registra um evento e reduz o estado da lane. Nunca falha: se o disco recusar, o evento
    /// ainda vale em memória — perder a supervisão porque o log encheu seria trocar o ouro pelo
    /// recibo.
    pub fn append(&self, mut e: AgentEvent) -> u64 {
        let mut g = self.inner.lock().unwrap();
        g.seq += 1;
        e.seq = g.seq;
        if let Some(f) = g.file.as_mut() {
            if let Ok(line) = serde_json::to_string(&e) {
                let _ = writeln!(f, "{line}");
            }
        }
        reduce(&mut g.lanes, &e);
        let seq = e.seq;
        g.events.push(e);
        // Limite de memória: o disco é a verdade longa; a RAM é só a janela de leitura.
        if g.events.len() > 20_000 {
            g.events.drain(0..5_000);
        }
        seq
    }

    pub fn state(&self) -> Vec<LaneState> {
        let g = self.inner.lock().unwrap();
        let mut v: Vec<_> = g.lanes.values().cloned().collect();
        v.sort_by(|a, b| urgency(a.kind).cmp(&urgency(b.kind)).then(a.lane.cmp(&b.lane)));
        v
    }

    pub fn since(&self, since: u64, lane: Option<&str>) -> Vec<AgentEvent> {
        let g = self.inner.lock().unwrap();
        g.events
            .iter()
            .filter(|e| e.seq > since && lane.map_or(true, |l| e.lane == l))
            .cloned()
            .collect()
    }

    /// A aprovação pendente de uma lane, se houver — id e método.
    pub fn pending(&self, lane: &str) -> Option<(String, String)> {
        let g = self.inner.lock().unwrap();
        g.lanes.get(lane).and_then(|s| s.pending_approval.clone())
    }
}

/// Quem precisa de você primeiro. Ordena o board sem que ninguém escreva prioridade à mão.
fn urgency(k: Kind) -> u8 {
    match k {
        Kind::AwaitingApproval | Kind::AwaitingInput => 0,
        Kind::Error => 1,
        Kind::TurnStarted | Kind::ToolCall | Kind::ToolResult | Kind::DiffProposed => 2,
        Kind::TurnEnded | Kind::Idle => 3,
        Kind::SessionStarted => 4,
        Kind::SessionEnded => 5,
        Kind::ApprovalAnswered | Kind::Unknown => 6,
    }
}

/// A redução. Toda a máquina de estado da frota mora aqui, e são vinte linhas — porque o
/// protocolo já diz o estado. A versão que raspava tela precisava de um classificador inteiro
/// com regex por família de CLI, e ainda errava.
fn reduce(lanes: &mut HashMap<String, LaneState>, e: &AgentEvent) {
    let st = lanes.entry(e.lane.clone()).or_insert_with(|| LaneState {
        lane: e.lane.clone(),
        kind: Kind::Unknown,
        confidence: e.confidence,
        observed_at_ms: e.ts_ms,
        detail: None,
        session: None,
        pending_approval: None,
        last_diff: None,
        turns: 0,
    });

    st.observed_at_ms = e.ts_ms;
    st.confidence = e.confidence;
    if e.session.is_some() {
        st.session = e.session.clone();
    }
    if let Some(d) = &e.diff {
        st.last_diff = Some(d.clone());
    }
    if e.kind == Kind::TurnStarted {
        st.turns += 1;
    }

    match e.kind {
        Kind::AwaitingApproval => {
            if let (Some(id), Some(m)) = (&e.approval_id, &e.approval_method) {
                st.pending_approval = Some((id.clone(), m.clone()));
            }
        }
        // Qualquer coisa que signifique "o turno andou" limpa a pendência: uma aprovação que
        // já foi respondida (por aqui ou pelo próprio terminal dele) não pode ficar no board
        // pedindo atenção que ninguém deve.
        Kind::ApprovalAnswered | Kind::TurnEnded | Kind::Idle | Kind::SessionEnded => {
            st.pending_approval = None;
        }
        _ => {}
    }

    // `Unknown` NÃO sobrescreve um estado conhecido: um evento que ainda não sabemos ler não
    // deve apagar o que sabemos. Ele fica na trama; só não muda o veredicto.
    if e.kind != Kind::Unknown {
        st.kind = e.kind;
        st.detail = e.detail.clone();
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::event::AgentEvent;

    fn ev(lane: &str, k: Kind) -> AgentEvent {
        AgentEvent::new(lane, k, Confidence::Exact)
    }

    #[test]
    fn o_estado_e_derivado_nunca_escrito() {
        let t = Trama::open(std::env::temp_dir().join("loomd-test-1.jsonl"));
        t.append(ev("codex-1", Kind::TurnStarted));
        t.append(ev("codex-1", Kind::ToolCall));
        let s = &t.state()[0];
        assert_eq!(s.kind, Kind::ToolCall);
        assert_eq!(s.turns, 1);
    }

    #[test]
    fn quem_espera_por_voce_vem_primeiro() {
        let t = Trama::open(std::env::temp_dir().join("loomd-test-2.jsonl"));
        t.append(ev("codex-1", Kind::Idle));
        t.append(ev("claude-1", Kind::ToolCall));
        t.append(ev("kimi-cli1", Kind::AwaitingApproval));
        assert_eq!(t.state()[0].lane, "kimi-cli1");
    }

    #[test]
    fn evento_desconhecido_nao_apaga_o_que_sabemos() {
        let t = Trama::open(std::env::temp_dir().join("loomd-test-3.jsonl"));
        t.append(ev("codex-1", Kind::AwaitingApproval));
        t.append(ev("codex-1", Kind::Unknown));
        // Continua pedindo atenção: um evento ilegível não é motivo para o board relaxar.
        assert_eq!(t.state()[0].kind, Kind::AwaitingApproval);
    }

    #[test]
    fn a_pendencia_some_quando_o_turno_anda() {
        let t = Trama::open(std::env::temp_dir().join("loomd-test-4.jsonl"));
        let mut a = ev("codex-1", Kind::AwaitingApproval);
        a.approval_id = Some("7".into());
        a.approval_method = Some("item/fileChange/requestApproval".into());
        t.append(a);
        assert!(t.pending("codex-1").is_some());
        // Ele pode ter aprovado no próprio terminal — o board não pode ficar pedindo.
        t.append(ev("codex-1", Kind::TurnEnded));
        assert!(t.pending("codex-1").is_none());
    }

    #[test]
    fn o_ultimo_diff_vem_da_trama_nao_de_grep() {
        let t = Trama::open(std::env::temp_dir().join("loomd-test-5.jsonl"));
        let mut d = ev("codex-1", Kind::DiffProposed);
        d.diff = Some("--- a\n+++ b\n".into());
        t.append(d);
        t.append(ev("codex-1", Kind::TurnEnded));
        assert!(t.state()[0].last_diff.as_deref().unwrap().contains("+++ b"));
    }

    #[test]
    fn since_e_um_cursor_de_leitura() {
        let t = Trama::open(std::env::temp_dir().join("loomd-test-6.jsonl"));
        t.append(ev("a", Kind::Idle));
        let s2 = t.append(ev("b", Kind::Idle));
        t.append(ev("a", Kind::Idle));
        assert_eq!(t.since(s2, None).len(), 1);
        assert_eq!(t.since(0, Some("a")).len(), 2);
    }
}
