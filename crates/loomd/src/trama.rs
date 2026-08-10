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
//! 3. **O diário é a única fonte que atravessa reinícios.** `open` RELÊ o rabo do jsonl: daí
//!    saem o `seq` (que precisa ser monotônico para o `?since=` valer), o estado das lanes e o
//!    id da thread de cada lane. Nenhum arquivo de estado paralelo — um segundo arquivo é uma
//!    segunda verdade, e as duas divergem.
use crate::event::{AgentEvent, Confidence, Kind};
use serde::Serialize;
use std::collections::{HashMap, VecDeque};
use std::io::{BufRead, BufReader, Seek, SeekFrom, Write};
use std::sync::Mutex;

/// Quanto do FIM do jsonl é relido na subida.
///
/// Com esta correção o maior `seq` passa a ser sempre a ÚLTIMA linha do arquivo, então a janela
/// só precisa cobrir o rabo; ela existe para que a subida não seja O(tamanho do diário) — o
/// diário é append-only e feito para durar meses.
/// O único caso em que a janela poderia subestimar é um jsonl LEGADO (escrito pela versão que
/// zerava o seq) maior que ela; o medido em 09-ago-2026 tem 4671 bytes, 0,4% da janela.
const JANELA_RELEITURA: u64 = 1 << 20;

/// Teto de eventos que a releitura traz de volta para a RAM. É uma JANELA DE LEITURA para o
/// `?since=`, não o histórico: o histórico é o arquivo. Menor que o teto de runtime (20k) de
/// propósito — quem acabou de subir não tem cliente com cursor antigo pendurado.
const TETO_RELEITURA: usize = 5_000;

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
    /// Comando ou patch, quando há aprovação pendente. Muda o rótulo do botão porque muda o risco.
    #[serde(skip_serializing_if = "Option::is_none")]
    pub pending_kind: Option<crate::event::ApprovalKind>,
    /// A mensagem SENDO ESCRITA agora, montada dos deltas. **Não está na trama** — é estado em
    /// voo, e some quando a mensagem completa chega. É isto que faz a tela mostrar o texto
    /// chegando sem enterrar o diário em 70 linhas por turno.
    #[serde(skip_serializing_if = "Option::is_none")]
    pub streaming_text: Option<String>,
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
    /// Abre o diário RETOMANDO o que já está nele.
    ///
    /// 🚨 MEDIDO (09-ago-2026, `/workspace/.loomd/trama.jsonl`): a versão anterior abria em
    /// `append` (certo, não truncava) mas zerava o `seq` e não relia nada. O arquivo tinha
    /// `seq = [1..8, 1..8, 1..8]` — três subidas, chaves duplicadas, e `?since=8` NUNCA mais
    /// entregava nada porque todo evento novo nascia com seq ≤ 8. Um cursor que só funciona
    /// enquanto o daemon não morre não é um cursor.
    pub fn open(path: impl Into<std::path::PathBuf>) -> Self {
        let path = path.into();
        if let Some(p) = path.parent() {
            let _ = std::fs::create_dir_all(p);
        }
        let (seq, events, lanes) = rehidratar(&path);
        eprintln!(
            "[loomd] trama {}: {} eventos relidos, {} lanes, seq retomado em {}",
            path.display(),
            events.len(),
            lanes.len(),
            seq
        );
        let file = std::fs::OpenOptions::new().create(true).append(true).open(&path).ok();
        Self { inner: Mutex::new(Inner { seq, events, lanes, file }), path }
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

    /// Junta mais um pedaço da mensagem em voo.
    ///
    /// Vive aqui, e não em `codex.rs`, porque o estado da lane é UMA coisa só: dois lugares
    /// guardando pedaço de verdade é como nasce card que discorda de si mesmo.
    pub fn acumular_delta(&self, lane: &str, pedaco: &str) {
        let mut g = self.inner.lock().unwrap();
        let agora = crate::event::now_ms();
        let st = g.lanes.entry(lane.to_string()).or_insert_with(|| LaneState {
            lane: lane.to_string(),
            kind: Kind::Unknown,
            confidence: Confidence::Exact,
            observed_at_ms: agora,
            detail: None,
            session: None,
            pending_approval: None,
            pending_kind: None,
            last_diff: None,
            streaming_text: None,
            turns: 0,
        });
        st.observed_at_ms = agora;
        st.streaming_text.get_or_insert_with(String::new).push_str(pedaco);
    }

    /// O parcial cumpriu seu papel: a mensagem completa chegou à trama.
    /// Não limpar faria o próximo turno começar com o texto do anterior colado na frente.
    pub fn limpar_delta(&self, lane: &str) {
        let mut g = self.inner.lock().unwrap();
        if let Some(st) = g.lanes.get_mut(lane) {
            st.streaming_text = None;
        }
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

    /// A última sessão que a lane teve — para o Codex, o `threadId`.
    ///
    /// É por AQUI que a subida FRIA retoma a thread (`codex::CodexLane::spawn`). Não há arquivo
    /// novo guardando o id: todo evento do Codex já carrega `session`, e a redução guarda o
    /// último. O id da thread é uma CONSEQUÊNCIA do diário, como todo o resto do estado.
    pub fn session_of(&self, lane: &str) -> Option<String> {
        let g = self.inner.lock().unwrap();
        g.lanes.get(lane).and_then(|s| s.session.clone())
    }

    /// O maior `seq` já emitido. Existe para o teste poder afirmar a monotonicidade sem
    /// depender de qual evento foi o último.
    pub fn seq(&self) -> u64 {
        self.inner.lock().unwrap().seq
    }
}

/// Relê o rabo do jsonl e devolve (maior seq, janela de eventos, estado reduzido).
///
/// Três cuidados que vieram de erro real:
///   * **maior**, não último: o arquivo legado é não-monotônico (`1..8` três vezes). Retomar
///     pelo seq da última linha daria 8→9 por sorte hoje e colidiria amanhã, quando a última
///     subida tiver sido mais curta que a anterior.
///   * a janela quase sempre começa no MEIO de uma linha — a primeira é lixo e é descartada.
///   * linha ilegível (escrita parcial interrompida por um kill -9, schema de outra versão) é
///     PULADA, nunca fatal: um byte torto no fim do diário não pode impedir o supervisor de
///     subir.
fn rehidratar(path: &std::path::Path) -> (u64, Vec<AgentEvent>, HashMap<String, LaneState>) {
    let mut lanes = HashMap::new();
    let Ok(mut f) = std::fs::File::open(path) else {
        return (0, Vec::new(), lanes);
    };
    let len = f.metadata().map(|m| m.len()).unwrap_or(0);
    let inicio = len.saturating_sub(JANELA_RELEITURA);
    if inicio > 0 && f.seek(SeekFrom::Start(inicio)).is_err() {
        return (0, Vec::new(), lanes);
    }
    let mut r = BufReader::new(f);
    if inicio > 0 {
        let mut parcial = String::new();
        let _ = r.read_line(&mut parcial);
    }

    let mut maior = 0u64;
    let mut janela: VecDeque<AgentEvent> = VecDeque::new();
    // `map_while` e não `filter_map`: um erro de I/O de verdade repetiria para sempre, e um
    // supervisor preso no boot é pior que um supervisor com histórico curto.
    for linha in r.lines().map_while(Result::ok) {
        let Ok(e) = serde_json::from_str::<AgentEvent>(&linha) else {
            continue;
        };
        maior = maior.max(e.seq);
        janela.push_back(e);
        if janela.len() > TETO_RELEITURA {
            janela.pop_front();
        }
    }

    // O estado volta pela MESMA redução que o runtime usa. Se a releitura tivesse um caminho
    // próprio para montar `LaneState`, ele divergiria da redução na primeira mudança de regra.
    for e in &janela {
        reduce(&mut lanes, e);
    }
    (maior, janela.into(), lanes)
}

/// Quem precisa de você primeiro. Ordena o board sem que ninguém escreva prioridade à mão.
fn urgency(k: Kind) -> u8 {
    match k {
        Kind::AwaitingApproval | Kind::AwaitingInput => 0,
        Kind::Error => 1,
        // A lane está falando ou trabalhando — o turno andou, e o board mostra isso junto.
        // `Delta` nunca chega aqui (não é reduzido), mas o match é exaustivo de propósito: é o
        // compilador cobrando um lugar para cada variante nova, e essa cobrança é o ponto.
        Kind::TurnStarted
        | Kind::ToolCall
        | Kind::ToolResult
        | Kind::DiffProposed
        | Kind::AgentMessage
        | Kind::Delta => 2,
        // Prompt do operador: ele acabou de mandar, a lane vai responder. Não é pedido de
        // atenção — atenção é o que ele acabou de dar.
        Kind::UserPrompt => 3,
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
        pending_kind: None,
        last_diff: None,
        streaming_text: None,
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
                // Derivado do método quando o evento não trouxe — assim um evento antigo,
                // relido do jsonl de antes desta versão, ainda ganha o rótulo certo.
                st.pending_kind = e.approval_kind.or(Some(crate::event::ApprovalKind::of(m)));
            }
        }
        // Qualquer coisa que signifique "o turno andou" limpa a pendência: uma aprovação que
        // já foi respondida (por aqui ou pelo próprio terminal dele) não pode ficar no board
        // pedindo atenção que ninguém deve.
        Kind::ApprovalAnswered | Kind::TurnEnded | Kind::Idle | Kind::SessionEnded => {
            st.pending_approval = None;
            st.pending_kind = None;
        }
        _ => {}
    }

    // `Unknown` NÃO sobrescreve um estado conhecido: um evento que ainda não sabemos ler não
    // deve apagar o que sabemos. Ele fica na trama; só não muda o veredicto.
    if e.kind != Kind::Unknown && e.kind != Kind::Delta {
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

    /// Um caminho LIMPO por teste.
    ///
    /// Necessário a partir do momento em que `open` relê o arquivo: estes testes usavam caminhos
    /// fixos em /tmp e só passavam porque a versão anterior IGNORAVA o conteúdo. Reaproveitar o
    /// arquivo de uma execução anterior faria o resultado depender de quantas vezes a suíte já
    /// rodou nesta máquina — exatamente o tipo de verde que não prova nada.
    fn arquivo_novo(nome: &str) -> std::path::PathBuf {
        let p = std::env::temp_dir().join(format!("loomd-test-{nome}.jsonl"));
        let _ = std::fs::remove_file(&p);
        p
    }

    #[test]
    fn o_estado_e_derivado_nunca_escrito() {
        let t = Trama::open(arquivo_novo("derivado"));
        t.append(ev("codex-1", Kind::TurnStarted));
        t.append(ev("codex-1", Kind::ToolCall));
        let s = &t.state()[0];
        assert_eq!(s.kind, Kind::ToolCall);
        assert_eq!(s.turns, 1);
    }

    #[test]
    fn quem_espera_por_voce_vem_primeiro() {
        let t = Trama::open(arquivo_novo("urgencia"));
        t.append(ev("codex-1", Kind::Idle));
        t.append(ev("claude-1", Kind::ToolCall));
        t.append(ev("kimi-cli1", Kind::AwaitingApproval));
        assert_eq!(t.state()[0].lane, "kimi-cli1");
    }

    #[test]
    fn evento_desconhecido_nao_apaga_o_que_sabemos() {
        let t = Trama::open(arquivo_novo("desconhecido"));
        t.append(ev("codex-1", Kind::AwaitingApproval));
        t.append(ev("codex-1", Kind::Unknown));
        // Continua pedindo atenção: um evento ilegível não é motivo para o board relaxar.
        assert_eq!(t.state()[0].kind, Kind::AwaitingApproval);
    }

    #[test]
    fn a_pendencia_some_quando_o_turno_anda() {
        let t = Trama::open(arquivo_novo("pendencia"));
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
        let t = Trama::open(arquivo_novo("diff"));
        let mut d = ev("codex-1", Kind::DiffProposed);
        d.diff = Some("--- a\n+++ b\n".into());
        t.append(d);
        t.append(ev("codex-1", Kind::TurnEnded));
        assert!(t.state()[0].last_diff.as_deref().unwrap().contains("+++ b"));
    }

    #[test]
    fn since_e_um_cursor_de_leitura() {
        let t = Trama::open(arquivo_novo("cursor"));
        t.append(ev("a", Kind::Idle));
        let s2 = t.append(ev("b", Kind::Idle));
        t.append(ev("a", Kind::Idle));
        assert_eq!(t.since(s2, None).len(), 1);
        assert_eq!(t.since(0, Some("a")).len(), 2);
    }

    // ─── Durabilidade: o que atravessa o reinício do daemon ──────────────────────────────────

    #[test]
    fn o_seq_continua_crescendo_depois_de_reabrir() {
        // O ACHADO: no arquivo real, `seq` era [1..8, 1..8, 1..8]. Três subidas, mesmas chaves.
        let p = arquivo_novo("monotonico");
        {
            let t = Trama::open(&p);
            t.append(ev("codex-1", Kind::TurnStarted));
            t.append(ev("codex-1", Kind::ToolCall));
            t.append(ev("codex-1", Kind::TurnEnded));
            assert_eq!(t.seq(), 3);
        }
        let t2 = Trama::open(&p);
        assert_eq!(t2.seq(), 3, "o seq tem que ser RETOMADO do disco, não zerado");
        assert_eq!(t2.append(ev("codex-1", Kind::TurnStarted)), 4);

        // E o diário no disco não pode ter chave repetida.
        let seqs: Vec<u64> = std::fs::read_to_string(&p)
            .unwrap()
            .lines()
            .filter(|l| !l.trim().is_empty())
            .map(|l| serde_json::from_str::<AgentEvent>(l).unwrap().seq)
            .collect();
        assert_eq!(seqs, vec![1, 2, 3, 4]);
    }

    #[test]
    fn o_seq_retoma_do_maior_e_nao_do_ultimo() {
        // A subida anterior foi mais CURTA que a de antes: o último seq do arquivo (2) é menor
        // que o maior (3). Retomar pelo último devolveria 3 — uma chave que já existe.
        let p = arquivo_novo("maior-nao-ultimo");
        let linhas: String = [1u64, 2, 3, 1, 2]
            .iter()
            .map(|s| {
                let mut e = ev("codex-1", Kind::Idle);
                e.seq = *s;
                format!("{}\n", serde_json::to_string(&e).unwrap())
            })
            .collect();
        std::fs::write(&p, linhas).unwrap();

        let t = Trama::open(&p);
        assert_eq!(t.seq(), 3);
        assert_eq!(t.append(ev("codex-1", Kind::Idle)), 4);
    }

    #[test]
    fn o_estado_da_lane_sobrevive_ao_reinicio() {
        // Medido no launcher (`sounio-loomd`): com o daemon de pé e o codex conectado,
        // `/v2/state` respondia `{"lanes":[]}` depois de todo reinício, porque nada havia
        // ACONTECIDO desde a subida. O board nascia cego sobre uma lane que ele já conhecia.
        let p = arquivo_novo("estado-sobrevive");
        {
            let t = Trama::open(&p);
            let mut e = ev("loom-1", Kind::TurnEnded);
            e.session = Some("019fe704".into());
            t.append(e);
        }
        let t2 = Trama::open(&p);
        let s = &t2.state()[0];
        assert_eq!(s.lane, "loom-1");
        assert_eq!(s.kind, Kind::TurnEnded);
    }

    #[test]
    fn o_cursor_since_atravessa_o_reinicio() {
        let p = arquivo_novo("since-reinicio");
        {
            let t = Trama::open(&p);
            t.append(ev("a", Kind::Idle));
            t.append(ev("a", Kind::ToolCall));
            t.append(ev("a", Kind::TurnEnded));
        }
        // Cliente que parou de ler no seq 1 continua a leitura de onde parou, com o daemon novo.
        let t2 = Trama::open(&p);
        let vistos: Vec<u64> = t2.since(1, None).iter().map(|e| e.seq).collect();
        assert_eq!(vistos, vec![2, 3]);
    }

    #[test]
    fn a_thread_da_lane_sobrevive_ao_reinicio() {
        // É daqui que a subida FRIA tira o `threadId` para o `thread/resume`. Sem isto o loomd
        // reiniciado abre sessão NOVA e o trabalho da lane fica órfão no store do Codex.
        let p = arquivo_novo("thread-sobrevive");
        {
            let t = Trama::open(&p);
            let mut e = ev("loom-1", Kind::SessionStarted);
            e.session = Some("019fe704-f858-7de2-ba18-e69a6f2e6246".into());
            t.append(e);
            t.append(ev("loom-1", Kind::TurnEnded)); // evento SEM sessão não pode apagar o id
        }
        let t2 = Trama::open(&p);
        assert_eq!(
            t2.session_of("loom-1").as_deref(),
            Some("019fe704-f858-7de2-ba18-e69a6f2e6246")
        );
        assert_eq!(t2.session_of("lane-que-nunca-existiu"), None);
    }

    #[test]
    fn linha_truncada_no_fim_nao_impede_a_retomada() {
        // Um kill -9 no meio de um `writeln!` deixa meia linha no fim do diário. Se a releitura
        // fosse estrita, o supervisor não subiria — e a metade escrita valeria mais que a frota.
        let p = arquivo_novo("truncada");
        {
            let t = Trama::open(&p);
            t.append(ev("a", Kind::Idle));
            t.append(ev("a", Kind::ToolCall));
        }
        {
            use std::io::Write as _;
            let mut f = std::fs::OpenOptions::new().append(true).open(&p).unwrap();
            write!(f, "{{\"seq\":9,\"ts_ms\":1,\"lane\":\"a\",\"ki").unwrap();
        }
        let t2 = Trama::open(&p);
        assert_eq!(t2.seq(), 2, "a linha pela metade não pode virar high-water mark");
        assert_eq!(t2.append(ev("a", Kind::Idle)), 3);
        assert_eq!(t2.since(0, None).len(), 3);
    }

    #[test]
    fn a_releitura_e_limitada_mesmo_com_diario_grande() {
        // O diário é para durar meses. A subida relê uma JANELA do fim, não o arquivo inteiro:
        // o custo do boot não pode crescer com o histórico. O que NÃO pode ser aproximado é o
        // seq — ele continua exato porque, a partir desta correção, o maior está na última linha.
        let p = arquivo_novo("janela");
        let n = 12_000u64;
        let mut buf = String::new();
        for i in 1..=n {
            let mut e = ev("a", Kind::Idle);
            e.seq = i;
            e.detail = Some("x".repeat(160)); // ~250 B/linha ⇒ ~3 MiB, o triplo da janela
            buf.push_str(&serde_json::to_string(&e).unwrap());
            buf.push('\n');
        }
        std::fs::write(&p, buf).unwrap();
        assert!(std::fs::metadata(&p).unwrap().len() > JANELA_RELEITURA);

        let t = Trama::open(&p);
        assert_eq!(t.seq(), n, "o seq exato tem que sobreviver à janela");
        let carregados = t.since(0, None).len();
        assert!(carregados <= TETO_RELEITURA, "carregou {carregados} eventos na RAM");
        assert!(carregados > 0, "a janela não pode voltar vazia");
        // A janela é o FIM do arquivo: o evento mais antigo ficou no disco, o último está na RAM.
        assert_eq!(t.since(n - 1, None).len(), 1);
        assert!(t.since(0, None).iter().all(|e| e.seq > 1));
    }

    #[test]
    fn o_delta_engorda_o_parcial_sem_entrar_no_diario() {
        // A política, em uma asserção: **70 deltas por turno não podem virar 70 linhas**. Se
        // entrassem, o teto de 20k eventos estouraria em poucos turnos e levaria a conversa
        // junto — trocando um diário legível por um dilúvio que não acrescenta nada, porque o
        // texto final chega inteiro no `item/completed`.
        let t = Trama::open(arquivo_novo("delta-nao-entra"));
        let antes = t.seq();
        for pedaco in ["Vou", " ler", " os", " módulos"] {
            t.acumular_delta("codex-1", pedaco);
        }
        assert_eq!(t.seq(), antes, "delta NÃO consome seq — não é evento de diário");
        let st = t.state().into_iter().find(|l| l.lane == "codex-1").unwrap();
        assert_eq!(st.streaming_text.as_deref(), Some("Vou ler os módulos"));
        assert_eq!(
            std::fs::read_to_string(t.path()).unwrap_or_default().lines().count(),
            0,
            "e nada foi escrito no jsonl"
        );
    }

    #[test]
    fn a_mensagem_completa_apaga_o_parcial() {
        // Sem isto o próximo turno começaria com o texto do anterior colado na frente — e a tela
        // mostraria uma resposta que ninguém deu.
        let t = Trama::open(arquivo_novo("delta-limpa"));
        t.acumular_delta("codex-1", "meio caminho");
        t.limpar_delta("codex-1");
        let mut e = AgentEvent::new("codex-1", Kind::AgentMessage, Confidence::Exact);
        e.text = Some("resposta inteira".into());
        t.append(e);
        let st = t.state().into_iter().find(|l| l.lane == "codex-1").unwrap();
        assert!(st.streaming_text.is_none(), "o parcial some quando a mensagem chega");
        assert_eq!(st.kind, Kind::AgentMessage);
    }

    #[test]
    fn a_pendencia_diz_se_e_comando_ou_patch() {
        // O rótulo do botão sai daqui: aplicar patch se desfaz por git, rodar comando não.
        let t = Trama::open(arquivo_novo("pendencia-kind"));
        let mut e = AgentEvent::new("codex-1", Kind::AwaitingApproval, Confidence::Exact);
        e.approval_id = Some("7".into());
        e.approval_method = Some("item/fileChange/requestApproval".into());
        t.append(e);
        let st = t.state().into_iter().find(|l| l.lane == "codex-1").unwrap();
        assert_eq!(st.pending_kind, Some(crate::event::ApprovalKind::Patch));

        // E some junto com a pendência quando o turno anda.
        t.append(AgentEvent::new("codex-1", Kind::TurnEnded, Confidence::Exact));
        let st = t.state().into_iter().find(|l| l.lane == "codex-1").unwrap();
        assert!(st.pending_kind.is_none() && st.pending_approval.is_none());
    }
}
