//! Supervisão de uma lane do Codex pelo `app-server` — JSON-RPC por stdio, sem TTY.
//!
//! Aqui somos donos do processo, e em troca ganhamos o estado como enum e a aprovação como RPC.
//! O contrário da lane do Claude, que chega por hook HTTP sem sermos donos de nada.
//!
//! **Orçamento declarado** (cláusula do Fable): se o ANDAIME DE SUPERVISÃO — spawn, reinício,
//! vivacidade — passar de ~500 linhas, ou aparecer um segundo bug de vivacidade em review, a
//! evidência empírica venceu e o `loomd` se reescreve em Elixir/OTP antes da lane 2 migrar.
//! Este arquivo é o lugar onde essa conta é feita.
use crate::event::{codex_approval_reply, from_codex_notification, thread_id, AgentEvent, Confidence, Kind};
use crate::trama::Trama;
use std::collections::HashMap;
use std::process::Stdio;
use std::sync::Arc;
use tokio::io::{AsyncBufReadExt, AsyncWriteExt, BufReader};
use tokio::sync::{oneshot, Mutex};

/// Aprovações que o agente nos manda e que ainda não respondemos.
/// A chave é o id da requisição JSON-RPC; o valor devolve o veredito para o writer.
type Pending = Arc<Mutex<HashMap<String, (String, oneshot::Sender<serde_json::Value>)>>>;

/// Id JSON-RPC do `thread/resume`. Fixo porque a RESPOSTA precisa ser reconhecível: é ela que
/// diz se a thread anotada ainda existe no store do Codex.
const ID_RESUME: i64 = 2;

pub struct CodexLane {
    pub lane: String,
    stdin: Arc<Mutex<Option<tokio::process::ChildStdin>>>,
    pending: Pending,
    trama: Arc<Trama>,
    /// A thread viva desta lane. É ela que `thread/resume` retoma depois de um restart —
    /// a sessão vive no store do Codex, não aqui. Por isso este daemon é descartável.
    thread: Arc<Mutex<Option<String>>>,
    cwd: String,
}

impl CodexLane {
    /// Sobe a lane e a mantém viva. O supervisor reinicia o filho quando ele morre; a SESSÃO
    /// não se perde nisso, porque quem a guarda é o store do próprio Codex (`thread/resume`).
    /// É por isso que este daemon pode ser descartável.
    pub fn spawn(lane: &str, bin: &str, cwd: &str, args: Vec<String>, trama: Arc<Trama>) -> Arc<Self> {
        // 🚨 A SUBIDA FRIA. Até 09-ago-2026 o id da thread nascia `None`: o `thread/resume`
        // abaixo só cobria a morte do app-server FILHO com o daemon vivo. Reiniciado o daemon,
        // a lane abria sessão NOVA — sem contexto — e a anterior ficava órfã no store do Codex.
        // O id vem da trama, que agora se relê ao abrir; nenhum arquivo de estado novo.
        let thread0 = trama.session_of(lane);
        if let Some(t) = &thread0 {
            eprintln!("[loomd] lane {lane}: thread anotada na trama, vou retomar: {t}");
        }
        let me = Arc::new(Self {
            lane: lane.to_string(),
            stdin: Arc::new(Mutex::new(None)),
            pending: Arc::new(Mutex::new(HashMap::new())),
            trama,
            thread: Arc::new(Mutex::new(thread0)),
            cwd: cwd.to_string(),
        });
        let (l, b, c, a) = (lane.to_string(), bin.to_string(), cwd.to_string(), args);
        let this = me.clone();
        tokio::spawn(async move {
            let mut backoff_ms = 500u64;
            loop {
                match this.run_once(&b, &c, &a).await {
                    Ok(()) => backoff_ms = 500,
                    Err(e) => {
                        this.trama.append(
                            AgentEvent::new(&l, Kind::Error, Confidence::Exact)
                                .detail(format!("app-server caiu: {e}")),
                        );
                    }
                }
                // Teto baixo de propósito: uma lane que não sobe tem que reaparecer no board
                // rápido, não sumir por dez minutos de backoff exponencial.
                tokio::time::sleep(std::time::Duration::from_millis(backoff_ms)).await;
                backoff_ms = (backoff_ms * 2).min(15_000);
            }
        });
        me
    }

    async fn run_once(&self, bin: &str, cwd: &str, extra: &[String]) -> std::io::Result<()> {
        // `-c chave=valor` do codex entra ANTES do subcomando. É por aqui que passam a política
        // de aprovação e o `model_reasoning_effort` — o config das lanes usa `max`, que a
        // versão instalada não conhece (`unknown variant 'max'`) e quebra o cache de modelos.
        let mut argv: Vec<String> = extra.to_vec();
        argv.extend(["app-server".into(), "--listen".into(), "stdio://".into()]);
        let mut child = tokio::process::Command::new(bin)
            .args(&argv)
            .current_dir(cwd)
            .stdin(Stdio::piped())
            .stdout(Stdio::piped())
            .stderr(Stdio::null())
            .kill_on_drop(true)
            .spawn()?;

        let out = child.stdout.take().expect("stdout pipe");
        *self.stdin.lock().await = child.stdin.take();

        self.send(serde_json::json!({
            "jsonrpc": "2.0", "id": 1, "method": "initialize",
            "params": {"clientInfo": {"name": "loomd", "title": "Loom", "version": "0.1.0"}}
        }))
        .await;

        // ISTO é a tese inteira em três linhas: se já conhecemos a thread, RETOMAMOS.
        // O tmux persiste PIXELS — depois de um restart ele te devolve um scrollback morto.
        // Aqui a sessão vive no store do próprio Codex e volta COM CONTEXTO. É por isso que
        // este daemon pode morrer sem que o trabalho morra junto.
        if let Some(tid) = self.thread.lock().await.clone() {
            self.send(serde_json::json!({
                "jsonrpc":"2.0","id":ID_RESUME,"method":"thread/resume",
                "params": {"threadId": tid, "cwd": cwd}
            }))
            .await;
            self.trama.append(
                AgentEvent::new(&self.lane, Kind::SessionStarted, Confidence::Exact)
                    .detail(format!("thread retomada por id: {tid}")),
            );
        }

        let mut lines = BufReader::new(out).lines();
        while let Some(line) = lines.next_line().await? {
            if line.trim().is_empty() {
                continue;
            }
            // Linha ilegível é registrada, nunca fatal: o vocabulário cresce e o transporte
            // pode intercalar ruído. Derrubar a supervisão por isso seria trocar informação
            // parcial por cegueira total.
            // LOOMD_DEBUG=1 despeja o fio cru. Existe porque, ao depurar, eu estava deduzindo
            // a forma da mensagem em vez de olhar — e errei duas vezes seguidas.
            if std::env::var("LOOMD_DEBUG").is_ok() {
                eprintln!("[rx] {}", &line.chars().take(220).collect::<String>());
            }
            let Ok(m) = serde_json::from_str::<serde_json::Value>(&line) else {
                continue;
            };
            self.on_message(m).await;
        }
        let _ = child.wait().await;
        *self.stdin.lock().await = None;
        self.trama.append(
            AgentEvent::new(&self.lane, Kind::SessionEnded, Confidence::Exact)
                .detail("app-server encerrou"),
        );
        Ok(())
    }

    async fn on_message(&self, m: serde_json::Value) {
        let method = m.get("method").and_then(|x| x.as_str()).unwrap_or("");
        let has_id = m.get("id").is_some();

        // ServerRequest: o agente perguntando. Isto é o que substitui `tmux send-keys y`.
        if has_id && !method.is_empty() {
            let id = m["id"].to_string();
            if is_approval(method) {
                let (tx, rx) = oneshot::channel();
                self.pending.lock().await.insert(id.clone(), (method.to_string(), tx));

                let mut e = AgentEvent::new(&self.lane, Kind::AwaitingApproval, Confidence::Exact);
                e.approval_id = Some(id.clone());
                e.approval_method = Some(method.to_string());
                // `.map(to_string)` num JSON null produzia a string "null" no card — um detalhe
                // que MENTE dizendo que há evidência. Ausente é ausente.
                e.detail = m
                    .get("params")
                    .and_then(|p| p.get("reason").or_else(|| p.get("command")))
                    .filter(|v| !v.is_null())
                    .map(|v| v.to_string());
                self.trama.append(e);

                // Espera o operador. Se ele responder pelo próprio terminal, o Codex segue e
                // esta requisição simplesmente nunca é respondida por nós — o que é correto.
                let stdin = self.stdin.clone();
                let (lane, meth) = (self.lane.clone(), method.to_string());
                let trama = self.trama.clone();
                let raw_id = m["id"].clone();
                tokio::spawn(async move {
                    if let Ok(verdict) = rx.await {
                        let reply = serde_json::json!({"jsonrpc":"2.0","id":raw_id,"result":verdict});
                        if let Some(w) = stdin.lock().await.as_mut() {
                            let _ = w.write_all(format!("{reply}\n").as_bytes()).await;
                            let _ = w.flush().await;
                        }
                        let mut done = AgentEvent::new(&lane, Kind::ApprovalAnswered, Confidence::Exact);
                        done.approval_method = Some(meth);
                        trama.append(done);
                    }
                });
            } else {
                // Requisição que não sabemos responder: responder VAZIO e seguir. Ignorar
                // deixaria o agente pendurado para sempre esperando um id que nunca volta.
                self.send(serde_json::json!({"jsonrpc":"2.0","id":m["id"],"result":{}})).await;
            }
            return;
        }

        // Resposta a thread/start: guarda o id da thread.
        if !has_id && method.is_empty() {
            return;
        }
        if method.is_empty() {
            // 🚨 Resposta JSON-RPC. A versão anterior só procurava `result.threadId` e descartava
            // o resto — então um `error` a um `turn/start` sumia SEM DEIXAR RASTRO, e o board
            // ficava eternamente em `session_started` sem ninguém poder dizer o motivo.
            // Um supervisor que não sabe dizer por que falhou não é supervisor.
            if let Some(e) = m.get("error") {
                let msg = e.get("message").and_then(|x| x.as_str()).map(str::to_string)
                    .unwrap_or_else(|| e.to_string());
                self.trama.append(
                    AgentEvent::new(&self.lane, Kind::Error, Confidence::Exact)
                        .detail(format!("rpc id={} recusado: {}", m.get("id").unwrap_or(&serde_json::Value::Null), msg)),
                );
                // Retomar uma thread que o store não tem mais (CODEX_HOME trocado, store limpo,
                // versão nova do CLI) é o caso normal de um id vindo do diário de ONTEM.
                // Esquecê-lo é obrigatório: mantido, TODO `turn/start` seguinte falharia contra
                // um id morto, para sempre — a lane ficaria supervisionada e muda.
                if e_falha_de_resume(&m) {
                    *self.thread.lock().await = None;
                    self.trama.append(
                        AgentEvent::new(&self.lane, Kind::Error, Confidence::Exact)
                            .detail("thread anotada não existe mais no store; o próximo turno abre uma nova"),
                    );
                }
                return;
            }
            if let Some(t) = m.get("result").and_then(thread_id) {
                *self.thread.lock().await = Some(t);
            }
            return;
        }

        // ServerNotification
        if !method.is_empty() {
            let p = m.get("params").unwrap_or(&serde_json::Value::Null);
            if method == "thread/started" {
                if let Some(t) = thread_id(p) {
                    *self.thread.lock().await = Some(t);
                }
            }
            if let Some(e) = from_codex_notification(&self.lane, method, p) {
                self.trama.append(e);
            }
        }
    }

    /// Manda um pedido à lane: abre thread se ainda não há, e inicia um turno.
    /// É o mínimo para o operador dirigir a lane sem terminal — e para testar o resto.
    /// Não bloqueia o request HTTP: `thread/start` responde de forma assíncrona, e esperar por
    /// ele dentro do handler fazia o cliente estourar o timeout — e o axum descarta o future de
    /// um cliente que desconectou, então o `turn/start` NUNCA era enviado. O turno morria antes
    /// de nascer e o board não tinha como saber por quê. Agora o trabalho vai para uma task.
    pub async fn prompt(self: &Arc<Self>, text: &str) -> Result<(), String> {
        let this = self.clone();
        let text = text.to_string();
        tokio::spawn(async move {
            if let Err(e) = this.prompt_inner(&text).await {
                this.trama.append(
                    AgentEvent::new(&this.lane, Kind::Error, Confidence::Exact)
                        .detail(format!("prompt falhou: {e}")),
                );
            }
        });
        Ok(())
    }

    async fn prompt_inner(&self, text: &str) -> Result<String, String> {
        let tid = {
            let g = self.thread.lock().await;
            g.clone()
        };
        let tid = match tid {
            Some(t) => t,
            None => {
                // thread/start é síncrono para nós: sem o id não há a quem falar. Como o
                // resultado chega assíncrono como resposta JSON-RPC, esperamos pelo evento
                // `session_started` que a própria notificação `thread/started` produz.
                self.send(serde_json::json!({
                    "jsonrpc":"2.0","id":900,"method":"thread/start","params":{"cwd": self.cwd}
                })).await;
                let deadline = std::time::Instant::now() + std::time::Duration::from_secs(20);
                loop {
                    if let Some(t) = self.thread.lock().await.clone() { break t; }
                    if std::time::Instant::now() > deadline {
                        return Err("thread/start não respondeu em 20s".into());
                    }
                    tokio::time::sleep(std::time::Duration::from_millis(100)).await;
                }
            }
        };
        self.send(serde_json::json!({
            "jsonrpc":"2.0","id":901,"method":"turn/start",
            "params":{"threadId": tid, "input":[{"type":"text","text": text}]}
        })).await;
        Ok(tid)
    }

    /// Responde uma aprovação pendente com o enum CERTO para aquela família.
    pub async fn answer(&self, approval_id: &str, allow: bool) -> Result<(), String> {
        let Some((method, tx)) = self.pending.lock().await.remove(approval_id) else {
            return Err(format!("nenhuma aprovação pendente com id {approval_id}"));
        };
        tx.send(codex_approval_reply(&method, allow))
            .map_err(|_| "a lane fechou antes de receber o veredito".to_string())
    }

    async fn send(&self, v: serde_json::Value) {
        if let Some(w) = self.stdin.lock().await.as_mut() {
            let _ = w.write_all(format!("{v}\n").as_bytes()).await;
            let _ = w.flush().await;
        }
    }

    /// A thread que esta lane conhece agora. Só o teste pergunta — o resto do mundo lê
    /// `session` no `/v2/state`, que sai da mesma redução.
    #[cfg(test)]
    pub async fn thread_atual(&self) -> Option<String> {
        self.thread.lock().await.clone()
    }
}

/// A resposta ao NOSSO `thread/resume` veio como erro?
///
/// Função separada porque é a condição que decide se esquecemos o id da thread, e isso precisa
/// ser testável sem subir um app-server. Casa pelo id fixo: um erro de `turn/start` (901) NÃO
/// significa que a thread sumiu, e tratá-lo assim jogaria fora uma sessão viva.
fn e_falha_de_resume(m: &serde_json::Value) -> bool {
    m.get("error").is_some() && m.get("id").and_then(|v| v.as_i64()) == Some(ID_RESUME)
}

fn is_approval(method: &str) -> bool {
    matches!(
        method,
        "item/commandExecution/requestApproval"
            | "item/fileChange/requestApproval"
            | "item/permissions/requestApproval"
            | "execCommandApproval"
            | "applyPatchApproval"
    )
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn so_as_familias_de_aprovacao_sao_tratadas_como_pergunta() {
        assert!(is_approval("item/fileChange/requestApproval"));
        assert!(is_approval("execCommandApproval"));
        // Estas são requisições do agente, mas não perguntas ao operador — respondem vazio.
        assert!(!is_approval("item/tool/call"));
        assert!(!is_approval("account/chatgptAuthTokens/refresh"));
        assert!(!is_approval("attestation/generate"));
    }

    #[test]
    fn so_o_erro_do_proprio_resume_faz_esquecer_a_thread() {
        assert!(e_falha_de_resume(
            &serde_json::json!({"jsonrpc":"2.0","id":2,"error":{"code":-32602,"message":"unknown thread"}})
        ));
        // Um turno que falhou (rede, modelo, sandbox) não é prova de que a thread sumiu.
        assert!(!e_falha_de_resume(
            &serde_json::json!({"jsonrpc":"2.0","id":901,"error":{"message":"stream error"}})
        ));
        // Resume que deu certo, obviamente, não apaga nada.
        assert!(!e_falha_de_resume(&serde_json::json!({"jsonrpc":"2.0","id":2,"result":{}})));
    }

    #[tokio::test]
    async fn a_lane_nasce_conhecendo_a_thread_que_a_trama_guardou() {
        // O correlato do ACHADO 3: numa subida FRIA o id morava só em memória, então a lane
        // abria sessão NOVA. Aqui a lane é construída a partir de uma trama que já sabe o id.
        let p = std::env::temp_dir().join("loomd-test-lane-fria.jsonl");
        let _ = std::fs::remove_file(&p);
        {
            let t = Trama::open(&p);
            let mut e = AgentEvent::new("loom-1", Kind::SessionStarted, Confidence::Exact);
            e.session = Some("019fe704-f858-7de2-ba18-e69a6f2e6246".into());
            t.append(e);
        }
        // Daemon NOVO sobre o mesmo diário — é isto que um restart é.
        let trama = Arc::new(Trama::open(&p));
        // `/bin/true` no lugar do codex: aqui se mede o que a lane SABE ao nascer, não o
        // protocolo. Medir com o codex real misturaria a pergunta com a rede e o login dele.
        let l = CodexLane::spawn("loom-1", "/bin/true", "/tmp", vec![], trama);
        assert_eq!(
            l.thread_atual().await.as_deref(),
            Some("019fe704-f858-7de2-ba18-e69a6f2e6246")
        );

        // E uma lane sem passado no diário nasce sem thread — não se inventa id.
        let virgem = CodexLane::spawn("lane-nova", "/bin/true", "/tmp", vec![], Arc::new(Trama::open(&p)));
        assert_eq!(virgem.thread_atual().await, None);
    }
}
