//! Cliente ACP — Agent Client Protocol.
//!
//! 🚨 A INVERSÃO IMPORTA: o adaptador (`claude-agent-acp`, Node) é o SERVIDOR; o loomd é o
//! CLIENTE. É o papel que o Zed ocupa, e foi ele que motivou trocar `stream-json` por protocolo
//! aberto: ACP é UMA tradução para N agentes (Codex e Gemini também têm adaptador), enquanto
//! `stream-json` seria o segundo dialeto artesanal deste crate.
//!
//! Enquadramento: ND-JSON, uma mensagem por linha. Não há `Content-Length`.

use crate::event::{AgentEvent, Confidence, Kind};
use crate::trama::Trama;
use std::collections::HashMap;
use std::process::Stdio;
use std::sync::Arc;
use tokio::io::{AsyncBufReadExt, AsyncWriteExt, BufReader};
use tokio::sync::{oneshot, Mutex};

const ID_INIT: u64 = 1;
const ID_SESSAO: u64 = 2;
const ID_MODO: u64 = 3;

pub struct AcpLane {
    pub lane: String,
    stdin: Arc<Mutex<Option<tokio::process::ChildStdin>>>,
    /// Aprovações penduradas: id JSON-RPC → quem espera a decisão do operador.
    pending: Arc<Mutex<HashMap<String, oneshot::Sender<String>>>>,
    sessao: Arc<Mutex<Option<String>>>,
    proximo_id: Arc<Mutex<u64>>,
    trama: Arc<Trama>,
    modo: String,
    cwd: String,
}

/// Parte um bloco cru em mensagens. Linha vazia é ignorada; linha ilegível é DESCARTADA e não
/// derruba nada — regra já vigente no `codex.rs`, porque o vocabulário cresce e o transporte
/// pode intercalar ruído. Cegueira total é pior que informação parcial.
pub fn linhas_ndjson(bruto: &str) -> Vec<serde_json::Value> {
    bruto
        .lines()
        .map(str::trim)
        .filter(|l| !l.is_empty())
        .filter_map(|l| serde_json::from_str(l).ok())
        .collect()
}

/// As mensagens de abertura, em ordem. **Função pura de propósito**: é o único jeito de assertar
/// que o `session/set_mode` está lá sem subir um Node. Ver o teste da mutação 1.
pub fn mensagens_de_abertura(
    sessao: Option<&str>,
    modo: &str,
    cwd: &str,
) -> Vec<serde_json::Value> {
    // `fs/*` FALSO de propósito: medido no censo que o agente nunca chamou `fs/read_text_file`
    // — ele usa a ferramenta `Read` dele. A capacidade serve a editor com buffer sujo, que não é
    // o nosso caso, e prometer o que não se usa é dívida.
    let mut v = vec![serde_json::json!({
        "jsonrpc": "2.0", "id": ID_INIT, "method": "initialize",
        "params": {
            "protocolVersion": 1,
            "clientCapabilities": {"fs": {"readTextFile": false, "writeTextFile": false}}
        }
    })];
    match sessao {
        Some(sid) => {
            v.push(serde_json::json!({
                "jsonrpc":"2.0","id":ID_SESSAO,"method":"session/load",
                "params":{"sessionId": sid, "cwd": cwd, "mcpServers": []}
            }));
            // Sessão conhecida: o modo já pode ir junto. Sem sessão, ele vai quando a resposta
            // do `session/new` trouxer o id — em `on_message`.
            v.push(serde_json::json!({
                "jsonrpc":"2.0","id":ID_MODO,"method":"session/set_mode",
                "params":{"sessionId": sid, "modeId": modo}
            }));
        }
        None => v.push(serde_json::json!({
            "jsonrpc":"2.0","id":ID_SESSAO,"method":"session/new",
            "params":{"cwd": cwd, "mcpServers": []}
        })),
    }
    v
}

impl AcpLane {
    pub fn spawn(lane: &str, bin: &str, cwd: &str, modo: &str, trama: Arc<Trama>) -> Arc<Self> {
        // A sessão vem da TRAMA na subida fria, igual ao codex: o daemon é descartável, a
        // sessão não. `session/load` é capacidade anunciada (`loadSession: true`), então
        // retomar é chamada de protocolo e não heurística.
        let s0 = trama.session_of(lane);
        if let Some(s) = &s0 {
            eprintln!("[loomd] lane {lane}: sessao ACP anotada na trama, vou carregar: {s}");
        }
        let me = Arc::new(Self {
            lane: lane.to_string(),
            stdin: Arc::new(Mutex::new(None)),
            pending: Arc::new(Mutex::new(HashMap::new())),
            sessao: Arc::new(Mutex::new(s0)),
            proximo_id: Arc::new(Mutex::new(10)),
            trama: trama.clone(),
            modo: modo.to_string(),
            cwd: cwd.to_string(),
        });
        let (b, c) = (bin.to_string(), cwd.to_string());
        let this = me.clone();
        crate::supervisao::supervisionar(lane.to_string(), trama, move || {
            let (this, b, c) = (this.clone(), b.clone(), c.clone());
            async move { this.run_once(&b, &c).await }
        });
        me
    }

    pub async fn session_id(&self) -> Option<String> {
        self.sessao.lock().await.clone()
    }

    async fn enviar(&self, v: serde_json::Value) {
        let mut g = self.stdin.lock().await;
        if let Some(si) = g.as_mut() {
            let _ = si.write_all(format!("{v}\n").as_bytes()).await;
            let _ = si.flush().await;
        }
    }

    async fn run_once(&self, bin: &str, cwd: &str) -> std::io::Result<()> {
        let mut child = tokio::process::Command::new(bin)
            .current_dir(cwd)
            .stdin(Stdio::piped())
            .stdout(Stdio::piped())
            .stderr(Stdio::null())
            .kill_on_drop(true)
            .spawn()?;
        let out = child.stdout.take().expect("stdout pipe");
        *self.stdin.lock().await = child.stdin.take();

        // O handshake vem da função PURA — é ela que o teste da mutação 1 asserta. Montar as
        // mensagens aqui dentro tornaria o `set_mode` inassertável sem subir um Node.
        let sid0 = self.sessao.lock().await.clone();
        for m in mensagens_de_abertura(sid0.as_deref(), &self.modo, cwd) {
            self.enviar(m).await;
        }

        let mut lines = BufReader::new(out).lines();
        while let Some(line) = lines.next_line().await? {
            if line.trim().is_empty() {
                continue;
            }
            if std::env::var("LOOMD_DEBUG").is_ok() {
                eprintln!("[acp rx] {}", &line.chars().take(220).collect::<String>());
            }
            let Ok(m) = serde_json::from_str::<serde_json::Value>(&line) else {
                continue;
            };
            self.on_message(m).await;
        }

        let _ = child.wait().await;
        *self.stdin.lock().await = None;
        self.cancelar_pendentes("adaptador ACP encerrou").await;
        self.trama.append(
            AgentEvent::new(&self.lane, Kind::SessionEnded, Confidence::Exact)
                .detail("adaptador ACP encerrou"),
        );
        Ok(())
    }

    async fn on_message(&self, m: serde_json::Value) {
        // Resposta ao `session/new` / `session/load`: guarda a sessão e FIXA O MODO.
        if m.get("id").and_then(|x| x.as_u64()) == Some(ID_SESSAO) {
            if let Some(sid) = m.pointer("/result/sessionId").and_then(|x| x.as_str()) {
                *self.sessao.lock().await = Some(sid.to_string());
                let mut e = AgentEvent::new(&self.lane, Kind::SessionStarted, Confidence::Exact)
                    .detail(format!("sessao ACP {sid}"));
                e.session = Some(sid.to_string());
                self.trama.append(e);
                self.fixar_modo(sid).await;
            }
            return;
        }
        let _ = self.traduzir(&m).await;
    }

    /// 🚨 SEM ISTO A TABELA DE APROVAÇÃO É CÓDIGO MORTO.
    ///
    /// Medido: `session/new` devolve `currentModeId: "bypassPermissions"`, e nesse modo o
    /// `session/request_permission` NÃO DISPARA UMA VEZ — o próprio SDK avisa no stderr que
    /// `canUseTool` fica sombreado. Escrito por dedução, a tela de aprovação ficaria vazia e a
    /// conclusão seria "o ACP não emite permissão".
    async fn fixar_modo(&self, sid: &str) {
        self.enviar(serde_json::json!({
            "jsonrpc":"2.0","id":ID_MODO,"method":"session/set_mode",
            "params":{"sessionId": sid, "modeId": self.modo}
        }))
        .await;
    }

    /// Preenchida na Task 4.
    async fn traduzir(&self, _m: &serde_json::Value) -> Option<()> {
        None
    }

    /// Preenchida na Task 5.
    async fn cancelar_pendentes(&self, _motivo: &str) {}
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn ndjson_parte_por_linha_e_ignora_ruido() {
        let bruto = "{\"a\":1}\n\n nao e json \n{\"b\":2}\n";
        let v = linhas_ndjson(bruto);
        assert_eq!(
            v.len(),
            2,
            "duas mensagens legiveis, o ruido nao conta e nao mata"
        );
        assert_eq!(v[0]["a"], 1);
        assert_eq!(v[1]["b"], 2);
    }

    #[test]
    fn ndjson_vazio_nao_produz_nada() {
        assert!(linhas_ndjson("").is_empty());
        assert!(linhas_ndjson("\n\n\n").is_empty());
    }

    /// 🚨 A MUTAÇÃO 1 DO SPEC, fechada por teste unitário e não só pela prova ao vivo.
    ///
    /// O adaptador nasce em `bypassPermissions`; nesse modo `session/request_permission` não
    /// dispara nenhuma vez. Se alguém remover o `set_mode`, TODA a tabela de aprovação vira
    /// código morto e a única evidência seria uma tela vazia — que se lê como "o ACP não pede
    /// permissão". O handshake é função PURA justamente para que isso seja assertável.
    #[test]
    fn o_handshake_manda_set_mode_e_ele_e_o_ultimo() {
        let ms = mensagens_de_abertura(Some("sess-1"), "default", "/workspace/.wt/claude-4");
        let metodos: Vec<&str> = ms
            .iter()
            .map(|m| m["method"].as_str().unwrap_or(""))
            .collect();
        assert_eq!(
            metodos,
            vec!["initialize", "session/load", "session/set_mode"]
        );
        let sm = ms.last().unwrap();
        assert_eq!(sm["params"]["modeId"], "default");
        assert_eq!(sm["params"]["sessionId"], "sess-1");
    }

    #[test]
    fn sem_sessao_conhecida_o_handshake_abre_uma_nova() {
        let ms = mensagens_de_abertura(None, "auto", "/workspace/.wt/claude-4");
        let metodos: Vec<&str> = ms
            .iter()
            .map(|m| m["method"].as_str().unwrap_or(""))
            .collect();
        // Sem sessão ainda não há `sessionId` para o `set_mode`: ele vai quando a resposta
        // do `session/new` chegar. Duas mensagens aqui, e a segunda é `session/new`.
        assert_eq!(metodos, vec!["initialize", "session/new"]);
        assert_eq!(ms[1]["params"]["cwd"], "/workspace/.wt/claude-4");
    }

    #[test]
    fn fs_e_declarado_falso_porque_o_agente_nunca_chama() {
        let ms = mensagens_de_abertura(None, "default", "/tmp");
        let caps = &ms[0]["params"]["clientCapabilities"]["fs"];
        assert_eq!(caps["readTextFile"], false);
        assert_eq!(caps["writeTextFile"], false);
    }
}
