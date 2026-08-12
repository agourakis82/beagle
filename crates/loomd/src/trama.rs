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
use serde::{Deserialize, Serialize};
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

/// O que ESTA lane aceita. A tela lê isto para nunca oferecer o que devolve 404, e para dizer
/// "enfileirar" onde enfileira e "redirecionar" onde redireciona.
///
/// 🚨 NÃO se deduz do nome. `claude-1` é tail (só leitura) e `claude-4` é ACP (dirigível) — mesmo
/// prefixo, comportamentos opostos. Deduzir do sid é o defeito que este tipo existe para impedir.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum Aceita {
    /// codex: `turn/steer` REDIRECIONA o turno em curso.
    Redireciona,
    /// ACP: não há steer; `promptQueueing` ENFILEIRA para depois.
    Enfileira,
    /// tail: o loomd só LÊ o transcript. `/prompt` e `/steer` devolvem 404.
    SomenteLeitura,
}

/// De qual conjunto a lane veio. A guarda de sobreposição em `main()` já garante que ela está em
/// no máximo um, então a ordem de teste aqui não pode produzir ambiguidade.
pub fn aceita_da_lane(
    codex: &[(String, String)],
    acp: &[(String, String)],
    tails: &[(String, String)],
    lane: &str,
) -> Option<Aceita> {
    let tem = |v: &[(String, String)]| v.iter().any(|(l, _)| l == lane);
    if tem(codex) {
        Some(Aceita::Redireciona)
    } else if tem(acp) {
        Some(Aceita::Enfileira)
    } else if tem(tails) {
        Some(Aceita::SomenteLeitura)
    } else {
        None
    }
}

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
    /// O turno EM CURSO. `turn/interrupt` e `turn/steer` exigem `turnId` como precondição, e o
    /// loomd recebia esse id em todo evento e o descartava — dava para ver a lane trabalhando e
    /// não havia como falar com o turno. `None` = nada rodando.
    #[serde(skip_serializing_if = "Option::is_none")]
    pub current_turn: Option<String>,
    /// Comando ou patch, quando há aprovação pendente. Muda o rótulo do botão porque muda o risco.
    #[serde(skip_serializing_if = "Option::is_none")]
    pub pending_kind: Option<crate::event::ApprovalKind>,
    /// A mensagem SENDO ESCRITA agora, montada dos deltas. **Não está na trama** — é estado em
    /// voo, e some quando a mensagem completa chega. É isto que faz a tela mostrar o texto
    /// chegando sem enterrar o diário em 70 linhas por turno.
    #[serde(skip_serializing_if = "Option::is_none")]
    pub streaming_text: Option<String>,
    /// O que esta lane aceita — ver `Aceita`. `None` só antes de a lane ser declarada.
    #[serde(skip_serializing_if = "Option::is_none")]
    pub aceita: Option<Aceita>,
    pub turns: u32,
    /// Custo acumulado da lane, em USD. Soma dos custos POR TURNO, onde o custo de um turno é o
    /// último `Usage` com valor — não a soma dos `Usage`, porque 15 de 16 vêm nulos e um
    /// fechamento zerado não pode apagar o preço que o turno já tinha.
    ///
    /// Omitido do JSON quando zero: "US$ 0,00" na tela é ruído que treina o olho a ignorar a
    /// linha, e zero é o estado da imensa maioria das lanes que nunca receberam um `usage_update`
    /// com custo. A ausência do campo já diz "sem custo conhecido" sem precisar de um número.
    #[serde(skip_serializing_if = "e_zero")]
    pub usd: f64,
    /// Último custo > 0 visto no turno EM CURSO (`None` fora de um turno, ou dentro de um que
    /// ainda não recebeu `Usage` com valor). Não vai ao JSON — é só o marcador que permite `usd`
    /// já contar o turno aberto (substituindo a contribuição antiga pela nova quando um segundo
    /// `Usage` chega) sem esperar um `TurnEnded` que pode nunca acontecer antes de o operador
    /// olhar a tela.
    #[serde(skip)]
    turno_usd: Option<f64>,
    /// Se esta lane JÁ emitiu `TurnStarted` alguma vez. É o que faz a contagem de `turns`
    /// **adaptar-se ao vocabulário da lane** em vez de exigir um evento que ela nunca manda.
    ///
    /// 🚨 MEDIDO no diário de produção (`/workspace/.loomd/trama.jsonl`, 11-ago-2026):
    /// `claude-4` (ACP) tinha `user_prompt = 7` e `turn_started = 0`, e o `/v2/state` dizia
    /// `turns: 0` — o operador mandou sete pedidos e a tela afirmava zero. Contar sempre em
    /// `TurnStarted | UserPrompt` seria pior: nas lanes de codex os dois chegam ADJACENTES no
    /// MESMO turno (`turn/started` + `item/completed` de `userMessage`), então todo turno
    /// contaria dobrado. Daí a regra por lane: se ela já provou que fala `TurnStarted`, conte
    /// por ele; se nunca emitiu, conte por `UserPrompt`. É honesto porque o adaptador de uma
    /// lane tem vocabulário FIXO — ele não alterna no meio da sessão.
    ///
    /// Fora do JSON: é mecanismo interno da contagem, não um fato que a tela deva afirmar.
    #[serde(skip)]
    viu_turn_started: bool,
    /// O turno em curso já foi contado por um `UserPrompt`, e o `TurnStarted` que vier a seguir
    /// não pode contá-lo de novo.
    ///
    /// 🚨 Esta é a ordem perigosa: numa lane de codex o PRIMEIRO evento do PRIMEIRO turno pode
    /// ser `UserPrompt`, **antes** de qualquer `TurnStarted`. Naquele instante `viu_turn_started`
    /// ainda é falso, então a regra acima conta o prompt — e o `TurnStarted` que chega logo
    /// depois contaria o mesmo turno uma segunda vez. Este marcador faz esse primeiro
    /// `TurnStarted` apenas CONSUMIR a contagem que o prompt já fez. Dali em frente
    /// `viu_turn_started` é verdadeiro, nenhum `UserPrompt` conta mais, e o marcador nunca
    /// volta a ser armado.
    #[serde(skip)]
    turno_contado_por_prompt: bool,
}

fn e_zero(v: &f64) -> bool {
    *v == 0.0
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
        let file = std::fs::OpenOptions::new()
            .create(true)
            .append(true)
            .open(&path)
            .ok();
        Self {
            inner: Mutex::new(Inner {
                seq,
                events,
                lanes,
                file,
            }),
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

    /// Junta mais um pedaço da mensagem em voo.
    ///
    /// Vive aqui, e não em `codex.rs`, porque o estado da lane é UMA coisa só: dois lugares
    /// guardando pedaço de verdade é como nasce card que discorda de si mesmo.
    pub fn acumular_delta(&self, lane: &str, pedaco: &str) {
        let mut g = self.inner.lock().unwrap();
        let agora = crate::event::now_ms();
        let st = g
            .lanes
            .entry(lane.to_string())
            .or_insert_with(|| LaneState {
                lane: lane.to_string(),
                kind: Kind::Unknown,
                confidence: Confidence::Exact,
                observed_at_ms: agora,
                detail: None,
                session: None,
                pending_approval: None,
                pending_kind: None,
                current_turn: None,
                last_diff: None,
                streaming_text: None,
                aceita: None,
                turns: 0,
                usd: 0.0,
                turno_usd: None,
                viu_turn_started: false,
                turno_contado_por_prompt: false,
            });
        st.observed_at_ms = agora;
        st.streaming_text
            .get_or_insert_with(String::new)
            .push_str(pedaco);
    }

    /// O parcial cumpriu seu papel: a mensagem completa chegou à trama.
    /// Não limpar faria o próximo turno começar com o texto do anterior colado na frente.
    pub fn limpar_delta(&self, lane: &str) {
        let mut g = self.inner.lock().unwrap();
        if let Some(st) = g.lanes.get_mut(lane) {
            st.streaming_text = None;
        }
    }

    /// Tira o texto acumulado e limpa o buffer, numa só operação. Devolve `None` se estava vazio.
    ///
    /// Existe porque `limpar_delta` DESCARTA — certo quando outro caminho já registrou a
    /// mensagem completa (o `item/completed` do codex), errado quando NINGUÉM mais vai
    /// registrá-la (o ACP só emite chunk, nunca uma variante de mensagem completa). Quem chama
    /// isto é responsável por publicar o texto antes de deixá-lo cair no chão.
    pub fn tomar_delta(&self, lane: &str) -> Option<String> {
        let mut g = self.inner.lock().unwrap();
        let st = g.lanes.get_mut(lane)?;
        let texto = st.streaming_text.take()?;
        if texto.is_empty() {
            None
        } else {
            Some(texto)
        }
    }

    /// DECLARA uma lane que o daemon supervisiona, mesmo antes do primeiro evento.
    ///
    /// 🚨 MEDIDO ao adotar a segunda lane (10-ago-2026): `codex-4` subiu, o processo estava vivo,
    /// e ela **não aparecia no `/v2/state`** — porque o estado é derivado de eventos e ela ainda
    /// não tinha falado. Uma lane que existe e é invisível é pior que uma lane ausente: o board
    /// não oferece nada nela, e quem olha conclui que a adoção falhou.
    ///
    /// `Unknown` de propósito, e é o oposto de um chute otimista: significa "supervisionada, nada
    /// observado ainda". O primeiro evento real substitui — `reduce` não deixa `Unknown` apagar
    /// estado conhecido, e aqui o restante do `LaneState` segue a mesma regra: só é criado do
    /// zero se a lane ainda não existe.
    ///
    /// 🚨 `aceita`, porém, é escrito **mesmo quando a lane já existe** (`and_modify`), e só
    /// esse campo. A rehidratação do diário em `Trama::open` já recria a entrada da lane (com
    /// `aceita: None`) antes de `main()` chamar `declarar_com` — em produção a lane SEMPRE já
    /// existe quando isto roda. Um `or_insert_with` puro seria silenciosamente inútil aqui: o
    /// `/v2/state` ficaria com `aceita: null` para a frota inteira, porque a entrada "já existia"
    /// e o closure nunca roda. `and_modify` tocando só `aceita` resolve isto sem reescrever a
    /// `LaneState` inteira — o que zeraria `usd`/`turns` acumulados a cada declaração.
    pub fn declarar_com(&self, lane: &str, aceita: Option<Aceita>) {
        let mut g = self.inner.lock().unwrap();
        let agora = crate::event::now_ms();
        g.lanes
            .entry(lane.to_string())
            .and_modify(|st| st.aceita = aceita)
            .or_insert_with(|| LaneState {
                lane: lane.to_string(),
                kind: Kind::Unknown,
                confidence: Confidence::Exact,
                observed_at_ms: agora,
                detail: Some("supervisionada; nenhum turno ainda".into()),
                session: None,
                pending_approval: None,
                pending_kind: None,
                current_turn: None,
                last_diff: None,
                streaming_text: None,
                aceita,
                turns: 0,
                usd: 0.0,
                turno_usd: None,
                viu_turn_started: false,
                turno_contado_por_prompt: false,
            });
    }

    pub fn state(&self) -> Vec<LaneState> {
        let g = self.inner.lock().unwrap();
        let mut v: Vec<_> = g.lanes.values().cloned().collect();
        v.sort_by(|a, b| {
            urgency(a.kind)
                .cmp(&urgency(b.kind))
                .then(a.lane.cmp(&b.lane))
        });
        v
    }

    pub fn since(&self, since: u64, lane: Option<&str>) -> Vec<AgentEvent> {
        let g = self.inner.lock().unwrap();
        g.events
            .iter()
            .filter(|e| e.seq > since && lane.is_none_or(|l| e.lane == l))
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

    /// O turno em curso, se houver. É a precondição de `turn/interrupt` e `turn/steer`.
    pub fn current_turn(&self, lane: &str) -> Option<String> {
        let g = self.inner.lock().unwrap();
        g.lanes.get(lane).and_then(|s| s.current_turn.clone())
    }

    /// O maior `seq` já emitido. Existe para o teste poder afirmar a monotonicidade sem
    /// depender de qual evento foi o último. Só chamado de `#[cfg(test)]`, então o build normal
    /// do binário a vê como morta.
    #[allow(dead_code)]
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
        // Custo de turno: informativo, nunca pede atenção do operador.
        Kind::Usage => 6,
        Kind::ApprovalAnswered | Kind::Unknown => 6,
    }
}

/// Lê o custo de um `detail` de `Kind::Usage` — o formato que este mesmo crate escreve em
/// `event.rs` (`.detail(format!("contexto {usados}/{teto} · USD {custo:.4}"))`).
///
/// `None` quando o detail não tem a forma esperada: melhor não somar nada do que somar lixo.
/// `Some(0.0)` é uma resposta válida e diferente de `None` — custo zero É informação ("veio
/// evento, sem cobrança"), enquanto `None` diz "isto não é um `Usage` legível".
pub fn custo_do_detail(detail: &str) -> Option<f64> {
    let (_, resto) = detail.split_once("USD ")?;
    resto.trim().parse::<f64>().ok()
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
        current_turn: None,
        last_diff: None,
        streaming_text: None,
        aceita: None,
        turns: 0,
        usd: 0.0,
        turno_usd: None,
        viu_turn_started: false,
        turno_contado_por_prompt: false,
    });

    st.observed_at_ms = e.ts_ms;
    st.confidence = e.confidence;
    if e.session.is_some() {
        st.session = e.session.clone();
    }
    if let Some(d) = &e.diff {
        st.last_diff = Some(d.clone());
    }
    // A contagem de turnos ADAPTA-SE ao vocabulário da lane — ver `viu_turn_started` e
    // `turno_contado_por_prompt` na `LaneState` para a medição que obrigou isto e para por que a
    // regra ingênua (`TurnStarted | UserPrompt`) dobraria nas lanes de codex.
    match e.kind {
        Kind::TurnStarted => {
            st.viu_turn_started = true;
            if st.turno_contado_por_prompt {
                // O `UserPrompt` que abriu ESTE turno já o contou (ele chegou antes do primeiro
                // `TurnStarted` da lane, quando ainda não se sabia que ela fala `TurnStarted`).
                // Contar aqui de novo daria dois turnos para um.
                st.turno_contado_por_prompt = false;
            } else {
                st.turns += 1;
            }
            st.current_turn = e.turn.clone();
        }
        // Só conta enquanto a lane nunca provou falar `TurnStarted`. Numa lane ACP isso é para
        // sempre — é a única fronteira de turno que ela emite.
        Kind::UserPrompt if !st.viu_turn_started => {
            st.turns += 1;
            st.turno_contado_por_prompt = true;
        }
        _ => {}
    }
    // Fim de turno, ociosidade ou queda de sessão: não há mais turno com quem falar. Deixar o id
    // para trás faria um "interromper" mirar num turno que já acabou — e o codex recusa com uma
    // precondição, o que na tela viraria um botão que falha sem explicação.
    if matches!(e.kind, Kind::TurnEnded | Kind::Idle | Kind::SessionEnded) {
        st.current_turn = None;
    }

    // O turno fecha aqui — em TurnEnded/Idle/SessionEnded, OU sucedido por um novo TurnStarted
    // (ninguém garante que o adaptador sempre emite um fim explícito). `st.usd` já contava a
    // contribuição do turno (ver abaixo), então fechar é só soltar o marcador: nada a somar de
    // novo, e nada que um evento de fechamento sem custo possa apagar.
    //
    // 🚨 `UserPrompt` está nesta lista porque é a ÚNICA fronteira de turno que a lane ACP de
    // fato emite. `Kind::Usage` só nasce em `event.rs::from_acp_update` (`usage_update` do ACP)
    // — ou seja, só em lanes ACP. E o vocabulário real de uma lane ACP não tem
    // `TurnStarted`/`TurnEnded`/`Idle`: tem `user_prompt`, `agent_message`, `tool_call`,
    // `usage`, `error`, `session_started/ended`. Sem `UserPrompt` aqui, `turno_usd` nunca era
    // liberado numa lane ACP, e `st.usd` acabava sendo o ÚLTIMO `usage` com custo da SESSÃO
    // inteira, não a soma por turno (medido: 3 turnos de 0,10/0,25/0,30 deviam somar 0,65 e
    // davam 0,30). É também a mesma fronteira que o lado Swift usa — `Turno.agrupar` quebra em
    // `.prompt` — então isto unifica a unidade "turno" entre as duas linguagens.
    //
    // Nas lanes de codex é inócuo: `item/completed` de `userMessage` (que vira `UserPrompt`)
    // chega no MESMO turno que já tem `turn/started` (`TurnStarted`), e lanes de codex nunca
    // emitem `Usage` — então soltar `turno_usd` de novo aqui não muda nada para elas. Note que
    // isto NÃO mexe na contagem de `turns`: quem conta é o `match` acima, com sua própria regra
    // (adaptada ao vocabulário da lane) — nas lanes de codex o `UserPrompt` não conta turno,
    // porque elas já provaram falar `TurnStarted`.
    if matches!(
        e.kind,
        Kind::TurnStarted | Kind::TurnEnded | Kind::Idle | Kind::SessionEnded | Kind::UserPrompt
    ) {
        st.turno_usd = None;
    }

    // Custo do turno em curso. `usados`/`teto` não interessam aqui — só `USD`, e só quando > 0:
    // medido nas fixtures do censo ACP, 15 dos 16 `usage_update` de um turno vêm com custo nulo,
    // e o adaptador às vezes fecha o turno com um `usage` de custo ZERO depois de um com custo.
    // Se aceitássemos qualquer valor (inclusive 0.0) aqui, esse fechamento apagaria o preço que
    // o turno já tinha. `st.usd` é mantido como TOTAL corrente: ao trocar o custo pendente do
    // turno em curso, tira-se a contribuição antiga e soma-se a nova — assim um turno aberto já
    // conta, sem esperar o `TurnEnded` que pode nunca vir antes de o operador olhar a tela.
    if e.kind == Kind::Usage {
        if let Some(custo) = e.detail.as_deref().and_then(custo_do_detail) {
            if custo > 0.0 {
                let antigo = st.turno_usd.take().unwrap_or(0.0);
                st.usd = st.usd - antigo + custo;
                st.turno_usd = Some(custo);
            }
        }
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

    /// 🚨 O que a lane ACEITA não se deduz do NOME. `claude-1` (tail, só leitura) e `claude-4`
    /// (ACP, dirigível) têm o mesmo prefixo e comportamentos OPOSTOS: `/prompt` na primeira
    /// devolve 404. O cliente lê este campo; nunca infere do sid.
    #[test]
    fn aceita_sai_de_qual_conjunto_a_lane_veio() {
        let codex = vec![("codex-4".to_string(), "/wt/codex-4".to_string())];
        let acp = vec![("claude-4".to_string(), "/wt/claude-4".to_string())];
        let tails = vec![("claude-1".to_string(), "/dir".to_string())];

        assert_eq!(
            aceita_da_lane(&codex, &acp, &tails, "codex-4"),
            Some(Aceita::Redireciona)
        );
        assert_eq!(
            aceita_da_lane(&codex, &acp, &tails, "claude-4"),
            Some(Aceita::Enfileira)
        );
        assert_eq!(
            aceita_da_lane(&codex, &acp, &tails, "claude-1"),
            Some(Aceita::SomenteLeitura)
        );
        assert_eq!(aceita_da_lane(&codex, &acp, &tails, "nao-existe"), None);
    }

    /// O prefixo do nome NÃO decide. Duas lanes `claude-*` em conjuntos diferentes têm de sair
    /// diferentes — é este teste que impede alguém de "simplificar" para `sid.starts_with`.
    #[test]
    fn duas_lanes_do_mesmo_prefixo_podem_aceitar_coisas_opostas() {
        let acp = vec![("claude-4".to_string(), "/wt".to_string())];
        let tails = vec![("claude-1".to_string(), "/dir".to_string())];
        let a = aceita_da_lane(&[], &acp, &tails, "claude-4");
        let b = aceita_da_lane(&[], &acp, &tails, "claude-1");
        assert_ne!(a, b, "mesmo prefixo, capacidades opostas");
    }

    #[test]
    fn aceita_serializa_em_snake_case() {
        let j = serde_json::to_string(&Aceita::SomenteLeitura).unwrap();
        assert_eq!(j, "\"somente_leitura\"");
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
        assert_eq!(
            t2.seq(),
            3,
            "o seq tem que ser RETOMADO do disco, não zerado"
        );
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
        assert_eq!(
            t2.seq(),
            2,
            "a linha pela metade não pode virar high-water mark"
        );
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
        assert!(
            carregados <= TETO_RELEITURA,
            "carregou {carregados} eventos na RAM"
        );
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
        assert_eq!(
            t.seq(),
            antes,
            "delta NÃO consome seq — não é evento de diário"
        );
        let st = t.state().into_iter().find(|l| l.lane == "codex-1").unwrap();
        assert_eq!(st.streaming_text.as_deref(), Some("Vou ler os módulos"));
        assert_eq!(
            std::fs::read_to_string(t.path())
                .unwrap_or_default()
                .lines()
                .count(),
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
        assert!(
            st.streaming_text.is_none(),
            "o parcial some quando a mensagem chega"
        );
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
        t.append(AgentEvent::new(
            "codex-1",
            Kind::TurnEnded,
            Confidence::Exact,
        ));
        let st = t.state().into_iter().find(|l| l.lane == "codex-1").unwrap();
        assert!(st.pending_kind.is_none() && st.pending_approval.is_none());
    }

    #[test]
    fn o_turno_corrente_existe_enquanto_ele_roda_e_some_quando_acaba() {
        // 🚨 `turn/interrupt` e `turn/steer` exigem `turnId` como PRECONDIÇÃO. O loomd recebia
        // esse id em todo evento e o descartava — dava para ver a lane trabalhando e não havia
        // como falar com o turno. E o inverso importa igual: deixar o id para trás faria um
        // "interromper" mirar num turno já encerrado, que o codex recusa — na tela, um botão que
        // falha sem explicação.
        let t = Trama::open(arquivo_novo("turno-corrente"));
        assert_eq!(t.current_turn("codex-1"), None, "lane parada não tem turno");

        let mut inicio = AgentEvent::new("codex-1", Kind::TurnStarted, Confidence::Exact);
        inicio.turn = Some("tu-7".into());
        t.append(inicio);
        assert_eq!(t.current_turn("codex-1").as_deref(), Some("tu-7"));

        // Um evento no MEIO do turno não pode apagar o alvo.
        t.append(AgentEvent::new(
            "codex-1",
            Kind::ToolCall,
            Confidence::Exact,
        ));
        assert_eq!(t.current_turn("codex-1").as_deref(), Some("tu-7"));

        t.append(AgentEvent::new(
            "codex-1",
            Kind::TurnEnded,
            Confidence::Exact,
        ));
        assert_eq!(
            t.current_turn("codex-1"),
            None,
            "turno encerrado não é alvo"
        );
    }

    #[test]
    fn a_lane_ociosa_perde_o_alvo_mesmo_sem_turn_ended() {
        // O codex nem sempre fecha com `turn/completed` — uma queda de sessão ou um `idle`
        // também significam "não há mais turno". Confiar só no fim feliz deixaria o id preso.
        for fim in [Kind::Idle, Kind::SessionEnded] {
            let t = Trama::open(arquivo_novo(&format!("turno-{fim:?}")));
            let mut inicio = AgentEvent::new("c", Kind::TurnStarted, Confidence::Exact);
            inicio.turn = Some("tu-1".into());
            t.append(inicio);
            t.append(AgentEvent::new("c", fim, Confidence::Exact));
            assert_eq!(t.current_turn("c"), None, "{fim:?} deveria limpar o alvo");
        }
    }

    #[test]
    fn lane_supervisionada_aparece_antes_do_primeiro_turno() {
        // 🚨 MEDIDO ao adotar a segunda lane: `codex-4` subiu com o processo vivo e NÃO aparecia
        // no /v2/state. Lane que existe e é invisível é pior que lane ausente — o board não
        // oferece nada nela e quem olha conclui que a adoção falhou.
        let t = Trama::open(arquivo_novo("declarar"));
        assert!(t.state().is_empty());
        t.declarar_com("codex-4", None);
        let st = t.state();
        assert_eq!(st.len(), 1);
        assert_eq!(
            st[0].kind,
            Kind::Unknown,
            "supervisionada e não observada — não um chute"
        );
        assert!(st[0].detail.as_deref().unwrap().contains("nenhum turno"));
    }

    #[test]
    fn declarar_nao_apaga_o_que_ja_se_sabe() {
        // O launcher declara a cada subida. Se `declarar` sobrescrevesse, uma reinicialização do
        // daemon zeraria o estado retomado do diário — e o `?since=` diria que nada aconteceu.
        let t = Trama::open(arquivo_novo("declarar-idempotente"));
        let mut e = AgentEvent::new("codex-4", Kind::AwaitingApproval, Confidence::Exact);
        e.approval_id = Some("7".into());
        e.approval_method = Some("item/fileChange/requestApproval".into());
        t.append(e);
        t.declarar_com("codex-4", None);
        let st = t.state().into_iter().find(|l| l.lane == "codex-4").unwrap();
        assert_eq!(
            st.kind,
            Kind::AwaitingApproval,
            "declarar não pode apagar uma pendência"
        );
        assert!(st.pending_approval.is_some());
    }

    #[test]
    fn declarar_com_grava_aceita_em_lane_ja_rehidratada() {
        // 🚨 MEDIDO em produção (10-ago-2026): as 6 lanes subiram com `aceita: None` no
        // `/v2/state` — `claude-1/2/3`, `claude-4`, `codex-4`, `loom-1`, todas. A causa é a
        // ORDEM real de `main()`: `Trama::open` relê o jsonl e rehidrata a lane (via `append`,
        // com `aceita: None`) ANTES de `declarar_com` ser chamado. Um `or_insert_with` puro só
        // age quando a chave não existe — e em produção ela já existe, então a declaração não
        // fazia nada. Este teste reproduz essa ordem: faz a lane existir primeiro (um `append`,
        // exatamente o que a rehidratação faz), só depois declara.
        let t = Trama::open(arquivo_novo("declarar-com-lane-rehidratada"));
        t.append(ev("codex-4", Kind::SessionStarted));
        assert!(
            t.state()
                .into_iter()
                .find(|l| l.lane == "codex-4")
                .unwrap()
                .aceita
                .is_none(),
            "antes de declarar, aceita ainda é None"
        );

        t.declarar_com("codex-4", Some(Aceita::Redireciona));

        let st = t.state().into_iter().find(|l| l.lane == "codex-4").unwrap();
        assert_eq!(
            st.aceita,
            Some(Aceita::Redireciona),
            "declarar_com tem de gravar aceita mesmo numa lane que já existia"
        );
    }

    #[test]
    fn declarar_com_duas_vezes_vale_a_ultima() {
        // É declaração, não primeira-escrita-ganha: se a segunda subida do launcher observar
        // outro conjunto (codex/ACP/tail), o `/v2/state` tem de refletir o valor mais recente.
        let t = Trama::open(arquivo_novo("declarar-com-duas-vezes"));
        t.declarar_com("codex-4", Some(Aceita::Redireciona));
        t.declarar_com("codex-4", Some(Aceita::SomenteLeitura));

        let st = t.state().into_iter().find(|l| l.lane == "codex-4").unwrap();
        assert_eq!(st.aceita, Some(Aceita::SomenteLeitura));
    }

    // ─── Custo (Task 6a): o chip da Frota lê `usd` daqui ──────────────────────────────────────

    fn usage(lane: &str, custo: f64) -> AgentEvent {
        AgentEvent::new(lane, Kind::Usage, Confidence::Exact)
            .detail(format!("contexto 100/200 · USD {custo:.4}"))
    }

    #[test]
    fn custo_do_detail_le_o_formato_real_e_rejeita_lixo() {
        assert_eq!(custo_do_detail("contexto 100/200 · USD 0.1000"), Some(0.1));
        assert_eq!(custo_do_detail("isto não é um usage"), None);
        // Zero É informação ("veio evento, sem cobrança") — não é o mesmo que "detail ilegível".
        assert_eq!(custo_do_detail("contexto 100/200 · USD 0.0000"), Some(0.0));
    }

    #[test]
    fn dentro_do_turno_o_custo_e_o_ultimo_com_valor_nao_a_soma() {
        // 15 dos 16 `usage_update` de um turno vêm com custo nulo; só o último traz número. Se
        // a regra fosse "somar todos os Usage com custo", 0.10 + 0.25 daria 0.35 — errado.
        let t = Trama::open(arquivo_novo("custo-ultimo-nao-soma"));
        t.append(ev("codex-1", Kind::TurnStarted));
        t.append(usage("codex-1", 0.10));
        t.append(usage("codex-1", 0.25));
        t.append(ev("codex-1", Kind::TurnEnded));
        assert_eq!(t.state()[0].usd, 0.25);
    }

    #[test]
    fn declarar_com_nao_zera_custo_nem_turnos_acumulados() {
        // A propriedade que o conserto de `aceita` não pode quebrar: um `and_modify` que
        // reescrevesse a `LaneState` inteira (em vez de tocar só `aceita`) zeraria `usd` e
        // `turns` a cada declaração — trocaria o defeito medido por um pior, porque o número
        // errado ficaria plausível (a lane continuaria aparecendo, só que mais barata do que é).
        let t = Trama::open(arquivo_novo("declarar-preserva-custo"));
        t.append(ev("codex-4", Kind::TurnStarted));
        t.append(usage("codex-4", 0.42));
        t.append(ev("codex-4", Kind::TurnEnded));

        t.declarar_com("codex-4", Some(Aceita::Redireciona));

        let st = t.state().into_iter().find(|l| l.lane == "codex-4").unwrap();
        assert_eq!(
            st.usd, 0.42,
            "declarar_com não pode zerar o custo acumulado"
        );
        assert_eq!(
            st.turns, 1,
            "declarar_com não pode zerar a contagem de turnos"
        );
        assert_eq!(st.aceita, Some(Aceita::Redireciona));
    }

    #[test]
    fn dois_turnos_somam_seus_custos() {
        let t = Trama::open(arquivo_novo("custo-dois-turnos"));
        t.append(ev("codex-1", Kind::TurnStarted));
        t.append(usage("codex-1", 0.10));
        t.append(ev("codex-1", Kind::TurnEnded));
        t.append(ev("codex-1", Kind::TurnStarted));
        t.append(usage("codex-1", 0.25));
        t.append(ev("codex-1", Kind::TurnEnded));
        assert_eq!(t.state()[0].usd, 0.35);
    }

    #[test]
    fn um_fechamento_com_custo_zero_nao_apaga_o_custo_do_turno() {
        // O adaptador às vezes emite um `usage` de fechamento com custo zero depois de um com
        // custo. Esse zero não pode substituir o preço que o turno já tinha.
        let t = Trama::open(arquivo_novo("custo-fechamento-zero"));
        t.append(ev("codex-1", Kind::TurnStarted));
        t.append(usage("codex-1", 0.25));
        t.append(usage("codex-1", 0.0));
        t.append(ev("codex-1", Kind::TurnEnded));
        assert_eq!(t.state()[0].usd, 0.25);
    }

    #[test]
    fn turno_aberto_com_custo_ja_conta_sem_esperar_turn_ended() {
        // A regra: turno fecha em TurnEnded/Idle/SessionEnded OU é sucedido por um novo
        // TurnStarted. Um turno que nunca fecha explicitamente não pode perder o custo — se só
        // somássemos em TurnEnded, uma lane com turno aberto mostraria zero, que é exatamente
        // onde o operador está olhando.
        let t = Trama::open(arquivo_novo("custo-turno-aberto"));
        t.append(ev("codex-1", Kind::TurnStarted));
        t.append(usage("codex-1", 0.42));
        // Sem TurnEnded — o turno segue aberto.
        assert_eq!(t.state()[0].usd, 0.42);
    }

    /// Tolerância para `f64`: os casos abaixo até acertam com `assert_eq!` exato hoje, por
    /// sorte de representação binária — não é prova de nada. Compare com isto, não com `==`.
    fn perto(a: f64, b: f64) {
        assert!(
            (a - b).abs() < 1e-9,
            "esperava {b}, veio {a} (diferença {})",
            (a - b).abs()
        );
    }

    /// 🚨 O teste que a produção teria falhado. Construído SÓ com o vocabulário que uma lane
    /// ACP de fato emite — `user_prompt`, `usage`, `agent_message` — SEM NENHUM
    /// `TurnStarted`/`TurnEnded`: injetar fronteira de turno numa lane ACP é ficção, porque o
    /// adaptador ACP nunca produz esses kinds (só o hook do Claude Code e o app-server do Codex
    /// produzem). As sete reviews anteriores passaram porque todos os testes de custo
    /// injetavam `TurnStarted`/`TurnEnded` numa lane `codex-*` — uma combinação que a produção,
    /// para uma lane ACP como `claude-4`, nunca produz.
    ///
    /// Três turnos delimitados por `UserPrompt`, custos 0,10 / 0,25 / 0,30 → soma 0,65. Antes do
    /// conserto (sem `UserPrompt` na lista de fronteiras), `turno_usd` nunca era liberado e o
    /// resultado era o ÚLTIMO usage com custo da sessão inteira: 0,30.
    #[test]
    fn lane_acp_sem_fronteira_explicita_soma_por_turno_via_user_prompt() {
        let t = Trama::open(arquivo_novo("acp-vocabulario-real-soma-por-turno"));
        // Turno 1
        t.append(ev("claude-4", Kind::UserPrompt));
        t.append(usage("claude-4", 0.10));
        t.append(
            AgentEvent::new("claude-4", Kind::AgentMessage, Confidence::Exact).with_text("ok"),
        );
        // Turno 2
        t.append(ev("claude-4", Kind::UserPrompt));
        t.append(usage("claude-4", 0.25));
        t.append(
            AgentEvent::new("claude-4", Kind::AgentMessage, Confidence::Exact).with_text("ok"),
        );
        // Turno 3
        t.append(ev("claude-4", Kind::UserPrompt));
        t.append(usage("claude-4", 0.30));
        t.append(
            AgentEvent::new("claude-4", Kind::AgentMessage, Confidence::Exact).with_text("ok"),
        );

        let st = t
            .state()
            .into_iter()
            .find(|l| l.lane == "claude-4")
            .unwrap();
        perto(st.usd, 0.65);
    }

    /// Dentro de UM turno ACP (delimitado só por `UserPrompt`, sem `TurnStarted`/`TurnEnded`),
    /// o segundo `usage` com custo substitui o primeiro — a regra do último-com-custo não pode
    /// se perder quando a fronteira passa a ser `UserPrompt`.
    #[test]
    fn dentro_de_um_turno_acp_o_ultimo_usage_com_custo_vale_nao_a_soma() {
        let t = Trama::open(arquivo_novo("acp-um-turno-ultimo-usage-vale"));
        t.append(ev("claude-4", Kind::UserPrompt));
        t.append(usage("claude-4", 0.10));
        t.append(usage("claude-4", 0.25));
        let st = t
            .state()
            .into_iter()
            .find(|l| l.lane == "claude-4")
            .unwrap();
        perto(st.usd, 0.25);
    }

    /// Um `usage` de fechamento com custo ZERO, depois de um turno ACP delimitado por
    /// `UserPrompt` já ter um custo, não pode apagar o que já foi contado.
    #[test]
    fn fechamento_com_custo_zero_em_turno_acp_nao_apaga_o_custo() {
        let t = Trama::open(arquivo_novo("acp-fechamento-zero-nao-apaga"));
        t.append(ev("claude-4", Kind::UserPrompt));
        t.append(usage("claude-4", 0.25));
        t.append(usage("claude-4", 0.0));
        let st = t
            .state()
            .into_iter()
            .find(|l| l.lane == "claude-4")
            .unwrap();
        perto(st.usd, 0.25);
    }

    /// Turno ACP aberto (sem `UserPrompt` seguinte que o feche) com custo já conta — não espera
    /// nenhuma fronteira posterior que uma lane ACP pode nunca emitir.
    #[test]
    fn turno_acp_aberto_com_custo_ja_conta() {
        let t = Trama::open(arquivo_novo("acp-turno-aberto-ja-conta"));
        t.append(ev("claude-4", Kind::UserPrompt));
        t.append(usage("claude-4", 0.42));
        let st = t
            .state()
            .into_iter()
            .find(|l| l.lane == "claude-4")
            .unwrap();
        perto(st.usd, 0.42);
    }

    /// A lane de codex não regride: `TurnStarted`/`TurnEnded` E `UserPrompt` presentes (o
    /// vocabulário real do codex, onde `item/completed` de `userMessage` chega no mesmo turno
    /// que `turn/started`) não pode contar turno nem custo em dobro. `turns` só conta por
    /// `UserPrompt` em lanes que NUNCA emitiram `TurnStarted`; aqui a lane já provou falar
    /// `TurnStarted`, então o prompt é ignorado pela contagem — e é isto que impede que a
    /// adaptação ao vocabulário ACP vire uma dobra nas lanes de codex.
    #[test]
    fn lane_codex_com_turn_started_e_user_prompt_nao_dobra_turno_nem_custo() {
        let t = Trama::open(arquivo_novo("codex-turn-started-e-user-prompt-sem-dobra"));
        t.append(ev("codex-4", Kind::TurnStarted));
        t.append(ev("codex-4", Kind::UserPrompt)); // codex emite os dois no mesmo turno
        t.append(usage("codex-4", 0.42)); // hipotético: codex hoje não emite Usage, mas prova a regra
        t.append(ev("codex-4", Kind::TurnEnded));

        let st = t.state().into_iter().find(|l| l.lane == "codex-4").unwrap();
        assert_eq!(
            st.turns, 1,
            "turns não pode contar em dobro por causa do UserPrompt"
        );
        perto(st.usd, 0.42);
    }

    /// 🚨 O defeito MEDIDO: `claude-4` (ACP) tinha `user_prompt = 7` e `turn_started = 0` no
    /// diário de produção, e o `/v2/state` respondia `turns: 0`. Sete pedidos do operador, zero
    /// na tela — o sistema sabia e a tela afirmava zero. Uma lane ACP não emite fronteira de
    /// turno: seu vocabulário é `user_prompt`, `agent_message`, `tool_call`, `usage`, `error`,
    /// `session_started/ended`. Contar só `TurnStarted` era esperar por um evento que ela nunca
    /// manda.
    #[test]
    fn lane_acp_sem_turn_started_conta_turno_por_user_prompt() {
        let t = Trama::open(arquivo_novo("acp-conta-por-user-prompt"));
        for _ in 0..7 {
            t.append(ev("claude-4", Kind::UserPrompt));
            t.append(ev("claude-4", Kind::AgentMessage));
            t.append(usage("claude-4", 0.01));
        }
        let st = t
            .state()
            .into_iter()
            .find(|l| l.lane == "claude-4")
            .unwrap();
        assert_eq!(
            st.turns, 7,
            "7 user_prompt e 0 turn_started numa lane ACP têm de dar 7 turnos, não 0"
        );
    }

    /// A regra ingênua (`TurnStarted | UserPrompt`) dobraria: nas lanes de codex os dois chegam
    /// ADJACENTES no mesmo turno. Três turnos têm de dar 3, nunca 6.
    #[test]
    fn lane_codex_com_tres_turnos_adjacentes_conta_tres_nao_seis() {
        let t = Trama::open(arquivo_novo("codex-tres-turnos-sem-dobra"));
        for _ in 0..3 {
            t.append(ev("codex-4", Kind::TurnStarted));
            t.append(ev("codex-4", Kind::UserPrompt));
            t.append(ev("codex-4", Kind::AgentMessage));
            t.append(ev("codex-4", Kind::TurnEnded));
        }
        let st = t.state().into_iter().find(|l| l.lane == "codex-4").unwrap();
        assert_eq!(
            st.turns, 3,
            "3 turnos de codex com TurnStarted+UserPrompt adjacentes contam 3, não 6"
        );
    }

    /// 🚨 A ORDEM PERIGOSA. Numa lane de codex o primeiro evento do primeiro turno pode ser
    /// `UserPrompt` — **antes** do primeiro `TurnStarted`. Naquele instante a lane ainda não
    /// provou falar `TurnStarted`, então o prompt conta; sem uma guarda, o `TurnStarted` que
    /// vem logo depois contaria o MESMO turno outra vez, e a lane inteira ficaria com um turno
    /// a mais para sempre. Dois turnos aqui têm de dar 2, nunca 3.
    #[test]
    fn user_prompt_antes_do_primeiro_turn_started_nao_dobra_o_turno() {
        let t = Trama::open(arquivo_novo("prompt-antes-do-turn-started"));
        // Turno 1: o prompt chega ANTES da fronteira.
        t.append(ev("codex-4", Kind::UserPrompt));
        t.append(ev("codex-4", Kind::TurnStarted));
        t.append(ev("codex-4", Kind::AgentMessage));
        t.append(ev("codex-4", Kind::TurnEnded));
        // Turno 2: mesma ordem, agora que a lane já provou falar `TurnStarted`.
        t.append(ev("codex-4", Kind::UserPrompt));
        t.append(ev("codex-4", Kind::TurnStarted));
        t.append(ev("codex-4", Kind::TurnEnded));

        let st = t.state().into_iter().find(|l| l.lane == "codex-4").unwrap();
        assert_eq!(
            st.turns, 2,
            "UserPrompt antes do primeiro TurnStarted não pode contar o turno duas vezes"
        );
    }

    #[test]
    fn lane_sem_usage_tem_custo_zero_e_o_json_nao_afirma_isso() {
        let t = Trama::open(arquivo_novo("custo-ausente"));
        t.append(ev("codex-1", Kind::TurnStarted));
        t.append(ev("codex-1", Kind::TurnEnded));
        let st = &t.state()[0];
        assert_eq!(st.usd, 0.0);
        let j = serde_json::to_string(st).unwrap();
        assert!(
            !j.contains("\"usd\""),
            "custo zero deve ser OMITIDO, não afirmado como 0.0: {j}"
        );
    }

    #[test]
    fn json_com_custo_inclui_usd() {
        let t = Trama::open(arquivo_novo("custo-json"));
        t.append(ev("codex-1", Kind::TurnStarted));
        t.append(usage("codex-1", 0.42));
        let j = serde_json::to_string(&t.state()[0]).unwrap();
        assert!(j.contains("\"usd\":0.42"), "{j}");
    }
}
