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
mod codex;
mod event;
mod supervisao;
mod trama;

use axum::{
    extract::{Path, Query, State},
    routing::{get, post},
    Json, Router,
};
use std::collections::HashMap;
use std::sync::Arc;
use trama::Trama;

#[derive(Clone)]
struct App {
    trama: Arc<Trama>,
    codex: Arc<HashMap<String, Arc<codex::CodexLane>>>,
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
            codex::CodexLane::spawn(l, &bin, c, cargs.clone(), trama.clone()),
        );
    }
    let app_state = App {
        trama: trama.clone(),
        codex: Arc::new(map),
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
    let Some(l) = a.codex.get(&lane) else {
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
    let Some(l) = a.codex.get(&lane) else {
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
    let Some(l) = a.codex.get(&lane) else {
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
        Ok(()) => (
            axum::http::StatusCode::ACCEPTED,
            Json(serde_json::json!({"ok":true,"lane":lane})),
        ),
        Err(e) => err(axum::http::StatusCode::CONFLICT, e),
    }
}

async fn prompt(
    State(a): State<App>,
    Path(lane): Path<String>,
    Json(b): Json<PromptBody>,
) -> (axum::http::StatusCode, Json<serde_json::Value>) {
    let Some(l) = a.codex.get(&lane) else {
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
