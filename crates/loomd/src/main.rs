//! loomd — supervisor de sessões de agente. NÃO é um multiplexer de terminal.
//!
//! Um multiplexer resolve o problema de 1984: muitas telas, um monitor. O problema aqui é de
//! 2026: **muitas sessões de agente, uma atenção**. Sessões têm estrutura — turnos, chamadas de
//! ferramenta, diffs propostos, pedidos de aprovação. O terminal é uma projeção COM PERDA dessa
//! estrutura, e raspar a tela é reconstruir o que o agente já sabia e destruiu ao desenhar.
//!
//! Duas fontes, um vocabulário:
//!   * **Codex** — `app-server` por JSON-RPC. Somos donos do processo; em troca, o estado vem
//!     como enum (`waitingOnApproval`) e a aprovação é RPC.
//!   * **Claude** — hooks HTTP. **Não** somos donos do processo: é configuração, e por isso
//!     alcança lane que já estava rodando.
//!
//! Persistência na camada certa: o tmux persiste PIXELS (depois de um restart do pod ele te dá
//! um scrollback morto). Aqui o diário guarda o que ACONTECEU e a sessão do agente é retomada
//! pelo id no store do próprio CLI. É isso que torna este daemon descartável de propósito.
mod acp;
mod codex;
mod event;
mod supervisao;
mod trama;
mod transcript;

use axum::{
    extract::{Path, Query, State},
    routing::{get, post},
    Json, Router,
};
use std::collections::HashMap;
use std::sync::Arc;
use trama::Trama;

/// Qual semântica o `/steer` aplicou. O operador precisa saber: redirecionar o turno em curso e
/// enfileirar para depois são coisas diferentes, e só o codex faz a primeira.
pub fn rotulo_de_steer(redireciona: bool) -> &'static str {
    if redireciona {
        "redirecionado"
    } else {
        "enfileirado"
    }
}

/// As duas classes de lane supervisionada. Enum e não trait: são exatamente duas, os métodos
/// são quatro, e um trait com `async fn` aqui só acrescentaria `Box<dyn>` e ruído.
#[derive(Clone)]
enum LaneHandle {
    Codex(Arc<codex::CodexLane>),
    Acp(Arc<acp::AcpLane>),
}

impl LaneHandle {
    async fn prompt(&self, t: &str) -> Result<(), String> {
        match self {
            LaneHandle::Codex(l) => l.prompt(t).await,
            LaneHandle::Acp(l) => l.prompt(t).await,
        }
    }
    async fn interrupt(&self) -> Result<(), String> {
        match self {
            LaneHandle::Codex(l) => l.interrupt().await,
            LaneHandle::Acp(l) => l.interrupt().await,
        }
    }
    /// Devolve `true` quando REDIRECIONOU o turno; `false` quando só enfileirou.
    async fn steer(&self, t: &str) -> Result<bool, String> {
        match self {
            LaneHandle::Codex(l) => l.steer(t).await.map(|_| true),
            LaneHandle::Acp(l) => l.enfileirar(t).await.map(|_| false),
        }
    }
    async fn answer(&self, id: &str, allow: bool) -> Result<(), String> {
        match self {
            LaneHandle::Codex(l) => l.answer(id, allow).await,
            LaneHandle::Acp(l) => l.answer(id, allow).await,
        }
    }
}

#[derive(Clone)]
struct App {
    trama: Arc<Trama>,
    lanes: Arc<HashMap<String, LaneHandle>>,
}

#[tokio::main]
async fn main() {
    let addr = std::env::var("LOOMD_ADDR").unwrap_or_else(|_| "127.0.0.1:4400".into());
    let jsonl =
        std::env::var("LOOMD_TRAMA").unwrap_or_else(|_| "/workspace/.loomd/trama.jsonl".into());
    let bin = std::env::var("LOOMD_CODEX_BIN").unwrap_or_else(|_| "codex".into());
    let cwd = std::env::var("LOOMD_CWD").unwrap_or_else(|_| "/workspace/sounio".into());
    let cargs: Vec<String> = std::env::var("LOOMD_CODEX_ARGS")
        .unwrap_or_default()
        .split_whitespace()
        .map(str::to_string)
        .collect();
    // Vazio por padrão: o daemon não adota lane nenhuma sem alguém mandar.
    //
    // 🚨 CWD POR LANE, e o motivo é concreto: `LOOMD_CWD` era global, então duas lanes
    // supervisionadas trabalhariam no MESMO diretório — exatamente o hazard "mesma árvore" que a
    // Frota existe para avisar, e que aqui eu criaria de dentro. Uma edição de uma seria
    // sobrescrita pela outra sem conflito de git para denunciar.
    //
    // Forma: `lane[:cwd]`, separado por vírgula. Sem `:`, cai no `LOOMD_CWD` — o que mantém a
    // configuração de uma lane só exatamente como era.
    //   LOOMD_CODEX_LANES="loom-1:/workspace/.wt/loom-1,codex-4:/workspace/.wt/codex-4"
    let lanes = parse_lanes(
        &std::env::var("LOOMD_CODEX_LANES").unwrap_or_default(),
        &cwd,
    );

    let trama = Arc::new(Trama::open(&jsonl));
    let mut map = HashMap::new();
    for (l, c) in &lanes {
        eprintln!("[loomd] lane {l} em {c}");
        // Declara ANTES de subir: uma lane que o daemon supervisiona precisa existir no board
        // mesmo antes do primeiro turno, senão a adoção parece ter falhado.
        trama.declarar(l);
        map.insert(
            l.clone(),
            LaneHandle::Codex(codex::CodexLane::spawn(
                l,
                &bin,
                c,
                cargs.clone(),
                trama.clone(),
            )),
        );
    }

    // Lanes ACP: mesma forma `lane[:cwd]` do codex, variável própria.
    //   LOOMD_ACP_LANES="claude-4:/workspace/.wt/claude-4"
    let acp_bin = std::env::var("LOOMD_ACP_BIN").unwrap_or_else(|_| "claude-agent-acp".into());
    // O modo vem da Task 1 do plano — MEDIDO, não escolhido pela descrição.
    let acp_modo = std::env::var("LOOMD_ACP_MODO").unwrap_or_else(|_| "default".into());
    let acp_lanes = parse_lanes(&std::env::var("LOOMD_ACP_LANES").unwrap_or_default(), &cwd);
    for (l, c) in &acp_lanes {
        eprintln!("[loomd] lane ACP {l} em {c} (modo {acp_modo})");
        trama.declarar(l);
        map.insert(
            l.clone(),
            LaneHandle::Acp(acp::AcpLane::spawn(
                l,
                &acp_bin,
                c,
                &acp_modo,
                trama.clone(),
            )),
        );
    }

    // Observação read-only das lanes TUI. Forma `lane:dir-de-projetos`, vírgula entre elas.
    //   LOOMD_TAILS="claude-1:/workspace/.home/openvscode-server/.agents/claude-1/.claude/projects/-workspace-sounio,…"
    for (l, d) in parse_lanes(&std::env::var("LOOMD_TAILS").unwrap_or_default(), "") {
        if d.is_empty() {
            eprintln!("[loomd] tail {l} SEM diretorio — ignorado");
            continue;
        }
        eprintln!("[loomd] tail {l} em {d}");
        trama.declarar(&l);
        transcript::TranscriptTail::spawn(&l, &d, trama.clone());
    }

    let app_state = App {
        trama: trama.clone(),
        lanes: Arc::new(map),
    };

    let app = Router::new()
        .route("/livez", get(|| async { "ok" }))
        // O Claude liga de volta aqui. A lane vai no caminho porque o hook não sabe o nosso
        // nome para ela — só o `session_id` dele.
        .route("/hooks/claude/:lane", post(hook_claude))
        .route("/v2/state", get(state))
        .route("/v2/trama", get(since))
        .route("/v2/lanes/:lane/approve", post(approve))
        .route("/v2/lanes/:lane/prompt", post(prompt))
        .route("/v2/lanes/:lane/interrupt", post(interrupt))
        .route("/v2/lanes/:lane/steer", post(steer))
        .with_state(app_state);

    eprintln!("[loomd] {addr} · trama={jsonl} · lanes codex: {lanes:?}");
    let listener = tokio::net::TcpListener::bind(&addr).await.expect("bind");
    axum::serve(listener, app).await.expect("serve");
}

/// Resposta 2xx com corpo vazio = "não interfira". Bloquear tem forma própria
/// (`hookSpecificOutput`) e não é o que a fatia 1 faz: aqui só OBSERVAMOS o Claude.
/// Responder não-2xx seria erro não-bloqueante para o CLI, mas polui o log dele à toa.
async fn hook_claude(
    State(a): State<App>,
    Path(lane): Path<String>,
    Json(body): Json<serde_json::Value>,
) -> Json<serde_json::Value> {
    a.trama.append(event::from_claude_hook(&lane, &body));
    Json(serde_json::json!({}))
}

async fn state(State(a): State<App>) -> Json<serde_json::Value> {
    Json(serde_json::json!({
        "ok": true,
        "observed_at_ms": event::now_ms(),
        "lanes": a.trama.state(),
    }))
}

#[derive(serde::Deserialize)]
struct SinceQ {
    since: Option<u64>,
    lane: Option<String>,
}

async fn since(State(a): State<App>, Query(q): Query<SinceQ>) -> Json<serde_json::Value> {
    let events = a.trama.since(q.since.unwrap_or(0), q.lane.as_deref());
    Json(serde_json::json!({ "ok": true, "events": events }))
}

#[derive(serde::Deserialize)]
struct ApproveBody {
    #[serde(default = "yes")]
    allow: bool,
}
fn yes() -> bool {
    true
}

/// Aprovar SEM ANEXAR. Nenhum cliente tmux é criado, então o pane que o agente (e o cmux dele)
/// está vendo não muda de tamanho. E o veredito usa o enum certo da família — ver
/// `event::codex_approval_reply`, que existe por causa de um "aprovado" que não aprovava.
async fn approve(
    State(a): State<App>,
    Path(lane): Path<String>,
    Json(b): Json<ApproveBody>,
) -> (axum::http::StatusCode, Json<serde_json::Value>) {
    let Some(l) = a.lanes.get(&lane) else {
        return err(
            axum::http::StatusCode::NOT_FOUND,
            format!("lane {lane} não é supervisionada pelo loomd"),
        );
    };
    let Some((id, method)) = a.trama.pending(&lane) else {
        return err(
            axum::http::StatusCode::CONFLICT,
            format!("a lane {lane} não está esperando aprovação"),
        );
    };
    match l.answer(&id, b.allow).await {
        Ok(()) => (
            axum::http::StatusCode::OK,
            Json(serde_json::json!({"ok": true, "lane": lane, "method": method, "allow": b.allow})),
        ),
        Err(e) => err(axum::http::StatusCode::CONFLICT, e),
    }
}

#[derive(serde::Deserialize)]
struct PromptBody {
    text: String,
}

/// Dirigir a lane sem terminal: texto entra por HTTP, o turno acontece, e tudo que ele fizer
/// volta pela trama como evento tipado.
/// `LOOMD_CODEX_LANES` → pares (lane, cwd).
///
/// 🚨 CWD POR LANE, e o motivo é concreto: `LOOMD_CWD` era global, então duas lanes supervisionadas
/// trabalhariam no MESMO diretório — exatamente o hazard "mesma árvore" que a Frota existe para
/// avisar, e que aqui eu criaria de dentro. Uma edição de uma seria sobrescrita pela outra sem
/// conflito de git para denunciar.
///
/// Forma: `lane[:cwd]`, separado por vírgula. Sem `:`, cai no padrão — o que mantém a configuração
/// de uma lane só exatamente como era antes desta mudança.
///   "loom-1:/workspace/.wt/loom-1,codex-4:/workspace/.wt/codex-4"
pub fn parse_lanes(spec: &str, padrao: &str) -> Vec<(String, String)> {
    spec.split(',')
        .map(str::trim)
        .filter(|s| !s.is_empty())
        .map(|s| match s.split_once(':') {
            Some((l, c)) if !c.trim().is_empty() => (l.trim().to_string(), c.trim().to_string()),
            // `lane:` com cwd vazio é erro de digitação, não pedido de cwd vazio — cai no padrão,
            // que é o comportamento seguro. Um cwd vazio faria o `current_dir` do processo
            // depender de onde o daemon subiu.
            _ => (
                s.trim_end_matches(':').trim().to_string(),
                padrao.to_string(),
            ),
        })
        .filter(|(l, _)| !l.is_empty())
        .collect()
}

/// Parar o turno em curso. 409 quando não há turno — pedir para interromper uma lane parada é
/// erro do chamador, e o motivo tem que dizer isso em vez de um 500 genérico.
async fn interrupt(
    State(a): State<App>,
    Path(lane): Path<String>,
) -> (axum::http::StatusCode, Json<serde_json::Value>) {
    let Some(l) = a.lanes.get(&lane) else {
        return err(
            axum::http::StatusCode::NOT_FOUND,
            format!("lane {lane} não é supervisionada pelo loomd"),
        );
    };
    match l.interrupt().await {
        Ok(()) => (
            axum::http::StatusCode::ACCEPTED,
            Json(serde_json::json!({"ok":true,"lane":lane})),
        ),
        Err(e) => err(axum::http::StatusCode::CONFLICT, e),
    }
}

/// GUIAR o turno em curso sem matá-lo — acrescenta instrução ao que já está correndo.
/// É mais barato que interromper: interromper joga fora o trabalho já feito.
async fn steer(
    State(a): State<App>,
    Path(lane): Path<String>,
    Json(b): Json<PromptBody>,
) -> (axum::http::StatusCode, Json<serde_json::Value>) {
    let Some(l) = a.lanes.get(&lane) else {
        return err(
            axum::http::StatusCode::NOT_FOUND,
            format!("lane {lane} não é supervisionada pelo loomd"),
        );
    };
    if b.text.trim().is_empty() {
        return err(
            axum::http::StatusCode::BAD_REQUEST,
            "guiar exige texto".to_string(),
        );
    }
    match l.steer(&b.text).await {
        Ok(redirecionou) => (
            axum::http::StatusCode::ACCEPTED,
            Json(serde_json::json!({
                "ok": true, "lane": lane, "efeito": rotulo_de_steer(redirecionou)
            })),
        ),
        Err(e) => err(axum::http::StatusCode::CONFLICT, e),
    }
}

async fn prompt(
    State(a): State<App>,
    Path(lane): Path<String>,
    Json(b): Json<PromptBody>,
) -> (axum::http::StatusCode, Json<serde_json::Value>) {
    let Some(l) = a.lanes.get(&lane) else {
        return err(
            axum::http::StatusCode::NOT_FOUND,
            format!("lane {lane} não é supervisionada pelo loomd"),
        );
    };
    // 202: aceito. O turno acontece de forma assíncrona e TUDO que ele fizer aparece na trama —
    // é lá que se acompanha, não no corpo desta resposta.
    match l.prompt(&b.text).await {
        Ok(()) => (
            axum::http::StatusCode::ACCEPTED,
            Json(serde_json::json!({"ok":true,"lane":lane})),
        ),
        Err(e) => err(axum::http::StatusCode::BAD_GATEWAY, e),
    }
}

fn err(
    code: axum::http::StatusCode,
    msg: String,
) -> (axum::http::StatusCode, Json<serde_json::Value>) {
    (code, Json(serde_json::json!({"ok": false, "error": msg})))
}

#[cfg(test)]
mod tests {
    use super::parse_lanes;
    use crate::trama::Trama;
    use std::sync::Arc;

    /// 🚨 `/steer` NÃO tem a mesma semântica nas duas classes de lane. No codex,
    /// `turn/steer` REDIRECIONA o turno em curso. O ACP não tem isso: ele anuncia
    /// `promptQueueing: true`, ou seja, outro prompt ENFILEIRA para depois.
    ///
    /// Semântica diferente sob o mesmo nome é armadilha. A resposta da rota tem de dizer qual
    /// das duas aconteceu, senão a tela mente para o operador.
    #[test]
    fn steer_declara_qual_semantica_aplicou() {
        assert_eq!(super::rotulo_de_steer(true), "redirecionado");
        assert_eq!(super::rotulo_de_steer(false), "enfileirado");
    }

    #[tokio::test]
    async fn steer_na_lane_acp_reporta_enfileirado() {
        let dir = std::env::temp_dir().join(format!("loomd-steer-{}", std::process::id()));
        std::fs::create_dir_all(&dir).unwrap();
        let t = Arc::new(Trama::open(dir.join("trama.jsonl")));
        let lane = crate::acp::AcpLane::nua_para_teste("claude-4", t, "default", Some("sess-1"));
        // 🚨 Pós-achado-4: `enviar` propaga a AUSÊNCIA de stdin como erro — correto, mas isso
        // deixaria de exercitar o que este teste quer provar (a semântica do DESPACHO: ACP
        // enfileira, nunca redireciona). Por isso pluga um stdin de verdade (subprocesso `cat`)
        // para a escrita ter sucesso, e a asserção testar o rótulo, não a entrega.
        let mut filho = tokio::process::Command::new("cat")
            .stdin(std::process::Stdio::piped())
            .stdout(std::process::Stdio::null())
            .stderr(std::process::Stdio::null())
            .spawn()
            .expect("cat tem de existir para este teste");
        lane.plugar_stdin_para_teste(filho.stdin.take().unwrap())
            .await;

        let h = super::LaneHandle::Acp(lane);
        // COM sessão E stdin: `enfileirar` chega a `Ok(())`, então o despacho tem de devolver
        // `Ok(false)` — asserção EXATA. A versão frouxa deste teste (`Err(_) | Ok(false)`)
        // passava com qualquer coisa menos `Ok(true)`, o que é quase não assertar nada.
        assert_eq!(
            h.steer("oi").await,
            Ok(false),
            "lane ACP ENFILEIRA, nunca redireciona"
        );
        let _ = filho.kill().await;
        std::fs::remove_dir_all(&dir).ok();
    }

    #[test]
    fn uma_lane_sem_cwd_continua_usando_o_padrao() {
        // A configuração que já existia não pode mudar de sentido por causa desta feature.
        assert_eq!(
            parse_lanes("loom-1", "/workspace/sounio"),
            vec![("loom-1".to_string(), "/workspace/sounio".to_string())]
        );
    }

    #[test]
    fn cada_lane_ganha_o_seu_diretorio() {
        // O ponto da mudança: duas lanes no mesmo cwd é o hazard "mesma árvore", criado de dentro.
        assert_eq!(
            parse_lanes(
                "loom-1:/workspace/.wt/loom-1, codex-4:/workspace/.wt/codex-4",
                "/padrao"
            ),
            vec![
                ("loom-1".to_string(), "/workspace/.wt/loom-1".to_string()),
                ("codex-4".to_string(), "/workspace/.wt/codex-4".to_string()),
            ]
        );
    }

    #[test]
    fn entrada_torta_nao_produz_lane_torta() {
        // Vazios, espaço sobrando e `lane:` sem caminho. `lane:` é erro de digitação, não pedido de
        // cwd vazio: um cwd vazio faria o `current_dir` do processo depender de onde o daemon subiu.
        assert_eq!(parse_lanes("", "/p"), vec![]);
        assert_eq!(parse_lanes(" , ,, ", "/p"), vec![]);
        assert_eq!(
            parse_lanes("a:,  b : /x  ,:", "/p"),
            vec![
                ("a".to_string(), "/p".to_string()),
                ("b".to_string(), "/x".to_string())
            ]
        );
    }
}
